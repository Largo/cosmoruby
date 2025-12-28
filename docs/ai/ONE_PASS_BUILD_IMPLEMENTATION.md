# One-Pass Build Implementation for Ruby Export Tables

## Summary

Fixed two issues:
1. **Spurious error in export_symbols.sh** - Fixed incorrect quoting causing temp file not found warnings
2. **Two-pass build requirement** - Implemented phased build system for one-pass clean builds

## Changes Made

### 1. Fixed export_symbols.sh Warning

**File:** `third_party/cosmo_plugin/export_symbols.sh:79-81`

**Before:**
```bash
echo "generated $(wc -l <\"$tmpnames\") symbols to $OUT"
```

**After:**
```bash
# Count symbols before temp file cleanup
symbol_count=$(wc -l <"$tmpnames" 2>/dev/null || echo "unknown")
echo "generated $symbol_count symbols to $OUT"
```

**Result:** No more spurious "No such file or directory" warnings.

### 2. Implemented Three-Phase Build System

The circular dependency problem was:
- `ruby.dbg` depends on `ruby_exports.o`
- `ruby_exports.o` depends on `ruby_exports.c`
- `ruby_exports.c` needs `ruby.dbg` to extract symbols ❌ CIRCULAR!

**Solution:** Build in explicit phases without circular dependencies

#### Phase 1: Build `.pre.dbg` without exports

```makefile
o/$(MODE)/third_party/ruby/ruby.pre.dbg:
    $(THIRD_PARTY_RUBY_RUBY_DEPS)
    o/$(MODE)/third_party/ruby/ruby.main.o
    $(EXTENSIONS)
    $(CRT)
    $(APE_NO_MODIFY_SELF)
	@$(APELINK)
```

- Does NOT depend on `.pkg` (which includes exports)
- Does NOT include `ruby_exports.o`
- Links successfully without export table

#### Phase 2: Generate exports from `.pre.dbg`

```makefile
o/$(MODE)/third_party/ruby/ruby_exports.c: o/$(MODE)/third_party/ruby/ruby.pre.dbg
	@bash third_party/ruby/generate_exports.sh $< $@
```

- Depends on `.pre.dbg` (no circular dependency!)
- Extracts real symbols from fully-linked binary
- No stubs needed

#### Phase 3: Build final `.dbg` with exports

```makefile
o/$(MODE)/third_party/ruby/ruby.dbg:
    $(THIRD_PARTY_RUBY_RUBY_DEPS)
    o/$(MODE)/third_party/ruby/ruby.pkg      # includes ruby_exports.o
    o/$(MODE)/third_party/ruby/ruby.main.o
    o/$(MODE)/third_party/ruby/ruby_exports.o
    $(EXTENSIONS)
    $(CRT)
    $(APE_NO_MODIFY_SELF)
	@$(APELINK)
```

- Links with real export table
- Final binary has complete exports for dynamic loading

### 3. Applied to All Ruby Binaries

Same three-phase build implemented for:
- ✅ `ruby` & `ruby.zipless`
- ✅ `irb` & `irb.zipless`
- ✅ `miniruby` & `miniruby.zipless`

Each gets:
- `.pre.dbg` - Phase 1 binary without exports
- `_exports.c` - Generated from `.pre.dbg`
- `.dbg` - Final binary with exports

## Build Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                  One-Pass Clean Build                       │
└─────────────────────────────────────────────────────────────┘

make o//third_party/ruby/ruby
  │
  ├─> Phase 1: Build ruby.pre.dbg
  │    └─> Links: ruby.main.o + ruby.a + extensions
  │        Result: o//third_party/ruby/ruby.pre.dbg
  │
  ├─> Phase 2: Generate exports
  │    └─> Run: generate_exports.sh ruby.pre.dbg → ruby_exports.c
  │        Result: o//third_party/ruby/ruby_exports.c (REAL symbols)
  │
  └─> Phase 3: Build final ruby.dbg
       └─> Links: ruby.main.o + ruby.a + ruby_exports.o + extensions
           Result: o//third_party/ruby/ruby.dbg (with export table)
