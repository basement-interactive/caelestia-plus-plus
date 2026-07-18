#!/usr/bin/env bash
# One-time root install for Redguard, the behavioral process protection daemon.
#
# Deploys the daemon (pure-Python, no venv/compile needed — unlike redwall it
# has no NFQUEUE binding) and a systemd service that starts it at boot. The
# Quickshell Protection tab is the UI and needs no install. Run via pkexec by
# the shell on first enable, so it works non-interactively on any machine.
set -euo pipefail

root_half_version=1

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The gid allowed to talk to the UI socket = the real user's primary group.
uigid=${PKEXEC_UID:+$(id -g "$PKEXEC_UID" 2>/dev/null)}
[[ -z "${uigid:-}" ]] && uigid=${SUDO_GID:-}
[[ -z "${uigid:-}" ]] && uigid=$(stat -c %g "$here")

echo ">> Deploying daemon to /opt/redguard"
install -d /opt/redguard
install -m755 "$here/redguardd.py" /opt/redguard/redguardd.py
install -m644 "$here/README.md" /opt/redguard/README.md 2>/dev/null || true

echo ">> Installing systemd unit"
sed "s/__UIGID__/$uigid/" "$here/redguardd.service" > /etc/systemd/system/redguardd.service

install -d /etc/caelestia
echo "$root_half_version" > /etc/caelestia/redguard.version

echo ">> Enabling service"
systemctl daemon-reload
systemctl enable redguardd.service
# restart (not just start) so re-running the installer applies daemon updates
systemctl restart redguardd.service

echo
echo "Redguard installed and running. Verify with:"
echo "    systemctl status redguardd.service"
echo
echo "The Protection tab turns active once the shell reconnects to the socket."
echo "Suspicious execs now freeze and prompt. Manage rules from the shield popup."
echo "To remove everything: sudo $here/uninstall.sh"
