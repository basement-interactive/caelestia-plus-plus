#!/usr/bin/env bash
# One-time root setup for the caelestia "Maximum performance" toggle.
#
# The GUI toggle (services/MaxPerf.qml) only ever writes a plain state file
# it owns; everything here is what turns that file into an actual power-plan
# change, running as root so the shell process never needs elevated rights.
#
# Usage: sudo ./install.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

for bin in thinkfan ryzenadj powerprofilesctl; do
    if ! command -v "$bin" >/dev/null; then
        echo "$bin not found. Install it first." >&2
        exit 1
    fi
done

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

install -Dm644 "$here/thinkfan-max.yaml" /etc/thinkfan-max.yaml
install -Dm644 "$here/thinkfan-max.service" /etc/systemd/system/thinkfan-max.service
install -Dm644 "$here/max-perf.service" /etc/systemd/system/max-perf.service
install -Dm644 "$here/max-perf-sync.service" /etc/systemd/system/max-perf-sync.service
install -Dm644 "$here/max-perf-sync.path" /etc/systemd/system/max-perf-sync.path
install -Dm755 "$here/max-perf-apply" /usr/local/bin/max-perf-apply
install -Dm755 "$here/max-perf-sync" /usr/local/bin/max-perf-sync

# ryzenadj needs the ryzen_smu kernel module on IO_STRICT_DEVMEM kernels
# (CachyOS): load it now and on every boot when it is installed.
if modinfo ryzen_smu >/dev/null 2>&1; then
    echo ryzen_smu > /etc/modules-load.d/ryzen_smu.conf
    modprobe ryzen_smu || true
else
    echo "WARNING: ryzen_smu module not installed — ryzenadj power limits will NOT work." >&2
    echo "         Install it first: paru -S dkms linux-cachyos-headers ryzen_smu-dkms-git" >&2
fi

state_dir=/home/john/.local/state/caelestia
state_file="$state_dir/max-perf"
install -d -o john -g john "$state_dir"
[[ -f "$state_file" ]] || printf '0\n' > "$state_file"
chown john:john "$state_file"

systemctl daemon-reload
systemctl enable --now max-perf-sync.path
systemctl enable --now max-perf-sync.service

cat <<'EOF'

Setup complete.

Manual fan control needs thinkpad_acpi loaded with fan_control=1 — bed-mode's
install already put that modprobe config in place; if you have rebooted since
then, nothing more to do.

Flipping "Maximum performance" in the features menu (bar wrench) now
starts/stops the power-plan applier and fan curve automatically. Check with:

  systemctl status max-perf.service thinkfan-max.service
  journalctl -u max-perf.service -f
EOF
