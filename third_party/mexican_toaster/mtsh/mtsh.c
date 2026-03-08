/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2022 Justine Alexandra Roberts Tunney                              │
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
#include "libc/assert.h"
#include "libc/calls/calls.h"
#include "libc/calls/struct/dirent.h"
#include "libc/calls/struct/stat.h"
#include "libc/calls/struct/timespec.h"
#include "libc/cosmotime.h"
#include "libc/ctype.h"
#include "libc/dce.h"
#include "libc/errno.h"
#include "libc/fmt/conv.h"
#include "libc/fmt/itoa.h"
#include "libc/fmt/magnumstrs.internal.h"
#include "libc/intrin/getenv.h"
#include "libc/intrin/weaken.h"
#include "libc/limits.h"
#include "libc/macros.h"
#include "libc/runtime/runtime.h"
#include "libc/serialize.h"
#include "libc/stdio/stdio.h"
#include "libc/stdlib.h"
#include "libc/mem/mem.h"
#include "libc/str/str.h"
#include "libc/sysv/consts/lock.h"
#include "libc/sysv/consts/o.h"
#include "libc/sysv/consts/ok.h"
#include "libc/sysv/consts/s.h"
#include "libc/sysv/consts/sig.h"
#include "libc/sysv/consts/timer.h"
#include "libc/temp.h"
#include "third_party/awk/cmd.h"
#include "third_party/getopt/getopt.internal.h"
#include "third_party/linenoise/linenoise.h"
#include "third_party/mexican_toaster/mtsh/mtsh_version.h"
#include "third_party/musl/glob.h"
#include "third_party/sed/cmd.h"
#include "third_party/tr/cmd.h"
#include "tool/curl/cmd.h"

/**
 * @fileoverview Mexican Toaster Shell (mtsh) v0.2.0
 *
 * Enhanced command interpreter used by Mexican Toaster and the Ruby build.
 * Based on cocmd but with additional features:
 *   - Subshell execution with ( )
 *   - Command substitution with $( ) and backticks
 *   - 'command -v' for finding executables in PATH
 *   - ':' null command builtin
 *   - Enhanced comment handling
 *   - Line editing in interactive mode (linenoise)
 */

#define STATE_CMD        0
#define STATE_VAR        1
#define STATE_SINGLE     2
#define STATE_QUOTED     3
#define STATE_QUOTED_VAR 4
#define STATE_WHITESPACE 5

#define TOMBSTONE ((char *)-1)
#define READ24(s) READ32LE(s "\0")

static char *p;
static char *q;
static char *r;
static int vari;
static size_t n;
static char *cmd;
static char *assign;
static char var[32];
static int lastchild;
static int exitstatus;
static char *envs[500];
static char *args[3000];
static const char *prog;
static char argbuf[ARG_MAX];
static bool unsupported[256];

// File redirection management
struct Redirect {
  enum {
    REDIRECT_FILE,  // Regular file redirection (< > >>)
    REDIRECT_DUP    // File descriptor duplication (>&, <&)
  } type;
  int fd;           // Target fd to redirect
  int flags;        // open() flags for REDIRECT_FILE
  const char *path; // File path for REDIRECT_FILE
  int src_fd;       // Source fd for REDIRECT_DUP
};

static struct Redirect redirects[10];
static int num_redirects = 0;

enum MtshMode {
  kMtshModeVanilla = 0,
  kMtshModeToast = 1,
};

struct MtshConfig {
  enum MtshMode mode;
};

static struct MtshConfig g_mtsh_config = {kMtshModeVanilla};

// Signal names table (was removed from Cosmopolitan public API in Aug 2024)
// Now defined in ksignalnames.S
extern const struct MagnumStr kSignalNames[];

// Local implementation of touch() (testlib version not suitable for production)
static int touch(const char *file, uint32_t mode) {
  int rc, fd, olderr;
  olderr = errno;
  if ((rc = utimes(file, 0)) == -1 && errno == ENOENT) {
    errno = olderr;
    fd = open(file, O_CREAT | O_WRONLY, mode);
    if (fd == -1)
      return -1;
    return close(fd);
  }
  return rc;
}

static int ShellSpawn(void);
static int ShellExec(void);
static int _mtsh(int argc, char **argv, char **envp);

#include "util.inc"
#include "tokenize.inc"
#include "entry.inc"
