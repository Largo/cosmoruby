# Ruby Static Linking Strategy for Cosmopolitan

**⚠️ OUTDATED - ARCHIVED 2025-12-28**
**This document describes an old architecture. See RUBY_EXTENSION_BUILD_MODES.md for current implementation.**

**Last Updated:** 2025-12-07
**Status:** ~~Documented~~ **SUPERSEDED**
**Purpose:** Explain how CosmoRuby avoids dlopen() and uses static linking for extensions

**Why Outdated:** This document doesn't describe the current three-mode system:
- Plugin mode (EXTSTATIC=0, DLEXT=.a) - dynamic loading via cosmo_plugin
- Static mode (EXTSTATIC=1, DLEXT=.so) - static linking with stub files
- Slim static mode (EXTSTATIC=1, SLIM_STATIC=1) - static linking optimized

---

## Overview

CosmoRuby uses a **static linking strategy** for C extensions instead of Ruby's default **dynamic loading** approach. This enables Actually Portable Executables that work across platforms without requiring separate `.so` files.

## Ruby's Three Extension Loading Modes

Ruby supports three different extension loading architectures:

### 1. **Dynamic Loading** (Standard Ruby)

**Files used:**
- `dmyext.c` - Defines empty `Init_ext()` (does nothing)
- `dln.c` - Implements `dln_load()` using `dlopen()`

**How it works:**
```
User: require 'socket'
  ↓
Ruby: Check if 'socket.so' already in $LOADED_FEATURES
  ↓ (not found)
Ruby: Search load path for socket.so file
  ↓
Ruby: dln_load("socket.so")  → dlopen()
  ↓
dlopen: Load socket.so, call Init_socket()
  ↓
Ruby: Add 'socket.so' to $LOADED_FEATURES
```

**Characteristics:**
- ✅ Can load gems with native extensions via `gem install`
- ✅ Extensions rebuilt independently
- ✅ Smaller base binary
- ❌ Requires `.so` files to exist on filesystem
- ❌ Platform-specific `.so` files
- ❌ Not portable across OSes

### 2. **MiniRuby** (Build-Time Tool)

**Files used:**
- `miniinit.c` - Defines empty `Init_enc()`
- `dmydln.c` - `dln_load()` throws "can't load extension libraries" error

**How it works:**
```
User: require 'socket'
  ↓
Ruby: Check if 'socket.so' in $LOADED_FEATURES
  ↓ (not found)
Ruby: Search load path
  ↓
Ruby: dln_load("socket.so") → ERROR!
  ↓
dmydln.c: rb_loaderror("this executable file can't load extension libraries")
```

**Characteristics:**
- ✅ Minimal binary for build tools
- ❌ Cannot load ANY extensions
- ❌ Only for building Ruby itself

### 3. **Static Linking** (CosmoRuby)

**Files used:**
- `ext/extinit.c` - Defines `Init_ext()` that calls all extension initializers
- `dln.c` - Full implementation (dlopen support compiled in but not used for built-in extensions)

**How it works:**
```
Ruby startup:
  ↓
ruby_init()
  ↓
Init_ext()  [from ext/extinit.c]
  ↓
├─ init(Init_socket, "socket") → if (Init_socket) ruby_init_ext("socket.so", Init_socket)
├─ init(Init_zlib, "zlib") → if (Init_zlib) ruby_init_ext("zlib.so", Init_zlib)
├─ init(Init_mbedtls, "mbedtls") → if (Init_mbedtls) ruby_init_ext("mbedtls.so", Init_mbedtls)
...
  ↓
ruby_init_ext():
  - Calls Init_socket() → initializes Socket module
  - SHOULD call rb_provide("socket.so") → marks extension as loaded
  - Adds "socket.so" to $LOADED_FEATURES

Later:
User: require 'socket'
  ↓
Ruby: Check if 'socket.so' in $LOADED_FEATURES
  ↓ (found!)
Ruby: Return immediately (already loaded)
```

**Characteristics:**
- ✅ Single portable binary
- ✅ No `.so` files needed
- ✅ Works across all platforms
- ✅ Can still use dlopen for user-installed gems (theoretically)
- ❌ Larger binary (all extensions included)
- ❌ Must rebuild Ruby to add/remove extensions

## CosmoRuby's Implementation

### Configuration

