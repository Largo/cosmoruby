#ifndef COSMOPOLITAN_THIRD_PARTY_COSMO_XNOTIFY_H_
#define COSMOPOLITAN_THIRD_PARTY_COSMO_XNOTIFY_H_
/*
 * Cross-platform file notification API for Cosmopolitan fat binaries.
 *
 * Provides a unified interface over:
 *   - inotify (Linux)
 *   - kqueue  (macOS/FreeBSD/OpenBSD/NetBSD)
 *   - Stub    (Windows — returns error, no native bridging yet)
 *
 * Runtime OS detection selects the correct backend. Extracted from
 * toybox's lib/portability.{h,c} which had compile-time #ifdef
 * platform selection — adapted here for Cosmo's fat binary model.
 *
 * Origin: toybox 0.8.13 (BSD licence)
 */
COSMOPOLITAN_C_START_

struct cosmo_xnotify {
  char **paths;
  int max, *fds, count, kq;
};

/* Allocate a notification context for up to max watched paths. */
struct cosmo_xnotify *cosmo_xnotify_init(int max);

/* Add fd/path to the watch set. Returns 0 on success, -1 on error. */
int cosmo_xnotify_add(struct cosmo_xnotify *not, int fd, char *path);

/* Block until a watched file changes. Sets *path and returns the fd. */
int cosmo_xnotify_wait(struct cosmo_xnotify *not, char **path);

COSMOPOLITAN_C_END_
#endif /* COSMOPOLITAN_THIRD_PARTY_COSMO_XNOTIFY_H_ */
