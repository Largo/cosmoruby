/*
 * Cross-platform file notification for Cosmopolitan fat binaries.
 *
 * Runtime OS detection selects the correct backend:
 *   - inotify                (Linux)
 *   - kqueue                 (macOS/FreeBSD/OpenBSD/NetBSD)
 *   - ReadDirectoryChangesW  (Windows)
 *
 * All backends compiled into every binary — one is selected at runtime.
 * Extracted from toybox 0.8.13 portability.c and extended with a
 * Windows backend based on the ReadDirectoryChangesW pattern used by
 * facebook/watchman (Apache 2.0).
 *
 * Copyright 2012 Rob Landley <rob@landley.net>
 * Copyright 2012 Georgi Chorbadzhiyski <gf@unixsol.org>
 * Adapted for Cosmopolitan by the CosmoRuby project, 2026.
 */

#include "libc/dce.h"
#include "libc/calls/calls.h"
#include "libc/sysv/consts/nr.h"
#include "third_party/cosmo_xnotify/cosmo_xnotify.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

/* ═══════════════════════════════════════════════════════════════════════
 * inotify backend (Linux)
 * ═══════════════════════════════════════════════════════════════════════ */

struct cosmo_inotify_event {
  int wd;
  unsigned mask;
  unsigned cookie;
  unsigned len;
};

#define COSMO_IN_MODIFY    2
#define COSMO_IN_CLOEXEC   0x80000  /* IN_CLOEXEC for inotify_init1 */

extern const int __NR_inotify_init1;
extern const int __NR_inotify_add_watch;

static struct cosmo_xnotify *xnotify_init_inotify(int max)
{
  struct cosmo_xnotify *ctx;
  int fd;

  /* Use inotify_init1 (not inotify_init) — init1 has an ARM Linux
   * syscall number (26), init does not. Pass IN_CLOEXEC for safety. */
  fd = syscall(__NR_inotify_init1, COSMO_IN_CLOEXEC);
  if (fd < 0) return NULL;

  ctx = calloc(1, sizeof(*ctx));
  if (!ctx) { close(fd); return NULL; }
  ctx->max = max;
  ctx->kq = fd;
  ctx->paths = calloc(max, sizeof(char *));
  ctx->fds = calloc(max * 2, sizeof(int));
  if (!ctx->paths || !ctx->fds) goto fail;
  return ctx;

fail:
  free(ctx->paths);
  free(ctx->fds);
  free(ctx);
  close(fd);
  return NULL;
}

static int xnotify_add_inotify(struct cosmo_xnotify *ctx, int fd, char *path)
{
  int i = 2 * ctx->count;

  if (ctx->count == ctx->max) { errno = ENOMEM; return -1; }
  ctx->fds[i] = syscall(__NR_inotify_add_watch, ctx->kq, path,
                         COSMO_IN_MODIFY);
  if (ctx->fds[i] == -1) return -1;
  ctx->fds[i + 1] = fd;
  ctx->paths[ctx->count++] = path;
  return 0;
}

static int xnotify_wait_inotify(struct cosmo_xnotify *ctx, char **path)
{
  struct cosmo_inotify_event ev;
  int i;

  for (;;) {
    if ((int)sizeof(ev) != read(ctx->kq, &ev, sizeof(ev))) {
      if (errno == EINTR) continue;
      return -1;
    }
    for (i = 0; i < ctx->count; i++) {
      if (ev.wd == ctx->fds[2 * i]) {
        *path = ctx->paths[i];
        return ctx->fds[2 * i + 1];
      }
    }
  }
}

/* ═══════════════════════════════════════════════════════════════════════
 * kqueue backend (macOS, FreeBSD, OpenBSD, NetBSD)
 * ═══════════════════════════════════════════════════════════════════════ */

/*
 * Note on macOS: kqueue works for per-file watching which is what this
 * API provides. FSEvents (FSEventStreamCreate etc.) is better for
 * recursive directory tree watching but requires CoreServices framework
 * and a CFRunLoop — overkill for this simple API and not available in
 * Cosmo. If a higher-level directory-tree watcher is needed in future,
 * FSEvents should be a separate library.
 */

struct cosmo_kevent {
  unsigned long ident;
  short filter;
  unsigned short flags;
  unsigned fflags;
  long data;
  void *udata;
};

