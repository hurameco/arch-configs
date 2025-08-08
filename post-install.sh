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

# Modify Boot Order
info "Installing necessary packages"

sudo pacman -S grub efibootmgr os-prober --noconfirm >/dev/null 2>&1

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
info "Installing GRUB to EFI directory"
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

# Generate GRUB configuration file
info "Generating GRUB configuration"
grub-mkconfig -o /boot/grub/grub.cfg

# Check if efibootmgr is installed and configure boot order
info "Configuring EFI boot order"

# Get the current boot order
current_boot_order=$(efibootmgr | grep '^BootOrder' | cut -d' ' -f2)

# Find the GRUB boot entry ID
grub_boot_id=$(efibootmgr | grep 'GRUB' | grep -o 'Boot[0-9A-F]*' | head -n1 | cut -c5-)

if [ -n "$grub_boot_id" ]; then
    # Set GRUB as the first in the boot order
    new_boot_order="$grub_boot_id,$(echo "$current_boot_order" | sed "s/$grub_boot_id//g" | sed 's/^,\|,,/,/g' | sed 's/,$//')"

    # Update the boot order
    info "Updating boot order to prioritize GRUB"
    efibootmgr -o "$new_boot_order"
    success "Boot order updated. GRUB is set as the primary boot entry."
else
    error "GRUB boot entry not found in efibootmgr."
fi
success "GRUB installation and configuration completed."

