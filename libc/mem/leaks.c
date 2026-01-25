/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2021 Justine Alexandra Roberts Tunney                              │
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
#include "libc/cosmo.h"
#include "libc/cxxabi.h"
#include "libc/intrin/cxaatexit.h"
#include "libc/intrin/kprintf.h"
#include "libc/intrin/weaken.h"
#include "libc/mem/allocator.h"
#include "libc/mem/mem.h"
#include "libc/runtime/runtime.h"
#include "libc/thread/posixthread.internal.h"

#if !defined(COSMO_USE_MIMALLOC) || !COSMO_USE_MIMALLOC
/* dlmalloc leak detection using dlmalloc_inspect_all */
#include "third_party/dlmalloc/dlmalloc.h"

struct LeakInfo {
  long count;
  long bytes;
};

static void visitor(void *start, void *end, size_t used_bytes, void *arg) {
  struct LeakInfo *info = arg;
  if (!used_bytes)
    return;
  kprintf("error: leaked %'zu byte allocation at %p\n", used_bytes, start);
  info->bytes += used_bytes;
  info->count += 1;
}
#endif

/**
 * Performs simple memory leak detection.
 *
 * This is a zero overhead memory leak detector. To use it you just need
 * to call CheckForMemoryLeaks() at the end of main(). With dlmalloc, the
 * leak detector works by calling dlmalloc_inspect_all. With mimalloc,
 * this function calls mi_collect() but detailed leak reporting is not
 * available - use cosmo_leak_print() instead for that.
 *
 * For each malloc(), realloc(), etc. call where free() wasn't called it
 * will print an error to kprintf() (dlmalloc only). The atexit()
 * destructors are called beforehand, to ensure global allocations are
 * freed. This function has to be called from an orphaned thread. If any
 * leaks are detected (dlmalloc), the process will call exit() with the
 * exit code 73.
 *
 * Alternatively, cosmo provides a second memory leak detector which may
 * be accessed via APIs such as cosmo_leak_print(). The other API traces
 * provenance and uses addr2line to print backtraces. To see the example
 * usage, take a look at cosmopolitan/examples/memleak.c
 */
void CheckForMemoryLeaks(void) {

  // validate usage of this api
  if (_weaken(_pthread_decimate))
    _weaken(_pthread_decimate)(kPosixThreadZombie);
  if (!pthread_orphan_np())
    kprintf("warning: called CheckForMemoryLeaks() from non-orphaned thread\n");

  // call dynamic global destructors
  __cxa_thread_finalize();
  __cxa_finalize(0);

#if defined(COSMO_USE_MIMALLOC) && COSMO_USE_MIMALLOC
  // mimalloc: use mi_collect to reclaim memory, but detailed leak
  // detection via inspect_all is not available
  mi_collect(true);
  // Note: For detailed leak detection with mimalloc, use cosmo_leak_print()
  // which provides backtraces via addr2line
#else
  // dlmalloc: check for leaks using dlmalloc_inspect_all
  struct LeakInfo info = {0};
  dlmalloc_inspect_all(visitor, &info);
  if (info.count) {
    kprintf("       you forgot to call free %'ld time%s (%'ld bytes)\n",
            info.count, info.count == 1 ? "" : "s", info.bytes);
    _Exit(73);
  }
#endif
}
