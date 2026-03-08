# Implementation Spec: Cross-Platform Thaw (Approach #3)

**Date:** 2026-03-07
**Status:** In Progress
**Scope:** Mexican Toaster userspace overlay fallback
**Constraint:** Working Linux prototype MUST NOT be broken

---

## Overview

Implement a portable userspace overlay fallback for `thaw` that works on
macOS, Windows, and Linux (when kernel features are unavailable), while
keeping the existing Linux kernel overlay path functional.

### Backend Selection Logic

| Platform | User Namespaces Available | Backend Used |
|----------|---------------------------|--------------|
| Linux | Yes | `kOverlayKernel` (existing) |
| Linux | No | `kOverlayUserland` (new) |
| macOS | N/A | `kOverlayUserland` (new) |
| Windows | N/A | `kOverlayUserland` (new) |

### Environment Variable Override

```bash
# Force userland overlay (for testing on Linux)
TOASTER_BACKEND=userland ./caboose thaw

# Force kernel overlay (default on Linux with userns)
TOASTER_BACKEND=kernel ./caboose thaw

# Auto-detect (default)
TOASTER_BACKEND=auto ./caboose thaw
```

---

## Existing Code Inventory

These files already exist and provide building blocks:

| File | Provides |
|------|----------|
| `overlay_backend.inc` | `enum OverlayBackend`, `ParseOverlayBackend()`, `OverlayBackendName()` |
| `env_probe.inc` | `ProbeOverlayUserns()`, `DetectEnv()`, `struct OverlayProbe` |
| `recursive_copy.inc` | `CopyFile()`, `CopyDirectoryRecursive()` |
| `namespace_setup.inc` | `SetupUserNamespace()`, `MountOverlay()` |
| `state.inc` | State machine (`kCold`, `kThawed`, `kFrozen`, `kPersisted`) |
| `state_file.inc` | `struct ToasterStateFile`, `LoadStateFile()`, `SaveStateFile()` |
| `persist.inc` | `Persist()`, `RunCommand()`, `CleanupTempDir()` |

---

## Files to Modify

### 1. `state_file.inc` -- Add Backend Tracking

Add `backend` field to `struct ToasterStateFile` and update
`LoadStateFile()` / `SaveStateFile()` to persist it.

**Changes:**
- Add `enum OverlayBackend backend;` to the struct
- Parse `backend` from `[overlay]` section in `LoadStateFile()`
- Write `backend` to `[overlay]` section in `SaveStateFile()`
- Default to `kOverlayKernel` for backward compatibility with old state files

### 2. `thaw.inc` -- Add Backend Dispatch

Replace the unconditional kernel path with backend selection and dispatch.

**Changes:**
- Add `SelectBackend()` function using `ProbeOverlayUserns()` from `env_probe.inc`
- Kernel path: existing code (moved into the `kOverlayKernel` branch)
- Userland path: call `ThawUserland()` from the new `thaw_userland.inc`
- Record `sf.backend` before saving state

### 3. NEW: `thaw_userland.inc` -- Userspace Thaw

**Logic:**
1. `mkdtemp()` a temp directory for the upper layer
2. `CopyDirectoryRecursive("/zip", upper)` to populate it
3. Set `sf->upper_path` to the temp dir
4. Clear `lower_path`, `work_path`, `mount_path` (not used in userland mode)

No namespaces, no mounts, no root required. Works everywhere.

### 4. `persist.inc` -- Handle Userland Mode

In userland mode, the upper layer already contains a full copy of `/zip/`
plus modifications. The existing merge step (`CopyDirectoryRecursive("/zip", staging)`
then `CopyDirectoryRecursive(upper, staging)`) would duplicate content.

**Change:** If `sf.backend == kOverlayUserland`, copy only the upper
layer to staging (it already has everything).

### 5. `discard.inc` -- Handle Userland Cleanup

In userland mode, the upper layer is a real directory tree with files
(not an overlayfs mount). `rmdir()` won't work; need `rm -rf`.

