#!/usr/bin/env bats
# Uninstalling, and what a second run offers.
#
# The code passed to in_script is zsh, expanded by zsh:
# shellcheck disable=SC2016

setup() {
    load test_helper/common
    common_setup
    STATE=$HOME/Library/Application\ Support/yt-dlp-setup/state
}

teardown() {
    common_teardown
}

# answer INPUT ARGS...: run the script with ARGS on a terminal, typing INPUT.
# TERM=dumb leaves out the colors and the spinner.
answer() {
    set -o pipefail
    # shellcheck disable=SC2059  # INPUT is a printf format, for \n
    printf "$1" | in_tty env TERM=dumb "$ZSH_BIN" "$SCRIPT" "${@:2}" | tr -d '\r'
}

# installed brew|port|pip: print what the fake manager has installed.
installed() {
    ls "$FAKE_STATE/$1"
}

# uninstalls: print the uninstall commands the fakes ran.
uninstalls() {
    grep -E '^(brew uninstall|sudo -n port -N uninstall|python3 -m pip uninstall)' "$FAKE_STATE/calls"
}

@test "with nothing installed by the script, there's nothing to uninstall" {
    run -0 setup_script --uninstall
    assert_line "Nothing to uninstall: setup-yt-dlp hasn't installed anything for you."
}

@test "a state file with nothing to uninstall is removed" {
    mkdir -p "${STATE%/*}"
    printf 'format=1\nmanager=homebrew\n' >"$STATE"
    run -0 setup_script --uninstall
    assert [ ! -e "$STATE" ]
}

@test "Homebrew: uninstalling removes what was installed, and only that" {
    use_fake homebrew
    fake_installed brew ffmpeg 7.1_4
    fake_installed pip six
    run -0 setup_script
    : >"$FAKE_STATE/calls"
    run -0 setup_script --uninstall --yes
    assert_line '  ✓ ~/.zshrc           deleted, as setup-yt-dlp created it'
    assert_line '  ✓ yt-dlp             uninstalled'
    assert_line --regexp '^✓ Done in [0-9]+s\. Everything setup-yt-dlp installed is removed\.$'
    run -0 installed brew
    assert_output ffmpeg
    run -0 installed pip
    assert_output six
    assert [ ! -e "$HOME/.zshrc" ]
    assert [ ! -e "$STATE" ]
    run -0 uninstalls
    assert_output "python3 -m pip uninstall --yes --break-system-packages yt-dlp-ejs
python3 -m pip uninstall --yes --break-system-packages websockets
python3 -m pip uninstall --yes --break-system-packages urllib3
python3 -m pip uninstall --yes --break-system-packages requests
python3 -m pip uninstall --yes --break-system-packages pycryptodomex
python3 -m pip uninstall --yes --break-system-packages mutagen
python3 -m pip uninstall --yes --break-system-packages curl-cffi
python3 -m pip uninstall --yes --break-system-packages certifi
brew uninstall --formula yt-dlp
brew uninstall --formula deno
brew uninstall --formula python3
brew uninstall --formula atomicparsley
brew uninstall --formula bash"
}

@test "the plan says what will go, before asking" {
    use_fake homebrew
    run -0 setup_script
    run -0 answer 'n\n' --uninstall
    assert_output --partial "This removes what setup-yt-dlp installed with Homebrew:
  Packages         yt-dlp, deno, python3, atomicparsley, ffmpeg, bash
  Python packages  yt-dlp-ejs, websockets, urllib3, requests, pycryptodomex, mutagen, curl-cffi, certifi
  Dependencies     2 that came with them, unless something else needs them
  Settings         the setup-yt-dlp lines in ~/.zshrc
Uninstall these? [y/N] "
}

@test "answering no, or just Enter, changes nothing" {
    use_fake homebrew
    run -0 setup_script
    cp "$STATE" "$BATS_TEST_TMPDIR/state-before"
    local reply
    for reply in 'n\n' '\n'; do
        run -0 answer "$reply" --uninstall
        assert_output --partial 'Nothing was changed.'
    done
    run -1 uninstalls
    diff -u "$BATS_TEST_TMPDIR/state-before" "$STATE"
}

@test "without a terminal, uninstalling needs --yes" {
    use_fake homebrew
    run -0 setup_script
    run -1 --separate-stderr setup_script --uninstall
    assert_stderr 'error: uninstalling needs a yes; run with --yes to go ahead without a terminal'
    run -1 uninstalls
}

@test "dependencies nothing else needs go, and the rest stay" {
    use_fake homebrew
    run -0 setup_script
    # Something the user installs afterwards needs one of ffmpeg's.
    fake_installed brew mpv
    fake_needs brew mpv x265
    run -0 setup_script --uninstall --yes
    assert_line '  ✓ dependencies       1 uninstalled'
    assert_line '    libvpx'
    assert_line '  – dependencies       kept 1 that something else needs'
    run -0 installed brew
    assert_output 'mpv
x265'
    assert [ ! -e "$STATE" ]
}

@test "a dependency that was there before isn't touched" {
    use_fake homebrew
    mkdir -p "$FAKE_STATE/brew"
    echo 1.0 >"$FAKE_STATE/brew/x265"
    run -0 setup_script
    run -0 setup_script --uninstall --yes
    run -0 installed brew
    assert_output x265
}

@test "a Python package something else needs is kept" {
    use_fake homebrew
    run -0 setup_script
    fake_installed pip httpx
    fake_needs pip httpx certifi
    run -0 setup_script --uninstall --yes
    assert_line '  – certifi            kept: httpx needs it'
    run -0 installed pip
    assert_output 'certifi
httpx'
}

