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
    whatsie
)

DEFAULT_CONFIGS_FOLDER="~/.arch-configs"

# Parse arguments
VERBOSE=0
NO_CONFIRM=1
DRY_RUN=0
SKIP_CONFIGS=0
NETWORK_NAME=''
NETWORK_PASSWORD=''
SKIP_EFIBOOTMGR=1

while [[ $# -gt 0 ]]; do
    case $1 in
        --configs-folder) DEFAULT_CONFIGS_FOLDER="$2"; shift ;;
        --confirm) NO_CONFIRM=0 ;;
        --dry-run) DRY_RUN=1 ;;
        --efibootmgr) SKIP_EFIBOOTMGR=0 ;;
        --network-name) NETWORK_NAME="$2"; shift ;;
        --network-password) NETWORK_PASSWORD="$2"; shift ;;
        --skip-configs) SKIP_CONFIGS=1 ;;
        --verbose) VERBOSE=1 ;;
        --help) cat <<EOF
Usage: $0 [OPTIONS]
Options:
    --configs-folder    Specify the folder for configuration files
    --confirm           Requires confirmation prompts
    --dry-run           Preview changes without modifying files
    --efibootmgr        Configure efibootmgr configuration
    --help              Show this help message
    --network-name      Specify Wi-Fi network name
    --network-password  Specify Wi-Fi network password
    --skip-configs      Skip the Configuration files
    --verbose           Enable verbose output
EOF
        exit 0 ;;
        *) error "Unknown option: $1" ;;
    esac
    shift
done

[[ $EUID -eq 0 ]] || error "This script must be run as root"

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
if ! pacman -Syu $( ((NO_CONFIRM)) && echo "--noconfirm") \
    $( ((!VERBOSE)) && echo "--quiet"); then
    error "System update failed"
fi
success "System updated"

# Modify Boot Order
if [ "$SKIP_EFIBOOTMGR" = "false" ]; then
    error "Easy!!"
    info "Installing and configuring GRUB..."

    sudo pacman -S $(((NO_CONFIRM)) && echo "--no-confirm";) $( ((VERBOSE)) && echo "--quiet" ) grub efibootmgr os-prober;

    # Modify /mnt/etc/default/grub to uncomment the last line
    if [ -f /mnt/etc/default/grub ]; then
        # Get the last line
        last_line=$(tail -n 1 /etc/default/grub)
        # Check if the last line is commented
        if [[ $last_line == \#* ]]; then
            sed -i "$ s/^#//" /etc/default/grub
        fi
    else
        error "/etc/default/grub not found."
    fi

    # Install GRUB to the EFI directory
    Info "Installing GRUB to EFI directory..."
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

    # Generate GRUB configuration file
    info "Generating GRUB configuration..."
    grub-mkconfig -o /boot/grub/grub.cfg

    # Check if efibootmgr is installed and configure boot order
    if command -v efibootmgr >/dev/null; then
        info "Configuring EFI boot order..."

        # Get the current boot order
        current_boot_order=$(efibootmgr | grep '^BootOrder' | cut -d' ' -f2)

        # Find the GRUB boot entry ID
        grub_boot_id=$(efibootmgr | grep 'GRUB' | grep -o 'Boot[0-9A-F]*' | head -n1 | cut -c5-)

        if [ -n "$grub_boot_id" ]; then
            # Set GRUB as the first in the boot order
            new_boot_order="$grub_boot_id"
            if [ -n "$current_boot_order" ]; then
                # Append other entries after GRUB, avoiding duplicates
                new_boot_order="$grub_boot_id,$(echo "$current_boot_order" | sed "s/$grub_boot_id//g" | sed 's/^,\|,,/,/g' | sed 's/,$//')"
            fi

            # Update the boot order
            info "Updating boot order to prioritize GRUB..."
            efibootmgr -o "$new_boot_order"
            success "Boot order updated. GRUB is set as the primary boot entry."
        else
            error "GRUB boot entry not found in efibootmgr."
        fi
    else
        error "Command efibootmgr not found. Skipping boot order configuration."
    fi
    success "GRUB installation and configuration completed."
fi

# Function to install packages
install_packages() {
    info "Installing $1 packages..."
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
install_packages pacman "${PACMAN_PACKAGES[@]}"

# Install yay if needed
if ! command -v yay >/dev/null; then
    info "Installing yay"
    tmp="yay"
    sudo -u "$SUDO_USER" mkdir "$tmp"
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
if ! (systemctl enable --now docker.service; success "Docker started";);then
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

# Download Repo with configs and create links  
#sudo -u $SUDO_USER git clone https://github.com/hurameco/arch-configs.git "${DEFAULT_CONFIGS_FOLDER}" $( ((!VERBOSE)) && echo "--quiet")

#cd "${DEFAULT_CONFIGS_FOLDER}"

# Config files setup
info "Setting up config files"
CONFIGS=(
    ".bashrc:~/.bashrc"
    "dotfiles/ghostty:~/.config/ghostty"
    "dotfiles/hypr:~/.config/hypr"
    "dotfiles/waybar:~/.config/waybar"
)

if [ "$SKIP_CONFIGS" -eq 0 ]; then
    # Get the non-root user's home directory
    user_home=$(eval echo "~$SUDO_USER")

    for config in "${CONFIGS[@]}"; do
        # Split the config string into local and output paths
        IFS=':' read -r local_path output_path <<< "$config"

        # Prefix local_path with DEFAULT_CONFIGS_FOLDER
        local_path="$DEFAULT_CONFIGS_FOLDER/$local_path"

        # Expand ~ in output_path to the user's home directory
        output_path=${output_path/\~/$user_home}
        local_path=${local_path/\~/$user_home}
        
        # info "DEBUG: $local_path -> $output_path"

        if [ -e "$local_path" ]; then
            if [ -e "$output_path" ]; then
              unlink "$output_path"
              rm -rf "$output_path"
            fi
            info "Setting up $local_path -> $output_path"
            mkdir -p "$(dirname "$output_path")"
            sudo -u "$SUDO_USER" ln -s "$local_path" "$output_path"  
            success "Created symlink: $local_path -> $output_path"
        fi

        # if [ -d "$local_path" ]; then
        #     if [ -e "$output_path" ]; then
        #       rm -rf "$output_path"
        #     fi
        #     info "Setting up $local_path -> $output_path"
        #     mkdir -p "$(dirname "$output_path")"
        #     ln -s "$(realpath "$local_path")" "$output_path"  
        #     success "Created symlink: $local_path -> $output_path"
        # fi
    done
    success "Successfully set up config files using symlinks"
fi

# Create a beautiful finished message
cat <<EOF
----------------------------------------
$([[ "$DRY_RUN" -eq 1 ]] && echo "Dry run completed. No changes applied." || {
    echo "System updated"
    echo "Packages installed"
    echo "Docker enabled"
    [[ -n "$NETWORK_NAME" ]] && echo "Connected to Wi-Fi: $NETWORK_NAME."
    [[ "$SKIP_EFIBOOTMGR" -eq 0 ]] && echo "GRUB boot order configured."
    [[ "$SKIP_CONFIGS" -eq 0 ]] && echo "Config files linked in $DEFAULT_CONFIGS_FOLDER."
})

Setup completed in $(elapsed_time).

Rebooting...
----------------------------------------
EOF

# Wait for any key to exit
read -n 1 -s -r -p "Press any key to reboot..."

# Exit hyprland
shutdown -r now
