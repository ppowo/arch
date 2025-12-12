#!/usr/bin/env bash
################################################################################
# Arch Linux ARM Minimal Post-Installation Script (Idempotent)
#
# This script performs essential post-installation setup for Arch Linux ARM
# minimal installations. Can be run multiple times safely - skips operations
# that are already configured.
#
# Usage:
#   Interactive: sudo ./arch-post-install.sh
#   With password: sudo ./arch-post-install.sh --password PASS
#
# Requirements:
# - Run as root user
# - Active internet connection
# - Fresh Arch Linux installation (or already configured system)
#
# Actions performed:
# 1. Configure timezone (Europe/Rome)
# 2. Configure console keymap (us)
# 3. Configure hostname (owo)
# 4. Configure system locale (en_US.UTF-8)
# 5. Set root password if not already set (same for both root and user "pun")
# 6. Create user "pun" with sudo access (wheel group)
# 7. Delete "alarm" user if it exists
# 8. Update user "pun" comment to "pun"
# 9. Install base-devel package group
# 10. Install and enable NetworkManager
# 11. Install all desktop packages: GNOME, asahi-meta-desktop, firefox
# 12. Enable GDM display manager
# 13. Configure sudo access for wheel group
#
# Idempotency: All operations check current state before making changes
################################################################################

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Configuration
readonly NEW_USERNAME="pun"
readonly MIN_PASSWORD_LENGTH=6

# Hardcoded system configuration
readonly TIMEZONE="Europe/Rome"
readonly KEYMAP="us"
readonly HOSTNAME="owo"

# Password (single password for both root and user)
PASSWORD=""

################################################################################
# Help and Argument Parsing
################################################################################

show_help() {
    cat << EOF
Arch Linux ARM Post-Installation Script

Usage: $0 [OPTIONS]

OPTIONS:
    -p, --password PASS       Set password for both root and user "pun"
    -h, --help                Show this help message

CONFIGURATION:
    Timezone: $TIMEZONE
    Keymap: $KEYMAP
    Hostname: $HOSTNAME

EXAMPLES:
    Interactive mode (prompts for password):
        sudo $0

    With password as argument:
        sudo $0 --password "mypassword123"

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--password)
                PASSWORD="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
}

################################################################################
# Validation Functions
################################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}ERROR: This script must be run as root user${NC}"
        exit 1
    fi
    echo -e "${GREEN}[✓] Running as root user${NC}"
}

