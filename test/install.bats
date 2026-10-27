#!/usr/bin/env bats
# Installing, and the state file that records what was installed.
#
# The code passed to in_script is zsh, expanded by zsh:
# shellcheck disable=SC2016

setup() {
    load test_helper/common
    common_setup
    STATE=$HOME/Library/Application\ Support/yt-dlp-setup/state
}

teardown() {
    common_teardown
}

# recorded: print the state file without its header lines.
recorded() {
    grep -v -e '^#' -e '^format=' "$STATE"
}

# installs: print the install commands the fakes ran.
installs() {
    grep -E '^(brew install|sudo -n port -N install|python3 -m pip install)' "$FAKE_STATE/calls"
}

@test "Homebrew: installing everything" {
    use_fake homebrew
    run -0 setup_script
    assert_output --regexp "^yt-dlp setup [0-9A-Za-z.-]+
Using Homebrew 4.6.3

▸ Packages
  ✓ bash               installed
  ✓ ffmpeg             installed
  ✓ atomicparsley      installed
  ✓ python3            installed
  ✓ deno               installed

▸ Python packages
  ✓ websockets         installed
  ✓ requests           installed
  ✓ mutagen            installed
  ✓ pycryptodomex      installed
  ✓ curl-cffi          installed
  ✓ yt-dlp-ejs         installed

▸ yt-dlp
  ✓ yt-dlp             installed

▸ Settings
  ✓ ~/.zshrc           setup-yt-dlp lines added
    export HOMEBREW_NO_ENV_HINTS=1
    export PATH=\"\\\$HOME/Library/Python/3.15/bin:\\\$PATH\"

✓ Done in [0-9]+s\. yt-dlp 1\.0 is installed\.
  Open a new terminal window to start using it\.$"
    run -0 installs
    assert_output "brew install --formula bash
brew install --formula ffmpeg
brew install --formula atomicparsley
brew install --formula python3
brew install --formula deno
python3 -m pip install --user --break-system-packages websockets
python3 -m pip install --user --break-system-packages requests
python3 -m pip install --user --break-system-packages mutagen
python3 -m pip install --user --break-system-packages pycryptodomex
python3 -m pip install --user --break-system-packages curl-cffi
python3 -m pip install --user --break-system-packages yt-dlp-ejs
brew install --formula yt-dlp"
}

@test "Homebrew: the state records what was installed, with dependencies" {
    use_fake homebrew
    run -0 setup_script
    run -0 recorded
    assert_output "manager=homebrew
package=bash
package=ffmpeg
dependency=libvpx
dependency=x265
package=atomicparsley
package=python3
package=deno
pip=certifi
pip=curl-cffi
pip=mutagen
pip=pycryptodomex
pip=requests
pip=urllib3
pip=websockets
pip=yt-dlp-ejs
package=yt-dlp
zshrc=$HOME/.zshrc
created=$HOME/.zshrc"
}

@test "Homebrew: what was installed already is left out of the state" {
    use_fake homebrew
    fake_installed brew ffmpeg 7.1_4
    fake_installed pip mutagen 1.47.0
    fake_installed pip six 1.17.0
    printf 'alias ll="ls -l"\n' >"$HOME/.zshrc"
    run -0 setup_script
    assert_line '  ✓ ffmpeg             already installed (7.1_4)'
    assert_line '  ✓ mutagen            already installed (1.47.0)'
    run -0 recorded
    refute_line package=ffmpeg
    refute_line pip=mutagen
    refute_line pip=six
    assert_line "zshrc=$HOME/.zshrc"
    refute_line --partial created=
}

@test "a package that fails doesn't stop the rest" {
    use_fake homebrew
    fake_fails deno
    run -1 setup_script
    assert_line '  ✗ deno               failed'
    assert_line '    Error: deno: no bottle available!'
    assert_line '  ✓ yt-dlp             installed'
    assert_output --regexp "
✗ Finished in [0-9]+s, with problems:
    deno couldn't be installed
  The log has the details: ~/Library/Logs/yt-dlp-setup/[0-9-]+\.log
  Run the script again to retry\.$"
    run -0 recorded
    refute_line package=deno
    assert_line package=yt-dlp
}

@test "without python3, the Python packages are skipped" {
    use_fake homebrew
    fake_fails python@3.15
    run -1 setup_script
    assert_line "  – websockets         skipped: python3 isn't installed"
    assert_line "    the Python packages were skipped, as python3 isn't installed"
    run -1 grep -q 'pip install' "$FAKE_STATE/calls"
}