@test "pip names compare the way pip compares them" {
    run -0 in_script 'pip_names curl_cffi Yt.DLP__ejs websockets'
    assert_output 'curl-cffi
yt-dlp-ejs
websockets'
}

@test "a package that won't uninstall is reported and stays recorded" {
    use_fake homebrew
    run -0 setup_script
    fake_fails deno
    run -1 setup_script --uninstall --yes
    assert_line '  ✗ deno               failed'
    assert_output --regexp "
✗ Finished in [0-9]+s, with problems:
    deno couldn't be uninstalled
  The log has the details: ~/Library/Logs/yt-dlp-setup/[0-9-]+\.log
  Run with --uninstall again to retry\.$"
    run -0 grep -v -e '^#' -e '^format=' "$STATE"
    assert_output 'manager=homebrew
package=deno'
}

@test "a package removed by hand is skipped" {
    use_fake homebrew
    run -0 setup_script
    rm "$FAKE_STATE/brew/yt-dlp"
    run -0 setup_script --uninstall --yes
    assert_line '  ✓ yt-dlp             already uninstalled'
}

@test "a ~/.zshrc that was there keeps everything but the setup-yt-dlp lines" {
    use_fake homebrew
    printf 'alias ll="ls -l"\n' >"$HOME/.zshrc"
    run -0 setup_script
    run -0 setup_script --uninstall --yes
    refute_line --partial 'deleted, as setup-yt-dlp created it'
    printf 'alias ll="ls -l"\n' | diff -u - "$HOME/.zshrc"
}

@test "a ~/.zshrc the script created stays if something else was added to it" {
    use_fake homebrew
    run -0 setup_script
    printf 'alias ll="ls -l"\n' >>"$HOME/.zshrc"
    run -0 setup_script --uninstall --yes
    refute_line --partial 'deleted'
    printf 'alias ll="ls -l"\n' | diff -u - "$HOME/.zshrc"
}

@test "MacPorts: uninstalling puts port select back and clears dependencies" {
    use_fake macports
    mkdir -p "$FAKE_STATE/select"
    echo python313 >"$FAKE_STATE/select/python3"
    run -0 setup_script
    run -0 setup_script --uninstall --yes
    assert_line '  ✓ python3            back to python313'
    assert_line '  ✓ pip                back to none'
    assert_line '    py314-pip'
    assert_line '    python314'
    run -0 installed port
    assert_output ''
    run -0 cat "$FAKE_STATE/select/python3" "$FAKE_STATE/select/pip"
    assert_output 'python313
none'
    assert [ ! -e "$STATE" ]
}

@test "--dry-run uninstalling changes nothing" {
    use_fake homebrew
    run -0 setup_script
    cp "$STATE" "$BATS_TEST_TMPDIR/state-before"
    : >"$FAKE_STATE/calls"
    run -0 setup_script --uninstall --dry-run
    assert_line '  – yt-dlp             would run: brew uninstall --formula yt-dlp'
    assert_line '  – ~/.zshrc           would have the setup-yt-dlp lines removed'
    assert_line '  – ~/.zshrc           would be deleted, as setup-yt-dlp created it'
    assert_line 'Dry run finished. Nothing was changed.'
    run -1 uninstalls
    diff -u "$BATS_TEST_TMPDIR/state-before" "$STATE"
    assert [ -e "$HOME/.zshrc" ]
}

@test "--manager has to match the one that was used" {
    use_fake homebrew
    use_fake macports
    run -0 setup_script --manager homebrew
    run -1 --separate-stderr setup_script --uninstall --manager macports
    assert_stderr 'error: yt-dlp was set up with Homebrew; run with --uninstall first to switch to MacPorts'
}

@test "run again, it asks what to do, and Enter repairs" {
    use_fake homebrew
    run -0 setup_script
    rm "$FAKE_STATE/brew/deno"
    run -0 answer '\n'
    assert_output --partial 'yt-dlp 1.0 is set up already. What do you want to do?
  1) Repair: install anything that'\''s missing
  2) Uninstall
  3) Quit
Choose 1-3 [1]: '
    assert_line '  ✓ deno               installed'
}

@test "run again with yt-dlp gone, it says so" {
    use_fake homebrew
    run -0 setup_script
    rm "$FAKE_STATE/brew/yt-dlp"
    run -0 answer '3\n'
    assert_line "setup-yt-dlp has run here before, but yt-dlp is missing. What do you want to do?"
}

@test "run again, choosing Uninstall uninstalls" {
    use_fake homebrew
    run -0 setup_script
    run -0 answer '2\ny\n'
    assert_line --partial 'This removes what setup-yt-dlp installed with Homebrew:'
    assert_line '  ✓ yt-dlp             uninstalled'
    assert [ ! -e "$STATE" ]
}

@test "run again, choosing Quit changes nothing" {
    use_fake homebrew
    run -0 setup_script
    : >"$FAKE_STATE/calls"
    run -0 answer '3\n'
    refute_line --partial '▸ Packages'
    run -1 grep -E 'install' "$FAKE_STATE/calls"
}

@test "run again with --yes, or without a terminal, it repairs without asking" {
    use_fake homebrew
    run -0 setup_script
    run -0 setup_script --yes
    refute_output --partial 'What do you want to do?'
    assert_line '  ✓ deno               already installed (1.0)'
    run -0 setup_script
    refute_output --partial 'What do you want to do?'
}
