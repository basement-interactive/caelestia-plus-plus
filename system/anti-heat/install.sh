#!/usr/bin/env bash
# One-time root setup for the caelestia "Anti-Heat" toggle.
#
# The GUI toggle (services/AntiHeat.qml) only ever writes a plain state file
# it owns; everything here is what turns that file into an actual undervolt
# and fan-curve change, running as root so the shell process never needs
# elevated rights. The shell runs this through pkexec on first enable, so it
# must work non-interactively on any machine: user paths are derived from
# the invoking user, and hardware-specific pieces install only where they
# apply.
#
# Usage: run as root (pkexec/sudo), directly from the checkout.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
target_user=${SUDO_USER:-}
[[ -z "$target_user" && -n "${PKEXEC_UID:-}" ]] && target_user=$(id -nu "$PKEXEC_UID")
[[ -z "$target_user" ]] && target_user=$(stat -c %U "$here")
if [[ -z "$target_user" || "$target_user" == root ]]; then
    echo "Could not determine the target user." >&2
    exit 1
fi
target_home=$(getent passwd "$target_user" | cut -d: -f6)

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
for f in anti-heat-sync anti-heat-sync.path; do
    sed "s|/home/john|$target_home|g" "$here/$f" > "$stage/$f"
done

install -Dm644 "$here/anti-heat.service" /etc/systemd/system/anti-heat.service
install -Dm644 "$here/anti-heat-sync.service" /etc/systemd/system/anti-heat-sync.service
install -Dm644 "$stage/anti-heat-sync.path" /etc/systemd/system/anti-heat-sync.path
install -Dm755 "$here/anti-heat-apply" /usr/local/bin/anti-heat-apply
install -Dm755 "$stage/anti-heat-sync" /usr/local/bin/anti-heat-sync

# ThinkPad-only early fan curve; other machines keep firmware fan control
if command -v thinkfan >/dev/null && [[ -d /proc/acpi/ibm ]]; then
    install -Dm644 "$here/thinkfan-cool.yaml" /etc/thinkfan-cool.yaml
    install -Dm644 "$here/thinkfan-cool.service" /etc/systemd/system/thinkfan-cool.service
else
    echo "No ThinkPad fan interface (or thinkfan missing) — skipping the early fan curve."
fi

# The AMD undervolt path needs ryzenadj, which needs the ryzen_smu kernel
# module on IO_STRICT_DEVMEM kernels (CachyOS)
if grep -q AuthenticAMD /proc/cpuinfo; then
    if ! command -v ryzenadj >/dev/null; then
        echo "WARNING: ryzenadj not installed — the AMD undervolt will NOT work." >&2
    elif modinfo ryzen_smu >/dev/null 2>&1; then
        echo ryzen_smu > /etc/modules-load.d/ryzen_smu.conf
        modprobe ryzen_smu || true
    else
        echo "WARNING: ryzen_smu module not installed — the undervolt will NOT work." >&2
        echo "         Install it first: paru -S dkms linux-cachyos-headers ryzen_smu-dkms-git" >&2
    fi
fi

state_dir=$target_home/.local/state/caelestia
state_file="$state_dir/anti-heat"
install -d -o "$target_user" -g "$target_user" "$state_dir"
[[ -f "$state_file" ]] || printf '0\n' > "$state_file"
chown "$target_user:$target_user" "$state_file"

systemctl daemon-reload
systemctl enable --now anti-heat-sync.path
systemctl enable --now anti-heat-sync.service

cat <<'EOF'

Setup complete.

Flipping "Anti-Heat" in the features menu (bar wrench) now starts/stops the
undervolt loop and the early fan curve automatically. Check with:

  systemctl status anti-heat.service
  journalctl -u anti-heat.service -f

Stability: the -10 curve-optimizer offset is conservative, but undervolt
crashes show up under LIGHT load (idle/browsing), not stress tests. If the
machine ever hangs or MCEs with anti-heat on, lower CO_OFFSET in
/usr/local/bin/anti-heat-apply (e.g. -5) or turn the mode off.
EOF
