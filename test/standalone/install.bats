#!/usr/bin/env bats
# Installing yt-dlp_macos, ffmpeg and ffprobe with the standalone script.
#
# The code passed to in_script is zsh, expanded by zsh:
# shellcheck disable=SC2016

setup() {
    load helper
    standalone_setup
    publish_ytdlp 2026.10.26
    publish_riedl amd64 9.0.2
    publish_riedl arm64 9.0.2
    publish_evermeet 9.0.1
}

teardown() {
    common_teardown
}

@test "it installs all three from yt-dlp's releases and martin-riedl.de" {
    run -0 setup_script
    assert_line 'macOS 12.7.6 on Intel'
    assert_line "▸ $BIN"
    assert_line '  ✓ yt-dlp_macos   installed 2026.10.26'
    assert_line '  ✓ ffmpeg         installed 9.0.2'
    assert_line '  ✓ ffprobe        installed 9.0.2'
    assert_line --regexp '^✓ Done in [0-9]+s\. Start yt-dlp with yt-dlp_macos\.$'
    run -0 installed_as yt-dlp_macos
    assert_output 2026.10.26
    run -0 installed_as ffprobe
    assert_output --regexp '^ffprobe version 9\.0\.2-https://www\.martin-riedl\.de '
    run -0 calls
    assert_line curl\ https://ffmpeg.martin-riedl.de/download/macos/amd64/1789931006_9.0.2/ffmpeg.zip
    refute_line --partial evermeet
}

@test "the binaries are executable, and nothing else is left behind" {
    run -0 setup_script
    run -0 find "$BIN" -type f ! -perm -755
    assert_output ''
    run -0 find "$TMPDIR" "$HOME" -mindepth 1
    assert_output ''
}

@test "Apple silicon gets the arm64 builds" {
    apple_silicon
    run -0 setup_script
    assert_line 'macOS 12.7.6 on Apple silicon'
    run -0 calls
    assert_line curl\ https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931006_9.0.2/ffmpeg.zip
    refute_line --partial /amd64/
}

@test "an Intel Mac on macOS 10.15 gets ffmpeg from evermeet.cx" {
    macos 10.15.7
    run -0 setup_script
    assert_line '  ✓ ffmpeg         installed 9.0.1'
    assert_line '  ✓ ffprobe        installed 9.0.1'
    run -0 installed_as ffmpeg
    assert_output --regexp '^ffmpeg version 9\.0\.1-tessus '
    run -0 calls
    refute_line --partial martin-riedl
}

@test "Apple silicon on macOS 11 gets yt-dlp_macos alone" {
    apple_silicon
    macos 11.7.10
    run -0 setup_script
    assert_line '  ✓ yt-dlp_macos   installed 2026.10.26'
    assert_line '  – ffmpeg         skipped: on Apple silicon, it needs macOS 12 or later'
    assert_line '  – ffprobe        skipped: on Apple silicon, it needs macOS 12 or later'
    assert [ ! -e "$BIN/ffmpeg" ]
}

@test "run again, it doesn't download anything and points at --update" {
    run -0 setup_script
    : >"$FAKE_STATE/calls"
    run -0 setup_script
    assert_line '  ✓ yt-dlp_macos   already installed (2026.10.26)'
    assert_line '  ✓ ffmpeg         already installed (9.0.2)'
    assert_line '  To update, run the script with --update.'
    run -0 calls
    assert_output ''
}

@test "it installs only what's missing" {
    run -0 setup_script
    rm "$BIN/ffprobe"
    run -0 setup_script
    assert_line '  ✓ ffmpeg         already installed (9.0.2)'
    assert_line '  ✓ ffprobe        installed 9.0.2'
}

@test "a yt-dlp_macos that doesn't run is installed again" {
    mkdir -p "$BIN"
    printf '#!/bin/bash\nexit 1\n' >"$BIN/yt-dlp_macos"
    chmod +x "$BIN/yt-dlp_macos"
    run -0 setup_script
    assert_line '  ✓ yt-dlp_macos   installed 2026.10.26'
}

@test "an ffmpeg it didn't install is left alone" {
    mkdir -p "$BIN" "$BATS_TEST_TMPDIR/cellar"
    fake_ffmpeg "$BATS_TEST_TMPDIR/cellar/ffmpeg" ffmpeg 8.0
    ln -s "$BATS_TEST_TMPDIR/cellar/ffmpeg" "$BIN/ffmpeg"
    fake_ffmpeg "$BIN/ffprobe" ffprobe 8.0
    run -0 setup_script
    assert_line '  – ffmpeg         left alone: this script didn'\''t install it'
    assert_line '  – ffprobe        left alone: this script didn'\''t install it'
    assert [ -L "$BIN/ffmpeg" ]
    run -0 installed_as ffprobe
    assert_output --regexp '^ffprobe version 8\.0 '
}

