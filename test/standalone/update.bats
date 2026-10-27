#!/usr/bin/env bats
# Updating with the standalone script's --update.

setup() {
    load helper
    standalone_setup
    publish_ytdlp 2026.10.20
    publish_riedl amd64 9.0.1
    setup_script >/dev/null
    publish_ytdlp 2026.10.26
    publish_riedl amd64 9.0.2
}

teardown() {
    common_teardown
}

@test "--update updates what's out of date" {
    run -0 setup_script --update
    assert_line '  ✓ yt-dlp_macos   updated 2026.10.20 → 2026.10.26'
    assert_line '  ✓ ffmpeg         updated 9.0.1 → 9.0.2'
    assert_line '  ✓ ffprobe        updated 9.0.1 → 9.0.2'
    refute_line --partial 'To update'
    run -0 installed_as yt-dlp_macos
    assert_output 2026.10.26
    run -0 installed_as ffmpeg
    assert_output --regexp '^ffmpeg version 9\.0\.2-'
}

@test "-U is the same as --update" {
    run -0 setup_script -U
    assert_line '  ✓ yt-dlp_macos   updated 2026.10.20 → 2026.10.26'
}

@test "--update leaves what's up to date" {
    run -0 setup_script --update
    : >"$FAKE_STATE/calls"
    run -0 setup_script --update
    assert_line '  ✓ yt-dlp_macos   up to date (2026.10.26)'
    assert_line '  ✓ ffprobe        up to date (9.0.2)'
    # It looks, but downloads nothing.
    run -0 calls
    refute_line --regexp '/download/.*(yt-dlp_macos|\.zip)$'
}

@test "--update installs what's missing" {
    rm "$BIN/ffmpeg"
    run -0 setup_script --update
    assert_line '  ✓ ffmpeg         installed 9.0.2'
    assert_line '  ✓ ffprobe        updated 9.0.1 → 9.0.2'
}

@test "--update leaves an ffmpeg it didn't install" {
    rm "$BIN/ffmpeg"
    fake_ffmpeg "$BIN/ffmpeg" ffmpeg 8.0
    run -0 setup_script --update
    assert_line '  – ffmpeg         left alone: this script didn'\''t install it'
    run -0 installed_as ffmpeg
    assert_output --regexp '^ffmpeg version 8\.0 '
}

@test "--update keeps the old copy when the new one fails" {
    local dir=$FAKE_WEB/ffmpeg.martin-riedl.de/download/macos/amd64/1789931006_9.0.2
    rm "$dir/ffprobe.zip"
    run -1 setup_script --update
    assert_line '  ✗ ffprobe        failed'
    assert_line '    ffprobe couldn'\''t be updated'
    assert_line '  Run the script with --update again to retry.'
    run -0 installed_as ffprobe
    assert_output --regexp '^ffprobe version 9\.0\.1-'
}

@test "--update --dry-run shows what it would update" {
    run -0 setup_script --update --dry-run
    assert_line '  – yt-dlp_macos   would update 2026.10.20 → 2026.10.26'
    assert_line '  – ffmpeg         would update 9.0.1 → 9.0.2'
    run -0 installed_as ffmpeg
    assert_output --regexp '^ffmpeg version 9\.0\.1-'
}
