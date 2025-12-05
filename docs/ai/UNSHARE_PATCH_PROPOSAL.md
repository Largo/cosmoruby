# Proposal: Add unshare() syscall wrapper to Cosmopolitan

## Summary

Add a wrapper for the Linux `unshare()` syscall to enable namespace operations for containerization and isolation use cases.

## Motivation

The `unshare()` syscall is fundamental for modern Linux containerization, allowing processes to disassociate parts of their execution context (mount namespaces, user namespaces, network namespaces, etc.). While Cosmopolitan already has the low-level syscall stub (`sys_unshare` in `libc/sysv/syscalls.sh:288`), it lacks the high-level C wrapper function.

**Use cases:**
- Creating isolated environments for applications
- Implementing userspace container runtimes
- Privilege separation and sandboxing
- Testing code in isolated namespaces

## Implementation

The implementation follows the existing pattern used by similar Linux-only syscalls like `pivot_root()`:

### Files to modify:

1. **libc/calls/syscall-sysv.internal.h** - Add `sys_unshare` declaration
2. **libc/isystem/sched.h** - Add `unshare()` public declaration
3. **libc/calls/unshare.c** - Implement wrapper function

### Implementation details:

The syscall stub already exists:
```
scall	sys_unshare		0xfffffffffffff110	0x061	globl # no wrapper
```

This maps to:
- Linux x86_64: syscall 272 (0x110)
- Linux aarch64: syscall 97 (0x061)
- Other OSes: ENOSYS (0xfff)

## Testing

Can be tested with:
```c
#include <sched.h>
#include <stdio.h>

int main() {
    if (unshare(CLONE_NEWUSER) == 0) {
        printf("Successfully created user namespace\n");
        return 0;
    }
    perror("unshare");
    return 1;
}
```

## Compatibility

- Linux-only syscall (returns ENOSYS on other platforms)
- Requires appropriate kernel support (CONFIG_USER_NS, CONFIG_PID_NS, etc.)
- May require CAP_SYS_ADMIN or unprivileged_userns_clone=1

## References

- man 2 unshare: https://man7.org/linux/man-pages/man2/unshare.2.html
- Similar syscalls already in Cosmopolitan: `pivot_root()`, `mount()`, `setns()`
