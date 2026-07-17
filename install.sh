#!/usr/bin/env bash
# Caelestia++ one-command installer for Arch.
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/basement-interactive/caelestia-plus-plus/main/install.sh)
set -euo pipefail

REPO=basement-interactive/caelestia-plus-plus
SHELL_DIR="$HOME/.config/quickshell/caelestia"

[[ $EUID -eq 0 ]] && { echo "run as your normal user, not root"; exit 1; }
command -v pacman >/dev/null || { echo "this installer is Arch-only"; exit 1; }

echo ":: downloading Caelestia++ packages from the latest release"
tmp=$(mktemp -d)
curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" |
    grep -o 'https://[^"]*\.pkg\.tar\.zst' | sort -u > "$tmp/urls"
[[ -s $tmp/urls ]] || { echo "no package assets on the latest release"; exit 1; }
while read -r url; do
    # GitHub asset URLs encode '+' as %2B; decode so filename globs match
    fname=$(basename "$url" | sed 's/%2B/+/g')
    curl -fL -o "$tmp/$fname" "$url"
done < "$tmp/urls"

deps=$(for pkg in "$tmp"/*.pkg.tar.zst; do
    bsdtar -xOf "$pkg" .PKGINFO | awk -F' = ' '$1 == "depend" {print $2}'
done | grep -v '^caelestia' | sort -u)

# pacman -T reports which of these aren't satisfied yet (provides count);
# only then is an AUR helper needed at all
# shellcheck disable=SC2086 — deps is a word list by construction
missing=$(pacman -T $deps || true)

if [[ -z $missing ]]; then
    echo ":: all dependencies already installed"
else
    echo ":: missing dependencies:" $missing
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
    # shellcheck disable=SC2086
    $aur -S --needed --asdeps --noconfirm $missing
fi

# A regular caelestia install conflicts with the ++ packages — swap it out.
# -Rdd because caelestia-shell-git depends on caelestia-cli and metas may pin
# both; the ++ packages provide the same names immediately after. The pinned
# quickshell build joins the swap only when its package is actually in the
# release (never remove quickshell without its replacement in hand).
swap_pattern='^caelestia-(shell|shell-git|cli|meta)$'
if compgen -G "$tmp/caelestia++-quickshell-*.pkg.tar.zst" >/dev/null; then
    swap_pattern='^(caelestia-(shell|shell-git|cli|meta)|quickshell-git|quickshell)$'
fi
old_pkgs=$(pacman -Qq 2>/dev/null | grep -E "$swap_pattern" || true)
if [[ -n $old_pkgs ]]; then
    echo ":: replacing regular caelestia packages:" $old_pkgs
    # shellcheck disable=SC2086
    sudo pacman -Rdd --noconfirm $old_pkgs
fi

echo ":: installing Caelestia++ packages"
sudo pacman -U --noconfirm "$tmp"/*.pkg.tar.zst
if ! grep -q '^IgnorePkg.*caelestia++' /etc/pacman.conf; then
    sudo sed -i '/^\[options\]/a IgnorePkg = caelestia++-shell caelestia++-cli' /etc/pacman.conf
fi

# The shell's easter-egg watcher reads keyboard evdev devices for its
# 5-letter trigger (keeps only the last 5 letter keycodes in RAM, logs
# nothing). That needs membership in the 'input' group.
if ! id -nG "$USER" | grep -qw input; then
    echo ":: adding $USER to the 'input' group for the easter-egg watcher"
    echo "   (remove anytime: sudo gpasswd -d $USER input; effective after re-login)"
    sudo usermod -aG input "$USER"
fi

echo ":: fetching the shell"
if [[ -d $SHELL_DIR/.git ]] && git -C "$SHELL_DIR" remote get-url origin 2>/dev/null | grep -q "$REPO"; then
    echo "   Caelestia++ checkout found, updating"
    git -C "$SHELL_DIR" pull --ff-only || echo "   pull failed (local changes?) — leaving checkout as is"
elif [[ -e $SHELL_DIR ]]; then
    backup="$SHELL_DIR.backup-$(date +%Y%m%d-%H%M%S)"
    echo "   existing non-Caelestia++ shell config found, moving to $backup"
    mv "$SHELL_DIR" "$backup"
    git clone "https://github.com/$REPO.git" "$SHELL_DIR"
else
    git clone "https://github.com/$REPO.git" "$SHELL_DIR"
fi

# Caelestia++ ships a full-info fastfetch config (DE row says Caelestia++).
# Foreign configs are backed up, not clobbered; ours is recognisable by the
# DE row and updated in place on re-runs.
ff_dir="$HOME/.config/fastfetch"
ff_conf="$ff_dir/config.jsonc"
if [[ -f $ff_conf ]] && ! grep -q 'Caelestia++' "$ff_conf"; then
    echo ":: existing fastfetch config backed up to config.jsonc.pre-caelestia++"
    mv "$ff_conf" "$ff_conf.pre-caelestia++"
fi
install -Dm644 "$SHELL_DIR/assets/fastfetch.jsonc" "$ff_conf"

echo
if pgrep -f 'qs -c caelestia' >/dev/null 2>&1; then
    echo ":: a shell instance is already running — restarting it as Caelestia++"
    qs -c caelestia kill 2>/dev/null || pkill -f 'qs -c caelestia' || true
    sleep 1
    setsid -f caelestia shell -d >/dev/null 2>&1
    echo "Caelestia++ installed and running."
else
    echo "Caelestia++ installed. Start it with:  caelestia shell -d"
fi
echo "Hyprland autostart:  exec-once = caelestia shell -d"
echo "Updates arrive in the shell's Settings > Updates tab."
