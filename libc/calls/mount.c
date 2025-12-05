/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2025 Justine Alexandra Roberts Tunney                              │
│                                                                              │
│ Permission to use, copy, modify, and/or distribute this software for         │
│ any purpose with or without fee is hereby granted, provided that the         │
│ above copyright notice and this permission notice appear in all copies.      │
│                                                                              │
│ THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL                │
│ WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED                │
│ WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE             │
│ AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL         │
│ DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR        │
│ PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER               │
│ TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR             │
│ PERFORMANCE OF THIS SOFTWARE.                                                │
╚─────────────────────────────────────────────────────────────────────────────*/
#include "libc/calls/mount.h"
#include "libc/calls/syscall-sysv.internal.h"
#include "libc/intrin/strace.h"

/**
 * Mounts filesystem.
 *
 * This system call is used to attach a filesystem to the directory tree.
 * On Linux, it can mount various filesystem types including overlay
 * filesystems for containerization.
 *
 * @param source is the device or filesystem source
 * @param target is the mount point directory path
 * @param filesystemtype is the filesystem type (e.g., "ext4", "overlay")
 * @param mountflags are flags like MS_RDONLY, MS_NOEXEC, etc.
 * @param data is filesystem-specific options string
 * @return 0 on success, or -1 w/ errno
 * @raise EACCES if permission denied
 * @raise EBUSY if target is busy
 * @raise EINVAL if invalid parameters
 * @raise ENODEV if filesystem type not configured in kernel
 * @raise ENOENT if target path doesn't exist
 * @raise ENOMEM if insufficient memory
 * @raise ENOTBLK if source is not a block device (when required)
 * @raise ENOTDIR if target is not a directory
 * @raise EPERM if caller lacks CAP_SYS_ADMIN capability
 */
int mount(const char *source, const char *target, const char *filesystemtype,
          unsigned long mountflags, const void *data) {
  int rc;
  rc = sys_mount(source, target, filesystemtype, mountflags, data);
  STRACE("mount(%#s, %#s, %#s, %#lx, %p) → %d% m", source, target,
         filesystemtype, mountflags, data, rc);
  return rc;
}
