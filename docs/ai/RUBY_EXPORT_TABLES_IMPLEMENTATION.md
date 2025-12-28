# Ruby Export Tables Implementation - Complete

## Changes Made

All Ruby binaries now have export table generation for dynamic plugin loading support.

### 1. Export Generation Rules Added (ruby.compile.mk)

**Location:** `third_party/ruby/ruby.compile.mk:152-169`

```makefile
# ruby_exports.c (existing)
o/$(MODE)/third_party/ruby/ruby_exports.c:
	@bash third_party/ruby/generate_exports.sh o/$(MODE)/third_party/ruby/ruby.dbg $@

o/$(MODE)/third_party/ruby/ruby_exports.o: o/$(MODE)/third_party/ruby/ruby_exports.c

# irb_exports.c (NEW)
o/$(MODE)/third_party/ruby/irb_exports.c:
	@bash third_party/ruby/generate_exports.sh o/$(MODE)/third_party/ruby/irb.dbg $@

o/$(MODE)/third_party/ruby/irb_exports.o: o/$(MODE)/third_party/ruby/irb_exports.c

# miniruby_exports.c (NEW)
o/$(MODE)/third_party/ruby/miniruby_exports.c:
	@bash third_party/ruby/generate_exports.sh o/$(MODE)/third_party/ruby/miniruby.dbg $@

o/$(MODE)/third_party/ruby/miniruby_exports.o: o/$(MODE)/third_party/ruby/miniruby_exports.c
```

### 2. Link Rules Updated (ruby.link.mk)

All binaries now include their export objects:

**ruby & ruby.zipless:**
- Line 26: `ruby.dbg` includes `ruby_exports.o`
- Line 52: `ruby.zipless.dbg` includes `ruby_exports.o`

**irb & irb.zipless (NEW):**
- Line 84: `irb.pkg` includes `irb_exports.o`
- Line 93: `irb.dbg` includes `irb_exports.o`
- Line 111: `irb.zipless.pkg` includes `irb_exports.o`
- Line 120: `irb.zipless.dbg` includes `irb_exports.o`

**miniruby & miniruby.zipless (NEW):**
- Line 152: `miniruby.zipless.pkg` includes `miniruby_exports.o`
- Line 164: `miniruby.zipless.dbg` includes `miniruby_exports.o`
- Line 180: `miniruby.pkg` includes `miniruby_exports.o`
- Line 192: `miniruby.dbg` includes `miniruby_exports.o`

## Build Process

### First Build (Stub Generation)

When building for the first time, each `*_exports.c` file is generated with a stub export table because the corresponding `.dbg` file doesn't exist yet:

```c
/* stub export table until <binary>.dbg exists */
struct cosmo_export_entry { unsigned name_off; unsigned long long addr; };
const struct cosmo_export_entry __cosmo_exports[] = {{0,0}};
const char __cosmo_exports_names[] = "";
// ... pointer definitions ...
```

This allows the build to succeed and create the `.dbg` files.

### Subsequent Builds (Real Exports)

After the `.dbg` files exist, `generate_exports.sh` extracts real symbols:

```bash
EXPORT_PREFIXES="rb_|ruby_" bash third_party/cosmo_plugin/export_symbols.sh <binary>.dbg <exports>.c
```

This creates a complete export table with all `rb_*` and `ruby_*` symbols.

## Verification Steps

### 1. Clean Build Test

```bash
# Remove existing export files
rm -f o//third_party/ruby/*_exports.c o//third_party/ruby/*_exports.o

# Build all Ruby binaries
bash bin/build_ruby.sh
```

### 2. Verify Export Files Generated

```bash
ls -lh o//third_party/ruby/*_exports.c
```

Expected output:
```
o//third_party/ruby/irb_exports.c
o//third_party/ruby/miniruby_exports.c
o//third_party/ruby/ruby_exports.c
```

### 3. Check Symbol Counts

```bash
echo "Ruby exports:"
grep -c 'rb_\|ruby_' o//third_party/ruby/ruby_exports.c || echo "stub"

echo "IRB exports:"
grep -c 'rb_\|ruby_' o//third_party/ruby/irb_exports.c || echo "stub"

echo "Miniruby exports:"
grep -c 'rb_\|ruby_' o//third_party/ruby/miniruby_exports.c || echo "stub"
```

