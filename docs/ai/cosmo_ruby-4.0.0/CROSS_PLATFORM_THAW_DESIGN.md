# Cross-Platform Thaw Design for Mexican Toaster

**Date:** 2026-03-07
**Authors:** Claude, with input from Kimi
**Reviewed by:** Kimi (see review notes inline)
**Status:** Research / design discussion -- no code changes yet
**Constraint:** The working Linux prototype MUST NOT be broken by any of this work.

---

## Problem Statement

The Mexican Toaster lifecycle (thaw -> modify -> persist) currently only works on Linux because `thaw` depends on:

- `unshare(CLONE_NEWUSER | CLONE_NEWNS)` -- Linux-only syscall
- `mount("overlay", ...)` -- Linux-only kernel filesystem
- `/proc/self/setgroups`, `/proc/self/uid_map`, `/proc/self/gid_map` -- Linux procfs

We want to run the full lifecycle on the GitHub CI matrix:

| Runner | OS | Arch | Status |
|--------|-----|------|--------|
| `ubuntu-latest` | Linux | x86_64 | Working |
| `ubuntu-24.04-arm` | Linux | aarch64 | Working |
| `macos-15-intel` | macOS | x86_64 | Thaw fails |
| `macos-latest` | macOS | aarch64 | Thaw fails |
| `windows-latest` | Windows | x86_64 | Thaw fails |
| `windows-11-arm` | Windows | aarch64 | Thaw fails |

`persist` should already be portable (copy, truncate, fasterzip, rename -- no kernel features).

---

## Current Architecture

```
caboose.c
  |-- overlay_backend.inc    enum { kOverlayKernel, kOverlayFuse, kOverlayUserland }
  |-- namespace_setup.inc    unshare() + /proc uid/gid mapping (Linux only)
  |-- piz_setup.inc          mount tmpfs, copy /zip/, mount overlayfs (Linux only)
  |-- thaw.inc               orchestrates the above
  |-- persist.inc             copy + truncate + merge + fasterzip + atomic rename
```

Key observation: `overlay_backend.inc` already defines `kOverlayUserland` as a variant,
but it's not implemented. The scaffolding is there.

---

## Approach #3: Userspace Overlay (Portable Fallback)

### Concept

Skip the kernel entirely. `thaw` just copies `/zip/` to a temp directory. The user
modifies files there directly. `persist` merges the temp directory back into the binary.

### What changes

**thaw.inc** gets a platform check:

```
if (Linux && user namespaces available)
    use existing kernel overlay path    (fast, transparent /zip/ illusion)
else
    use userspace overlay               (portable, explicit paths)
```

The userspace path is simple:

```
1. mkdtemp("/tmp/toaster-upper-XXXXXX")
2. CopyDirectoryRecursive("/zip", upper)     -- full copy of embedded content
3. Save upper path in state file
4. Print "Thawed. Writable layer at /tmp/toaster-upper-XXXXXX"
```

After thaw, the upper directory contains a complete copy of `/zip/`. The user
(or demo script) can read AND write files in the upper directory using ordinary
file I/O -- no special helpers needed. `persist` merges the upper directory back
into the binary via a single fasterzip pass.

### What does NOT change

- `persist.inc` -- already works with an explicit upper path
- `state_file.inc` -- already stores upper_path
- Demo scripts -- already use `$UPPER` paths explicitly

### Trade-offs

