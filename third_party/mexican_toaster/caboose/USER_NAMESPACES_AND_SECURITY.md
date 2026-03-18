# User Namespaces, Overlayfs, and Security on Linux

This document explains the security layers that can interfere with Mexican Toaster's
operation and how to configure them correctly.

## Overview

Mexican Toaster uses two key Linux kernel features:

1. **User Namespaces** - Allow an unprivileged user to become "root" inside a container
2. **Overlayfs** - A layered filesystem that combines read-only and read-write layers

These features enable the toaster to create an isolated environment without requiring
actual root privileges on the host system.

## Required Kernel Configuration

### User Namespace Support

For unprivileged users to create user namespaces, the kernel must allow it:

```bash
# Check current setting
cat /proc/sys/kernel/unprivileged_userns_clone

# If it returns 0, you need to enable it
sudo sysctl kernel.unprivileged_userns_clone=1

# To make it permanent
echo "kernel.unprivileged_userns_clone=1" | sudo tee /etc/sysctl.d/99-userns.conf
```

**What this does:** Allows non-root users to create new user namespaces. Without this,
the `unshare(CLONE_NEWUSER)` syscall will fail with "Operation not permitted".

### Distribution Defaults

| Distribution | Default Value | Notes |
|--------------|---------------|-------|
| Ubuntu 20.04+ | 1 | Usually enabled |
| Debian 10+ | 1 | Usually enabled |
| Arch Linux | 1 | Enabled |
| Fedora | 1 | Enabled |
| RHEL/CentOS 7+ | 0 | May need to enable |

## Security Layers That Block Overlayfs

### 1. AppArmor (Ubuntu/Debian)

AppArmor is Mandatory Access Control (MAC) system that restricts what processes can do.

#### The Problem

When you create a user namespace with an overlayfs mount, AppArmor sees paths that are
"disconnected" from the host filesystem. It cannot resolve these paths through normal
means and blocks access with errors like:

```
apparmor="ALLOWED" operation="open" info="Failed name lookup - disconnected path"
error=-13 profile="unprivileged_userns"
```

#### Solution 1: Add attach_disconnected Flag (Recommended)

Edit the AppArmor profile to handle disconnected paths:

```bash
# Edit the profile
sudo vim /etc/apparmor.d/unprivileged_userns
```

Change:
```
profile unprivileged_userns flags=(complain) {
```

To:
```
profile unprivileged_userns flags=(complain,attach_disconnected) {
```

Reload the profile:
```bash
sudo apparmor_parser -r /etc/apparmor.d/unprivileged_userns
```

The `attach_disconnected` flag tells AppArmor: "I understand this process uses mount
namespaces. Allow access even when you can't resolve the full path."

#### Solution 2: Disable the Profile (Nuclear Option)

If the above doesn't work or you need to quickly test:

```bash
# Disable the profile
sudo ln -sf /etc/apparmor.d/unprivileged_userns /etc/apparmor.d/disable/
sudo apparmor_parser -R /etc/apparmor.d/unprivileged_userns

# Re-enable later
sudo rm /etc/apparmor.d/disable/unprivileged_userns
sudo apparmor_parser -r /etc/apparmor.d/unprivileged_userns
```

#### Checking AppArmor Status

```bash
# See loaded profiles
sudo aa-status

# Check kernel logs for AppArmor denials
sudo dmesg | grep apparmor

# Check if a specific profile is in enforce or complain mode
sudo aa-status | grep unprivileged_userns
```

### 2. SELinux (RHEL/CentOS/Fedora)

SELinux is another MAC system that can block user namespaces and overlayfs.

#### Check SELinux Status

```bash
# Check if SELinux is enabled
getenforce
# Returns: Enforcing, Permissive, or Disabled

# View SELinux denials
sudo ausearch -m avc -ts recent
```

#### Solutions

**Option 1: Set Permissive Mode (Temporary)**
```bash
sudo setenforce 0
```

