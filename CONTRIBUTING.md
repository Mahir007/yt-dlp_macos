# Contributing

## Layout

- `src/` has the two setup scripts and the downloader scripts. `setup-yt-dlp-standalone.zsh` installs yt-dlp_macos, ffmpeg and ffprobe into `/usr/local/bin`, and the yt-dlp-apple-webkit-jsi plugin into yt-dlp's plugins folder, without a package manager. `youtube-downloader-pro.command` is a template: the setup script downloads it from the release's tag (from `main` for version `0.0.0-dev`, and from the commit for a CI build) and fills in `@BASH@`, `@PREFIX@` and `@MANAGER@`. The standalone script saves `youtube-downloader-pro-standalone.command` as it is.
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

The setup script has to run on zsh 5.8, the version macOS 12 ships, and the standalone script on zsh 5.7.1, the version macOS 10.15 ships. CI runs the tests on Linux with Debian 11's zsh 5.8 package and Debian 10's zsh 5.7.1 package, and on the latest macOS with its own zsh.

zsh 5.7.1 has no `zparseopts -F`, which is why the standalone script parses its options differently.

To get zsh 5.8 on Debian or Ubuntu (for 5.7.1, the files are `zsh-common_5.7.1-1+deb10u1_all.deb` and `zsh_5.7.1-1+deb10u1_amd64.deb`):

```sh
curl -fsSLO https://archive.debian.org/debian/pool/main/z/zsh/zsh-common_5.8-6+deb11u1_all.deb
curl -fsSLO https://archive.debian.org/debian/pool/main/z/zsh/zsh_5.8-6+deb11u1_amd64.deb
sudo dpkg -i zsh-common_5.8-6+deb11u1_all.deb zsh_5.8-6+deb11u1_amd64.deb
sudo apt-mark hold zsh zsh-common
```

## Commits

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>[optional scope][!]: <description>
```

The release notes are written from them, so the type says who a change is for. `feat` and `fix` are changes users of the scripts see, and `perf` and `docs` are listed in the notes too. Use `docs(contributing)` for this file, and `test`, `ci`, `build`, `refactor`, `style` or `chore` for everything else, even when it adds or fixes something. Mark a breaking change with `!` and a `BREAKING CHANGE:` footer that says what users have to do differently. A revert keeps the `This reverts commit <hash>.` line that `git revert` writes.

The type decides the next version: a breaking change bumps the major, `feat` the minor, and anything else the patch.

## Releasing

Push a tag for the version:

```sh
git tag -a v1.0.0-beta.2 -m "v1.0.0-beta.2"
git push origin v1.0.0-beta.2
```

The scripts in the repository say their version is `0.0.0-dev`. CI builds `setup-yt-dlp.tar.xz` and `setup-yt-dlp-standalone.tar.xz` on every push, with a version in the copies of the scripts in them, and checks that macOS's tar extracts them and the scripts start. On a branch the version is `0.0.0-dev+<commit>`, and the archives are kept for a day as the run's `release` artifact.

The release workflow runs CI with the tag's version, then publishes a release with CI's archives, their checksums and an attestation of where they were built. A tag with a hyphen, such as `v1.0.0-beta.2`, becomes a pre-release. Pre-releases are `-alpha.N`, `-beta.N` or `-rc.N`, counting from 1, and the copies of the scripts in their archives have the commit too, such as `1.0.0-beta.2+1a2b3c4`.

The notes list the commits since the previous tag for a pre-release, and since the previous final release for a final release, so they include its pre-releases. Breaking changes, features, fixes, performance and documentation get their own sections, with the text of a `BREAKING CHANGE:` footer. Other commits go in a collapsed section, and a reverted commit is left out with its revert.

The download table lists the archives the release's `.sha256` files name, with the labels in `file_labels` at the top of `.github/scripts/release-notes.sh`, and links the README's quick start at the tag. A new kind of archive needs an entry there. A second `-m` on the tag adds a summary at the top of the notes:

```sh
git tag -a v1.1.0 -m "v1.1.0" -m "A sentence or two about the release."
```

To preview the notes for a tag, with its `.sha256` files:

```sh
.github/scripts/release-notes.sh v1.0.0 Mahir007/yt-dlp_macos dist/*.sha256
```
