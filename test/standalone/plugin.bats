#!/usr/bin/env bats
# Installing and updating the yt-dlp-apple-webkit-jsi plugin with the
# standalone script.
#
# The code passed to stub is bash, expanded by the stub:
# shellcheck disable=SC2016

setup() {
    load helper
    standalone_setup
    publish_ytdlp 2026.10.26
    publish_riedl amd64 9.0.2
    publish_evermeet 9.0.1
    publish_plugin 0.1.0
    PLUGIN_FILE=$PLUGIN_DIR/yt_dlp_plugins/extractor/webkit_jsi.py
}

teardown() {
    common_teardown
}

@test "it unzips the plugin into ~/.config/yt-dlp/plugins" {
    run -0 setup_script
    assert_line "▸ ~/.config/yt-dlp/plugins"
    assert_line '  ✓ yt-dlp-apple-webkit-jsi installed 0.1.0'
    assert [ -f "$PLUGIN_FILE" ]
    run -0 calls
    assert_line curl\ https://github.com/grqz/yt-dlp-apple-webkit-jsi/releases/download/v0.1.0/yt-dlp-apple-webkit-jsi.zip
}

@test "it uses XDG_CONFIG_HOME" {
    export XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/my\ config
    run -0 setup_script
    assert [ -f "$XDG_CONFIG_HOME/yt-dlp/plugins/yt-dlp-apple-webkit-jsi/yt_dlp_plugins/extractor/webkit_jsi.py" ]
    assert [ ! -e "$HOME/.config" ]
}

@test "run again, it leaves the plugin and doesn't look it up" {
    run -0 setup_script
    publish_plugin 0.1.1
    : >"$FAKE_STATE/calls"
    run -0 setup_script
    assert_line '  ✓ yt-dlp-apple-webkit-jsi already installed (0.1.0)'
    run -0 calls
    assert_output ''
}

@test "--update replaces the plugin, leaving none of the old files" {
    run -0 setup_script
    publish_plugin 0.1.1
    run -0 setup_script --update
    assert_line '  ✓ yt-dlp-apple-webkit-jsi updated 0.1.0 → 0.1.1'
    run -0 grep __version__ "$PLUGIN_FILE"
    assert_output "__version__ = '0.1.1'"
    assert [ -e "$PLUGIN_DIR/yt_dlp_plugins/extractor/from-0.1.1.py" ]
    assert [ ! -e "$PLUGIN_DIR/yt_dlp_plugins/extractor/from-0.1.0.py" ]
    run -0 find "$TMPDIR" -mindepth 1
    assert_output ''
}

@test "--update looks up the plugin, but downloads nothing when it's up to date" {
    run -0 setup_script
    : >"$FAKE_STATE/calls"
    run -0 setup_script --update
    assert_line '  ✓ yt-dlp-apple-webkit-jsi up to date (0.1.0)'
    run -0 calls
    assert_line curl\ https://github.com/grqz/yt-dlp-apple-webkit-jsi/releases/latest
    refute_line --partial yt-dlp-apple-webkit-jsi.zip
}

@test "updating only the plugin doesn't ask for administrator access" {
    run -0 setup_script
    publish_plugin 0.1.1
    chmod 555 "$BIN"
    stub sudo 'echo "sudo $*" >>"$FAKE_STATE/calls"; exit 1'
    run -0 setup_script --update
    chmod 755 "$BIN"
    assert_line '  ✓ yt-dlp-apple-webkit-jsi updated 0.1.0 → 0.1.1'
    run -0 calls
    refute_line --partial sudo
}

@test "--update keeps the old plugin when the download fails" {
    run -0 setup_script
    publish_plugin 0.1.1
    rm "$FAKE_WEB/github.com/grqz/yt-dlp-apple-webkit-jsi/releases/download/v0.1.1/yt-dlp-apple-webkit-jsi.zip"
    run -1 setup_script --update
    assert_line '  ✗ yt-dlp-apple-webkit-jsi failed'
    assert_line '    yt-dlp-apple-webkit-jsi couldn'\''t be updated'
    run -0 grep __version__ "$PLUGIN_FILE"
    assert_output "__version__ = '0.1.0'"
}

@test "--update keeps the old plugin when the zip doesn't have the plugin in it" {
    run -0 setup_script
    publish_plugin 0.1.1
    local dir=$FAKE_WEB/github.com/grqz/yt-dlp-apple-webkit-jsi/releases/download/v0.1.1
    make_zip "$dir/yt-dlp-apple-webkit-jsi.zip" "$BIN/yt-dlp_macos"
    run -1 setup_script --update
    assert_line "    yt-dlp-apple-webkit-jsi.zip doesn't have the plugin in it."
    run -0 grep __version__ "$PLUGIN_FILE"
    assert_output "__version__ = '0.1.0'"
}

@test "a release whose version differs from its tag still installs" {
    local releases=$FAKE_WEB/github.com/grqz/yt-dlp-apple-webkit-jsi/releases
    mkdir "$releases/download/v0.1.1"
    cp "$releases/download/v0.1.0/yt-dlp-apple-webkit-jsi.zip" "$releases/download/v0.1.1/"
    printf 'https://github.com/grqz/yt-dlp-apple-webkit-jsi/releases/tag/v0.1.1' >"$releases/latest.redirect"
    run -0 setup_script
    assert_line '  ✓ yt-dlp-apple-webkit-jsi installed 0.1.1'
    assert [ -f "$PLUGIN_FILE" ]
}

@test "a plugin folder that doesn't say its version is installed again" {
    mkdir -p "$PLUGIN_DIR"
    touch "$PLUGIN_DIR/stray"
    run -0 setup_script
    assert_line '  ✓ yt-dlp-apple-webkit-jsi installed 0.1.0'
    assert [ -f "$PLUGIN_FILE" ]
    assert [ ! -e "$PLUGIN_DIR/stray" ]
}

@test "a link to a plugin's checkout is left alone" {
    mkdir -p "${PLUGIN_DIR%/*}" "$BATS_TEST_TMPDIR/checkout"
    ln -s "$BATS_TEST_TMPDIR/checkout" "$PLUGIN_DIR"
    run -0 setup_script --update
    assert_line '  – yt-dlp-apple-webkit-jsi left alone: this script didn'\''t install it'
    assert [ -L "$PLUGIN_DIR" ]
    run -0 find "$BATS_TEST_TMPDIR/checkout" -mindepth 1
    assert_output ''
}

@test "macOS 10.15 skips the plugin" {
    macos 10.15.7
    run -0 setup_script
    assert_line '  – yt-dlp-apple-webkit-jsi skipped: it needs macOS 11 or later'
    assert [ ! -e "$HOME/.config" ]
    run -0 calls
    refute_line --partial yt-dlp-apple-webkit-jsi
}

@test "macOS 11 gets the plugin" {
    macos 11.7.10
    run -0 setup_script
    assert_line '  ✓ yt-dlp-apple-webkit-jsi installed 0.1.0'
}

@test "--dry-run shows what it would do to the plugin" {
    run -0 setup_script --dry-run
    assert_line '  – yt-dlp-apple-webkit-jsi would install 0.1.0'
    assert [ ! -e "$HOME/.config" ]
}

@test "it says so when it can't find the plugin's latest version" {
    rm -r "$FAKE_WEB/github.com/grqz"
    run -1 setup_script
    assert_line '  ✓ yt-dlp_macos   installed 2026.10.26'
    assert_line "  ✗ yt-dlp-apple-webkit-jsi couldn't find the latest version"
    assert_line "    the latest yt-dlp-apple-webkit-jsi couldn't be found"
}
