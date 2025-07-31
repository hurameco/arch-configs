#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Message functions
success() { echo -e "${GREEN}SUCCESS${NC}\t:: $*"; }
error() { echo -e "${RED}ERROR${NC}\t:: $*"; exit 1; }
info() { echo -e "${BLUE}INFO${NC}\t:: $*"; }
warning() { echo -e "${YELLOW}WARNING${NC}\t:: $*"; }

# Configuration
PACMAN_PACKAGES=(
    aspnet-runtime
    base-devel
    docker
    docker-compose
    dotnet-sdk
    ghostty
    git
    hyprlock
    pavucontrol
    power-profiles-daemon
    telegram-desktop
    ttf-font-awesome
    ttf-jetbrains-mono
    ttf-jetbrains-mono-nerd
    waybar
    waybar-hyprland
)

YAY_PACKAGES=(
    brave-bin
    gnome-keyring
    libsecret
    nerd-fonts-jetbrains-mono
    openvpn3
    outlook-for-linux-bin
    spotify-launcher
    stremio
    teams-for-linux
    thunderbird
    visual-studio-code-bin
    #zapzap
    whatsie
)

GITHUB_REPO="https://raw.githubusercontent.com/hurameco/Arch-Linux/main"

# Check root first - this will exit if not root
[[ $EUID -eq 0 ]] || error "This script must be run as root"

# Parse arguments
VERBOSE=0
NO_CONFIRM=0
DRY_RUN=0
SKIP_CONFIGS=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose) VERBOSE=1 ;;
        --no-confirm) NO_CONFIRM=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --network-name) NETWORK_NAME="$2"; shift ;;
        --network-password) NETWORK_PASSWORD="$2"; shift ;;
        --skip-configs) SKIP_CONFIGS=1 ;;
        --help) cat <<EOF
Usage: $0 [OPTIONS]
Options:
    --dry-run           Preview changes without modifying files
    --help              Show this help message
    --network-name      Specify Wi-Fi network name
    --network-password  Specify Wi-Fi network password
    --no-confirm        Skip confirmation prompts
    --skip-configs
    --verbose           Enable verbose output
EOF
        exit 0 ;;
        *) error "Unknown option: $1" ;;
    esac
    shift
done

# Network connection
if [[ -n "$NETWORK_NAME" && -n "$NETWORK_PASSWORD" ]]; then
    info "Connecting to Wi-Fi: $NETWORK_NAME"
    if ! nmcli device wifi connect "$NETWORK_NAME" password "$NETWORK_PASSWORD"; then
        error "Failed to connect to Wi-Fi"
    fi
fi

# Check internet
if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    error "No internet connection"
fi

# System update
info "Updating system"
if ! pacman -Syu $( ((NO_CONFIRM)) && echo "--noconfirm") \
    $( ((!VERBOSE)) && echo "--quiet"); then
    error "System update failed"
fi
success "System updated"

# Package installation function
install_packages() {
    local manager="$1"
    shift
    local packages=("$@")
    
    for pkg in "${packages[@]}"; do
        if $manager -Qi "$pkg" >/dev/null 2>&1; then
            success "$pkg already installed"
            continue
        fi
        
        info "Installing $pkg"
        if ! $manager -S $( ((NO_CONFIRM)) && echo "--noconfirm") \
            $( ((!VERBOSE)) && echo "--quiet") "$pkg"; then
            warning "Failed to install $pkg"
        fi
    done
}

# Install pacman packages
info "Installing pacman packages"
install_packages pacman "${PACMAN_PACKAGES[@]}"

# Install yay if needed
if ! command -v yay >/dev/null; then
    info "Installing yay"
    tmp="./home/coelho/yay"
    mkdir "$tmp"
    chmod 777 "$tmp"
    if ! git clone -q https://aur.archlinux.org/yay-bin.git "$tmp"; then
        rm -rf "$tmp"
        error "Failed to clone yay repository"
    fi
    
    if ! (cd "$tmp"; sudo -u "$SUDO_USER" makepkg -si $( ((NO_CONFIRM)) && echo "--noconfirm")); then
        rm -rf "$tmp"
        error "Failed to install yay"
    fi
    rm -rfrm -rf "$tmp" "$tmp"
fi

# Install AUR packages
info "Installing AUR packages"
install_packages "sudo -u $SUDO_USER yay" "${YAY_PACKAGES[@]}"

