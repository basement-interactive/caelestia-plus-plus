#!/usr/bin/env bash
# Generic staged service repair used by the system scan's quick fixes.
# Diagnoses before acting and narrates every step (streamed live into the
# debug window). Never hangs: every blocking call is timeout-wrapped.
#
#   service.sh [--user] [--pkg NAME] [--restart] UNIT [UNIT...]
#
#   --user      operate on the user manager (run unprivileged)
#   --pkg NAME  package that ships the unit: installed if missing,
#               reinstalled if the unit file is gone
#   --restart   restart+verify instead of enable+start (for stale state,
#               e.g. duplicate audio sinks)
#
# Stages per unit: file exists (else install/reinstall the package),
# unmask, clear a stuck boot job queue (system scope), reset-failed,
# enable (static units just start), start --no-block, poll with progress,
# and on failure print the unit's own journal instead of a generic error.
set -u

step() { echo "==> $*"; }
ok()   { echo "OK   $*"; }
warn() { echo "WARN $*"; }
fail() { echo "FAIL $*"; }

USER_SCOPE=0
PKG=""
MODE=ensure
UNITS=()
while [ $# -gt 0 ]; do
    case "$1" in
    --user) USER_SCOPE=1 ;;
    --pkg) PKG=$2; shift ;;
    --restart) MODE=restart ;;
    *) UNITS+=("$1") ;;
    esac
    shift
done
if [ ${#UNITS[@]} -eq 0 ]; then
    fail "no units given"
    exit 1
fi

SC=(systemctl)
[ "$USER_SCOPE" = 1 ] && SC=(systemctl --user)

sc() { timeout 20 "${SC[@]}" "$@"; }

clear_stale_pacman_lock() {
    if [ -e /var/lib/pacman/db.lck ] && ! pgrep -x pacman >/dev/null; then
        step "Removing a stale pacman lock (no pacman process is running)"
        rm -f /var/lib/pacman/db.lck
    fi
}

diagnose() {
    fail "$1 did not come up — this is what it says itself:"
    if [ "$USER_SCOPE" = 1 ]; then
        journalctl --user -u "$1" -b --no-pager -n 12 2>/dev/null | sed 's/^/     /'
    else
        journalctl -u "$1" -b --no-pager -n 12 2>/dev/null | sed 's/^/     /'
    fi
    exit 1
}

if [ -n "$PKG" ]; then
    step "Checking the $PKG package"
    if pacman -Q "$PKG" >/dev/null 2>&1; then
        ok "installed: $(pacman -Q "$PKG")"
    else
        step "$PKG is not installed — that is why the unit does not exist; installing it"
        clear_stale_pacman_lock
        if timeout 300 pacman -S --needed --noconfirm "$PKG"; then
            ok "$PKG installed"
        else
            fail "pacman could not install $PKG"
            exit 1
        fi
    fi
fi

for u in "${UNITS[@]}"; do
    step "Checking unit $u"
    if ! sc cat "$u" >/dev/null 2>&1; then
        if [ -n "$PKG" ]; then
            step "Unit file missing — reinstalling $PKG to restore it"
            clear_stale_pacman_lock
            timeout 300 pacman -S --noconfirm "$PKG" >/dev/null 2>&1 || true
            sc daemon-reload 2>/dev/null || true
        fi
        if ! sc cat "$u" >/dev/null 2>&1; then
            if [ -n "$PKG" ]; then
                fail "$u does not exist even after reinstalling $PKG"
            else
                fail "$u does not exist on this system"
            fi
            exit 1
        fi
    fi
    ok "unit file present"

    enable_state=$(sc is-enabled "$u" 2>&1 | head -1)
    echo "     enable state: $enable_state"
    if [ "$enable_state" = "masked" ]; then
        step "Unmasking $u"
        if sc unmask "$u"; then
            ok "unmasked"
        else
            fail "could not unmask $u"
            exit 1
        fi
    fi

    if [ "$USER_SCOPE" = 0 ]; then
        # A stuck boot transaction queues every new start job forever
        njobs=$("${SC[@]}" list-jobs --no-legend --plain 2>/dev/null | grep -c .)
        if [ "$njobs" -gt 0 ]; then
            warn "$njobs stuck systemd jobs — clearing them so this start is not queued forever:"
            "${SC[@]}" list-jobs --no-legend --plain 2>/dev/null | sed 's/^/     /'
            timeout 5 plymouth quit 2>/dev/null || true
            if pgrep -x plymouthd >/dev/null; then
                pkill -x plymouthd 2>/dev/null || true
                sleep 1
                pgrep -x plymouthd >/dev/null && pkill -9 -x plymouthd 2>/dev/null
            fi
            sc cancel 2>/dev/null || true
        fi
    fi

    sc reset-failed "$u" 2>/dev/null || true

    if [ "$MODE" = "restart" ]; then
        step "Restarting $u"
        timeout 30 "${SC[@]}" restart "$u" 2>&1 | sed 's/^/     /'
    else
        step "Enabling $u"
        enable_out=$(sc enable "$u" 2>&1)
        if [ -n "$enable_out" ]; then
            printf '%s\n' "$enable_out" | sed 's/^/     /'
        fi
        if printf '%s' "$enable_out" | grep -qi 'no install\|transient or generated\|does not exist'; then
            warn "unit cannot be enabled (static) — starting it directly"
        fi
        step "Starting $u"
        timeout 10 "${SC[@]}" start --no-block "$u" 2>&1 | sed 's/^/     /'
    fi

    waited=0
    until "${SC[@]}" is-active -q "$u" 2>/dev/null; do
        "${SC[@]}" is-failed -q "$u" 2>/dev/null && diagnose "$u"
        [ "$waited" -ge 30 ] && diagnose "$u"
        [ $((waited % 5)) -eq 0 ] && [ "$waited" -gt 0 ] && echo "     still starting... (${waited}s)"
        sleep 1
        waited=$((waited + 1))
    done
    ok "$u is active"
done

echo "DONE"