#define COSMO_EVFILT_VNODE (-4)
#define COSMO_EV_ADD       0x0001
#define COSMO_EV_CLEAR     0x0020
#define COSMO_EV_ERROR     0x4000
#define COSMO_NOTE_WRITE   0x0002

/* Raw syscall stubs from libc/sysv/calls/ — globl symbols with per-OS
 * dispatch baked into the assembly. */
extern long sys_kqueue(void);
extern long sys_kevent(int kq, const void *changelist, int nchanges,
                       void *eventlist, int nevents,
                       const struct timespec *timeout);

static struct cosmo_xnotify *xnotify_init_kqueue(int max)
{
  struct cosmo_xnotify *ctx;
  int fd;

  fd = sys_kqueue();
  if (fd < 0) return NULL;

  ctx = calloc(1, sizeof(*ctx));
  if (!ctx) { close(fd); return NULL; }
  ctx->max = max;
  ctx->kq = fd;
  ctx->paths = calloc(max, sizeof(char *));
  ctx->fds = calloc(max, sizeof(int));
  if (!ctx->paths || !ctx->fds) goto fail;
  return ctx;

fail:
  free(ctx->paths);
  free(ctx->fds);
  free(ctx);
  close(fd);
  return NULL;
}

static int xnotify_add_kqueue(struct cosmo_xnotify *ctx, int fd, char *path)
{
  struct cosmo_kevent event;

  if (ctx->count == ctx->max) { errno = ENOMEM; return -1; }

  memset(&event, 0, sizeof(event));
  event.ident = fd;
  event.filter = COSMO_EVFILT_VNODE;
  event.flags = COSMO_EV_ADD | COSMO_EV_CLEAR;
  event.fflags = COSMO_NOTE_WRITE;

  if (sys_kevent(ctx->kq, &event, 1, NULL, 0, NULL) == -1)
    return -1;

  ctx->paths[ctx->count] = path;
  ctx->fds[ctx->count++] = fd;
  return 0;
}

static int xnotify_wait_kqueue(struct cosmo_xnotify *ctx, char **path)
{
  struct cosmo_kevent event;
  int i;

  for (;;) {
    if (sys_kevent(ctx->kq, NULL, 0, &event, 1, NULL) < 1) {
      if (errno == EINTR) continue;
      return -1;
    }
    for (i = 0; i < ctx->count; i++) {
      if ((unsigned long)ctx->fds[i] == event.ident) {
        *path = ctx->paths[i];
        return event.ident;
      }
    }
  }
}

/* ═══════════════════════════════════════════════════════════════════════
 * Windows backend (ReadDirectoryChangesW)
 * ═══════════════════════════════════════════════════════════════════════
 *
 * ReadDirectoryChangesW watches directories, not individual files.
 * To match the xnotify per-file API: we watch each file's parent
 * directory and filter results for the target filename.
 *
 * Cosmo doesn't have a ReadDirectoryChangesW import stub, so we
 * load it dynamically via GetProcAddress at runtime.
 */

/* NT types — minimal definitions for our use. */
typedef void *cosmo_nt_handle;
typedef unsigned long cosmo_nt_dword;
typedef int cosmo_nt_bool;
typedef unsigned short cosmo_nt_wchar;

#define COSMO_NT_INVALID_HANDLE ((cosmo_nt_handle)(long)-1)

/* FILE_NOTIFY_INFORMATION structure */
struct cosmo_nt_file_notify_info {
  cosmo_nt_dword next_offset;
  cosmo_nt_dword action;
  cosmo_nt_dword name_length;   /* in bytes, not chars */
  cosmo_nt_wchar name[1];       /* variable length */
};

/* FILE_NOTIFY_CHANGE flags */
#define COSMO_FILE_NOTIFY_CHANGE_LAST_WRITE 0x00000010
#define COSMO_FILE_NOTIFY_CHANGE_FILE_NAME  0x00000001
#define COSMO_FILE_NOTIFY_CHANGE_SIZE       0x00000008

/* CreateFileW flags */
#define COSMO_FILE_LIST_DIRECTORY          0x00000001
#define COSMO_FILE_SHARE_RW_DELETE         0x00000007
#define COSMO_OPEN_EXISTING                3
#define COSMO_FILE_FLAG_BACKUP_SEMANTICS   0x02000000

