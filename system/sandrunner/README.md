# Sandrunner — fake-root throwaway sandbox

Run any untrusted file with `sandrunner FILE [args...]` and it executes
believing it is root — `id -u` is 0, `sudo`/`doas`/`pkexec`/`su` all "work" —
while actually confined to an unprivileged bubblewrap user namespace that
cannot touch the host. No install, no daemon, no root: the sandbox is built
per-run and evaporates on exit.

## What the program sees vs. what it gets

| Sees | Gets |
|------|------|
| uid 0, `whoami` → root | user namespace mapped to your uid, **zero capabilities** (`CapEff: 0`), no-new-privs set |
| working `sudo` / `doas` / `pkexec` / `su` | shims that strip the options and run the command as-is (already "root") |
| `/usr`, `/bin`, `/lib` | host's, **read-only** — even "sudo" writes fail |
| `/etc` | only passwd/group (synthetic, no host users), ld.so, ssl/ca-certificates, nsswitch, localtime |
| writable `/root`, `/tmp`, `/var`, `/run` | size-capped tmpfs (1G/1G/256M/64M), discarded on exit |
| network, other processes, `/home`, real hostname | nothing — net/pid/ipc/uts unshared, `/home` not mounted at all |
| normal syscalls | seccomp filter (`Seccomp: 2`) on top — see below |
| room to fork/allocate | cgroup scope: TasksMax=512, MemoryMax=50% of RAM, swap denied |

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
`Operation not permitted`; `rm -rf /usr/share/doc` as "sudo" bounced off the
read-only mount file-by-file.

## Usage

```
sandrunner suspicious.sh                 # script, fully isolated
sandrunner ./installer arg1 arg2         # args pass through, exit code too
sandrunner "sudo rm -rf /usr/share/doc"  # probe a command: every rm fails,
                                         # host untouched
sandrunner ls -la /root                  # unquoted commands work too
sandrunner --net fetcher.sh              # allow network (adds resolv.conf/hosts)
sandrunner --gui ./some-app              # Wayland/X11 socket + /dev/dri passthrough
sandrunner --bind-dir ./app/run.sh       # mount parent dir ro so relative paths work
sandrunner --shell                       # poke around the empty sandbox yourself
sandrunner --shell FILE                  # sandbox with FILE mounted, shell first
```

The first argument is treated as a file if it exists; otherwise the arguments
run as a shell command inside the sandbox (a lone path-looking token that
doesn't exist still errors, so typos aren't silently reinterpreted).
Non-executable files are run via a `chmod +x` copy automatically. Exit code of
the sandboxed program is propagated.

Command probing shows what a command *touches*, not what it would do on the
real system: there is no systemd/dbus inside, so e.g.
`sandrunner "sudo systemctl stop foo"` fails with a bus error rather than
simulating the stop. Filesystem-touching commands (`rm`, `install`, `cp`,
package scripts) probe realistically — writes land on read-only mounts or
throwaway tmpfs.

## Caveats

- `--gui` hands the app your compositor socket: it can read window contents /
  inject input on permissive compositors. Only use it for apps you merely
  distrust, not ones you assume are hostile.
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

Nothing to install; a symlink makes it a command:

```
ln -sf "$HOME/.config/quickshell/caelestia/system/sandrunner/sandrunner" ~/.local/bin/sandrunner
```
