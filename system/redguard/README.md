# Redguard — behavioral process protection

A lightweight HIPS for this Caelestia setup, companion to redwall. Redwall
governs the network (who may connect out); redguard governs behavior (is a
process acting like an exploit payload). It touches no networking, so it is
completely VPN-agnostic.

## What it catches

Two deliberately narrow, high-confidence detections — chosen so false
positives are near zero, because every hit freezes a real process:

- **reverse-shell** — an interpreter/shell (bash, python, perl, nc, socat, …)
  whose stdin/stdout/stderr is wired to a **network** socket. The textbook
  reverse shell. Normal interactive shells (pty stdio) and pipelines (pipe
  stdio) never match.
- **foreign-exec** — a process whose executable file lives in a world-writable
  scratch dir (`/tmp`, `/dev/shm`, `/var/tmp`, `/run/user`) or has been
  deleted/anonymised (memfd, unlinked) while running. The dropper and
  in-memory-malware pattern. AppImage mounts, Chromium/Electron sandboxes and
  systemd-private paths are excluded.

The spawning parent (e.g. "spawned by firefox") is reported for context but is
never a trigger by itself — browsers legitimately run helper shells, so lineage
alone would be a false-positive machine.

## How it works

```
exec()  ->  kernel netlink proc-connector (real time, no polling)
        ->  pre-filter: interpreter, or exe in scratch/deleted?  no -> ignore
        ->  SIGSTOP (freeze) -> classify from /proc
              benign        -> SIGCONT (released instantly)
              detection     -> prompt the bar (allow / block / once)
        verdict  ->  allow: SIGCONT   block: SIGKILL (group)   once: SIGCONT
                     allow/block remembered per-executable, persisted
```

## Pieces

```
redguardd.py        the daemon (pure Python stdlib: netlink + /proc + signals)
redguardd.service   systemd unit (root; runs at boot, Restart=on-failure)
install.sh          one-time root setup (no compile/venv needed)
uninstall.sh        full removal
```

Shell side (ships with the config, no install):

```
services/Protection.qml                  socket bridge + models + IPC
modules/protection/ProtectionPrompt.qml  the freeze alert (allow/block/once)
modules/protection/ProtectionTab.qml     rules manager (in the security center)
```

## Honesty / limits

- **Best-effort, not a kernel sandbox.** There is a small window between exec
  and freeze. For the interactive payloads this targets — a reverse shell
  waiting for its operator, a dropper about to act — the freeze lands in time.
  It is not a substitute for not running untrusted code.
- **Fails open.** If the bar UI is not connected there is no one to answer, so
  a frozen process is released and logged rather than stuck forever.
  Enforcement is therefore active only while the shell runs (it is the desktop).
- **Freeze, never silent kill.** Unknown detections always ask. Only an
  explicit remembered "block" kills on sight.

## Safety

Stopping the service stops all protection immediately — it never leaves a
process frozen. Killing the daemon does not affect any running program.
