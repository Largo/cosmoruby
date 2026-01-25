# mimalloc Integration for Cosmopolitan

This document describes the integration of mimalloc v3.2.7 as an alternative memory allocator for Cosmopolitan, replacing dlmalloc as the default for most build modes.

## Overview

mimalloc is a general-purpose allocator developed by Microsoft Research with excellent performance characteristics:
- Small footprint with no dependencies
- Free list sharding for good multi-threaded performance
- Secure mode with randomised allocation and guard pages
- First-class support for heaps and heap walking

The integration maintains dlmalloc as a fallback for tiny build modes where binary size is the priority.

## Architecture

### Allocator Selection

Selection is compile-time via preprocessor defines:

```
┌─────────────────────────────────────────────────────────────┐
│                    libc/mem/allocator.h                      │
├─────────────────────────────────────────────────────────────┤
│  #if COSMO_USE_MIMALLOC                                     │
│    COSMO_MALLOC(n)  →  mi_malloc(n)                         │
│    COSMO_FREE(p)    →  mi_free(p)                           │
│    ...                                                       │
│  #else                                                       │
│    COSMO_MALLOC(n)  →  dlmalloc(n)                          │
│    COSMO_FREE(p)    →  dlfree(p)                            │
│    ...                                                       │
│  #endif                                                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    libc/mem/*.c wrappers                     │
│  (malloc.c, free.c, realloc.c, calloc.c, memalign.c, etc.) │
├─────────────────────────────────────────────────────────────┤
│  Use COSMO_* macros for all allocator calls                 │
│  Debug modes (MODE_DBG, COSMO_MEM_DEBUG) add instrumentation│
└─────────────────────────────────────────────────────────────┘
```

### Build Mode Selection

| Build Mode | Allocator | Rationale |
|------------|-----------|-----------|
| (default)  | mimalloc  | Best performance |
| dbg        | mimalloc  | With MI_DEBUG=2, MI_SECURE=4 |
| opt        | mimalloc  | Best performance |
| rel        | mimalloc  | Best performance |
| tiny       | dlmalloc  | Smaller binary size |
| tinylinux  | dlmalloc  | Smaller binary size |
| aarch64-tiny | dlmalloc | Smaller binary size |
| sysv       | mimalloc  | Best performance |
| aarch64    | mimalloc  | Best performance |

### Function Mapping

| libc function | mimalloc | dlmalloc |
|---------------|----------|----------|
| `malloc()` | `mi_malloc()` | `dlmalloc()` |
| `free()` | `mi_free()` | `dlfree()` |
| `realloc()` | `mi_realloc()` | `dlrealloc()` |
| `calloc()` | `mi_calloc()` | `dlcalloc()` |
| `memalign()` | `mi_malloc_aligned()` | `dlmemalign()` |
| `malloc_usable_size()` | `mi_usable_size()` | `dlmalloc_usable_size()` |
| `realloc_in_place()` | `mi_expand()` | `dlrealloc_in_place()` |
| `malloc_trim()` | `mi_collect()` | `dlmalloc_trim()` |

## Files Created

### third_party/mimalloc/BUILD.mk

Build configuration for the mimalloc package:
- Defines `THIRD_PARTY_MIMALLOC` package
- Creates `o/$(MODE)/third_party/mimalloc/mimalloc.a`
- Compiles `src/static.c` (includes all mimalloc sources) and `cosmo_prim.c`
- Dependencies: `LIBC_CALLS`, `LIBC_INTRIN`, `LIBC_NEXGEN32E`, `LIBC_STR`, `LIBC_SYSV`, `LIBC_SYSV_CALLS`
- Note: `LIBC_THREAD` is intentionally NOT included to avoid circular dependency (LIBC_THREAD → LIBC_MEM → THIRD_PARTY_MIMALLOC). The pthread_key_* functions mimalloc needs are in LIBC_MEM.
- Uses `-O3` optimisation (except tiny modes)
- Debug mode adds `-DMI_DEBUG=2 -DMI_SECURE=4`

### third_party/mimalloc/README.cosmo

Provenance documentation:
- Source: https://github.com/microsoft/mimalloc
- Version: 3.2.7
- Licence: MIT
- Lists local modifications

### third_party/mimalloc/cosmo_config.h

Cosmopolitan-specific configuration defines:

```c
// Key settings:
#undef MI_MALLOC_OVERRIDE         // Don't override malloc/free symbols (must be undef, not 0)
#define MI_PRIM_HAS_PROCESS_ATTACH 1  // We handle process init ourselves
#define MI_PRIM_HAS_ALLOCATOR_INIT 1  // We handle allocator init ourselves
#define MI_TLS_MODEL_THREAD_LOCAL 1   // Use __thread for TLS
#define MI_TLS_RECURSE_GUARD 1    // Guard against TLS recursion
#define MI_NO_THP 1               // Disable transparent huge pages
```

