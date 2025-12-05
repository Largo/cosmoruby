# Mexican Toaster - Self-Contained Rails+Redbean Dev Environment

## Vision

Mexican Toaster is a **single-file APE (Actually Portable Executable)** containing:
- Ruby interpreter
- Rails framework
- Redbean web server
- All dependencies
- Development tools

**Goal**: Distribute a single `.com` file that runs a complete Rails dev environment on Linux, macOS, Windows, and BSDs - no installation required.

## Design Constraints

### No Root Required
- Must work **without sudo on the host**
- Must work **without fake root inside containers**
- Users should just run `./railsapp.com` and it works

### Writable Overlay Strategy
Since the APE contains a read-only embedded ZIP filesystem (`/zip`), we need a writable layer for:
- Rails tmp/ directory
- Database files (SQLite)
- Log files
- User-uploaded content
- Gem installations

**Overlay Options (in priority order):**
1. **Userland overlay** - Pure application-level copy-on-write (portable, no privileges)
2. **FUSE-overlayfs** - If `/dev/fuse` accessible and binary available
3. **Kernel overlayfs with user namespaces** - Best performance but requires kernel support

### Current Status
- ✅ Embedded ZIP filesystem works
- ✅ unshare() syscall wrapper implemented and tested
- ✅ Kernel overlayfs with user namespaces working (requires AppArmor config - see below)
- 🚧 Userland overlay implementation (primary target for portability)
- 🚧 FUSE-overlayfs fallback (if available)

### AppArmor Restriction on User Namespaces

**Issue**: On Ubuntu/Debian systems, AppArmor restricts unprivileged user namespaces by default:
```bash
kernel.apparmor_restrict_unprivileged_userns = 1  # Blocks user namespaces
```

**Current Development Workaround** (requires sudo once):
```bash
sudo sysctl kernel.apparmor_restrict_unprivileged_userns=0
```

**TODO - Production Solution**:
We need a more fine-grained approach that doesn't require system-wide AppArmor changes:
1. Ship an AppArmor profile that allows user namespaces only for caboose binary
2. Gracefully fall back to userland overlay if kernel overlayfs is unavailable
3. Detect the restriction and provide helpful error message with instructions
4. Consider FUSE-overlayfs as middle ground (works with unprivileged FUSE)

**Why this matters**:
- Security-conscious users won't want to disable AppArmor restrictions system-wide
- CI/CD environments and containers may have this restriction enabled
- macOS/Windows/BSDs don't support user namespaces anyway
- The "it just works" principle requires graceful fallback

## Philosophy

Mexican Toaster follows the "it just works" principle:
- No system modifications
- No privilege escalation
- No external dependencies
- Cross-platform by default
- Single file distribution
