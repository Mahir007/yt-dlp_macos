#!/bin/bash

# macOS yt-dlp Dependency Installer
# Compatible with bash-3.2

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track failures
FAILED_PACKAGES=""
FAILED_PIP_PACKAGES=""

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Phase 1: Package Manager Detection
detect_package_manager() {
    local has_brew=false
    local has_macports=false
    
    if command_exists brew; then
        has_brew=true
        print_info "Homebrew detected"
    fi
    
    if command_exists port; then
        has_macports=true
        print_info "MacPorts detected"
    fi
    
    if [ "$has_brew" = true ] && [ "$has_macports" = true ]; then
        # Both installed - prompt user
        echo ""
        print_warning "Both Homebrew and MacPorts are installed."
        echo "Please choose which package manager to use:"
        echo "  1) Homebrew (recommended)"
        echo "  2) MacPorts"
        echo ""
        printf "Enter your choice (1 or 2): "
        read -r choice
        
        case "$choice" in
            1)
                PACKAGE_MANAGER="homebrew"
                print_info "Using Homebrew"
                ;;
            2)
                PACKAGE_MANAGER="macports"
                print_info "Using MacPorts"
                ;;
            *)
                print_error "Invalid choice. Please run the script again."
                exit 1
                ;;
        esac
    elif [ "$has_brew" = true ]; then
        PACKAGE_MANAGER="homebrew"
        print_info "Using Homebrew"
    elif [ "$has_macports" = true ]; then
        PACKAGE_MANAGER="macports"
        print_info "Using MacPorts"
    else
        # Neither installed
        print_error "Neither Homebrew nor MacPorts is installed."
        echo ""
        echo "Please install one of the following package managers:"
        echo ""
        echo "First, run: xcode-select --install"
        echo ""
        echo "Then choose one:"
        echo ""
        echo "Homebrew (recommended):"
        echo "  Download and install from: https://github.com/Homebrew/brew/releases/latest"
        echo ""
        echo "MacPorts:"
        echo "  Download and install the correct version for your OS:"
        echo "  https://github.com/macports/macports-base/releases/latest"
        echo ""
        printf "Press Enter to exit..."
        read -r
        exit 1
    fi
}

# Function to check if a Homebrew package is installed
brew_package_installed() {
    brew list "$1" >/dev/null 2>&1
}

# Function to check if a MacPorts package is installed
macports_package_installed() {
    port installed "$1" 2>/dev/null | grep -q "  $1 @"
}

# Function to check if a package is installed
package_installed() {
    local package="$1"
    if [ "$PACKAGE_MANAGER" = "homebrew" ]; then
        brew_package_installed "$package"
    else
        macports_package_installed "$package"
    fi
}

# Function to install a Homebrew package
install_brew_package() {
    local package="$1"
    print_info "Installing $package via Homebrew..."
    if brew install -q "$package"; then
        print_success "$package installed successfully"
        echo ""
        return 0
    else
        print_error "Failed to install $package"
        echo ""
        FAILED_PACKAGES="$FAILED_PACKAGES $package"
        return 1
    fi
}

# Function to install a MacPorts package
install_macports_package() {
    local package="$1"
    print_info "Installing $package via MacPorts..."
    if sudo port -q install "$package"; then
        print_success "$package installed successfully"
        echo ""
        return 0
    else
        print_error "Failed to install $package"
        echo ""
        FAILED_PACKAGES="$FAILED_PACKAGES $package"
        return 1
    fi
}

# Function to install a package
install_package() {
    local package="$1"
    if [ "$PACKAGE_MANAGER" = "homebrew" ]; then
        install_brew_package "$package"
    else
        install_macports_package "$package"
    fi
}

# Function to configure Homebrew
configure_homebrew() {
    print_info "Configuring Homebrew to suppress environment hints..."
    
    # Always export for current session
    export HOMEBREW_NO_ENV_HINTS=1
    
    # Add it permanently to ~/.zshrc
    local zshrc_file="$HOME/.zshrc"
    if grep -q "HOMEBREW_NO_ENV_HINTS" "$zshrc_file" 2>/dev/null; then
        print_info "HOMEBREW_NO_ENV_HINTS is already configured in $zshrc_file"
    else
        # Add to .zshrc
        echo "" >> "$zshrc_file"
        echo "# Suppress Homebrew environment hints" >> "$zshrc_file"
        echo "export HOMEBREW_NO_ENV_HINTS=1" >> "$zshrc_file"
        print_success "Disabled environment hints in $zshrc_file config"
    fi
}

# Function to configure MacPorts
configure_macports() {
    # MacPorts config file location (default)
    local config_file="/opt/local/etc/macports/macports.conf"
    
    if [ ! -f "$config_file" ]; then
        print_error "MacPorts config file not found at $config_file"
        return 1
    fi
    
    print_info "Enabling binary archives in MacPorts configuration..."
    
    # Check if the line is already uncommented
    if grep -q "^buildfromsource[[:space:]]*ifneeded" "$config_file"; then
        print_info "Binary archives are already enabled in MacPorts configuration."
        return 0
    fi
    
    # Check if the line exists commented out
    if grep -q "^#[[:space:]]*buildfromsource[[:space:]]*ifneeded" "$config_file"; then
        # Use sed to uncomment the line (bash-3.2 compatible)
        # Create a backup first
        if sudo cp "$config_file" "${config_file}.backup"; then
            # Uncomment the line - remove # and preserve any whitespace/tabs after
            # Match: #buildfromsource followed by whitespace/tabs and ifneeded
            # Replace: buildfromsource followed by tabs and ifneeded
            if sudo sed -i '' 's/^#\(buildfromsource[[:space:]]*ifneeded\)/\1/' "$config_file"; then
                print_success "Successfully enabled in MacPorts configuration."
                return 0
            else
                print_error "Failed to update MacPorts configuration."
                # Restore backup
                sudo mv "${config_file}.backup" "$config_file"
                return 1
            fi
        else
            print_error "Failed to create backup of MacPorts configuration."
            return 1
        fi
    else
        print_warning "Could not find buildfromsource configuration line in MacPorts config."
        print_info "You may need to manually configure binary archives."
        return 0
    fi
}