```

## Benefits

### Before (Two-Pass Build)
```bash
make -j1 o//third_party/ruby/ruby  # Pass 1: stub exports
make -j1 o//third_party/ruby/ruby  # Pass 2: real exports
```

Problems:
- Required running make twice
- First build had stub export tables
- Confusing for developers
- Easy to forget second pass

### After (One-Pass Build)
```bash
make -j1 o//third_party/ruby/ruby  # Single pass: real exports
```

Benefits:
- ✅ Single make invocation
- ✅ No circular dependencies
- ✅ Real exports on first build
- ✅ No stub generation needed
- ✅ Cleaner dependency graph
- ✅ Works from `make clean`

## Technical Details

### Breaking the Circular Dependency

**Key insight:** The `.pre.dbg` binary contains all the same symbols as the final `.dbg`, just without the export table itself. We can extract symbols from `.pre.dbg` to create the export table, then link that table into the final `.dbg`.

**Why this works:**
1. Ruby's exported symbols come from Ruby core code, not from the export table
2. The `.pre.dbg` binary has all `rb_*` and `ruby_*` functions fully linked
3. The export table is just metadata - it doesn't define new symbols
4. Therefore: symbols in `.pre.dbg` == symbols in final `.dbg`

### Optimization: Shared Exports

For `miniruby` and `miniruby.zipless`:
```makefile
# Both variants share the same exports (identical Ruby core)
o/$(MODE)/third_party/ruby/miniruby_exports.c: o/$(MODE)/third_party/ruby/miniruby.pre.dbg
	@bash third_party/ruby/generate_exports.sh $< $@
```

- Only `miniruby.pre.dbg` is used to generate exports
- `miniruby.zipless.pre.dbg` is built but doesn't generate exports
- Both final binaries link the same `miniruby_exports.o`
- Saves build time (only extract symbols once)

### Make Dependencies

The dependency chain is now:
```
ruby.pre.dbg
  └─> ruby_exports.c
       └─> ruby_exports.o
            └─> ruby.dbg
```

No cycles! Make can resolve this in one pass.

## Files Modified

1. **third_party/cosmo_plugin/export_symbols.sh**
   - Lines 79-81: Fixed temp file counting

2. **third_party/ruby/ruby.compile.mk**
   - Lines 150-168: Updated export generation rules to use `.pre.dbg` files

3. **third_party/ruby/ruby.link.mk**
   - Lines 22-56: Added ruby.pre.dbg phase
   - Lines 108-139: Added irb.pre.dbg phase
   - Lines 192-278: Added miniruby/miniruby.zipless.pre.dbg phases

## Verification

After clean build (`make clean`), verify one-pass build:

```bash
# Clean
rm -rf o//third_party/ruby/*.dbg o//third_party/ruby/*_exports.*

# Build in one pass
make -j1 o//third_party/ruby/ruby

# Verify
ls -lh o//third_party/ruby/*.pre.dbg          # Should exist
ls -lh o//third_party/ruby/*_exports.c        # Should have real symbols
grep -c '\\0"$' o//third_party/ruby/ruby_exports.c  # Should show ~2700+ symbols
```

Expected: All binaries build successfully with real export tables in one make invocation.

## Future Enhancements

Possible optimizations:
1. **Reuse .pre.dbg files**: If Ruby core hasn't changed, could reuse existing `.pre.dbg`
2. **Parallel phase builds**: Build ruby.pre.dbg, irb.pre.dbg, miniruby.pre.dbg in parallel
3. **Incremental exports**: Only regenerate exports if symbols changed
4. **Export caching**: Cache symbol extraction results

But current implementation is simple, correct, and fast enough.

## Status

✅ Implemented and tested
✅ No circular dependencies
✅ One-pass clean build
✅ Real exports on first build
✅ All six Ruby binaries supported
✅ Ready for dynamic plugin loading integration
