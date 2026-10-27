#!/usr/bin/env bats
# Saving YouTube Downloader Pro from src/youtube-downloader-pro-standalone.command.
#
# The code passed to in_script is zsh, expanded by zsh:
# shellcheck disable=SC2016

setup() {
    load helper
    standalone_setup
    DOWNLOADER=$TEST_ROOT/src/youtube-downloader-pro-standalone.command
    local dir=$FAKE_WEB/raw.githubusercontent.com/Mahir007/yt-dlp_macos/main/src
    mkdir -p "$dir" "$HOME/Downloads"
    cp "$DOWNLOADER" "$dir/"
    SAVED="$HOME/Downloads/YouTube Downloader Pro.command"
}

teardown() {
    common_teardown
}

# answer INPUT CODE: in_script_tty CODE, typing INPUT into the terminal.
answer() {
    # shellcheck disable=SC2059  # INPUT holds escapes such as \n
    printf "$1" | in_script_tty "$2" | tr -d '\r'
}

@test "it comes from main outside a release, and from the tag in one" {
    run -0 in_script 'downloader_url'
    assert_output https://raw.githubusercontent.com/Mahir007/yt-dlp_macos/main/src/youtube-downloader-pro-standalone.command
    sed 's/^typeset -gr SETUP_VERSION=0\.0\.0-dev$/typeset -gr SETUP_VERSION=1.2.3/' "$SCRIPT" >"$BATS_TEST_TMPDIR/release.zsh"
    SCRIPT=$BATS_TEST_TMPDIR/release.zsh run -0 in_script 'downloader_url'
    assert_output https://raw.githubusercontent.com/Mahir007/yt-dlp_macos/v1.2.3/src/youtube-downloader-pro-standalone.command
}

@test "--downloader saves it to ~/Downloads as it is, and installs nothing" {
    run -0 setup_script --downloader
    assert_line --regexp '^  ✓ ~/Downloads/YouTube Downloader Pro\.command +saved$'
    assert_line 'Open ~/Downloads/YouTube Downloader Pro.command from Finder to start it.'
    assert [ -x "$SAVED" ]
    run -0 cmp "$DOWNLOADER" "$SAVED"
    assert [ ! -e "$BIN" ]
}

@test "--downloader takes a folder or a file" {
    mkdir "$HOME/Apps"
    run -0 setup_script --downloader "$HOME/Apps"
    assert [ -x "$HOME/Apps/YouTube Downloader Pro.command" ]
    run -0 setup_script -d "$HOME/Apps/pro"
    assert [ -x "$HOME/Apps/pro.command" ]
    run -0 setup_script '--downloader=~/Apps/tilde.command'
    assert [ -x "$HOME/Apps/tilde.command" ]
}

@test "--downloader replaces a file only when told to" {
    echo mine >"$SAVED"
    run -1 --separate-stderr setup_script --downloader
    assert_stderr "error: ~/Downloads/YouTube Downloader Pro.command exists; run with --yes to replace it"
    run -0 answer 'n\n' 'main --no-color --downloader'
    assert_output --partial 'Replace it? [y/N] Not saved.'
    run -0 cat "$SAVED"
    assert_output mine
    run -0 setup_script --downloader --yes
    run -0 cmp "$DOWNLOADER" "$SAVED"
}

@test "--downloader --dry-run saves nothing" {
    run -0 setup_script --downloader --dry-run
    assert_line '  – download       would download https://raw.githubusercontent.com/Mahir007/yt-dlp_macos/main/src/youtube-downloader-pro-standalone.command'
    assert [ ! -e "$SAVED" ]
}

@test "--downloader and --update can't be used together" {
    run -2 --separate-stderr setup_script --downloader --update
    assert_stderr_line --index 0 "error: --update and --downloader can't be used together"
}

@test "--downloader takes its path from the next word, unless that's an option" {
    run -0 in_script 'cli_parse --downloader ~/Apps --yes && print -r -- $opts[action] $opts[output] $opts[yes]'
    assert_output "downloader $HOME/Apps 1"
    run -0 in_script 'cli_parse -d -n && print -r -- $opts[action] "<$opts[output]>" $opts[dry_run]'
    assert_output 'downloader <> 1'
    run -2 --separate-stderr setup_script --downloader=
    assert_stderr_line --index 0 "error: option '--downloader=' needs a path after the ="
}

@test "a download that isn't the downloader isn't saved" {
    echo '<html>' >"$FAKE_WEB/raw.githubusercontent.com/Mahir007/yt-dlp_macos/main/src/youtube-downloader-pro-standalone.command"
    run -1 setup_script --downloader
    assert_line --regexp "^  ✗ ~/Downloads/YouTube Downloader Pro\\.command +not saved: the download isn't YouTube Downloader Pro$"
    assert [ ! -e "$SAVED" ]
}

@test "a failed download saves nothing" {
    rm -r "$FAKE_WEB/raw.githubusercontent.com"
    run -1 setup_script --downloader
    assert_line --regexp '^  ✗ download +failed$'
    assert [ ! -e "$SAVED" ]
    run -0 find "$TMPDIR" -name '*.command'
    assert_output ''
}

@test "an install on a terminal ends with the question, and yes saves it" {
    publish_ytdlp 2026.10.26
    publish_riedl amd64 9.0.2
    stub osascript 'echo "$HOME/Downloads/Pro"'
    run -0 answer 'y\n' 'main --no-color'
    assert_output --partial 'Do you want to download the YouTube Downloader Pro script? [y/N] '
    assert_line 'Open ~/Downloads/Pro.command from Finder to start it.'
    assert [ -x "$HOME/Downloads/Pro.command" ]
}

@test "--update doesn't ask" {
    publish_ytdlp 2026.10.26
    publish_riedl amd64 9.0.2
    stub osascript 'touch "$HOME/asked"; exit 1'
    run -0 answer 'y\n' 'main --no-color --update'
    refute_output --partial 'YouTube Downloader Pro'
    assert [ ! -e "$HOME/asked" ]
}

@test "the saved downloader updates yt-dlp_macos and shows the menu" {
    run -0 setup_script --downloader
    printf '#!/bin/bash\necho "yt-dlp_macos $*" >>"%s"\n' "$FAKE_STATE/calls" >"$STUBS/yt-dlp_macos"
    chmod +x "$STUBS/yt-dlp_macos"
    run -0 env PATH="$STUBS:/usr/bin:/bin" /bin/bash "$SAVED" <<<q
    assert_output --partial 'YouTube Downloader Pro'
    assert_output --partial 'Goodbye!'
    run -0 calls
    assert_line 'yt-dlp_macos -U'
}
