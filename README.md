# Arch Linux ARM Post-Installation Script

A minimal, idempotent post-installation script for Arch Linux ARM systems. Designed for Apple Silicon Macs running Asahi Linux, but works on any Arch Linux ARM installation.

## Features

- **Idempotent**: Safe to run multiple times — skips already-configured operations
- **Minimal setup**: Configures essentials without bloat
- **Desktop ready**: Installs Xfce with LightDM display manager
- **Apple Silicon support**: Includes `asahi-desktop-meta` package

### What it configures

| Category | Settings |
|----------|----------|
| Timezone | Europe/Rome |
| Keymap | US |
| Hostname | owo |
| Locale | en_US.UTF-8 (also enables en_GB, it_IT) |
| User | `pun` with sudo access |
| Packages | base-devel, NetworkManager, Xfce4, LightDM, Firefox |
| Cleanup | Removes default `alarm` user |

## Requirements

- Arch Linux ARM installation (minimal or already configured)
- Root access (`sudo`)
- Active internet connection

## Usage

### Interactive mode

```bash
sudo ./arm.sh
```

The script will prompt for a password that's used for both root and the new user.

### Non-interactive mode

```bash
sudo ./arm.sh --password "your_password"
```

Useful for automated installations or headless setups.

## What happens

1. **System configuration**
   - Sets timezone, keymap, hostname, and locale
   - Configures `/etc/hosts` and `/etc/hostname`

2. **User management**
   - Sets root password
   - Creates user `pun` with sudo/wheel group access
   - Deletes the default `alarm` user (if present)

3. **Package installation**
   - Updates package database
   - Installs `base-devel` (gcc, make, git, etc.)
   - Installs and enables NetworkManager
   - Installs Xfce4 desktop environment
   - Installs LightDM display manager
   - Installs Firefox browser
   - Installs `asahi-desktop-meta` (Apple Silicon support)

4. **Service setup**
   - Enables NetworkManager
   - Enables LightDM (graphical login)

## Post-installation

After the script completes:

```bash
# Log out from root
exit

# Log in as user 'pun'
# Cache sudo credentials
sudo -v

# Update the system
sudo pacman -Syu
```

## Customization

Edit these variables at the top of the script:

```bash
readonly NEW_USERNAME="pun"      # Change to your preferred username
readonly TIMEZONE="Europe/Rome"  # Your timezone
readonly KEYMAP="us"             # Your keymap
readonly HOSTNAME="owo"          # Your hostname
```

## Safety

- All operations check current state before making changes
- Sudoers configuration is validated with `visudo -c`
- Script exits immediately on errors (`set -euo pipefail`)
- Password minimum length warning (6 characters)

## License

MIT License — see [LICENSE](LICENSE)

## Author

ppowo
