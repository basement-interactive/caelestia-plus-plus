#!/usr/bin/env bash
# One-time root setup for the caelestia "Anti-Heat" toggle.
#
# The GUI toggle (services/AntiHeat.qml) only ever writes a plain state file
# it owns; everything here is what turns that file into an actual undervolt
# and fan-curve change, running as root so the shell process never needs
# elevated rights.
#
# Usage: sudo ./install.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

for bin in thinkfan ryzenadj; do
    if ! command -v "$bin" >/dev/null; then
        echo "$bin not found. Install it first." >&2
        exit 1
    fi
done

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

install -Dm644 "$here/thinkfan-cool.yaml" /etc/thinkfan-cool.yaml
install -Dm644 "$here/thinkfan-cool.service" /etc/systemd/system/thinkfan-cool.service
install -Dm644 "$here/anti-heat.service" /etc/systemd/system/anti-heat.service
install -Dm644 "$here/anti-heat-sync.service" /etc/systemd/system/anti-heat-sync.service
install -Dm644 "$here/anti-heat-sync.path" /etc/systemd/system/anti-heat-sync.path
install -Dm755 "$here/anti-heat-apply" /usr/local/bin/anti-heat-apply
install -Dm755 "$here/anti-heat-sync" /usr/local/bin/anti-heat-sync

# ryzenadj needs the ryzen_smu kernel module on IO_STRICT_DEVMEM kernels
# (CachyOS): max-perf's install normally handles this, but be self-contained.
if modinfo ryzen_smu >/dev/null 2>&1; then
    echo ryzen_smu > /etc/modules-load.d/ryzen_smu.conf
    modprobe ryzen_smu || true
else
    echo "WARNING: ryzen_smu module not installed — the undervolt will NOT work." >&2
    echo "         Install it first: paru -S dkms linux-cachyos-headers ryzen_smu-dkms-git" >&2
fi

state_dir=/home/john/.local/state/caelestia
state_file="$state_dir/anti-heat"
install -d -o john -g john "$state_dir"
[[ -f "$state_file" ]] || printf '0\n' > "$state_file"
chown john:john "$state_file"

systemctl daemon-reload
systemctl enable --now anti-heat-sync.path
systemctl enable --now anti-heat-sync.service

cat <<'EOF'

Setup complete.

Flipping "Anti-Heat" in the features menu (bar wrench) now starts/stops the
undervolt loop and the early fan curve automatically. Check with:

  systemctl status anti-heat.service thinkfan-cool.service
  journalctl -u anti-heat.service -f

Stability: the -10 curve-optimizer offset is conservative, but undervolt
crashes show up under LIGHT load (idle/browsing), not stress tests. If the
machine ever hangs or MCEs with anti-heat on, lower CO_OFFSET in
/usr/local/bin/anti-heat-apply (e.g. -5) or turn the mode off.
EOF
