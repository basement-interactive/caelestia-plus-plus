#!/usr/bin/env bash
# Full removal of Redguard. Protection stops immediately; nothing about
# networking or other processes is affected.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

systemctl disable --now redguardd.service 2>/dev/null || true
rm -f /etc/systemd/system/redguardd.service
rm -rf /opt/redguard
rm -f /etc/caelestia/redguard.version
systemctl daemon-reload

echo "Redguard removed. Rules kept at /var/lib/redguard (delete manually if you want them gone)."
