# Build System Fixes - 28 January 2026

## Summary

Fixed intermittent objcopy segfaults and related build issues affecting the Cosmopolitan build system, particularly for mtsh and Ruby targets.

## Issues Addressed

### 1. Intermittent GNU objcopy Segfaults

**Symptom:** `.cosmocc/3.9.2/bin/x86_64-linux-cosmo-objcopy` would randomly segfault when creating `.com` files from `.dbg` files.

**Investigation:**
- Checked system resources (memory, file descriptors, disk) - all healthy
- Installed APE binfmt_misc handler to eliminate shell bootstrap as a variable
- Segfaults persisted even after binfmt_misc installation
- Concluded it's a latent bug in GNU objcopy 2.42

**Solution:** Use Cosmopolitan's `objbincopy` instead of GNU objcopy.

### 2. objbincopy Build Failure (Stale Object Files)

**Symptom:** Building objbincopy failed with undefined references to `__dlrealloc` and `__dlfree`.

```
undefined reference to `__dlrealloc'
undefined reference to `__dlfree'
```

**Root Cause:** Object files in `o//libc/mem/` were compiled before the mimalloc integration and still referenced dlmalloc symbols. The BUILD.mk correctly sets `-DCOSMO_USE_MIMALLOC=1` but the objects were stale.

**Solution:**
```bash
rm -f o//libc/mem/*.o o//libc/mem/mem.a
make -j1 o//libc/mem/mem.a
```

### 3. objbincopy NULL Pointer Crash

**Symptom:** After building objbincopy, it segfaulted on most binaries.

**Root Cause:** `tool/build/objbincopy.c` unconditionally accessed `macho->loadcount` without checking if the `.macho` section exists. Most Cosmopolitan binaries don't have a `.macho` section (only `ape.elf` does).

**Fix:** Added NULL check in `tool/build/objbincopy.c:343-351`:

```c
if (macho) {
  loadcommand = (struct MachoLoadCommand *)(macho + 1);
  loadcount = macho->loadcount;
} else {
  loadcommand = 0;
  loadcount = 0;
}
```

### 4. "Text file busy" When Rebuilding mtsh

**Symptom:** After switching to objbincopy, rebuilding `mtsh.com` failed with "Text file busy" because mtsh is the shell used by the build system.

**Root Cause:** Writing directly to a running executable fails with ETXTBSY.

**Solution:** Write to temp file then use `mv` (atomic rename works on busy files):

```make
MAKE_OBJCOPY = $(OBJBINCOPY) -o $@.tmp $< && mv -f $@.tmp $@ && $(MAKE_ZIPCOPY)
```

## Files Changed

### `tool/build/objbincopy.c`
- Added NULL check for `.macho` section

### `build/bootstrap/objbincopy`
- New bootstrap binary (copy of fixed objbincopy)

### `local-includes.mk`
- Added objbincopy override for MAKE_OBJCOPY:

```make
# Use objbincopy instead of GNU objcopy (fixes intermittent segfaults)
# Write to temp file then mv to handle "Text file busy" on running executables
OBJBINCOPY = build/bootstrap/objbincopy
ifneq ($(ARCH), aarch64)
MAKE_OBJCOPY = $(OBJBINCOPY) -o $@.tmp $< && mv -f $@.tmp $@ && $(MAKE_ZIPCOPY)
endif
```

## Other Work

### APE binfmt_misc Installation

Installed the APE loader for faster, more reliable APE binary execution:

```bash
sudo ape/apeinstall.sh
```

This registers APE format with the kernel's binfmt_misc, eliminating the shell script bootstrap overhead (~400us faster per invocation).

### Ruby LSP Plugin (Claude Code)

Cherry-picked PR #106 from `anthropics/claude-plugins-official` to add Ruby LSP support to local Claude Code installation:

```bash
cd ~/.claude/plugins/marketplaces/claude-plugins-official
git fetch origin pull/106/head:ruby-lsp-pr
git cherry-pick ruby-lsp-pr
claude plugin install ruby-lsp@claude-plugins-official
```

## Ruby GC Fix for Cosmopolitan

### `third_party/ruby-wip-4.0.0/gc/default/default.c`

**Problem:** Ruby's GC heap page allocator has an mmap-based path that:
1. Allocates a large memory region
2. Uses `munmap` to trim unaligned portions to get page-aligned memory

This fails on Windows because `VirtualFree` requires freeing exact allocations - you cannot free partial regions of an allocation.

**Fix:** Added Cosmopolitan-specific case to disable the mmap path:

```c
#elif defined(__COSMOPOLITAN__)
/* Cosmopolitan: partial munmap doesn't work reliably on Windows with mimalloc.
 * The mmap path allocates a large region then munmaps the unaligned portions,
 * but Windows VirtualFree requires freeing exact allocations, not partial regions.
 * Use gc_aligned_malloc (posix_memalign) instead which works across all platforms.
 */
static const bool HEAP_PAGE_ALLOC_USE_MMAP = false;
```

This forces Ruby to use `gc_aligned_malloc` (which wraps `posix_memalign`) for heap page allocation, which works correctly on all Cosmopolitan-supported platforms.

## Ruby Allocator Info Feature (v1.2.0)

Added runtime allocator identification to CosmoRuby to help with debugging and benchmarking.

### Features Added

1. **Option A: Version string** - Shows `+MIMALLOC` or `+DLMALLOC` in `--version` output
2. **Option B: `--cosmo-info` flag** - Detailed Cosmopolitan build information
3. **Option D: `RUBY_COSMO_ALLOCATOR` constant** - Runtime-accessible allocator name