# Function to configure MacPorts Python selection
configure_macports_python() {
    # Check if python313 is installed via MacPorts
    if ! package_installed "python313"; then
        return 0
    fi
    
    print_info "Configuring MacPorts Python selection..."
    
    # Set python and python3 to python313
    if sudo port select --set python python313 >/dev/null 2>&1; then
        print_success "Set python to python313"
    else
        print_error "Failed to set python to python313"
    fi
    
    if sudo port select --set python3 python313 >/dev/null 2>&1; then
        print_success "Set python3 to python313"
    else
        print_error "Failed to set python3 to python313"
    fi
    
    # Set pip and pip3 to pip313 (if py-pip is installed)
    if package_installed "py-pip"; then
        if sudo port select --set pip pip313 >/dev/null 2>&1; then
            print_success "Set pip to pip313"
        else
            print_error "Failed to set pip to pip313"
        fi
        
        if sudo port select --set pip3 pip313 >/dev/null 2>&1; then
            print_success "Set pip3 to pip313"
        else
            print_error "Failed to set pip3 to pip313"
        fi
    fi
    
    # Refresh command cache to use new python/pip commands immediately
    hash -r 2>/dev/null || true
}

# Function to get system packages for the chosen package manager
get_system_packages() {
    local pm="$1"
    local packages=""
    
    if [ "$pm" = "homebrew" ]; then
        packages="bash ffmpeg atomicparsley python3 deno"
    elif [ "$pm" = "macports" ]; then
        packages="ffmpeg8 py-pip deno"
    fi
    
    echo "$packages"
}

# Function to check if a pip package is installed
pip3_package_installed() {
    pip3 show "$1" >/dev/null 2>&1
}

# Function to install a pip package
install_pip3_package() {
    local package="$1"
    print_info "Installing $package via pip3..."
    if pip3 install "$package"; then
        print_success "$package installed successfully"
        echo ""
        return 0
    else
        print_error "Failed to install $package"
        echo ""
        FAILED_PIP_PACKAGES="$FAILED_PIP_PACKAGES $package"
        return 1
    fi
}

# Function to configure pip for MacPorts Python
configure_macports_pip() {
    # Get pip config directory (standard location)
    local pip_config_dir="$HOME/.config/pip"
    local pip_config_file="$pip_config_dir/pip.conf"
    
    # Create directory if it doesn't exist
    mkdir -p "$pip_config_dir"
    
    print_info "Configuring pip settings for MacPorts Python..."
    
    # Check if user setting is already present
    if [ -f "$pip_config_file" ] && grep -q "user = true" "$pip_config_file" 2>/dev/null; then
        print_info "Pip settings are already configured"
    else
        # Add or update config file
        {
            echo "[install]"
            echo "user = true"
        } >> "$pip_config_file"
        print_success "Configured pip settings in $pip_config_file"
    fi
    
    # Add pip scripts directory to PATH
    local python_user_base
    python_user_base=$(python3 -m site --user-base 2>/dev/null)
    if [ -n "$python_user_base" ]; then
        local pip_scripts_dir="${python_user_base}/bin"
        
        # Add to current session PATH
        export PATH="$pip_scripts_dir:$PATH"
        
        # Add permanently to ~/.zshrc
        local zshrc_file="$HOME/.zshrc"
        if ! grep -q "$pip_scripts_dir" "$zshrc_file" 2>/dev/null; then
            {
                echo ""
                echo "# Add pip user scripts to PATH"
                echo "export PATH=\"$pip_scripts_dir:\$PATH\""
            } >> "$zshrc_file"
            print_success "Added pip scripts directory to PATH in $zshrc_file"
        fi
    fi
}

# Function to configure pip for Homebrew Python
configure_homebrew_pip() {
    # Get pip config directory (standard location)
    local pip_config_dir="$HOME/.config/pip"
    local pip_config_file="$pip_config_dir/pip.conf"
    
    # Create directory if it doesn't exist
    mkdir -p "$pip_config_dir"
    
    print_info "Configuring pip settings for Homebrew Python..."
    
    # Check if settings are already present
    if [ -f "$pip_config_file" ] && \
       grep -q "break-system-packages" "$pip_config_file" 2>/dev/null && \
       grep -q "user = true" "$pip_config_file" 2>/dev/null; then
        print_info "Pip settings are already configured"
    else
        # Add required settings
        {
            echo "[global]"
            echo "break-system-packages = true"
            echo ""
            echo "[install]"
            echo "user = true"
        } >> "$pip_config_file"
        print_success "Configured pip settings in $pip_config_file"
    fi
    
    # Add pip scripts directory to PATH
    local python_user_base
    python_user_base=$(python3 -m site --user-base 2>/dev/null)
    if [ -n "$python_user_base" ]; then
        local pip_scripts_dir="${python_user_base}/bin"
        
        # Add to current session PATH
        export PATH="$pip_scripts_dir:$PATH"
        
        # Add permanently to ~/.zshrc
        local zshrc_file="$HOME/.zshrc"
        if ! grep -q "$pip_scripts_dir" "$zshrc_file" 2>/dev/null; then
            {
                echo ""
                echo "# Add pip user scripts to PATH"
                echo "export PATH=\"$pip_scripts_dir:\$PATH\""
            } >> "$zshrc_file"
            print_success "Added pip scripts directory to PATH in $zshrc_file"
        fi
    fi
}

# Function to check and install pip packages
check_and_install_pip_packages() {
    # Install package manager-specific Python packages
    if [ "$PACKAGE_MANAGER" = "homebrew" ]; then
        local packages="websockets requests mutagen pycryptodomex"
        for package in $packages; do
            if pip3_package_installed "$package"; then
                print_success "$package is already installed"
                echo ""
            else
                install_pip3_package "$package" || true
            fi
        done
    elif [ "$PACKAGE_MANAGER" = "macports" ]; then
        local packages="py-websockets py-requests py-mutagen py-pycryptodomex"
        for package in $packages; do
            if package_installed "$package"; then
                print_success "$package is already installed"
                echo ""
            else
                install_package "$package" || true
            fi
        done
    fi
    
    # Install pip packages for both package managers
    for package in curl-cffi yt-dlp-ejs; do
        if pip3_package_installed "$package"; then
            print_success "$package is already installed"
            echo ""
        else
            install_pip3_package "$package" || true
        fi
    done
}

