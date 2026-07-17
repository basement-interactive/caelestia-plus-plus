#!/usr/bin/env bash
# Caelestia++ one-command installer for Arch.
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/basement-interactive/caelestia-plus-plus/main/install.sh)
set -euo pipefail

REPO=basement-interactive/caelestia-plus-plus
SHELL_DIR="$HOME/.config/quickshell/caelestia"

[[ $EUID -eq 0 ]] && { echo "run as your normal user, not root"; exit 1; }
command -v pacman >/dev/null || { echo "this installer is Arch-only"; exit 1; }

# AUR helper — needed for quickshell-git and the font dependencies
if command -v paru >/dev/null; then
    aur=paru
elif command -v yay >/dev/null; then
    aur=yay
else
    echo ":: no AUR helper found, installing paru"
    sudo pacman -S --needed --noconfirm base-devel git
    aurtmp=$(mktemp -d)
    git clone https://aur.archlinux.org/paru-bin.git "$aurtmp/paru-bin"
    (cd "$aurtmp/paru-bin" && makepkg -si --noconfirm)
    aur=paru
fi

echo ":: downloading Caelestia++ packages from the latest release"
tmp=$(mktemp -d)
curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" |
    grep -o 'https://[^"]*\.pkg\.tar\.zst' | sort -u > "$tmp/urls"
[[ -s $tmp/urls ]] || { echo "no package assets on the latest release"; exit 1; }
while read -r url; do
    curl -fL -o "$tmp/$(basename "$url")" "$url"
done < "$tmp/urls"

echo ":: installing dependencies"
deps=$(for pkg in "$tmp"/*.pkg.tar.zst; do
    bsdtar -xOf "$pkg" .PKGINFO | awk -F' = ' '$1 == "depend" {print $2}'
done | grep -v '^caelestia' | sort -u)
# shellcheck disable=SC2086 — deps is a word list by construction
$aur -S --needed --asdeps --noconfirm $deps

echo ":: installing Caelestia++ packages"
sudo pacman -U --noconfirm "$tmp"/*.pkg.tar.zst
if ! grep -q '^IgnorePkg.*caelestia++' /etc/pacman.conf; then
    sudo sed -i '/^\[options\]/a IgnorePkg = caelestia++-shell caelestia++-cli' /etc/pacman.conf
fi

echo ":: fetching the shell"
if [[ -e $SHELL_DIR ]]; then
    echo "   $SHELL_DIR already exists, leaving it untouched"
else
    git clone "https://github.com/$REPO.git" "$SHELL_DIR"
fi

echo
echo "Caelestia++ installed. Start it with:  caelestia shell -d"
echo "Hyprland autostart:  exec-once = caelestia shell -d"
echo "Updates arrive in the shell's Settings > Updates tab."
