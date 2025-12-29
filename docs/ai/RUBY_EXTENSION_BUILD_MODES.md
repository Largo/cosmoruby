# Ruby Extension Build Modes - CosmoRuby 3.4.7

**Last Updated:** 2025-12-28
**Status:** Current Implementation
**Purpose:** Document the extension build modes and expected $LOADED_FEATURES behavior

## Executive Summary

CosmoRuby supports three extension build modes, configured via `cosmo_configure.sh`:

| Mode | EXTSTATIC | DLEXT | SLIM_STATIC | Extensions Linked | Files in /zip | $LOADED_FEATURES |
|------|-----------|-------|-------------|-------------------|---------------|------------------|
| **Dynamic** (default) | 0 | `.a` | 0 | ❌ No (loaded via cosmo_plugin) | ✅ Actual .a archives | `.a` (full path only) |
| **Static Bare** | 1 | `.so` | 0 | ✅ Yes (--whole-archive) | ❌ Nothing | `.so` (short name only) |
| **Static Slim** | 1 | `.so` | 1 | ✅ Yes (--whole-archive) | ✅ Zero-byte .so stubs | `.so` (full path only) |

**Key Differences:**
- **Dynamic:** Extensions loaded on-demand from actual `.a` archives via position-independent code loader
- **Static Bare:** Extensions baked in, NO stub files (minimal ZIP, may break Ruby tools expecting files)
- **Static Slim:** Extensions baked in, zero-byte stubs present (Ruby require sees files, doesn't load them)

**Potential Future Mode:**
- **Static Fat:** Extensions baked in + actual .a archives in ZIP (FULL_STATIC=1, historical/compatibility)

## Critical Fix: DLEXT-Aware rb_provide()

**Recent Fix (2025-12-28):** All extensions now use `rb_provide("name" DLEXT)` instead of hardcoded `.so`:

```c
// Before (wrong - always used .so):
rb_provide("monitor.so");

// After (correct - adapts to build mode):
rb_provide("monitor" DLEXT);  // → "monitor.a" or "monitor.so" depending on mode
```

**Why this matters:** In dynamic mode, Ruby searches for `.a` files. If an extension calls `rb_provide("monitor.so")` but the file is `monitor.a`, require fails to find it.

**Fixed extensions:**
- ripper, io/console, io/wait, monitor, pathname, socket, stringio

## Mode 1: Dynamic (Plugin Mode)

### Configuration

```bash
third_party/ruby/cosmo_configure.sh --with-plugin-ext  # default
```

**Sets:**
- `EXTSTATIC=0` in `config.h`
- `DLEXT=".a"` in `config.h` and `rbconfig.rb`
- `SLIM_STATIC=0`

### How It Works

**Build Time:**
1. Extensions compiled as position-independent code → `.a` archives
2. Extensions **NOT** linked into ruby binary
3. Packaging script copies actual `.a` files to `/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/`

**Runtime:**
```
User: require 'monitor'
  ↓
Ruby: Check $LOADED_FEATURES for 'monitor' or 'monitor.a'
  ↓ (not found)
Ruby: Search load path for monitor.a
  ↓
Ruby: Finds /zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.a
  ↓
load.c: IS_DLEXT() matches ".a", calls dln_load_cosmo()
  ↓
cosmo_plugin: Loads .a archive, relocates code, resolves symbols
  ↓
cosmo_plugin: Calls Init_monitor()
  ↓
Init_monitor(): Initializes module, calls rb_provide("monitor.a")
  ↓
Ruby: Adds "/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.a" to $LOADED_FEATURES
```

**Characteristics:**
- ✅ Smaller base binary (~6MB without extensions)
- ✅ Extensions loaded on-demand (faster startup for scripts that don't use them)
- ✅ Rebuild individual extensions without relinking Ruby
- ✅ Position-independent code enables secure runtime loading
- ⚠️ Runtime overhead on first load (~1-5ms per extension)
- ⚠️ Requires cosmo_plugin infrastructure

**Files in /zip:**
```
/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/
  monitor.a           # ~50KB actual archive (position-independent code)
  pathname.a          # ~30KB actual archive
  ripper.a            # ~200KB actual archive
  ...
```

**Current $LOADED_FEATURES behavior:**
```ruby
enumerator.so          # Built-in (part of core interpreter)
fiber.so               # Built-in
ripper.a               # Extension without wrapper (short name from rb_provide)
io/console.a           # Extension without wrapper (short name from rb_provide)
io/wait.a              # Extension without wrapper (short name from rb_provide)
monitor.a              # Extension WITH wrapper (short name from rb_provide) ⚠️
/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.a     # Extension (full path from require) ⚠️
/zip/lib/ruby/3.4.0/monitor.rb                             # Ruby wrapper file
pathname.a             # Extension WITH wrapper (short name from rb_provide) ⚠️
/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/pathname.a    # Extension (full path from require) ⚠️
/zip/lib/ruby/3.4.0/pathname.rb                            # Ruby wrapper file
```

**Issue:** Extensions with Ruby wrappers appear TWICE (⚠️ marked). This is undesired double registration.

**Desired behavior:** Only full paths for extensions, no short names. See `LOADED_FEATURES_DOUBLE_REGISTRATION.md`.

## Mode 2: Static Bare

### Configuration

```bash
third_party/ruby/cosmo_configure.sh --with-static-linked-ext
```

**Sets:**
- `EXTSTATIC=1` in `config.h`
- `DLEXT=".so"` in `config.h` and `rbconfig.rb`
- `SLIM_STATIC=0`

### How It Works

**Build Time:**
1. Extensions compiled as `.a` archives
2. Extensions linked into ruby binary via `--whole-archive`:
   ```makefile
   -Wl,--whole-archive \
     o/$(MODE)/third_party/ruby/ext/monitor/monitor.a \
     o/$(MODE)/third_party/ruby/ext/pathname/pathname.a \
     ... \
   -Wl,--no-whole-archive
   ```
3. `ext/extinit.c` compiled with `EXTSTATIC=1`, registers Init functions
4. Packaging script does **NOT** create any stub files (bare mode)

**Startup:**
```
Ruby initialization:
  ↓
ruby_init() → Init_ext()  [EXTSTATIC=1 defined]
  ↓
init(Init_monitor, "monitor"):
  → extern void Init_monitor(void) __attribute__((weak));
  → if (Init_monitor) ruby_init_ext("monitor.so", Init_monitor);
  ↓
ruby_init_ext("monitor.so", Init_monitor):
  → Adds entry to vm->static_ext_inits: {"monitor.so" => Init_monitor}
  → Does NOT call Init_monitor() yet!
  → Does NOT add to $LOADED_FEATURES yet!
```

**Runtime:**
```
User: require 'monitor'
  ↓
Ruby: Check $LOADED_FEATURES for 'monitor' or 'monitor.so'
  ↓ (not found)
Ruby: Does NOT find monitor.so in load path (no stub file exists)
  ↓
Ruby: Checks if 'monitor.so' is in vm->static_ext_inits table
  ↓
run_static_ext_init(vm, "monitor.so"):
  → Found! Call Init_monitor()
  → Delete from table (prevent double-init)
  ↓
Init_monitor(): Initializes module, calls rb_provide("monitor.so")
  ↓
Ruby: Adds "monitor.so" to $LOADED_FEATURES (short name only!)
```

**Characteristics:**
- ✅ Minimal ZIP size (no stub files)
- ✅ Single binary, all extensions included
- ✅ No runtime loading overhead
- ⚠️ **May break Ruby introspection tools** that expect extension files to exist
- ❌ Larger binary (~8MB with extensions)
- ❌ Must rebuild Ruby to add/remove extensions

**Files in /zip:**
```
/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/
  (empty - no files created)
```

**Current $LOADED_FEATURES behavior:**
```ruby
enumerator.so          # Built-in
fiber.so               # Built-in
ripper.so              # Extension without wrapper (short name from rb_provide)
io/console.so          # Extension without wrapper (short name from rb_provide)
io/wait.so             # Extension without wrapper (short name from rb_provide)
monitor.so             # Extension WITH wrapper (short name from run_static_ext_init)
/zip/lib/ruby/3.4.0/monitor.rb                            # Ruby wrapper file
pathname.so            # Extension WITH wrapper (short name from run_static_ext_init)
/zip/lib/ruby/3.4.0/pathname.rb                           # Ruby wrapper file
```

**Note:** Only short names appear for extensions since stub files don't exist in bare mode.

## Mode 3: Static Slim (Recommended Static Mode)

### Configuration

```bash
third_party/ruby/cosmo_configure.sh --with-static-linked-ext --with-slim-static
```

**Sets:**
- `EXTSTATIC=1` in `config.h`
- `DLEXT=".so"` in `config.h` and `rbconfig.rb`
- `SLIM_STATIC=1`

### How It Works

**Build Time:** Same as Static Bare, but:
- Packaging script creates **zero-byte** stub `.so` files in `/zip/lib/ruby/3.4.0/extensions/`

**Startup:** Same as Static Bare (extensions registered in vm->static_ext_inits)

**Runtime:**
```
User: require 'monitor'
  ↓
Ruby: Check $LOADED_FEATURES
  ↓ (not found)
Ruby: Search load path
  ↓
Ruby: Finds /zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.so (0 bytes!)
  ↓
load.c: found == 's' (static extension marker)
  ↓
run_static_ext_init(vm, "monitor.so"):
  → Look up "monitor.so" in vm->static_ext_inits
  → Found! Call Init_monitor()
  → Delete from table
  ↓
Init_monitor(): Initializes module, calls rb_provide("monitor.so")
  ↓
Ruby: Adds "/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.so" to $LOADED_FEATURES (full path)
```

**Characteristics:**
- ✅ Ruby tools see extension files (compatibility)
- ✅ Single binary, all extensions included
- ✅ No runtime loading overhead
- ✅ Minimal ZIP overhead (~2KB for all stubs)
- ❌ Larger binary (~8MB with extensions)
- ❌ Must rebuild Ruby to add/remove extensions

**Files in /zip:**
```
/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/
  monitor.so           # 0 bytes (stub marker)
  pathname.so          # 0 bytes (stub marker)
  ripper.so            # 0 bytes (stub marker)
  ...
```

**Current $LOADED_FEATURES behavior:**
```ruby
enumerator.so          # Built-in
fiber.so               # Built-in
ripper.so              # Extension without wrapper (short name from rb_provide)
io/console.so          # Extension without wrapper (short name from rb_provide)
io/wait.so             # Extension without wrapper (short name from rb_provide)
monitor.so             # Extension WITH wrapper (short name from run_static_ext_init) ⚠️
/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.so    # Zero-byte stub (full path from require) ⚠️
/zip/lib/ruby/3.4.0/monitor.rb                             # Ruby wrapper file
pathname.so            # Extension WITH wrapper (short name from run_static_ext_init) ⚠️
/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/pathname.so   # Zero-byte stub (full path from require) ⚠️
/zip/lib/ruby/3.4.0/pathname.rb                            # Ruby wrapper file
```

**Issue:** Extensions with wrappers appear TWICE (⚠️ marked). Undesired double registration.

**Desired behavior:** Only full paths for extensions. See `LOADED_FEATURES_DOUBLE_REGISTRATION.md`.

## Potential Future Mode: Static Fat

### Configuration (Not Yet Implemented)

```bash
third_party/ruby/cosmo_configure.sh --with-static-linked-ext --with-full-static
```

**Would set:**
- `EXTSTATIC=1`
- `DLEXT=".so"`
- `FULL_STATIC=1`

### Concept

**Build Time:**
- Extensions linked into ruby binary (like static modes)
- Actual `.a` archives **also copied** to `/zip/lib/ruby/3.4.0/extensions/`
- Provides "historical accuracy" - files exist as archives even though code is statically linked

**Use Case:**
- Maximum Ruby ecosystem compatibility
- Tools that expect to find extension archives
- Debugging/inspection (can extract and examine .a files)

**Tradeoff:**
- Larger ZIP (~2MB extra for all extension archives)
- Functionally identical to Static Slim at runtime

## Comparison Matrix

### Binary & ZIP Size

| Mode | Ruby Binary | Extensions in /zip | Total ruby.com |
|------|-------------|-------------------|----------------|
| Dynamic | ~6MB | ~2MB (.a archives) | ~17MB (+ stdlib) |
| Static Bare | ~8MB | ~0KB (nothing) | ~15MB (+ stdlib) |
| Static Slim | ~8MB | ~2KB (stubs) | ~15MB (+ stdlib) |
| Static Fat | ~8MB | ~2MB (.a archives) | ~17MB (+ stdlib) |

### $LOADED_FEATURES Behavior

**Current (has bug):**

| Mode | Built-ins | Extensions w/o wrapper | Extensions WITH wrapper (.rb) |
|------|-----------|------------------------|-------------------------------|
| Dynamic | `.so` short | `.a` short only | `.a` short + full path + .rb ⚠️ |
| Static Bare | `.so` short | `.so` short only | `.so` short + .rb |
| Static Slim | `.so` short | `.so` short only | `.so` short + full path + .rb ⚠️ |

**Desired (after fix):**

| Mode | Built-ins | All Extensions |
|------|-----------|----------------|
| Dynamic | `.so` short name | `.a` full path only |
| Static Bare | `.so` short name | `.so` short name only |
| Static Slim | `.so` short name | `.so` full path only |

⚠️ = Double registration bug. See `LOADED_FEATURES_DOUBLE_REGISTRATION.md` for fix.

### Performance

| Operation | Dynamic | Static Bare | Static Slim |
|-----------|---------|-------------|-------------|
| Startup (no extensions) | Fast | Fast | Fast |
| Startup (load 10 exts) | Medium (+10-50ms) | Fast | Fast |
| First require | Slow (1-5ms load) | Instant | Instant |
| Subsequent require | Instant | Instant | Instant |
| Memory usage | Lower (on-demand) | Higher | Higher |

### Ruby Compatibility

| Aspect | Dynamic | Static Bare | Static Slim |
|--------|---------|-------------|-------------|
| `File.exist?("monitor.so")` | ✅ Yes (.a file) | ❌ No | ✅ Yes (stub) |
| `gem install` native exts | ❌ No | ❌ No | ❌ No |
| RubyGems introspection | ⚠️ Sees .a not .so | ⚠️ No files | ✅ Sees .so stubs |
| Standard Ruby tools | ⚠️ May expect .so | ❌ May break | ✅ Compatible |

## Switching Between Modes

### Dynamic → Static Slim (Recommended)

```bash
# Reconfigure
bash third_party/ruby/cosmo_configure.sh --with-static-linked-ext --with-slim-static

# Rebuild
make -j8 o//third_party/ruby/ruby

# Repackage
bash third_party/ruby/package_ruby.sh

# Verify
ruby.com --disable-gems -e 'puts $LOADED_FEATURES.grep(/monitor/)'
# Expected: /zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.so

ruby.com --disable-gems -e 'puts File.size("/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.so")'
# Expected: 0
```

### Static Slim → Dynamic

```bash
# Reconfigure
bash third_party/ruby/cosmo_configure.sh --with-plugin-ext

# Rebuild
make -j8 o//third_party/ruby/ruby

# Repackage
bash third_party/ruby/package_ruby.sh

# Verify
ruby.com --disable-gems -e 'puts $LOADED_FEATURES.grep(/monitor/)'
# Expected: /zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.a

ruby.com --disable-gems -e 'puts File.size("/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.a")'
# Expected: 50000+ (actual archive size)
```

## Troubleshooting

### Double Registration in $LOADED_FEATURES

**Symptom:** Both short name and full path appear:
```ruby
monitor.a
/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.a
```

**Root Cause:** Extension's `.rb` wrapper calls `require 'monitor'` after the extension is already loaded.

**Fix:** Ensure extension Init functions call `rb_provide()` BEFORE any Ruby code runs. The fix is already applied (using `DLEXT` macro).

### Extension LoadError Despite File Existing

**Symptom:**
```ruby
ruby.com -e "require 'monitor'"
# LoadError: cannot load such file -- monitor
```

**Diagnosis:**
```bash
# Check mode
grep EXTSTATIC third_party/ruby/include/ruby/config.h
grep DLEXT third_party/ruby/include/ruby/config.h

# Dynamic mode (EXTSTATIC=0, DLEXT=".a"):
ruby.com -e 'puts Dir["/zip/**/monitor.{a,so}"]'
# Should show: .../monitor.a

# Static mode (EXTSTATIC=1, DLEXT=".so"):
nm o//third_party/ruby/ruby | grep Init_monitor
# Should show: T Init_monitor
```

**Fix:**
- If DLEXT mismatch: Run `cosmo_configure.sh` again, rebuild, repackage
- If Init_monitor missing: Check `extinit.c` has `init(Init_monitor, "monitor")`
- If .a file missing: Ensure `package_ruby.sh` ran after build

### Mixed .a and .so Extensions

**Symptom:**
```ruby
$LOADED_FEATURES:
  monitor.a
  pathname.so
  ripper.a
```

**Root Cause:** Packaging bug or stale ZIP content.

**Fix:**
```bash
make clean
bash third_party/ruby/cosmo_configure.sh --with-plugin-ext  # or --with-static-linked-ext --with-slim-static
make -j8 o//third_party/ruby/ruby
bash third_party/ruby/package_ruby.sh
```

## Recommendations

### For Development: Dynamic Mode

**Use when:**
- ✅ Iterating on individual extensions
- ✅ Testing extension loading behavior
- ✅ Want faster rebuild times

### For Production: Static Slim Mode

**Use when:**
- ✅ Shipping to users
- ✅ Want Ruby tool compatibility
- ✅ Need maximum performance (no load overhead)
- ✅ Don't plan to modify extensions

### For Debugging: Static Bare Mode

**Use when:**
- ✅ Minimizing ZIP size for analysis
- ✅ Debugging static linking issues
- ❌ Don't use if you need Ruby introspection tools

## Technical Implementation Details

### Dynamic Mode: cosmo_plugin Loading

```c
// dln_cosmo.c
void *dln_load_cosmo(const char *path, const char *init_name) {
  const struct cosmo_export *exports = cosmo_get_exports(NULL);
  return cosmo_load_plugin(path, exports, init_name);
}
```

**Process:**
1. Read `.a` archive from /zip
2. Extract position-independent `.o` files
3. Allocate executable memory
4. Apply relocations, resolve symbols against export table
5. Call init function

### Static Modes: Weak Symbol Pattern

```c
// ext/extinit.c
#define init(func, name) { \
    extern void func(void) __attribute__((weak)); \
    if (func) ruby_init_ext(name DLEXT, func); \
}

void Init_ext(void) {
#if defined(EXTSTATIC) && EXTSTATIC
    init(Init_monitor, "monitor");
    init(Init_pathname, "pathname");
    init(Init_ripper, "ripper");
    init(Init_console, "io/console");
    init(Init_wait, "io/wait");
    // ...
#endif
}
```

**Why weak symbols:**
- Allows removing extensions from build without breaking extinit.c
- `if (func)` checks if extension was actually linked
- Modular: can enable/disable extensions via THIRD_PARTY_RUBY_EXTENSIONS list

### Packaging Logic

**From ruby.plugins.mk:**
```makefile
if [ "$(RUBY_EXTSTATIC)" = "0" ]; then
  # Dynamic mode: copy actual .a archives
  cp o/$(MODE)/third_party/ruby/ext/monitor/monitor.a \
     o/$(MODE)/third_party/ruby/plugins/x86_64-cosmo/monitor.a
elif [ "$(RUBY_SLIM_STATIC)" = "1" ]; then
  # Static slim: create zero-byte stubs
  : > o/$(MODE)/third_party/ruby/plugins/x86_64-cosmo/monitor.so
fi
# Note: If EXTSTATIC=1 and SLIM_STATIC=0 (bare), nothing is copied
```

## Related Documentation

- `BUILD_TARGETS.md` - All Ruby build artifacts
- `EXTENSIONS_HOW_TO.md` - Adding new extensions
- `COSMO_PLUGIN_SYSTEM_V2.md` - Plugin loader architecture
- `STATIC_EXTENSION_INIT_FIX.md` - Init system debugging
- `LOADED_FEATURES_DOUBLE_REGISTRATION.md` - **Issue: Double registration and fix**
- `cosmo_configure.sh` - Configuration script source

## Changelog

**2025-12-28:** Initial documentation
- Documented three current modes (dynamic, static bare, static slim)
- Noted potential future mode (static fat)
- Fixed DLEXT-aware rb_provide() in all extensions
- Added ripper, io/console, io/wait to extinit.c
- Clarified expected $LOADED_FEATURES behavior (no double registration)
