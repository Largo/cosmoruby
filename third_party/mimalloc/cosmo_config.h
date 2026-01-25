/* -*- mode: c; indent-tabs-mode: nil; tab-width: 2; c-basic-offset: 2 -*- */
/* vi: set et ts=2 sw=2 fenc=utf-8 :vi */
/*
 * Cosmopolitan-specific configuration for mimalloc
 *
 * This file is included via -include flag before any mimalloc headers
 */
#ifndef COSMO_MIMALLOC_CONFIG_H
#define COSMO_MIMALLOC_CONFIG_H

/* ------------------------------------------------------------------------- */
/* Platform Detection                                                        */
/* ------------------------------------------------------------------------- */

/* Cosmopolitan is Unix-like with mmap support */
#ifndef __unix__
#define __unix__ 1
#endif

/* Tell mimalloc we have pthreads - but don't redefine if atomic.h will define it */
/* atomic.h defines MI_USE_PTHREADS when __unix__ is set, so we don't need to */

/* ------------------------------------------------------------------------- */
/* Feature Configuration                                                     */
/* ------------------------------------------------------------------------- */

/* Don't override standard malloc/free - we provide our own wrappers */
/* Note: must be undefined, not defined to 0, because code uses #if defined() */
#undef MI_MALLOC_OVERRIDE

/* Don't use the alloc-override.c dynamic symbol interposition */
#define MI_SKIP_COLLECT_ON_EXIT 1

/* We handle process init/done ourselves */
#define MI_PRIM_HAS_PROCESS_ATTACH 1

/* We handle allocator init ourselves */
#define MI_PRIM_HAS_ALLOCATOR_INIT 1

/* Enable statistics in debug mode */
#ifndef MI_STAT
#if MI_DEBUG > 0
#define MI_STAT 2
#else
#define MI_STAT 1
#endif
#endif

/* ------------------------------------------------------------------------- */
/* TLS Model Configuration                                                   */
/* ------------------------------------------------------------------------- */

/* Use regular thread local variables on Cosmopolitan */
#define MI_TLS_MODEL_THREAD_LOCAL 1

/* Don't use TLS slot access since Cosmopolitan has its own TLS layout */
#undef MI_HAS_TLS_SLOT

/* Guard against recursion during TLS init */
#define MI_TLS_RECURSE_GUARD 1

/* ------------------------------------------------------------------------- */
/* OS-specific Configuration                                                 */
/* ------------------------------------------------------------------------- */

/* Disable features that require Linux-specific interfaces */
#define MI_NO_THP 1  /* Disable transparent huge pages */

/* Use environ for environment variables */
#define MI_USE_ENVIRON 1

/* ------------------------------------------------------------------------- */
/* Debug Configuration                                                       */
/* ------------------------------------------------------------------------- */

/* MI_DEBUG and MI_SECURE are set via BUILD.mk CFLAGS for MODE=dbg */

/* Additional internal checks in debug builds */
#if MI_DEBUG > 0
#define MI_SHOW_ERRORS 1
#endif

/* ------------------------------------------------------------------------- */
/* Size Configuration                                                        */
/* ------------------------------------------------------------------------- */

/* Use standard arena sizes */
#ifndef MI_ARENA_BLOCK_SIZE
#define MI_ARENA_BLOCK_SIZE (64 * 1024)  /* 64 KiB */
#endif

/* Limit segment size for better cross-platform compatibility */
#ifndef MI_SEGMENT_SLICE_SIZE
#define MI_SEGMENT_SLICE_SIZE (64 * 1024)  /* 64 KiB */
#endif

/* ------------------------------------------------------------------------- */
/* Compatibility Macros                                                      */
/* ------------------------------------------------------------------------- */

/* Ensure we have standard includes available */
#include "libc/isystem/stddef.h"
#include "libc/isystem/stdint.h"
#include "libc/isystem/stdbool.h"

#endif /* COSMO_MIMALLOC_CONFIG_H */
