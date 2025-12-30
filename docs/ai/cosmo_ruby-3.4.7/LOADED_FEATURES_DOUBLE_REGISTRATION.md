# $LOADED_FEATURES Double Registration Issue

**Last Updated:** 2025-12-28
**Status:** Known Behavior / Design Decision Needed
**Issue:** Extensions with Ruby wrappers appear twice in $LOADED_FEATURES

## The Problem

In plugin mode (DLEXT=".a"), some extensions appear in `$LOADED_FEATURES` with BOTH a short name and full path:

```ruby
monitor.a                                                    # Short name
/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.a       # Full path
/zip/lib/ruby/3.4.0/monitor.rb                              # Wrapper .rb file
```

Others appear only with the short name:

```ruby
ripper.a                                                     # Short name only (during IRB startup)
```

## Root Cause

Extensions that have Ruby wrapper files (`.rb` files that call `require 'extension.a'`) get registered twice due to standard Ruby behavior:

### Flow for monitor (HAS wrapper .rb):

```
1. require 'monitor'
   ↓
2. Ruby finds /zip/lib/ruby/3.4.0/monitor.rb
   ↓
3. Ruby loads monitor.rb → adds "/zip/lib/ruby/3.4.0/monitor.rb" to $LOADED_FEATURES
   ↓
4. monitor.rb executes: require 'monitor.a'  [line 10 of monitor.rb]
   ↓
5. Ruby finds /zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.a
   ↓
6. Ruby loads the .a archive via cosmo_plugin
   ↓
7. Calls Init_monitor()
   ↓
8. Init_monitor() calls: rb_provide("monitor.a")
   → Adds "monitor.a" to $LOADED_FEATURES
   ↓
9. require mechanism adds: "/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.a"
   → Adds full path to $LOADED_FEATURES
```

**Result:** THREE entries in $LOADED_FEATURES:
1. `monitor.a` (from rb_provide in C code)
2. `/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.a` (from require mechanism)
3. `/zip/lib/ruby/3.4.0/monitor.rb` (from loading wrapper)

### Extensions with this behavior:

All extensions that have `ext/NAME/lib/NAME.rb` files that do `require 'NAME.a'`:
- monitor (ext/monitor/lib/monitor.rb → `require 'monitor.a'` on line 10)
- pathname (ext/pathname/lib/pathname.rb → `require 'pathname.a'` on line 13)
- stringio (lib/stringio.rb → likely has similar require)

### Extensions WITHOUT this behavior:

Extensions loaded directly without a wrapper .rb that calls require:
- ripper (has ripper.rb but it doesn't call `require 'ripper.a'`, just loads Ruby helper files)
- io/console (no wrapper .rb file that requires the extension)
- io/wait (no wrapper .rb file that requires the extension)

## Desired Behavior (User Requirement)

> in all cases i would like loaded_features to have the bare .so when built-in and the full path when dynamically loaded but not both

**Interpretation:**
- **Built-ins** (enumerator, fiber, rational, complex): Short name only (e.g., `"enumerator.so"`)
- **Dynamically loaded extensions** (.a files via cosmo_plugin): Full path only (e.g., `"/zip/.../monitor.a"`)
- **NO double registration**: Each extension should appear exactly once

## Potential Solutions

### Option 1: Remove rb_provide() from C extensions (Recommended)

**Change:** Don't call `rb_provide()` in Init functions for extensions with Ruby wrappers

**Rationale:** The require mechanism will add the full path automatically when the .a file is loaded

**Implementation:**
```c
// ext/monitor/monitor.c - REMOVE THIS:
// rb_provide("monitor" DLEXT);

// Let the require mechanism handle it
```

**Result:**
- `$LOADED_FEATURES` will only have: `/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.a`
- No short name `monitor.a`

**Pros:**
- ✅ Eliminates double registration
- ✅ Consistent behavior: all dynamically loaded extensions show full path
- ✅ Matches standard Ruby behavior (require adds full path)

**Cons:**
- ⚠️ Extensions without .rb wrappers (io/console, io/wait) still need rb_provide()
- ⚠️ Need to audit which extensions have wrappers vs which don't

### Option 2: Modify rb_provide() to add full path

**Change:** Make rb_provide() smarter - add full path instead of short name

**Implementation:**
```c
// In each Init function, pass the full path:
rb_provide("/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor" DLEXT);
```

**Pros:**
- ✅ Keeps rb_provide() calls (explicit intent)
- ✅ Single source of registration

**Cons:**
- ❌ Extensions don't know their own path at Init time
- ❌ Would need to pass path from loader
- ❌ Complex to implement

### Option 3: Check if already loaded before requiring in .rb wrappers

**Change:** Modify wrapper .rb files to check $LOADED_FEATURES first

**Implementation:**
```ruby
# ext/monitor/lib/monitor.rb
require 'monitor.a' unless $LOADED_FEATURES.any? { |f| f.include?('monitor.a') }
```

**Pros:**
- ✅ Explicit opt-in for each extension
- ✅ Keeps rb_provide() calls

**Cons:**
- ❌ Fragile (path-dependent check)
- ❌ Need to modify Ruby stdlib files
- ❌ Doesn't follow standard Ruby patterns

### Option 4: Let rb_provide() add full path when called from loaded extension

**Change:** Modify rb_provide() C implementation to detect if it's being called from a loaded .a file

**Implementation:**
```c
// In rb_provide():
if (currently_loading_from_zip) {
    // Add full path instead of short name
    rb_ary_push(vm->loaded_features, current_loading_path);
} else {
    // Add short name (current behavior)
    rb_ary_push(vm->loaded_features, name);
}
```

**Pros:**
- ✅ Centralized fix
- ✅ No changes needed to Init functions
- ✅ Automatically handles all extensions

**Cons:**
- ⚠️ Requires tracking "currently loading path" in load.c
- ⚠️ More complex implementation

## Recommendation

**Use Option 1 (Remove rb_provide for extensions with wrappers) + refinement:**

1. **Create two categories of extensions:**
   - **With Ruby wrappers** (monitor, pathname, stringio): Don't call rb_provide()
   - **Without wrappers** (io/console, io/wait): Keep rb_provide()

2. **Document the pattern:**
   ```c
   // Init_monitor() - HAS wrapper .rb file that calls require
   void Init_monitor(void) {
       // ... initialization ...

       // DON'T call rb_provide() - the wrapper .rb handles loading
       // rb_provide("monitor" DLEXT);  // ← REMOVE
   }

   // Init_console() - NO wrapper, direct require 'io/console'
   void Init_console(void) {
       // ... initialization ...

       // DO call rb_provide() - no wrapper to add to $LOADED_FEATURES
       rb_provide("io/console" DLEXT);  // ← KEEP
   }
   ```

3. **Update EXTENSIONS_HOW_TO.md** to document when to use rb_provide()

## Expected Results After Fix

**Plugin mode (DLEXT=".a"):**
```ruby
$LOADED_FEATURES:
  enumerator.so                                           # Built-in (short name)
  fiber.so                                                # Built-in (short name)
  ripper.a                                                # Extension without wrapper (short name via rb_provide)
  io/console.a                                            # Extension without wrapper (short name via rb_provide)
  io/wait.a                                               # Extension without wrapper (short name via rb_provide)
  /zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.a   # Extension with wrapper (full path only)
  /zip/lib/ruby/3.4.0/monitor.rb                          # Ruby wrapper
  /zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/pathname.a  # Extension with wrapper (full path only)
  /zip/lib/ruby/3.4.0/pathname.rb                         # Ruby wrapper
  /zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/stringio.a  # Extension with wrapper (full path only)
```

**Static modes (DLEXT=".so"):**
```ruby
$LOADED_FEATURES:
  enumerator.so                                           # Built-in (short name)
  fiber.so                                                # Built-in (short name)
  ripper.so                                               # Static extension (short name from rb_provide)
  io/console.so                                           # Static extension (short name from rb_provide)
  io/wait.so                                              # Static extension (short name from rb_provide)
  monitor.so                                              # Static extension with wrapper (short name from run_static_ext_init)
  /zip/lib/ruby/3.4.0/monitor.rb                          # Ruby wrapper
  pathname.so                                             # Static extension with wrapper (short name from run_static_ext_init)
  /zip/lib/ruby/3.4.0/pathname.rb                         # Ruby wrapper
  stringio.so                                             # Static extension with wrapper (short name from run_static_ext_init)
```

## Action Items

1. **Audit all extensions** - categorize which have .rb wrappers
2. **Remove rb_provide()** from extensions with wrappers (monitor, pathname, stringio, etc.)
3. **Keep rb_provide()** for extensions without wrappers (ripper, io/console, io/wait, etc.)
4. **Test** that require still works correctly
5. **Update docs** to explain when to use rb_provide()

## Extension Audit

| Extension | Has .rb wrapper? | Calls require in wrapper? | Current rb_provide? | Action |
|-----------|------------------|---------------------------|---------------------|--------|
| monitor | ✅ Yes (ext/monitor/lib/monitor.rb) | ✅ Yes (`require 'monitor.a'`) | ✅ Yes | Remove rb_provide() |
| pathname | ✅ Yes (ext/pathname/lib/pathname.rb) | ✅ Yes (`require 'pathname.a'`) | ✅ Yes | Remove rb_provide() |
| stringio | ✅ Yes (lib/stringio.rb) | ✅ Likely | ✅ Yes | Remove rb_provide() |
| ripper | ⚠️ Yes (lib/ripper.rb) | ❌ No (only requires ripper/*.rb) | ✅ Yes | Keep rb_provide() |
| io/console | ❌ No | N/A | ✅ Yes | Keep rb_provide() |
| io/wait | ❌ No | N/A | ✅ Yes | Keep rb_provide() |
| socket | ✅ Yes (ext/socket/lib/socket.rb) | ✅ Likely | ✅ Yes | Remove rb_provide() |
| etc | ❌ No | N/A | ✅ Likely | Keep rb_provide() |
| psych | ✅ Yes (ext/psych/lib/psych.rb) | ✅ Likely | ✅ Likely | Remove rb_provide() |
| json | ✅ Yes (ext/json/lib/json.rb) | ✅ Likely | ✅ Likely | Remove rb_provide() |
| zlib | ❓ Need to check | ❓ Need to check | ✅ Likely | TBD |
| digest | ❓ Need to check | ❓ Need to check | ✅ Likely | TBD |
| date | ❓ Need to check | ❓ Need to check | ✅ Likely | TBD |
| mbedtls | ❌ No | N/A | ✅ Likely | Keep rb_provide() |

## References

- Ruby require mechanism: `load.c`
- Extension initialization: `ext/extinit.c`
- Wrapper files: `ext/*/lib/*.rb` and `lib/*.rb`