@test "running it again installs what's missing and keeps the record" {
    use_fake homebrew
    fake_fails deno
    run -1 setup_script
    rm "$FAKE_STATE/fail/deno"
    : >"$FAKE_STATE/calls"
    run -0 setup_script
    assert_line '  ✓ bash               already installed (1.0)'
    assert_line '  ✓ deno               installed'
    assert_line '  ✓ ~/.zshrc           already set up'
    run -0 installs
    assert_output 'brew install --formula deno'
    run -0 recorded
    assert_line package=bash
    assert_line package=deno
    assert_equal "$(grep -c '^package=bash$' "$STATE")" 1
}

@test "MacPorts: installing everything" {
    use_fake macports
    run -0 setup_script
    assert_line '  ✓ AtomicParsley      installed'
    assert_line '  ✓ python3            now python314'
    assert_line '  ✓ pip3               now pip314'
    run -0 installs
    assert_output "sudo -n port -N install ffmpeg
sudo -n port -N install AtomicParsley
sudo -n port -N install py-pip
sudo -n port -N install deno
sudo -n port -N install py-websockets
sudo -n port -N install py-requests
sudo -n port -N install py-mutagen
sudo -n port -N install py-pycryptodomex
sudo -n port -N install py-curl-cffi
sudo -n port -N install yt-dlp-ejs
sudo -n port -N install yt-dlp -ffmpeg"
    assert [ ! -e "$HOME/.zshrc" ]
}

@test "MacPorts: the state records the ports and the earlier port select choices" {
    use_fake macports
    mkdir -p "$FAKE_STATE/select"
    echo python313 >"$FAKE_STATE/select/python3"
    run -0 setup_script
    run -0 recorded
    assert_output "manager=macports
package=ffmpeg
package=AtomicParsley
package=py-pip
dependency=py314-pip
dependency=python314
package=deno
package=py-websockets
package=py-requests
package=py-mutagen
package=py-pycryptodomex
package=py-curl-cffi
package=yt-dlp-ejs
package=yt-dlp
select=pip=none
select=pip3=none
select=python=none
select=python3=python313"
}

@test "MacPorts: the choice from before the first run is the one kept" {
    use_fake macports
    run -0 setup_script
    echo python313 >"$FAKE_STATE/select/python3"
    run -0 setup_script
    assert_line '  ✓ python3            now python314'
    run -0 grep '^select=python3=' "$STATE"
    assert_output select=python3=none
}

@test "--dry-run installs nothing and records nothing" {
    use_fake homebrew
    run -0 setup_script --dry-run
    assert_line --regexp '^yt-dlp setup [0-9A-Za-z.-]+ \(dry run: nothing will be changed\)$'
    assert_line '  – ffmpeg             would run: brew install --formula ffmpeg'
    assert_line '  – ~/.zshrc           would have the setup-yt-dlp lines added'
    assert_line 'Dry run finished. Nothing was changed.'
    run -1 installs
    assert [ ! -e "$STATE" ]
    assert [ ! -e "$HOME/.zshrc" ]
    assert [ ! -e "$HOME/Library/Logs" ]
}

@test "switching to the other manager needs an uninstall first" {
    use_fake homebrew
    use_fake macports
    mkdir -p "${STATE%/*}"
    printf 'format=1\nmanager=macports\n' >"$STATE"
    run -1 --separate-stderr setup_script --manager homebrew
    assert_stderr 'error: yt-dlp was set up with MacPorts; run with --uninstall first to switch to Homebrew'
    run -1 installs
}

@test "the manager in the state is used without asking" {
    use_fake homebrew
    use_fake macports
    mkdir -p "${STATE%/*}"
    printf 'format=1\nmanager=macports\n' >"$STATE"
    run -0 setup_script
    assert_line 'Using MacPorts 2.10.5'
}

@test "the manager in the state has to be there still" {
    use_fake homebrew
    mkdir -p "${STATE%/*}"
    printf 'format=1\nmanager=macports\n' >"$STATE"
    run -1 --separate-stderr setup_script
    assert_stderr "error: yt-dlp was set up with MacPorts, but MacPorts isn't installed any more"
}

@test "the state file is read, not run" {
    mkdir -p "${STATE%/*}"
    # shellcheck disable=SC2016  # the $( ) is meant to stay unexpanded
    printf '%s\n' '# a comment' 'format=1' 'package=$(touch "$HOME/ran")' '$(touch "$HOME/ran")' 'Package=x' >"$STATE"
    run -0 in_script 'state_load; state_values package; print -r -- $#state'
    assert_output '$(touch "$HOME/ran")
1'
    assert [ ! -e "$HOME/ran" ]
}

@test "state_add saves each value once" {
    run -0 in_script 'state_add package ffmpeg; state_add package deno; state_add package ffmpeg; state_load; state_values package'
    assert_output 'ffmpeg
deno'
    run -0 cat "$STATE"
    assert_output '# Written by setup-yt-dlp.zsh, and read by its --uninstall option.
format=1
package=ffmpeg
package=deno'
}
