#!/usr/bin/env bats
# Step output, running commands, the log, and administrator access.
#
# The code passed to in_script is zsh, expanded by zsh:
# shellcheck disable=SC2016

setup() {
    load test_helper/common
    common_setup
    LOGS=$HOME/Library/Logs/yt-dlp-setup
}

teardown() {
    common_teardown
}

# A sudo that logs its arguments to $SUDO_LOG. `sudo -n` exits with
# $SUDO_CACHED (0: still has access), anything else with $SUDO_STATUS.
stub_sudo() {
    export SUDO_LOG=$BATS_TEST_TMPDIR/sudo.log SUDO_CACHED=${1:-0} SUDO_STATUS=${2:-0}
    stub sudo 'echo "$*" >>"$SUDO_LOG"; [[ $1 == -n ]] && exit "$SUDO_CACHED"; exit "$SUDO_STATUS"'
}

# ctrl_c_after SECONDS CODE: in_script_tty CODE, pressing Ctrl-C after SECONDS.
ctrl_c_after() {
    { sleep "$1"; printf '\003'; } | in_script_tty "$2"
}

@test "step lines line up their subjects" {
    run -0 in_script 'ui_init; ui_ok bash "already installed"; ui_fail atomicparsley failed; ui_skip py-pycryptodomex skipped'
    assert_output "  ✓ bash               already installed
  ✗ atomicparsley      failed
  – py-pycryptodomex   skipped"
}

@test "ASCII symbols outside a UTF-8 locale" {
    export LC_ALL=C
    run -0 in_script 'ui_init; ui_section Packages; ui_ok bash "already installed"; ui_fail deno failed'
    assert_output "
> Packages
  + bash               already installed
  x deno               failed"
}

@test "LC_CTYPE=UTF-8 counts as a UTF-8 locale" {
    unset LANG
    export LC_CTYPE=UTF-8
    run -0 in_script 'ui_init; ui_ok bash "already installed"'
    assert_output '  ✓ bash               already installed'
}

@test "durations read as seconds, or minutes and seconds" {
    run -0 in_script 'ui_duration 0; ui_duration 59.9; ui_duration 60; ui_duration 125'
    assert_output '0s
59s
1m 0s
2m 5s'
}

@test "a step that succeeds" {
    run -0 in_script 'ui_init; run_step ffmpeg installing installed -- touch "$HOME/ran"'
    assert_output '  ✓ ffmpeg             installed'
    assert [ -e "$HOME/ran" ]
}

@test "a slow step shows how long it took" {
    run -0 in_script 'ui_init; run_step ffmpeg installing installed -- sleep 1.1'
    assert_output --regexp '^  ✓ ffmpeg             installed \([0-9]+s\)$'
}

@test "a step that fails shows the end of its output" {
    run -3 in_script 'ui_init; run_step deno installing installed -- sh -c '\''for i in $(seq 1 14); do echo "line $i"; done; echo "Error: no bottle" >&2; exit 3'\'
    assert_line --index 0 '  ✗ deno               failed'
    refute_line '    line 5'
    assert_line --index 1 '    line 6'
    assert_line --index 10 '    Error: no bottle'
    assert_equal "${#lines[@]}" 11
}

@test "a failed step's output keeps the last draw of progress lines" {
    run -1 in_script 'ui_init; run_step deno installing installed -- sh -c '\''printf "10%%\r50%%\r100%%\n\n   \nError\n"; exit 1'\'
    assert_output '  ✗ deno               failed
    100%
    Error'
}

@test "--verbose shows the output under the step" {
    run -0 in_script 'opts[verbose]=1; ui_init; run_step ffmpeg installing installed -- sh -c "echo one; echo two >&2"'
    assert_output '  ▸ ffmpeg             installing…
    │ one
    │ two
  ✓ ffmpeg             installed'
}

@test "--verbose doesn't repeat the output after a failure" {
    run -1 in_script 'opts[verbose]=1; ui_init; run_step deno installing installed -- sh -c "echo oops; exit 1"'
    assert_line --index 1 '    │ oops'
    assert_line --index 2 '  ✗ deno               failed'
    assert_equal "${#lines[@]}" 3
}

@test "--dry-run shows the command without running it" {
    run -0 in_script 'opts[dry_run]=1; ui_init; run_step ffmpeg installing installed -- touch "$HOME/two words"'
    assert_output "  – ffmpeg             would run: touch '$HOME/two words'"
    assert [ ! -e "$HOME/two words" ]
    assert [ ! -e "$LOGS" ]
}

