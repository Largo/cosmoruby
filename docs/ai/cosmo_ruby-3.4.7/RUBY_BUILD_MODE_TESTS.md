# CosmoRuby Build Mode Test Suite

**Created:** 2025-12-28
**Purpose:** Comprehensive test suite to validate build mode behavior

## Overview

The test suite validates that CosmoRuby behaves correctly in each of its three build modes:

1. **Dynamic mode** (EXTSTATIC=0): Extensions loaded via cosmo_plugin from .a archives
2. **Static Slim mode** (EXTSTATIC=1, SLIM_STATIC=1): Extensions baked in, zero-byte stubs in ZIP
3. **Static Bare mode** (EXTSTATIC=1, SLIM_STATIC=0): Extensions baked in, no stubs

## Test Files

- `third_party/ruby-wip-3.4.7/test_build_modes.rb` - Main test script (runs inside Ruby)
- `third_party/ruby-wip-3.4.7/test_all_build_modes.sh` - Shell wrapper to run tests

## Running Tests

### Test Current Build

```bash
cd third_party/ruby-wip-3.4.7
./test_all_build_modes.sh
```

Or run the Ruby test directly:

```bash
ruby.com --disable-gems test_build_modes.rb
```

### Test All Modes

To test all three modes, rebuild with each configuration:

**Dynamic mode:**
```bash
cd third_party/ruby-wip-3.4.7
./cosmo_configure.sh --with-plugin-ext
make -j8
./package_ruby.sh
./test_all_build_modes.sh
```

**Static Slim mode:**
```bash
cd third_party/ruby-wip-3.4.7
./cosmo_configure.sh --with-static-linked-ext --with-slim-static
make -j8
./package_ruby.sh
./test_all_build_modes.sh
```

**Static Bare mode:**
```bash
cd third_party/ruby-wip-3.4.7
./cosmo_configure.sh --with-static-linked-ext --without-slim-static
make -j8
./package_ruby.sh
./test_all_build_modes.sh
```

## What the Tests Check

### 1. Config Consistency
- ✅ DLEXT matches mode (`.a` for dynamic, `.so` for static)
- ✅ EXTSTATIC value is correct
- ✅ SLIM_STATIC value is correct
- ✅ Config values are consistent with each other

### 2. $LOADED_FEATURES Validation
- ✅ **No duplicate entries**
- ✅ **No double registration** (short name + full path for same extension)
- ✅ Built-ins appear as short `.so` names
- ✅ Extensions appear in correct format:
  - Dynamic: full paths only (e.g., `/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.a`)
  - Static: short names only (e.g., `monitor.so`)

### 3. ZIP Filesystem Structure
- ✅ `/zip` exists when expected
- ✅ Extension files in correct state:
  - **Dynamic mode**: actual .a files (size > 0)
  - **Static Slim mode**: zero-byte .so stubs (size = 0)
  - **Static Bare mode**: no extension files at all
- ✅ File sizes make sense

### 4. Extension Functionality
- ✅ Extensions can be loaded
- ✅ Extensions actually work (not just registered)
- ✅ Tests: monitor, pathname, stringio, io/console

### 5. Mode-Specific Expectations

**Dynamic Mode:**
- ✅ EXTSTATIC=0, DLEXT='.a'
- ✅ Actual .a files in /zip/lib/ruby/3.4.0/extensions/
- ✅ Extensions have full paths in $LOADED_FEATURES
- ✅ No zero-byte stubs
- ✅ No double registration

**Static Slim Mode:**
- ✅ EXTSTATIC=1, SLIM_STATIC=1, DLEXT='.so'
- ✅ Zero-byte .so stubs in /zip/lib/ruby/3.4.0/extensions/
- ✅ Extensions have short names in $LOADED_FEATURES
- ✅ No actual extension files (only stubs)

**Static Bare Mode:**
- ✅ EXTSTATIC=1, SLIM_STATIC=0, DLEXT='.so'
- ✅ No extension files in /zip at all
- ✅ Extensions have short names in $LOADED_FEATURES

## Test Output

The test script provides detailed output:

```
================================================================================
CosmoRuby Build Mode Test Suite
================================================================================
Build Mode: Dynamic (plugin mode)
Config Values:
  DLEXT: .a (expected: .a)
  EXTSTATIC: 0
  SLIM_STATIC: 0
================================================================================

TEST: Config consistency
--------------------------------------------------------------------------------
✅ DLEXT is correct for mode

TEST: $LOADED_FEATURES validation
--------------------------------------------------------------------------------
✅ No duplicate entries in $LOADED_FEATURES
📊 Feature breakdown:
   Built-ins (.so, short): 5 (e.g., enumerator.so, fiber.so, rational.so)
   Extensions (full path): 4
   Extensions (short name): 3
     Examples: ripper.a, io/console.a, io/wait.a
   Ruby files: 150
✅ No extensions appearing as BOTH short name and full path

TEST: ZIP filesystem structure
--------------------------------------------------------------------------------
✅ /zip filesystem exists
✅ Extensions directory exists: /zip/lib/ruby/3.4.0/extensions

📁 Extension files in /zip:
   Total files: 7
   Zero-byte stubs: 0
   Actual files: 7

   Actual files (size > 0):
     - x86_64-cosmo/monitor.a (45.2 KB)
     - x86_64-cosmo/pathname.a (123.4 KB)
     - x86_64-cosmo/stringio.a (67.8 KB)
     ...

✅ Found actual extension files (expected for dynamic mode)
✅ No zero-byte stubs (expected for dynamic mode)

TEST: Extension functionality
--------------------------------------------------------------------------------
✅ monitor: functional and verified
✅ pathname: functional and verified
✅ stringio: functional and verified
✅ io/console: functional and verified

TEST: Build mode expectations summary
--------------------------------------------------------------------------------
DYNAMIC MODE expectations:
  ✓ EXTSTATIC=0, DLEXT='.a'
  ✓ Extensions loaded via cosmo_plugin from /zip
  ✓ Actual .a files in /zip/lib/ruby/3.4.0/extensions/
  ✓ Extensions appear with full paths in $LOADED_FEATURES
  ✓ No zero-byte stubs
  ✓ No double registration (short + full path)

✅ Dynamic mode behaving as expected

================================================================================
TEST SUMMARY
================================================================================
Build Mode: Dynamic (plugin mode)
Total Features Loaded: 162
Extensions Tested: 4
================================================================================
✅ ALL TESTS PASSED

No errors detected. Build is behaving as expected.
```

## Expected Results by Mode

### Dynamic Mode (EXTSTATIC=0)

**Config:**
- DLEXT: `.a`
- EXTSTATIC: `0`
- SLIM_STATIC: `0` (ignored)

**$LOADED_FEATURES:**
- Built-ins: `enumerator.so`, `fiber.so`, etc. (short names)
- Extensions: `/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.a` (full paths)
- Ruby wrappers: `/zip/lib/ruby/3.4.0/monitor.rb`
- **No duplicates**

**ZIP Filesystem:**
- Actual .a files in `/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/`
- File sizes > 0 (e.g., monitor.a ~45KB, pathname.a ~120KB)
- No zero-byte stubs

**Extension Loading:**
- Loaded via cosmo_plugin when required
- `rb_provide()` skipped (conditional on EXTSTATIC)

### Static Slim Mode (EXTSTATIC=1, SLIM_STATIC=1)

**Config:**
- DLEXT: `.so`
- EXTSTATIC: `1`
- SLIM_STATIC: `1`

**$LOADED_FEATURES:**
- Built-ins: `enumerator.so`, `fiber.so`, etc. (short names)
- Extensions: `monitor.so`, `pathname.so`, etc. (short names)
- Ruby wrappers: `/zip/lib/ruby/3.4.0/monitor.rb`
- **No duplicates**

**ZIP Filesystem:**
- Zero-byte .so stubs in `/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/`
- File sizes = 0
- Stubs allow require to succeed (already initialized)

**Extension Loading:**
- Pre-initialized via `run_static_ext_init()` during Ruby startup
- `rb_provide()` called (adds short name)
- Wrappers' `require` calls find name already loaded, skip

### Static Bare Mode (EXTSTATIC=1, SLIM_STATIC=0)

**Config:**
- DLEXT: `.so`
- EXTSTATIC: `1`
- SLIM_STATIC: `0`

**$LOADED_FEATURES:**
- Built-ins: `enumerator.so`, `fiber.so`, etc. (short names)
- Extensions: `monitor.so`, `pathname.so`, etc. (short names)
- Ruby wrappers: `/zip/lib/ruby/3.4.0/monitor.rb`
- **No duplicates**

**ZIP Filesystem:**
- No extension files at all
- Extensions directory may not exist

**Extension Loading:**
- Pre-initialized via `run_static_ext_init()` during Ruby startup
- `rb_provide()` called (adds short name)
- Wrappers' `require` calls find name already loaded, skip

## Regression Testing

Run these tests after:
- Changing build mode configuration
- Modifying `rb_provide()` calls in extensions
- Updating `cosmo_configure.sh` or packaging scripts
- Changing `EXTSTATIC` or `SLIM_STATIC` logic
- Adding new extensions

## Known Issues / Expected Warnings

Some extensions (ripper, io/console, io/wait) may appear with short names in dynamic mode if they're loaded very early during Ruby initialization. This is expected behavior and not a bug.

## Troubleshooting

**Test fails with "Binary not found":**
- Build first: `make -j8 o//third_party/ruby/ruby`
- Package: `cd third_party/ruby && ./package_ruby.sh`

**Test reports duplicates:**
- Check if `rb_provide()` is called when it shouldn't be
- Verify EXTSTATIC conditional in Init functions

**Test reports wrong file sizes:**
- Check that packaging script correctly handles SLIM_STATIC flag
- Verify `ruby.plugins.mk` creates stubs vs copies actual files

**Extensions not functional:**
- May indicate linking or initialization issue
- Check that extension is properly registered in `extinit.c`

## See Also

- `LOADED_FEATURES_DOUBLE_REGISTRATION.md` - Background on the double registration bug
- `RUBY_EXTENSION_BUILD_MODES.md` - Detailed explanation of build modes
- `EXTENSIONS_HOW_TO.md` - How to add new extensions