# ============================================================================
# UNINSTALLER FUNCTIONS
# ============================================================================

# ----------------------------------------------------------------------------
# Utility Functions
# ----------------------------------------------------------------------------

# Function to reverse a space-separated list of packages
reverse_package_list() {
    local packages="$1"
    local reversed=""
    for package in $packages; do
        reversed="$package $reversed"
    done
    # Trim trailing space
    echo "$reversed" | sed 's/[[:space:]]*$//'
}

# ----------------------------------------------------------------------------
# Single Package Uninstall Functions
# ----------------------------------------------------------------------------

# Function to uninstall a Homebrew package
uninstall_brew_package() {
    local package="$1"
    if brew_package_installed "$package"; then
        print_info "Uninstalling $package via Homebrew..."
        if brew uninstall "$package" 2>/dev/null; then
            print_success "$package uninstalled successfully"
            echo ""
            return 0
        else
            print_warning "Failed to uninstall $package (may be a dependency of other packages)"
            echo ""
            return 1
        fi
    else
        print_info "$package is not installed, skipping"
        echo ""
        return 0
    fi
}

# Function to uninstall a single MacPorts package
uninstall_macports_package() {
    local package="$1"
    if macports_package_installed "$package"; then
        print_info "Uninstalling $package via MacPorts..."
        if sudo port uninstall "$package" 2>/dev/null; then
            print_success "$package uninstalled successfully"
            echo ""
            return 0
        else
            print_warning "Failed to uninstall $package (may be a dependency of other packages)"
            echo ""
            return 1
        fi
    else
        print_info "$package is not installed, skipping"
        echo ""
        return 0
    fi
}

# Function to uninstall a package (dispatcher)
uninstall_package() {
    local package="$1"
    if [ "$PACKAGE_MANAGER" = "homebrew" ]; then
        uninstall_brew_package "$package"
    else
        uninstall_macports_package "$package"
    fi
}

# ----------------------------------------------------------------------------
# Full System Package Uninstall Functions
# ----------------------------------------------------------------------------

# Function to uninstall all Homebrew packages
uninstall_homebrew_packages() {
    # Get system packages for Homebrew
    # Note: yt-dlp is not included here as it's already uninstalled in Phase 1
    local packages
    packages=$(get_system_packages "homebrew")
    
    # Reverse the package list to uninstall in reverse installation order
    packages=$(reverse_package_list "$packages")
    
    # Uninstall packages in reverse order
    for package in $packages; do
        uninstall_brew_package "$package"
    done
}

# Function to uninstall all MacPorts packages (full uninstallation)
uninstall_macports_packages() {
    # Reverse port select changes BEFORE uninstalling py-pip
    # This must happen before py-pip is removed
    print_info "Reversing MacPorts port select changes..."
    
    if command_exists port; then
        # Unset python selections
        if sudo port select --set python none 2>&1 | grep -q "succeeded"; then
            print_success "Unset python selection"
        fi
        
        if sudo port select --set python3 none 2>&1 | grep -q "succeeded"; then
            print_success "Unset python3 selection"
        fi
        
        if sudo port select --set pip none 2>&1 | grep -q "succeeded"; then
            print_success "Unset pip selection"
        fi
        
        if sudo port select --set pip3 none 2>&1 | grep -q "succeeded"; then
            print_success "Unset pip3 selection"
        fi
    fi
    echo ""
    
    # Uninstall MacPorts Python packages first (in reverse installation order)
    # These are installed as system packages, not pip packages
    local python_packages="py-pycryptodomex py-mutagen py-requests py-websockets"
    for package in $python_packages; do
        uninstall_macports_package "$package"
    done
    
    # Get system packages for MacPorts
    local packages
    packages=$(get_system_packages "macports")
    
    # Reverse the package list to uninstall in reverse installation order
    packages=$(reverse_package_list "$packages")
    
    # Uninstall packages in reverse order
    for package in $packages; do
        uninstall_macports_package "$package"
    done
    
    # Clean up orphaned dependencies (packages no longer needed after uninstalling)
    print_info "Cleaning up orphaned dependencies..."
    if sudo port uninstall rleaves >/dev/null 2>&1; then
        print_success "Cleaned up orphaned dependencies"
        echo ""
    else
        print_warning "Failed to clean up orphaned dependencies (may not be needed)"
        echo ""
    fi
}

# ----------------------------------------------------------------------------
# Pip Package Uninstall Functions
# ----------------------------------------------------------------------------

# Function to uninstall pip packages selectively (helper function)
uninstall_pip_packages_selective() {
    # Get list of known pip packages based on package manager (in reverse installation order)
    local packages=""
    if [ "$PACKAGE_MANAGER" = "homebrew" ]; then
        packages="yt-dlp-ejs curl-cffi pycryptodomex mutagen requests websockets"
    elif [ "$PACKAGE_MANAGER" = "macports" ]; then
        packages="yt-dlp-ejs curl-cffi"
    fi
    
    # Uninstall each package (in reverse order)
    for package in $packages; do
        if pip3_package_installed "$package"; then
            print_info "Uninstalling $package via pip3..."
            if pip3 uninstall -y "$package" >/dev/null 2>&1; then
                print_success "$package uninstalled successfully"
                echo ""
            else
                print_warning "Failed to uninstall $package"
                echo ""
            fi
        fi
    done
}