@test "--dry-run says so in the header" {
    run -0 in_script 'opts[dry_run]=1; ui_init; ui_header'
    assert_output --regexp '^yt-dlp setup [0-9A-Za-z.-]+ \(dry run: nothing will be changed\)$'
}

@test "the log has each command, its output and its status" {
    run -1 in_script 'setup_args=(-v --manager "two words"); run_step a doing done -- echo hello; run_step b doing done -- sh -c "echo bye; exit 1"'
    run -0 sed -E -e 's/^(yt-dlp setup) [0-9A-Za-z.-]+,/\1 V,/' -e 's/^==> \[[0-9:]{8}\]/==> [T]/' "$LOGS"/*.log
    assert_output "yt-dlp setup V, arguments: -v --manager 'two words'
==> [T] echo hello
hello
==> exit status 0 after 0s
==> [T] sh -c 'echo bye; exit 1'
bye
==> exit status 1 after 0s"
}

@test "only the ten newest logs are kept" {
    mkdir -p "$LOGS"
    local i
    for i in 01 02 03 04 05 06 07 08 09 10 11 12; do
        touch -t "2026010100$i" "$LOGS/old-$i.log"
    done
    run -0 in_script 'run_step a doing done -- true'
    run -0 ls "$LOGS"
    assert_equal "${#lines[@]}" 10
    refute_line old-03.log
    assert_line old-04.log
    assert_line old-12.log
}

@test "no spinner when the output isn't a terminal" {
    run -0 in_script 'ui_init; run_step ffmpeg installing installed -- sleep 0.3'
    refute_output --partial $'\r'
}

@test "a spinner runs while a step does, on a terminal" {
    run -0 in_script_tty 'ui_init; run_step ffmpeg installing installed -- sleep 0.3'
    assert_output --partial $'\e[?25l\r  \e[34m⠋\e[0m ffmpeg             installing…'
    assert_output --partial $'\r\e[K\e[?25h  \e[32m✓\e[0m ffmpeg             installed'
}

@test "no spinner on a dumb terminal" {
    export TERM=dumb
    run -0 in_script_tty 'ui_init; run_step ffmpeg installing installed -- sleep 0.3'
    refute_output --partial '⠋'
    assert_output --partial '  ✓ ffmpeg             installed'
}

@test "Ctrl-C stops the step, the spinner and the script" {
    local marker=leak-check-$BATS_TEST_NUMBER-$$
    run -130 ctrl_c_after 1.5 ": $marker; ui_init; run_step deno installing installed -- sleep 30; print not reached"
    assert_output --partial $'\r\e[K\e[?25h\e[31merror:\e[0m interrupted'
    refute_output --partial 'not reached'
    run -1 pgrep -f "$marker"
    run -0 ls "$LOGS"
    assert_output --regexp '^[0-9]{8}-[0-9]{6}\.log$'
}

@test "administrator access that's still cached isn't asked for again" {
    stub_sudo 0
    run -0 in_script 'sudo_begin "MacPorts needs administrator access."'
    assert_output ''
    run -0 cat "$SUDO_LOG"
    assert_line --index 0 '-n -v'
    refute_line '-k'
}

@test "administrator access is asked for once, then dropped at exit" {
    stub_sudo 1 0
    run -0 in_script 'sudo_begin "MacPorts needs administrator access."; sudo_begin "again"'
    assert_output 'MacPorts needs administrator access.'
    run -0 cat "$SUDO_LOG"
    assert_line --index 0 '-n -v'
    assert_line --index 1 '-v -p Password for %u: '
    assert_line '-k'
}

@test "the script stops without administrator access" {
    stub_sudo 1 1
    run -1 --separate-stderr in_script 'sudo_begin "MacPorts needs administrator access."; print not reached'
    assert_output 'MacPorts needs administrator access.'
    assert_stderr "error: couldn't get administrator access"
}

@test "--dry-run doesn't ask for administrator access" {
    stub_sudo 1 1
    run -0 in_script 'opts[dry_run]=1; sudo_begin "MacPorts needs administrator access."'
    assert_output ''
    assert [ ! -e "$SUDO_LOG" ]
}

@test "paths show ~ for the home folder, and spaces as they are" {
    run -0 in_script 'ui_path "$HOME/Library/Application Support/x"; ui_path $HOME; ui_path ${HOME}2/x; ui_path /tmp/a'
    # shellcheck disable=SC2088  # a ~ the script printed
    assert_output "~/Library/Application Support/x
~
$HOME"'2/x
/tmp/a'
}
