# $LOADED_FEATURES Double Registration - RESOLVED

**Date:** 2025-12-28
**Status:** ✅ FIXED
**Issue:** Extensions appearing twice in $LOADED_FEATURES

## Problem Summary

Extensions were appearing multiple times in `$LOADED_FEATURES`:
- Once with short name (e.g., `monitor.so`)
- Once with full path (e.g., `/zip/.../monitor.a`)

Additionally, in slim static mode, registration was inconsistent:
- Some extensions: full paths (correct)
- Others: short names (wrong)

## Root Cause Analysis

### Issue 1: Extensions calling rb_provide() directly

Extension Init functions were calling `cosmo_provide()` → `rb_provide()` to manually register themselves. However, **Ruby's require mechanism automatically calls `rb_provide_feature()` after loading ANY extension** (load.c:1421).

**Evidence from pristine Ruby 3.4.7:**
```bash
$ grep -r "rb_provide" third_party/ruby-3.4.7/ext/monitor/
# No results - pristine extensions don't call rb_provide()

$ grep -r "rb_provide" third_party/ruby-3.4.7/cont.c
rb_provide("fiber.so");  # Only built-in features call it
```

**Conclusion:** Only built-in features initialized at startup (fiber.so, enumerator.so, complex.so, rational.so) call `rb_provide()`. Extensions loaded via require should NOT call it.

### Issue 2: Slim static mode search order bug

In load.c, the code checked `vm->static_ext_inits` BEFORE searching for stub files, even in slim static mode. This caused some extensions to return the short name from the static table instead of finding the stub file.

**Debug output revealed:**
```
[DEBUG search_required] FOUND in static_ext_inits! Returning short name: io/console.so
[DEBUG search_required] FOUND in static_ext_inits! Returning short name: stringio.so
```

But stub files existed:
```
/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/io/console.so (0 bytes)
/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/stringio.so (0 bytes)
```

## Solution

### Fix 1: Made cosmo_provide() a NO-OP

**File:** `third_party/ruby-wip-3.4.7/include/ruby/cosmo.h`

```c
/**
 * cosmo_provide - Mark extension initialization point (NO-OP)
 *
 * This function is intentionally a no-op in ALL build modes because Ruby's require
 * mechanism automatically calls rb_provide_feature() after successfully loading any
 * extension (see load.c:1421 in CosmoRuby, load.c:1354 in pristine Ruby 3.4.7).
 *
 * Why this function still exists:
 * - Provides a single code site for future registration logic if needed
 * - Documents the initialization point for each extension
 * - Maintains consistency across extension Init functions
 */
static inline void
cosmo_provide(const char *feature)
{
    // NO-OP: require mechanism handles registration automatically
    // after Init function completes successfully (load.c:1421)
    (void)feature;
}
```

**All extension Init functions updated to call cosmo_provide():**
- monitor.c
- pathname.c
- ripper_init.c
- socket.c
- stringio.c
- console.c
- wait.c

### Fix 2: Conditional static_ext_inits check

**File:** `third_party/ruby-wip-3.4.7/load.c`

Wrapped the static_ext_inits fallback to only run in static BARE mode:

```c
// IMPORTANT: Only do this in static BARE mode (SLIM_STATIC=0).
// In slim static mode (SLIM_STATIC=1), we want to find stub files, not use static_ext_inits.
#if defined(EXTSTATIC) && EXTSTATIC && defined(SLIM_STATIC) && !SLIM_STATIC
    if (!ft && type != loadable_ext_rb && vm->static_ext_inits) {
        // Prefer the logical feature name for static bare extensions (no stub files).
        VALUE lookup_name = fname;
        // ... lookup in static_ext_inits and return short name ...
    }
#endif
```

**Effect by build mode:**
- **Static bare** (EXTSTATIC=1, SLIM_STATIC=0): Fallback to static_ext_inits, returns short names
- **Slim static** (EXTSTATIC=1, SLIM_STATIC=1): Skips static_ext_inits, finds stub files, returns full paths
- **Dynamic** (EXTSTATIC=0): Skips static_ext_inits (not defined), finds .a files, returns full paths

