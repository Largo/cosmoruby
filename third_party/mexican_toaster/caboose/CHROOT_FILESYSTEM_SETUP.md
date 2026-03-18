# Chroot Filesystem Setup

This document explains how Mexican Toaster sets up the filesystem inside the chroot
jail, including the APE loader, device access, and system information directories.

## Overview

When you run `caboose toast`, the program:

1. Creates a user namespace (you become root inside)
2. Creates a mount namespace (isolated mount points)
3. Sets up an overlayfs at `/piz` (or `/tmp/piz-mount-*`)
4. Copies necessary files into the overlay
5. Bind-mounts essential directories
6. Chroots into the overlay
7. Starts the interactive shell

## The Problem: Empty Chroot

A chroot jail is isolated from the host filesystem. By default, it has **nothing**:
- No `/proc` - process information
- No `/dev` - device files (random, null, tty)
- No `/sys` - kernel and hardware information
- No APE loader - can't execute APE binaries

Without these, even simple commands fail with confusing errors.

## The Fixes

### 1. APE Loader

#### The Problem

APE (Actually Portable Executable) binaries need an interpreter to run. When the
kernel sees an APE binary, it executes `/usr/bin/ape` with the binary as an argument.

**Without the loader:**
```
toast$ /bin/lsdir
/bin/lsdir: No such file or directory
```

This error is **misleading**! The file exists, but the APE loader (`/usr/bin/ape`)
doesn't exist inside the chroot.

#### The Solution

Copy the host's APE loader into the chroot:

```c
// Before chroot, copy /usr/bin/ape into the overlay
CopyFile("/usr/bin/ape", "/tmp/piz-lower-XXXX/usr/bin/ape");
chmod("/tmp/piz-lower-XXXX/usr/bin/ape", 0755);
```

Also register the APE format with binfmt_misc:

```c
// Register APE magic bytes with kernel
write(binfmt_register_fd, ":APE:M::MZqFpD::/usr/bin/ape:");
```

This tells the kernel: "If a file starts with `MZqFpD`, run it through `/usr/bin/ape`"

#### Verification

```
🔍 POST-CHROOT: /usr/bin/ape exists (APE binaries should work)
```

### 2. Device Access (/dev)

#### The Problem

The mimalloc memory allocator (used by APE binaries) needs cryptographically secure
randomness for security features:

1. Tries `getrandom()` syscall
2. Falls back to `/dev/urandom`

**Without device access:**
```
mimalloc: warning: unable to use secure randomness
```

While the binary still works, this weakens security (memory layout randomization).

#### The Solution

Bind-mount the host's `/dev` directory into the chroot:

```c
mkdir("/tmp/piz-mount-XXXX/dev", 0755);
mount("/dev", "/tmp/piz-mount-XXXX/dev", NULL, MS_BIND | MS_REC, NULL);
```

This provides access to:
- `/dev/urandom` - secure randomness
- `/dev/null` - discard output
- `/dev/zero` - zero bytes
- `/dev/tty` - terminal access
- `/dev/full` - always-full device (for testing)

#### Verification

```
✅ /dev available (urandom, null, zero, etc.)
```

And no more mimalloc warning!

### 3. System Info (/sys)

#### The Problem

Some programs expect `/sys` to exist:
- Hardware detection tools
- Network interface enumeration (`/sys/class/net`)
- Power management tools
- Some libraries probe `/sys` for capabilities

**Without /sys:** Programs may fail or behave unexpectedly.

#### The Solution

Bind-mount the host's `/sys` directory:

```c
mkdir("/tmp/piz-mount-XXXX/sys", 0755);
mount("/sys", "/tmp/piz-mount-XXXX/sys", NULL, MS_BIND | MS_REC, NULL);
```

Note: This is marked as optional. If the mount fails, the toaster continues.

#### Verification

```
✅ /sys available
```

### 4. Process Info (/proc)

#### Already Present

`/proc` was already being bind-mounted before these fixes. It's essential for:
- Process information (`/proc/self`, `/proc/$$`)
- binfmt_misc registration (`/proc/sys/fs/binfmt_misc`)
- Memory maps, file descriptors, etc.

## Directory Structure After Setup

```
/piz (chroot root)
├── bin/           # APE binaries from /zip
│   ├── mtsh
│   ├── lsdir
│   ├── zipcopy
│   └── fasterzip
├── usr/
│   └── bin/
│       └── ape    # APE loader (copied from host)
├── dev/           # Bind-mounted from host
│   ├── urandom
│   ├── null
│   ├── zero
│   └── tty
├── sys/           # Bind-mounted from host
│   ├── class/
│   ├── devices/
│   └── kernel/
├── proc/          # Bind-mounted from host
│   ├── self/
│   └── sys/fs/binfmt_misc/  # APE registration
├── app/           # Application data from /zip
└── usr/share/     # SSL certs, zoneinfo, etc.
```

## Why Not Copy Everything?

You might wonder: why bind-mount instead of copying?

| Method | Pros | Cons |
|--------|------|------|
| **Copy** | Completely isolated | Slower, uses more memory, stale data |
| **Bind-mount** | Fast, dynamic, efficient | Shares state with host |

For `/dev`, `/proc`, `/sys`: We need dynamic access to kernel-provided information.
Copying would give us stale snapshots.

For `/usr/bin/ape`: This is a small static binary (~9KB). Copying is fine and ensures
it's always available even if the host uninstalls it.

## Summary Table

| Path | Source | Method | Critical | Purpose |
|------|--------|--------|----------|---------|
| `/bin/*` | `/zip/bin` | Copy to lower layer | Yes | APE binaries |
| `/usr/bin/ape` | Host `/usr/bin/ape` | Copy | Yes | APE loader/interpreter |
| `/dev` | Host `/dev` | Bind-mount | Yes | Devices (urandom, null, tty) |
| `/proc` | Host `/proc` | Bind-mount | Yes | Process info, binfmt_misc |
| `/sys` | Host `/sys` | Bind-mount | No | Hardware/kernel info |

## References

- [APE Format Documentation](https://justine.lol/ape.html)
- [binfmt_misc Kernel Doc](https://www.kernel.org/doc/html/latest/admin-guide/binfmt-misc.html)
- [Linux Device Files](https://www.kernel.org/doc/html/latest/admin-guide/devices.html)
- [sysfs Documentation](https://www.kernel.org/doc/html/latest/filesystems/sysfs.html)
