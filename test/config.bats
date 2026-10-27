#!/usr/bin/env bats
# The setup-yt-dlp lines in ~/.zshrc, and MacPorts' `port select`.
#
# The code passed to in_script is zsh, expanded by zsh:
# shellcheck disable=SC2016

setup() {
    load test_helper/common
    common_setup
    ZSHRC=$HOME/.zshrc
}

teardown() {
    common_teardown
}

# block LINE...: print a setup-yt-dlp block holding LINEs.
block() {
    printf '%s\n' '# >>> setup-yt-dlp >>>' \
        '# Added by setup-yt-dlp.zsh. Its --uninstall option removes these lines.' \
        "$@" '# <<< setup-yt-dlp <<<'
}

# zshrc_is: fail unless ~/.zshrc is byte for byte what's on stdin.
zshrc_is() {
    diff -u - "$ZSHRC"
}

@test "a new ~/.zshrc gets the block" {
    run -0 in_script 'ui_init; rc_change "export A=1" "export B=2"'
    assert_output '  ✓ ~/.zshrc           setup-yt-dlp lines added
    export A=1
    export B=2'
    block 'export A=1' 'export B=2' | zshrc_is
}

@test "the block goes after a blank line at the end" {
    printf 'alias ll="ls -l"\n' >"$ZSHRC"
    run -0 in_script 'rc_change "export A=1"'
    { printf 'alias ll="ls -l"\n\n'; block 'export A=1'; } | zshrc_is
}

@test "a ~/.zshrc without a final newline gets one before the block" {
    printf 'alias ll="ls -l"' >"$ZSHRC"
    run -0 in_script 'rc_change "export A=1"'
    { printf 'alias ll="ls -l"\n\n'; block 'export A=1'; } | zshrc_is
}

@test "the same lines again change nothing" {
    printf 'alias ll="ls -l"\n' >"$ZSHRC"
    run -0 in_script 'rc_change "export A=1"'
    cp "$ZSHRC" "$BATS_TEST_TMPDIR/before"
    run -0 in_script 'ui_init; rc_change "export A=1"'
    assert_output '  ✓ ~/.zshrc           already set up'
    zshrc_is <"$BATS_TEST_TMPDIR/before"
}

@test "new lines replace the block where it is" {
    { printf 'a\n'; block 'export A=1'; printf 'z\n'; } >"$ZSHRC"
    run -0 in_script 'ui_init; rc_change "export B=2"'
    assert_line --index 0 '  ✓ ~/.zshrc           setup-yt-dlp lines updated'
    { printf 'a\n'; block 'export B=2'; printf 'z\n'; } | zshrc_is
}

@test "a second block is removed when updating" {
    { block 'export A=1'; printf 'a\n\n'; block 'export A=1'; } >"$ZSHRC"
    run -0 in_script 'rc_change "export B=2"'
    { block 'export B=2'; printf 'a\n'; } | zshrc_is
}

@test "adding then removing gives back the file as it was" {
    local before
    for before in 'a\n' 'a\n\n' 'a\nb\n' '\n' ''; do
        # shellcheck disable=SC2059  # the samples are printf formats
        printf "$before" >"$ZSHRC"
        cp "$ZSHRC" "$BATS_TEST_TMPDIR/before"
        run -0 in_script 'rc_change "export A=1" && rc_change'
        zshrc_is <"$BATS_TEST_TMPDIR/before"
    done
}

@test "removing a block from the middle of the file" {
    { printf 'a\n\n'; block 'export A=1'; printf 'z\n'; } >"$ZSHRC"
    run -0 in_script 'ui_init; rc_change'
    assert_output '  ✓ ~/.zshrc           setup-yt-dlp lines removed'
    printf 'a\nz\n' | zshrc_is
}

@test "removing when there's nothing to remove" {
    run -0 in_script 'ui_init; rc_change'
    assert_output '  ✓ ~/.zshrc           nothing to remove'
    assert [ ! -e "$ZSHRC" ]
}

@test "a block without its end marker is left alone" {
    { printf 'a\n'; block 'export A=1' | sed '$d'; printf 'z\n'; } >"$ZSHRC"
    cp "$ZSHRC" "$BATS_TEST_TMPDIR/before"
    run -1 in_script 'ui_init; rc_change "export B=2"'
    assert_output "  ✗ ~/.zshrc           has a '# >>> setup-yt-dlp >>>' line with no '# <<< setup-yt-dlp <<<' after it
    Fix the file by hand, then run this again."
    zshrc_is <"$BATS_TEST_TMPDIR/before"
}

@test "a symlinked ~/.zshrc stays a symlink" {
    mkdir "$HOME/dotfiles"
    printf 'a\n' >"$HOME/dotfiles/zshrc"
    ln -s dotfiles/zshrc "$ZSHRC"
    run -0 in_script 'rc_change "export A=1"'
    assert [ -L "$ZSHRC" ]
    { printf 'a\n\n'; block 'export A=1'; } | diff -u - "$HOME/dotfiles/zshrc"
}