**Notes**:
- `MI_MALLOC_OVERRIDE` must be undefined (not defined to 0) because mimalloc uses `#if defined(MI_MALLOC_OVERRIDE)`
- `MI_USE_PTHREADS` is NOT defined - we exclude `__COSMOPOLITAN__` in `atomic.h` to use atomic spinlocks instead

### third_party/mimalloc/cosmo_prim.c

Platform primitives implementation using Cosmopolitan APIs:

| Primitive | Implementation |
|-----------|----------------|
| `_mi_prim_mem_init()` | Uses `getpagesize()`, reads `/proc/meminfo` on Linux, sets virtual_address_bits=47 for x64 |
| `_mi_prim_free()` | `munmap()` |
| `_mi_prim_alloc()` | `mmap()` with alignment handling |
| `_mi_prim_commit()` | `mprotect(PROT_READ\|PROT_WRITE)` |
| `_mi_prim_decommit()` | `madvise(MADV_DONTNEED)` |
| `_mi_prim_reset()` | `madvise(MADV_FREE)` or `madvise(MADV_DONTNEED)` |
| `_mi_prim_protect()` | `mprotect()` |
| `_mi_prim_alloc_huge_os_pages()` | `mmap(MAP_HUGETLB\|MAP_HUGE_1GB)` on Linux |
| `_mi_prim_numa_node()` | Returns 0 (single NUMA node assumed) |
| `_mi_prim_clock_now()` | `clock_gettime(CLOCK_MONOTONIC)` |
| `_mi_prim_process_info()` | No-op (returns zeros to avoid LIBC_PROC dependency) |
| `_mi_prim_out_stderr()` | `write(2, msg, len)` (avoids LIBC_STDIO dependency) |
| `_mi_prim_getenv()` | Direct `environ` access |
| `_mi_prim_random_buf()` | `getrandom()` syscall or `/dev/urandom` |
| `_mi_prim_thread_*()` | No-op (avoids LIBC_MEM circular dependency) |

Process initialisation uses constructor priority 50:
```c
__attribute__((constructor(50)))
static void mi_cosmo_process_init(void) {
  _mi_auto_process_init();
}
```

**Note**: Locking uses mimalloc's atomic spinlock fallback (not pthread mutexes) because `__COSMOPOLITAN__` is excluded from the pthreads path in `atomic.h`.

### libc/mem/allocator.h

Allocator abstraction header providing unified `COSMO_*` macros:

```c
#if defined(COSMO_USE_MIMALLOC) && COSMO_USE_MIMALLOC

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

#include "third_party/dlmalloc/dlmalloc.h"

#define COSMO_MALLOC(n)                  dlmalloc(n)
#define COSMO_FREE(p)                    dlfree(p)
#define COSMO_CALLOC(n, sz)              dlcalloc(n, sz)
#define COSMO_REALLOC(p, n)              dlrealloc(p, n)
#define COSMO_MEMALIGN(align, n)         dlmemalign(align, n)
#define COSMO_USABLE_SIZE(p)             dlmalloc_usable_size(p)
#define COSMO_REALLOC_IN_PLACE(p, n)     dlrealloc_in_place(p, n)
#define COSMO_MALLOC_TRIM(pad)           dlmalloc_trim(pad)

#endif
```

## Files Modified

### Makefile (line 261)

Added mimalloc include after dlmalloc:

```makefile
include third_party/dlmalloc/BUILD.mk      #─┘
include third_party/mimalloc/BUILD.mk      #─┐ Memory allocators
include libc/mem/BUILD.mk                  # │
```

### libc/mem/BUILD.mk

Added conditional allocator selection:

```makefile
# Allocator selection based on build mode
ifeq ($(MODE),tiny)
COSMO_USE_DLMALLOC := 1
endif
ifeq ($(MODE),tinylinux)
COSMO_USE_DLMALLOC := 1
endif
ifeq ($(MODE),aarch64-tiny)
COSMO_USE_DLMALLOC := 1
endif

# Allow explicit override via environment or command line
ifdef COSMO_USE_DLMALLOC
LIBC_MEM_ALLOCATOR_DEP := THIRD_PARTY_DLMALLOC
LIBC_MEM_ALLOCATOR_FLAGS :=
else
LIBC_MEM_ALLOCATOR_DEP := THIRD_PARTY_MIMALLOC
LIBC_MEM_ALLOCATOR_FLAGS := -DCOSMO_USE_MIMALLOC=1
endif

LIBC_MEM_A_DIRECTDEPS = \
    ... \
    $(LIBC_MEM_ALLOCATOR_DEP)

# Pass allocator selection flag to C files
$(LIBC_MEM_A_OBJS): private CFLAGS += $(LIBC_MEM_ALLOCATOR_FLAGS)
```

