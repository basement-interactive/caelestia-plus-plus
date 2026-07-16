#!/usr/bin/env bash
# Full removal of Redwall. Leaves saved rules in /var/lib/redwall unless --purge.
# Usage: sudo ./uninstall.sh [--purge]
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

echo ">> Stopping and disabling service"
systemctl disable --now redwalld.service 2>/dev/null || true

echo ">> Removing kernel ruleset (networking returns to normal immediately)"
nft delete table inet redwall 2>/dev/null || true

echo ">> Removing files"
rm -f /etc/systemd/system/redwalld.service
rm -rf /opt/redwall /etc/redwall
systemctl daemon-reload

if [[ "${1:-}" == "--purge" ]]; then
    echo ">> Purging saved rules"
    rm -rf /var/lib/redwall
fi

echo "Redwall removed."
