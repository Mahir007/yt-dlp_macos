#!/usr/bin/env bats
# Saving YouTube Downloader Pro, filled in from bin/youtube-downloader-pro.command.
#
# The code passed to in_script is zsh, expanded by zsh:
# shellcheck disable=SC2016

setup() {
    load test_helper/common
    common_setup
    TEMPLATE=$BATS_TEST_DIRNAME/../bin/youtube-downloader-pro.command
    SAVED=$HOME/Downloads/yt.command
    mkdir -p "$HOME/Downloads"
    # A curl that "downloads" the template from this checkout, and notes
    # the URL it was given.
    stub curl 'out= url=
while (($#)); do
    case $1 in
        -o) out=$2; shift ;;
        http*) url=$1 ;;
    esac
    shift
done
echo "$url" >"$HOME/curl-url"
cp "'"$TEMPLATE"'" "$out"'
}

teardown() {
    common_teardown
}

# use_manager homebrew|macports: the fake manager, with bash in its prefix.
# The bash running the tests stands in for it.
use_manager() {
    use_fake "$1"
    PREFIX=$BATS_TEST_TMPDIR/$1
    ln -s "$BASH" "$PREFIX/bin/bash"
}

# save MANAGER: save the downloader to $SAVED with MANAGER's values.
save() {
    in_script "ui_init; opts[manager]=$1; pm_init; downloader_save \$HOME/Downloads/yt.command"
}

# answer INPUT CODE: in_script_tty CODE, typing INPUT into the terminal.
answer() {
    # shellcheck disable=SC2059  # INPUT holds escapes such as \n
    printf "$1" | in_script_tty "$2" | tr -d '\r'
}

@test "the template has the values to fill in" {
    run -0 head -1 "$TEMPLATE"
    assert_output '#!@BASH@'
    run -0 grep -E '^(PREFIX|MANAGER)=' "$TEMPLATE"
    assert_output 'PREFIX=@PREFIX@
MANAGER=@MANAGER@'
}

@test "the template comes from main outside a release, and from the tag in one" {
    run -0 in_script 'downloader_url'
    assert_output https://raw.githubusercontent.com/Mahir007/yt-dlp_macos/main/bin/youtube-downloader-pro.command
    sed 's/^typeset -gr SETUP_VERSION=0\.0\.0-dev$/typeset -gr SETUP_VERSION=1.2.3/' "$SCRIPT" >"$BATS_TEST_TMPDIR/release.zsh"
    SCRIPT=$BATS_TEST_TMPDIR/release.zsh run -0 in_script 'downloader_url'
    assert_output https://raw.githubusercontent.com/Mahir007/yt-dlp_macos/v1.2.3/bin/youtube-downloader-pro.command
}

@test "Homebrew: the saved script has Homebrew's values" {
    use_manager homebrew
    run -0 save homebrew
    assert_line --regexp '^  ✓ download +downloaded$'
    assert_line --regexp '^  ✓ ~/Downloads/yt\.command +saved$'
    assert [ -x "$SAVED" ]
    run -1 diff "$TEMPLATE" "$SAVED"
    assert_output "1c1
< #!@BASH@
---
> #!$PREFIX/bin/bash
12,13c12,13
< PREFIX=@PREFIX@
< MANAGER=@MANAGER@
---
> PREFIX=$PREFIX
> MANAGER=homebrew"
}

@test "MacPorts: the saved script has MacPorts' values" {
    use_manager macports
    run -0 save macports
    run -0 grep -E '^(#!|PREFIX=|MANAGER=)' "$SAVED"
    assert_output "#!$PREFIX/bin/bash
PREFIX=$PREFIX
MANAGER=macports"
}

@test "a prefix with a quote in it is quoted" {
    use_fake homebrew
    PREFIX="$BATS_TEST_TMPDIR/it's"
    mkdir -p "$PREFIX/bin"
    ln -s "$FAKES/brew" "$BASH" "$PREFIX/bin/"
    PATH=$PREFIX/bin:$PATH run -0 save homebrew
    run -0 grep '^PREFIX=' "$SAVED"
    assert_output "PREFIX=$BATS_TEST_TMPDIR/it\\'s"
}

