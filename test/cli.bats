#!/usr/bin/env bats
# Command-line parsing, --help and --version.
#
# The code passed to in_script is zsh, expanded by zsh:
# shellcheck disable=SC2016

setup() {
    load test_helper/common
    common_setup
}

teardown() {
    common_teardown
}

@test "--help shows usage on stdout" {
    run -0 --separate-stderr setup_script --help
    assert_line --index 0 'Usage: setup-yt-dlp.zsh [options]'
    assert_line '  -m, --manager <name>  Package manager to use: homebrew or macports'
    assert_stderr ''
}

@test "-h is the same as --help" {
    run -0 setup_script --help
    local expected=$output
    run -0 setup_script -h
    assert_output "$expected"
}

@test "--help wins over other options" {
    run -0 setup_script --uninstall --help
    assert_line --index 0 'Usage: setup-yt-dlp.zsh [options]'
}

@test "--version shows the version, which is 0.0.0-dev outside a release" {
    run -0 setup_script --version
    assert_output 'setup-yt-dlp 0.0.0-dev'
}

@test "-V is the same as --version" {
    run -0 setup_script --version
    local expected=$output
    run -0 setup_script -V
    assert_output "$expected"
}

@test "an unknown long option is a usage error" {
    run -2 --separate-stderr setup_script --bogus
    assert_output ''
    assert_stderr "error: unknown option '--bogus'
Run 'setup-yt-dlp.zsh --help' to see the options."
}

@test "an unknown short option is a usage error" {
    run -2 --separate-stderr setup_script -x
    assert_stderr_line --index 0 "error: unknown option '-x'"
}

@test "the unknown option is named when valid ones come first" {
    run -2 --separate-stderr setup_script -y --bogus -v
    assert_stderr_line --index 0 "error: unknown option '--bogus'"
}

@test "the unknown option is named when it follows an option's value" {
    run -2 --separate-stderr setup_script --manager brew -y --bogus
    assert_stderr_line --index 0 "error: unknown option '--bogus'"
}

@test "an unknown letter in combined short options is a usage error" {
    run -2 --separate-stderr setup_script -yq
    assert_stderr_line --index 0 "error: unknown option '-yq'"
}

@test "--manager needs a value" {
    run -2 --separate-stderr setup_script --manager
    assert_stderr_line --index 0 "error: option '--manager' needs a value"
}

@test "-m needs a value" {
    run -2 --separate-stderr setup_script -m
    assert_stderr_line --index 0 "error: option '-m' needs a value"
}

@test "--manager= with nothing after it needs a value" {
    run -2 --separate-stderr setup_script --manager=
    assert_stderr_line --index 0 "error: option '--manager' needs a value"
}

@test "flags don't take values" {
    run -2 --separate-stderr setup_script --yes=1
    assert_stderr_line --index 0 "error: option '--yes' doesn't take a value"
}

@test "an unknown package manager is a usage error" {
    run -2 --separate-stderr setup_script --manager apt
    assert_stderr_line --index 0 "error: unknown package manager 'apt'; use homebrew or macports"
}

@test "arguments that aren't options are a usage error" {
    run -2 --separate-stderr setup_script install
    assert_stderr_line --index 0 "error: unexpected argument 'install'"
}

@test "words after -- aren't options" {
    run -2 --separate-stderr setup_script -- --help
    assert_stderr_line --index 0 "error: unexpected argument '--help'"
}

@test "--uninstall and --status can't be combined" {
    run -2 --separate-stderr setup_script --uninstall --status
    assert_stderr_line --index 0 "error: --uninstall and --status can't be used together"
}

@test "--downloader can't be combined with --uninstall or --status" {
    run -2 --separate-stderr setup_script --downloader --uninstall
    assert_stderr_line --index 0 "error: --uninstall and --downloader can't be used together"
    run -2 --separate-stderr setup_script -s -d
    assert_stderr_line --index 0 "error: --status and --downloader can't be used together"
}

@test "--downloader takes its path from the next word, unless that's an option" {
    run -0 in_script 'cli_parse --downloader ~/Apps --yes && print -r -- $opts[action] $opts[output] $opts[yes]'
    assert_output "downloader $HOME/Apps 1"
    run -0 in_script 'cli_parse -d --yes && print -r -- $opts[action] "<$opts[output]>" $opts[yes]'
    assert_output 'downloader <> 1'
    run -0 in_script 'cli_parse --downloader=/tmp/x && print -r -- $opts[output]'
    assert_output /tmp/x
    run -2 --separate-stderr setup_script --downloader=
    assert_stderr_line --index 0 "error: option '--downloader=' needs a path after the ="
    # Without --downloader, a path is still an unexpected argument.
    run -2 --separate-stderr setup_script --yes /tmp/x
    assert_stderr_line --index 0 "error: unexpected argument '/tmp/x'"
}

@test "defaults without options" {
    run -0 in_script 'cli_parse && print -r -- $opts[action] $opts[dry_run] $opts[yes] $opts[verbose] $opts[color] "<$opts[manager]>"'
    assert_output 'install 0 0 0 auto <>'
}

@test "flags set their options" {
    run -0 in_script 'cli_parse --dry-run --yes --verbose --no-color && print -r -- $opts[dry_run] $opts[yes] $opts[verbose] $opts[color]'
    assert_output '1 1 1 never'
}

@test "short flags can be combined" {
    run -0 in_script 'cli_parse -nyv && print -r -- $opts[dry_run] $opts[yes] $opts[verbose]'
    assert_output '1 1 1'
}

@test "--uninstall and --status set the action" {
    run -0 in_script 'cli_parse -u && print -r -- $opts[action]'
    assert_output uninstall
    run -0 in_script 'cli_parse --status && print -r -- $opts[action]'
    assert_output status
}

@test "--manager takes names and aliases in any case" {
    local pair
    for pair in homebrew:homebrew brew:homebrew HomeBrew:homebrew \
        macports:macports port:macports MacPorts:macports; do
        run -0 in_script "cli_parse --manager ${pair%%:*} && print -r -- \$opts[manager]"
        assert_output "${pair#*:}"
    done
}

@test "--manager takes its value in every form" {
    local args
    for args in '-m port' '-mport' '--manager port' '--manager=port'; do
        run -0 in_script "cli_parse $args && print -r -- \$opts[manager]"
        assert_output macports
    done
}
