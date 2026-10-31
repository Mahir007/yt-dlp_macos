#!/bin/bash
# package.sh VERSION [DIR]: build the archives for VERSION, such as 1.0.0 or
# 0.0.0-dev+1a2b3c4, in DIR (default dist): setup-yt-dlp.tar.xz and
# setup-yt-dlp-standalone.tar.xz, each holding its script and LICENSE with
# no folder around them, and their SHA-256s in NAME.tar.xz.sha256. The
# scripts in the repository say their version is 0.0.0-dev; the copies in
# the archives get VERSION. Needs GNU tar. Run from the top of the repo.
set -euo pipefail

version=$1
out=${2:-dist}

if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?(\+[0-9A-Za-z.]+)?$ ]]; then
    echo "error: $version isn't a version, such as 1.0.0, 1.0.0-beta.1 or 0.0.0-dev+1a2b3c4" >&2
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# package NAME: build NAME.tar.xz from src/NAME.zsh.
package() {
    local name=$1 script=src/$1.zsh dir=$work/$1
    mkdir "$dir"
    sed "s/^typeset -gr SETUP_VERSION=0\.0\.0-dev\$/typeset -gr SETUP_VERSION=$version/" "$script" >"$dir/$name.zsh"
    if ! grep -qx "typeset -gr SETUP_VERSION=$version" "$dir/$name.zsh"; then
        echo "error: $script has no 'typeset -gr SETUP_VERSION=0.0.0-dev' line to put the version in" >&2
        exit 1
    fi
    chmod 755 "$dir/$name.zsh"
    install -m 644 LICENSE "$dir/LICENSE"

    # The same commit always gives the same archive: fixed order, owners
    # and times, and a format without per-file access times.
    tar --format=ustar --sort=name --owner=0 --group=0 --numeric-owner \
        --mtime="@$(git log -1 --format=%ct)" -C "$dir" -cf - LICENSE "$name.zsh" |
        xz -9e --threads=1 >"$out/$name.tar.xz"
    (cd "$out" && sha256sum "$name.tar.xz" >"$name.tar.xz.sha256")
}

mkdir -p "$out"
package setup-yt-dlp
package setup-yt-dlp-standalone