# Function to uninstall pip packages
uninstall_pip_packages() {
    print_info "Uninstalling pip packages..."
    echo ""
    
    # Check if pip3 is available
    if ! command_exists pip3; then
        print_warning "pip3 is not available, skipping pip package uninstallation"
        echo ""
        return 0
    fi
    
    # Get list of known pip packages to uninstall (in reverse installation order)
    local packages=""
    if [ "$PACKAGE_MANAGER" = "homebrew" ]; then
        packages="yt-dlp-ejs curl-cffi pycryptodomex mutagen requests websockets"
    elif [ "$PACKAGE_MANAGER" = "macports" ]; then
        packages="yt-dlp-ejs curl-cffi"
    fi
    
    # Try to install pip-autoremove if not present (for better dependency handling)
    local pip_autoremove_installed=false
    if ! pip3 show pip-autoremove >/dev/null 2>&1; then
        print_info "Installing pip-autoremove temporarily for better dependency handling..."
        if pip3 install pip-autoremove >/dev/null 2>&1; then
            print_success "pip-autoremove installed"
            echo ""
            pip_autoremove_installed=true
        else
            print_warning "Failed to install pip-autoremove, using direct uninstall"
            echo ""
        fi
    fi
    
    # Try to use pip-autoremove if available (removes package and unused dependencies)
    local autoremove_cmd=""
    if command_exists pip-autoremove; then
        autoremove_cmd="pip-autoremove"
    fi
    
    if [ -n "$autoremove_cmd" ]; then
        print_info "Removing pip packages using pip-autoremove (removes unused dependencies too)..."
        local removed_any=false
        for package in $packages; do
            if pip3_package_installed "$package"; then
                if $autoremove_cmd "$package" -y >/dev/null 2>&1; then
                    print_success "$package removed successfully (with unused dependencies)"
                    removed_any=true
                else
                    print_warning "Failed to remove $package with pip-autoremove, trying direct uninstall"
                    pip3 uninstall -y "$package" >/dev/null 2>&1 || true
                fi
            fi
        done
        if [ "$removed_any" = true ]; then
            echo ""
        fi
    else
        # Fallback to direct uninstall
        print_info "Using direct uninstall method..."
        uninstall_pip_packages_selective
    fi
    
    # Uninstall pip-autoremove itself if we installed it
    if [ "$pip_autoremove_installed" = true ]; then
        if pip3 show pip-autoremove >/dev/null 2>&1; then
            print_info "Removing pip-autoremove..."
            pip3 uninstall -y pip-autoremove >/dev/null 2>&1
            echo ""
        fi
    fi
}

# ----------------------------------------------------------------------------
# Cleanup Functions
# ----------------------------------------------------------------------------

