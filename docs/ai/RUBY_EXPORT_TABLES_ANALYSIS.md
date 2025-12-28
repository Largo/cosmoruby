# Ruby Export Tables Analysis

## Overview

This document analyzes the current export table generation for Ruby binaries and identifies what needs to be added to support dynamic plugin loading for all Ruby executables.

## Current Build Structure

### Binaries Built (from `bin/build_ruby.sh`)

1. **ruby** - Full Ruby with ZIP filesystem support
2. **ruby.zipless** - Ruby with filesystem-only paths (no ZIP)
3. **irb** - Interactive Ruby with ZIP support
4. **irb.zipless** - Interactive Ruby, filesystem-only
5. **miniruby** - Minimal Ruby with ZIP support
6. **miniruby.zipless** - Minimal Ruby, filesystem-only

Each binary is built in two versions:
- `.dbg` - Debug symbols included
- `.com` - Stripped binary (APE format)

## Current Export Table Generation

### What Has Export Tables Now

**File:** `third_party/ruby/ruby.compile.mk:152-153`

```makefile
o/$(MODE)/third_party/ruby/ruby_exports.c:
	@bash third_party/ruby/generate_exports.sh o/$(MODE)/third_party/ruby/ruby.dbg $@

o/$(MODE)/third_party/ruby/ruby_exports.o: o/$(MODE)/third_party/ruby/ruby_exports.c
```

**Linked into:** (from `third_party/ruby/ruby.link.mk`)
- `ruby.dbg` (line 26)
- `ruby.zipless.dbg` (line 52)

### What's Missing Export Tables

**No export tables for:**
- `irb.dbg` (line 91)
- `irb.zipless.dbg` (line 116)
- `miniruby.dbg` (line 184)
- `miniruby.zipless.dbg` (line 158)

## Export Generation Flow

### Build Flow from local-includes.mk

1. **local-includes.mk** includes:
   ```makefile
   include third_party/ruby/BUILD.mk
   ```

2. **third_party/ruby/BUILD.mk** includes (in order):
   ```makefile
   include third_party/ruby/ruby.env.mk      # Environment variables
   include third_party/ruby/ruby.codegen.mk  # Code generation rules
   include third_party/ruby/ruby.deps.mk     # Dependencies, package lists
   include third_party/ruby/ruby.compile.mk  # Compilation rules, CFLAGS
   include third_party/ruby/ruby.link.mk     # Link rules, LDFLAGS
   ```

3. **Export table generation** (ruby.compile.mk):
   - Rule creates `ruby_exports.c` using `generate_exports.sh`
   - Script extracts symbols from `ruby.dbg` with prefixes `rb_|ruby_`
   - On first build (before ruby.dbg exists), creates stub export table
   - After ruby.dbg is linked, real exports are generated

4. **Export table linkage** (ruby.link.mk):
   - `ruby_exports.o` is added as dependency to ruby.dbg
   - Provides symbol table for cosmo_plugin dynamic loader

### How generate_exports.sh Works

```bash
#!/bin/sh
# Usage: generate_exports.sh <ruby.dbg> <output.c>

if test -f "$RUBY_DBG"; then
  # Extract symbols with rb_|ruby_ prefixes from the .dbg file
  EXPORT_PREFIXES="rb_|ruby_" bash third_party/cosmo_plugin/export_symbols.sh "$RUBY_DBG" "$OUTPUT"
else
  # First build: create stub with empty export table
  # Allows linking to succeed before ruby.dbg exists
  printf "/* stub export table until ruby.dbg exists */\n" >"$OUTPUT"
  printf "struct cosmo_export_entry { unsigned name_off; unsigned long long addr; };\n" >>"$OUTPUT"
  # ... more stub code ...
fi
```

## Why Export Tables Are Needed

### Current Static Extension Loading

All Ruby binaries currently use `--whole-archive` to statically link extensions:

```makefile
o/$(MODE)/third_party/ruby/ruby.dbg: private
	LDFLAGS += \
		--whole-archive \
		$(foreach x,$(THIRD_PARTY_RUBY_EXTENSIONS),$($(x)_A)) \
		--no-whole-archive
```

This forces all extension object files to be included in the binary, even if not used.

### Future Dynamic Plugin Loading

With the cosmo_plugin system, extensions will be:
1. Built as separate `.so` files
2. Loaded dynamically at runtime via `dlopen()`
3. Need to call back into Ruby's exported symbols (rb_*, ruby_* functions)

