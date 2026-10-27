# yt-dlp_macos

`setup-yt-dlp.zsh` installs [yt-dlp](https://github.com/yt-dlp/yt-dlp) on macOS with Homebrew or MacPorts, along with ffmpeg, deno and the Python packages yt-dlp can use. It can also show what's installed and remove it again.

It needs macOS 12 or later, and Homebrew or MacPorts.

## Quick start

Download `setup-yt-dlp.tar.xz` from [Releases](https://github.com/Mahir007/yt-dlp_macos/releases), then, from the folder it's in:

```sh
tar -xf setup-yt-dlp.tar.xz
./setup-yt-dlp.zsh
```

When it's done, open a new terminal window to use yt-dlp.

## What it installs

|                 | Homebrew | MacPorts |
| --------------- | -------- | -------- |
| Packages        | bash, ffmpeg, atomicparsley, python3, deno | bash, ffmpeg, AtomicParsley, py-pip, deno |
| Python packages | websockets, requests, mutagen, pycryptodomex, curl-cffi, yt-dlp-ejs, with pip into your user site-packages | The same, as ports: py-websockets, py-requests, py-mutagen, py-pycryptodomex, py-curl-cffi, yt-dlp-ejs |
| yt-dlp          | yt-dlp | yt-dlp, without its ffmpeg variant |
| Settings        | A marked block in `~/.zshrc` that sets `HOMEBREW_NO_ENV_HINTS=1` and puts pip's user folder on `PATH` | `python`, `python3`, `pip` and `pip3` point at MacPorts' newest Python |

Anything you already have is left as it is. If you keep your zsh files in `$ZDOTDIR`, the block goes in `$ZDOTDIR/.zshrc`.

## Usage

```
./setup-yt-dlp.zsh [options]
```

| Option | |
| ------ | - |
| `-m`, `--manager <name>` | Use `homebrew` or `macports`. Without it, the script uses the one it used before, or the one that's installed, and asks if both are. |
| `-u`, `--uninstall` | Remove what the script installed. |
| `-s`, `--status` | Show what's installed. |
| `-d`, `--downloader` | Only save [YouTube Downloader Pro](#youtube-downloader-pro). Installs nothing. |
| `-o`, `--output <path>` | Where `--downloader` saves it: a folder, or a file name. The default is `~/Downloads`. |
| `-n`, `--dry-run` | Show what would be done without changing anything. |
| `-y`, `--yes` | Don't ask questions. Picks Homebrew when both are installed. |
| `-v`, `--verbose` | Show the output of brew, port and pip as they run. |
| `--no-color` | Don't use colors. Setting `NO_COLOR` does the same. |
| `-h`, `--help` | Show the options. |
| `-V`, `--version` | Show the version. |

Run again after an install, the script asks whether to repair (install anything that's missing), uninstall, or quit. With `--yes` it repairs.

With MacPorts, the script asks for your password once, when it first needs it.

## YouTube Downloader Pro

YouTube Downloader Pro is a menu for downloading audio (MP3 or FLAC), video (MP4 or MKV) or a thumbnail with yt-dlp. At the end of an install, the script asks whether to download it. If you say yes, a save dialog opens in Downloads. Double-click the saved file to start it.

The script fills it in for the package manager it used. Each time it starts, it updates yt-dlp. With MacPorts, it asks for your password only when there's an update.

To save it without installing anything, for example to get it again:

```sh
./setup-yt-dlp.zsh --downloader
```

If the file is there already, the script asks before replacing it, or replaces it with `--yes`.

## Uninstalling

```sh
./setup-yt-dlp.zsh --uninstall
```

The script lists what it will remove and asks before it starts. It removes only what it installed: packages you had before stay, and so do dependencies and Python packages that something else needs. It takes its block out of `~/.zshrc`, and deletes the file if it created it and nothing else has been added. With MacPorts, `port select` goes back to what it was. A saved YouTube Downloader Pro is left alone.

What the script installed is recorded in `~/Library/Application Support/yt-dlp-setup/state`. If that file is deleted, `--uninstall` has nothing to remove.

## Troubleshooting

### "neither Homebrew nor MacPorts is installed"

Install Apple's command line tools with `xcode-select --install`, then Homebrew from its [releases](https://github.com/Homebrew/brew/releases/latest), or the MacPorts release for your version of macOS from [its releases](https://github.com/macports/macports-base/releases/latest). Then run the script again.

### A package failed

The summary at the end lists what failed. Installing and uninstalling write a log to `~/Library/Logs/yt-dlp-setup/` with the full output of every command; `--verbose` shows it as it happens. Run the script again to retry. It skips what's already installed.

### "yt-dlp was set up with Homebrew; run with --uninstall first to switch to MacPorts"

The script works with one package manager at a time. To switch, uninstall, then run it with `--manager macports` (or `homebrew`).

### yt-dlp isn't found after installing

Open a new terminal window. `--status` shows whether anything is missing.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
