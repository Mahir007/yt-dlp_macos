#!/usr/bin/env bats
# Starting the script: shells, platform checks and colors.

setup() {
    load test_helper/common
    common_setup
}

teardown() {
    common_teardown
}

@test "the script parses" {
    run -0 "$ZSH_BIN" -n "$SCRIPT"
}

@test "started with bash, it runs again under zsh" {
    ln -s "$ZSH_BIN" "$STUBS/zsh"
    run -0 bash "$SCRIPT" --version
    assert_output --regexp '^setup-yt-dlp '
}

@test "started with sh, it runs again under zsh" {
    ln -s "$ZSH_BIN" "$STUBS/zsh"
    run -0 sh "$SCRIPT" --version
    assert_output --regexp '^setup-yt-dlp '
}

@test "it stops when the macOS tools aren't there" {
    rm "$STUBS/sw_vers"
    run -1 --separate-stderr env PATH="$STUBS" "$ZSH_BIN" "$SCRIPT"
    assert_stderr 'error: this script only works on macOS'
}

@test "it warns on macOS older than 12" {
    stub sw_vers 'echo 11.7.10'
    run -0 --separate-stderr in_script preflight
    assert_stderr 'warning: macOS 11.7.10 is older than macOS 12, the oldest version this script supports'
}

@test "it doesn't warn on macOS 12 or later" {
    local version
    for version in 12.0 12.7.6 15.5 26.1; do
        stub sw_vers "echo $version"
        run -0 --separate-stderr in_script preflight
        assert_stderr ''
    done
}

@test "--help uses colors on a terminal" {
    run -0 in_tty "$ZSH_BIN" "$SCRIPT" --help
    assert_output --partial $'\e[1mUsage:\e[0m'
}

@test "--no-color turns colors off" {
    run -0 in_tty "$ZSH_BIN" "$SCRIPT" --help --no-color
    assert_output --partial 'Usage:'
    refute_output --partial $'\e['
}

@test "NO_COLOR turns colors off" {
    run -0 in_tty env NO_COLOR=1 "$ZSH_BIN" "$SCRIPT" --help
    assert_output --partial 'Usage:'
    refute_output --partial $'\e['
}

@test "TERM=dumb turns colors off" {
    run -0 in_tty env TERM=dumb "$ZSH_BIN" "$SCRIPT" --help
    assert_output --partial 'Usage:'
    refute_output --partial $'\e['
}

@test "no colors when the output isn't a terminal" {
    run -0 setup_script --help
    refute_output --partial $'\e['
}

@test "usage errors respect --no-color" {
    run -2 in_tty "$ZSH_BIN" "$SCRIPT" --no-color --bogus
    assert_output --partial "error: unknown option '--bogus'"
    refute_output --partial $'\e['
}
