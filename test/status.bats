#!/usr/bin/env bats
# --status.

setup() {
    load test_helper/common
    common_setup
    STATE=$HOME/Library/Application\ Support/yt-dlp-setup/state
}

teardown() {
    common_teardown
}

@test "--status lists everything, marking what the script didn't install" {
    use_fake homebrew
    fake_installed brew ffmpeg 7.1_4
    run -0 setup_script
    run -0 setup_script --status
    assert_output --regexp "^yt-dlp setup [0-9A-Za-z.-]+
Using Homebrew 4.6.3

▸ Packages
  ✓ bash               1\.0
  ✓ ffmpeg             7\.1_4 · not installed by setup-yt-dlp
  ✓ atomicparsley      1\.0
  ✓ python3            1\.0
  ✓ deno               1\.0

▸ Python packages
  ✓ websockets         1\.0
  ✓ requests           1\.0
  ✓ mutagen            1\.0
  ✓ pycryptodomex      1\.0
  ✓ curl-cffi          1\.0
  ✓ yt-dlp-ejs         1\.0

▸ yt-dlp
  ✓ yt-dlp             1\.0

▸ Settings
  ✓ ~/\.zshrc           has the setup-yt-dlp lines

✓ Everything is installed\.$"
}

@test "--status fails when something is missing" {
    use_fake homebrew
    run -0 setup_script
    rm "$FAKE_STATE/pip/mutagen"
    printf '' >"$HOME/.zshrc"
    run -1 setup_script --status
    assert_line '  ✗ mutagen            missing'
    assert_line "  ✗ ~/.zshrc           doesn't have the setup-yt-dlp lines"
    assert_line '✗ 2 missing. Run the script without options to repair it.'
}

@test "--status before installing changes nothing" {
    use_fake homebrew
    fake_installed brew ffmpeg 7.1_4
    run -1 setup_script --status
    assert_line '  ✓ ffmpeg             7.1_4'
    assert_line '  ✗ yt-dlp             missing'
    assert_line --regexp '^✗ [0-9]+ missing\. Run the script without options to install it\.$'
    assert [ ! -e "$STATE" ]
    assert [ ! -e "$HOME/Library/Logs" ]
    run -1 grep -E 'install' "$FAKE_STATE/calls"
}

@test "--status with MacPorts shows the port select choices" {
    use_fake macports
    run -0 setup_script
    run -0 setup_script --status
    assert_line '  ✓ python3            python314'
    assert_line '  ✓ pip3               pip314'
    assert_line '  ✓ AtomicParsley      1.0_0'
}

@test "--status uses the manager in the state" {
    use_fake homebrew
    use_fake macports
    run -0 setup_script --manager macports
    run -0 setup_script --status
    assert_line 'Using MacPorts 2.10.5'
}
