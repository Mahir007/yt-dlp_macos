#!@BASH@
# shellcheck shell=bash

# YouTube Downloader Pro for macOS
#
# A template: setup-yt-dlp.zsh downloads it, fills in the @NAME@ values for
# the package manager it used, and saves it where you choose. Needs bash 4
# or later.

# Where the package manager keeps its commands, and which manager it is:
# homebrew or macports.
PREFIX=@PREFIX@
MANAGER=@MANAGER@
# Opened from Finder, the PATH may not have the manager's commands, which
# yt-dlp needs to find ffmpeg.
export PATH="$PREFIX/bin:$PATH"

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

# Add a new format by adding one line here and one key to FORMAT_KEYS.
declare -A FORMATS=(
    [1]="Audio (MP3)|-f ba/b* -x --audio-format mp3 --convert-thumbnails jpg"
    [2]="Video (MP4)|--sub-langs en.* --convert-subs srt --embed-subs --convert-thumbnails jpg -S vcodec:h264 -f bv*[ext=mp4]+ba[ext=m4a]/b*[ext=mp4]"
    [3]="HD Audio (FLAC)|-f ba/b* -x --audio-format flac --convert-thumbnails png"
    [4]="UHD Video (MKV)|--sub-langs en.* --convert-subs ass --embed-subs --convert-thumbnails png -f bv*+ba/b* --merge-output-format mkv"
    [5]="Thumbnail (PNG)|--write-thumbnail --skip-download --convert-thumbnails png"
)
FORMAT_KEYS=(1 2 3 4 5)

check_dependencies() {
    if ! command -v yt-dlp &> /dev/null; then
        error "Error: yt-dlp is not installed or not on your PATH."
        echo -e "Run ${YELLOW}setup-yt-dlp.zsh${NC} again to install it."
        exit 1
    fi
}

update_ytdlp() {
    print_header "Checking for Updates"
    case $MANAGER in
        homebrew)
            brew upgrade -q yt-dlp || true
            python3 -m pip install --user --break-system-packages -Uq yt-dlp-ejs || true
            ;;
        macports)
            info "MacPorts needs your password to update yt-dlp."
            sudo port -q selfupdate && sudo port -qN upgrade yt-dlp yt-dlp-ejs || true
            ;;
    esac
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

        if yt-dlp "${opts[@]}" "$url"; then
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

        case "${choice,,}" in
            m) break ;;
            q) clear; success "Goodbye!"; exit 0 ;;
        esac
    done
}

main_menu() {
    while true; do
        clear
        echo -e "${BLUE}========================================${NC}"
        echo -e "          ${BOLD}${CYAN}YouTube Downloader Pro${NC}"
        echo -e "${BLUE}========================================${NC}"

        for key in "${FORMAT_KEYS[@]}"; do
            local label="${FORMATS[$key]%%|*}"
            echo -e "  ${YELLOW}${key}.${NC} ${label} Downloader"
        done
        echo -e "  ${YELLOW}q.${NC} Exit"
        echo -e "${BLUE}========================================${NC}"
        echo ""

        read -r -p "Type the option number and press ENTER: " choice
        choice="${choice,,}"

        if [[ "$choice" == "q" ]]; then
            clear
            success "Goodbye!"
            exit 0
        fi

        if [[ -n "${FORMATS[$choice]:-}" ]]; then
            local entry="${FORMATS[$choice]}"
            download_loop "${entry%%|*}" "${entry#*|}"
        else
            error "Invalid selection."
            sleep 1
        fi
    done
}

# --- Script Start ---
check_dependencies
update_ytdlp
main_menu