# Function to cleanup Homebrew configuration
cleanup_homebrew_config() {
    print_info "Cleaning up Homebrew configuration..."
    
    local zshrc_file="$HOME/.zshrc"
    if [ -f "$zshrc_file" ]; then
        # Exact lines we added during installation
        local expected_comment="# Suppress Homebrew environment hints"
        local expected_export="export HOMEBREW_NO_ENV_HINTS=1"
        
        # Check if file contains our configuration
        if grep -qF "$expected_comment" "$zshrc_file" 2>/dev/null || \
           grep -qF "$expected_export" "$zshrc_file" 2>/dev/null; then
            # Read all lines into an array (bash-3.2 compatible)
            local lines_array=()
            while IFS= read -r line || [ -n "$line" ]; do
                lines_array+=("$line")
            done < "$zshrc_file"
            
            # Mark lines to skip (0 = keep, 1 = skip)
            local skip_array=()
            local i=0
            local array_size=${#lines_array[@]}
            
            # Initialize skip array
            while [ $i -lt $array_size ]; do
                skip_array+=("0")
                i=$((i + 1))
            done
            
            # Mark lines to skip
            i=0
            local removed=false
            while [ $i -lt $array_size ]; do
                local line="${lines_array[$i]}"
                
                # Check if this is our comment line
                if [ "$line" = "$expected_comment" ]; then
                    removed=true
                    # Mark comment line to skip
                    skip_array[$i]="1"
                    
                    # Check if previous line is blank and mark it to skip
                    if [ $i -gt 0 ]; then
                        local prev_line="${lines_array[$((i - 1))]}"
                        if [ -z "$(echo "$prev_line" | tr -d '[:space:]')" ]; then
                            skip_array[$((i - 1))]="1"
                        fi
                    fi
                    
                    # Check if next line is our export and mark it to skip
                    local next_i=$((i + 1))
                    if [ $next_i -lt $array_size ]; then
                        local next_line="${lines_array[$next_i]}"
                        if [ "$next_line" = "$expected_export" ]; then
                            skip_array[$next_i]="1"
                        fi
                    fi
                # Also check for standalone export line (in case comment was removed manually)
                elif [ "$line" = "$expected_export" ]; then
                    removed=true
                    skip_array[$i]="1"
                fi
                
                i=$((i + 1))
            done
            
            # Write lines that are not marked to skip
            local temp_file="${zshrc_file}.tmp"
            > "$temp_file"  # Create empty temp file
            
            i=0
            while [ $i -lt $array_size ]; do
                if [ "${skip_array[$i]}" != "1" ]; then
                    echo "${lines_array[$i]}" >> "$temp_file"
                fi
                i=$((i + 1))
            done
            
            if [ "$removed" = true ]; then
                # Collapse consecutive blank lines and remove trailing blanks
                local temp_lines_array=()
                while IFS= read -r tline || [ -n "$tline" ]; do
                    temp_lines_array+=("$tline")
                done < "$temp_file"
                
                # Find last non-empty line index
                local last_non_empty_idx=-1
                local j=0
                while [ $j -lt ${#temp_lines_array[@]} ]; do
                    local tline="${temp_lines_array[$j]}"
                    if [ -n "$(echo "$tline" | tr -d '[:space:]')" ]; then
                        last_non_empty_idx=$j
                    fi
                    j=$((j + 1))
                done
                
                # Rewrite temp file, collapsing consecutive blank lines and removing trailing blanks
                > "$temp_file"
                j=0
                local prev_was_blank=false
                while [ $j -le $last_non_empty_idx ]; do
                    local tline="${temp_lines_array[$j]}"
                    local is_blank=false
                    if [ -z "$(echo "$tline" | tr -d '[:space:]')" ]; then
                        is_blank=true
                    fi
                    
                    # Only write the line if:
                    # 1. It's not blank, OR
                    # 2. It's blank but the previous line wasn't blank (collapse consecutive blanks)
                    if [ "$is_blank" = false ] || [ "$prev_was_blank" = false ]; then
                        echo "$tline" >> "$temp_file"
                    fi
                    
                    prev_was_blank=$is_blank
                    j=$((j + 1))
                done
                
                mv "$temp_file" "$zshrc_file"
                print_success "Removed HOMEBREW_NO_ENV_HINTS from $zshrc_file"
            else
                # grep found it but exact match didn't - likely modified, skip silently
                rm -f "$temp_file"
            fi
        else
            print_info "HOMEBREW_NO_ENV_HINTS not found in $zshrc_file"
        fi
    else
        print_info ".zshrc file not found"
    fi
    echo ""
}

# Function to cleanup MacPorts configuration
cleanup_macports_config() {
    print_info "Cleaning up MacPorts configuration..."
    
    # Restore macports.conf backup if it exists
    local config_file="/opt/local/etc/macports/macports.conf"
    local backup_file="${config_file}.backup"
    
    if [ -f "$backup_file" ]; then
        print_info "Restoring MacPorts configuration from backup..."
        if sudo mv "$backup_file" "$config_file" 2>/dev/null; then
            print_success "Restored MacPorts configuration from backup"
        else
            print_warning "Failed to restore MacPorts configuration backup"
        fi
    else
        # Try to revert buildfromsource change
        if [ -f "$config_file" ] && grep -q "^buildfromsource[[:space:]]*ifneeded" "$config_file"; then
            print_info "Reverting buildfromsource configuration..."
            if sudo sed -i '' 's/^buildfromsource[[:space:]]*ifneeded/#buildfromsource ifneeded/' "$config_file" 2>/dev/null; then
                print_success "Reverted buildfromsource configuration"
            else
                print_warning "Failed to revert buildfromsource configuration"
            fi
        fi
    fi
    
}

# Function to cleanup pip configuration
cleanup_pip_config() {
    print_info "Cleaning up pip configuration..."
    
    local pip_config_file="$HOME/.config/pip/pip.conf"
    
    if [ -f "$pip_config_file" ]; then
        # Exact lines we added during installation
        local expected_install_line="user = true"
        local expected_global_line="break-system-packages = true"
        
        # Check if file contains our configuration
        if grep -qF "$expected_install_line" "$pip_config_file" 2>/dev/null || \
           grep -qF "$expected_global_line" "$pip_config_file" 2>/dev/null; then
            # Create temp file without our specific lines
            local temp_file="${pip_config_file}.tmp"
            > "$temp_file"  # Create empty temp file
            
            local current_section=""
            local section_lines_array=()
            local section_has_other_content=false
            
            # Helper function to write section if it has content other than our config
            write_section_if_needed() {
                if [ -n "$current_section" ] && [ "$section_has_other_content" = true ]; then
                    # add a newline if this isn't the first section being written
                    if [ -s "$temp_file" ]; then
                        echo "" >> "$temp_file"
                    fi
                    # Section has content other than our config, write it
                    echo "$current_section" >> "$temp_file"
                    # Write all section lines except trailing empty ones
                    local last_non_empty_idx=-1
                    local i=0
                    while [ $i -lt ${#section_lines_array[@]} ]; do
                        local sl="${section_lines_array[$i]}"
                        if [ -n "$(echo "$sl" | tr -d '[:space:]')" ]; then
                            last_non_empty_idx=$i
                        fi
                        i=$((i + 1))
                    done
                    # Write lines up to and including last non-empty
                    i=0
                    while [ $i -lt ${#section_lines_array[@]} ]; do
                        if [ $i -le $last_non_empty_idx ]; then
                            echo "${section_lines_array[$i]}" >> "$temp_file"
                        fi
                        i=$((i + 1))
                    done
                fi
                # Reset for next section
                current_section=""
                section_lines_array=()
                section_has_other_content=false
            }
            
            while IFS= read -r line || [ -n "$line" ]; do
                # Check for section headers
                if echo "$line" | grep -q "^\[install\]"; then
                    # Write previous section if needed
                    write_section_if_needed
                    # Start new install section
                    current_section="$line"
                    section_lines_array=()
                    section_has_other_content=false
                elif echo "$line" | grep -q "^\[global\]"; then
                    # Write previous section if needed
                    write_section_if_needed
                    # Start new global section
                    current_section="$line"
                    section_lines_array=()
                    section_has_other_content=false
                elif echo "$line" | grep -q "^\["; then
                    # Other section header - write previous section if needed, then keep this section
                    write_section_if_needed
                    echo "$line" >> "$temp_file"
                    current_section=""
                    section_lines_array=()
                    section_has_other_content=false
                elif [ -n "$current_section" ]; then
                    # We're in a section (install or global)
                    # Skip exact lines we added
                    if [ "$line" = "$expected_install_line" ] && echo "$current_section" | grep -q "\[install\]"; then
                        # Skip our install config line
                        continue
                    elif [ "$line" = "$expected_global_line" ] && echo "$current_section" | grep -q "\[global\]"; then
                        # Skip our global config line
                        continue
                    else
                        # Add line to section (empty or not)
                        section_lines_array+=("$line")
                        # Mark as having content if line is not empty
                        if [ -n "$(echo "$line" | tr -d '[:space:]')" ]; then
                            section_has_other_content=true
                        fi
                    fi
                else
                    # Not in any section - keep the line as-is
                    echo "$line" >> "$temp_file"
                fi
            done < "$pip_config_file"
            
            # Write final section if needed
            write_section_if_needed
            
            # Collapse consecutive blank lines and remove trailing blanks (bash-3.2 compatible)
            # Read temp file, find last non-empty line, rewrite
            if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
                local temp_lines_array=()
                while IFS= read -r tline || [ -n "$tline" ]; do
                    temp_lines_array+=("$tline")
                done < "$temp_file"
                
                # Find last non-empty line index
                local last_non_empty_idx=-1
                i=0
                while [ $i -lt ${#temp_lines_array[@]} ]; do
                    local tline="${temp_lines_array[$i]}"
                    if [ -n "$(echo "$tline" | tr -d '[:space:]')" ]; then
                        last_non_empty_idx=$i
                    fi
                    i=$((i + 1))
                done
                
                # Rewrite temp file, collapsing consecutive blank lines and removing trailing blanks
                > "$temp_file"
                i=0
                local prev_was_blank=false
                while [ $i -le $last_non_empty_idx ]; do
                    local tline="${temp_lines_array[$i]}"
                    local is_blank=false
                    if [ -z "$(echo "$tline" | tr -d '[:space:]')" ]; then
                        is_blank=true
                    fi
                    
                    # Only write the line if:
                    # 1. It's not blank, OR
                    # 2. It's blank but the previous line wasn't blank (collapse consecutive blanks)
                    if [ "$is_blank" = false ] || [ "$prev_was_blank" = false ]; then
                        echo "$tline" >> "$temp_file"
                    fi
                    
                    prev_was_blank=$is_blank
                    i=$((i + 1))
                done
            fi
            
            # Check if temp file has meaningful content
            if [ -f "$temp_file" ]; then
                local content=$(cat "$temp_file" | tr -d '[:space:]')
                if [ -n "$content" ]; then
                    mv "$temp_file" "$pip_config_file"
                    print_success "Removed pip configuration entries"
                else
                    # File is empty, delete it
                    rm -f "$pip_config_file" "$temp_file"
                    print_success "Removed empty pip configuration file"
                    
                    # Remove directory if it's now empty
                    local pip_config_dir="$HOME/.config/pip"
                    if [ -d "$pip_config_dir" ] && [ -z "$(ls -A "$pip_config_dir" 2>/dev/null)" ]; then
                        rmdir "$pip_config_dir" 2>/dev/null && print_success "Removed empty pip configuration directory"
                    fi
                fi
            fi
        else
            print_info "No pip configuration to remove"
        fi
    else
        print_info "Pip configuration file not found"
    fi
    echo ""
}

# Function to cleanup PATH entries
cleanup_path_config() {
    print_info "Cleaning up PATH configuration..."
    
    local zshrc_file="$HOME/.zshrc"
    if [ -f "$zshrc_file" ]; then
        # Read all lines into an array (bash-3.2 compatible)
        local lines_array=()
        while IFS= read -r line || [ -n "$line" ]; do
            lines_array+=("$line")
        done < "$zshrc_file"
        
        # Mark lines to skip (0 = keep, 1 = skip)
        local skip_array=()
        local i=0
        local array_size=${#lines_array[@]}
        
        # Initialize skip array
        while [ $i -lt $array_size ]; do
            skip_array+=("0")
            i=$((i + 1))
        done
        
        # Mark lines to skip
        i=0
        local removed=false
        while [ $i -lt $array_size ]; do
            local line="${lines_array[$i]}"
            
            # Check if this is our comment line
            if [ "$line" = "# Add pip user scripts to PATH" ]; then
                removed=true
                # Mark comment line to skip
                skip_array[$i]="1"
                
                # Check if previous line is blank and mark it to skip
                if [ $i -gt 0 ]; then
                    local prev_line="${lines_array[$((i - 1))]}"
                    if [ -z "$(echo "$prev_line" | tr -d '[:space:]')" ]; then
                        skip_array[$((i - 1))]="1"
                    fi
                fi
                
                # Check if next line is export PATH and mark it to skip
                local next_i=$((i + 1))
                if [ $next_i -lt $array_size ]; then
                    local next_line="${lines_array[$next_i]}"
                    if echo "$next_line" | grep -qE '^[[:space:]]*export[[:space:]]+PATH='; then
                        skip_array[$next_i]="1"
                    fi
                fi
            fi
            
            i=$((i + 1))
        done
        
        # Write lines that are not marked to skip
        local temp_file="${zshrc_file}.tmp"
        > "$temp_file"  # Create empty temp file
        
        i=0
        while [ $i -lt $array_size ]; do
            if [ "${skip_array[$i]}" != "1" ]; then
                echo "${lines_array[$i]}" >> "$temp_file"
            fi
            i=$((i + 1))
        done
        
        if [ "$removed" = true ]; then
            # Collapse consecutive blank lines and remove trailing blanks
            local temp_lines_array=()
            while IFS= read -r tline || [ -n "$tline" ]; do
                temp_lines_array+=("$tline")
            done < "$temp_file"
            
            # Find last non-empty line index
            local last_non_empty_idx=-1
            local j=0
            while [ $j -lt ${#temp_lines_array[@]} ]; do
                local tline="${temp_lines_array[$j]}"
                if [ -n "$(echo "$tline" | tr -d '[:space:]')" ]; then
                    last_non_empty_idx=$j
                fi
                j=$((j + 1))
            done
            
            # Rewrite temp file, collapsing consecutive blank lines and removing trailing blanks
            > "$temp_file"
            j=0
            local prev_was_blank=false
            while [ $j -le $last_non_empty_idx ]; do
                local tline="${temp_lines_array[$j]}"
                local is_blank=false
                if [ -z "$(echo "$tline" | tr -d '[:space:]')" ]; then
                    is_blank=true
                fi
                
                # Only write the line if:
                # 1. It's not blank, OR
                # 2. It's blank but the previous line wasn't blank (collapse consecutive blanks)
                if [ "$is_blank" = false ] || [ "$prev_was_blank" = false ]; then
                    echo "$tline" >> "$temp_file"
                fi
                
                prev_was_blank=$is_blank
                j=$((j + 1))
            done
            
            mv "$temp_file" "$zshrc_file"
            print_success "Removed pip scripts directory from PATH in $zshrc_file"
        else
            rm -f "$temp_file"
            print_info "No pip PATH entries found in $zshrc_file"
        fi
    else
        print_info ".zshrc file not found"
    fi
    echo ""
}

# Function to cleanup yt-dlp configuration
cleanup_ytdlp_config() {
    print_info "Cleaning up yt-dlp configuration..."
    
    local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
    local ytdlp_config_file="${config_home}/yt-dlp/config"
    
    if [ -f "$ytdlp_config_file" ]; then
        # Exact lines we added during installation
        local expected_comment="# Enable MacPorts version of FFMPEG"
        local expected_ffmpeg_line=" --ffmpeg-location /opt/local/bin/ffmpeg8"
        
        # Check if file contains our configuration
        if grep -qF "$expected_comment" "$ytdlp_config_file" 2>/dev/null || \
           grep -qF "$expected_ffmpeg_line" "$ytdlp_config_file" 2>/dev/null; then
            # Read all lines into an array (bash-3.2 compatible)
            local lines_array=()
            while IFS= read -r line || [ -n "$line" ]; do
                lines_array+=("$line")
            done < "$ytdlp_config_file"
            
            # Mark lines to skip (0 = keep, 1 = skip)
            local skip_array=()
            local i=0
            local array_size=${#lines_array[@]}
            
            # Initialize skip array
            while [ $i -lt $array_size ]; do
                skip_array+=("0")
                i=$((i + 1))
            done
            
            # Mark lines to skip
            i=0
            local removed=false
            while [ $i -lt $array_size ]; do
                local line="${lines_array[$i]}"
                
                # Check if this is our comment line
                if [ "$line" = "$expected_comment" ]; then
                    removed=true
                    # Mark comment line to skip
                    skip_array[$i]="1"
                    
                    # Check if next line is our ffmpeg line and mark it to skip
                    local next_i=$((i + 1))
                    if [ $next_i -lt $array_size ]; then
                        local next_line="${lines_array[$next_i]}"
                        if [ "$next_line" = "$expected_ffmpeg_line" ]; then
                            skip_array[$next_i]="1"
                        fi
                    fi
                # Also check for standalone ffmpeg line (in case comment was removed manually)
                elif [ "$line" = "$expected_ffmpeg_line" ]; then
                    removed=true
                    skip_array[$i]="1"
                fi
                
                i=$((i + 1))
            done
            
            # Write lines that are not marked to skip
            local temp_file="${ytdlp_config_file}.tmp"
            > "$temp_file"  # Create empty temp file
            
            i=0
            while [ $i -lt $array_size ]; do
                if [ "${skip_array[$i]}" != "1" ]; then
                    echo "${lines_array[$i]}" >> "$temp_file"
                fi
                i=$((i + 1))
            done
            
            if [ "$removed" = true ]; then
                # Check if file is empty or only has whitespace
                local content=$(cat "$temp_file" | tr -d '[:space:]')
                if [ -n "$content" ]; then
                    # Remove trailing blank lines from temp file
                    # Find last non-empty line
                    local temp_lines_array=()
                    while IFS= read -r tline || [ -n "$tline" ]; do
                        temp_lines_array+=("$tline")
                    done < "$temp_file"
                    
                    local last_non_empty_idx=-1
                    local j=0
                    while [ $j -lt ${#temp_lines_array[@]} ]; do
                        local tline="${temp_lines_array[$j]}"
                        if [ -n "$(echo "$tline" | tr -d '[:space:]')" ]; then
                            last_non_empty_idx=$j
                        fi
                        j=$((j + 1))
                    done
                    
                    # Rewrite temp file, collapsing consecutive blank lines and removing trailing blanks
                    > "$temp_file"
                    j=0
                    local prev_was_blank=false
                    while [ $j -le $last_non_empty_idx ]; do
                        local tline="${temp_lines_array[$j]}"
                        local is_blank=false
                        if [ -z "$(echo "$tline" | tr -d '[:space:]')" ]; then
                            is_blank=true
                        fi
                        
                        # Only write the line if:
                        # 1. It's not blank, OR
                        # 2. It's blank but the previous line wasn't blank (collapse consecutive blanks)
                        if [ "$is_blank" = false ] || [ "$prev_was_blank" = false ]; then
                            echo "$tline" >> "$temp_file"
                        fi
                        
                        prev_was_blank=$is_blank
                        j=$((j + 1))
                    done
                    
                    mv "$temp_file" "$ytdlp_config_file"
                    print_success "Removed ffmpeg-location from yt-dlp config"
                else
                    # File is empty, delete it
                    rm -f "$ytdlp_config_file" "$temp_file"
                    print_success "Removed empty yt-dlp configuration file"
                    
                    # Remove directory if it's now empty
                    local ytdlp_config_dir="${config_home}/yt-dlp"
                    if [ -d "$ytdlp_config_dir" ] && [ -z "$(ls -A "$ytdlp_config_dir" 2>/dev/null)" ]; then
                        rmdir "$ytdlp_config_dir" 2>/dev/null && print_success "Removed empty yt-dlp configuration directory"
                    fi
                fi
            else
                # grep found it but exact match didn't - likely modified, skip silently
                rm -f "$temp_file"
            fi
        else
            print_info "No ffmpeg-location configuration found"
        fi
    else
        print_info "yt-dlp configuration file not found"
    fi
    echo ""
}

# ----------------------------------------------------------------------------
# Main Uninstaller Function
# ----------------------------------------------------------------------------

# Main uninstaller function
uninstall_all() {
    print_info "Starting yt-dlp dependency uninstallation..."
    echo ""
    
    # Prompt for confirmation
    echo ""
    print_warning "This will uninstall all packages from the known package lists."
    print_warning "Configuration changes will be reverted."
    echo ""
    printf "Continue? (yes/no): "
    read -r confirmation
    
    if [ "$confirmation" != "yes" ] && [ "$confirmation" != "y" ]; then
        print_info "Uninstallation cancelled."
        exit 0
    fi
    
    echo ""
    
    # Phase 1: Detect package manager
    detect_package_manager
    echo ""
    
    # Phase 2: Remove yt-dlp package first
    print_info "Phase 1: Removing yt-dlp package..."
    echo ""
    uninstall_package "yt-dlp"
    echo ""
    
    # Phase 3: Remove pip packages (CRITICAL: Before removing python3)
    print_info "Phase 2: Removing pip packages..."
    echo ""
    uninstall_pip_packages
    echo ""
    
    # Phase 4: Remove system packages
    print_info "Phase 3: Removing system packages..."
    echo ""
    if [ "$PACKAGE_MANAGER" = "homebrew" ]; then
        uninstall_homebrew_packages
    elif [ "$PACKAGE_MANAGER" = "macports" ]; then
        uninstall_macports_packages
    fi
    echo ""
    
    # Phase 5: Clean up configurations
    print_info "Phase 4: Cleaning up configurations..."
    echo ""
    if [ "$PACKAGE_MANAGER" = "homebrew" ]; then
        cleanup_homebrew_config
    elif [ "$PACKAGE_MANAGER" = "macports" ]; then
        cleanup_macports_config
    fi
    
    cleanup_pip_config
    cleanup_path_config
    
    # Only cleanup yt-dlp config for MacPorts (Homebrew doesn't add yt-dlp config)
    if [ "$PACKAGE_MANAGER" = "macports" ]; then
        cleanup_ytdlp_config
    fi
    echo ""
    
    # Phase 6: Refresh command cache
    print_info "Refreshing command cache..."
    hash -r 2>/dev/null || true
    echo ""
    
    # Phase 7: Report summary
    echo "=========================================="
    echo ""
    print_success "Uninstallation completed!"
    echo ""
    print_info "Summary:"
    echo "  - Pip packages have been removed"
    echo "  - System packages have been removed (or kept if dependencies of other packages)"
    echo "  - Configuration changes have been reverted"
    echo ""
    print_info "Note: Some packages may still be installed if they are dependencies of other packages."
    print_info "This is expected and safe behavior."
    echo ""
    echo "=========================================="
}

# Main installation function
main() {
    print_info "Starting yt-dlp dependency installation..."
    echo ""
    
    # Phase 1: Detect package manager
    detect_package_manager
    echo ""
    
    # Phase 1.5: Configure package manager
    if [ "$PACKAGE_MANAGER" = "homebrew" ]; then
        configure_homebrew
        echo ""
    elif [ "$PACKAGE_MANAGER" = "macports" ]; then
        configure_macports
        echo ""
    fi
    
    # Phase 2: Install system packages
    print_info "Checking and installing system packages..."
    echo ""
    
    local packages
    packages=$(get_system_packages "$PACKAGE_MANAGER")
    
    for package in $packages; do
        if package_installed "$package"; then
            print_success "$package is already installed"
            echo ""
        else
            install_package "$package" || true
        fi
    done
    
    # Phase 2.5: Configure package manager-specific settings
    if [ "$PACKAGE_MANAGER" = "homebrew" ]; then
        configure_homebrew_pip
        echo ""
    elif [ "$PACKAGE_MANAGER" = "macports" ]; then
        configure_macports_python
        echo ""
        configure_macports_pip
        echo ""
    fi
    
    # Phase 3: Install pip packages
    print_info "Checking and installing pip packages..."
    python3 --version
    echo ""
    check_and_install_pip_packages
    
    # Phase 4: Install yt-dlp
    if [ "$PACKAGE_MANAGER" = "macports" ]; then
        # MacPorts: install with -ffmpeg variant deselection
        print_info "Installing yt-dlp via MacPorts (deselecting ffmpeg variant)..."
        if sudo port -q install yt-dlp -ffmpeg; then
            print_success "yt-dlp installed successfully"
            echo ""
            # Configure yt-dlp config file for MacPorts FFMPEG support
            local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
            local ytdlp_config_dir="${config_home}/yt-dlp"
            local ytdlp_config_file="${ytdlp_config_dir}/config"
            
            print_info "Configuring yt-dlp config file for MacPorts FFMPEG support..."
            
            # Create config directory
            mkdir -p "$ytdlp_config_dir"
            
            # Check if the configuration already exists in the config file
            if [ -f "$ytdlp_config_file" ] && grep -q "--ffmpeg-location /opt/local/bin/ffmpeg8" "$ytdlp_config_file" 2>/dev/null; then
                print_info "FFMPEG location is already configured in $ytdlp_config_file"
            else
                # Add the configuration block to the config file
                {
                    echo "# Enable MacPorts version of FFMPEG"
                    echo " --ffmpeg-location /opt/local/bin/ffmpeg8"
                } >> "$ytdlp_config_file"
                print_success "Added FFMPEG location to yt-dlp config: $ytdlp_config_file"
            fi
            echo ""
        else
            print_error "Failed to install yt-dlp"
            FAILED_PACKAGES="$FAILED_PACKAGES yt-dlp"
            echo ""
        fi
    else
        # Homebrew: standard installation
        install_package "yt-dlp" || true
    fi
    
    # Phase 5: Report failures and completion
    echo ""
    echo "=========================================="
    echo ""
    
    if [ -n "$FAILED_PACKAGES" ] || [ -n "$FAILED_PIP_PACKAGES" ]; then
        print_warning "Installation completed with some issues:"
        echo ""
        if [ -n "$FAILED_PACKAGES" ]; then
            print_error "Failed system packages:$FAILED_PACKAGES"
        fi
        if [ -n "$FAILED_PIP_PACKAGES" ]; then
            print_error "Failed pip packages:$FAILED_PIP_PACKAGES"
        fi
        echo ""
        print_info "You may need to install these manually or check for errors above."
    else
        print_success "Installation completed successfully!"
        echo ""
        print_info "All required dependencies for yt-dlp have been installed."
        print_info "Please restart your shell to start using yt-dlp on your system."
    fi
    
    echo ""
    echo "=========================================="
}

# Check for uninstall flag
if [ "$1" = "--uninstall" ] || [ "$1" = "-u" ]; then
    uninstall_all
else
    # Run main function (installation)
    main
fi

## THINGS TO STILL DO:
## Cosmetic issues when uninstalling 
## Check order functions for script and see if it can be cleaned up
## Make installer detect if yt-dlp is already installed at the very beginning
## and inform the user of the uninstaller and how to run it