validate_password() {
    local password="$1"

    if [[ ${#password} -lt $MIN_PASSWORD_LENGTH ]]; then
        echo -e "${YELLOW}WARNING: Password is quite short (${#password} chars, recommended minimum: $MIN_PASSWORD_LENGTH)${NC}"
        echo -e "${YELLOW}Continue anyway? (y/N)${NC}"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo -e "${RED}Aborted${NC}"
            exit 1
        fi
    fi

    return 0
}

user_exists() {
    local username="$1"
    id "$username" >/dev/null 2>&1
}

check_internet() {
    if ! ping -c 1 -W 2 archlinux.org >/dev/null 2>&1; then
        echo -e "${YELLOW}WARNING: Cannot reach archlinux.org. Package installation may fail.${NC}"
    else
        echo -e "${GREEN}[✓] Internet connectivity verified${NC}"
    fi
}

################################################################################
# Idempotency Helper Functions
################################################################################

# Check if a file exists and has expected content
file_has_content() {
    local file="$1"
    local expected_content="$2"
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    local current_content
    current_content=$(<"$file")
    if [[ "$current_content" == "$expected_content" ]]; then
        return 0
    fi
    return 1
}

# Check if a symlink points to the expected target
symlink_is_correct() {
    local symlink="$1"
    local expected_target="$2"
    if [[ ! -L "$symlink" ]]; then
        return 1
    fi
    local current_target
    current_target=$(readlink -f "$symlink")
    local expected_target_resolved
    expected_target_resolved=$(readlink -f "$expected_target" 2>/dev/null || echo "$expected_target")
    if [[ "$current_target" == "$expected_target_resolved" ]]; then
        return 0
    fi
    return 1
}

# Check if a systemd service is enabled
is_service_enabled() {
    local service="$1"
    systemctl is-enabled "$service" >/dev/null 2>&1
}

# Check if a systemd service is active/running
is_service_active() {
    local service="$1"
    systemctl is-active "$service" >/dev/null 2>&1
}

# Check if root password is already set
root_password_is_set() {
    # Check if root has a password (not locked)
    ! grep '^root:*$' /etc/shadow >/dev/null 2>&1
}

# Check if a locale is already generated
locale_is_generated() {
    local locale="$1"
    localedef --list-archive 2>/dev/null | grep -q "^${locale}$"
}

################################################################################
# Interactive Input Functions
################################################################################

prompt_password() {
    if [[ -n "$PASSWORD" ]]; then
        echo -e "${BLUE}[INFO] Using password from argument${NC}"
        return 0
    fi

    echo ""
    echo -e "${BOLD}=== Password Setup ===${NC}"
    echo "This password will be used for BOTH root and user '$NEW_USERNAME' accounts"
    echo ""

    while [[ -z "$PASSWORD" ]]; do
        read -s -p "Enter password: " PASSWORD
        echo ""

        if [[ -z "$PASSWORD" ]]; then
            echo -e "${RED}ERROR: Password cannot be empty${NC}"
            continue
        fi

        validate_password "$PASSWORD"

        # Confirm password
        read -s -p "Confirm password: " password_confirm
        echo ""

        if [[ "$PASSWORD" != "$password_confirm" ]]; then
            echo -e "${RED}ERROR: Passwords do not match${NC}"
            PASSWORD=""
        fi
    done

    echo -e "${GREEN}[✓] Password set${NC}"
}

################################################################################
# System Configuration Functions
################################################################################

configure_timezone() {
    echo -e "${BLUE}[INFO] Configuring timezone: $TIMEZONE${NC}"

    # Check if timezone symlink is already correct
    local expected_timezone="/usr/share/zoneinfo/$TIMEZONE"
    if [[ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]]; then
        echo -e "${YELLOW}WARNING: Timezone file not found, using UTC${NC}"
        expected_timezone="/usr/share/zoneinfo/UTC"
    fi

    # Check if already configured correctly
    if symlink_is_correct "/etc/localtime" "$expected_timezone"; then
        echo -e "${GREEN}[✓] Timezone already configured: $TIMEZONE${NC}"
        return 0
    fi

    # Set timezone symlink
    ln -sf "$expected_timezone" /etc/localtime || {
        echo -e "${RED}ERROR: Failed to set timezone${NC}"
        exit 1
    }

    # Generate /etc/adjtime
    hwclock --systohc || {
        echo -e "${YELLOW}WARNING: Failed to generate /etc/adjtime${NC}"
    }

    echo -e "${GREEN}[✓] Timezone configured: $TIMEZONE${NC}"
}

configure_keymap() {
    echo -e "${BLUE}[INFO] Configuring console keymap: $KEYMAP${NC}"

    # Check if already configured correctly
    local expected_content="KEYMAP=$KEYMAP"
    if file_has_content "/etc/vconsole.conf" "$expected_content"; then
        echo -e "${GREEN}[✓] Console keymap already configured: $KEYMAP${NC}"
    else
        # Set console keymap
        loadkeys "$KEYMAP" 2>/dev/null || {
            echo -e "${YELLOW}WARNING: Failed to load keymap '$KEYMAP', trying 'us'${NC}"
            loadkeys us 2>/dev/null || {
                echo -e "${YELLOW}WARNING: Could not load any keymap${NC}"
                return 0
            }
        }

        # Make it persistent
        echo "$expected_content" > /etc/vconsole.conf || {
            echo -e "${YELLOW}WARNING: Failed to write vconsole.conf${NC}"
        }

        echo -e "${GREEN}[✓] Console keymap configured: $KEYMAP${NC}"
    fi
}

configure_hostname() {
    echo -e "${BLUE}[INFO] Configuring hostname: $HOSTNAME${NC}"

    # Check if already configured correctly
    local expected_hostname="$HOSTNAME"
    local expected_hosts_content
    expected_hosts_content=$(cat <<EOF
127.0.0.1    localhost
::1          localhost
127.0.1.1    $HOSTNAME.localdomain    $HOSTNAME
EOF
)

    local hostname_needs_update=false
    local hosts_needs_update=false

    # Check hostname file
    if ! file_has_content "/etc/hostname" "$expected_hostname"; then
        hostname_needs_update=true
    fi

    # Check hosts file
    if ! file_has_content "/etc/hosts" "$expected_hosts_content"; then
        hosts_needs_update=true
    fi

    # Update files only if needed
    if ! $hostname_needs_update && ! $hosts_needs_update; then
        echo -e "${GREEN}[✓] Hostname already configured: $HOSTNAME${NC}"
        return 0
    fi

    # Set hostname
    if $hostname_needs_update; then
        echo "$HOSTNAME" > /etc/hostname || {
            echo -e "${RED}ERROR: Failed to set hostname${NC}"
            exit 1
        }
    fi

    # Update /etc/hosts
    if $hosts_needs_update; then
        {
            echo "127.0.0.1    localhost"
            echo "::1          localhost"
            echo "127.0.1.1    $HOSTNAME.localdomain    $HOSTNAME"
        } > /etc/hosts || {
            echo -e "${YELLOW}WARNING: Failed to update /etc/hosts${NC}"
        }
    fi

    echo -e "${GREEN}[✓] Hostname configured: $HOSTNAME${NC}"
}

configure_locale() {
    echo -e "${BLUE}[INFO] Configuring system locale...${NC}"

    # Common locales to enable
    local locales=(
        "en_US.UTF-8"
        "en_GB.UTF-8"
        "it_IT.UTF-8"
    )

    local need_locale_gen=false
    local need_config_update=false

    # Check if locales are already generated
    for locale in "${locales[@]}"; do
        if ! locale_is_generated "$locale"; then
            need_locale_gen=true
            break
        fi
    done

    # Check if locale.conf is already set correctly
    local expected_locale_conf="LANG=en_US.UTF-8"
    if ! file_has_content "/etc/locale.conf" "$expected_locale_conf"; then
        need_config_update=true
    fi

    # Skip if everything is already configured
    if ! $need_locale_gen && ! $need_config_update; then
        echo -e "${GREEN}[✓] System locale already configured${NC}"
        export LANG=en_US.UTF-8
        return 0
    fi

    # Enable locales in /etc/locale.gen
    for locale in "${locales[@]}"; do
        sed -i "s/^#${locale} UTF-8/${locale} UTF-8/" /etc/locale.gen 2>/dev/null || true
    done

    # Generate locales
    if $need_locale_gen; then
        locale-gen || {
            echo -e "${YELLOW}WARNING: Failed to generate some locales${NC}"
        }
    fi

    # Set system-wide locale
    if $need_config_update; then
        echo "$expected_locale_conf" > /etc/locale.conf || {
            echo -e "${YELLOW}WARNING: Failed to set locale.conf${NC}"
        }
    fi

    # Set LC_ALL
    export LANG=en_US.UTF-8

    echo -e "${GREEN}[✓] System locale configured${NC}"
}

################################################################################
# Core Functions
################################################################################

change_root_password() {
    echo -e "${BLUE}[INFO] Setting root password...${NC}"

    # Check if root password is already set
    if root_password_is_set; then
        echo -e "${GREEN}[✓] Root password already set${NC}"
        return 0
    fi

    # Set password using chpasswd
    echo "root:$PASSWORD" | chpasswd || {
        echo -e "${RED}ERROR: Failed to change root password${NC}"
        exit 1
    }

    echo -e "${GREEN}[✓] Root password changed successfully${NC}"
}

install_sudo() {
    if command -v sudo >/dev/null 2>&1; then
        echo -e "${GREEN}[✓] sudo is already installed${NC}"
        return 0
    fi

    echo -e "${BLUE}[INFO] Installing sudo package...${NC}"
    pacman -Sy --noconfirm --needed sudo || {
        echo -e "${RED}ERROR: Failed to install sudo${NC}"
        exit 1
    }

    echo -e "${GREEN}[✓] sudo installed successfully${NC}"
}

configure_sudo_wheel() {
    echo -e "${BLUE}[INFO] Configuring sudo access for wheel group...${NC}"

    # Create sudoers configuration file for wheel group
    local sudoers_file="/etc/sudoers.d/10-wheel-group"
    local sudoers_config="%wheel ALL=(ALL) ALL"

    # Write sudoers configuration
    echo "$sudoers_config" > "$sudoers_file" || {
        echo -e "${RED}ERROR: Failed to write sudoers file${NC}"
        exit 1
    }

    # Validate sudoers syntax using visudo
    if ! visudo -c -f "$sudoers_file" 2>/dev/null; then
        rm -f "$sudoers_file"
        echo -e "${RED}ERROR: Invalid sudoers configuration. File removed for safety.${NC}"
        exit 1
    fi

    # Set correct permissions (0440 = r--r-----)
    chmod 440 "$sudoers_file" || {
        echo -e "${RED}ERROR: Failed to set sudoers file permissions${NC}"
        exit 1
    }

    echo -e "${GREEN}[✓] sudo configured for wheel group${NC}"
}

create_sudo_user() {
    local username="$1"
    local password="$2"

    # Check if user already exists
    if user_exists "$username"; then
        echo -e "${YELLOW}WARNING: User '$username' already exists. Skipping user creation.${NC}"
        # Ensure user is in wheel group
        usermod -aG wheel "$username" 2>/dev/null || true
        return 0
    fi

    echo -e "${BLUE}[INFO] Creating user '$username' with wheel group...${NC}"

    # Validate username
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo -e "${RED}ERROR: Invalid username format${NC}"
        exit 1
    fi

    # Create user with home directory, bash shell, and wheel group
    useradd -m -G wheel -s /bin/bash -c "Arch Linux User" "$username" || {
        echo -e "${RED}ERROR: Failed to create user: $username${NC}"
        exit 1
    }

    # Set user password
    echo "$username:$password" | chpasswd || {
        echo -e "${RED}ERROR: Failed to set password for user: $username${NC}"
        exit 1
    }

    # Set ownership of home directory
    chown -R "$username:$username" "/home/$username" 2>/dev/null || {
        echo -e "${YELLOW}WARNING: Failed to set home directory ownership${NC}"
    }

    # Copy skel files
    if [[ -d /etc/skel ]]; then
        cp -r /etc/skel/. "/home/$username/" 2>/dev/null || {
            echo -e "${YELLOW}WARNING: Failed to copy skel files${NC}"
        }
        chown -R "$username:$username" "/home/$username" 2>/dev/null || true
    fi

    echo -e "${GREEN}[✓] User '$username' created successfully with sudo access${NC}"
}

cleanup_users() {
    echo -e "${BLUE}[INFO] Cleaning up user accounts...${NC}"

    # Delete alarm user if it exists
    if user_exists "alarm"; then
        echo -e "${BLUE}[INFO] Deleting 'alarm' user and home directory...${NC}"
        userdel -r alarm 2>/dev/null || {
            echo -e "${YELLOW}WARNING: Failed to delete 'alarm' user${NC}"
        }
        echo -e "${GREEN}[✓] Deleted 'alarm' user${NC}"
    else
        echo -e "${GREEN}[✓] 'alarm' user does not exist${NC}"
    fi

    # Fix pun user comment if it exists
    if user_exists "$NEW_USERNAME"; then
        local current_comment
        current_comment=$(getent passwd "$NEW_USERNAME" | cut -d: -f5)
        if [[ "$current_comment" != "$NEW_USERNAME" ]]; then
            echo -e "${BLUE}[INFO] Updating '$NEW_USERNAME' user comment...${NC}"
            usermod -c "$NEW_USERNAME" "$NEW_USERNAME" || {
                echo -e "${YELLOW}WARNING: Failed to update user comment${NC}"
            }
            echo -e "${GREEN}[✓] Updated '$NEW_USERNAME' user comment${NC}"
        else
            echo -e "${GREEN}[✓] '$NEW_USERNAME' user comment already correct${NC}"
        fi
    fi

    echo -e "${GREEN}[✓] User cleanup complete${NC}"
}

install_base_devel() {
    echo -e "${BLUE}[INFO] Installing base-devel package group...${NC}"

    # Update package database first
    echo -e "${BLUE}[INFO] Updating package database...${NC}"
    pacman -Sy || {
        echo -e "${RED}ERROR: Failed to update package database${NC}"
        exit 1
    }

    # Install base-devel
    echo -e "${BLUE}[INFO] Installing base-devel (this may take a while)...${NC}"
    if ! pacman -S --noconfirm --needed base-devel; then
        echo -e "${RED}ERROR: Failed to install base-devel package group${NC}"
        exit 1
    fi

    echo -e "${GREEN}[✓] base-devel installed successfully${NC}"
    echo -e "${BLUE}[INFO] Available tools include: gcc, make, git, binutils, etc.${NC}"
}

install_networkmanager() {
    echo -e "${BLUE}[INFO] Setting up NetworkManager...${NC}"

    # Check if NetworkManager is already installed
    if ! pacman -Qs networkmanager >/dev/null 2>&1; then
        echo -e "${BLUE}[INFO] Installing networkmanager package...${NC}"
        pacman -S --noconfirm --needed networkmanager || {
            echo -e "${RED}ERROR: Failed to install networkmanager${NC}"
            exit 1
        }
    else
        echo -e "${GREEN}[✓] NetworkManager already installed${NC}"
    fi

    # Check if service is already enabled and active
    local service_enabled=false
    local service_active=false

    if is_service_enabled "NetworkManager.service"; then
        service_enabled=true
    fi

    if is_service_active "NetworkManager.service"; then
        service_active=true
    fi

    # Enable service only if not already enabled
    if ! $service_enabled; then
        echo -e "${BLUE}[INFO] Enabling NetworkManager service...${NC}"
        systemctl enable NetworkManager.service || {
            echo -e "${RED}ERROR: Failed to enable NetworkManager${NC}"
            exit 1
        }
    else
        echo -e "${GREEN}[✓] NetworkManager already enabled${NC}"
    fi

    # Start service only if not already active
    if ! $service_active; then
        echo -e "${BLUE}[INFO] Starting NetworkManager service...${NC}"
        systemctl start NetworkManager.service || {
            echo -e "${RED}ERROR: Failed to start NetworkManager${NC}"
            exit 1
        }
    else
        echo -e "${GREEN}[✓] NetworkManager already active${NC}"
    fi

    echo -e "${GREEN}[✓] NetworkManager setup complete${NC}"
    echo -e "${YELLOW}[NOTE] Only one network manager should run at a time${NC}"
    echo -e "${YELLOW}[NOTE] If you have other network services running, disable them${NC}"
    echo -e "${BLUE}[INFO] Use 'nmcli' to manage network connections${NC}"
}

enable_gdm() {
    echo -e "${BLUE}[INFO] Configuring GDM display manager...${NC}"

    # Check if GDM is already enabled
    if is_service_enabled "gdm.service"; then
        echo -e "${GREEN}[✓] GDM already enabled${NC}"
    else
        # Enable GDM service
        echo -e "${BLUE}[INFO] Enabling GDM service...${NC}"
        systemctl enable gdm.service || {
            echo -e "${RED}ERROR: Failed to enable GDM${NC}"
            exit 1
        }
        echo -e "${GREEN}[✓] GDM enabled${NC}"
    fi

    echo -e "${YELLOW}[NOTE] GDM will start automatically on boot${NC}"
    echo -e "${YELLOW}[NOTE] You can switch between GNOME and console with Ctrl+Alt+F1/F2${NC}"
}

install_all_packages() {
    echo -e "${BLUE}[INFO] Installing all desktop packages and tools...${NC}"
    echo -e "${YELLOW}[NOTE] This includes: gnome, asahi-meta-desktop, firefox${NC}"
    echo -e "${YELLOW}[NOTE] This may take a while...${NC}"

    # Check if all packages are already installed
    local all_installed=true

    # Check gnome group
    if ! pacman -Qg gnome >/dev/null 2>&1; then
        all_installed=false
    fi

    # Check individual packages
    for pkg in asahi-meta-desktop firefox; do
        if ! pacman -Qs "$pkg" >/dev/null 2>&1; then
            all_installed=false
            break
        fi
    done

    if $all_installed; then
        echo -e "${GREEN}[✓] All packages already installed (gnome, asahi-meta-desktop, firefox)${NC}"
        return 0
    fi

    # Update package database first
    echo -e "${BLUE}[INFO] Updating package database...${NC}"
    pacman -Sy || {
        echo -e "${RED}ERROR: Failed to update package database${NC}"
        exit 1
    }

    # Install all packages in one command
    echo -e "${BLUE}[INFO] Installing all packages in one operation...${NC}"
    if ! pacman -S --noconfirm --needed gnome asahi-meta-desktop firefox; then
        echo -e "${RED}ERROR: Failed to install one or more packages${NC}"
        exit 1
    fi

    echo -e "${GREEN}[✓] All packages installed successfully${NC}"
    echo -e "${BLUE}[INFO] Installed: GNOME desktop, asahi-meta-desktop, firefox, prompt${NC}"
}

display_system_info() {
    echo ""
    echo "========================================="
    echo -e "${GREEN}  Post-Installation Complete!${NC}"
    echo "========================================="
    echo ""
    echo "Configuration Summary:"
    echo "  ✓ Timezone: $TIMEZONE"
    echo "  ✓ Keymap: $KEYMAP"
    echo "  ✓ Hostname: $HOSTNAME"
    echo "  ✓ Locale: en_US.UTF-8"
    echo "  ✓ Root password: configured (if needed)"
    echo "  ✓ User created: $NEW_USERNAME (with sudo access)"
    echo "  ✓ User cleanup: alarm user deleted (if existed)"
    echo "  ✓ User comment: $NEW_USERNAME"
    echo "  ✓ base-devel: installed"
    echo "  ✓ NetworkManager: installed and enabled"
    echo "  ✓ All desktop packages: installed (GNOME, asahi-meta-desktop, firefox)"
    echo "  ✓ GDM: display manager enabled"
    echo "  ✓ sudo: configured for wheel group"
    echo ""
    echo "Next Steps:"
    echo "  1. Log out from root account"
    echo "  2. Log in as user: $NEW_USERNAME"
    echo "  3. Run 'sudo -v' to cache credentials"
    echo "  4. Update system: 'sudo pacman -Syu'"
    echo ""
    echo "========================================="
    echo ""
}

################################################################################
# Main Execution
################################################################################

main() {
    echo ""
    echo "========================================="
    echo -e "  ${BOLD}Arch Linux ARM Post-Installation${NC}"
    echo "========================================="
    echo ""

    # Parse command-line arguments
    parse_arguments "$@"

    # Pre-flight checks
    check_root
    check_internet

    # Prompt for password (interactive if not provided via argument)
    prompt_password

    # System configuration
    configure_timezone
    configure_keymap
    configure_hostname
    configure_locale

    # Main installation steps
    change_root_password
    install_sudo
    configure_sudo_wheel
    create_sudo_user "$NEW_USERNAME" "$PASSWORD"
    cleanup_users
    install_base_devel
    install_networkmanager
    install_all_packages
    enable_gdm

    # Display completion message
    display_system_info

    echo -e "${GREEN}Post-installation script completed successfully!${NC}"
}

################################################################################
# Script Entry Point
################################################################################

# Run main function
main "$@"