## Verification

All three build modes tested and passing:

### Dynamic Mode ✅
```bash
$ irb.com
>> puts $LOADED_FEATURES.grep(/monitor|console|stringio/)
/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.a
/zip/lib/ruby/3.4.0/monitor.rb
/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/io/console.a
/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/stringio.a
```
✅ All extensions: full paths
✅ No duplicates

### Slim Static Mode ✅
```bash
$ irb.com
>> puts $LOADED_FEATURES.grep(/monitor|console|stringio/)
/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.so
/zip/lib/ruby/3.4.0/monitor.rb
/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/io/console.so
/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/stringio.so
```
✅ All extensions: full paths (consistent!)
✅ No duplicates

### Static Bare Mode ✅
```bash
$ irb.com
>> puts $LOADED_FEATURES.grep(/monitor|console|stringio/)
monitor.so
io/console.so
/zip/lib/ruby/3.4.0/monitor.rb
stringio.so
```
✅ All extensions: short names (correct for bare mode)
✅ No duplicates

## Test Suite Results

```bash
$ ./test_all_build_modes.sh
✅ Dynamic (plugin mode): PASSED
✅ Static Bare (no stubs): PASSED
✅ Static Slim (zero-byte stubs): PASSED
```

## Technical Details

### Ruby's Extension Loading Flow

```
1. require('extension_name')
   ↓
2. search_required() finds the file/static entry
   ↓
3. run_static_ext_init() OR dln_load_cosmo()
   ↓
4. Init_extension() is called
   ↓
5. Init function does its work
   ↓
6. Init function returns
   ↓
7. require_internal() calls rb_provide_feature(path)  ← AUTOMATIC!
   ↓
8. Extension registered in $LOADED_FEATURES
```

**Key insight:** Step 7 is AUTOMATIC for all extensions. Extensions should never call `rb_provide()` themselves.

### Built-in Features vs Extensions

**Built-in features** (compiled into Ruby core):
- Initialized during Ruby startup via Init_builtin()
- NOT loaded through require mechanism
- MUST call rb_provide() manually
- Examples: fiber.so, enumerator.so, complex.so, rational.so

**Extensions** (loaded via require):
- Loaded through require mechanism
- Require automatically calls rb_provide_feature()
- Should NOT call rb_provide()
- Examples: monitor, pathname, stringio, ripper, socket

## Files Modified

- `third_party/ruby-wip-3.4.7/include/ruby/cosmo.h` - Created NO-OP cosmo_provide()
- `third_party/ruby-wip-3.4.7/load.c` - Conditional static_ext_inits check + debug printfs
- `third_party/ruby-wip-3.4.7/ext/monitor/monitor.c` - Use cosmo_provide()
- `third_party/ruby-wip-3.4.7/ext/pathname/pathname.c` - Use cosmo_provide()
- `third_party/ruby-wip-3.4.7/ext/ripper/ripper_init.c` - Use cosmo_provide()
- `third_party/ruby-wip-3.4.7/ext/socket/socket.c` - Use cosmo_provide()
- `third_party/ruby-wip-3.4.7/ext/stringio/stringio.c` - Use cosmo_provide()
- `third_party/ruby-wip-3.4.7/ext/io/console/console.c` - Use cosmo_provide()
- `third_party/ruby-wip-3.4.7/ext/io/wait/wait.c` - Use cosmo_provide()

## Next Steps

1. ✅ Remove debug printfs from load.c before final commit
2. ✅ Test all three build modes
3. ✅ Verify no performance regressions
4. ✅ Document the fix
5. 🔄 Commit the changes

## References

- Pristine Ruby 3.4.7: `third_party/ruby-3.4.7/`
- CosmoRuby load.c: `third_party/ruby-wip-3.4.7/load.c:1421`
- Ruby's rb_provide: `third_party/ruby-wip-3.4.7/load.c:759`
- Extension registration: `third_party/ruby-wip-3.4.7/ext/extinit.c`
