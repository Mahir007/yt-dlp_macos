#!/bin/zsh -f
#
# yt-dlp_setup: install yt-dlp and its dependencies on macOS with Homebrew
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
    echo "yt-dlp_setup: this script needs zsh. Run it with: zsh yt-dlp_setup.zsh" >&2
    exit 1
fi

emulate -R zsh
setopt extended_glob no_unset pipe_fail warn_create_global
# ~/.zshenv is still read when run as `zsh yt-dlp_setup.zsh`. Drop any
# aliases it defined before they can change the code below.
unalias -m '*'

autoload -Uz is-at-least
if ! is-at-least 5.8; then
    print -ru2 -- "yt-dlp_setup: needs zsh 5.8 or later, but this is zsh $ZSH_VERSION."
    exit 1
fi

zmodload zsh/zutil      # zparseopts
zmodload zsh/datetime   # EPOCHREALTIME, strftime
zmodload zsh/zselect    # sleeping for a fraction of a second
zmodload -F zsh/files b:zf_mkdir b:zf_rm

typeset -gr SETUP_VERSION=1.0.0

# Name to show in messages. $0 isn't a regular file when the script comes
# from a pipe or a process substitution such as `zsh <(curl ...)`.
if [[ -f $0 ]]; then
    typeset -gr SETUP_PROG=${0:t}
else
    typeset -gr SETUP_PROG=yt-dlp_setup.zsh
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
    print -r -- "${c[bold]}yt-dlp_setup${c[reset]} ${c[dim]}$SETUP_VERSION${c[reset]}$note"
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
    local dir=$HOME/Library/Logs/yt-dlp_setup stamp
    zf_mkdir -p $dir 2>/dev/null || die "couldn't create ${(D)dir}"
    strftime -s stamp %Y%m%d-%H%M%S $EPOCHSECONDS
    log_file=$dir/$stamp.log
    local args=none
    (( $#setup_args )) && args=${(j: :)${(q-)setup_args}}
    print -r -- "yt-dlp_setup $SETUP_VERSION, arguments: $args" >$log_file
    # Keep the ten newest logs.
    local -a old=( $dir/*.log(Nom[11,-1]) )
    (( $#old )) && zf_rm -f -- $old
    return 0
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
        (( opts[verbose] )) || ui_tail $out
        ui_detail "Log: ${(D)log_file}"
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
        ui_choose "Both Homebrew and MacPorts are installed. Which one should yt-dlp_setup use?" \
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

cmd_install() {
    pm_select
    pm_init
    print -r -- "Using $PM_TITLE[$opts[manager]] $pm_version"
    # Still being ported from archive/setup-yt-dlp.sh.
    die "installing isn't implemented yet"
}

# Still being ported from archive/setup-yt-dlp.sh.
cmd_uninstall() { die "uninstalling isn't implemented yet" }
cmd_status()    { die "--status isn't implemented yet" }

# ----------------------------------------------------------------------------
# Exit and interrupts
# ----------------------------------------------------------------------------

# Defined at the top level, so they apply to the whole script and not to a
# single function. Neither runs in subshells or background jobs.
TRAPEXIT() {
    spinner_stop
    sudo_end
    [[ -n $log_file ]] && zf_rm -f ${log_file%.log}.out
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
        version) print -r -- "yt-dlp_setup $SETUP_VERSION"; return 0 ;;
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
