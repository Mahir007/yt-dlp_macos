#!/bin/zsh -f
#
# setup-yt-dlp-standalone: install yt-dlp_macos, ffmpeg and ffprobe into
# /usr/local/bin without a package manager, and update them with --update.
#
# Needs zsh 5.7.1 or later. macOS 10.15 Catalina ships 5.7.1 as /bin/zsh.
#
# https://github.com/Mahir007/yt-dlp_macos

# Started with sh or bash: run again under zsh. Keep this block POSIX sh,
# since those shells run it before they reach any zsh syntax below.
if [ -z "${ZSH_VERSION-}" ]; then
    if [ -f "$0" ]; then
        exec zsh -f "$0" "$@"
    fi
    echo "setup-yt-dlp-standalone: this script needs zsh. Run it with: zsh setup-yt-dlp-standalone.zsh" >&2
    exit 1
fi

emulate -R zsh
setopt extended_glob no_unset pipe_fail warn_create_global
# ~/.zshenv is still read when run as `zsh setup-yt-dlp-standalone.zsh`.
# Drop any aliases it defined before they can change the code below.
unalias -m '*'

autoload -Uz is-at-least
if ! is-at-least 5.7.1; then
    print -ru2 -- "setup-yt-dlp-standalone: needs zsh 5.7.1 or later, but this is zsh $ZSH_VERSION."
    exit 1
fi

zmodload zsh/zutil      # zparseopts
zmodload zsh/datetime   # EPOCHREALTIME, strftime
zmodload zsh/zselect    # sleeping for a fraction of a second
zmodload -F zsh/files b:zf_mkdir b:zf_rm

# sysctl is in /usr/sbin, which a PATH set by hand can leave out.
path+=(/usr/sbin)

# The release workflow writes the tag's version here, in the copy it
# packages.
typeset -gr SETUP_VERSION=0.0.0-dev

# Name to show in messages. $0 isn't a regular file when the script comes
# from a pipe or a process substitution such as `zsh <(curl ...)`.
if [[ -f $0 ]]; then
    typeset -gr SETUP_PROG=${0:t}
else
    typeset -gr SETUP_PROG=setup-yt-dlp-standalone.zsh
fi

# Where the binaries go. The tests put them somewhere else.
typeset -gr BIN_DIR=${SETUP_YT_DLP_BIN_DIR:-/usr/local/bin}
typeset -gra TOOLS=(yt-dlp_macos ffmpeg ffprobe)

# yt-dlp_macos comes from yt-dlp's releases on GitHub. ffmpeg and ffprobe
# come from martin-riedl.de, whose builds need macOS 12 or later, or on
# older Intel Macs from evermeet.cx, whose builds need 10.13. Neither has a
# build for Apple silicon on macOS 11.
typeset -gr YTDLP_URL=https://github.com/yt-dlp/yt-dlp/releases
typeset -gr RIEDL_URL=https://ffmpeg.martin-riedl.de
typeset -gr EVERMEET_URL=https://evermeet.cx/ffmpeg

# Settings from the command line, filled in by cli_parse.
typeset -gA opts=(
    action   install    # install, update, help or version
    dry_run  0
    verbose  0
    color    auto       # auto or never
)
# The arguments as given, for the log.
typeset -ga setup_args=()

# The Mac, found by preflight: macOS's version, such as 10.15.7, and the
# architecture as martin-riedl.de names it, arm64 or amd64. An Apple silicon
# Mac is arm64 even in a terminal running under Rosetta.
typeset -g mac_version='' mac_arch=''

# ----------------------------------------------------------------------------
# Output
# ----------------------------------------------------------------------------

