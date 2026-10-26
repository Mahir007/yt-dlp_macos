#!/usr/bin/env bats
# Choosing between Homebrew and MacPorts, and their package operations.
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

# answer INPUT CODE: in_script_tty CODE, typing INPUT into the terminal.
# The terminal's \r\n line endings become \n.
answer() {
    set -o pipefail
    # shellcheck disable=SC2059  # INPUT is a printf format, for \n
    printf "$1" | in_script_tty "$2" | tr -d '\r'
}

calls() {
    cat "$FAKE_STATE/calls"
}

@test "with only Homebrew installed, it's used" {
    use_fake homebrew
    run -0 in_script 'pm_select; print -r -- $opts[manager]'
    assert_output homebrew
}

@test "with only MacPorts installed, it's used" {
    use_fake macports
    run -0 in_script 'pm_select; print -r -- $opts[manager]'
    assert_output macports
}

@test "with neither installed, it says how to install one" {
    run -1 --separate-stderr setup_script
    assert_stderr --partial "error: neither Homebrew nor MacPorts is installed

Install one of them, then run this script again:
  1. Install Apple's command line tools: xcode-select --install"
    assert_stderr --partial 'https://github.com/Homebrew/brew/releases/latest'
    assert_stderr --partial 'https://github.com/macports/macports-base/releases/latest'
}

@test "--manager has to name an installed manager" {
    use_fake homebrew
    run -1 --separate-stderr in_script 'opts[manager]=macports; pm_select'
    assert_stderr "error: MacPorts isn't installed: there's no 'port' command"
}

@test "--manager picks one of two without asking" {
    use_fake homebrew
    use_fake macports
    run -0 in_script 'opts[manager]=macports; pm_select; print -r -- $opts[manager]'
    assert_output macports
}

@test "with both installed, --yes picks Homebrew" {
    use_fake homebrew
    use_fake macports
    run -0 in_script 'opts[yes]=1; pm_select; print -r -- $opts[manager]'
    assert_output homebrew
}

@test "with both installed, it asks, and Enter picks Homebrew" {
    use_fake homebrew
    use_fake macports
    run -0 answer '\n' 'pm_select; print -r -- "picked $opts[manager]"'
    assert_output --partial 'Both Homebrew and MacPorts are installed. Which one do you want to use?
  1) Homebrew (recommended)
  2) MacPorts
Choose 1-2 [1]: '
    assert_output --partial 'picked homebrew'
}

@test "with both installed, answering 2 picks MacPorts" {
    use_fake homebrew
    use_fake macports
    run -0 answer '2\n' 'pm_select; print -r -- "picked $opts[manager]"'
    assert_output --partial 'picked macports'
}

@test "an answer that isn't a choice is asked again" {
    use_fake homebrew
    use_fake macports
    run -0 answer '3\nx\n2\n' 'pm_select; print -r -- "picked $opts[manager]"'
    assert_equal "$(grep -o 'Choose 1-2 \[1\]: ' <<<"$output" | wc -l | tr -d ' ')" 3
    assert_output --partial 'picked macports'
}

@test "Ctrl-D at the question stops the script" {
    use_fake homebrew
    use_fake macports
    run -1 answer '\004' 'pm_select; print -r -- "picked $opts[manager]"'
    assert_output --partial 'error: no answer given'
    refute_output --partial picked
}

@test "when stdin isn't the terminal, it asks on the terminal" {
    use_fake homebrew
    use_fake macports
    run -0 answer '2\n' 'exec </dev/null; pm_select; print -r -- "picked $opts[manager]"'
    assert_output --partial 'Choose 1-2 [1]: '
    assert_output --partial 'picked macports'
}

@test "with both installed and no terminal, it asks for --manager" {
    use_fake homebrew
    use_fake macports
    run -1 --separate-stderr in_script 'pm_select'
    assert_stderr 'error: both Homebrew and MacPorts are installed; choose one with --manager'
}

@test "the install says which manager it uses" {
    use_fake homebrew
    run setup_script
    assert_line 'Using Homebrew 4.6.3'

    rm -r "$BATS_TEST_TMPDIR/homebrew"
    use_fake macports
    run setup_script
    assert_line 'Using MacPorts 2.10.5'
}

@test "Homebrew's environment hints and questions are turned off" {
    use_fake homebrew
    run -0 in_script 'opts[manager]=homebrew; pm_init; print -r -- $HOMEBREW_NO_ENV_HINTS $HOMEBREW_NO_ASK $pm_prefix'
    assert_output "1 1 $BATS_TEST_TMPDIR/homebrew"
}

