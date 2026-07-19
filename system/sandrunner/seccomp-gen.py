#!/usr/bin/env python3
"""Generate the seccomp BPF filter sandrunner feeds to bwrap.

Hand-assembled classic-BPF for x86_64, pure stdlib — no libseccomp binding
needed. Deny-list of kernel attack surface an unprivileged (capability-less)
process can still reach: keyring, bpf(), io_uring, userfaultfd,
perf_event_open, ptrace — classic local-privesc primitives. Mount/module/
reboot syscalls are listed too even though the empty capability set already
stops them: defence in depth if a kernel bug ever leaks a capability.

Arg-filtered rules: clone(CLONE_NEWUSER) is refused (backs up bwrap's
--disable-userns), clone3 returns ENOSYS so libc falls back to the
filterable clone, and the TIOCSTI/TIOCLINUX terminal-injection ioctls are
refused (backs up --new-session). Non-x86_64 syscall ABIs (x32, ia32) kill
the process. Everything else is allowed.

Usage: seccomp-gen.py OUTPUT_FILE
"""
import struct
import sys

AUDIT_ARCH_X86_64 = 0xC000003E
X32_SYSCALL_BIT = 0x40000000

BPF_LD_W_ABS = 0x20
BPF_JEQ_K = 0x15
BPF_JSET_K = 0x45
BPF_RET_K = 0x06

RET_ALLOW = 0x7FFF0000
RET_KILL_PROCESS = 0x80000000
RET_EPERM = 0x00050000 | 1
RET_ENOSYS = 0x00050000 | 38

OFF_NR = 0
OFF_ARCH = 4
OFF_ARG0 = 16
OFF_ARG1 = 24

NR_IOCTL = 16
NR_CLONE = 56
CLONE_NEWUSER = 0x10000000
TIOCSTI = 0x5412
TIOCLINUX = 0x541C

# x86_64 syscall numbers, denied with EPERM.
DENY = {
    "ptrace": 101, "syslog": 103, "uselib": 134, "personality": 135,
    "ustat": 136, "sysfs": 139, "vhangup": 153, "pivot_root": 155,
    "_sysctl": 156, "acct": 163, "mount": 165, "umount2": 166,
    "swapon": 167, "swapoff": 168, "reboot": 169, "sethostname": 170,
    "setdomainname": 171, "iopl": 172, "ioperm": 173, "create_module": 174,
    "init_module": 175, "delete_module": 176, "get_kernel_syms": 177,
    "query_module": 178, "quotactl": 179, "nfsservctl": 180,
    "lookup_dcookie": 212, "kexec_load": 246, "add_key": 248,
    "request_key": 249, "keyctl": 250, "unshare": 272,
    "perf_event_open": 298, "name_to_handle_at": 303,
    "open_by_handle_at": 304, "setns": 308, "process_vm_readv": 310,
    "process_vm_writev": 311, "kcmp": 312, "finit_module": 313,
    "kexec_file_load": 320, "bpf": 321, "userfaultfd": 323,
    "io_uring_setup": 425, "io_uring_enter": 426, "io_uring_register": 427,
    "open_tree": 428, "move_mount": 429, "fsopen": 430, "fsconfig": 431,
    "fsmount": 432, "fspick": 433, "pidfd_getfd": 438,
    "mount_setattr": 442, "quotactl_fd": 443, "memfd_secret": 447,
}


def stmt(code, k):
    return struct.pack("<HBBI", code, 0, 0, k)


def jump(code, k, jt, jf):
    return struct.pack("<HBBI", code, jt, jf, k)


def build():
    prog = [
        stmt(BPF_LD_W_ABS, OFF_ARCH),
        jump(BPF_JEQ_K, AUDIT_ARCH_X86_64, 1, 0),
        stmt(BPF_RET_K, RET_KILL_PROCESS),
        stmt(BPF_LD_W_ABS, OFF_NR),
        jump(BPF_JSET_K, X32_SYSCALL_BIT, 0, 1),
        stmt(BPF_RET_K, RET_KILL_PROCESS),
    ]

    for nr in sorted(DENY.values()):
        prog += [
            jump(BPF_JEQ_K, nr, 0, 1),
            stmt(BPF_RET_K, RET_EPERM),
        ]

    # clone3's flags live in a struct BPF can't reach; ENOSYS makes libc
    # retry with clone, which the next block can inspect.
    prog += [
        jump(BPF_JEQ_K, 435, 0, 1),
        stmt(BPF_RET_K, RET_ENOSYS),
    ]

    # clone: refuse only if CLONE_NEWUSER is in the flags (arg0).
    prog += [
        jump(BPF_JEQ_K, NR_CLONE, 0, 4),
        stmt(BPF_LD_W_ABS, OFF_ARG0),
        jump(BPF_JSET_K, CLONE_NEWUSER, 0, 1),
        stmt(BPF_RET_K, RET_EPERM),
        stmt(BPF_LD_W_ABS, OFF_NR),
    ]

    # ioctl: refuse the two requests that inject input into a terminal.
    prog += [
        jump(BPF_JEQ_K, NR_IOCTL, 0, 5),
        stmt(BPF_LD_W_ABS, OFF_ARG1),
        jump(BPF_JEQ_K, TIOCSTI, 1, 0),
        jump(BPF_JEQ_K, TIOCLINUX, 0, 1),
        stmt(BPF_RET_K, RET_EPERM),
        stmt(BPF_LD_W_ABS, OFF_NR),
    ]

    prog.append(stmt(BPF_RET_K, RET_ALLOW))
    return b"".join(prog)


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: seccomp-gen.py OUTPUT_FILE")
    with open(sys.argv[1], "wb") as out:
        out.write(build())


if __name__ == "__main__":
    main()