@test "a download with the wrong checksum isn't installed" {
    local dir=$FAKE_WEB/ffmpeg.martin-riedl.de/download/macos/amd64/1789931006_9.0.2
    echo "$(printf '0%.0s' {1..64})  ffmpeg.zip" >"$dir/ffmpeg.zip.sha256"
    run -1 setup_script
    assert_line '  ✗ ffmpeg         failed'
    assert_line --regexp "^    The download's SHA-256 is [0-9a-f]{64}, but should be 0{64}\.$"
    assert_line '  ✓ ffprobe        installed 9.0.2'
    assert_line '    ffmpeg couldn'\''t be installed'
    assert_line '  Run the script again to retry.'
    assert [ ! -e "$BIN/ffmpeg" ]
}

@test "a new copy that says the wrong version isn't installed" {
    fake_ytdlp "$FAKE_WEB/github.com/yt-dlp/yt-dlp/releases/download/2026.10.26/yt-dlp_macos" 2026.10.20
    (cd "$FAKE_WEB/github.com/yt-dlp/yt-dlp/releases/download/2026.10.26" && shasum -a 256 yt-dlp_macos >SHA2-256SUMS)
    run -1 setup_script
    assert_line '  ✗ yt-dlp_macos   failed'
    assert_line "    The new yt-dlp_macos says it's version 2026.10.20, not 2026.10.26."
    assert [ ! -e "$BIN/yt-dlp_macos" ]
}

@test "it says so when it can't find the latest version" {
    rm -r "$FAKE_WEB/ffmpeg.martin-riedl.de"
    run -1 setup_script
    assert_line '  ✓ yt-dlp_macos   installed 2026.10.26'
    assert_line "  ✗ ffmpeg         couldn't find the latest version"
    assert_line "    the latest ffprobe couldn't be found"
    assert_line --regexp "^  The log has the details: $TMPDIR/setup-yt-dlp-standalone-[0-9-]+\.log\$"
    run -0 cat "$TMPDIR"/setup-yt-dlp-standalone-*.log
    assert_line --partial "couldn't look up the latest versions at riedl"
    assert_line 'curl: (22) The requested URL returned error: 404'
}

@test "the checksums are read from shasum's output" {
    local a b
    a=$(printf 'a%.0s' {1..64})
    b=$(printf 'B%.0s' {1..64})
    run -0 in_script "sum_for b.zip '$a  a.zip
$b *b.zip'"
    assert_output "${b,,}"
    run -1 in_script "sum_for c.zip '$a  a.zip'"
}

@test "--dry-run looks up versions but installs nothing" {
    run -0 setup_script --dry-run
    assert_line --partial '(dry run: nothing will be changed)'
    assert_line '  – yt-dlp_macos   would install 2026.10.26'
    assert_line '  – ffmpeg         would install 9.0.2'
    assert_line 'Dry run finished. Nothing was changed.'
    assert [ ! -e "$BIN" ]
}

@test "--verbose shows what the steps do" {
    run -0 setup_script --verbose
    assert_line '  ▸ ffmpeg         installing…'
    assert_line '    │ Downloading https://ffmpeg.martin-riedl.de/download/macos/amd64/1789931006_9.0.2/ffmpeg.zip'
}

@test "it uses sudo when it can't write to the folder" {
    mkdir -p "$BIN"
    chmod 555 "$BIN"
    # A sudo that can write to the folder while it runs a command.
    stub sudo 'case $1 in -v|-k) exit 0 ;; -n) shift ;; esac
case $1 in -v|-k) exit 0 ;; esac
echo "sudo $*" >>"$FAKE_STATE/calls"
chmod 755 "'"$BIN"'"; "$@"; rc=$?; chmod 555 "'"$BIN"'"; exit $rc'
    run -0 setup_script
    assert_line '  ✓ ffmpeg         installed 9.0.2'
    run -0 calls
    assert_line --regexp "^sudo mv -f $TMPDIR/setup-yt-dlp-standalone\.[^ ]+/ffmpeg/unzipped/ffmpeg $BIN/ffmpeg$"
    chmod 755 "$BIN"
}

@test "it needs sudo only when it can't write to the folder or create it" {
    # No folder yet, in a writable one.
    run -1 in_script needs_sudo
    mkdir -p "$BIN"
    run -1 in_script needs_sudo
    chmod 555 "$BIN"
    run -0 in_script needs_sudo
    chmod 755 "$BIN"
}
