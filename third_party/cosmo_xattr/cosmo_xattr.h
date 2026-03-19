#ifndef COSMOPOLITAN_THIRD_PARTY_COSMO_XATTR_H_
#define COSMOPOLITAN_THIRD_PARTY_COSMO_XATTR_H_
#include "libc/calls/calls.h"
/*
 * Cross-platform extended attribute API for Cosmopolitan fat binaries.
 *
 * Provides a unified interface over:
 *   - Linux xattr  (getxattr, setxattr, listxattr, etc.)
 *   - macOS xattr  (same names but different signatures — extra args)
 *   - Stub         (FreeBSD/OpenBSD/Windows — returns ENOTSUP)
 *
 * These wrappers normalise the Linux vs macOS signature differences
 * and use runtime OS detection to call the correct syscall.
 *
 * Origin: toybox 0.8.13 (BSD licence)
 */
COSMOPOLITAN_C_START_

ssize_t cosmo_xattr_get(const char *path, const char *name,
                         void *value, size_t size);
ssize_t cosmo_xattr_lget(const char *path, const char *name,
                          void *value, size_t size);
ssize_t cosmo_xattr_fget(int fd, const char *name,
                          void *value, size_t size);

ssize_t cosmo_xattr_list(const char *path, char *list, size_t size);
ssize_t cosmo_xattr_llist(const char *path, char *list, size_t size);
ssize_t cosmo_xattr_flist(int fd, char *list, size_t size);

ssize_t cosmo_xattr_set(const char *path, const char *name,
                          const void *value, size_t size, int flags);
ssize_t cosmo_xattr_lset(const char *path, const char *name,
                           const void *value, size_t size, int flags);
ssize_t cosmo_xattr_fset(int fd, const char *name,
                           const void *value, size_t size, int flags);

COSMOPOLITAN_C_END_
#endif /* COSMOPOLITAN_THIRD_PARTY_COSMO_XATTR_H_ */