**File:** `include/ruby/config.h`
```c
#define HAVE_DLOPEN 1           // dlopen() IS available
// Note: We do NOT define --disable-dln
// We do NOT define --with-static-linked-ext explicitly
```

**Why `HAVE_DLOPEN = 1`?**
- Cosmopolitan DOES provide `dlopen()` (from `libc/dlopen/`)
- Some Ruby code checks `defined?(HAVE_DLOPEN)` for feature detection
- We compile `dln.c` (full version), not `dmydln.c` (stub version)
- **However**, we pre-load all extensions statically, so `dlopen()` is rarely called

### Extension Registration

**File:** `ext/extinit.c`
```c
#define init(func, name) {	\
    extern void func(void) __attribute__((weak));	\
    if (func) ruby_init_ext(name".so", func); \
}

void Init_ext(void) {
    init(Init_date_core, "date_core");
    init(Init_digest, "digest");
    init(Init_md5, "digest/md5");
    init(Init_sha1, "digest/sha1");
    init(Init_sha2, "digest/sha2");
    init(Init_etc, "etc");
    init(Init_nonblock, "io/nonblock");
    init(Init_generator, "json/ext/generator");
    init(Init_parser, "json/ext/parser");
    init(Init_mbedtls, "mbedtls");          // ← MbedTLS extension!
    init(Init_monitor, "monitor");
    init(Init_pathname, "pathname");
    init(Init_psych, "psych");               // ← YAML extension (if linked)
    init(Init_socket, "socket");
    init(Init_stringio, "stringio");
    init(Init_zlib, "zlib");
}
```

**Weak Symbol Pattern:**
- `__attribute__((weak))` means symbol may or may not exist
- `if (func)` checks if extension was actually linked
- Only initializes extensions that are compiled into the binary
- **Modular**: Can add/remove extensions without breaking build

### Extension Source Registration

**File:** `ruby.deps.mk`
```makefile
THIRD_PARTY_RUBY_A_SRCS_C = \
    third_party/ruby/array.c \
    # ... core Ruby sources ...
    third_party/ruby/ext/socket/socket.c \           # ← Socket extension
    third_party/ruby/ext/zlib/zlib.c \                # ← Zlib extension
    third_party/ruby/ext/mbedtls/mbedtls.c \          # ← MbedTLS extension
    # ...
```

**Build Integration:**
```makefile
# Extension is compiled into Ruby's static library
$(THIRD_PARTY_RUBY_A): $(THIRD_PARTY_RUBY_A_OBJS)

# Extension linked via ruby.deps.mk
include third_party/ruby/ext/mbedtls/BUILD.mk
```

### The Critical `rb_provide()` Call

**Purpose:** Mark extension as already loaded to prevent `require` from trying to `dlopen()` it.

**Current Status:**

| Extension | `rb_provide()` Status | Location |
|-----------|----------------------|----------|
| socket | ✅ HAS | `ext/socket/socket.c:2108` |
| stringio | ✅ HAS | `ext/stringio/stringio.c:2017` |
| monitor | ✅ HAS | `ext/monitor/monitor.c:257` |
| pathname | ✅ HAS | `ext/pathname/pathname.c:1670` |
| io/console | ✅ HAS | `ext/io/console/console.c:1913` |
| io/wait | ✅ HAS | `ext/io/wait/wait.c:439` |
| ripper | ✅ HAS | `ext/ripper/ripper_init.c:628` |
| **date_core** | ❌ MISSING | Needs to be added |
| **digest** | ❌ MISSING | Needs to be added |
| **digest/md5** | ❌ MISSING | Needs to be added |
| **digest/sha1** | ❌ MISSING | Needs to be added |
| **digest/sha2** | ❌ MISSING | Needs to be added |
| **etc** | ❌ MISSING | Needs to be added |
| **io/nonblock** | ❌ MISSING | Needs to be added |
| **json/ext/generator** | ❌ MISSING | Needs to be added |
| **json/ext/parser** | ❌ MISSING | Needs to be added |
| **mbedtls** | ❌ MISSING | Needs to be added |
| **psych** | ❌ MISSING | Needs to be added (if linked) |
| **zlib** | ❌ MISSING | Needs to be added |

**Why it matters:**
```ruby
# WITHOUT rb_provide("socket.so"):
require 'socket'
→ Not in $LOADED_FEATURES
→ Searches load path for socket.so
→ Tries dlopen("socket.so")
→ May succeed (if .so exists) or fail

# WITH rb_provide("socket.so"):
require 'socket'
→ Found in $LOADED_FEATURES
→ Returns immediately
→ No dlopen attempt
```

