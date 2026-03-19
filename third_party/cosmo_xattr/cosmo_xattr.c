/*
 * Cross-platform extended attributes for Cosmopolitan fat binaries.
 *
 * Runtime OS detection handles the Linux/macOS signature difference:
 *   - Linux:  getxattr(path, name, value, size)         — 4 args
 *   - macOS:  getxattr(path, name, value, size, pos, opts) — 6 args
 *   - Others: returns -1 with errno ENOTSUP
 *
 * Both Linux and macOS xattr syscalls are registered in Cosmo's
 * syscalls.sh with per-OS numbers baked in. However, the ARGUMENT
 * COUNTS differ, so we must dispatch at runtime to pass the correct
 * number of args. macOS "lget" variants use the XATTR_NOFOLLOW
 * option flag on the regular getxattr call.
 *
 * Copyright 2012 Rob Landley <rob@landley.net>
 * Copyright 2012 Georgi Chorbadzhiyski <gf@unixsol.org>
 * Adapted for Cosmopolitan by the CosmoRuby project, 2026.
 */

#include "libc/dce.h"
#include "libc/calls/calls.h"
#include "third_party/cosmo_xattr/cosmo_xattr.h"

#include <errno.h>
#include <sys/syscall.h>
#include <unistd.h>

/* ── Syscall stubs ─────────────────────────────────────────────────── */

/* These are raw syscall stubs from libc/sysv/calls/ with per-OS
 * dispatch. Each encodes both the Linux AND macOS syscall numbers.
 * We call them with the correct argument count for the current OS. */

/* sys_getxattr etc. are globl symbols but not declared in any header.
 * On Linux these take 4 args; on macOS they take 6 (extra position
 * and options args). We declare them as taking the maximum (6) and
 * rely on the C calling convention ignoring extra args on Linux. */
extern long sys_getxattr(const char *, const char *, void *, size_t,
                         unsigned long, int);
extern long sys_fgetxattr(int, const char *, void *, size_t,
                          unsigned long, int);
extern long sys_lgetxattr(const char *, const char *, void *, size_t);
extern long sys_listxattr(const char *, char *, size_t, int);
extern long sys_flistxattr(int, char *, size_t, int);
extern long sys_llistxattr(const char *, char *, size_t);
extern long sys_setxattr(const char *, const char *, const void *, size_t,
                         unsigned long, int);
extern long sys_fsetxattr(int, const char *, const void *, size_t,
                          unsigned long, int);
extern long sys_lsetxattr(const char *, const char *, const void *, size_t,
                          int);

/* macOS XATTR_NOFOLLOW flag — used by l* variants on macOS. */
#define COSMO_XATTR_NOFOLLOW 0x0001

/* ── Unsupported platforms ─────────────────────────────────────────── */

static ssize_t xattr_enotsup(void)
{
  errno = ENOTSUP;
  return -1;
}

/* ── Public API — runtime dispatch ─────────────────────────────────── */

/*
 * For get/fget: Linux takes 4 args, macOS takes 6 (position + options).
 * We call the same sys_* stub but pass the extra args only for macOS.
 * On Linux the extra args are ignored by the kernel (only 4 are read
 * from registers). On macOS all 6 are used.
 *
 * For lget/llist/lset: macOS has no separate l* syscall. Instead, the
 * regular syscall takes an XATTR_NOFOLLOW option flag. These l*
 * variants only exist as Linux syscall stubs (macOS number is 0xfff).
 * So on macOS we call the non-l variant with the NOFOLLOW flag.
 */

ssize_t cosmo_xattr_get(const char *path, const char *name,
                         void *value, size_t size)
{
  if (IsLinux() || IsXnu())
    return sys_getxattr(path, name, value, size, 0, 0);
  return xattr_enotsup();
}

ssize_t cosmo_xattr_lget(const char *path, const char *name,
                          void *value, size_t size)
{
  if (IsLinux())
    return sys_lgetxattr(path, name, value, size);
  if (IsXnu())
    return sys_getxattr(path, name, value, size, 0, COSMO_XATTR_NOFOLLOW);
  return xattr_enotsup();
}

ssize_t cosmo_xattr_fget(int fd, const char *name,
                          void *value, size_t size)
{
  if (IsLinux() || IsXnu())
    return sys_fgetxattr(fd, name, value, size, 0, 0);
  return xattr_enotsup();
}

ssize_t cosmo_xattr_list(const char *path, char *list, size_t size)
{
  if (IsLinux() || IsXnu())
    return sys_listxattr(path, list, size, 0);
  return xattr_enotsup();
}

ssize_t cosmo_xattr_llist(const char *path, char *list, size_t size)
{
  if (IsLinux())
    return sys_llistxattr(path, list, size);
  if (IsXnu())
    return sys_listxattr(path, list, size, COSMO_XATTR_NOFOLLOW);
  return xattr_enotsup();
}

ssize_t cosmo_xattr_flist(int fd, char *list, size_t size)
{
  if (IsLinux() || IsXnu())
    return sys_flistxattr(fd, list, size, 0);
  return xattr_enotsup();
}

ssize_t cosmo_xattr_set(const char *path, const char *name,
                          const void *value, size_t size, int flags)
{
  if (IsLinux() || IsXnu())
    return sys_setxattr(path, name, value, size, 0, flags);
  return xattr_enotsup();
}

ssize_t cosmo_xattr_lset(const char *path, const char *name,
                           const void *value, size_t size, int flags)
{
  if (IsLinux())
    return sys_lsetxattr(path, name, value, size, flags);
  if (IsXnu())
    return sys_setxattr(path, name, value, size, 0,
                        flags | COSMO_XATTR_NOFOLLOW);
  return xattr_enotsup();
}

ssize_t cosmo_xattr_fset(int fd, const char *name,
                           const void *value, size_t size, int flags)
{
  if (IsLinux() || IsXnu())
    return sys_fsetxattr(fd, name, value, size, 0, flags);
  return xattr_enotsup();
}
