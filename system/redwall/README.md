# Redwall — per-application interactive firewall

SimpleWall-style outbound firewall for this Caelestia setup. The first time an
executable opens a new outbound connection it is **held at the kernel** while a
popup asks you to allow or deny it; the choice is remembered per-executable and
persisted, so it survives reboots. Managed entirely from the red shield in the
top bar (next to the tray).

## Pieces

```
redwalld.py        enforcement daemon (NFQUEUE): attribution, rules, UI socket
redwall.nft        nftables ruleset: hooks OUTPUT, queues NEW connections
redwalld.service   systemd unit: starts the daemon at boot (survives reboots)
install.sh         one-time root setup
uninstall.sh       full removal (networking returns to normal immediately)
```

Shell side (no install, ships with the config):

```
services/Firewall.qml                    socket bridge + models + IPC
modules/bar/components/FirewallButton.qml animated bar shield
modules/firewall/FirewallPrompt.qml       animated allow/deny popup
modules/firewall/FirewallPanel.qml        rules manager
```

## How it works

```
app connect()  ->  nftables OUTPUT hook (inet, v4+v6)
               ->  NEW tcp/udp  ->  NFQUEUE 0 (packet HELD)
redwalld: held SYN's local port -> /proc/net -> inode -> pid -> exe
   known rule?  allow -> ACCEPT   deny -> DROP
   unknown?     hold packet, prompt the bar over /run/redwall/ui.sock
   verdict      -> ACCEPT/DROP the held packet(s) + remember per-exe
```

Prompts are per-executable, so a retransmitted SYN or several parallel
connections from one app produce a single popup.

### What "Deny" guarantees

- **New connections**: the SYN is held, so Deny drops it before it completes;
  retransmits stay NEW and are re-dropped. Nothing leaks.
- **Live connections**: denying an app (prompt or panel flip) also tears down
  its current sockets — `ss -K` RSTs open TCP sockets immediately and
  `conntrack -D` clears per-port state so UDP/QUIC flows fall out of the
  established fast-path and get re-dropped. A deny bites right now, not just on
  the next connection.
- **DNS**: `:53` is filtered too, so a denied app cannot use DNS (tunnel/exfil)
  either. `:53` is auto-allowed for non-denied apps without a prompt, so normal
  resolution never stalls.

### Safety

- The nft queue rule has `bypass`: if the daemon is not running the kernel
  **accepts** (fails OPEN) — a crashed/stopped daemon never cuts networking.
  Corollary: Deny is enforced while the daemon runs (systemd keeps it up,
  `Restart=on-failure`); if you stop the service, filtering stops.
- Loopback and established/related are always allowed. ICMP is allowed
  unconditionally (ping / path-MTU) — ICMP tunnels are out of scope.
- No UI connected => auto-allow (never brick the network when the bar is down).
- `uninstall.sh` flushes the table instantly; stopping the service also tears
  the ruleset down (`ExecStopPost`).

## Install (one-time, root)

```sh
sudo ./install.sh
```

Installs `nftables`, `libnetfilter_queue`, builds a venv with the `NetfilterQueue`
binding, deploys to `/opt/redwall`, writes `/etc/redwall/redwall.nft` and the
systemd unit, and enables `redwalld.service`. The bar shield turns from a dim
struck shield to a red check once it connects.

Rules live in `/var/lib/redwall/rules.json`. Socket: `/run/redwall/ui.sock`
(owned `root:<your-gid>`, mode 0660).

## Use

- **Popup** on each new app: **Allow** (remember), **Deny** (remember),
  **Once** (allow this time only, no rule).
- **Shield** in the bar: dim = daemon off (or firewall disabled), red check =
  clear, red `!` + count badge = prompts waiting. Click it to open the rules
  manager.
- **Rules manager**: a master **on/off switch** in the header disables/enables
  the whole firewall (traffic passes when off, rules are kept, state persists
  across reboots). Flip any app between Allow/Deny or delete its rule. Also
  reachable via `qs -c caelestia ipc call firewall togglePanel` (bind a key).

## Test the UI without root

```sh
python3 redwalld.py --simulate --sock /run/user/$UID/redwall-ui.sock \
    --rules /run/user/$UID/redwall-rules.json --ui-gid $(id -g)
```

Simulate mode skips NFQUEUE/root and injects synthetic connection events; feed
it `{"t":"simconnect","exe":"...","name":"...","dst":"...","port":443}` lines
over the socket. Real enforcement only runs under the installed service.

## Remove

```sh
sudo ./uninstall.sh          # keep saved rules
sudo ./uninstall.sh --purge  # also delete /var/lib/redwall
```

## Install on another machine (Hyprland + Caelestia)

`redwall-bootstrap.sh` is a self-contained installer: it embeds the UI + system
files and wires the bar/shell idempotently (backing up touched files as
`*.redwall-bak`), then runs the privileged install.

```sh
# hand a friend the file, or host it and:
curl -fsSL <your-url>/redwall-bootstrap.sh | bash
# or just:
bash redwall-bootstrap.sh
```

It assumes caelestia at `~/.config/quickshell/caelestia` (override with
`CAEL=/path`) and prompts for sudo for the system part. Re-runnable; skips
anything already wired.

## Notes / limits

- Attribution is done while the SYN is held (socket live in `/proc`), which is
  reliable for interactive prompting. Extremely short-lived flows that beat the
  hold are accepted rather than mis-attributed.
- Outbound only (matches SimpleWall's common mode). Inbound is not filtered
  here; add a separate input chain if you want that.
