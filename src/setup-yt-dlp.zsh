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

zmodload zsh/zutil  # zparseopts

typeset -gr SETUP_VERSION=1.0.0

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

# ----------------------------------------------------------------------------
# Output
# ----------------------------------------------------------------------------

# Escape sequences by name, empty until ui_init turns colors on.
typeset -gA c=(bold '' dim '' red '' green '' yellow '' blue '' reset '')

ui_init() {
    if [[ $opts[color] == auto && -t 1 && -z ${NO_COLOR-} && ${TERM-dumb} != dumb ]]; then
        c=(bold $'\e[1m' dim $'\e[2m' red $'\e[31m' green $'\e[32m'
           yellow $'\e[33m' blue $'\e[34m' reset $'\e[0m')
    fi
}

ui_header() {
    print -r -- "${c[bold]}yt-dlp setup${c[reset]} ${c[dim]}$SETUP_VERSION${c[reset]}"
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

# Still being ported from setup-yt-dlp.sh.
cmd_install()   { die "installing isn't implemented yet" }
cmd_uninstall() { die "uninstalling isn't implemented yet" }
cmd_status()    { die "--status isn't implemented yet" }

main() {
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
