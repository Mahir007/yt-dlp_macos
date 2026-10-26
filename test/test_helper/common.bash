# Shared setup for the bats tests. Each test gets its own HOME and a
# directory of stub commands placed first on PATH.
#
# shellcheck shell=bash

# The zsh under test. /bin/zsh is what users run; CI on Linux installs
# zsh 5.8 there to match macOS 12.
ZSH_BIN=${TEST_ZSH:-/bin/zsh}

common_setup() {
    bats_require_minimum_version 1.5.0
    load test_helper/bats-support/load
    load test_helper/bats-assert/load

    SCRIPT=$BATS_TEST_DIRNAME/../src/setup-yt-dlp.zsh
    # Resolved before the stubs go on PATH, for in_tty.
    PYTHON=$(command -v python3)

    export HOME=$BATS_TEST_TMPDIR/home
    mkdir -p "$HOME"
    STUBS=$BATS_TEST_TMPDIR/stubs
    mkdir -p "$STUBS"
    export PATH=$STUBS:$PATH
    unset NO_COLOR ZDOTDIR
    # CI runners don't set TERM, and the script treats that like TERM=dumb.
    export TERM=xterm-256color

    stub sw_vers 'echo 12.7.6'
}

# Fail the test if zsh's warn_create_global fired during the last run: a
# function assigned to a variable it didn't declare, usually a missing local.
common_teardown() {
    local out="${output-}${stderr-}"
    if [[ $out == *'created globally in function'* ]]; then
        echo "zsh warned about a variable created globally:" >&2
        grep 'created globally' <<<"$out" >&2
        return 1
    fi
}

# stub NAME BODY: put a command NAME on PATH that runs BODY with bash.
stub() {
    printf '#!/bin/bash\n%s\n' "$2" >"$STUBS/$1"
    chmod +x "$STUBS/$1"
}

# setup_script ARGS...: run the script under test. Use with run.
setup_script() {
    "$ZSH_BIN" "$SCRIPT" "$@"
}

# in_script CODE: source the script and run CODE in the same zsh, to test
# its functions directly. Use with run.
in_script() {
    # shellcheck disable=SC2016  # expanded by zsh, not here
    "$ZSH_BIN" -fc 'source "$1" && eval "$2"' zsh "$SCRIPT" "$1"
}

# in_tty COMMAND...: run COMMAND with a pseudo-terminal for its output.
in_tty() {
    "$PYTHON" -c 'import os, pty, sys; sys.exit(os.waitstatus_to_exitcode(pty.spawn(sys.argv[1:])))' "$@"
}
