# Contributing

## Layout

- `src/` has the two setup scripts and the downloader scripts. `setup-yt-dlp-standalone.zsh` installs yt-dlp_macos, ffmpeg and ffprobe into `/usr/local/bin` without a package manager. `youtube-downloader-pro.command` is a template: the setup script downloads it from the release's tag (from `main` for version `0.0.0-dev`) and fills in `@BASH@`, `@PREFIX@` and `@MANAGER@`. The standalone script saves `youtube-downloader-pro-standalone.command` as it is.
- `test/` has the bats tests, with those for the standalone script in `test/standalone/`. `test/bats` and `test/test_helper/bats-*` are git submodules, and `test/fakes/` has the fake `brew`, `port`, `python3`, `sudo` and `curl` they run against.
- `.github/workflows/` has the CI and release workflows, and `.github/scripts/` the scripts that build a release's archives and notes.

## Running the tests

```sh
git submodule update --init
make test
make lint
```

`make test` uses `/bin/zsh`. To test another zsh, pass its path: `make test ZSH=/opt/homebrew/bin/zsh`. `make test-setup` and `make test-standalone` run the tests for one script. `make lint` needs shellcheck.

The tests run the script with a temporary `HOME` and a `PATH` of only the fakes, `/usr/bin` and `/bin`, so they don't change the machine they run on or use its own package managers. The standalone script's tests download from a folder of files through the fake `curl`, and install into a temporary folder. The tests that fake a terminal need python3, and the ones for the release archive need GNU tar, so they're skipped on macOS.

## zsh 5.8 and 5.7.1

The setup script has to run on zsh 5.8, the version macOS 12 ships, and the standalone script on zsh 5.7.1, the version macOS 10.15 ships. CI runs the tests on Linux with Debian 11's zsh 5.8 package and Debian 10's zsh 5.7.1 package, and on macOS 15 with its own zsh.

zsh 5.7.1 has no `zparseopts -F`, which is why the standalone script parses its options differently.

To get zsh 5.8 on Debian or Ubuntu (for 5.7.1, the files are `zsh-common_5.7.1-1+deb10u1_all.deb` and `zsh_5.7.1-1+deb10u1_amd64.deb`):

```sh
curl -fsSLO https://archive.debian.org/debian/pool/main/z/zsh/zsh-common_5.8-6+deb11u1_all.deb
curl -fsSLO https://archive.debian.org/debian/pool/main/z/zsh/zsh_5.8-6+deb11u1_amd64.deb
sudo dpkg -i zsh-common_5.8-6+deb11u1_all.deb zsh_5.8-6+deb11u1_amd64.deb
sudo apt-mark hold zsh zsh-common
```

## Releasing

Push a tag for the version:

```sh
git tag -a v1.0.0-beta.2 -m "setup-yt-dlp 1.0.0-beta.2"
git push origin v1.0.0-beta.2
```

The release workflow runs the tests, then publishes a release with `setup-yt-dlp.tar.xz`, `setup-yt-dlp-standalone.tar.xz` and their checksums. The scripts in the repository say their version is `0.0.0-dev`; the copies in the archives get the tag's. A tag with a hyphen, such as `v1.0.0-beta.2`, becomes a pre-release.

The notes list the commits since the previous `v` tag. A subject starting with Add or Install goes under New, one starting with Fix under Fixes, and the rest under Changes. Commits that only touch tests, CI or this file go in a collapsed section, and a commit that was reverted is left out along with its revert.
