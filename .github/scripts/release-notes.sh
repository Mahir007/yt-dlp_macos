#!/bin/bash
# release-notes.sh TAG REPO SHA256FILE...: print the release notes for TAG,
# in Markdown: how to install it, the commits since the previous release
# grouped by their Conventional Commits type, and the archives' checksums.
# REPO is owner/name.
#
# The tests run this with macOS's /bin/bash, 3.2, so it keeps to bash 3.2.
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

subject_re='^([a-zA-Z]+)(\(([^)]+)\))?(!)?: (.+)$'
breaking_re='^BREAKING[ -]CHANGE: (.*)$'
footer_re='^[A-Za-z-]+(: | #)'
# git revert names the reverted commit in the body and quotes its subject in
# the revert's subject, which may be reworded to revert: <subject>.
reverts_re='This reverts commit ([0-9a-f]{7,40})'
revert_subject_re='^Revert "(.+)"$'

# sentence TEXT: print TEXT with its first word capitalised, if that is a
# plain word, which a file name isn't.
sentence() {
    if [[ $1 =~ ^[a-z]+([[:space:]]|$) ]]; then
        printf '%s%s' "$(printf '%s' "${1:0:1}" | tr '[:lower:]' '[:upper:]')" "${1:1}"
    else
        printf '%s' "$1"
    fi
}

# footer BODY: print the text of BODY's BREAKING CHANGE footer on one line.
# The footer runs to a blank line or the next footer, such as Co-Authored-By.
footer() {
    local line text='' found=0
    local -a words=()
    while IFS= read -r line; do
        line=${line%$'\r'}
        if ((found)); then
            if [[ -z ${line//[[:space:]]/} || $line =~ $footer_re ]]; then
                break
            fi
            text+=" $line"
        elif [[ $line =~ $breaking_re ]]; then
            found=1
            text=${BASH_REMATCH[1]}
        fi
    done <<<"$1"
    read -r -a words <<<"$text" || true
    printf '%s' "${words[*]+"${words[*]}"}"
}

# Each commit in the range, oldest first, split into its Conventional Commits
# parts. A subject that doesn't follow them has no type.
declare -a shas=() subjects=() types=() scopes=() descriptions=() breaking=()
declare -a reverts_sha=() reverts_subject=() skip=()
while IFS= read -r -d $'\x1e' record; do
    record=${record#$'\n'}
    sha=${record%%$'\x1f'*}
    rest=${record#*$'\x1f'}
    subject=${rest%%$'\x1f'*}
    body=${rest#*$'\x1f'}

    type='' scope='' description=$subject breaking_text=''
    if [[ $subject =~ $subject_re ]]; then
        type=${BASH_REMATCH[1]} scope=${BASH_REMATCH[3]} bang=${BASH_REMATCH[4]}
        description=${BASH_REMATCH[5]}
        type=$(printf '%s' "$type" | tr '[:upper:]' '[:lower:]')
        text=$(footer "$body")
        if [[ -n $text ]]; then
            breaking_text="$(sentence "$description"). $text"
        elif [[ -n $bang ]]; then
            breaking_text=$description
        fi
    fi

    reverted_sha='' reverted_subject=''
    if [[ $body =~ $reverts_re ]]; then
        reverted_sha=${BASH_REMATCH[1]}
    fi
    if [[ $subject =~ $revert_subject_re ]]; then
        reverted_subject=${BASH_REMATCH[1]}
    elif [[ $type == revert ]]; then
        reverted_subject=$description
    fi

    shas+=("$sha")
    subjects+=("$subject")
    types+=("$type")
    scopes+=("$scope")
    descriptions+=("$description")
    breaking+=("$breaking_text")
    reverts_sha+=("$reverted_sha")
    reverts_subject+=("$reverted_subject")
    skip+=(0)
done < <(git log --no-merges --reverse --format='%H%x1f%s%x1f%b%x1e' "$range")
count=${#shas[@]}

# Leave out each commit that a later one reverts, and the revert. A revert of
# a commit from an earlier release stays.
for ((i = 0; i < count; i++)); do
    [[ -n ${reverts_sha[i]}${reverts_subject[i]} ]] || continue
    for ((j = 0; j < i; j++)); do
        if ((skip[j])); then
            continue
        elif [[ -n ${reverts_sha[i]} ]]; then
            [[ ${shas[j]} == "${reverts_sha[i]}"* ]] || continue
        else
            [[ ${subjects[j]} == "${reverts_subject[i]}" ]] || continue
        fi
        skip[i]=1
        skip[j]=1
        break
    done
done

# entry INDEX [TEXT]: print a list item with a link to the commit. Without
# TEXT, it's the commit's subject.
entry() {
    local text=${2-}
    if [[ -z $text ]]; then
        text=${subjects[$1]}
    else
        text=$(sentence "$text")
        [[ -z ${scopes[$1]} ]] || text="**${scopes[$1]}:** $text"
    fi
    printf '%s\n' "- $text ([\`${shas[$1]:0:7}\`]($url/commit/${shas[$1]}))"
}

declare -a new=() fixes=() performance=() docs=() breaks=() other=()
untyped=0
for ((i = 0; i < count; i++)); do
    if ((skip[i])); then
        continue
    elif [[ -n ${breaking[i]} ]]; then
        breaks+=("$(entry "$i" "${breaking[i]}")")
        continue
    fi
    case ${types[i]} in
        feat) new+=("$(entry "$i" "${descriptions[i]}")") ;;
        fix) fixes+=("$(entry "$i" "${descriptions[i]}")") ;;
        perf) performance+=("$(entry "$i" "${descriptions[i]}")") ;;
        # Contributor docs are for people working on the scripts, not using them.
        docs)
            if [[ ${scopes[i]} == contributing ]]; then
                other+=("$(entry "$i")")
            else
                docs+=("$(entry "$i" "${descriptions[i]}")")
            fi
            ;;
        '')
            untyped=1
            other+=("$(entry "$i")")
            ;;
        *) other+=("$(entry "$i")") ;;
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

section "⚠️ Breaking changes" "${breaks[@]+"${breaks[@]}"}"
section "✨ Features" "${new[@]+"${new[@]}"}"
section "🐛 Fixes" "${fixes[@]+"${fixes[@]}"}"
section "⚡ Performance" "${performance[@]+"${performance[@]}"}"
section "📖 Documentation" "${docs[@]+"${docs[@]}"}"
# A commit that doesn't follow Conventional Commits may still change the scripts.
if ((${#breaks[@]} + ${#new[@]} + ${#fixes[@]} + ${#performance[@]} + ${#docs[@]} == 0 && !untyped)); then
    printf '\nNo user-facing changes.\n'
fi
if ((${#other[@]})); then
    printf '\n<details>\n<summary>🧰 Other changes (%d)</summary>\n\n' "${#other[@]}"
    printf '%s\n' "${other[@]}"
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
