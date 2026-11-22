#!/bin/bash
# release-notes.sh TAG REPO SHA256FILE...: print the release notes for TAG, in
# Markdown: the tag's summary, a download table, the commits since the
# previous release grouped by their Conventional Commits type, and the
# checksums. REPO is owner/name, and the SHA256FILEs are the release's .sha256
# files, which name its archives.
#
# The tests run this with macOS's /bin/bash, 3.2, so it keeps to bash 3.2.
set -euo pipefail

tag=$1
repo=$2
sums=("${@:3}")
version=${tag#v}
url=https://github.com/$repo
nl=$'\n'

# The files a release has: a glob for the name, what the file is for, and its
# system, in the order of the download table.
file_globs=(setup-yt-dlp.tar.xz setup-yt-dlp-standalone.tar.xz)
file_labels=("macOS, with Homebrew or MacPorts" "macOS, without a package manager")
file_systems=(macOS macOS)

# The command that checks the downloads on each system, in the order they're
# listed. The backticks and $ are Markdown and PowerShell.
# shellcheck disable=SC2016
check_commands=(
    'macOS: `shasum -a 256 -c *.sha256`'
    'Linux: `sha256sum -c *.sha256`'
    'Android: `sha256sum -c *.sha256`'
    'Windows, in PowerShell: `Get-ChildItem *.sha256 | ForEach-Object { $hash, $file = (Get-Content $_.FullName) -split '"'"'\s+'"'"'; "${file}: $((Get-FileHash $file).Hash -eq $hash)" }`'
)
check_systems=(macOS Linux Android Windows)

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
plain_word_re="^[a-z]+('[a-z]+)?([[:space:]]|$)"
heading_re='^#{2,3} +(.+)$'
install_re='quick ?start|install|download'
# git revert names the reverted commit in the body and quotes its subject in
# the revert's subject, which may be reworded to revert: <subject>.
reverts_re='This reverts commit ([0-9a-f]{7,40})'
revert_subject_re='^Revert "(.+)"$'

# sentence TEXT: print TEXT with its first word capitalised, if that is a
# plain word, which a file name isn't.
sentence() {
    if [[ $1 =~ $plain_word_re ]]; then
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

# tag_message: print the tag's message without its first line and its
# signature, if it's an annotated tag. For a lightweight tag, for-each-ref
# would give the tagged commit's message.
tag_message() {
    [[ $(git for-each-ref --format='%(objecttype)' "refs/tags/$tag") == tag ]] || return 0
    git for-each-ref --format='%(contents)' "refs/tags/$tag" | sed -e 1d -e '/^-----BEGIN /,$d' | sed '/./,$!d'
}

# install_heading README: print the first ## or ### heading about a quick
# start, installing or downloading.
install_heading() {
    local line text fenced=0
    while IFS= read -r line; do
        line=${line%$'\r'}
        if [[ $line == '```'* ]]; then
            fenced=$((1 - fenced))
        elif ((!fenced)) && [[ $line =~ $heading_re ]]; then
            text=$(printf '%s' "${BASH_REMATCH[1]}" | sed 's/[ #]*$//')
            if [[ $(printf '%s' "$text" | tr '[:upper:]' '[:lower:]') =~ $install_re ]]; then
                printf '%s' "$text"
                return
            fi
        fi
    done <<<"$1"
}

# anchor HEADING: print the id GitHub gives a heading.
anchor() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9_ -]//g' -e 's/ /-/g'
}