**Export tables provide:**
- Symbol name → address mapping
- Required for dynamic loader to resolve symbols
- Each binary needs its own export table (can't share between binaries)

## What Needs to Be Added

### 1. Export Table Generation for IRB

**Add to `third_party/ruby/ruby.compile.mk`:**

```makefile
# IRB export table generated from linked irb.dbg
o/$(MODE)/third_party/ruby/irb_exports.c:
	@bash third_party/ruby/generate_exports.sh o/$(MODE)/third_party/ruby/irb.dbg $@

o/$(MODE)/third_party/ruby/irb_exports.o: o/$(MODE)/third_party/ruby/irb_exports.c
```

**Add to `third_party/ruby/ruby.link.mk`:**

Line 91: Add `o/$(MODE)/third_party/ruby/irb_exports.o` to irb.dbg dependencies
Line 116: Add `o/$(MODE)/third_party/ruby/irb_exports.o` to irb.zipless.dbg dependencies

### 2. Export Table Generation for Miniruby

**Add to `third_party/ruby/ruby.compile.mk`:**

```makefile
# Miniruby export table generated from linked miniruby.dbg
o/$(MODE)/third_party/ruby/miniruby_exports.c:
	@bash third_party/ruby/generate_exports.sh o/$(MODE)/third_party/ruby/miniruby.dbg $@

o/$(MODE)/third_party/ruby/miniruby_exports.o: o/$(MODE)/third_party/ruby/miniruby_exports.c
```

**Add to `third_party/ruby/ruby.link.mk`:**

Line 184: Add `o/$(MODE)/third_party/ruby/miniruby_exports.o` to miniruby.dbg dependencies
Line 158: Add `o/$(MODE)/third_party/ruby/miniruby_exports.o` to miniruby.zipless.dbg dependencies

### 3. Update .pkg Rules

Each binary's `.pkg` rule needs to include the exports object:

**ruby.link.mk changes:**

```makefile
o/$(MODE)/third_party/ruby/irb.pkg:
    o/$(MODE)/third_party/ruby/irb.main.o
    o/$(MODE)/third_party/ruby/irb_exports.o  # ADD THIS
    $(foreach x,$(THIRD_PARTY_RUBY_IRB_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/third_party/ruby/miniruby.pkg:
    o/$(MODE)/third_party/ruby/miniruby.main.o
    o/$(MODE)/third_party/ruby/miniruby_exports.o  # ADD THIS
    $(foreach x,$(THIRD_PARTY_RUBY_MINIRUBY_DIRECTDEPS),$($(x)_A).pkg)
```

## Verification Steps

After adding export tables:

1. **Clean build:**
   ```bash
   rm -f o//third_party/ruby/*.dbg o//third_party/ruby/*_exports.*
   ```

2. **Build all binaries:**
   ```bash
   bash bin/build_ruby.sh
   ```

3. **Verify export tables generated:**
   ```bash
   ls -lh o//third_party/ruby/*_exports.c
   # Should see: ruby_exports.c, irb_exports.c, miniruby_exports.c
   ```

4. **Check symbol counts:**
   ```bash
   grep -c 'rb_\|ruby_' o//third_party/ruby/ruby_exports.c
   grep -c 'rb_\|ruby_' o//third_party/ruby/irb_exports.c
   grep -c 'rb_\|ruby_' o//third_party/ruby/miniruby_exports.c
   # All should have similar counts (same Ruby symbols)
   ```

5. **Test plugin loading:**
   ```ruby
   # In ruby, irb, or miniruby:
   require 'fiddle'
   # Should work if export tables are correct
   ```

## Build Dependency Graph

```
local-includes.mk
  └─> third_party/ruby/BUILD.mk
        ├─> ruby.env.mk (environment)
        ├─> ruby.codegen.mk (generated code)
        ├─> ruby.deps.mk (SRCS, OBJS, extensions list)
        ├─> ruby.compile.mk (compilation rules)
        │     ├─> ruby_exports.c generation rule
        │     ├─> irb_exports.c generation rule (MISSING)
        │     └─> miniruby_exports.c generation rule (MISSING)
        └─> ruby.link.mk (link rules)
              ├─> ruby.dbg: links ruby_exports.o ✓
              ├─> ruby.zipless.dbg: links ruby_exports.o ✓
              ├─> irb.dbg: needs irb_exports.o ✗
              ├─> irb.zipless.dbg: needs irb_exports.o ✗
              ├─> miniruby.dbg: needs miniruby_exports.o ✗
              └─> miniruby.zipless.dbg: needs miniruby_exports.o ✗
```

## Summary

**Current State:**
- Only `ruby` and `ruby.zipless` have export tables
- `generate_exports.sh` script exists and works correctly
- Export table generation is simple and reusable

**What's Needed:**
- Add export table generation for `irb` and `miniruby`
- Update link rules to include the new export objects
- This enables all Ruby binaries to support dynamic plugin loading

**Implementation Strategy:**
- Copy the ruby_exports pattern for irb and miniruby
- Same script (`generate_exports.sh`) works for all
- Same symbol prefixes (`rb_|ruby_`) for all binaries
- Each binary gets its own export table (required by cosmo_plugin)