### Example Output

```
$ ruby-mi --version
ruby 4.0.0 (2025-12-31) +PRISM +MIMALLOC [x86_64-cosmo]

$ ruby-dl --version
ruby 4.0.0 (2025-12-31) +PRISM +DLMALLOC [x86_64-cosmo]

$ ruby-mi --cosmo-info
Cosmopolitan Ruby Build Information
====================================
Ruby version:    4.0.0
Platform:        x86_64-cosmo
Allocator:       mimalloc
...

$ ruby -e 'puts RUBY_COSMO_ALLOCATOR'
mimalloc
```

### Files Changed

- `third_party/ruby-wip-4.0.0/version.c` - Added allocator detection macros and `ruby_show_cosmo_info()`
- `third_party/ruby-wip-4.0.0/ruby.c` - Added `--cosmo-info` option parsing
- `third_party/ruby-wip-4.0.0/include/ruby/internal/interpreter.h` - Added function declaration
- `third_party/ruby/ruby.compile.mk` - Added `$(LIBC_MEM_ALLOCATOR_FLAGS)` to propagate allocator flag
- `bin/build_ruby.sh` - Added `version.o` cleanup when switching allocators

## Memory Allocator Benchmark Results

Benchmark: 1M `Class.new` allocations with GC after each 100K batch.

```
┌────────────┬────────────────┬───────┬────────────────┬───────┬─────────────────┬───────┬────────────────────┬───────┐
│ Iterations │  System Ruby   │       │    mimalloc    │       │    dlmalloc     │       │ dlmalloc (no rseq) │       │
├────────────┼────────────────┼───────┼────────────────┼───────┼─────────────────┼───────┼────────────────────┼───────┤
│            │ RSS (KB)       │ Time  │ RSS (KB)       │ Time  │ RSS (KB)        │ Time  │ RSS (KB)           │ Time  │
├────────────┼────────────────┼───────┼────────────────┼───────┼─────────────────┼───────┼────────────────────┼───────┤
│ Start      │ 16,152         │ -     │ 15,260         │ -     │ 12,276          │ -     │ 11,560             │ -     │
├────────────┼────────────────┼───────┼────────────────┼───────┼─────────────────┼───────┼────────────────────┼───────┤
│ 100K       │ 19,368 (1.20x) │ 1.4s  │ 24,284 (1.59x) │ 2.7s  │ 31,796 (2.59x)  │ 4.8s  │ 18,464 (1.60x)     │ 3.3s  │
├────────────┼────────────────┼───────┼────────────────┼───────┼─────────────────┼───────┼────────────────────┼───────┤
│ 200K       │ 19,576 (1.21x) │ 2.8s  │ 24,284 (1.59x) │ 5.3s  │ 51,028 (4.16x)  │ 9.6s  │ 18,464 (1.60x)     │ 6.6s  │
├────────────┼────────────────┼───────┼────────────────┼───────┼─────────────────┼───────┼────────────────────┼───────┤
│ 500K       │ 19,576 (1.21x) │ 7.1s  │ 24,284 (1.59x) │ 13.4s │ 75,968 (6.19x)  │ 24.4s │ 18,464 (1.60x)     │ 16.7s │
├────────────┼────────────────┼───────┼────────────────┼───────┼─────────────────┼───────┼────────────────────┼───────┤
│ 1M         │ 19,576 (1.21x) │ 14.3s │ 24,284 (1.59x) │ 26.8s │ 108,040 (8.80x) │ 49.8s │ 18,464 (1.60x)     │ 33.2s │
└────────────┴────────────────┴───────┴────────────────┴───────┴─────────────────┴───────┴────────────────────┴───────┘
```

### Summary

| Allocator | Final RSS | Growth | Time | Status |
|-----------|-----------|--------|------|--------|
| System Ruby (glibc) | 19,576 KB | **1.21x** | **14.3s** | Best overall |
| mimalloc | 24,284 KB | **1.59x** | 26.8s | Stable, recommended for CosmoRuby |
| dlmalloc (no rseq) | 18,464 KB | **1.60x** | 33.2s | Stable, slower |
| dlmalloc (default) | 108,040 KB | **8.80x** | 49.8s | Memory retention issue with RSEQ |

### Key Findings

1. **mimalloc is recommended** - Stable memory, fastest CosmoRuby option
2. **dlmalloc's RSEQ causes memory retention** - Pages not returned to OS; disable with `COSMOPOLITAN_M_RSEQ_MAX=0`
3. **Pure computation is fast** - CosmoRuby mimalloc matches system Ruby speed (0.48s vs 0.47s for 10M iterations)
4. **Allocation overhead** - The ~2x slowdown is entirely in malloc/GC path, not Ruby interpreter

## Key Learnings

1. **Stale object files** can cause confusing link errors after build system changes - always clean affected directories after modifying compile flags in BUILD.mk

2. **objbincopy vs objcopy:** Cosmopolitan's objbincopy is designed for APE binaries but had a bug with non-macOS-supporting binaries. Now fixed.

3. **Atomic rename:** You can replace a running executable using `mv` (rename syscall) because it atomically swaps the directory entry. The running process keeps its handle to the old inode.

4. **COMPILE wrapper:** The build system's COMPILE wrapper does sophisticated temp-file handling, but for simple tools like objbincopy, a shell-level temp+mv is simpler and works.

5. **Allocator selection propagation:** When adding compile-time flags that affect multiple packages, ensure all dependent packages receive the flag (e.g., `$(LIBC_MEM_ALLOCATOR_FLAGS)` must be added to Ruby's CFLAGS, not just libc/mem).
