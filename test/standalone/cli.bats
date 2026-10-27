#!/usr/bin/env bats
# Starting the standalone script, its options, and the checks it makes
# before doing anything.
#
# The code passed to in_script is zsh, expanded by zsh:
# shellcheck disable=SC2016

setup() {
    load helper
    standalone_setup
}

teardown() {
    common_teardown
}

@test "the script parses" {
    run -0 "$ZSH_BIN" -n "$SCRIPT"
}

@test "the script is executable" {
    assert [ -x "$SCRIPT" ]
}

@test "started with bash, it runs again under zsh" {
    ln -s "$ZSH_BIN" "$STUBS/zsh"
    run -0 bash "$SCRIPT" --version
    assert_output 'setup-yt-dlp-standalone 0.0.0-dev'
}

@test "--help shows usage on stdout" {
    run -0 --separate-stderr setup_script --help
    assert_line --index 0 'Usage: setup-yt-dlp-standalone.zsh [options]'
    assert_line '  -U, --update     Also update them to the latest versions'
    assert_stderr ''
}

@test "the short options are the same as the long ones" {
    run -0 setup_script --help
    local expected=$output
    run -0 setup_script -h
    assert_output "$expected"
    run -0 setup_script -V
    assert_output 'setup-yt-dlp-standalone 0.0.0-dev'
}

@test "--help wins over other options" {
    run -0 setup_script --update --help
    assert_line --index 0 'Usage: setup-yt-dlp-standalone.zsh [options]'
}

@test "an unknown option is a usage error" {
    run -2 --separate-stderr setup_script --bogus
    assert_output ''
    assert_stderr "error: unknown option '--bogus'
Run 'setup-yt-dlp-standalone.zsh --help' to see the options."
    run -2 --separate-stderr setup_script -U -n -x
    assert_stderr_line --index 0 "error: unknown option '-x'"
}

@test "an option given a value is a usage error" {
    run -2 --separate-stderr setup_script --update=yes
    assert_stderr_line --index 0 "error: option '--update' doesn't take a value"
}

@test "an argument is a usage error" {
    run -2 --separate-stderr setup_script -U something
    assert_stderr_line --index 0 "error: unexpected argument 'something'"
}

@test "the options are read into opts" {
    run -0 in_script 'cli_parse --update -n --verbose --no-color; print -r -- ${(kv)opts}'
    assert_output --partial 'action update'
    assert_output --partial 'dry_run 1'
    assert_output --partial 'verbose 1'
    assert_output --partial 'color never'
}

@test "usage errors respect --no-color" {
    run -2 in_tty "$ZSH_BIN" "$SCRIPT" --no-color --bogus
    assert_output --partial "error: unknown option '--bogus'"
    refute_output --partial $'\e['
}

@test "it stops when the macOS tools aren't there" {
    rm "$STUBS/sw_vers"
    run -1 --separate-stderr env PATH="$STUBS" "$ZSH_BIN" "$SCRIPT"
    assert_stderr 'error: this script only works on macOS'
}

@test "it warns on macOS older than 10.15" {
    macos 10.14.6
    run -0 --separate-stderr in_script preflight
    assert_stderr 'warning: macOS 10.14.6 is older than macOS 10.15, the oldest version this script supports'
}

@test "it doesn't warn on macOS 10.15 or later" {
    local version
    for version in 10.15 10.15.7 11.7.10 12.0 26.1; do
        macos $version
        run -0 --separate-stderr in_script preflight
        assert_stderr ''
    done
}

@test "it tells Apple silicon from Intel" {
    run -0 in_script 'preflight; print -r -- $mac_arch'
    assert_output amd64
    apple_silicon
    run -0 in_script 'preflight; print -r -- $mac_arch'
    assert_output arm64
}

@test "ffmpeg comes from martin-riedl.de on macOS 12, and evermeet.cx on older Intel Macs" {
    run -0 in_script 'preflight; tool_source ffmpeg; tool_source yt-dlp_macos'
    assert_output 'riedl
ytdlp'
    macos 10.15.7
    run -0 in_script 'preflight; tool_source ffmpeg'
    assert_output evermeet
    apple_silicon
    macos 11.7.10
    run -0 in_script 'preflight; tool_source ffmpeg'
    assert_output ''
}