**Option 2: Create SELinux Policy Module**
```bash
# Generate policy from denials
sudo ausearch -c 'caboose' --raw | audit2allow -M caboose_policy
sudo semodule -i caboose_policy.pp
```

**Option 3: Disable SELinux (Not Recommended)**
Edit `/etc/selinux/config` and set `SELINUX=disabled`, then reboot.

### 3. Seccomp BPF

Some container runtimes and security tools use seccomp to block syscalls.

#### Check for Seccomp

```bash
cat /proc/self/status | grep Seccomp
# Seccomp: 0 = disabled, 1 = strict, 2 = filter
```

If seccomp is blocking you, you may need to run with a less restrictive profile
or disable it for testing.

## User Namespaces vs Overlayfs

These are **different but related** technologies:

### User Namespaces

- **What:** Isolation of user and group IDs
- **How:** Maps your UID (e.g., 1000) to root (0) inside the namespace
- **Why:** Allows unprivileged "root" inside a container
- **Syscall:** `unshare(CLONE_NEWUSER)` or `clone(CLONE_NEWUSER)`

### Mount Namespaces

- **What:** Isolation of mount points
- **How:** Each namespace has its own view of the filesystem
- **Why:** Allows mounting/unmounting without affecting the host
- **Syscall:** `unshare(CLONE_NEWNS)` or part of `CLONE_NEWUSER`

### Overlayfs

- **What:** A union filesystem that layers directories
- **How:** Combines "lower" (read-only) and "upper" (read-write) directories
- **Why:** Allows modifications without changing the base layer
- **Mount:** `mount -t overlay overlay -o lowerdir=...,upperdir=...,workdir=...`

### How They Work Together in Caboose

1. **User namespace** - You become "root" (UID 0) inside
2. **Mount namespace** - Your mounts don't affect the host
3. **Overlayfs** - `/zip` contents are lower layer, `/tmp/piz-overlay/upper` is writable layer

```
┌─────────────────────────────────────────┐
│  Caboose Process (inside namespace)     │
│  - Sees itself as UID 0 (root)          │
│  - Can mount filesystems                │
│                                         │
│  /piz (overlay mount)                   │
│  ├── upper/ ←─ Your writes go here      │
│  └── lower/ ←─ /zip contents (read-only)│
└─────────────────────────────────────────┘
```

## Troubleshooting Checklist

### Step 1: Check User Namespace Support
```bash
unshare --user --pid --fork --mount-proc echo "Success"
```
If this fails, enable `kernel.unprivileged_userns_clone=1`.

### Step 2: Check AppArmor
```bash
sudo aa-status | grep unprivileged_userns
```
If it shows "enforce" or you see denials in `dmesg`, add `attach_disconnected`.

### Step 3: Check SELinux
```bash
getenforce
```
If "Enforcing", set to "Permissive" or create a policy.

### Step 4: Check Overlayfs Module
```bash
lsmod | grep overlay
# or
cat /proc/filesystems | grep overlay
```
If missing, load with `sudo modprobe overlay`.

## Hardening: Strict AppArmor Profile (Experimental)

The default `unprivileged_userns` profile has a very permissive rule:
```
allow file rwlkm /**,
```

This allows ALL file access. For better security, you can create a stricter profile
that only allows what caboose actually needs.

### Strict Profile

Create `/etc/apparmor.d/local/unprivileged_userns`:

```bash
# Capabilities needed for namespace and mount operations
capability sys_admin,
capability dac_override,
capability dac_read_search,
capability sys_chroot,
capability setuid,
capability setgid,

# Mount operations for overlayfs
mount fstype=tmpfs,
mount fstype=overlay,
mount options=(rw, rprivate),

# Device access (bind-mounted into chroot)
/dev/** rw,

# Proc access for binfmt_misc and process info
/proc/** rw,
owner @{PROC}/@{pid}/setgroups w,
owner @{PROC}/@{pid}/uid_map w,
owner @{PROC}/@{pid}/gid_map w,

# Sys access (read-only is sufficient)
/sys/** r,

# Host APE loader (needed before chroot)
/usr/bin/ape r,

# Temp directories used by caboose
/tmp/piz-*/** rwk,
owner /tmp/piz-*/** rwk,
/tmp/overlay-test*/** rwk,
owner /tmp/overlay-test*/** rwk,

# Deny access to sensitive areas
deny /etc/shadow r,
deny /root/** r,
deny /home/*/.ssh/** r,
```

