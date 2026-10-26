# Contributing

## Layout

- `src/` has the setup script.
- `bin/` has the downloader scripts.
- `test/` has the bats tests. `test/bats` and `test/test_helper/bats-*` are git submodules.
- `archive/` has the old bash setup script, which the zsh one replaces. It isn't maintained or released.

## Running the tests

```sh
git submodule update --init
make test
make lint
```

`make test` uses `/bin/zsh`. To test another zsh, pass its path: `make test ZSH=/opt/homebrew/bin/zsh`. `make lint` needs shellcheck.

The tests run the script with a temporary `HOME` and stub commands first on `PATH`, so they don't change the machine they run on. The tests that fake a terminal need python3.

## zsh 5.8

The script has to run on zsh 5.8, the version macOS 12 ships. CI runs the tests on Linux with Debian 11's zsh 5.8 package, and on macOS 15 with its own zsh.

To get zsh 5.8 on Debian or Ubuntu:

```sh
curl -fsSLO https://archive.debian.org/debian/pool/main/z/zsh/zsh-common_5.8-6+deb11u1_all.deb
curl -fsSLO https://archive.debian.org/debian/pool/main/z/zsh/zsh_5.8-6+deb11u1_amd64.deb
sudo dpkg -i zsh-common_5.8-6+deb11u1_all.deb zsh_5.8-6+deb11u1_amd64.deb
sudo apt-mark hold zsh zsh-common
```