info "Installing oh-my-bash"
cd ~
sudo -u "$SUDO_USER" bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"
success "Installed oh-my-bash"

# Docker service
info "Starting Docker"
if ! systemctl enable --now docker.service; then
    warning "Failed to start Docker"
fi

# Cleanup
info "Cleaning up"
if ! pacman -Qdtq | xargs -r pacman -Rns --noconfirm $( ((!VERBOSE)) && echo "--quiet"); then
    warning "Failed to clean up pacman packages"
fi

if ! sudo -u "$SUDO_USER" yay -Qdtq | xargs -r yay -Rns --noconfirm $( ((!VERBOSE)) && echo "--quiet"); then
    warning "Failed to clean up AUR packages"
fi

# Enhanced config file handling
download_config() {
    local src="$1"
    local dest="$2"
    local backup="${dest}.bak"
    local dest_dir=$(dirname "$dest")
    local temp_file="${dest}.tmp"
     local download_url="${GITHUB_REPO}/${src}"

    if [[ "$dest_dir" != "." ]]; then
        if [[ -d "$dest_dir" ]]; then
            # Directory exists - verify permissions
            if [[ ! -w "$dest_dir" ]]; then
                warning "No write permissions for directory '$dest_dir'"
                return 1
            fi
            # Ensure correct permissions (755) and ownership
            if ! chmod 755 "$dest_dir" || ! chown "${SUDO_USER:-$(whoami)}:${SUDO_USER:-$(whoami)}" "$dest_dir"; then
                warning "Could not fix permissions for '$dest_dir'"
                return 1
            fi
        else
            # Directory doesn't exist - create with secure defaults
            if ! mkdir -p "$dest_dir"; then
                warning "Failed to create directory '$dest_dir'"
                return 1
            fi
            # Set proper permissions (755) and ownership
            chmod 755 "$dest_dir"
            chown "${SUDO_USER:-$(whoami)}:${SUDO_USER:-$(whoami)}" "$dest_dir"
        fi
    fi

    # Handle existing config file
    if [[ -f "$dest" ]]; then
        # Interactive confirmation
        if [[ "$NO_CONFIRM" -eq 0 ]]; then
            read -p "Overwrite $dest? [y/N] " answer
            [[ "$answer" != "y" ]] && return 2
        fi
        info "Backing up existing $dest"
        # Create backup preserving permissions
        cp -p "$dest" "$backup" || {
            warning "Failed to backup $dest"
            return 1
        }
    fi

    # Download with atomic operation
    if ! curl -sfL "$download_url" -o "$temp_file"; then
        warning "Failed to download $download_url"
        [[ -f "$backup" ]] && mv "$backup" "$dest"
        return 1
    fi

    # Verify and move into place
    if mv "$temp_file" "$dest"; then
        chmod 644 "$dest"
        chown "${SUDO_USER:-$(whoami)}:${SUDO_USER:-$(whoami)}" "$dest"
        return 0
    else
        warning "Failed to install $dest"
        [[ -f "$backup" ]] && mv "$backup" "$dest"
        return 1
    fi

    # Set secure permissions (user RW, group/others R)
    chmod 644 "$dest"
    chown "${SUDO_USER:-$(whoami)}:${SUDO_USER:-$(whoami)}" "$dest"

    return 0
}

# Config files setup
info "Setting up config files"
CONFIGS=(
    "a.bashrc:./.bashrc"
    "ghostty/config:./.config/ghostty/config"
    "hypr/hyprland.conf:./.config/hypr/hyprland.conf"
    "waybar/config.jsonc:./.config/waybar/config.jsonc"
    "waybar/style.css:./.config/waybar/style.css"
)


if [[ "$SKIP_CONFIGS" -eq 0 ]]; then
    for config in "${CONFIGS[@]}"; do
        # Localize IFS change and handle errors
        IFS=':' read -r src dest _ <<< "$config" || {
            warning "Malformed config entry: $config"
            continue
        }

        # Expand ~ in paths if present
        dest="${dest/#\~/$HOME}"

        # Call function directly and check return code
        download_config "$src" "$dest"
        case $? in
            0) success "Configured $dest" ;;
            1) warning "Failed to configure $dest" ;;
            2) info "Skipped $dest (user chose not to overwrite)" ;;
            *) warning "Unknown return code for $dest" ;;
        esac
    done
fi

success "Setup completed"
exit 0