/* NT functions accessed via _weaken() to avoid LIBC_NT package dependency.
 * These resolve at link time if any other part of the binary links LIBC_NT
 * (which any Windows-supporting Cosmo binary does). */
#include "libc/intrin/weaken.h"

/* Declare with correct signatures for _weaken(). */
cosmo_nt_handle CreateFileW(const cosmo_nt_wchar *, cosmo_nt_dword,
                            cosmo_nt_dword, void *, cosmo_nt_dword,
                            cosmo_nt_dword, cosmo_nt_handle);
cosmo_nt_handle LoadLibraryW(const cosmo_nt_wchar *);
void *GetProcAddress(cosmo_nt_handle, const char *);

/* ReadDirectoryChangesW — loaded dynamically via GetProcAddress. */
typedef cosmo_nt_bool (*rdcw_fn)(cosmo_nt_handle, void *, cosmo_nt_dword,
                                 cosmo_nt_bool, cosmo_nt_dword,
                                 cosmo_nt_dword *, void *, void *);

static rdcw_fn get_ReadDirectoryChangesW(void)
{
  static rdcw_fn cached;
  static int tried;
  cosmo_nt_handle lib;
  static const cosmo_nt_wchar klib[] = {'k','e','r','n','e','l','3','2',
                                         '.','d','l','l',0};
  if (tried) return cached;
  tried = 1;
  if (!_weaken(LoadLibraryW)) return NULL;
  lib = _weaken(LoadLibraryW)(klib);
  if (!lib) return NULL;
  cached = (rdcw_fn)_weaken(GetProcAddress)(lib, "ReadDirectoryChangesW");
  return cached;
}

/* Per-watched-file state for the Windows backend. */
struct cosmo_win_watch {
  cosmo_nt_handle dir_handle;
  cosmo_nt_wchar target_name[256];  /* filename within directory */
  int target_name_len;               /* in wchars */
};

/* Convert UTF-8 path to wide string. Simple ASCII-only for now. */
static int utf8_to_wide(const char *src, cosmo_nt_wchar *dst, int dstmax)
{
  int i;
  for (i = 0; i < dstmax - 1 && src[i]; i++)
    dst[i] = (unsigned char)src[i];
  dst[i] = 0;
  return i;
}

/* Extract parent directory from a path (modifies buf). */
static void get_parent_dir(const char *path, cosmo_nt_wchar *dir,
                           cosmo_nt_wchar *name, int *namelen, int max)
{
  int len = utf8_to_wide(path, dir, max);
  int i = len;

  /* Find last separator. */
  while (i > 0 && dir[i - 1] != '/' && dir[i - 1] != '\\') i--;

  /* Copy filename part. */
  *namelen = len - i;
  memcpy(name, dir + i, (*namelen + 1) * sizeof(cosmo_nt_wchar));

  /* Truncate dir at separator (or use "." if no separator). */
  if (i > 0) {
    dir[i > 1 ? i - 1 : i] = 0;
  } else {
    dir[0] = '.';
    dir[1] = 0;
  }
}

/* Compare wide strings case-insensitively (ASCII range). */
static int wstr_casecmp(const cosmo_nt_wchar *a, int alen,
                        const cosmo_nt_wchar *b, int blen)
{
  int i;
  cosmo_nt_wchar ca, cb;

  if (alen != blen) return 1;
  for (i = 0; i < alen; i++) {
    ca = a[i]; cb = b[i];
    if (ca >= 'A' && ca <= 'Z') ca += 32;
    if (cb >= 'A' && cb <= 'Z') cb += 32;
    if (ca != cb) return 1;
  }
  return 0;
}

static struct cosmo_xnotify *xnotify_init_win(int max)
{
  struct cosmo_xnotify *ctx;

  if (!get_ReadDirectoryChangesW()) { errno = ENOSYS; return NULL; }

  ctx = calloc(1, sizeof(*ctx));
  if (!ctx) return NULL;
  ctx->max = max;
  ctx->paths = calloc(max, sizeof(char *));
  ctx->fds = calloc(max, sizeof(int));
  /* Stash per-file Windows state in a parallel array. We allocate it
   * as a single block pointed to by kq (cast to intptr). */
  {
    struct cosmo_win_watch *watches = calloc(max, sizeof(*watches));
    if (!watches || !ctx->paths || !ctx->fds) {
      free(watches);
      free(ctx->paths);
      free(ctx->fds);
      free(ctx);
      return NULL;
    }
    ctx->kq = (int)(long)watches; /* stash pointer as int — recovered in add/wait */
  }
  return ctx;
}

