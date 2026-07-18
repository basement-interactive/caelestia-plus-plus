#!/usr/bin/env bash
# Staged repair for power-profiles-daemon, run as root (pkexec) by the
# system scan's "Repair" quick fix. It diagnoses as it goes and only applies
# the remedies the diagnosis calls for; every line streams live into the
# debug window so the user watches what happens and why.
#
# Stages:
#   1. package present?        install if not
#   2. unit file present?      reinstall the package if not
#   3. unit masked?            unmask
#   4. conflicting daemons?    stop + disable them (tlp, tuned, tuned-ppd,
#                              auto-cpufreq, laptop-mode) — they claim the
#                              same knobs/D-Bus name and are exactly what
#                              produces the 25s activation NoReply
#   5. enable --now, wait up to 10s for active
#   6. verify D-Bus answers; on failure, print the unit's journal so the
#      real error is on screen instead of a generic "did not work"
set -u

step() { echo "==> $*"; }
ok()   { echo "OK   $*"; }
warn() { echo "WARN $*"; }
fail() { echo "FAIL $*"; }

step "Checking the power-profiles-daemon package"
if pacman -Q power-profiles-daemon >/dev/null 2>&1; then
    ok "installed: $(pacman -Q power-profiles-daemon)"
else
    step "Not installed — installing it now"
    if pacman -S --needed --noconfirm power-profiles-daemon; then
        ok "package installed"
    else
        fail "pacman could not install power-profiles-daemon"
        exit 1
    fi
fi

step "Checking the systemd unit file"
if systemctl cat power-profiles-daemon.service >/dev/null 2>&1; then
    ok "unit file present"
else
    step "Unit file missing despite the package — reinstalling to restore it"
    if pacman -S --noconfirm power-profiles-daemon; then
        systemctl daemon-reload
        ok "package reinstalled, units reloaded"
    else
        fail "reinstall failed"
        exit 1
    fi
fi

enable_state=$(systemctl is-enabled power-profiles-daemon 2>&1 || true)
echo "     unit enable state: $enable_state"
if [ "$enable_state" = "masked" ]; then
    step "Unit is masked (usually another power tool did this) — unmasking"
    if systemctl unmask power-profiles-daemon; then
        ok "unmasked"
    else
        fail "could not unmask"
        exit 1
    fi
fi

step "Checking for conflicting power daemons"
found_conflict=0
for c in tlp tuned tuned-ppd auto-cpufreq laptop-mode; do
    if systemctl is-active -q "$c.service" 2>/dev/null || systemctl is-enabled -q "$c.service" 2>/dev/null; then
        found_conflict=1
        step "$c.service is active/enabled — it blocks power-profiles-daemon; stopping and disabling it"
        if systemctl disable --now "$c.service" 2>/dev/null; then
            ok "$c stopped and disabled (re-enable later with: systemctl enable --now $c)"
        else
            warn "could not disable $c — continuing anyway"
        fi
    fi
done
[ "$found_conflict" = 0 ] && ok "none found"

step "Enabling and starting power-profiles-daemon"
systemctl enable --now power-profiles-daemon 2>&1 | sed 's/^/     /'
tries=0
until systemctl is-active -q power-profiles-daemon; do
    tries=$((tries + 1))
    if [ "$tries" -ge 10 ]; then
        fail "service did not become active after 10s — this is what the daemon itself says:"
        journalctl -u power-profiles-daemon -b --no-pager -n 15 2>/dev/null | sed 's/^/     /'
        systemctl status power-profiles-daemon --no-pager -l 2>/dev/null | head -12 | sed 's/^/     /'
        exit 1
    fi
    sleep 1
done
ok "service is active"

step "Verifying the daemon answers on D-Bus"
if powerprofilesctl get >/dev/null 2>&1; then
    ok "D-Bus answers — active profile: $(powerprofilesctl get 2>/dev/null)"
else
    warn "service runs but D-Bus is not answering yet — give it a few seconds"
fi

echo "DONE — reload the shell (debug window footer) so it reconnects to the daemon."
