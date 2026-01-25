#ifndef COSMOPOLITAN_LIBC_MEM_ALLOCATOR_H_
#define COSMOPOLITAN_LIBC_MEM_ALLOCATOR_H_
/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2024 Justine Alexandra Roberts Tunney                              │
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

/**
 * Allocator abstraction layer for Cosmopolitan.
 *
 * This header provides a unified interface for memory allocation that
 * allows switching between dlmalloc and mimalloc at compile time.
 *
 * Selection is controlled by:
 *   - COSMO_USE_MIMALLOC=1  : Force mimalloc (default for most modes)
 *   - COSMO_USE_DLMALLOC=1  : Force dlmalloc (default for tiny modes)
 *
 * The build system sets COSMO_USE_DLMALLOC=1 automatically for
 * MODE=tiny, MODE=tinylinux, and MODE=aarch64-tiny.
 */

#if defined(COSMO_USE_MIMALLOC) && COSMO_USE_MIMALLOC

/*
 * mimalloc allocator
 */
#include "third_party/mimalloc/mimalloc.h"

#define COSMO_MALLOC(n)                  mi_malloc(n)
#define COSMO_FREE(p)                    mi_free(p)
#define COSMO_CALLOC(n, sz)              mi_calloc(n, sz)
#define COSMO_REALLOC(p, n)              mi_realloc(p, n)
#define COSMO_MEMALIGN(align, n)         mi_malloc_aligned(n, align)
#define COSMO_USABLE_SIZE(p)             mi_usable_size(p)
#define COSMO_REALLOC_IN_PLACE(p, n)     mi_expand(p, n)
#define COSMO_MALLOC_TRIM(pad)           (mi_collect(false), 1)

#else /* Default: dlmalloc */

/*
 * dlmalloc allocator (default and fallback)
 */
#include "third_party/dlmalloc/dlmalloc.h"

#define COSMO_MALLOC(n)                  dlmalloc(n)
#define COSMO_FREE(p)                    dlfree(p)
#define COSMO_CALLOC(n, sz)              dlcalloc(n, sz)
#define COSMO_REALLOC(p, n)              dlrealloc(p, n)
#define COSMO_MEMALIGN(align, n)         dlmemalign(align, n)
#define COSMO_USABLE_SIZE(p)             dlmalloc_usable_size(p)
#define COSMO_REALLOC_IN_PLACE(p, n)     dlrealloc_in_place(p, n)
#define COSMO_MALLOC_TRIM(pad)           dlmalloc_trim(pad)

#endif /* COSMO_USE_MIMALLOC */

#endif /* COSMOPOLITAN_LIBC_MEM_ALLOCATOR_H_ */