**Change:** If `sf.backend == kOverlayUserland` (or if no mount exists),
use `CleanupTempDir()` (which does `rm -rf`) instead of `rmdir()`.

### 6. `freeze.inc` -- Handle Userland Mode

In userland mode there's no mount to unmount. Freeze is just a state
transition.

**Change:** Skip the `unmount()` call when `sf.mount_path` is empty
(which it will be for userland mode). The current code already handles
`EINVAL`/`EPERM`/`ENOENT` gracefully, so this may already work, but
it's cleaner to skip explicitly.

### 7. `status_cmd.inc` -- Show Backend

**Change:** Display the backend when state is not `kCold`.

### 8. `caboose.c` -- Add Include

**Change:** Add `#include "thaw_userland.inc"` after `recursive_copy.inc`
(since `ThawUserland` uses `CopyDirectoryRecursive`).

### 9. `demo_lifecycle.sh` -- Soften Namespace Requirement

**Change:** When `CAN_UNSHARE=false`, don't skip entirely. Instead print
a note that userland fallback will be used, and proceed with the demo.

---

## Implementation Checklist

- [ ] 1. Add `backend` field to `struct ToasterStateFile` in `state_file.inc`
- [ ] 2. Update `LoadStateFile()` to parse `backend` from `[overlay]` section
- [ ] 3. Update `SaveStateFile()` to write `backend` to `[overlay]` section
- [ ] 4. Create `thaw_userland.inc` with `ThawUserland()` function
- [ ] 5. Add `SelectBackend()` to `thaw.inc` and dispatch kernel vs userland
- [ ] 6. Update `persist.inc` to handle userland mode (skip /zip/ copy)
- [ ] 7. Update `discard.inc` to handle userland cleanup (rm -rf)
- [ ] 8. Update `freeze.inc` to skip unmount when no mount exists
- [ ] 9. Update `status_cmd.inc` to show backend
- [ ] 10. Update `caboose.c` includes
- [ ] 11. Update `demo_lifecycle.sh` to soften namespace requirement
- [ ] 12. Test on Linux with `TOASTER_BACKEND=userland`
- [ ] 13. Verify existing Linux kernel path still works

---

## Testing Strategy

### Manual Tests on Linux

```bash
# Build
make -j1 o//third_party/mexican_toaster/caboose

# Test 1: Userland path (force fallback)
TOASTER_BACKEND=userland o//third_party/mexican_toaster/caboose thaw
TOASTER_BACKEND=userland o//third_party/mexican_toaster/caboose status
TOASTER_BACKEND=userland o//third_party/mexican_toaster/caboose discard

# Test 2: Kernel path (default on Linux with userns)
o//third_party/mexican_toaster/caboose thaw
o//third_party/mexican_toaster/caboose status
o//third_party/mexican_toaster/caboose discard

# Test 3: Full lifecycle with userland
TOASTER_BACKEND=userland bash third_party/mexican_toaster/caboose/demo_lifecycle.sh
```

### Regression

```bash
# Existing kernel path must still work
bash third_party/mexican_toaster/caboose/demo_lifecycle.sh
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Break Linux kernel path | Keep existing code untouched; only add dispatch logic |
| State file incompatibility | Default to `kOverlayKernel` if backend field missing |
| Path too long on Windows | Use `__get_tmpdir()` which handles platform differences |
| Copy failures | Reuse existing `CopyDirectoryRecursive()` with error handling |

---

## Success Criteria

- [ ] `TOASTER_BACKEND=userland caboose thaw` works on Linux
- [ ] `caboose thaw` auto-detects and uses kernel overlay on capable Linux
- [ ] Full `demo_lifecycle.sh` passes with userland backend
- [ ] Existing kernel backend still works (no regression)
- [ ] State file correctly records and restores backend type
- [ ] `caboose status` displays the active backend
- [ ] `caboose discard` correctly cleans up for both backends
