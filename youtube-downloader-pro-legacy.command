#!/bin/bash

# YouTube Downloader Pro for macOS
# Compatible with the legacy built-in Bash-3.2.

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}$*${NC}"; }
success() { echo -e "${GREEN}$*${NC}"; }
error()   { echo -e "${RED}$*${NC}"; }

print_header() {
    local title="$1"
    echo -e "${BLUE}========================================${NC}"
    echo -e "  ${BOLD}${CYAN}${title}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# Add a new format by appending one entry to each array below.
FORMAT_LABELS=(
    "Audio (MP3)"
    "Video (MP4)"
    "HD Audio (FLAC)"
    "UHD Video (MKV)"
    "Thumbnail (PNG)"
)
FORMAT_OPTS=(
    "-f ba/b* -x --audio-format mp3 --convert-thumbnails jpg"
    "--sub-langs en.* --convert-subs srt --embed-subs --convert-thumbnails jpg -S vcodec:h264 -f bv*[ext=mp4]+ba[ext=m4a]/b*[ext=mp4]"
    "-f ba/b* -x --audio-format flac --convert-thumbnails png"
    "--sub-langs en.* --convert-subs ass --embed-subs --convert-thumbnails png -f bv*+ba/b* --merge-output-format mkv"
    "--write-thumbnail --skip-download --convert-thumbnails png"
)

check_dependencies() {
    if ! command -v yt-dlp_macos &> /dev/null; then
        error "Error: yt-dlp is not installed or not on your PATH."
        echo -e "Download from ${YELLOW}https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos${NC}"
        exit 1
    fi
}

update_ytdlp() {
    print_header "Checking for Updates"
    yt-dlp_macos -U
    echo ""
    sleep 1
}

# Arguments: $1 = label, $2 = space-separated yt-dlp options
download_loop() {
    local label="$1" flags_str="$2"
    local -a opts
    read -ra opts <<< "$flags_str"

    # Drop format for plain titles
    local title="${label%% (*}"

    while true; do
        clear
        echo -e "${BOLD}${CYAN}${title} Downloader${NC}"
        echo ""

        read -r -p "Please enter the YouTube URL: " url

        [[ -z "$url" ]] && break

        echo -e "\n${BLUE}Starting download...${NC}\n"

        if yt-dlp_macos "${opts[@]}" "$url"; then
            success "\nDownload completed successfully!"
        else
            error "\nDownload failed. Please verify the URL and try again."
        fi

        echo -e "\n------------------------------------------"
        echo -e "What would you like to do next?"
        echo ""
        echo -e "  Press ${YELLOW}ENTER${NC} to download another file"
        echo ""
        echo -e "  OR:"
        echo -e "      - Type ${YELLOW}M${NC} to return to the main menu"
        echo -e "      - Type ${YELLOW}Q${NC} to quit"
        echo ""
        echo -e "YouTube Downloader Pro (macOS)"
        echo -e "------------------------------------------"
        read -rsn1 choice
        echo ""

        case "$choice" in
            [Mm]) break ;;
            [Qq]) clear; success "Goodbye!"; exit 0 ;;
        esac
    done
}

main_menu() {
    while true; do
        clear
        echo -e "${BLUE}========================================${NC}"
        echo -e "          ${BOLD}${CYAN}YouTube Downloader Pro${NC}"
        echo -e "${BLUE}========================================${NC}"

        local i=0
        while [ "$i" -lt "${#FORMAT_LABELS[@]}" ]; do
            echo -e "  ${YELLOW}$((i + 1)).${NC} ${FORMAT_LABELS[$i]} Downloader"
            i=$((i + 1))
        done
        echo -e "  ${YELLOW}q.${NC} Exit"
        echo -e "${BLUE}========================================${NC}"
        echo ""

        read -r -p "Type the option number and press ENTER: " choice

        case "$choice" in
            [Qq])
                clear
                success "Goodbye!"
                exit 0
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#FORMAT_LABELS[@]}" ]; then
                    local idx=$((choice - 1))
                    download_loop "${FORMAT_LABELS[$idx]}" "${FORMAT_OPTS[$idx]}"
                else
                    error "Invalid selection."
                    sleep 1
                fi
                ;;
        esac
    done
}

# --- Script Start ---
check_dependencies
update_ytdlp
main_menu
