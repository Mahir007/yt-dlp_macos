# Shared setup for the tests of src/setup-yt-dlp-standalone.zsh. The
# script downloads from a fake web, and installs into a folder of the test's
# own instead of /usr/local/bin.
#
# shellcheck shell=bash

load ../test_helper/common

standalone_setup() {
    common_setup
    # shellcheck disable=SC2034  # run by common.bash's setup_script
    SCRIPT=$TEST_ROOT/src/setup-yt-dlp-standalone.zsh

    # The script's own setting for where to install, there for the tests.
    export SETUP_YT_DLP_BIN_DIR=$BATS_TEST_TMPDIR/bin
    BIN=$SETUP_YT_DLP_BIN_DIR

    export FAKE_STATE=$BATS_TEST_TMPDIR/fake FAKE_WEB=$BATS_TEST_TMPDIR/web
    mkdir -p "$FAKE_STATE" "$FAKE_WEB"
    touch "$FAKE_STATE/calls"
    ln -s "$FAKES/curl" "$STUBS/"
    export TMPDIR=$BATS_TEST_TMPDIR/tmp
    mkdir -p "$TMPDIR"

    # An Intel Mac on macOS 12 unless a test says otherwise. On Intel,
    # sysctl doesn't know hw.optional.arm64.
    stub sysctl 'exit 1'
}

# apple_silicon: make the Mac an Apple silicon one.
apple_silicon() {
    stub sysctl '[[ $* == "-n hw.optional.arm64" ]] && echo 1'
}

# macos VERSION: make the Mac run macOS VERSION.
macos() {
    stub sw_vers "echo $1"
}

# calls: print the commands the fakes ran.
calls() {
    cat "$FAKE_STATE/calls"
}

# fake_ytdlp FILE VERSION: write a yt-dlp_macos that says it's VERSION.
fake_ytdlp() {
    # shellcheck disable=SC2016  # expanded by the fake
    printf '#!/bin/bash\n[[ $1 == --version ]] && echo %s\n' "$2" >"$1"
    chmod +x "$1"
}

# fake_ffmpeg FILE TOOL BUILD: write an ffmpeg or ffprobe whose -version
# starts as the real ones do, such as "ffmpeg version 9.0.2-tessus".
fake_ffmpeg() {
    # shellcheck disable=SC2016  # expanded by the fake
    printf '#!/bin/bash\n[[ $1 == -version ]] && printf "%%s\\n" "%s version %s Copyright (c) 2000-2026 the FFmpeg developers" "built with Apple clang"\n' \
        "$2" "$3" >"$1"
    chmod +x "$1"
}

# make_zip ZIP FILE: put FILE in ZIP, at its top level.
make_zip() {
    "$PYTHON" -I -c 'import os, sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.write(sys.argv[2], os.path.basename(sys.argv[2]))' "$1" "$2"
}

# publish_ytdlp VERSION: make VERSION yt-dlp's latest release.
publish_ytdlp() {
    local releases=$FAKE_WEB/github.com/yt-dlp/yt-dlp/releases
    local dir=$releases/download/$1
    mkdir -p "$dir"
    printf 'https://github.com/yt-dlp/yt-dlp/releases/tag/%s' "$1" >"$releases/latest.redirect"
    fake_ytdlp "$dir/yt-dlp_macos" "$1"
    fake_ytdlp "$dir/yt-dlp" "$1"
    (cd "$dir" && shasum -a 256 yt-dlp yt-dlp_macos >SHA2-256SUMS)
}

# publish_riedl ARCH VERSION: make VERSION the latest release build for
# ARCH, arm64 or amd64, on martin-riedl.de.
publish_riedl() {
    local site=$FAKE_WEB/ffmpeg.martin-riedl.de build=1789931006_$2 tool
    local dir=$site/download/macos/$1/$build
    mkdir -p "$dir" "$site/redirect/latest/macos/$1/release" "$BATS_TEST_TMPDIR/riedl"
    printf 'https://ffmpeg.martin-riedl.de/download/macos/%s/%s/ffmpeg.zip' "$1" "$build" \
        >"$site/redirect/latest/macos/$1/release/ffmpeg.zip.redirect"
    for tool in ffmpeg ffprobe; do
        fake_ffmpeg "$BATS_TEST_TMPDIR/riedl/$tool" $tool "$2-https://www.martin-riedl.de"
        make_zip "$dir/$tool.zip" "$BATS_TEST_TMPDIR/riedl/$tool"
        (cd "$dir" && shasum -a 256 $tool.zip >$tool.zip.sha256)
    done
}

# publish_evermeet VERSION: make VERSION the latest release on evermeet.cx.
publish_evermeet() {
    local site=$FAKE_WEB/evermeet.cx/ffmpeg tool
    mkdir -p "$BATS_TEST_TMPDIR/evermeet"
    for tool in ffmpeg ffprobe; do
        mkdir -p "$site/info/$tool"
        printf '{"name":"%s","type":"release","version":"%s","size":1,"download":{"7z":{"url":"https://evermeet.cx/ffmpeg/%s-%s.7z","size":1},"zip":{"url":"https://evermeet.cx/ffmpeg/%s-%s.zip","size":1}},"libraries":{"internal":[{"name":"libavutil","version":"61.1.102"}]}}' \
            $tool "$1" $tool "$1" $tool "$1" >"$site/info/$tool/release"
        fake_ffmpeg "$BATS_TEST_TMPDIR/evermeet/$tool" $tool "$1-tessus"
        make_zip "$site/$tool-$1.zip" "$BATS_TEST_TMPDIR/evermeet/$tool"
    done
}

# installed_as TOOL: print what TOOL in $BIN says its version is.
installed_as() {
    if [[ $1 == yt-dlp_macos ]]; then
        "$BIN/$1" --version
    else
        "$BIN/$1" -version | head -1
    fi
}