All three should have similar counts (they export the same Ruby core symbols).

### 4. Verify Binaries Include Exports

```bash
# Check that export symbols are present in binaries
nm o//third_party/ruby/ruby.dbg | grep __cosmo_exports
nm o//third_party/ruby/irb.dbg | grep __cosmo_exports
nm o//third_party/ruby/miniruby.dbg | grep __cosmo_exports
```

Expected: Each should show `__cosmo_exports*` symbols.

### 5. Test Dynamic Loading (Future)

Once cosmo_plugin loader is integrated with Ruby's `require`:

```ruby
# In any Ruby binary (ruby, irb, miniruby)
require 'fiddle'  # Should work with dynamic loading
```

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│                     Build Flow                              │
└─────────────────────────────────────────────────────────────┘

local-includes.mk
  └─> third_party/ruby/BUILD.mk
        ├─> ruby.compile.mk (export generation)
        │     ├─> ruby_exports.c ─> ruby_exports.o
        │     ├─> irb_exports.c ─> irb_exports.o      [NEW]
        │     └─> miniruby_exports.c ─> miniruby_exports.o [NEW]
        │
        └─> ruby.link.mk (binary linking)
              ├─> ruby.dbg + ruby_exports.o
              ├─> ruby.zipless.dbg + ruby_exports.o
              ├─> irb.dbg + irb_exports.o              [NEW]
              ├─> irb.zipless.dbg + irb_exports.o      [NEW]
              ├─> miniruby.dbg + miniruby_exports.o    [NEW]
              └─> miniruby.zipless.dbg + miniruby_exports.o [NEW]

┌─────────────────────────────────────────────────────────────┐
│                Export Table Contents                        │
└─────────────────────────────────────────────────────────────┘

Each export table contains:
  • Symbol names (all rb_* and ruby_* functions)
  • Symbol addresses (resolved at link time)
  • Binary-specific addresses (each binary has unique addresses)

Format: cosmo_plugin compatible export table
  struct cosmo_export_entry {
    unsigned name_off;           // Offset into names string
    unsigned long long addr;     // Symbol address
  };

  __cosmo_exports[]              // Array of entries
  __cosmo_exports_names[]        // Concatenated null-terminated names
  __cosmo_exports_start/end      // Pointers for iteration
  __cosmo_exports_names_start/end // Pointers for name lookup
```

## Next Steps for Plugin Support

Now that all Ruby binaries have export tables, the next phase is:

1. **Modify Ruby's `require` mechanism:**
   - Detect `.so` extension requests
   - Use cosmo_plugin loader instead of static linking
   - Map `dlsym()` to export table lookups

2. **Update extension build system:**
   - Build extensions as separate `.so` files
   - Link against host binary's export table
   - Test with simple extension (e.g., stringio, monitor)

3. **Integration testing:**
   - Verify all extensions load correctly
   - Test in ruby, irb, and miniruby
   - Benchmark performance vs static linking

## Files Modified

1. **third_party/ruby/ruby.compile.mk**
   - Added irb_exports.c generation rule (lines 157-162)
   - Added miniruby_exports.c generation rule (lines 164-169)

2. **third_party/ruby/ruby.link.mk**
   - Added irb_exports.o to irb.pkg (line 84)
   - Added irb_exports.o to irb.dbg (line 93)
   - Added irb_exports.o to irb.zipless.pkg (line 111)
   - Added irb_exports.o to irb.zipless.dbg (line 120)
   - Added miniruby_exports.o to miniruby.zipless.pkg (line 152)
   - Added miniruby_exports.o to miniruby.zipless.dbg (line 164)
   - Added miniruby_exports.o to miniruby.pkg (line 180)
   - Added miniruby_exports.o to miniruby.dbg (line 192)

## Implementation Status

✅ Export table generation for all Ruby binaries
✅ Build system updated and consistent
✅ Reuses existing generate_exports.sh script
✅ No changes to core Cosmopolitan files
✅ Ready for Ruby dynamic plugin loading integration

**Status:** Implementation complete, ready for testing and Ruby integration.
