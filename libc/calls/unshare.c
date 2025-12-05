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
#include "libc/calls/calls.h"
#include "libc/calls/syscall-sysv.internal.h"
#include "libc/intrin/strace.h"

/**
 * Disassociates parts of process execution context.
 *
 * This system call allows a process (or thread) to disassociate parts of its
 * execution context that are currently being shared with other processes (or
 * threads). This is commonly used to create namespaces for containerization.
 *
 * The flags parameter controls which parts of the execution context should be
 * unshared:
 *
 * - `CLONE_NEWNS`: Unshare mount namespace
 * - `CLONE_NEWUTS`: Unshare UTS namespace (hostname, etc.)
 * - `CLONE_NEWIPC`: Unshare IPC namespace
 * - `CLONE_NEWUSER`: Unshare user namespace
 * - `CLONE_NEWPID`: Unshare PID namespace
 * - `CLONE_NEWNET`: Unshare network namespace
 * - `CLONE_NEWCGROUP`: Unshare cgroup namespace
 * - `CLONE_FILES`: Unshare file descriptor table
 * - `CLONE_FS`: Unshare filesystem information
 * - `CLONE_SYSVSEM`: Unshare System V semaphore adjustment values
 * - `CLONE_VM`: Unshare virtual memory
 *
 * @param flags specifies which parts of the execution context to unshare
 * @return 0 on success, or -1 with errno set on error
 * @raise EINVAL if invalid flags specified
 * @raise ENOMEM if insufficient memory
 * @raise ENOSPC if maximum nesting depth for namespace exceeded
 * @raise EPERM if lacking necessary privileges
 * @raise EUSERS if maximum number of user namespaces exceeded
 * @raise ENOSYS on non-Linux systems
 */
int unshare(int flags) {
  int rc;
  rc = sys_unshare(flags);
  STRACE("unshare(%#x) → %d% m", flags, rc);
  return rc;
}
