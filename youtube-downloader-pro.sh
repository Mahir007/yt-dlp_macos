#!/bin/bash

# YouTube Downloader Pro for macOS
# Compatible with the default macOS Bash 3.2.

set -o pipefail

set_title() {
    printf '\033]0;%s\007' "YouTube Downloader Pro"
}

pause_for_exit() {
    echo
    printf "Press Enter to exit..."
    read -r _
}

clear_screen() {
    clear 2>/dev/null || printf '\033c'
}

check_dependencies() {
    if ! command -v yt-dlp >/dev/null 2>&1; then
        echo "yt-dlp was not found."
        echo "Install it with: brew install yt-dlp"
        pause_for_exit
        exit 1
    fi
}

check_for_updates() {
    echo
    echo "===================="
    echo "Checking for updates"
    echo "===================="

    if command -v brew >/dev/null 2>&1; then
        HOMEBREW_NO_ENV_HINTS=1 brew upgrade -q yt-dlp
    else
        echo "Homebrew was not found, so yt-dlp could not be updated automatically."
        echo "Install Homebrew from: https://brew.sh"
    fi

    echo
}

prompt_url() {
    printf "Please enter the YouTube URL: "
    read -r URL
    echo

    if [ -z "$URL" ]; then
        echo "No URL entered."
        return 1
    fi

    return 0
}

menu() {
    while true; do
        clear_screen
        echo
        echo "=================="
        echo "Select Downloader:"
        echo "=================="
        echo
        echo "1: Audio (MP3) Downloader"
        echo "2: Video (MP4) Downloader"
        echo "3: HD Audio (FLAC) Downloader"
        echo "4: UHD Video (MKV) Downloader"
        echo "5: Thumbnail (PNG) Downloader"
        echo
        printf "Type 1, 2, 3, 4 or 5 then press ENTER: "
        read -r choice

        case "$choice" in
            1) download_mp3 ;;
            2) download_mp4 ;;
            3) download_flac ;;
            4) download_mkv ;;
            5) download_png ;;
        esac
    done
}

done_prompt() {
    current_label="$1"
    repeat_choice="$2"

    echo
    echo
    echo "-----------------------------------------"
    echo "DONE!"
    echo
    echo " Type 1 to download another $current_label"
    echo
    echo " OR:"
    echo "    - Type 2 to use the \"MP3\" downloader"
    echo "    - Type 3 to use the \"MP4\" downloader"
    echo "    - Type 4 to use the \"FLAC\" downloader"
    echo "    - Type 5 to use the \"MKV\" downloader"
    echo "    - Type 6 to use the \"PNG\" downloader"
    echo
    echo "Otherwise you may simply exit the program"
    echo "-----------------------------------------"
    echo
    echo
    printf "Enter Your Choice: "
    read -r next_choice

    case "$next_choice" in
        1) "$repeat_choice" ;;
        2) download_mp3 ;;
        3) download_mp4 ;;
        4) download_flac ;;
        5) download_mkv ;;
        6) download_png ;;
        *) exit 0 ;;
    esac
}

download_mp3() {
    clear_screen
    echo "Audio Downloader"
    echo
    prompt_url || download_mp3

    yt-dlp -f 'ba/b*' -x --audio-format mp3 --convert-thumbnails jpg "$URL"
    done_prompt "MP3" download_mp3
}

download_mp4() {
    clear_screen
    echo "Video Downloader"
    echo
    prompt_url || download_mp4

    yt-dlp --sub-langs 'en.*' --convert-subs srt --embed-subs --convert-thumbnails jpg -S 'vcodec:h264' -f 'bv*[ext=mp4]+ba[ext=m4a]/b*[ext=mp4]' "$URL"
    done_prompt "MP4" download_mp4
}

download_flac() {
    clear_screen
    echo "HD Audio Downloader"
    echo
    prompt_url || download_flac

    yt-dlp -f 'ba/b*' -x --audio-format flac --convert-thumbnails png "$URL"
    done_prompt "FLAC" download_flac
}

download_mkv() {
    clear_screen
    echo "UHD Video Downloader"
    echo
    prompt_url || download_mkv

    yt-dlp --sub-langs 'en.*' --convert-subs ass --embed-subs --convert-thumbnails png -f 'bv*+ba/b*' --merge-output-format mkv "$URL"
    done_prompt "MKV" download_mkv
}

download_png() {
    clear_screen
    echo "Thumbnail Downloader"
    echo
    prompt_url || download_png

    yt-dlp --write-thumbnail --skip-download --convert-thumbnails png "$URL"
    done_prompt "PNG" download_png
}

set_title
check_for_updates
check_dependencies
menu
