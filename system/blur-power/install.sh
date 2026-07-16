#!/usr/bin/env bash
# Install the blur power-sync: blur on AC, off on battery.
set -euo pipefail

here=$(dirname "$(realpath "$0")")

install -Dm755 "$here/blur-power-sync" /usr/local/bin/blur-power-sync
install -Dm644 "$here/90-blur-power.rules" /etc/udev/rules.d/90-blur-power.rules

udevadm control --reload
# Apply the correct state right now.
/usr/local/bin/blur-power-sync

echo "blur-power installed. Hyprland startup hook lives in execs.lua."