## dlopen() Usage Analysis

### Where dlopen() IS Used in CosmoRuby

**1. Modular GC (NOT USED)**
```c
// gc.c:791
#if USE_MODULAR_GC
handle = dlopen(gc_so_path, RTLD_LAZY | RTLD_GLOBAL);
#endif
```
- **Status:** `USE_MODULAR_GC = 0` in config.h
- **Impact:** This code path never executes

**2. Fiddle Extension (Foreign Function Interface)**
```c
// Not statically linked by default
// Allows Ruby code to call arbitrary C functions
```
- **Status:** Not in `extinit.c`, not compiled into binary
- **Impact:** Fiddle requires dlopen at runtime, not included in CosmoRuby

**3. Dynamic Extension Loading (Theoretical)**
```c
// load.c:1175
return (VALUE)dln_load(RSTRING_PTR(path));
```
- **Status:** Code exists, can be called for non-pre-loaded extensions
- **Impact:** Would allow `require` to load `.so` files from filesystem
- **Current behavior:** Only called if extension not in `$LOADED_FEATURES`

### Where dlopen() Is NOT Used (Replaced with Static Linking)

**1. All Core Extensions**
- Socket, Zlib, MbedTLS, Stringio, Monitor, Pathname, etc.
- **Old way:** `dlopen("socket.so")` at `require` time
- **New way:** `ruby_init_ext("socket.so", Init_socket)` at startup

**2. Encoding Libraries**
```c
// enc/enc/encinit.c
#define ENC_DEFINE(name) \
    enc_register_stub(name".so", rb_##name##_encindex); \
    rb_provide(name".so");
```
- **Old way:** Load encoding `.so` files on demand
- **New way:** All encodings statically compiled, registered at startup

**3. Transcoders**
```c
// enc/trans/transdb.c
// All transcoders statically compiled
CALL(trans_single_byte);  // in inits.c
```
- **Old way:** Load transcoder `.so` files on demand
- **New way:** Initialized at startup via `Init_trans_*()` functions

## How to Add a New Statically-Linked Extension

### Step 1: Add Source Files to Build

**File:** `ruby.deps.mk`
```makefile
THIRD_PARTY_RUBY_A_SRCS_C = \
    # ... existing ...
    third_party/ruby/ext/EXTENSION_NAME/file.c
```

### Step 2: Register in extinit.c

**File:** `ext/extinit.c`
```c
void Init_ext(void) {
    // ... existing ...
    init(Init_extension_name, "extension_name");
}
```

### Step 3: Add rb_provide() to Extension

**File:** `ext/EXTENSION_NAME/extension.c`
```c
void Init_extension_name(void) {
    // ... existing initialization ...

    /* Mark extension as already loaded (statically linked) */
    rb_provide("extension_name.so");
}
```

### Step 4: Add Special Compile Flags (if needed)

**File:** `ruby.compile.mk` or extension's `BUILD.mk`
```makefile
o/$(MODE)/third_party/ruby/ext/EXTENSION/file.o: private \
    CFLAGS += -DSPECIAL_FLAG
```

### Step 5: Test

```bash
ruby.com -e "require 'extension_name'; puts ExtensionName::VERSION"
```

## Comparison: Static vs Dynamic Loading

| Aspect | Dynamic (Standard Ruby) | Static (CosmoRuby) |
|--------|------------------------|-------------------|
| **Binary portability** | Platform-specific | Actually Portable |
| **File distribution** | Binary + .so files | Single binary |
| **Load time** | dlopen() overhead | Instant (pre-loaded) |
| **Memory usage** | Loaded on demand | All in memory |
| **Development** | Rebuild .so only | Rebuild entire binary |
| **Gem install** | Native extensions work | Pure Ruby only* |
| **Binary size** | Small + .so files | Large (all included) |
| **dlopen calls** | Many (per require) | Few/none (pre-loaded) |

*With future ZIP dynamic loading, native extensions could work

## Future: Hybrid Approach

### Current Limitation

User-installed gems with native extensions don't work:
```bash
$ gem.com install nokogiri
Building native extensions...
# Would need compiler in ZIP or extract/compile workflow
```

### Planned Solution: ZIP Dynamic Loading

