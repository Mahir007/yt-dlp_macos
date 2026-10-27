#!/bin/zsh -f
#
# setup-yt-dlp: install yt-dlp and its dependencies on macOS with Homebrew
# or MacPorts, and remove them again with --uninstall.
#
# Needs zsh 5.8 or later. macOS 12 Monterey ships 5.8 as /bin/zsh.
#
# https://github.com/Mahir007/yt-dlp_macos

# Started with sh or bash: run again under zsh. Keep this block POSIX sh,
# since those shells run it before they reach any zsh syntax below.
if [ -z "${ZSH_VERSION-}" ]; then
    if [ -f "$0" ]; then
        exec zsh -f "$0" "$@"
    fi
    echo "setup-yt-dlp: this script needs zsh. Run it with: zsh setup-yt-dlp.zsh" >&2
    exit 1
fi

emulate -R zsh
setopt extended_glob no_unset pipe_fail warn_create_global
# ~/.zshenv is still read when run as `zsh setup-yt-dlp.zsh`. Drop any
# aliases it defined before they can change the code below.
unalias -m '*'

autoload -Uz is-at-least
if ! is-at-least 5.8; then
    print -ru2 -- "setup-yt-dlp: needs zsh 5.8 or later, but this is zsh $ZSH_VERSION."
    exit 1
fi

zmodload zsh/zutil      # zparseopts
zmodload zsh/datetime   # EPOCHREALTIME, strftime
zmodload zsh/zselect    # sleeping for a fraction of a second
zmodload -F zsh/files b:zf_mkdir b:zf_mv b:zf_rm b:zf_rmdir

# The release workflow writes the tag's version here, in the copy it
# packages.
typeset -gr SETUP_VERSION=0.0.0-dev

# Name to show in messages. $0 isn't a regular file when the script comes
# from a pipe or a process substitution such as `zsh <(curl ...)`.
if [[ -f $0 ]]; then
    typeset -gr SETUP_PROG=${0:t}
else
    typeset -gr SETUP_PROG=setup-yt-dlp.zsh
fi

# Settings from the command line, filled in by cli_parse.
typeset -gA opts=(
    action   install    # install, uninstall, status, help or version
    manager  ''         # homebrew or macports; empty means detect
    dry_run  0
    yes      0
    verbose  0
    color    auto       # auto or never
)
# The arguments as given, for the log.
typeset -ga setup_args=()

# ----------------------------------------------------------------------------
# Output
# ----------------------------------------------------------------------------