@test "~/.zshrc keeps its permissions" {
    printf 'a\n' >"$ZSHRC"
    chmod 600 "$ZSHRC"
    run -0 in_script 'rc_change "export A=1"'
    run -0 ls -l "$ZSHRC"
    assert_output --regexp '^-rw------- '
}

@test "no temporary file is left next to ~/.zshrc" {
    printf 'a\n' >"$ZSHRC"
    run -0 in_script 'rc_change "export A=1"'
    run -0 find "$HOME" -name '*setup-yt-dlp-*'
    assert_output ''
}

@test "ZDOTDIR is respected" {
    export ZDOTDIR=$HOME/.config/zsh
    mkdir -p "$ZDOTDIR"
    run -0 in_script 'ui_init; rc_change "export A=1"'
    assert_line --index 0 '  ✓ ~/.config/zsh/.zshrc setup-yt-dlp lines added'
    block 'export A=1' | diff -u - "$ZDOTDIR/.zshrc"
    assert [ ! -e "$ZSHRC" ]
}

@test "--dry-run doesn't change ~/.zshrc" {
    run -0 in_script 'opts[dry_run]=1; ui_init; rc_change "export A=1"'
    assert_output '  – ~/.zshrc           would have the setup-yt-dlp lines added
    export A=1'
    assert [ ! -e "$ZSHRC" ]
}

@test "the change is in the log" {
    run -0 in_script 'rc_change "export A=1"'
    run -0 cat "$HOME"/Library/Logs/yt-dlp-setup/*.log
    assert_line --regexp '^==> \[[0-9:]{8}\] ~/\.zshrc: setup-yt-dlp lines added$'
}

@test "Homebrew's lines: no environment hints, and pip's commands on PATH" {
    use_fake homebrew
    run -0 in_script 'opts[manager]=homebrew; pm_init; homebrew_shell_setup'
    # shellcheck disable=SC2016  # $HOME and $PATH are written as they are
    block 'export HOMEBREW_NO_ENV_HINTS=1' 'export PATH="$HOME/Library/Python/3.15/bin:$PATH"' | zshrc_is
}

@test "MacPorts: python, python3, pip and pip3 run the newest Python" {
    use_fake macports
    fake_installed port python313 3.13.9_0
    fake_installed port python314 3.14.0_0
    fake_installed port py-pip
    run -0 in_script 'opts[manager]=macports; pm_init; ui_init; macports_select_python; for k in ${(ok)port_select_before}; do print -r -- "$k=$port_select_before[$k]"; done'
    assert_output '  ✓ python             now python314
  ✓ python3            now python314
  ✓ pip                now pip314
  ✓ pip3               now pip314
pip=none
pip3=none
python=none
python3=none'
    run -0 calls
    assert_line 'sudo -n port select --set python python314'
    assert_line 'sudo -n port select --set pip3 pip314'
}

@test "MacPorts: python310 counts as newer than python39" {
    use_fake macports
    fake_installed port python39
    fake_installed port python310
    run -0 in_script 'opts[manager]=macports; pm_init; macports_python'
    assert_output python310
}

@test "MacPorts: an inactive Python isn't selected" {
    use_fake macports
    fake_installed port python313
    mkdir -p "$FAKE_STATE/port"
    echo '@3.14.0_0' >"$FAKE_STATE/port/python314"
    run -0 in_script 'opts[manager]=macports; pm_init; macports_python'
    assert_output python313
}

@test "MacPorts: groups already selected are left alone" {
    use_fake macports
    fake_installed port python314
    mkdir -p "$FAKE_STATE/select"
    echo python314 >"$FAKE_STATE/select/python3"
    echo python313 >"$FAKE_STATE/select/python"
    run -0 in_script 'opts[manager]=macports; pm_init; ui_init; macports_select_python; for k in ${(ok)port_select_before}; do print -r -- "$k=$port_select_before[$k]"; done'
    assert_output '  ✓ python             now python314
  ✓ python3            already python314
python=python313'
    run -0 calls
    refute_line --partial 'select --set python3'
}

@test "MacPorts: pip isn't selected without py-pip" {
    use_fake macports
    fake_installed port python314
    run -0 in_script 'opts[manager]=macports; pm_init; ui_init; macports_select_python'
    refute_output --partial pip
}

@test "MacPorts: no Python installed, nothing to select" {
    use_fake macports
    run -0 in_script 'opts[manager]=macports; pm_init; ui_init; macports_select_python'
    assert_output '  – python             no MacPorts Python to select'
}

@test "MacPorts: --dry-run shows the select commands" {
    use_fake macports
    fake_installed port python314
    run -0 in_script 'opts[manager]=macports opts[dry_run]=1; pm_init; ui_init; macports_select_python'
    assert_output '  – python             would run: sudo -n port select --set python python314
  – python3            would run: sudo -n port select --set python3 python314'
}
