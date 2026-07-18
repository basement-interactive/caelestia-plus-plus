#!/usr/bin/env bash
# One-time root setup for the caelestia "Maximum performance" toggle.
#
# The GUI toggle (services/MaxPerf.qml) only ever writes a plain state file
# it owns; everything here is what turns that file into an actual power-plan
# change, running as root so the shell process never needs elevated rights.
# The shell runs this through pkexec on first enable, so it must work
# non-interactively on any machine: user paths are derived from the invoking
# user, and hardware-specific pieces install only where they apply.
#
# Usage: run as root (pkexec/sudo), directly from the checkout.
set -euo pipefail

# Bump whenever ANY root-side file of this feature changes; the shell's
# system scan compares it against /etc/caelestia/max-perf.version and offers the
# upgrade automatically.
root_half_version=2

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

# Who toggles the feature: pkexec exports PKEXEC_UID, sudo sets SUDO_USER;
# fall back to the checkout's owner for a manual root shell
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
target_user=${SUDO_USER:-}
[[ -z "$target_user" && -n "${PKEXEC_UID:-}" ]] && target_user=$(id -nu "$PKEXEC_UID")
[[ -z "$target_user" ]] && target_user=$(stat -c %U "$here")
if [[ -z "$target_user" || "$target_user" == root ]]; then
    echo "Could not determine the target user." >&2
    exit 1
fi
target_home=$(getent passwd "$target_user" | cut -d: -f6)

# Units and helpers reference the state file by absolute path; stage them
# with the real home substituted in
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
for f in max-perf-sync max-perf-sync.path; do
    sed "s|/home/john|$target_home|g" "$here/$f" > "$stage/$f"
done

install -Dm644 "$here/max-perf.service" /etc/systemd/system/max-perf.service
install -Dm644 "$here/max-perf-sync.service" /etc/systemd/system/max-perf-sync.service
install -Dm644 "$stage/max-perf-sync.path" /etc/systemd/system/max-perf-sync.path
install -Dm755 "$here/max-perf-apply" /usr/local/bin/max-perf-apply
install -Dm755 "$stage/max-perf-sync" /usr/local/bin/max-perf-sync

# ThinkPad-only aggressive fan curve; other machines keep firmware fan
# control (thinkfan-max.service no-ops without its yaml anyway)
if command -v thinkfan >/dev/null && [[ -d /proc/acpi/ibm ]]; then
    install -Dm644 "$here/thinkfan-max.yaml" /etc/thinkfan-max.yaml
    install -Dm644 "$here/thinkfan-max.service" /etc/systemd/system/thinkfan-max.service
else
    echo "No ThinkPad fan interface (or thinkfan missing) — skipping the max-perf fan curve."
fi

# AMD mobile APUs get SMU performance mode via ryzenadj, which needs the
# ryzen_smu kernel module on IO_STRICT_DEVMEM kernels (CachyOS)
if grep -q AuthenticAMD /proc/cpuinfo && command -v ryzenadj >/dev/null; then
    if modinfo ryzen_smu >/dev/null 2>&1; then
        echo ryzen_smu > /etc/modules-load.d/ryzen_smu.conf
        modprobe ryzen_smu || true
    else
        echo "WARNING: ryzen_smu module not installed — ryzenadj power limits will NOT work." >&2
        echo "         Install it first: paru -S dkms linux-cachyos-headers ryzen_smu-dkms-git" >&2
    fi
fi

state_dir=$target_home/.local/state/caelestia
state_file="$state_dir/max-perf"
install -d -o "$target_user" -g "$target_user" "$state_dir"
[[ -f "$state_file" ]] || printf '0\n' > "$state_file"
chown "$target_user:$target_user" "$state_file"

install -d /etc/caelestia
echo "$root_half_version" > /etc/caelestia/max-perf.version

systemctl daemon-reload
systemctl enable --now max-perf-sync.path
systemctl enable --now max-perf-sync.service

echo
echo "Setup complete. Flipping \"Maximum performance\" in the features menu"
echo "(bar wrench) now starts/stops the power-plan applier automatically."
echo "Check with: systemctl status max-perf.service"