# Escape sequences by name, empty until ui_init turns colors on.
typeset -gA c=(bold '' dim '' red '' green '' yellow '' blue '' reset '')
# Status symbols and spinner frames, ASCII until ui_init finds a UTF-8 locale.
typeset -gA sym=(ok + fail x skip - step '>' bar '|' more ... to '->')
typeset -ga spinner_frames=('|' / - '\')
# 1 when the output is a terminal that can redraw a line for the spinner.
typeset -gi ui_live=0
# Width of the subject column in step lines.
typeset -gri UI_WIDTH=14

ui_init() {
    if [[ $opts[color] == auto && -t 1 && -z ${NO_COLOR-} && ${TERM-dumb} != dumb ]]; then
        c=(bold $'\e[1m' dim $'\e[2m' red $'\e[31m' green $'\e[32m'
           yellow $'\e[33m' blue $'\e[34m' reset $'\e[0m')
    fi
    if [[ -t 1 && ${TERM-dumb} != dumb ]]; then
        ui_live=1
    fi
    if [[ ${LC_ALL:-${LC_CTYPE:-${LANG-}}} == (#i)*utf(-|)8* ]]; then
        sym=(ok ✓ fail ✗ skip – step ▸ bar │ more … to →)
        spinner_frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    fi
}

ui_header() {
    local note=''
    if (( opts[dry_run] )); then
        note=" ${c[dim]}(dry run: nothing will be changed)${c[reset]}"
    fi
    print -r -- "${c[bold]}yt-dlp standalone setup${c[reset]} ${c[dim]}$SETUP_VERSION${c[reset]}$note"
}

# ui_section TITLE: start a group of steps.
ui_section() {
    print
    print -r -- "${c[bold]}${c[blue]}${sym[step]}${c[reset]} ${c[bold]}$1${c[reset]}"
}

# ui_step COLOR SYMBOL SUBJECT TEXT: print one line of a section, such as
# "  ✓ ffmpeg         installed 9.0.2".
ui_step() {
    print -rf "  %s %-*s %s\n" "${c[$1]}$2${c[reset]}" $UI_WIDTH "$3" "$4"
}

ui_ok()   { ui_step green "$sym[ok]" "$1" "$2" }
ui_fail() { ui_step red "$sym[fail]" "$1" "$2" }
ui_skip() { ui_step dim "$sym[skip]" "$1" "${c[dim]}$2${c[reset]}" }

# ui_detail TEXT: print a dim line under a step.
ui_detail() {
    print -r -- "    ${c[dim]}$1${c[reset]}"
}

# ui_path PATH: print PATH with ~ for the home folder. Unlike ${(D)...},
# this doesn't put a backslash before spaces.
ui_path() {
    local p=$1
    if [[ $p == ${(b)HOME} || $p == ${(b)HOME}/* ]]; then
        p="~${p#${(b)HOME}}"
    fi
    print -r -- $p
}

# ui_duration SECONDS: print "45s" or "2m 5s".
ui_duration() {
    local -i s=$1
    if (( s < 60 )); then
        print -r -- "${s}s"
    else
        print -r -- "$(( s / 60 ))m $(( s % 60 ))s"
    fi
}

ui_warn() {
    print -ru2 -- "${c[yellow]}warning:${c[reset]} $1"
}

ui_error() {
    print -ru2 -- "${c[red]}error:${c[reset]} $1"
}

# die MESSAGE [STATUS]
die() {
    ui_error "$1"
    exit ${2:-1}
}

typeset -gi spinner_pid=0

# spinner_start SUBJECT TEXT: animate a step line until spinner_stop.
spinner_start() {
    print -n $'\e[?25l'
    {
        local -i i=0
        while :; do
            print -nrf "\r  %s %-*s %s" "${c[blue]}${spinner_frames[i % $#spinner_frames + 1]}${c[reset]}" \
                $UI_WIDTH "$1" "$2"
            (( i++ ))
            zselect -t 8
        done
    } &
    spinner_pid=$!
}

spinner_stop() {
    (( spinner_pid )) || return 0
    kill $spinner_pid 2>/dev/null
    wait $spinner_pid 2>/dev/null
    spinner_pid=0
    print -n $'\r\e[K\e[?25h'
}

# ----------------------------------------------------------------------------
# Running commands
# ----------------------------------------------------------------------------

# The log of this run, created by the first step.
typeset -g log_file=''

log_open() {
    [[ -n $log_file ]] && return 0
    local dir=$HOME/Library/Logs/yt-dlp-setup-standalone stamp
    zf_mkdir -p $dir 2>/dev/null || die "couldn't create $(ui_path "$dir")"
    strftime -s stamp %Y%m%d-%H%M%S $EPOCHSECONDS
    log_file=$dir/$stamp.log
    local args=none
    (( $#setup_args )) && args=${(j: :)${(q-)setup_args}}
    print -r -- "yt-dlp standalone setup $SETUP_VERSION, arguments: $args" >$log_file
    # Keep the ten newest logs.
    local -a old=( $dir/*.log(Nom[11,-1]) )
    (( $#old )) && zf_rm -f -- $old
    return 0
}

# log_note TEXT: add a line to the log, for what isn't a step's output.
log_note() {
    log_open
    local stamp
    strftime -s stamp %H:%M:%S $EPOCHSECONDS
    print -r -- "==> [$stamp] $1" >>$log_file
}

# run_step SUBJECT DOING DONE -- COMMAND...
#
# Run COMMAND as one step of a section, as in `run_step ffmpeg installing
# installed -- install_tool ffmpeg`. Shows a spinner on a terminal, or the
# command's output with --verbose, and the end of the output if it fails.
# All output goes to the log. Returns COMMAND's status.
run_step() {
    local subject=$1 doing=$2 done=$3
    [[ ${4-} == -- ]] || die "run_step: missing -- before the command"
    shift 4
    local cmdline=${(j: :)${(q-)@}}

    log_open
    local out=${log_file%.log}.out stamp
    local -F start=$EPOCHREALTIME
    local -i rc
    strftime -s stamp %H:%M:%S $EPOCHSECONDS
    print -r -- "==> [$stamp] $cmdline" >>$log_file

    if (( opts[verbose] )); then
        ui_step blue "$sym[step]" "$subject" "$doing$sym[more]"
        "$@" </dev/null 2>&1 | ui_stream $out
        rc=$?
    else
        (( ui_live )) && spinner_start "$subject" "$doing$sym[more]"
        "$@" </dev/null >$out 2>&1
        rc=$?
        spinner_stop
    fi

    local took=$(ui_duration $(( EPOCHREALTIME - start )))
    print -r -- "$(<$out)" >>$log_file
    print -r -- "==> exit status $rc after $took" >>$log_file
    if (( rc == 0 )); then
        if (( EPOCHREALTIME - start >= 1 )); then
            done+=" ${c[dim]}($took)${c[reset]}"
        fi
        ui_ok "$subject" "$done"
    else
        ui_fail "$subject" failed
        (( opts[verbose] )) || ui_tail "$out"
    fi
    zf_rm -f $out
    return rc
}

# ui_stream FILE: copy stdin to FILE and show it under the current step.
ui_stream() {
    local line
    {
        while IFS= read -r line || [[ -n $line ]]; do
            print -r -- $line >&3
            print -r -- "    ${c[dim]}${sym[bar]} ${line##*$'\r'}${c[reset]}"
        done
    } 3>$1
}

# ui_tail FILE: show the last lines of a failed step's output.
ui_tail() {
    local -a lines=( "${(@f)"$(<$1)"}" )
    # Progress bars redraw their line after a carriage return; keep the last
    # drawing, and drop blank lines.
    lines=( ${${lines##*$'\r'}:#[[:space:]]#} )
    local -i first=$(( $#lines > 10 ? $#lines - 9 : 1 ))
    local line
    for line in ${lines[first,-1]}; do
        ui_detail "$line"
    done
}

# ----------------------------------------------------------------------------
# Administrator access
# ----------------------------------------------------------------------------

typeset -gi sudo_keepalive_pid=0 sudo_asked=0

# sudo_begin REASON: get administrator access before the steps that need
# it, so they can use `sudo -n` behind the spinner. Keeps it fresh until
# the script exits.
sudo_begin() {
    (( sudo_keepalive_pid )) && return 0
    if ! sudo -n -v 2>/dev/null; then
        print -r -- "$1"
        sudo -v -p "Password for %u: " || die "couldn't get administrator access"
        sudo_asked=1
    fi
    {
        while kill -0 $$ 2>/dev/null && sudo -n -v 2>/dev/null; do
            zselect -t 3000
        done
    } &
    sudo_keepalive_pid=$!
}

sudo_end() {
    (( sudo_keepalive_pid )) || return 0
    kill $sudo_keepalive_pid 2>/dev/null
    wait $sudo_keepalive_pid 2>/dev/null
    sudo_keepalive_pid=0
    # Don't leave the terminal with access the script asked for.
    (( sudo_asked )) && sudo -k
    return 0
}

# needs_sudo: succeed if writing to BIN_DIR, or creating it, needs
# administrator access.
needs_sudo() {
    local dir=$BIN_DIR
    while [[ ! -d $dir ]]; do
        dir=${dir:h}
    done
    [[ ! -w $dir ]]
}

# ----------------------------------------------------------------------------
# Versions
# ----------------------------------------------------------------------------

# binary_version FILE TOOL: set REPLY to the version of FILE, a copy of
# TOOL. Fails with 1 if it doesn't run or say its version, or with 2 if it's
# an ffmpeg or ffprobe from somewhere else, such as a build of your own.
binary_version() {
    local file=$1 tool=$2 line
    local -a match mbegin mend
    typeset -g REPLY=''
    if [[ $tool == yt-dlp_macos ]]; then
        line=$($file --version 2>/dev/null) || return 1
        [[ $line == [0-9][0-9.]# ]] || return 1
    else
        # "ffmpeg version 9.0.2-https://www.martin-riedl.de Copyright ...",
        # or "ffmpeg version 9.0.2-tessus ..." from evermeet.cx.
        line=$($file -version 2>/dev/null) || return 1
        line=${line%%$'\n'*}
        [[ $line == (#b)"$tool version "([^-[:space:]]##)-(https://www.martin-riedl.de|tessus)([[:space:]]*|) ]] ||
            return 2
        line=$match[1]
    fi
    REPLY=$line
}

# installed_version TOOL: set REPLY to the version of TOOL in BIN_DIR. Fails
# with 1 if it isn't there, or with 2 if it isn't one this script installs,
# such as Homebrew's ffmpeg linked into /usr/local/bin on an Intel Mac. A
# yt-dlp_macos that doesn't run counts as not there, so it's installed
# again.
installed_version() {
    local file=$BIN_DIR/$1
    typeset -g REPLY=''
    [[ -e $file || -L $file ]] || return 1
    [[ -f $file && ! -L $file ]] || return 2
    binary_version $file $1
}

# tool_source TOOL: print where TOOL comes from on this Mac: ytdlp, riedl or
# evermeet, or nothing when there's no build that runs on it.
tool_source() {
    if [[ $1 == yt-dlp_macos ]]; then
        print ytdlp
    elif is-at-least 12 $mac_version; then
        print riedl
    elif [[ $mac_arch == amd64 ]]; then
        print evermeet
    fi
}

# The latest version of each tool, its download, and the download's
# SHA-256. evermeet.cx publishes GPG signatures but no SHA-256, so its
# downloads have none.
typeset -gA latest=() latest_url=() latest_sha=()
# The sources looked up so far, with 1 for those that worked.
typeset -gA looked_up=()

# lookup SOURCE: find the latest versions at SOURCE, once per run. Fails if
# that didn't work; the log says why.
lookup() {
    if (( ! ${+looked_up[$1]} )); then
        log_note "looking up the latest versions at $1"
        if lookup_$1 2>>$log_file; then
            looked_up[$1]=1
        else
            looked_up[$1]=0
            log_note "couldn't look up the latest versions at $1"
        fi
    fi
    (( looked_up[$1] ))
}

# redirect_of URL: print where URL redirects to.
redirect_of() {
    local to
    to=$(curl -fsS --retry 2 -o /dev/null -w '%{redirect_url}' $1) || return 1
    [[ -n $to ]] || return 1
    print -r -- $to
}

# fetch URL: print what's at URL.
fetch() {
    curl -fsSL --retry 2 $1
}

# sum_for NAME SUMS: print the SHA-256 SUMS lists for NAME. SUMS is in
# shasum's format, a "SHA-256  NAME" line for each file.
sum_for() {
    local -a lines=( ${(M)${(f)2}:#[[:xdigit:]](#c64)[[:space:]]##(\*|)$1} )
    (( $#lines )) || return 1
    print -r -- ${(L)lines[1]%%[[:space:]]*}
}

# found TOOL VERSION URL [SHA-256]: record the latest version of TOOL.
found() {
    latest[$1]=$2
    latest_url[$1]=$3
    latest_sha[$1]=${4-}
    log_note "latest $1: $2 at $3"
}

lookup_ytdlp() {
    local url tag sums sha
    # https://github.com/yt-dlp/yt-dlp/releases/tag/2026.10.26
    url=$(redirect_of $YTDLP_URL/latest) || return 1
    [[ $url == */tag/[^/]## ]] || return 1
    tag=${url:t}
    sums=$(fetch $YTDLP_URL/download/$tag/SHA2-256SUMS) || return 1
    sha=$(sum_for yt-dlp_macos $sums) || return 1
    found yt-dlp_macos $tag $YTDLP_URL/download/$tag/yt-dlp_macos $sha
}

lookup_riedl() {
    local url dir tool sums sha
    # https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2/ffmpeg.zip:
    # ffmpeg and ffprobe sit side by side in a folder for the build.
    url=$(redirect_of $RIEDL_URL/redirect/latest/macos/$mac_arch/release/ffmpeg.zip) || return 1
    dir=${url:h}
    [[ ${dir:t} == <->_?## ]] || return 1
    for tool in ffmpeg ffprobe; do
        sums=$(fetch $dir/$tool.zip.sha256) || return 1
        sha=$(sum_for $tool.zip $sums) || return 1
        found $tool ${${dir:t}#*_} $dir/$tool.zip $sha
    done
}

lookup_evermeet() {
    local tool json version
    local -a match mbegin mend
    local MATCH MBEGIN MEND
    for tool in ffmpeg ffprobe; do
        # JSON, starting {"name":"ffmpeg","type":"release","version":"9.0.2",
        # with the zip at "zip":{"url":"https://...".
        json=$(fetch $EVERMEET_URL/info/$tool/release) || return 1
        [[ $json =~ '"version":"([^"]+)"' ]] || return 1
        version=$match[1]
        [[ $json =~ '"zip":[{]"url":"(https://[^"]+)"' ]] || return 1
        found $tool $version $match[1]
    done
}

# ----------------------------------------------------------------------------
# Installing
# ----------------------------------------------------------------------------

# A temporary folder for the downloads, made by install_run, and whether
# moving them into BIN_DIR needs sudo.
typeset -g work_dir=''
typeset -gi use_sudo=0

# install_tool TOOL: download the latest TOOL, check it, and move it into
# BIN_DIR. Run as a step, so its output goes to the log.
install_tool() {
    local tool=$1 url=$latest_url[$1] sha=$latest_sha[$1] got
    local dir=$work_dir/$tool
    local file=$dir/${url:t}
    zf_mkdir -p $dir || return 1
    print -r -- "Downloading $url"
    curl -fsSL --retry 2 -o $file $url || return 1
    if [[ -n $sha ]]; then
        got=$(shasum -a 256 $file) || return 1
        got=${(L)got%% *}
        if [[ $got != $sha ]]; then
            print -r -- "The download's SHA-256 is $got, but should be $sha."
            return 1
        fi
        print -r -- "SHA-256 $got is right."
    fi
    if [[ $file == *.zip ]]; then
        unzip -oq $file -d $dir/unzipped || return 1
        file=$dir/unzipped/$tool
        if [[ ! -f $file ]]; then
            print -r -- "${url:t} has no $tool in it."
            return 1
        fi
    fi
    chmod 755 $file || return 1
    # Try the new copy before it replaces the old one.
    if ! binary_version $file $tool; then
        print -r -- "The new $tool doesn't run on this Mac."
        return 1
    fi
    if [[ $REPLY != $latest[$tool] ]]; then
        print -r -- "The new $tool says it's version $REPLY, not $latest[$tool]."
        return 1
    fi
    if (( use_sudo )); then
        sudo -n mkdir -p $BIN_DIR && sudo -n mv -f $file $BIN_DIR/$tool
    else
        zf_mkdir -p $BIN_DIR && mv -f $file $BIN_DIR/$tool
    fi
}

# What install_run does with each tool, and the version installed before.
# The plan is one of:
#   current      installed, and the latest if --update checked
#   install      not installed
#   update       installed, but not the latest
#   foreign      not one the script installs, so left alone
#   unsupported  no build runs on this Mac
#   unknown      the latest version couldn't be found
typeset -gA plan=() had=()

# plan_tool TOOL: decide what to do with TOOL, looking up the latest
# version when it's needed.
plan_tool() {
    local tool=$1 source
    local -i rc
    installed_version $tool
    rc=$?
    had[$tool]=$REPLY
    if (( rc == 2 )); then
        plan[$tool]=foreign
        return 0
    fi
    if (( rc == 0 )) && [[ $opts[action] != update ]]; then
        plan[$tool]=current
        return 0
    fi
    source=$(tool_source $tool)
    if [[ -z $source ]]; then
        plan[$tool]=unsupported
        return 0
    fi
    (( ui_live )) && spinner_start $tool "checking$sym[more]"
    lookup $source
    rc=$?
    spinner_stop
    if (( rc )); then
        plan[$tool]=unknown
    elif [[ -z $had[$tool] ]]; then
        plan[$tool]=install
    elif [[ $had[$tool] == $latest[$tool] ]]; then
        plan[$tool]=current
    else
        plan[$tool]=update
    fi
}

# apply_tool TOOL: carry out TOOL's plan, as a step.
apply_tool() {
    local tool=$1 old=$had[$1] new=${latest[$1]-}
    case $plan[$tool] in
        current)
            if [[ $opts[action] == update ]]; then
                ui_ok $tool "up to date ${c[dim]}($old)${c[reset]}"
            else
                ui_ok $tool "already installed ${c[dim]}($old)${c[reset]}"
            fi
            ;;
        foreign)
            ui_skip $tool "left alone: this script didn't install it"
            ;;
        unsupported)
            ui_skip $tool "skipped: on Apple silicon, it needs macOS 12 or later"
            ;;
        unknown)
            ui_fail $tool "couldn't find the latest version"
            problems+=("the latest $tool couldn't be found")
            ;;
        install)
            if (( opts[dry_run] )); then
                ui_skip $tool "would install $new"
            elif ! run_step $tool installing "installed $new" -- install_tool $tool; then
                problems+=("$tool couldn't be installed")
            fi
            ;;
        update)
            if (( opts[dry_run] )); then
                ui_skip $tool "would update $old $sym[to] $new"
            elif ! run_step $tool updating "updated $old $sym[to] $new" -- install_tool $tool; then
                problems+=("$tool couldn't be updated")
            fi
            ;;
    esac
    return 0
}

# What went wrong during the run, for the summary at the end.
typeset -ga problems=()

# install_run: install what's missing, or with --update, also update what's
# out of date, then sum up.
install_run() {
    local tool
    local -F start=$EPOCHREALTIME
    for tool in $TOOLS; do
        plan_tool $tool
    done

    # (Inside (( )), the expansion would match against all of plan's
    # values joined into one string.)
    local -a downloads=( ${(M)${(v)plan}:#(install|update)} )
    if (( ! opts[dry_run] && $#downloads )); then
        if needs_sudo; then
            use_sudo=1
            print
            sudo_begin "Installing into $BIN_DIR needs administrator access."
        fi
        work_dir=$(mktemp -d "${TMPDIR:-/tmp}"/setup-yt-dlp-standalone.XXXXXX) ||
            die "couldn't create a temporary folder"
    fi

    ui_section $BIN_DIR
    for tool in $TOOLS; do
        apply_tool $tool
    done

    local retry="Run the script again to retry."
    [[ $opts[action] == update ]] && retry="Run the script with --update again to retry."
    local -a done=("Start yt-dlp with yt-dlp_macos.")
    if [[ $opts[action] == install && ${(v)plan} == *current* ]]; then
        done+=("To update, run the script with --update.")
    fi
    finish $start $retry $done
}

# finish START RETRY DONE...: end the run that began at START. If there were
# problems, lists them, says how to try again with RETRY, and fails.
# Otherwise prints the DONE lines, the first after "Done in 2m 5s.".
finish() {
    local took=$(ui_duration $(( EPOCHREALTIME - $1 ))) retry=$2 line
    shift 2
    print
    if (( opts[dry_run] )); then
        print -r -- "Dry run finished. Nothing was changed."
    elif (( $#problems )); then
        print -r -- "${c[red]}${sym[fail]}${c[reset]} ${c[bold]}Finished in $took, with problems:${c[reset]}"
        for line in $problems; do
            print -r -- "    $line"
        done
        [[ -n $log_file ]] && print -r -- "  The log has the details: $(ui_path "$log_file")"
        print -r -- "  $retry"
        return 1
    else
        print -r -- "${c[green]}${sym[ok]}${c[reset]} ${c[bold]}Done in $took.${c[reset]} $1"
        shift
        for line; do
            print -r -- "  $line"
        done
    fi
    return 0
}

# ----------------------------------------------------------------------------
# Command line
# ----------------------------------------------------------------------------

cli_usage() {
    print -r -- "\
${c[bold]}Usage:${c[reset]} $SETUP_PROG [options]

Install yt-dlp_macos, ffmpeg and ffprobe into $BIN_DIR, without a
package manager.

${c[bold]}Options:${c[reset]}
  -U, --update     Also update them to the latest versions
  -n, --dry-run    Show what would be done without changing anything
  -v, --verbose    Show the output of the downloads
      --no-color   Don't use colors
  -h, --help       Show this help, then exit
  -V, --version    Show the version, then exit"
}

# cli_fail MESSAGE: report a usage error and exit.
cli_fail() {
    ui_error "$1"
    print -ru2 -- "Run '$SETUP_PROG --help' to see the options."
    exit 2
}

# zparseopts specs. -M files long options under their short name, so
# --update ends up as -U.
typeset -gra CLI_SPEC=(
    'U'    '-update=U'
    'n'    '-dry-run=n'
    'v'    '-verbose=v'
           '-no-color'
    'h'    '-help=h'
    'V'    '-version=V'
)

# cli_parse ARGS...: fill in opts, or exit on a usage error.
cli_parse() {
    local -A parsed
    # zsh 5.7.1's zparseopts has no -F. It stops at the first word it
    # doesn't know and leaves it in argv.
    zparseopts -D -M -A parsed -- $CLI_SPEC
    if (( $# )); then
        local word=$1
        local -a names=( ${${CLI_SPEC%%[:=]*}/#/-} )
        if [[ $word == -*=* ]] && (( ${names[(Ie)${word%%=*}]} )); then
            cli_fail "option '${word%%=*}' doesn't take a value"
        elif [[ $word == -?* ]]; then
            cli_fail "unknown option '$word'"
        fi
        cli_fail "unexpected argument '$word'"
    fi

    if (( ${+parsed[-h]} )); then
        opts[action]=help
        return 0
    elif (( ${+parsed[-V]} )); then
        opts[action]=version
        return 0
    fi
    (( ${+parsed[-U]} )) && opts[action]=update
    (( ${+parsed[-n]} )) && opts[dry_run]=1
    (( ${+parsed[-v]} )) && opts[verbose]=1
    (( ${+parsed[--no-color]} )) && opts[color]=never
    return 0
}

# ----------------------------------------------------------------------------
# Checks before changing anything
# ----------------------------------------------------------------------------

# preflight: check the script can run here, and fill in mac_version and
# mac_arch.
preflight() {
    if (( EUID == 0 )); then
        die "don't run this script as root or with sudo; it asks for your password when it needs it"
    fi
    if (( ! $+commands[sw_vers] )); then
        die "this script only works on macOS"
    fi
    mac_version=$(sw_vers -productVersion 2>/dev/null)
    if [[ $mac_version != <->(.<->)# ]]; then
        die "couldn't tell which version of macOS this is"
    fi
    if ! is-at-least 10.15 $mac_version; then
        ui_warn "macOS $mac_version is older than macOS 10.15, the oldest version this script supports"
    fi
    if [[ $(sysctl -n hw.optional.arm64 2>/dev/null) == 1 ]]; then
        mac_arch=arm64
    else
        mac_arch=amd64
    fi
}

# ----------------------------------------------------------------------------
# Exit and interrupts
# ----------------------------------------------------------------------------

# Defined at the top level, so they apply to the whole script and not to a
# single function. Neither runs in subshells or background jobs.
TRAPEXIT() {
    spinner_stop
    sudo_end
    [[ -n $log_file ]] && zf_rm -f ${log_file%.log}.out
    [[ -n $work_dir ]] && zf_rm -rf -- $work_dir
}

TRAPINT() {
    if (( spinner_pid )); then
        spinner_stop
    else
        print
    fi
    ui_error "interrupted"
    exit 130
}

TRAPTERM() {
    exit 143
}

main() {
    setup_args=("$@")
    # Decide on colors before parsing, so usage errors respect --no-color.
    (( ${argv[(Ie)--no-color]} )) && opts[color]=never
    ui_init
    cli_parse "$@"

    case $opts[action] in
        help)    cli_usage; return 0 ;;
        version) print -r -- "setup-yt-dlp-standalone $SETUP_VERSION"; return 0 ;;
    esac

    preflight
    ui_header
    if [[ $mac_arch == arm64 ]]; then
        print -r -- "macOS $mac_version on Apple silicon"
    else
        print -r -- "macOS $mac_version on Intel"
    fi
    install_run
}

# Run only when executed, not when sourced: the tests source this file to
# call its functions.
if [[ $ZSH_EVAL_CONTEXT == toplevel ]]; then
    main "$@"
fi
