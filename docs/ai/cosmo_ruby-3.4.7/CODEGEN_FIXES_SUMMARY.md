# Ruby Codegen Fixes Summary

## Issues Fixed

### 1. JSON Circular Dependency
**Problem:** `add_to_manifest.rb` required the `json` library, creating a circular dependency.
**Solution:** Rewrote `add_to_manifest.rb` to use pure Ruby string manipulation instead of the JSON gem.
**File:** `third_party/ruby/tool/add_to_manifest.rb`

### 2. Missing stdlib in RUBYLIB
**Problem:** Codegen scripts couldn't load `fileutils` and other stdlib files.
**Solution:** Added `/lib` directory to all RUBYLIB paths in codegen makefiles.
**Files Modified:** `third_party/ruby-wip-3.4.7/ruby.codegen.mk` (multiple lines)

### 3. RubyGems Loading During Codegen
**Problem:** HOST_RUBY was loading RubyGems by default, causing errors during hermetic build.
**Solution:** Added `--disable=gems` flag to all HOST_RUBY invocations.
**Files Modified:** `third_party/ruby-wip-3.4.7/ruby.codegen.mk` (all HOST_RUBY calls)

## Changes Made to ruby.codegen.mk

### Pattern Applied
All HOST_RUBY calls now use:
```makefile
RUBYLIB=$(abspath $(RUBY_SRCDIR))/lib $(HOST_RUBY) --disable=gems [rest of command]
```

### Specific Lines Modified

1. **Line 37** - `ruby_write_patch` function
2. **Line 41** - `ruby_prepare_encdir` function
3. **Line 50** - `$(RUBY_PATCHDIR)` directory creation
4. **Line 80** - `mkconfig.rb` (rbconfig generation)
5. **Line 90, 119, 130, 148, 169-170, 193, 213, 233, 251, 276, 301, 324** - All `add_to_manifest.rb` calls
6. **Line 147** - `file2lastrev.rb` (revision header)
7. **Line 167-168** - `id2token.rb` and `lrama` (parser generation)
8. **Line 270** - `make_encmake.rb` (encoding makefile)
9. **Line 295** - `configure-ext.mk` generation (extension config)
10. **Line 319** - `exts.mk` generation (extension build makefile)
11. **Line 341** - `ruby.codegen.cleanpatches` target

## Build Status

✅ **Working:**
- Code generation completes successfully
- Ruby binaries build: `ruby`, `irb`, `miniruby`
- All variants build: `.pre.dbg`, exports, final binaries
- Build time: ~9 seconds (fast!)

⚠️ **Known Issue:**
- Segfault in `ruby.codegen.cleanpatches` target (line 341)
- This happens AFTER successful build
- Non-blocking: binaries are still created
- Root cause: Old `o//third_party/ruby/ruby` binary (timestamped 15:51) being used during build
- Workaround: Use system Ruby for initial bootstrap, or ignore the segfault

## Testing

```bash
$ o//third_party/ruby/ruby --version
ruby 3.4.7 (2025-10-08 revision 7a5688e2a2) +PRISM [x86_64-cosmo]

$ RUBYLIB=$PWD/third_party/ruby-wip-3.4.7/lib o//third_party/ruby/ruby --disable=gems -e "require 'fileutils'; puts 'OK'"
OK
```

## Next Steps

To eliminate the segfault:
1. Clean old ruby binary: `rm o//third_party/ruby/ruby`
2. Modify `bin/build_ruby.sh` to use system Ruby for first build:
   ```bash
   if [ ! -x "$COSMO_HOST_RUBY" ]; then
       export HOST_RUBY=/usr/bin/ruby  # Bootstrap with system Ruby
   fi
   ```
3. Rebuild from clean state
4. Second build will use newly-built CosmoRuby for codegen

## Files Modified Summary

- `third_party/ruby/tool/add_to_manifest.rb` - Removed json dependency (47 lines rewritten)
- `third_party/ruby-wip-3.4.7/ruby.codegen.mk` - Added RUBYLIB and --disable-gems (30+ locations)
- `docs/ai/JSON_CIRCULAR_DEPENDENCY_FIX.md` - Complete analysis document
- `docs/ai/CODEGEN_FIXES_SUMMARY.md` - This file