### Testing the Strict Profile

**IMPORTANT:** Test thoroughly before using in production.

```bash
# 1. Backup current local profile
sudo cp /etc/apparmor.d/local/unprivileged_userns \
        /etc/apparmor.d/local/unprivileged_userns.bak

# 2. Install strict profile
sudo tee /etc/apparmor.d/local/unprivileged_userns << 'EOF'
[strict profile content from above]
EOF

# 3. Reload (still in complain mode to test)
sudo apparmor_parser -r /etc/apparmor.d/unprivileged_userns

# 4. Run caboose and watch for denials
sudo dmesg -w &  # Watch kernel logs in background
TOASTER_VERBOSE=1 o//third_party/mexican_toaster/caboose.com toast

# 5. Check what would be denied
sudo dmesg | grep apparmor | grep -v ALLOWED
```

### Switching to Enforce Mode

Only after testing confirms no legitimate denials:

```bash
# Edit main profile: change complain to enforce
sudo sed -i 's/flags=(complain/flags=(enforce/' \
    /etc/apparmor.d/unprivileged_userns

# Or set specific profile to enforce
sudo aa-enforce /etc/apparmor.d/unprivileged_userns

# Reload
sudo apparmor_parser -r /etc/apparmor.d/unprivileged_userns
```

### Rollback

If things break:

```bash
# Restore backup
sudo cp /etc/apparmor.d/local/unprivileged_userns.bak \
        /etc/apparmor.d/local/unprivileged_userns

# Revert to complain mode
sudo sed -i 's/flags=(enforce/flags=(complain/' \
    /etc/apparmor.d/unprivileged_userns

sudo apparmor_parser -r /etc/apparmor.d/unprivileged_userns
```

### Known Limitations

1. **Disconnected paths** - AppArmor sees paths like `piz-overlay-XXXX/upper/file`
   (without `/tmp/` prefix) inside mount namespaces. The rules may need adjustment.

2. **Dynamic paths** - Caboose uses PID-based paths (`/tmp/piz-lower-XXXX`).
   The glob patterns (`/tmp/piz-*/**`) should handle this, but wildcards can be
   tricky in AppArmor.

3. **Future features** - If caboose adds new capabilities (e.g., network access,
   different temp directories), the profile will need updates.

## Verification Test

To confirm `attach_disconnected` is required:

```bash
# Remove the flag
sudo sed -i 's/flags=(complain,attach_disconnected)/flags=(complain)/' \
    /etc/apparmor.d/unprivileged_userns
sudo apparmor_parser -r /etc/apparmor.d/unprivileged_userns

# Test (should fail with "Permission denied")
o//third_party/mexican_toaster/caboose.com toast

# Restore the flag
sudo sed -i 's/flags=(complain)/flags=(complain,attach_disconnected)/' \
    /etc/apparmor.d/unprivileged_userns
sudo apparmor_parser -r /etc/apparmor.d/unprivileged_userns
```

## References

- [Linux User Namespaces](https://man7.org/linux/man-pages/man7/user_namespaces.7.html)
- [Overlay Filesystem](https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html)
- [AppArmor Documentation](https://gitlab.com/apparmor/apparmor/-/wikis/Documentation)
- [AppArmor attach_disconnected](https://gitlab.com/apparmor/apparmor/-/wikis/AppArmorDisclaimers#attach_disconnected)
- [SELinux Documentation](https://selinuxproject.org/page/Main_Page)