# Escape sequences by name, empty until ui_init turns colors on.
typeset -gA c=(bold '' dim '' red '' green '' yellow '' blue '' reset '')
# Status symbols and spinner frames, ASCII until ui_init finds a UTF-8 locale.
typeset -gA sym=(ok + fail x skip - step '>' bar '|' more ...)
typeset -ga spinner_frames=('|' / - '\')
# 1 when the output is a terminal that can redraw a line for the spinner.
typeset -gi ui_live=0
# Width of the subject column in step lines.
typeset -gri UI_WIDTH=18

ui_init() {
    if [[ $opts[color] == auto && -t 1 && -z ${NO_COLOR-} && ${TERM-dumb} != dumb ]]; then
        c=(bold $'\e[1m' dim $'\e[2m' red $'\e[31m' green $'\e[32m'
           yellow $'\e[33m' blue $'\e[34m' reset $'\e[0m')
    fi
    if [[ -t 1 && ${TERM-dumb} != dumb ]]; then
        ui_live=1
    fi
    if [[ ${LC_ALL:-${LC_CTYPE:-${LANG-}}} == (#i)*utf(-|)8* ]]; then
        sym=(ok ✓ fail ✗ skip – step ▸ bar │ more …)
        spinner_frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    fi
}

ui_header() {
    local note=''
    if (( opts[dry_run] )); then
        note=" ${c[dim]}(dry run: nothing will be changed)${c[reset]}"
    fi
    print -r -- "${c[bold]}yt-dlp setup${c[reset]} ${c[dim]}$SETUP_VERSION${c[reset]}$note"
}

# ui_section TITLE: start a group of steps.
ui_section() {
    print
    print -r -- "${c[bold]}${c[blue]}${sym[step]}${c[reset]} ${c[bold]}$1${c[reset]}"
}

# ui_step COLOR SYMBOL SUBJECT TEXT: print one line of a section, such as
# "  ✓ ffmpeg             installed".
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
    local dir=$HOME/Library/Logs/yt-dlp-setup stamp
    zf_mkdir -p $dir 2>/dev/null || die "couldn't create ${(D)dir}"
    strftime -s stamp %Y%m%d-%H%M%S $EPOCHSECONDS
    log_file=$dir/$stamp.log
    local args=none
    (( $#setup_args )) && args=${(j: :)${(q-)setup_args}}
    print -r -- "yt-dlp setup $SETUP_VERSION, arguments: $args" >$log_file
    # Keep the ten newest logs.
    local -a old=( $dir/*.log(Nom[11,-1]) )
    (( $#old )) && zf_rm -f -- $old
    return 0
}

# log_note TEXT: add a line to the log, for changes that aren't commands.
log_note() {
    log_open
    local stamp
    strftime -s stamp %H:%M:%S $EPOCHSECONDS
    print -r -- "==> [$stamp] $1" >>$log_file
}

# run_step SUBJECT DOING DONE -- COMMAND...
#
# Run COMMAND as one step of a section, as in `run_step ffmpeg installing
# installed -- brew install ffmpeg`. Shows a spinner on a terminal, or the
# command's output with --verbose, and the end of the output if it fails.
# All output goes to the log. Returns COMMAND's status.
run_step() {
    local subject=$1 doing=$2 done=$3
    [[ ${4-} == -- ]] || die "run_step: missing -- before the command"
    shift 4
    local cmdline=${(j: :)${(q-)@}}

    if (( opts[dry_run] )); then
        ui_skip "$subject" "would run: $cmdline"
        return 0
    fi

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
    (( sudo_keepalive_pid || opts[dry_run] )) && return 0
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

# ----------------------------------------------------------------------------
# Asking questions
# ----------------------------------------------------------------------------

# ui_can_ask: succeed if there's a terminal to ask questions on. When the
# script is piped in (curl ... | zsh), stdin is the script itself, so the
# questions go to /dev/tty.
ui_can_ask() {
    [[ -t 0 ]] || { : </dev/tty } 2>/dev/null
}

# ui_read NAME: read a line from the terminal into the variable NAME.
ui_read() {
    if [[ -t 0 ]]; then
        read -r $1
    else
        read -r $1 </dev/tty
    fi
}

# ui_choose QUESTION CHOICE...: ask which choice to use, and set REPLY to
# its number. The first choice is the default, used with --yes or on Enter.
ui_choose() {
    local question=$1 answer
    shift
    if (( opts[yes] )); then
        typeset -g REPLY=1
        return 0
    fi
    print -r -- "$question"
    local -i i
    for (( i = 1; i <= $#; i++ )); do
        print -r -- "  $i) $argv[i]"
    done
    while :; do
        print -rn -- "Choose 1-$# [1]: "
        if ! ui_read answer; then
            print
            die "no answer given"
        fi
        [[ -z $answer ]] && answer=1
        [[ $answer == <-> ]] && (( answer >= 1 && answer <= $# )) && break
    done
    typeset -g REPLY=$answer
}

# ui_confirm QUESTION: ask a yes or no question, No being the default.
# Succeeds on yes, which --yes answers without asking.
ui_confirm() {
    local answer
    (( opts[yes] )) && return 0
    while :; do
        print -rn -- "$1 [y/N] "
        if ! ui_read answer; then
            print
            die "no answer given"
        fi
        case ${(L)answer} in
            y | yes) return 0 ;;
            n | no | '') return 1 ;;
        esac
    done
}

# ----------------------------------------------------------------------------
# Package managers
# ----------------------------------------------------------------------------

typeset -grA PM_TITLE=(homebrew Homebrew macports MacPorts)
typeset -grA PM_COMMAND=(homebrew brew macports port)
# The chosen manager's prefix, such as /opt/homebrew, and version. Set by
# pm_init.
typeset -g pm_prefix='' pm_version=''

# pm_select: settle opts[manager], asking if both managers are installed.
pm_select() {
    local -a found=()
    local name
    for name in homebrew macports; do
        (( $+commands[$PM_COMMAND[$name]] )) && found+=($name)
    done

    if [[ -n $opts[manager] ]]; then
        if (( ! ${found[(Ie)$opts[manager]]} )); then
            die "$PM_TITLE[$opts[manager]] isn't installed: there's no '$PM_COMMAND[$opts[manager]]' command"
        fi
    elif (( $#found == 1 )); then
        opts[manager]=$found[1]
    elif (( $#found == 2 )); then
        if (( ! opts[yes] )) && ! ui_can_ask; then
            die "both Homebrew and MacPorts are installed; choose one with --manager"
        fi
        ui_choose "Both Homebrew and MacPorts are installed. Which one do you want to use?" \
            "Homebrew (recommended)" MacPorts
        local -a choices=(homebrew macports)
        opts[manager]=$choices[REPLY]
    else
        ui_error "neither Homebrew nor MacPorts is installed"
        print -ru2 -- "
Install one of them, then run this script again:
  1. Install Apple's command line tools: xcode-select --install
  2. Install Homebrew (recommended):
       https://github.com/Homebrew/brew/releases/latest
     or the MacPorts release for your version of macOS:
       https://github.com/macports/macports-base/releases/latest"
        exit 1
    fi
}

# pm_init: get the chosen manager ready to use.
pm_init() {
    # The command is PREFIX/bin/brew or PREFIX/bin/port. Not resolving
    # symlinks matters: /opt/homebrew/bin/brew links into
    # /opt/homebrew/Homebrew.
    local cmd=$commands[$PM_COMMAND[$opts[manager]]]
    pm_prefix=${cmd:h:h}
    case $opts[manager] in
        homebrew)
            export HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_ASK=1
            # The first line is "Homebrew 4.6.3".
            local -a lines=( ${(f)"$(brew --version 2>/dev/null)"} )
            pm_version=${lines[1]-}
            pm_version=${pm_version#Homebrew }
            ;;
        macports)
            # "Version: 2.10.5"
            pm_version=$(port version 2>/dev/null)
            pm_version=${pm_version#Version: }
            ;;
    esac
}

# pkg_version NAME: print the installed version of package NAME, or fail if
# it isn't installed.
pkg_version() { ${opts[manager]}_version "$@" }

# pkg_install NAME [ARGS...]: install package NAME as a step. ARGS go to
# the manager, such as MacPorts variants.
pkg_install() { ${opts[manager]}_install "$@" }

# pkg_uninstall NAME: uninstall package NAME as a step.
pkg_uninstall() { ${opts[manager]}_uninstall "$@" }

# pkg_uninstall_dependencies NAME...: uninstall packages that came along as
# dependencies, as one step.
pkg_uninstall_dependencies() { ${opts[manager]}_uninstall_dependencies "$@" }

# pkg_list: print every installed package, one per line.
pkg_list() { ${opts[manager]}_list }

# pkg_installed_name NAME: print the name package NAME is installed under,
# such as python@3.15 for Homebrew's python3.
pkg_installed_name() { ${opts[manager]}_installed_name "$@" }

# pkg_unneeded: print the packages installed as dependencies that nothing
# installed needs any more, one per line.
pkg_unneeded() { ${opts[manager]}_unneeded }

homebrew_version() {
    # "ffmpeg 7.1_4", or "python@3.15 3.15.1" for the alias python3.
    local -a words=( ${=$(brew list --formula --versions $1 2>/dev/null)} )
    (( $#words > 1 )) || return 1
    print -r -- $words[-1]
}

homebrew_install() {
    run_step "$1" installing installed -- brew install --formula "$@"
}

homebrew_uninstall() {
    run_step "$1" uninstalling uninstalled -- brew uninstall --formula $1
}

homebrew_uninstall_dependencies() {
    run_step dependencies uninstalling "$# uninstalled" -- brew uninstall --formula "$@"
}

homebrew_installed_name() {
    local -a words=( ${=$(brew list --formula --versions $1 2>/dev/null)} )
    print -r -- ${words[1]:-$1}
}

homebrew_list() {
    brew list --formula -1 2>/dev/null
    return 0
}

homebrew_unneeded() {
    # "==> Would autoremove 2 unneeded formulae:", then a name per line.
    # This counts what would become unneeded once those go.
    local line
    for line in ${(f)"$(brew autoremove --dry-run 2>/dev/null)"}; do
        [[ $line == '==>'* ]] || print -r -- $line
    done
    return 0
}

macports_version() {
    # "  ffmpeg @7.1_0+gpl2 (active)". An inactive port counts as not
    # installed: installing it again activates it.
    local line
    local -a match mbegin mend
    for line in ${(f)"$(port -q installed $1 2>/dev/null)"}; do
        if [[ $line == (#b)[[:space:]]#$1' @'([^+[:space:]]##)*'(active)'* ]]; then
            print -r -- $match[1]
            return 0
        fi
    done
    return 1
}

macports_install() {
    sudo_begin "MacPorts needs administrator access to install packages."
    run_step "$1" installing installed -- sudo -n port -N install "$@"
}

macports_uninstall() {
    sudo_begin "MacPorts needs administrator access to remove packages."
    run_step "$1" uninstalling uninstalled -- sudo -n port -N uninstall $1
}

macports_uninstall_dependencies() {
    sudo_begin "MacPorts needs administrator access to remove packages."
    run_step dependencies uninstalling "$# uninstalled" -- sudo -n port -N uninstall "$@"
}

macports_installed_name() {
    print -r -- $1
}

macports_list() {
    local line
    local -a match mbegin mend
    for line in ${(f)"$(port -q installed 2>/dev/null)"}; do
        # "  ffmpeg @7.1_0+gpl2 (active)"
        if [[ $line == (#b)[[:space:]]#([^[:space:]]##)' @'*'(active)'* ]]; then
            print -r -- $match[1]
        fi
    done
    return 0
}

macports_unneeded() {
    # "py314-pip   @26.2.2_0". Unlike Homebrew's list, this doesn't count
    # what would become unneeded once those go.
    local line
    for line in ${(f)"$(port -q echo leaves 2>/dev/null)"}; do
        print -r -- ${${line##[[:space:]]#}%%[[:space:]]*}
    done
    return 0
}

# macports_python: print the newest active python3NN port, such as python314.
macports_python() {
    local line
    local -a names=() match mbegin mend
    for line in ${(f)"$(port -q installed 2>/dev/null)"}; do
        # "  python314 @3.14.0_0 (active)"
        if [[ $line == (#b)[[:space:]]#(python3<->)' @'*'(active)'* ]]; then
            names+=($match[1])
        fi
    done
    (( $#names )) || return 1
    # Sort by the number in the name, highest first: python310 > python39.
    print -r -- ${${(On)names}[1]}
}

# Each `port select` group's choice before this run changed it, such as
# (python3 none). Uninstalling puts these back.
typeset -gA port_select_before=()

# macports_select GROUP TARGET [DONE]: point the `port select` group GROUP,
# such as python3, at TARGET, as a step. DONE is what the step says after.
macports_select() {
    local group=$1 target=$2 done=${3:-now $2} current
    # "The currently selected version for 'python3' is 'python314'."
    current=$(port select --show $group 2>/dev/null)
    current=${${current%\'*}##*\'}
    if [[ $current == $target ]]; then
        ui_ok "$group" "already $target"
        return 0
    fi
    port_select_before[$group]=${current:-none}
    sudo_begin "MacPorts needs administrator access to change which Python it uses."
    run_step "$group" selecting "$done" -- sudo -n port select --set "$group" "$target"
}

# macports_select_python: make python and python3, and pip and pip3 when
# py-pip is installed, run MacPorts' newest Python, as steps.
macports_select_python() {
    local py group
    local -i rc=0
    if ! py=$(macports_python); then
        ui_skip python "no MacPorts Python to select"
        return 0
    fi
    for group in python python3; do
        macports_select "$group" "$py" || rc=1
    done
    if pkg_version py-pip >/dev/null; then
        for group in pip pip3; do
            macports_select "$group" "pip${py#python}" || rc=1
        done
    fi
    rehash
    return rc
}

# With Homebrew, yt-dlp's Python packages go into the user's site-packages
# of Homebrew's Python. Homebrew marks that Python as externally managed,
# hence --break-system-packages.
pip_version() {
    local line
    for line in ${(f)"$($pm_prefix/bin/python3 -m pip show $1 2>/dev/null)"}; do
        if [[ $line == 'Version: '* ]]; then
            print -r -- ${line#Version: }
            return 0
        fi
    done
    return 1
}

pip_install() {
    run_step "$1" installing installed -- \
        $pm_prefix/bin/python3 -m pip install --user --break-system-packages $1
}

pip_uninstall() {
    run_step "$1" uninstalling uninstalled -- \
        $pm_prefix/bin/python3 -m pip uninstall --yes --break-system-packages $1
}

# pip_required_by NAME: print the installed packages that need NAME, one per
# line.
pip_required_by() {
    local line
    for line in ${(f)"$($pm_prefix/bin/python3 -m pip show $1 2>/dev/null)"}; do
        # "Required-by: requests, yt-dlp-ejs"
        if [[ $line == 'Required-by:'* ]]; then
            line=${line#Required-by:}
            print -rl -- ${(s:,:)line//[[:space:]]/}
            return 0
        fi
    done
    return 0
}

# pip_user_bin: print where pip --user puts commands for Homebrew's Python,
# such as /Users/me/Library/Python/3.15/bin.
pip_user_bin() {
    local base
    base=$($pm_prefix/bin/python3 -m site --user-base 2>/dev/null)
    [[ -n $base ]] || return 1
    print -r -- $base/bin
}

# ----------------------------------------------------------------------------
# The zsh startup file
# ----------------------------------------------------------------------------

# The script's lines in ~/.zshrc go between these markers.
typeset -gr RC_BEGIN='# >>> setup-yt-dlp >>>'
typeset -gr RC_NOTE='# Added by setup-yt-dlp.zsh. Its --uninstall option removes these lines.'
typeset -gr RC_END='# <<< setup-yt-dlp <<<'

# Whether rc_rewrite found a block of the script's lines, and whether
# rc_change created the file.
typeset -gi rc_had_block=0 rc_created=0

# A temporary file that file_write hasn't moved into place yet.
typeset -g file_tmp=''

# rc_file: print the zsh startup file to change. Respects ZDOTDIR, for users
# who keep their zsh files elsewhere.
rc_file() {
    print -r -- ${ZDOTDIR:-$HOME}/.zshrc
}

# file_read FILE: set REPLY to FILE's exact contents, or to nothing if FILE
# doesn't exist.
file_read() {
    typeset -g REPLY=''
    [[ -e $1 ]] || return 0
    # read stops at a NUL byte, which text files don't have, and fails at
    # the end of the file, which is expected here.
    IFS= read -rd '' REPLY <$1
    return 0
}

# file_write FILE TEXT: replace FILE's contents with TEXT. If FILE is a
# symlink, the file it points to is written and the link stays. Permissions
# are kept. The text goes to a temporary file next to it first, so an
# interruption can't leave FILE half written.
file_write() {
    local target=${1:A}
    file_tmp=$target.setup-yt-dlp-$$
    if [[ -e $target ]]; then
        cp -p -- $target $file_tmp || return 1
    fi
    { print -rn -- "$2" >|$file_tmp && zf_mv -f -- $file_tmp $target } || return 1
    file_tmp=''
}

# rc_rewrite TEXT [LINE...]: set REPLY to TEXT, a zsh startup file, with a
# block holding LINEs: the existing block is replaced where it is, or a new
# one appended after a blank line. With no LINEs, removes the block, and the
# blank line before it. Sets rc_had_block. Fails if a block has no end
# marker.
rc_rewrite() {
    local text=$1
    shift
    local -a block=() lines=( "${(@f)text}" ) out=()
    (( $# )) && block=( "$RC_BEGIN" "$RC_NOTE" "$@" "$RC_END" )
    local -i i=1 j placed=0
    rc_had_block=0

    while (( i <= $#lines )); do
        if [[ $lines[i] == "$RC_BEGIN" ]]; then
            for (( j = i + 1; j <= $#lines; j++ )); do
                [[ $lines[j] == "$RC_END" ]] && break
            done
            (( j > $#lines )) && return 1
            rc_had_block=1
            if (( $#block && ! placed )); then
                out+=( "${block[@]}" )
                placed=1
            elif (( $#out )) && [[ -z $out[-1] ]]; then
                out[-1]=()
            fi
            (( i = j + 1 ))
        else
            out+=( "$lines[i]" )
            (( i++ ))
        fi
    done

    text=${(F)out}
    if (( $#block && ! placed )); then
        if [[ -n $text ]]; then
            [[ $text == *$'\n' ]] || text+=$'\n'
            text+=$'\n'
        fi
        text+=${(F)block}$'\n'
    fi
    typeset -g REPLY=$text
}

# rc_change [LINE...]: rc_edit the zsh startup file.
rc_change() {
    rc_edit "$(rc_file)" "$@"
}

# rc_edit FILE [LINE...]: rewrite FILE, a zsh startup file, with
# rc_rewrite, as a step, and show the LINEs added.
rc_edit() {
    local file=$1 old new done
    shift
    local subject=${(D)file}
    file_read "$file"
    old=$REPLY
    if ! rc_rewrite "$old" "$@"; then
        ui_fail "$subject" "has a '$RC_BEGIN' line with no '$RC_END' after it"
        ui_detail "Fix the file by hand, then run this again."
        return 1
    fi
    new=$REPLY

    if [[ $new == "$old" ]]; then
        if (( $# )); then
            ui_ok "$subject" "already set up"
        else
            ui_ok "$subject" "nothing to remove"
        fi
        return 0
    fi
    if (( $# )); then
        done=added
        (( rc_had_block )) && done=updated
    else
        done=removed
    fi

    if (( opts[dry_run] )); then
        ui_skip "$subject" "would have the setup-yt-dlp lines $done"
    else
        [[ -e $file || -L $file ]] || rc_created=1
        if ! file_write $file "$new"; then
            ui_fail "$subject" "couldn't be written"
            return 1
        fi
        log_note "$subject: setup-yt-dlp lines $done"
        ui_ok "$subject" "setup-yt-dlp lines $done"
    fi
    local line
    for line in "$@"; do
        ui_detail "$line"
    done
    return 0
}

# homebrew_shell_setup: add Homebrew's lines to the zsh startup file: no
# environment hints from brew, and pip's user commands on PATH.
homebrew_shell_setup() {
    local -a lines=('export HOMEBREW_NO_ENV_HINTS=1')
    local bin
    if bin=$(pip_user_bin); then
        # Written with $HOME, so the line still reads right if the home
        # folder moves.
        lines+=( 'export PATH="'${bin/#${(b)HOME}/\$HOME}':$PATH"' )
    fi
    rc_change "${lines[@]}"
}

# ----------------------------------------------------------------------------
# What the script has done
# ----------------------------------------------------------------------------

# A record of what the script installed and changed, so that uninstalling
# removes only that. KEY=VALUE lines, in the order things happened:
#   manager=homebrew           the package manager used
#   package=ffmpeg             a package the script installed
#   dependency=x265            a package that came with one of those
#   pip=certifi                a package pip added to the user's site-packages
#   zshrc=/Users/me/.zshrc     a zsh startup file the script added lines to
#   created=/Users/me/.zshrc   a file the script created
#   select=python3=none        a `port select` group and its earlier choice
# The file is read line by line, never sourced.
typeset -ga state=()

state_file() {
    print -r -- "$HOME/Library/Application Support/yt-dlp-setup/state"
}

# state_load: read the state file, if there is one.
state_load() {
    state=()
    local file=$(state_file) line
    [[ -r $file ]] || return 0
    for line in "${(@f)"$(<$file)"}"; do
        [[ $line == [a-z]##=* && $line != format=* ]] && state+=("$line")
    done
    return 0
}

# state_values KEY: print each value recorded for KEY, one per line.
state_values() {
    local -a values=( ${${(M)state:#$1=*}#$1=} )
    (( $#values )) && print -rl -- $values
    return 0
}

# state_has KEY VALUE: succeed if VALUE is recorded for KEY.
state_has() {
    (( ${state[(Ie)$1=$2]} ))
}

# state_has_installed: succeed if there's anything to uninstall.
state_has_installed() {
    local -a left=( ${state:#manager=*} )
    (( $#left ))
}

# state_add KEY VALUE: record VALUE for KEY, unless it's there already, and
# save the state file. Does nothing with --dry-run, as do the other changes
# below.
state_add() {
    (( opts[dry_run] )) && return 0
    state_has $1 $2 && return 0
    state+=("$1=$2")
    state_save
}

# state_remove KEY VALUE: forget VALUE for KEY, and save the state file.
state_remove() {
    (( opts[dry_run] )) && return 0
    local -i i=${state[(Ie)$1=$2]}
    (( i )) || return 0
    state[i]=()
    state_save
}

state_save() {
    local file=$(state_file)
    if ! { zf_mkdir -p ${file:h} 2>/dev/null &&
           file_write $file "# Written by setup-yt-dlp.zsh, and read by its --uninstall option.
format=1
${(F)state}
" }; then
        die "couldn't save ${(D)file}"
    fi
}

# state_delete: remove the state file, and its folder if that's empty.
state_delete() {
    (( opts[dry_run] )) && return 0
    local file=$(state_file)
    zf_rm -f -- $file
    zf_rmdir ${file:h} 2>/dev/null
    state=()
    return 0
}

# ----------------------------------------------------------------------------
# Ending a run
# ----------------------------------------------------------------------------

# What went wrong during the run, for the summary at the end.
typeset -ga problems=()

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
        [[ -n $log_file ]] && print -r -- "  The log has the details: ${(D)log_file}"
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
# Installing
# ----------------------------------------------------------------------------

# What gets installed, in this order. bash is there for
# youtube-downloader-pro.command, which runs with Homebrew's bash.
typeset -gra HOMEBREW_PACKAGES=(bash ffmpeg atomicparsley python3 deno)
typeset -gra MACPORTS_PACKAGES=(ffmpeg AtomicParsley py-pip deno)
# yt-dlp's optional Python packages: from pip with Homebrew, as ports with
# MacPorts.
typeset -gra PIP_PACKAGES=(websockets requests mutagen pycryptodomex curl-cffi yt-dlp-ejs)
typeset -gra MACPORTS_PY_PACKAGES=(py-websockets py-requests py-mutagen py-pycryptodomex py-curl-cffi yt-dlp-ejs)

# The packages installed before the latest install, to tell which
# dependencies it brought along.
typeset -ga pkg_seen=()
typeset -gi pkg_seen_taken=0

# install_package NAME [ARGS...]: install package NAME, passing ARGS to the
# manager, unless it's installed already. Records it, and the dependencies
# it brings along, when this run installs it.
install_package() {
    local version name
    local -i rc=0
    if version=$(pkg_version $1); then
        ui_ok "$1" "already installed ${c[dim]}($version)${c[reset]}"
        return 0
    fi
    if (( ! opts[dry_run] && ! pkg_seen_taken )); then
        pkg_seen=( ${(f)"$(pkg_list)"} )
        pkg_seen_taken=1
    fi
    if pkg_install "$@"; then
        state_add package $1
    else
        problems+=("$1 couldn't be installed")
        rc=1
    fi
    # Even a failed install can leave dependencies behind.
    if (( ! opts[dry_run] )); then
        local own=$(pkg_installed_name $1)
        local -a now=( ${(f)"$(pkg_list)"} )
        for name in ${now:|pkg_seen}; do
            [[ $name == "$own" ]] || state_add dependency $name
        done
        pkg_seen=( $now )
    fi
    return rc
}

# pip_user_packages: print the packages in the user's site-packages of
# Homebrew's Python, one per line.
pip_user_packages() {
    local line
    for line in ${(f)"$($pm_prefix/bin/python3 -m pip list --user --format=freeze 2>/dev/null)"}; do
        # "certifi==2026.10.5", or "name @ file:///..." for a local install.
        [[ $line == [[:alnum:]]* ]] && print -r -- ${line%%[=@ ]*}
    done
    return 0
}

# install_pip_packages: install PIP_PACKAGES into Homebrew's Python, and
# record everything pip added, dependencies too, so uninstalling can remove
# them.
install_pip_packages() {
    local name version
    if (( ! opts[dry_run] )) && ! pkg_version python3 >/dev/null; then
        for name in $PIP_PACKAGES; do
            ui_skip $name "skipped: python3 isn't installed"
        done
        problems+=("the Python packages were skipped, as python3 isn't installed")
        return 1
    fi
    local -a before=( ${(f)"$(pip_user_packages)"} ) after
    for name in $PIP_PACKAGES; do
        if version=$(pip_version $name); then
            ui_ok $name "already installed ${c[dim]}($version)${c[reset]}"
        elif ! pip_install $name; then
            problems+=("$name couldn't be installed")
        fi
    done
    after=( ${(f)"$(pip_user_packages)"} )
    for name in ${after:|before}; do
        state_add pip $name
    done
}

# install_settings: the ~/.zshrc lines for Homebrew, or `port select` for
# MacPorts.
install_settings() {
    case $opts[manager] in
        homebrew)
            local file=$(rc_file)
            if homebrew_shell_setup; then
                state_add zshrc $file
                (( rc_created )) && state_add created $file
            else
                problems+=("${(D)file} couldn't be set up")
            fi
            ;;
        macports)
            macports_select_python || problems+=("MacPorts' Python couldn't be selected")
            local group
            local -a earlier
            for group in ${(ok)port_select_before}; do
                # Keep the choice from before the first run. (The array is
                # needed: inside (( )), ${(M)state...} would match against
                # all of state joined into one string.)
                earlier=( ${(M)state:#select=$group=*} )
                (( $#earlier )) || state_add select "$group=$port_select_before[$group]"
            done
            ;;
    esac
    return 0
}

# install_run: install everything, then sum up.
install_run() {
    local name version
    local -F start=$EPOCHREALTIME
    state_add manager $opts[manager]

    ui_section Packages
    case $opts[manager] in
        homebrew)
            for name in $HOMEBREW_PACKAGES; do
                install_package $name
            done
            ui_section "Python packages"
            install_pip_packages
            ui_section yt-dlp
            install_package yt-dlp
            ;;
        macports)
            for name in $MACPORTS_PACKAGES; do
                install_package $name
            done
            ui_section "Python packages"
            for name in $MACPORTS_PY_PACKAGES; do
                install_package $name
            done
            ui_section yt-dlp
            # Without the ffmpeg variant, as the bash version did, since
            # ffmpeg is installed above.
            install_package yt-dlp -ffmpeg
            ;;
    esac
    ui_section Settings
    install_settings

    version=$(pkg_version yt-dlp)
    finish $start "Run the script again to retry." \
        "yt-dlp${version:+ $version} is installed." "Open a new terminal window to start using it."
}

# ----------------------------------------------------------------------------
# Uninstalling
# ----------------------------------------------------------------------------

# pip_names NAME...: print NAMEs the way pip compares them, lowercase and
# with runs of -, _ and . as one -, so curl_cffi matches curl-cffi.
pip_names() {
    (( $# )) && print -rl -- ${(L)@//[-_.]##/-}
    return 0
}

# uninstall_plan: say what uninstalling will remove.
uninstall_plan() {
    local -a packages=( ${(Oa)${(f)"$(state_values package)"}} )
    local -a pips=( ${(Oa)${(f)"$(state_values pip)"}} )
    local -a deps=( ${(f)"$(state_values dependency)"} )
    local -a files=( ${(f)"$(state_values zshrc)"} )
    local -a selects=( ${(f)"$(state_values select)"} )
    local file
    print
    print -r -- "This removes what setup-yt-dlp installed with $PM_TITLE[$opts[manager]]:"
    (( $#packages )) && print -rf '  %-16s %s\n' Packages "${(j:, :)packages}"
    (( $#pips )) && print -rf '  %-16s %s\n' "Python packages" "${(j:, :)pips}"
    if (( $#deps == 1 )); then
        print -rf '  %-16s %s\n' Dependencies "1 that came with them, unless something else needs it"
    elif (( $#deps )); then
        print -rf '  %-16s %s\n' Dependencies "$#deps that came with them, unless something else needs them"
    fi
    for file in $files; do
        print -rf '  %-16s %s\n' Settings "the setup-yt-dlp lines in ${(D)file}"
    done
    (( $#selects )) && print -rf '  %-16s %s\n' Settings "MacPorts' ${(j:, :)${(@)selects%%=*}} choices go back to what they were"
    return 0
}

# uninstall_created FILE: delete FILE, which the script created, if all that
# was in it was the script's lines.
uninstall_created() {
    state_has created "$1" || return 0
    file_read "$1"
    rc_rewrite "$REPLY" || return 0
    if [[ -n ${REPLY//[[:space:]]/} ]]; then
        state_remove created "$1"
    elif (( opts[dry_run] )); then
        ui_skip "${(D)1}" "would be deleted, as setup-yt-dlp created it"
    elif zf_rm -f -- "$1"; then
        log_note "${(D)1}: deleted"
        ui_ok "${(D)1}" "deleted, as setup-yt-dlp created it"
        state_remove created "$1"
    fi
    return 0
}

uninstall_settings() {
    local -a files=( ${(Oa)${(f)"$(state_values zshrc)"}} ) selects=( ${(f)"$(state_values select)"} )
    local file entry
    (( $#files + $#selects )) || return 0
    ui_section Settings
    for file in $files; do
        if rc_edit "$file"; then
            uninstall_created "$file"
            state_remove zshrc "$file"
        else
            problems+=("the setup-yt-dlp lines in ${(D)file} couldn't be removed")
        fi
    done
    # An entry is GROUP=EARLIER, such as python3=none.
    for entry in $selects; do
        if macports_select ${entry%%=*} ${entry#*=} "back to ${entry#*=}"; then
            state_remove select "$entry"
        else
            problems+=("MacPorts' ${entry%%=*} choice couldn't be put back")
        fi
    done
    return 0
}

# uninstall_pip_packages: uninstall the recorded pip packages, keeping any
# that a package the script didn't install needs.
uninstall_pip_packages() {
    local -a pips=( ${(Oa)${(f)"$(state_values pip)"}} ) ours others
    local name
    (( $#pips )) || return 0
    ui_section "Python packages"
    ours=( ${(f)"$(pip_names $pips)"} )
    for name in $pips; do
        if ! pip_version $name >/dev/null; then
            ui_ok $name "already uninstalled"
            state_remove pip $name
            continue
        fi
        others=( ${(f)"$(pip_names ${(f)"$(pip_required_by $name)"})"} )
        others=( ${others:|ours} )
        if (( $#others )); then
            ui_skip $name "kept: ${(j:, :)others} needs it"
            state_remove pip $name
        elif pip_uninstall $name; then
            state_remove pip $name
        else
            problems+=("$name couldn't be uninstalled")
        fi
    done
    return 0
}

# uninstall_packages: uninstall the recorded packages, newest first, then
# the dependencies they brought along that nothing needs any more.
uninstall_packages() {
    local -a packages=( ${(Oa)${(f)"$(state_values package)"}} ) deps
    local name
    deps=( ${(f)"$(state_values dependency)"} )
    (( $#packages + $#deps )) || return 0
    ui_section Packages
    for name in $packages; do
        if ! pkg_version $name >/dev/null; then
            ui_ok $name "already uninstalled"
            state_remove package $name
        elif pkg_uninstall $name; then
            state_remove package $name
        else
            problems+=("$name couldn't be uninstalled")
        fi
    done
    uninstall_dependencies
}

# uninstall_dependencies: uninstall the recorded dependencies that the
# manager says nothing needs any more. MacPorts only lists what's unneeded
# right now, so this goes round until nothing more is.
uninstall_dependencies() {
    local -a deps=( ${(f)"$(state_values dependency)"} ) unneeded installed kept
    local name
    local -i round
    (( $#deps )) || return 0
    if (( opts[dry_run] )); then
        ui_skip dependencies "would remove any of the $#deps that nothing else needs"
        return 0
    fi
    for (( round = 1; round <= 10; round++ )); do
        unneeded=( ${(f)"$(pkg_unneeded)"} )
        unneeded=( ${unneeded:*deps} )
        (( $#unneeded )) || break
        if ! pkg_uninstall_dependencies $unneeded; then
            problems+=("some dependencies couldn't be uninstalled")
            break
        fi
        ui_detail "${(j:, :)unneeded}"
        for name in $unneeded; do
            state_remove dependency $name
        done
    done
    # What's left is gone already, or something else needs it. With the
    # packages gone, there's no reason to remember it.
    deps=( ${(f)"$(state_values dependency)"} )
    installed=( ${(f)"$(pkg_list)"} )
    kept=( ${deps:*installed} )
    (( $#kept )) && ui_skip dependencies "kept $#kept that something else needs"
    if [[ -z $(state_values package) ]]; then
        for name in $deps; do
            state_remove dependency $name
        done
    fi
    return 0
}

# uninstall_run: say what will go, ask, and remove it.
uninstall_run() {
    uninstall_plan
    if (( ! opts[dry_run] )); then
        if (( ! opts[yes] )) && ! ui_can_ask; then
            die "uninstalling needs a yes; run with --yes to go ahead without a terminal"
        fi
        if ! ui_confirm "Uninstall these?"; then
            print -r -- "Nothing was changed."
            return 0
        fi
    fi
    local -F start=$EPOCHREALTIME
    uninstall_settings
    uninstall_pip_packages
    uninstall_packages
    state_has_installed || state_delete
    finish $start "Run with --uninstall again to retry." \
        "Everything setup-yt-dlp installed is removed."
}

# ----------------------------------------------------------------------------
# Status
# ----------------------------------------------------------------------------

# status_package pkg|pip NAME: show whether package NAME is installed, and
# fail if it isn't. pkg is a package from the manager; pip, from pip.
status_package() {
    local kind=$1 name=$2 version note=''
    if ! version=$(${kind}_version $name); then
        ui_fail "$name" missing
        return 1
    fi
    if (( $#state )); then
        local -a recorded=( ${(f)"$(state_values package)"} )
        if [[ $kind == pip ]]; then
            recorded=( ${(f)"$(pip_names ${(f)"$(state_values pip)"})"} )
            name=$(pip_names $name)
        fi
        (( ${recorded[(Ie)$name]} )) ||
            note=" ${c[dim]}· not installed by setup-yt-dlp${c[reset]}"
    fi
    ui_ok "$2" "$version$note"
}

# status_run: show what's installed, and fail if anything is missing.
status_run() {
    local name group current
    local -i missing=0
    ui_section Packages
    case $opts[manager] in
        homebrew)
            for name in $HOMEBREW_PACKAGES; do
                status_package pkg $name || (( missing++ ))
            done
            ui_section "Python packages"
            for name in $PIP_PACKAGES; do
                status_package pip $name || (( missing++ ))
            done
            ;;
        macports)
            for name in $MACPORTS_PACKAGES; do
                status_package pkg $name || (( missing++ ))
            done
            ui_section "Python packages"
            for name in $MACPORTS_PY_PACKAGES; do
                status_package pkg $name || (( missing++ ))
            done
            ;;
    esac
    ui_section yt-dlp
    status_package pkg yt-dlp || (( missing++ ))

    ui_section Settings
    case $opts[manager] in
        homebrew)
            local file=$(rc_file)
            file_read $file
            if rc_rewrite "$REPLY" && (( rc_had_block )); then
                ui_ok "${(D)file}" "has the setup-yt-dlp lines"
            else
                ui_fail "${(D)file}" "doesn't have the setup-yt-dlp lines"
                (( missing++ ))
            fi
            ;;
        macports)
            for group in python python3 pip pip3; do
                current=$(port select --show $group 2>/dev/null)
                ui_ok $group ${${current%\'*}##*\'}
            done
            ;;
    esac

    print
    if (( ! missing )); then
        print -r -- "${c[green]}${sym[ok]}${c[reset]} Everything is installed."
        return 0
    fi
    if state_has_installed; then
        print -r -- "${c[red]}${sym[fail]}${c[reset]} $missing missing. Run the script without options to repair it."
    else
        print -r -- "${c[red]}${sym[fail]}${c[reset]} $missing missing. Run the script without options to install it."
    fi
    return 1
}

# ----------------------------------------------------------------------------
# Command line
# ----------------------------------------------------------------------------

cli_usage() {
    print -r -- "\
${c[bold]}Usage:${c[reset]} $SETUP_PROG [options]

Install yt-dlp and its dependencies on macOS with Homebrew or MacPorts.

${c[bold]}Options:${c[reset]}
  -m, --manager <name>  Package manager to use: homebrew or macports
  -u, --uninstall       Remove what this script installed and undo its changes
  -s, --status          Show what is installed, then exit
  -n, --dry-run         Show what would be done without changing anything
  -y, --yes             Don't ask questions
  -v, --verbose         Show the output of brew, port and pip
      --no-color        Don't use colors
  -h, --help            Show this help, then exit
  -V, --version         Show the version, then exit

If both Homebrew and MacPorts are installed and --manager isn't given, the
script asks which one to use, or picks Homebrew with --yes."
}

# cli_fail MESSAGE: report a usage error and exit.
cli_fail() {
    ui_error "$1"
    print -ru2 -- "Run '$SETUP_PROG --help' to see the options."
    exit 2
}

# zparseopts specs. -M files long options under their short name, so
# --manager ends up as -m.
typeset -gra CLI_SPEC=(
    'm:=m' '-manager:=m'
    'u'    '-uninstall=u'
    's'    '-status=s'
    'n'    '-dry-run=n'
    'y'    '-yes=y'
    'v'    '-verbose=v'
           '-no-color'
    'h'    '-help=h'
    'V'    '-version=V'
)

# cli_accepts ARGS...: succeed if zparseopts accepts ARGS.
cli_accepts() {
    local -A parsed
    zparseopts -F -M -A parsed -- $CLI_SPEC 2>/dev/null
}

# cli_explain ARGS...: exit with a message saying why zparseopts rejected
# ARGS. Its own message drops the dashes on zsh 5.8 ("bad option: x").
cli_explain() {
    if cli_accepts "$@" value; then
        cli_fail "option '${argv[-1]}' needs a value"
    fi
    # Find the first word that doesn't parse. A prefix that ends in an
    # option wanting a value fails on its own, so also try it with the next
    # word.
    local -i i=1
    while (( i <= $# )); do
        if cli_accepts "${(@)argv[1,i]}"; then
            (( i += 1 ))
        elif (( i < $# )) && cli_accepts "${(@)argv[1,i+1]}"; then
            (( i += 2 ))
        else
            break
        fi
    done
    local word=${argv[i]-}
    local -a names=( ${${CLI_SPEC%%[:=]*}/#/-} )
    if (( ${names[(Ie)${word%%=*}]} )); then
        cli_fail "option '${word%%=*}' doesn't take a value"
    fi
    cli_fail "unknown option '$word'"
}

# cli_parse ARGS...: fill in opts, or exit on a usage error.
cli_parse() {
    local -A parsed
    if ! zparseopts -D -F -M -A parsed -- $CLI_SPEC 2>/dev/null; then
        cli_explain "$@"
    fi
    if (( $# )); then
        cli_fail "unexpected argument '$1'"
    fi

    if (( ${+parsed[-h]} )); then
        opts[action]=help
        return 0
    elif (( ${+parsed[-V]} )); then
        opts[action]=version
        return 0
    fi

    if (( ${+parsed[-u]} && ${+parsed[-s]} )); then
        cli_fail "--uninstall and --status can't be used together"
    elif (( ${+parsed[-u]} )); then
        opts[action]=uninstall
    elif (( ${+parsed[-s]} )); then
        opts[action]=status
    fi
    (( ${+parsed[-n]} )) && opts[dry_run]=1
    (( ${+parsed[-y]} )) && opts[yes]=1
    (( ${+parsed[-v]} )) && opts[verbose]=1
    (( ${+parsed[--no-color]} )) && opts[color]=never

    if (( ${+parsed[-m]} )); then
        # --manager=brew arrives as "=brew".
        local manager=${parsed[-m]#=}
        case ${(L)manager} in
            homebrew|brew) opts[manager]=homebrew ;;
            macports|port) opts[manager]=macports ;;
            '')            cli_fail "option '--manager' needs a value" ;;
            *)             cli_fail "unknown package manager '$manager'; use homebrew or macports" ;;
        esac
    fi
    return 0
}

# ----------------------------------------------------------------------------
# Checks before changing anything
# ----------------------------------------------------------------------------

preflight() {
    if (( EUID == 0 )); then
        die "don't run this script as root or with sudo; it asks for your password when it needs it"
    fi
    if (( ! $+commands[sw_vers] )); then
        die "this script only works on macOS"
    fi
    local version=$(sw_vers -productVersion 2>/dev/null)
    if [[ $version == <->* ]] && (( ${version%%.*} < 12 )); then
        ui_warn "macOS $version is older than macOS 12, the oldest version this script supports"
    fi
}

# ----------------------------------------------------------------------------
# Commands
# ----------------------------------------------------------------------------

# use_manager: pick the package manager, the one the state names if there's
# a state file, and say which it is.
use_manager() {
    local earlier=$(state_values manager)
    if [[ -n $earlier ]]; then
        if [[ -n $opts[manager] && $opts[manager] != $earlier ]]; then
            die "yt-dlp was set up with $PM_TITLE[$earlier]; run with --uninstall first to switch to $PM_TITLE[$opts[manager]]"
        fi
        if (( ! $+commands[$PM_COMMAND[$earlier]] )); then
            die "yt-dlp was set up with $PM_TITLE[$earlier], but $PM_TITLE[$earlier] isn't installed any more"
        fi
        opts[manager]=$earlier
    fi
    pm_select
    pm_init
    print -r -- "Using $PM_TITLE[$opts[manager]] $pm_version"
}

cmd_install() {
    state_load
    use_manager
    # Run again after installing: ask what to do, unless --yes or the lack
    # of a terminal makes it a repair.
    if state_has_installed && (( ! opts[yes] )) && ui_can_ask; then
        local version=$(pkg_version yt-dlp)
        print
        if [[ -n $version ]]; then
            ui_choose "yt-dlp $version is set up already. What do you want to do?" \
                "Repair: install anything that's missing" Uninstall Quit
        else
            ui_choose "setup-yt-dlp has run here before, but yt-dlp is missing. What do you want to do?" \
                "Repair: install anything that's missing" Uninstall Quit
        fi
        case $REPLY in
            2) uninstall_run; return ;;
            3) return 0 ;;
        esac
    fi
    install_run
}

cmd_uninstall() {
    state_load
    if ! state_has_installed; then
        print -r -- "Nothing to uninstall: setup-yt-dlp hasn't installed anything for you."
        state_delete
        return 0
    fi
    use_manager
    uninstall_run
}

cmd_status() {
    state_load
    use_manager
    status_run
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
    [[ -n $file_tmp ]] && zf_rm -f -- $file_tmp
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
        version) print -r -- "setup-yt-dlp $SETUP_VERSION"; return 0 ;;
    esac

    preflight
    ui_header
    case $opts[action] in
        install)   cmd_install ;;
        uninstall) cmd_uninstall ;;
        status)    cmd_status ;;
    esac
}

# Run only when executed, not when sourced: the tests source this file to
# call its functions.
if [[ $ZSH_EVAL_CONTEXT == toplevel ]]; then
    main "$@"
fi