@test "the saved script runs and updates yt-dlp with Homebrew" {
    ((BASH_VERSINFO[0] >= 4)) || skip "needs bash 4 or later to run the saved script"
    use_manager homebrew
    stub yt-dlp 'exit 0'
    run -0 save homebrew
    run -0 env PATH=/usr/bin:/bin "$SAVED" <<<q
    assert_output --partial 'Goodbye!'
    run -0 calls
    assert_line 'brew upgrade -q yt-dlp'
    assert_line 'python3 -m pip install --user --break-system-packages -Uq yt-dlp-ejs'
}

@test "the saved script updates yt-dlp with MacPorts" {
    ((BASH_VERSINFO[0] >= 4)) || skip "needs bash 4 or later to run the saved script"
    use_manager macports
    stub yt-dlp 'exit 0'
    run -0 save macports
    run -0 env PATH="$STUBS:/usr/bin:/bin" "$SAVED" <<<q
    assert_output --partial 'Goodbye!'
    run -0 calls
    assert_line 'sudo port -q selfupdate'
}

@test "a failed download saves nothing" {
    use_manager homebrew
    stub curl 'echo "curl: (22) The requested URL returned error: 404" >&2; exit 22'
    run -1 save homebrew
    assert_line --regexp '^  ✗ download +failed$'
    assert_line '    curl: (22) The requested URL returned error: 404'
    assert [ ! -e "$SAVED" ]
    run -0 find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'setup-yt-dlp-*.command'
    assert_output ''
}

@test "a download that isn't the template isn't saved" {
    use_manager homebrew
    stub curl 'while (($#)); do [[ $1 == -o ]] && echo "<html>" >"$2"; shift; done'
    run -1 save homebrew
    assert_line --regexp "^  ✗ ~/Downloads/yt\\.command +not saved: the download isn't the template$"
    assert [ ! -e "$SAVED" ]
}

@test "without bash in the prefix, nothing is downloaded" {
    use_fake homebrew
    run -1 save homebrew
    assert_line --regexp "^  ✗ ~/Downloads/yt\\.command +not saved: .*/homebrew/bin/bash isn't installed$"
    assert [ ! -e "$HOME/curl-url" ]
}

@test "asked after installing, yes saves it where Finder's dialog says" {
    use_manager homebrew
    stub osascript 'echo "$HOME/Downloads/Pro"'
    run -0 answer 'y\n' 'opts[color]=never; ui_init; opts[manager]=homebrew; pm_init; downloader_offer'
    assert_output --partial '✓ download           downloaded'
    assert_line '  ✓ ~/Downloads/Pro.command saved'
    assert_line 'Open ~/Downloads/Pro.command from Finder to start it.'
    assert [ -x "$HOME/Downloads/Pro.command" ]
}

@test "Finder's dialog starts in ~/Downloads" {
    use_manager homebrew
    stub osascript 'shift; printf "%s\n" "$@" >"$HOME/osascript-args"; echo "$HOME/Downloads/x.command"'
    run -0 answer 'y\n' 'opts[color]=never; ui_init; opts[manager]=homebrew; pm_init; downloader_offer'
    run -0 cat "$HOME/osascript-args"
    assert_output "$HOME/Downloads
YouTube Downloader Pro.command"
}

@test "answering no, or cancelling the dialog, saves nothing" {
    use_manager homebrew
    stub osascript 'touch "$HOME/asked"; exit 1'
    run -0 answer '\n' 'opts[color]=never; ui_init; opts[manager]=homebrew; pm_init; downloader_offer'
    assert [ ! -e "$HOME/asked" ]
    run -0 answer 'y\n' 'opts[color]=never; ui_init; opts[manager]=homebrew; pm_init; downloader_offer'
    assert [ -e "$HOME/asked" ]
    assert_line 'Do you want to download the YouTube Downloader Pro script? [y/N] Not saved.'
    assert [ ! -e "$HOME/curl-url" ]
}

@test "with --yes or --dry-run, it isn't offered" {
    use_manager homebrew
    stub osascript 'touch "$HOME/asked"; exit 1'
    local option
    for option in yes dry_run; do
        run -0 answer '' "opts[color]=never; ui_init; opts[manager]=homebrew opts[$option]=1; pm_init; downloader_offer"
        refute_output --partial 'YouTube Downloader Pro'
    done
    assert [ ! -e "$HOME/asked" ]
}

@test "an install on a terminal ends with the question" {
    use_manager homebrew
    stub osascript 'exit 1'
    run -0 answer 'y\n' 'main --no-color'
    assert_output --regexp "Open a new terminal window to start using it\\.

Do you want to download the YouTube Downloader Pro script\\? \\[y/N\\] Not saved\\.$"
}