@test "Homebrew: the version of an installed formula" {
    use_fake homebrew
    fake_installed brew ffmpeg 7.1_4
    run -0 in_script 'opts[manager]=homebrew; pm_init; pkg_version ffmpeg'
    assert_output 7.1_4
    run -1 in_script 'opts[manager]=homebrew; pm_init; pkg_version atomicparsley'
    assert_output ''
}

@test "Homebrew: python3 is found through its alias" {
    use_fake homebrew
    fake_installed brew python@3.15 3.15.1
    run -0 in_script 'opts[manager]=homebrew; pm_init; pkg_version python3'
    assert_output 3.15.1
}

@test "Homebrew: installing a formula" {
    use_fake homebrew
    run -0 in_script 'opts[manager]=homebrew; pm_init; ui_init; pkg_install deno && pkg_version deno'
    assert_output '  ✓ deno               installed
1.0'
    run -0 calls
    assert_line 'brew install --formula deno'
}

@test "Homebrew: a formula that fails to install" {
    use_fake homebrew
    fake_fails deno
    run -1 in_script 'opts[manager]=homebrew; pm_init; ui_init; pkg_install deno'
    assert_line --index 0 '  ✗ deno               failed'
    assert_line --index 1 '    Error: deno: no bottle available!'
}

@test "Homebrew: uninstalling a formula" {
    use_fake homebrew
    fake_installed brew deno
    run -0 in_script 'opts[manager]=homebrew; pm_init; ui_init; pkg_uninstall deno'
    assert_output '  ✓ deno               uninstalled'
    run -0 calls
    assert_line 'brew uninstall --formula deno'
}

@test "MacPorts: the version of the active port" {
    use_fake macports
    fake_installed port ffmpeg 9.0.2_0+gpl2
    run -0 in_script 'opts[manager]=macports; pm_init; pkg_version ffmpeg'
    assert_output 9.0.2_0
}

@test "MacPorts: an inactive port counts as not installed" {
    use_fake macports
    mkdir -p "$FAKE_STATE/port"
    echo '@9.0.2_0+gpl2' >"$FAKE_STATE/port/ffmpeg"
    run -1 in_script 'opts[manager]=macports; pm_init; pkg_version ffmpeg'
    assert_output ''
}

@test "MacPorts: installing a port uses sudo and passes variants" {
    use_fake macports
    run -0 in_script 'opts[manager]=macports; pm_init; ui_init; pkg_install yt-dlp -ffmpeg && pkg_version yt-dlp'
    assert_output '  ✓ yt-dlp             installed
1.0_0'
    run -0 calls
    assert_line 'sudo -n port -N install yt-dlp -ffmpeg'
}

@test "MacPorts: uninstalling a port" {
    use_fake macports
    fake_installed port deno
    run -0 in_script 'opts[manager]=macports; pm_init; ui_init; pkg_uninstall deno'
    assert_output '  ✓ deno               uninstalled'
    run -0 calls
    assert_line 'sudo -n port -N uninstall deno'
}

@test "MacPorts: --dry-run shows the commands and runs none" {
    use_fake macports
    run -0 in_script 'opts[manager]=macports opts[dry_run]=1; pm_init; ui_init; pkg_install ffmpeg; pkg_uninstall deno'
    assert_output '  – ffmpeg             would run: sudo -n port -N install ffmpeg
  – deno               would run: sudo -n port -N uninstall deno'
    run -0 calls
    refute_output --partial ' -N '
}

@test "pip: the version of an installed package" {
    use_fake homebrew
    fake_installed pip mutagen 1.47.0
    run -0 in_script 'opts[manager]=homebrew; pm_init; pip_version mutagen'
    assert_output 1.47.0
    run -1 in_script 'opts[manager]=homebrew; pm_init; pip_version websockets'
    assert_output ''
}

@test "pip: packages go to the user's site-packages of Homebrew's Python" {
    use_fake homebrew
    # A python3 earlier on PATH must not be the one used.
    stub python3 'echo "wrong python3" >&2; exit 1'
    run -0 in_script 'opts[manager]=homebrew; pm_init; ui_init; pip_install mutagen && pip_version mutagen'
    assert_output '  ✓ mutagen            installed
1.0'
    run -0 in_script 'opts[manager]=homebrew opts[dry_run]=1; pm_init; ui_init; pip_install mutagen'
    assert_output "  – mutagen            would run: $BATS_TEST_TMPDIR/homebrew/bin/python3 -m pip install --user --break-system-packages mutagen"
}

@test "pip: uninstalling a package" {
    use_fake homebrew
    fake_installed pip mutagen
    run -0 in_script 'opts[manager]=homebrew; pm_init; ui_init; pip_uninstall mutagen'
    assert_output '  ✓ mutagen            uninstalled'
    run -0 calls
    assert_line 'python3 -m pip uninstall --yes --break-system-packages mutagen'
}