### libc/mem/*.c Wrapper Files

All wrapper files were modified to:
1. Include `libc/mem/allocator.h` instead of `third_party/dlmalloc/dlmalloc.h`
2. Use `COSMO_*` macros instead of direct `dl*` function calls

| File | Changes |
|------|---------|
| `malloc.c` | `dlmalloc()` → `COSMO_MALLOC()`, `dlmalloc_usable_size()` → `COSMO_USABLE_SIZE()` |
| `free.c` | `dlfree()` → `COSMO_FREE()`, `dlmalloc_usable_size()` → `COSMO_USABLE_SIZE()` |
| `realloc.c` | `dlrealloc()` → `COSMO_REALLOC()`, `dlmalloc_usable_size()` → `COSMO_USABLE_SIZE()` |
| `calloc.c` | `dlcalloc()` → `COSMO_CALLOC()` |
| `memalign.c` | `dlmemalign()` → `COSMO_MEMALIGN()`, `dlmalloc_usable_size()` → `COSMO_USABLE_SIZE()` |
| `malloc_usable_size.c` | `dlmalloc_usable_size()` → `COSMO_USABLE_SIZE()` |
| `malloc_trim.c` | `dlmalloc_trim()` → `COSMO_MALLOC_TRIM()` |
| `realloc_in_place.c` | `dlrealloc_in_place()` → `COSMO_REALLOC_IN_PLACE()` |

### third_party/mimalloc/src/prim/prim.c

Added Cosmopolitan detection to prevent including `unix/prim.c` (since `cosmo_prim.c` provides the primitives):

```c
#if defined(__COSMOPOLITAN__)
// Cosmopolitan: primitives are provided by cosmo_prim.c
// which is compiled separately and linked in

#elif defined(_WIN32)
#include "windows/prim.c"
// ... rest unchanged
```

## Upstream Files Copied

The following files were copied from mimalloc v3.2.7:

```
third_party/mimalloc/
├── LICENSE                    # MIT licence
├── mimalloc.h                 # Public API header
├── mimalloc-new-delete.h      # C++ new/delete overrides (unused)
├── mimalloc-override.h        # Symbol override macros (unused)
├── mimalloc-stats.h           # Statistics structures
├── mimalloc/                  # Internal headers
│   ├── atomic.h
│   ├── bits.h
│   ├── internal.h
│   ├── prim.h
│   ├── track.h
│   └── types.h
└── src/                       # Source files
    ├── static.c               # Single-source build entry point
    ├── alloc.c
    ├── alloc-aligned.c
    ├── alloc-override.c
    ├── alloc-posix.c
    ├── arena.c
    ├── arena-meta.c
    ├── bitmap.c
    ├── bitmap.h
    ├── free.c
    ├── heap.c
    ├── init.c
    ├── libc.c
    ├── options.c
    ├── os.c
    ├── page.c
    ├── page-map.c
    ├── page-queue.c
    ├── random.c
    ├── stats.c
    ├── theap.c
    ├── threadlocal.c
    └── prim/
        ├── prim.c             # Modified for Cosmopolitan
        ├── unix/prim.c
        ├── windows/prim.c
        ├── osx/prim.c
        ├── wasi/prim.c
        └── emscripten/prim.c
```

## Build Instructions

### Default Build (uses mimalloc)

```bash
make -j8 o//test/libc/mem
```

### Force dlmalloc

```bash
make -j8 COSMO_USE_DLMALLOC=1 o//test/libc/mem
```

### Tiny Mode (automatically uses dlmalloc)

```bash
make -j8 MODE=tiny o//examples/hello
```

### Debug Mode (mimalloc with MI_DEBUG=2, MI_SECURE=4)

```bash
make -j8 MODE=dbg o//test/libc/mem
```

## Testing

### Run Memory Tests

```bash
# Build and run malloc tests
make -j8 o//test/libc/mem
o//test/libc/mem/malloc_test

# With mimalloc explicitly
make -j8 o//test/libc/mem/malloc_test
o//test/libc/mem/malloc_test

# With dlmalloc explicitly
make -j8 COSMO_USE_DLMALLOC=1 o//test/libc/mem/malloc_test
o//test/libc/mem/malloc_test
```

