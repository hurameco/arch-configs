#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
ORANGE='\033[38;5;208m'
NC='\033[0m' # No Color

start_time=$SECONDS

# Message functions with time elapsed
success() { echo -e "${ORANGE}$(elapsed_time)\t${GREEN}SUCCESS${NC}\t:: $*"; }
error() { echo -e "${ORANGE}$(elapsed_time)\t${RED}ERROR${NC}\t:: $*"; exit 1; }
info() { echo -e "${ORANGE}$(elapsed_time)\t${BLUE}INFO${NC}\t:: $*"; }
warning() { echo -e "${ORANGE}$(elapsed_time)\t${YELLOW}WARNING${NC}\t:: $*"; }

# Function to calculate elapsed time retrives 00:00:00
elapsed_time() {
  elapsed_time=$((SECONDS - start_time))
  printf "%02d:%02d:%02d" $((elapsed_time/3600)) $((elapsed_time%3600/60)) $((elapsed_time%60))
}

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
    openvpn
    pavucontrol
    power-profiles-daemon
    telegram-desktop
    ttf-font-awesome
    ttf-jetbrains-mono
    ttf-jetbrains-mono-nerd
    waybar
)

YAY_PACKAGES=(
    brave-bin
    gnome-keyring
    libsecret
    nerd-fonts-jetbrains-mono
    outlook-for-linux-bin
    spotify-launcher
    stremio
    teams-for-linux
    thunderbird
    visual-studio-code-bin
    zapzap
    # openvpn3
)

DEFAULT_CONFIGS_FOLDER="~/.arch-configs"
DEFAULT_YAY_FOLDER="~/.yay"
NETWORK_NAME=''
NETWORK_PASSWORD=''

while [[ $# -gt 0 ]]; do
    case $1 in
        --network-name) NETWORK_NAME="$2"; shift ;;
        --network-password) NETWORK_PASSWORD="$2"; shift ;;
        --help) cat <<EOF
Usage: $0 [OPTIONS]
Options:
    --help              Show this help message
    --network-name      Specify Wi-Fi network name
    --network-password  Specify Wi-Fi network password
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
    error "The installation needs access to internet. Provide network connection details using --network-name and --network-password flags. See --help for more details."
fi

# System update
info "Updating system..."
if ! sudo pacman -Syu --noconfirm; then
    error "System update failed"
fi
success "System updated"

# Install packages
info "Installing packages..."
for pkg in "${PACMAN_PACKAGES[@]}"; do
    if ! (sudo pacman -Qi "$pkg") >/dev/null; then
        info "Installing $pkg"
        if ! sudo pacman -S "$pkg" --noconfirm >/dev/null; then
            warning "Failed to install $pkg"
        fi
    else
        success "$pkg already installed"
    fi
done

# Install yay if needed
if ! command -v yay >/dev/null; then
    info "Installing yay"
    mkdir -p "$DEFAULT_YAY_FOLDER"
    chmod 777 "$DEFAULT_YAY_FOLDER"
    if ! git clone -q https://aur.archlinux.org/yay-bin.git "$DEFAULT_YAY_FOLDER" >/dev/null; then
        rm -rf "$DEFAULT_YAY_FOLDER"
        error "Failed to clone yay repository"
    fi
    
    if ! (cd "$DEFAULT_YAY_FOLDER"; makepkg -si --noconfirm); then
        rm -rf "$DEFAULT_YAY_FOLDER"
        error "Failed to install yay"
    fi
    rm -rfrm -rf "$DEFAULT_YAY_FOLDER" "$DEFAULT_YAY_FOLDER"
fi

# Install AUR packages
for pkg in "${YAY_PACKAGES[@]}"; do
    if ! yay -Qi "$pkg" >/dev/null; then
        info "Installing $pkg"
        if ! yay -S "$pkg" --noconfirm >/dev/null; then
            warning "Failed to install $pkg"
        fi
    else
        success "$pkg already installed"
    fi
done

info "Installing oh-my-bash"
cd ~
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"
success "Installed oh-my-bash"

info "Installing Dotnet Entity Framework"
dotnet tool install --global dotnet-ef >/dev/null

# Docker service
if ! getent group "docker" >/dev/null; then
    info "Adding user to docker group"
    sudo groupadd docker
    sudo usermod -aG docker "$USER"
    newgrp docker
    info "Starting Docker"
    if ! (systemctl enable --now docker.service; success "Docker started";);then
        warning "Failed to start Docker"
    fi
fi

# Cleanup
info "Cleaning up"
if ! sudo pacman -Qdtq | xargs -r sudo pacman -Rns --noconfirm >/dev/null; then
    warning "Failed to clean up pacman packages"
fi

if ! yay -Qdtq | xargs -r yay -Rns --noconfirm; then
    warning "Failed to clean up AUR packages"
fi

# Download Repo with configs and create links  
git clone https://github.com/hurameco/arch-configs.git "${DEFAULT_CONFIGS_FOLDER}" >/dev/null

cd "${DEFAULT_CONFIGS_FOLDER}"

# Config files setup
info "Setting up config files"
CONFIGS=(
    ".bashrc:~/.bashrc"
    "dotfiles/ghostty:~/.config/ghostty"
    "dotfiles/hypr:~/.config/hypr"
    "dotfiles/waybar:~/.config/waybar"
)

for config in "${CONFIGS[@]}"; do
    # Split the config string into local and output paths
    IFS=':' read -r local_path output_path <<< "$config"

    if [ -e "$local_path" ]; then
        if [ -e "$output_path" ]; then
            unlink "$output_path"
            rm -rf "$output_path"
        fi
        info "Setting up $local_path -> $output_path"
        mkdir -p "$(dirname "$output_path")"
        ln -s "$local_path" "$output_path"  
        success "Created symlink: $local_path -> $output_path"
    fi
done
success "Successfully set up config files using symlinks"

# Create a beautiful finished message
cat <<EOF
----------------------------------------
Setup completed in $(elapsed_time).

Rebooting...
----------------------------------------
EOF

source ./bashrc

# Wait for any key to exit
read -n 1 -s -r -p "Press any key to reboot..."
reboot