# The archives the .sha256 files name, in the order of file_globs.
declare -a dl_names=() dl_labels=() dl_systems=() dl_lines=()
sorted=''
for path in "${sums[@]+"${sums[@]}"}"; do
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}
        [[ -n ${line//[[:space:]]/} ]] || continue
        name=${line#*[[:space:]]}
        name=${name#"${name%%[! ]*}"}
        name=${name#\*}
        found=-1
        for ((i = 0; i < ${#file_globs[@]}; i++)); do
            # shellcheck disable=SC2053 # the glob is a pattern
            if [[ $name == ${file_globs[i]} ]]; then
                found=$i
                break
            fi
        done
        if ((found < 0)); then
            echo "error: $name matches none of the files in file_globs" >&2
            exit 1
        fi
        sorted+="$(printf '%03d' "$found")"$'\t'"$name"$'\t'"$line"$'\n'
    done <"$path"
done
while IFS=$'\t' read -r order name line; do
    [[ -n $order ]] || continue
    i=$((10#$order))
    dl_names+=("$name")
    dl_labels+=("${file_labels[i]}")
    dl_systems+=("${file_systems[i]}")
    dl_lines+=("$line")
done < <(printf '%s' "$sorted" | LC_ALL=C sort -t $'\t' -k1,1 -k2,2)

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

# part TEXT: print a part of the notes, after a blank line if one came before.
started=0
part() {
    ((!started)) || printf '\n'
    started=1
    printf '%s\n' "$1"
}

# section TITLE LINE...: add a group of commits to the changes, if it has any.
changes="## What's changed"
section() {
    local title=$1
    shift
    (($#)) || return 0
    changes+="$nl$nl### $title$nl$nl$(printf '%s\n' "$@")"
}

if [[ $version == *-* ]]; then
    part "> [!WARNING]$nl> This is a pre-release, for trying things out before ${version%%-*} is final. Please report problems in [Issues]($url/issues)."
fi
message=$(tag_message)
[[ -z $message ]] || part "$message"

download="## Download"
if ((${#dl_names[@]})); then
    download+="$nl$nl| File | For |$nl| --- | --- |"
    for ((i = 0; i < ${#dl_names[@]}; i++)); do
        download+="$nl| [${dl_names[i]}]($url/releases/download/$tag/${dl_names[i]}) | ${dl_labels[i]} |"
    done
fi
readme_link=$url/blob/$tag/README.md
heading=$(install_heading "$(git show "$tag:README.md" 2>/dev/null || true)")
if [[ -n $heading ]]; then
    download+="$nl${nl}For how to install it, see [$heading]($readme_link#$(anchor "$heading")) in the README."
else
    download+="$nl${nl}For how to install it, see the [README]($readme_link)."
fi
part "$download"

section "⚠️ Breaking changes" "${breaks[@]+"${breaks[@]}"}"
section "✨ Features" "${new[@]+"${new[@]}"}"
section "🐛 Fixes" "${fixes[@]+"${fixes[@]}"}"
section "⚡ Performance" "${performance[@]+"${performance[@]}"}"
section "📖 Documentation" "${docs[@]+"${docs[@]}"}"
# A commit that doesn't follow Conventional Commits may still change the scripts.
if ((${#breaks[@]} + ${#new[@]} + ${#fixes[@]} + ${#performance[@]} + ${#docs[@]} == 0 && !untyped)); then
    changes+="$nl${nl}No user-facing changes."
fi
if ((${#other[@]})); then
    changes+="$nl$nl<details>$nl<summary>🧰 Other changes (${#other[@]})</summary>$nl$nl$(printf '%s\n' "${other[@]}")$nl$nl</details>"
fi
if [[ -n $previous ]]; then
    changes+="$nl$nl**Full changelog:** [$previous...$tag]($url/compare/$previous...$tag)"
else
    changes+="$nl$nl**Full changelog:** [all commits]($url/commits/$tag)"
fi
part "$changes"

if ((${#dl_names[@]})); then
    block="<details>$nl<summary>🔒 SHA-256</summary>$nl$nl\`\`\`"
    for line in "${dl_lines[@]}"; do
        block+="$nl$line"
    done
    block+="$nl\`\`\`$nl${nl}To check your downloads, put them and their \`.sha256\` files in a folder of their own, and run the command for your system there. Delete older copies first, so your browser doesn't rename the new ones.$nl"
    for ((i = 0; i < ${#check_systems[@]}; i++)); do
        for system in "${dl_systems[@]}"; do
            if [[ $system == "${check_systems[i]}" ]]; then
                block+="$nl- ${check_commands[i]}"
                break
            fi
        done
    done
    part "$block$nl$nl</details>"
fi
