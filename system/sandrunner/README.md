# Sandrunner — fake-root throwaway simulation sandbox

Run any untrusted file with `sandrunner FILE [args...]` and it executes
believing it is root on your real system — `id -u` is 0, `sudo`/`doas`/
`pkexec`/`su` all "work", `pacman -S` genuinely installs, config edits stick —
while actually confined to an unprivileged bubblewrap user namespace whose
every write lands in a throwaway fuse-overlayfs layer. The host never
changes; the whole world evaporates on exit. No daemon, no root.

## What the program sees vs. what it gets

| Sees | Gets |
|------|------|
| uid 0, `whoami` → root | user namespace mapped to your uid, **zero capabilities** (`CapEff: 0`), no-new-privs set |
| working `sudo` / `doas` / `pkexec` / `su` | shims that strip the options and run the command as-is (already "root") |
| **writable** `/usr`, `/etc`, `/opt`, pacman DB + cache | fuse-overlayfs merged views — writes go to a throwaway upper layer, the host stays untouched; `sudo pacman -S pkg` fully installs (with `--net`), then vanishes |
| `/etc/passwd`, hostname | synthetic (root+nobody, `sandbox`) even though the rest of /etc is the host's |
| writable `/root`, `/tmp`, `/var`, `/run` | size-capped tmpfs (1G/1G/256M/64M), discarded on exit |
| network, other processes, `/home`, real hostname | nothing — net/pid/ipc/uts unshared, `/home` not mounted at all |
| normal syscalls | seccomp filter (`Seccomp: 2`) on top — see below |
| room to fork/allocate | cgroup scope: TasksMax=512, MemoryMax=50% of RAM, swap denied |

Without fuse-overlayfs installed the sandbox falls back to the old read-only
view (installs fail realistically instead of succeeding).

## Hardening layers

1. **Namespaces** — user/mount/pid/net/ipc/uts/cgroup all unshared;
   `--disable-userns` forbids creating nested user namespaces (the classic
   sandbox-escape amplifier).
2. **Zero capabilities + no-new-privs** — "root" can't use any root power,
   and no setuid binary can hand privileges back.
3. **Seccomp** (`seccomp-gen.py`, pure-stdlib BPF assembler, no libseccomp
   needed) — EPERMs the unprivileged kernel attack surface: `keyctl`/`add_key`,
   `bpf`, `io_uring_*`, `userfaultfd`, `perf_event_open`, `ptrace`,
   `process_vm_*`, `open_by_handle_at`/`name_to_handle_at`, the whole
   mount/module/reboot family, `unshare`/`setns`, `clone(CLONE_NEWUSER)`;
   `clone3` returns ENOSYS (so libc falls back to filterable `clone`);
   `TIOCSTI`/`TIOCLINUX` terminal-injection ioctls blocked (on top of
   `--new-session`); non-x86_64 syscall ABIs (ia32/x32) kill the process.
4. **Resource caps** — `systemd-run --user --scope` puts each run in its own
   cgroup: fork bombs die at 512 tasks, memory at 50% of RAM, no swap
   thrash; tmpfs mounts are size-capped so they can't fill RAM either.
5. **Environment** — `--clearenv`, synthetic identity files, `--die-with-parent`.

Verified live: fork bomb (600 spawns) hit the task cap and died inside;
`unshare`, `dmesg`, `io_uring_setup`, `keyctl` all return
`Operation not permitted`; `sudo pacman -S --noconfirm tree` with `--net`
downloaded, ran hooks and installed inside the overlay (`tree` runnable),
host DB untouched; `rm /usr/bin/ls` "worked" inside, `/usr/bin/ls` intact
on the host.

## Usage

```
sandrunner suspicious.sh                 # script, fully isolated
sandrunner ./installer arg1 arg2         # args pass through, exit code too
sandrunner "sudo rm -rf /usr/share/doc"  # probe: rm "succeeds" in the overlay,
                                         # host untouched
sandrunner ls -la /root                  # unquoted commands work too
sandrunner --net fetcher.sh              # allow network (adds resolv.conf/hosts)
sandrunner --gui ./some-app              # Wayland/X11 socket + /dev/dri passthrough
sandrunner --net "sudo pacman -S htop"   # full simulated install, discarded
sandrunner --bind-dir ./app/run.sh       # mount parent dir ro so relative paths work
sandrunner --shell                       # poke around the empty sandbox yourself
sandrunner --shell FILE                  # sandbox with FILE mounted, shell first
```

The first argument is treated as a file if it exists; otherwise the arguments
run as a shell command inside the sandbox (a lone path-looking token that
doesn't exist still errors, so typos aren't silently reinterpreted).
Non-executable files are run via a `chmod +x` copy automatically. Exit code of
the sandboxed program is propagated.

Simulation is filesystem-true, not service-true: there is no systemd or
SYSTEM bus inside, so e.g. `sandrunner "sudo systemctl stop foo"` fails with
a bus error rather than simulating the stop. `--gui` runs get a PRIVATE
session D-Bus (`dbus-run-session`) — real bus, empty service list, never the
host's (session dbus can screenshot/inject input) — so tray/dbusmenu
libraries stop erroring. Filesystem-touching commands (`rm`,
`install`, `cp`, `pacman`, installers, config edits) behave exactly as they
would on the host — into the throwaway overlay. pacman specifics: snapshot
pre-hooks (snap-pac/timeshift) are masked and `DownloadUser`/scriptlet
network isolation are disabled inside (they need capabilities fake root
doesn't have); package installs need `--net` unless the package is already
in the host's pacman cache.

## Caveats

- `--gui` hands the app your compositor socket: it can read window contents /
  inject input on permissive compositors. Only use it for apps you merely
  distrust, not ones you assume are hostile.
- The overlaid `/etc` exposes the host's world-readable config to the
  program (root-only files like shadow stay unreadable); identity files and
  hostname are still synthetic.
- Overlay upper layers live under `/tmp` for the run — a huge simulated
  install is bounded by your `/tmp` size.
- `--bind-dir` exposes sibling files of FILE (read-only) to the program.
- `--net` is full outbound network; combine with distrust accordingly
  (Redwall still sees the traffic — it egresses as your uid).
- Seccomp blocks `ptrace` (strace/gdb inside won't work) and io_uring; 32-bit
  binaries are killed outright. Browsers' internal sandboxes may fail under
  `--disable-userns`.
- Kernel attack surface is still the host kernel; the seccomp denylist trims
  the classic exploit primitives, but a kernel 0-day in an allowed syscall
  beats any sandbox. For real malware analysis use a VM.

## Install

Two packages and a symlink (the installer and the system scan do all this):

```
sudo pacman -S --needed bubblewrap fuse-overlayfs
ln -sf "$HOME/.config/quickshell/caelestia/system/sandrunner/sandrunner" ~/.local/bin/sandrunner
```
