#!/bin/bash
# release-notes.sh TAG REPO SHA256FILE...: print the release notes for TAG,
# in Markdown: how to install it, the commits since the previous release
# grouped by kind, and the archives' checksums. REPO is owner/name.
set -euo pipefail

tag=$1
repo=$2
sums=("${@:3}")
version=${tag#v}
url=https://github.com/$repo

# A pre-release lists the commits since the previous tag of any kind. A
# final release skips the pre-releases before it, so it lists everything
# since the previous final release.
exclude=()
[[ $version == *-* ]] || exclude=(--exclude 'v*-*')
previous=$(git describe --tags --abbrev=0 --match 'v*' "${exclude[@]+"${exclude[@]}"}" "$tag^" 2>/dev/null || true)
range=${previous:+$previous..}$tag

# kind SHA SUBJECT: print which group a commit goes in. Commits that only
# touch tests, CI or contributor docs go under development.
kind() {
    local file dev=1
    while IFS= read -r file; do
        case $file in
            test/* | .github/* | Makefile | CONTRIBUTING.md | .editorconfig | .gitattributes | .gitmodules) ;;
            *) dev=0 ;;
        esac
    done < <(git show --format= --name-only "$1")
    if ((dev)); then
        echo development
        return
    fi
    case $2 in
        Add* | Install*) echo new ;;
        Fix*) echo fixes ;;
        *) echo changes ;;
    esac
}

declare -a shas=() subjects=() reverted=()
while IFS=$'\t' read -r sha subject; do
    shas+=("$sha")
    subjects+=("$subject")
    if [[ $subject =~ ^Revert\ \"(.*)\"$ ]]; then
        reverted+=("${BASH_REMATCH[1]}")
    fi
done < <(git log --no-merges --reverse --format='%h%x09%s' "$range")

# is_reverted SUBJECT: succeed if a commit in the range reverts SUBJECT.
is_reverted() {
    local subject
    for subject in "${reverted[@]+"${reverted[@]}"}"; do
        [[ $subject == "$1" ]] && return 0
    done
    return 1
}

declare -a new=() fixes=() changes=() development=()
for i in "${!shas[@]}"; do
    sha=${shas[i]} subject=${subjects[i]}
    # A commit and its revert cancel out, so neither is listed.
    if [[ $subject == 'Revert "'*'"' ]] || is_reverted "$subject"; then
        continue
    fi
    line="- $subject ($sha)"
    case $(kind "$sha" "$subject") in
        new) new+=("$line") ;;
        fixes) fixes+=("$line") ;;
        changes) changes+=("$line") ;;
        development) development+=("$line") ;;
    esac
done

# section TITLE LINE...: print a group of commits, if it has any.
section() {
    local title=$1
    shift
    (($#)) || return 0
    printf '\n### %s\n\n' "$title"
    printf '%s\n' "$@"
}

if [[ $version == *-* ]]; then
    cat <<EOF
> [!WARNING]
> This is a pre-release, for trying things out before ${version%%-*} is final.

EOF
fi

cat <<EOF
Installs [yt-dlp](https://github.com/yt-dlp/yt-dlp) and the tools it uses on macOS.

## Install

With Homebrew or MacPorts, on macOS 12 or later:

\`\`\`sh
curl -fsSLO $url/releases/download/$tag/setup-yt-dlp.tar.xz
tar -xf setup-yt-dlp.tar.xz
./setup-yt-dlp.zsh
\`\`\`

Without a package manager, on macOS 10.15 or later, into \`/usr/local/bin\`:

\`\`\`sh
curl -fsSLO $url/releases/download/$tag/setup-yt-dlp-standalone.tar.xz
tar -xf setup-yt-dlp-standalone.tar.xz
./setup-yt-dlp-standalone.zsh
\`\`\`

## What's changed
EOF

section "✨ New" "${new[@]+"${new[@]}"}"
section "🐛 Fixes" "${fixes[@]+"${fixes[@]}"}"
section "🔧 Changes" "${changes[@]+"${changes[@]}"}"
if ((${#development[@]})); then
    printf '\n<details>\n<summary>🧰 Tests, CI and other development (%d)</summary>\n\n' "${#development[@]}"
    printf '%s\n' "${development[@]}"
    printf '\n</details>\n'
fi

if [[ -n $previous ]]; then
    printf '\n**Full changelog:** [%s...%s](%s/compare/%s...%s)\n' "$previous" "$tag" "$url" "$previous" "$tag"
else
    printf '\n**Full changelog:** [all commits](%s/commits/%s)\n' "$url" "$tag"
fi

cat <<EOF

<details>
<summary>🔒 SHA-256</summary>

\`\`\`
$(cat "${sums[@]}")
\`\`\`

Check one with \`shasum -a 256 -c setup-yt-dlp.tar.xz.sha256\`, or with \`setup-yt-dlp-standalone.tar.xz.sha256\`.

</details>
EOF
