#!/bin/bash
# package.sh TAG [DIR]: build the release archive for TAG, such as v1.0.0,
# in DIR (default dist): setup-yt-dlp.tar.xz, holding
# setup-yt-dlp-VERSION/setup-yt-dlp.zsh and LICENSE, and its SHA-256 in
# setup-yt-dlp.tar.xz.sha256. The script in the repository says its version
# is dev; the copy in the archive gets the tag's. Needs GNU tar. Run from
# the top of the repo.
set -euo pipefail

tag=$1
out=${2:-dist}
version=${tag#v}
script=src/setup-yt-dlp.zsh

if [[ ! $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
    echo "error: $tag isn't a version tag, such as v1.0.0 or v1.0.0-beta.1" >&2
    exit 1
fi

name=setup-yt-dlp-$version
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
install -d -m 755 "$work/$name"
sed "s/^typeset -gr SETUP_VERSION=dev\$/typeset -gr SETUP_VERSION=$version/" "$script" >"$work/$name/setup-yt-dlp.zsh"
if ! grep -qx "typeset -gr SETUP_VERSION=$version" "$work/$name/setup-yt-dlp.zsh"; then
    echo "error: $script has no 'typeset -gr SETUP_VERSION=dev' line to put the version in" >&2
    exit 1
fi
chmod 755 "$work/$name/setup-yt-dlp.zsh"
install -m 644 LICENSE "$work/$name/LICENSE"

# The same commit always gives the same archive: fixed order, owners and
# times, and a format without per-file access times.
mkdir -p "$out"
tar --format=ustar --sort=name --owner=0 --group=0 --numeric-owner \
    --mtime="@$(git log -1 --format=%ct)" -C "$work" -cf - "$name" |
    xz -9e --threads=1 >"$out/setup-yt-dlp.tar.xz"
(cd "$out" && sha256sum setup-yt-dlp.tar.xz >setup-yt-dlp.tar.xz.sha256)