### Verify Allocator Selection

```bash
# Check which allocator is linked
nm o//test/libc/mem/malloc_test | grep -E "mi_malloc|dlmalloc"
```

## Potential Issues

### Binary Size

mimalloc may produce larger binaries than dlmalloc. This is mitigated by:
- Using dlmalloc automatically for `MODE=tiny`, `MODE=tinylinux`, `MODE=aarch64-tiny`
- Using `-fdata-sections -ffunction-sections` for dead code elimination

### SSE Register Usage

Unlike dlmalloc, mimalloc cannot use `-mgeneral-regs-only` because it returns structs (like `mi_memid_t`) that require SSE registers on the System V AMD64 ABI. This is handled in BUILD.mk by not applying that flag to mimalloc objects.

### rseq Optimisation

dlmalloc has Linux-specific restartable sequences (rseq) support for lockless small allocations. mimalloc uses different optimisations. Benchmark to verify performance meets requirements.

### Cross-Platform Compatibility

The `cosmo_prim.c` uses Cosmopolitan's portable APIs (`mmap`, `mprotect`, `madvise`, `pthread_*`) which should work across all supported platforms. Some features like huge pages are Linux-only.

### Circular Dependency Prevention

mimalloc does NOT depend on `LIBC_THREAD` to avoid a circular dependency:
```
LIBC_MEM → THIRD_PARTY_MIMALLOC → LIBC_THREAD → LIBC_MEM (cycle!)
```
The pthread_key_* functions that mimalloc needs for thread-local cleanup are actually in `LIBC_MEM`, not `LIBC_THREAD`, so this works correctly.

## Performance Results

### Memory Allocation Benchmark (Class.new cycles)

Tested with `third_party/ruby-wip-4.0.0/performance_regressions/memory_allocator_benchmark.rb`:

| Ruby Version | RSS Start | RSS End (1M iters) | Growth Factor |
|--------------|-----------|-------------------|---------------|
| System Ruby 4.0.0 (glibc) | 16,096 KB | 19,532 KB | **1.21x** |
| CosmoRuby + mimalloc | 9,928 KB | 15,416 KB | **1.55x** |
| CosmoRuby + dlmalloc (old) | ~16 MB | ~45 MB | **~2.85x** |

**Key findings:**
- mimalloc reduced RSS growth from ~2.85x to 1.55x (45% improvement)
- Memory usage plateaus and remains stable (no unbounded growth)
- Starting RSS is lower with CosmoRuby (9.9 MB vs 16 MB)

### Ruby Test Suite Results

With mimalloc, the previously failing memory leak tests now pass:

```
test_class.rb:  61 tests, 10433 assertions, 0 failures, 0 errors
test_module.rb: 195 tests, 1240 assertions, 0 failures, 0 errors
```

Tests run with `RUBY_TEST_TIMEOUT_SCALE=8` to allow sufficient time for memory-intensive tests.

## Simplifications Made

To avoid circular dependencies in Cosmopolitan's build system, the following simplifications were made in `cosmo_prim.c`:

| Feature | Implementation | Impact |
|---------|----------------|--------|
| Locking | Atomic spinlocks (not pthread mutex) | Low - mimalloc's own fallback mechanism |
| Thread cleanup | No-op (deferred to process exit) | Medium - memory reclaimed at exit, not per-thread |
| Process stats | Returns zeros | Low - only affects `mi_stats_print()` |
| `mi_realpath()` | Excluded | None - convenience function only |
| stderr output | Direct `write(2, ...)` | None - avoids LIBC_STDIO dependency |

These trade-offs were necessary because:
- `LIBC_THREAD` depends on `LIBC_MEM` (circular)
- `LIBC_PROC` depends on `LIBC_MEM` (circular)
- `LIBC_STDIO` depends on `LIBC_MEM` (circular)

## Upstream Modifications

Files modified from upstream mimalloc v3.2.7:

| File | Change |
|------|--------|
| `mimalloc/atomic.h` | Added `!defined(__COSMOPOLITAN__)` to pthread detection |
| `src/options.c` | Removed `#include <stdio.h>` and stdout/stderr comparison |
| `src/alloc.c` | Added `!defined(__COSMOPOLITAN__)` to realpath guard |

## Future Work

1. **Thread Cleanup**: Investigate using nsync for proper per-thread cleanup
2. **NUMA Support**: Add proper NUMA node detection for multi-socket systems
3. **Huge Pages**: Test and enable huge page support on more platforms
4. **Statistics**: Implement `_mi_prim_process_info()` using lower-level APIs
5. **Further Testing**: Run full Ruby test suite to validate stability