| | Kernel overlay (Linux) | Userspace overlay (portable) |
|---|---|---|
| Reads | Transparent via `/zip/` | From `$UPPER` (full copy at thaw time) |
| Writes | Transparent via `/zip/` | To `$UPPER` explicitly |
| Thaw cost | Mount setup (~0ms) | Full `/zip/` copy (fast for small payloads) |
| Performance | Kernel-speed file ops | Same (no overhead -- it's just a directory) |
| Dependencies | Linux kernel, user namespaces | None |
| Complexity | ~200 lines (namespace + mount) | ~30 lines (mkdtemp + copy + save state) |

### Impact on demo scripts

Zero. Both `demo_lifecycle.sh` and `demo_persist_word.sh` already work with explicit
paths to the upper layer directory. They never relied on the transparent `/zip/`
overlay illusion.

### Implementation plan

1. Add a `ThawUserland()` function in `thaw.inc` (or a new `thaw_userland.inc`)
   - `mkdtemp()` to create upper directory
   - `CopyDirectoryRecursive("/zip", upper)` to populate it
   - Save upper path in state file
2. `Thaw()` checks platform and namespace availability, dispatches accordingly
3. On Linux: try kernel overlay first, fall back to userland on failure
4. On macOS/Windows: go straight to userland
5. `persist` uses upper directory as sole staging input (no `/zip/` + upper merge needed)
6. Everything else stays the same

### Design decision: full copy at thaw time

The userspace thaw performs a full copy of `/zip/` into the upper directory at
thaw time. This matches what `piz_setup.inc` already does for the kernel overlay's
lower layer -- both paths start with a complete copy of the embedded content.

**Why full copy, not lazy or empty:**

- **Transparent reads**: Any code (Ruby's `File.open`, gem install, shell scripts)
  can read files from the upper directory without needing a special helper or
  falling back to `/zip/`. The upper directory IS the working tree.
- **No surprises**: An empty upper directory would silently break any code that
  reads existing `/zip/` content via ordinary file paths. This would surface as
  confusing "file not found" errors in user code that works fine on the Linux
  kernel overlay path.
- **Simplicity**: One `CopyDirectoryRecursive("/zip", upper)` call. No lazy-copy
  hooks, no helper functions, no fallback logic.
- **Consistency**: Both the kernel overlay and userspace overlay start from the
  same baseline -- a directory containing all of `/zip/`. The difference is just
  how that directory got populated (mount vs copy).

**Cost**: For a typical caboose binary, `/zip/` contains a handful of small files
(state, config, app scripts). The copy is fast. For larger payloads (e.g. a Ruby
stdlib), the copy takes longer, but correctness beats speed here -- and Approach #4
(zipos VFS hook) eliminates the copy entirely for the long-term case.

**Persist implication**: Since the upper directory contains ALL content (original +
modified), `persist` can use the upper directory directly as its staging input. No
need to merge `/zip/` + upper -- upper already has everything.

### Review feedback: Windows path separators

**Resolved.** Cosmopolitan handles this. `__get_tmpdir()` (`libc/calls/tmpdir.c:43-44`)
calls `GetTempPath()` on Windows, then `__mkunixpath()` to convert to forward-slash
Unix-style paths. So `mkdtemp()` with a template based on `__get_tmpdir()` returns a
Unix-style path on all platforms. Our `snprintf("%s/%s", upper, name)` concatenations
work correctly without any platform-specific path handling.

### Review feedback: testing without macOS/Windows

Add `TOASTER_BACKEND` environment variable to force a specific backend on any platform:

```bash
# Force userland overlay on Linux (for testing the portable path)
TOASTER_BACKEND=userland ./caboose.com thaw

# Force kernel overlay (default on Linux, fails on other platforms)
TOASTER_BACKEND=kernel ./caboose.com thaw

# Auto-detect (default)
TOASTER_BACKEND=auto ./caboose.com thaw
```

This uses the existing `ParseOverlayBackend()` function in `overlay_backend.inc` which
already parses these exact strings. The CI workflow can test the portable path on Linux
runners without needing macOS/Windows runners for basic validation.

### Review feedback: framing for upstream

If Approach #4 is proposed to Cosmopolitan upstream, frame it as:

> "Writable `/zip/` overlay for APE applications"

Not:

> "Mexican Toaster needs this"

The benefit to other apps is the selling point -- any APE application could use a
writable `/zip/` layer for configuration, plugins, caching, etc. Mexican Toaster
would be one consumer of a general-purpose feature.

---

## Approach #4: Cosmopolitan zipos VFS Hook (Long-Term)

### Concept

Extend Cosmopolitan's `/zip/` VFS layer to support an overlay directory. When a
global flag is set, all `/zip/` operations check the overlay directory first before
falling back to the embedded ZIP.

This would make `thaw` a single function call that sets a flag, and ALL `/zip/` reads
would transparently see the overlay content -- on every platform.

### Where it hooks in

The entry point is `__zipos_open()` in `libc/runtime/zipos-open.c:203`:

```c
int __zipos_open(struct ZiposUri *name, int flags) {
    // Currently rejects writes immediately:
    if ((flags & O_CREAT) || (flags & O_TRUNC) || ...)
        return erofs();

    // Then finds and loads from ZIP:
    struct Zipos *zipos = __zipos_get();
    ssize_t cf = __zipos_find(zipos, name);
    ...
}
```

A hook would intercept BEFORE this logic:

```c
// Hypothetical overlay hook
int __zipos_open(struct ZiposUri *name, int flags) {
    // NEW: check overlay directory first
    if (__zipos_overlay_path[0]) {
        char real[PATH_MAX];
        snprintf(real, sizeof(real), "%s/%s", __zipos_overlay_path, name->path);
        int fd = open(real, flags);
        if (fd >= 0 || errno != ENOENT)
            return fd;    // found in overlay (or real error)
        // fall through to ZIP lookup
    }

    // Existing logic unchanged...
    if ((flags & O_CREAT) || (flags & O_TRUNC) || ...)
        return erofs();
    ...
}
```

Similar hooks needed in:
- `zipos-stat.c` (`__zipos_stat`) -- stat checks overlay first
- `zipos-access.c` (`__zipos_access`) -- access checks overlay first
- `zipos-find.c` (`__zipos_find`) -- directory listing includes overlay entries

### Other affected zipos files

| File | Function | Hook needed? |
|------|----------|-------------|
| `zipos-open.c` | `__zipos_open` | Yes -- read/open redirect |
| `zipos-stat.c` | `__zipos_stat` | Yes -- stat redirect |
| `zipos-stat-impl.c` | `__zipos_stat_impl` | Maybe -- called by fstat |
| `zipos-access.c` | `__zipos_access` | Yes -- access redirect |
| `zipos-find.c` | `__zipos_find` | Yes -- directory listing merge |
| `zipos-fstat.c` | `__zipos_fstat` | No -- operates on open handle |
| `zipos-read.c` | `__zipos_read` | No -- operates on open handle |
| `zipos-seek.c` | `__zipos_seek` | No -- operates on open handle |
| `zipos-mmap.c` | `__zipos_mmap` | No -- operates on open handle |
| `zipos-close.c` | `__zipos_close` | No -- operates on open handle |
| `zipos-get.c` | `__zipos_get` | No -- ZIP singleton init |
| `zipos-normpath.c` | `__zipos_normpath` | No -- path normalisation |
| `zipos-parseuri.c` | `__zipos_parseuri` | No -- URI parsing |
| `zipos-inode.c` | `__zipos_inode` | No -- inode number generation |
| `zipos-notat.c` | `__zipos_notat` | Maybe -- AT_FDCWD handling |

### The global state

```c
// In a new file, or in zipos.internal.h
extern char __zipos_overlay_path[PATH_MAX];  // empty = disabled

// thaw sets it:
void __zipos_set_overlay(const char *path) {
    if (path)
        snprintf(__zipos_overlay_path, PATH_MAX, "%s", path);
    else
        __zipos_overlay_path[0] = '\0';
}
```

### Write support

The real power: with the overlay hook, writes to `/zip/` could be redirected to the
overlay directory instead of returning EROFS:

```c
if (__zipos_overlay_path[0] && (flags & (O_CREAT | O_TRUNC | O_WRONLY | O_RDWR))) {
    char real[PATH_MAX];
    snprintf(real, sizeof(real), "%s/%s", __zipos_overlay_path, name->path);
    // ensure parent directories exist
    mkdirp(dirname(real));
    return open(real, flags, 0644);
}
```

This would make `/zip/` truly writable after thaw -- transparently, on all platforms.

### Trade-offs

| | Approach #3 (Userspace) | Approach #4 (zipos hook) |
|---|---|---|
| Transparency | Explicit upper paths | Fully transparent `/zip/` |
| Write to `/zip/` | Not possible | Works (redirected to overlay) |
| Platforms | All | All |
| Cosmo core changes | None | Yes -- 4-6 files in libc/runtime/ |
| Benefits other apps | No | Yes -- any Cosmo app could use it |
| Risk | Low | Medium -- touching core VFS |
| Upstream approval | Not needed | **Required** (per CLAUDE.md) |

### Open questions for #4

1. **Thread safety**: `__zipos_overlay_path` should be `_Thread_local` or guarded by
   an atomic flag, not merely "set before any access". Kimi notes that a simple
   "set it early" approach is insufficient if any thread touches `/zip/` during init.

2. **Directory listing**: `__zipos_find` does a binary search of the central directory
   index. Merging overlay entries into directory listings requires scanning the overlay
   dir and deduplicating against ZIP entries. This is the most complex part.

3. **Copy-up semantics**: If a file exists in both ZIP and overlay, overlay wins. If
   a file is deleted in the overlay (whiteout), should it disappear from `/zip/` too?
   Docker's overlay2 supports whiteouts; do we need them?

4. **Upstream appetite**: Would jart accept a `/zip/` overlay feature into Cosmopolitan?
   It's a useful general-purpose feature (any APE app could use writable `/zip/`), but
   it adds complexity to a performance-critical code path.

---

## Approach #4b: Out-of-Tree Link-Time Interposition

### The _weaken() dispatch chain

Cosmopolitan's `openat.c` dispatches to `/zip/` via weak references:

```c
// libc/calls/openat.c:202-205
} else if (_weaken(__zipos_open) &&
           _weaken(__zipos_parseuri)(path, &zipname) != -1) {
    if (!__vforked && dirfd == AT_FDCWD) {
      rc = _weaken(__zipos_open)(&zipname, flags);
    }
}
```

Same pattern in `fstatat.c`, `access.c`, `truncate.c`, etc. The key functions
called through `_weaken()` are:

- `__zipos_open` (from `openat.c`)
- `__zipos_stat` (from `fstatat.c`)
- `__zipos_access` (from `access.c`)
- `__zipos_parseuri` (from all of the above)

### Link-time interposition

Since these are resolved at link time (not runtime), we can provide our own
implementations that the linker picks up first. If our `.o` is linked before the
zipos `.o` files, our symbols win.

```c
// third_party/mexican_toaster/zipos_overlay.c
//
// Drop-in replacement for __zipos_open that checks an overlay directory
// before falling through to the real zipos implementation.

#include "libc/runtime/zipos.internal.h"

static char g_overlay_path[PATH_MAX];

void toaster_set_overlay(const char *path) {
    if (path)
        snprintf(g_overlay_path, sizeof(g_overlay_path), "%s", path);
    else
        g_overlay_path[0] = '\0';
}

int __zipos_open(struct ZiposUri *name, int flags) {
    // If overlay is active and file exists there, redirect to real open
    if (g_overlay_path[0]) {
        char real[PATH_MAX];
        snprintf(real, sizeof(real), "%s/%s", g_overlay_path, name->path);
        int fd = open(real, flags);           // kernel open, not /zip/
        if (fd >= 0) return fd;
        if (errno != ENOENT) return -1;       // real error, propagate
        // fall through to ZIP lookup
    }

    // Call the real zipos open (need to call the internal implementation)
    // ... this is the tricky part -- see "Problem" below
}
```

### The problem with link-time interposition

The approach has a fundamental issue: if we define `__zipos_open`, we REPLACE
it entirely. We can't easily call the original from our replacement because
there's only one symbol with that name.

Possible workarounds:

1. **Copy the original implementation** into our file and add the overlay check
   at the top. Fragile -- breaks when upstream changes the function.

2. **Rename the original** via objcopy (`--redefine-sym __zipos_open=__zipos_open_orig`)
   then call `__zipos_open_orig` from our wrapper. Build system complexity.

3. **Don't interpose at the zipos level** -- instead interpose at `openat()` itself.
   But `openat` is even more complex and performance-critical.

4. **Use a different hook point**: Instead of replacing `__zipos_open`, replace
   `__zipos_parseuri`. Our version checks if the path exists in the overlay
   directory. If it does, rewrite the path to the overlay location and return -1
   (making openat fall through to the kernel syscall path for the rewritten path).
   If not, call the real parseuri to let zipos handle it. Same rename problem though.

### Verdict on out-of-tree

Link-time interposition is technically possible but fragile and complex. The
cleanest out-of-tree approach is **not to hook the VFS at all** but rather:

- Use Approach #3 (userspace overlay) for the portable fallback
- If #4 is pursued, do it properly as an upstream Cosmopolitan change with a
  well-designed API (e.g. `__zipos_set_overlay(path)`) rather than fighting
  the linker

---

## Recommendation

**Do both, in order:**

1. **Now: Approach #3** -- Implement the userspace overlay fallback in `thaw.inc`.
   This gets us cross-platform CI immediately with zero risk to the Linux prototype.
   It's ~20 lines of code and uses the existing `kOverlayUserland` backend enum.

2. **Later: Approach #4** -- Propose the zipos overlay hook to Cosmopolitan upstream.
   This is the elegant long-term solution that benefits all Cosmo apps. But it requires
   upstream approval and careful implementation in a performance-critical path.

The two approaches are complementary, not competing. #3 gives us portability today.
#4 gives us transparency tomorrow. And Mexican Toaster's `persist` doesn't care which
one `thaw` used -- it just reads from `/zip/` + upper and merges them.

---

## Files Referenced

| File | Purpose |
|------|---------|
| `third_party/mexican_toaster/examples/caboose/thaw.inc` | Current Linux-only thaw |
| `third_party/mexican_toaster/examples/caboose/piz_setup.inc` | Kernel overlay setup |
| `third_party/mexican_toaster/examples/caboose/namespace_setup.inc` | Linux namespace setup |
| `third_party/mexican_toaster/examples/caboose/overlay_backend.inc` | Backend enum (already has kOverlayUserland) |
| `third_party/mexican_toaster/examples/caboose/persist.inc` | Persist (already portable) |
| `libc/runtime/zipos-open.c` | Cosmopolitan /zip/ VFS open |
| `libc/runtime/zipos-stat.c` | Cosmopolitan /zip/ VFS stat |
| `libc/runtime/zipos-access.c` | Cosmopolitan /zip/ VFS access |
| `libc/runtime/zipos-find.c` | Cosmopolitan /zip/ VFS find/scan |
| `libc/runtime/zipos.internal.h` | Cosmopolitan /zip/ VFS internal header |
| `.github/workflows/cosmo-hello-world.yml` | Existing 6-runner CI matrix |
