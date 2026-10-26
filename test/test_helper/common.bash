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

    SCRIPT=$BATS_TEST_DIRNAME/../src/yt-dlp_setup.zsh
    FAKES=$BATS_TEST_DIRNAME/fakes
    # Resolved before PATH changes, for detached and in_tty.
    PYTHON=$(command -v python3)

    export HOME=$BATS_TEST_TMPDIR/home
    mkdir -p "$HOME"
    STUBS=$BATS_TEST_TMPDIR/stubs
    mkdir -p "$STUBS"
    # Only the system's own commands, so a real brew or port isn't found.
    export PATH=$STUBS:/usr/bin:/bin
    unset NO_COLOR ZDOTDIR
    # CI runners don't set TERM, and the script treats that like TERM=dumb.
    export TERM=xterm-256color
    # The script picks Unicode or ASCII symbols from the locale.
    export LANG=en_US.UTF-8
    unset LC_ALL LC_CTYPE

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

# use_fake homebrew|macports: put the fake brew and its python3, or the fake
# port and sudo, on PATH. They sit in PREFIX/bin like in a real install.
use_fake() {
    export FAKE_STATE=$BATS_TEST_TMPDIR/fake
    mkdir -p "$FAKE_STATE"
    touch "$FAKE_STATE/calls"
    local prefix=$BATS_TEST_TMPDIR/$1
    mkdir -p "$prefix/bin"
    case $1 in
        homebrew) ln -s "$FAKES/brew" "$FAKES/python3" "$prefix/bin/" ;;
        macports) ln -s "$FAKES/port" "$prefix/bin/" && ln -s "$FAKES/sudo" "$STUBS/" ;;
    esac
    export PATH=$prefix/bin:$PATH
}

# fake_installed brew|port|pip NAME [VERSION]: mark NAME as installed.
fake_installed() {
    mkdir -p "$FAKE_STATE/$1"
    if [[ $1 == port ]]; then
        echo "@${3:-1.0_0} (active)" >"$FAKE_STATE/$1/$2"
    else
        echo "${3:-1.0}" >"$FAKE_STATE/$1/$2"
    fi
}

# fake_fails NAME: make installing or uninstalling NAME fail.
fake_fails() {
    mkdir -p "$FAKE_STATE/fail"
    touch "$FAKE_STATE/fail/$1"
}

# detached COMMAND...: run COMMAND without a terminal, so the script can't
# stop to ask a question on the terminal running the tests.
detached() {
    "$PYTHON" -c 'import subprocess, sys
r = subprocess.run(sys.argv[1:], start_new_session=True).returncode
sys.exit(128 - r if r < 0 else r)' "$@" </dev/null
}

# setup_script ARGS...: run the script under test. Use with run.
setup_script() {
    detached "$ZSH_BIN" "$SCRIPT" "$@"
}

# in_script CODE: source the script and run CODE in the same zsh, to test
# its functions directly. Use with run.
in_script() {
    # shellcheck disable=SC2016  # expanded by zsh, not here
    detached "$ZSH_BIN" -fc 'source "$1" && eval "$2"' zsh "$SCRIPT" "$1"
}

# in_tty COMMAND...: run COMMAND with a pseudo-terminal for its output.
# Anything on stdin is typed into the terminal, so `printf '\003'` is Ctrl-C.
in_tty() {
    "$PYTHON" -c 'import os, pty, sys; sys.exit(os.waitstatus_to_exitcode(pty.spawn(sys.argv[1:])))' "$@"
}

# in_script_tty CODE: in_script with a pseudo-terminal for the output.
in_script_tty() {
    # shellcheck disable=SC2016  # expanded by zsh, not here
    in_tty "$ZSH_BIN" -fc 'source "$1" && eval "$2"' zsh "$SCRIPT" "$1"
}
