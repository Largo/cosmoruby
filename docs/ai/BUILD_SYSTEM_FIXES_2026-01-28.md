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

## Key Learnings

1. **Stale object files** can cause confusing link errors after build system changes - always clean affected directories after modifying compile flags in BUILD.mk

2. **objbincopy vs objcopy:** Cosmopolitan's objbincopy is designed for APE binaries but had a bug with non-macOS-supporting binaries. Now fixed.

3. **Atomic rename:** You can replace a running executable using `mv` (rename syscall) because it atomically swaps the directory entry. The running process keeps its handle to the old inode.

4. **COMPILE wrapper:** The build system's COMPILE wrapper does sophisticated temp-file handling, but for simple tools like objbincopy, a shell-level temp+mv is simpler and works.
