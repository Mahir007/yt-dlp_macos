# Contributing

## Layout

- `src/` has the setup script and the downloader scripts. `youtube-downloader-pro.command` is a template: the setup script downloads it from the release's tag (from `main` for version `0.0.0-dev`) and fills in `@BASH@`, `@PREFIX@` and `@MANAGER@`.
- `test/` has the bats tests. `test/bats` and `test/test_helper/bats-*` are git submodules, and `test/fakes/` has the fake `brew`, `port`, `python3` and `sudo` they run against.
- `.github/workflows/` has the CI and release workflows, and `.github/scripts/` the scripts that build a release's archive and notes.

## Running the tests

```sh
git submodule update --init
make test
make lint
```

`make test` uses `/bin/zsh`. To test another zsh, pass its path: `make test ZSH=/opt/homebrew/bin/zsh`. `make lint` needs shellcheck.

The tests run the script with a temporary `HOME` and a `PATH` of only the fakes, `/usr/bin` and `/bin`, so they don't change the machine they run on or use its own package managers. The tests that fake a terminal need python3, and the ones for the release archive need GNU tar, so they're skipped on macOS.

## zsh 5.8

The script has to run on zsh 5.8, the version macOS 12 ships. CI runs the tests on Linux with Debian 11's zsh 5.8 package, and on macOS 15 with its own zsh.

To get zsh 5.8 on Debian or Ubuntu:

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

The release workflow runs the tests, then publishes a release with `setup-yt-dlp.tar.xz` and its checksum. The script in the repository says its version is `0.0.0-dev`; the copy in the archive gets the tag's. A tag with a hyphen, such as `v1.0.0-beta.2`, becomes a pre-release.

The notes list the commits since the previous `v` tag. A subject starting with Add or Install goes under New, one starting with Fix under Fixes, and the rest under Changes. Commits that only touch tests, CI or this file go in a collapsed section, and a commit that was reverted is left out along with its revert.