See `RUBY_ZIP_EXTENSION_LOADER.md` for design of:
1. Package `.so` files in ZIP filesystem
2. Extract to `/tmp` on first `require`
3. Call `dlopen()` on extracted file
4. Enable `gem install` for native extension gems

**Architecture:**
```
Core extensions: Static linking (current)
  ↓
User gems: Dynamic loading from ZIP (future)
  ↓
Best of both worlds:
  - Core always available
  - User gems installable
  - Single binary distribution
```

## Key Files Reference

| File | Purpose | CosmoRuby Uses |
|------|---------|----------------|
| `dmyext.c` | Empty Init_ext for dynamic Ruby | ❌ No |
| `dmydln.c` | Stub dln_load that errors | ❌ No |
| `dln.c` | Full dlopen implementation | ✅ Yes (but rarely called) |
| `ext/extinit.c` | Static extension registration | ✅ Yes (our main file) |
| `miniinit.c` | Minimal init for miniruby | ❌ No |
| `load.c` | require implementation | ✅ Yes (unmodified) |
| `ruby.c` | Calls Init_ext() at startup | ✅ Yes (unmodified) |

## Debugging Extension Loading

### Check if Extension is Loaded

```ruby
ruby.com -e 'puts $LOADED_FEATURES.grep(/socket/)'
# Should show: socket.so
```

### Check if Extension Initializer Was Called

```ruby
ruby.com -e 'puts Socket.class'
# Should show: Class
# If error: extension Init function never called
```

### Check if rb_provide() Was Called

```ruby
ruby.com -e '
  $LOADED_FEATURES.delete("socket.so")  # Remove from loaded
  require "socket"                       # Try to load again
  puts "Success"
'
# WITHOUT rb_provide: May try dlopen
# WITH rb_provide: Will re-add to $LOADED_FEATURES
```

### Trace Extension Loading

```bash
ruby.com --verbose -e 'require "socket"' 2>&1 | grep socket
```

## Common Issues

### Issue 1: "cannot load such file -- extension_name"

**Cause:** Extension not in `$LOADED_FEATURES` and `.so` file not found.

**Fix:** Add `rb_provide("extension_name.so")` to Init function.

### Issue 2: Extension initialized twice

**Cause:** Extension called in both `inits.c` and `extinit.c`.

**Fix:** Extensions should ONLY be in `extinit.c`, not `inits.c`.

### Issue 3: Undefined symbol errors at link time

**Cause:** Extension has external dependencies not linked.

**Fix:** Add dependencies to `THIRD_PARTY_RUBY_A_DIRECTDEPS` in BUILD.mk.

### Issue 4: Extension works but gem install fails

**Cause:** Gem tries to compile native extension, no compiler in ZIP.

**Fix:** Either:
1. Use only pure Ruby gems
2. Install gems with native extensions manually (extract, compile, package)
3. Implement ZIP dynamic loader (future)

## Recommendations

### For Adding Core Extensions
1. ✅ **DO** use static linking for core functionality
2. ✅ **DO** add `rb_provide()` to mark as loaded
3. ✅ **DO** use weak symbols in `extinit.c` for modularity
4. ❌ **DON'T** put extensions in `inits.c` (that's for Ruby core classes only)

### For User-Installable Extensions
1. ⏳ **WAIT** for ZIP dynamic loader implementation
2. ⚠️ **DOCUMENT** that native extension gems don't work yet
3. ✅ **RECOMMEND** pure Ruby gems as alternative

### For Build System
1. ✅ **KEEP** `HAVE_DLOPEN = 1` (Cosmopolitan has it)
2. ✅ **USE** `dln.c` not `dmydln.c` (full implementation available)
3. ✅ **COMPILE** extensions into main binary via `ruby.deps.mk`

## Conclusion

CosmoRuby uses **static linking** to achieve portability while maintaining the ability to use `dlopen()` for future dynamic loading of user-installed gems. The key is the `extinit.c` modular registration system combined with `rb_provide()` calls to prevent redundant loading attempts.

This approach gives us:
- ✅ Portable single-binary distribution
- ✅ Fast extension loading (no dlopen overhead for core)
- ✅ Compatibility with Ruby's extension API
- ✅ Path forward for dynamic gem installation

The main tradeoff is larger binary size and the need to rebuild for extension changes, but these are acceptable for a portable Ruby distribution.