static int xnotify_add_win(struct cosmo_xnotify *ctx, int fd, char *path)
{
  struct cosmo_win_watch *watches = (void *)(long)ctx->kq;
  struct cosmo_win_watch *w;
  cosmo_nt_wchar dirw[1024];

  if (ctx->count == ctx->max) { errno = ENOMEM; return -1; }
  w = &watches[ctx->count];

  get_parent_dir(path, dirw, w->target_name, &w->target_name_len, 1024);

  if (!_weaken(CreateFileW)) { errno = ENOSYS; return -1; }
  w->dir_handle = _weaken(CreateFileW)(dirw,
                               COSMO_FILE_LIST_DIRECTORY,
                               COSMO_FILE_SHARE_RW_DELETE,
                               NULL,
                               COSMO_OPEN_EXISTING,
                               COSMO_FILE_FLAG_BACKUP_SEMANTICS,
                               NULL);
  if (w->dir_handle == COSMO_NT_INVALID_HANDLE) { errno = ENOENT; return -1; }

  ctx->paths[ctx->count] = path;
  ctx->fds[ctx->count++] = fd;
  return 0;
}

static int xnotify_wait_win(struct cosmo_xnotify *ctx, char **path)
{
  struct cosmo_win_watch *watches = (void *)(long)ctx->kq;
  rdcw_fn ReadDirChanges = get_ReadDirectoryChangesW();
  char buf[4096];
  cosmo_nt_dword bytes_returned;
  int i;

  /* Poll each watched directory. This is simple but O(n) per wait.
   * For a small number of watches (toybox's use case) this is fine.
   * A production version would use overlapped I/O + WaitForMultipleObjects. */
  for (;;) {
    for (i = 0; i < ctx->count; i++) {
      struct cosmo_win_watch *w = &watches[i];
      struct cosmo_nt_file_notify_info *info;

      if (!ReadDirChanges(w->dir_handle, buf, sizeof(buf), 0 /* not recursive */,
                          COSMO_FILE_NOTIFY_CHANGE_LAST_WRITE |
                          COSMO_FILE_NOTIFY_CHANGE_FILE_NAME |
                          COSMO_FILE_NOTIFY_CHANGE_SIZE,
                          &bytes_returned, NULL, NULL))
        continue;

      if (bytes_returned == 0) continue;

      /* Walk the linked list of FILE_NOTIFY_INFORMATION entries. */
      info = (struct cosmo_nt_file_notify_info *)buf;
      for (;;) {
        int nchars = info->name_length / sizeof(cosmo_nt_wchar);

        if (!wstr_casecmp(info->name, nchars,
                          w->target_name, w->target_name_len)) {
          *path = ctx->paths[i];
          return ctx->fds[i];
        }

        if (!info->next_offset) break;
        info = (void *)((char *)info + info->next_offset);
      }
    }
  }
}

/* ═══════════════════════════════════════════════════════════════════════
 * Public API — runtime OS dispatch
 * ═══════════════════════════════════════════════════════════════════════ */

struct cosmo_xnotify *cosmo_xnotify_init(int max)
{
  if (IsLinux())   return xnotify_init_inotify(max);
  if (IsBsd())     return xnotify_init_kqueue(max);
  if (IsWindows()) return xnotify_init_win(max);
  errno = ENOSYS;
  return NULL;
}

int cosmo_xnotify_add(struct cosmo_xnotify *ctx, int fd, char *path)
{
  if (IsLinux())   return xnotify_add_inotify(ctx, fd, path);
  if (IsBsd())     return xnotify_add_kqueue(ctx, fd, path);
  if (IsWindows()) return xnotify_add_win(ctx, fd, path);
  errno = ENOSYS;
  return -1;
}

int cosmo_xnotify_wait(struct cosmo_xnotify *ctx, char **path)
{
  if (IsLinux())   return xnotify_wait_inotify(ctx, path);
  if (IsBsd())     return xnotify_wait_kqueue(ctx, path);
  if (IsWindows()) return xnotify_wait_win(ctx, path);
  errno = ENOSYS;
  return -1;
}
