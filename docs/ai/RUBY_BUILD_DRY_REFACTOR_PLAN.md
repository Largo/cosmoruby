# Ruby Build System DRY Refactor Plan

**Status:** Planned (not yet implemented)
**Created:** 2026-01-25

## Problem

There are six Ruby binary targets that share many common dependencies:
- `o//third_party/ruby/ruby` / `ruby.zipless`
- `o//third_party/ruby/irb` / `irb.zipless`
- `o//third_party/ruby/miniruby` / `miniruby.zipless`

Currently, dependencies are repeated across all targets, leading to:
- Confusing "up to date" messages
- Redundant dependency declarations
- Make not understanding what's truly shared vs target-specific

## Current Dependency Structure

**Six final binary targets:**
1. `o/$(MODE)/third_party/ruby/ruby.dbg` - Full Ruby with ZIP load paths
2. `o/$(MODE)/third_party/ruby/ruby.zipless.dbg` - Full Ruby with filesystem paths
3. `o/$(MODE)/third_party/ruby/irb.dbg` - IRB with ZIP load paths
4. `o/$(MODE)/third_party/ruby/irb.zipless.dbg` - IRB with filesystem paths
5. `o/$(MODE)/third_party/ruby/miniruby.dbg` - Minimal bootstrap Ruby with ZIP paths
6. `o/$(MODE)/third_party/ruby/miniruby.zipless.dbg` - Minimal bootstrap Ruby with filesystem paths

**Intermediate binaries (multi-stage linking for export table generation):**
- Each binary has `.pre.dbg`, `.stage1.dbg`, `.stage2.dbg` intermediate versions

### Identified Shared Dependencies

**Common to ALL six final targets:**
- `$(CRT)` - C runtime
- `$(APE_NO_MODIFY_SELF)` - APE loader
- `$(RUBY_LINK_EXT_ARCHIVES)` or `$(MINIRUBY_LINK_EXT_ARCHIVES)` - Extension archives
- `$(RUBY_ALL_ORDER_ONLY)` or `$(MINIRUBY_ALL_ORDER_ONLY)` - Order-only deps
- `ruby.codegen` - Code generation (phony target)
- `ruby.plugins` (conditionally, when `RUBY_EXTSTATIC=0` or `RUBY_SLIM_STATIC=1`)

**Common to ruby and irb (but not miniruby):**
- `$(THIRD_PARTY_RUBY_RUBY_DEPS)` and `$(THIRD_PARTY_RUBY_IRB_DEPS)` - share most libc packages
- `$(RUBY_LINK_EXT_ARCHIVES)` - Full extension set

**Specific to miniruby:**
- `$(THIRD_PARTY_RUBY_MINIRUBY_DEPS)` - Has `LIBC_THREAD` and `LIBC_LOG` but no `LIBC_RUNTIME`
- `$(MINIRUBY_LINK_EXT_ARCHIVES)` - Reduced extension set (only monitor, stringio)

## Proposed Solution: Stamp Files

Create three stamp files representing different dependency groups:

1. `.ruby-core-deps.stamp` - Core Ruby library dependencies (ruby.a + libc packages)
2. `.ruby-full-exts.stamp` - Full extension archives (for ruby/irb)
3. `.miniruby-exts.stamp` - Miniruby extension archives

### Benefits

- Make status messages become meaningful ("ruby-core-deps.stamp is up to date")
- Dependencies declared once, consumed by multiple targets
- Better incremental build understanding

## Implementation Steps

### Step 1: Define Common Dependency Variables (ruby.deps.mk)

Create consolidated lists at the top of `ruby.deps.mk`:

```makefile
# Common libc packages shared by ALL Ruby binaries
RUBY_COMMON_LIBC_DEPS = \
    LIBC_CALLS \
    LIBC_FMT \
    LIBC_INTRIN \
    LIBC_NEXGEN32E \
    LIBC_STDIO \
    LIBC_MEM \
    LIBC_STR \
    LIBC_SYSV

# Additional deps for full ruby/irb (not miniruby)
RUBY_FULL_EXTRA_DEPS = \
    LIBC_RUNTIME

# Additional deps for miniruby
MINIRUBY_EXTRA_DEPS = \
    LIBC_THREAD \
    LIBC_LOG
```

### Step 2: Create Stamp File Rules (new file: ruby.stamps.mk)

```makefile
# Stamp file for core Ruby dependencies
RUBY_CORE_DEPS_STAMP = o/$(MODE)/third_party/ruby/.ruby-core-deps.stamp

$(RUBY_CORE_DEPS_STAMP): \
    $(THIRD_PARTY_RUBY_A) \
    $(call uniq,$(foreach x,$(RUBY_COMMON_LIBC_DEPS),$($(x))))
	@mkdir -p $(@D)
	@touch $@

# Stamp file for full extension archives
RUBY_FULL_EXTS_STAMP = o/$(MODE)/third_party/ruby/.ruby-full-exts.stamp

$(RUBY_FULL_EXTS_STAMP): $(RUBY_LINK_EXT_ARCHIVES) | ruby.codegen ruby.plugins
	@mkdir -p $(@D)
	@touch $@

# Stamp file for miniruby extension archives
MINIRUBY_EXTS_STAMP = o/$(MODE)/third_party/ruby/.miniruby-exts.stamp

$(MINIRUBY_EXTS_STAMP): $(MINIRUBY_LINK_EXT_ARCHIVES) | ruby.codegen
	@mkdir -p $(@D)
	@touch $@
```

### Step 3: Refactor Binary Targets (ruby.link.mk)

Simplify each binary target to depend on stamp files:

```makefile
# Ruby final binary - depends on stamps + target-specific files
o/$(MODE)/third_party/ruby/ruby.dbg: \
    $(RUBY_CORE_DEPS_STAMP) \
    $(RUBY_FULL_EXTS_STAMP) \
    o/$(MODE)/third_party/ruby/ruby.pkg \
    o/$(MODE)/third_party/ruby/ruby.main.o \
    o/$(MODE)/third_party/ruby/ruby_exports.o \
    $(CRT) \
    $(APE_NO_MODIFY_SELF) \
    $(RUBY_ALL_ORDER_ONLY)
	@$(APELINK)

# IRB final binary - same stamps, different main/exports
o/$(MODE)/third_party/ruby/irb.dbg: \
    $(RUBY_CORE_DEPS_STAMP) \
    $(RUBY_FULL_EXTS_STAMP) \
    o/$(MODE)/third_party/ruby/irb.pkg \
    o/$(MODE)/third_party/ruby/irb.main.o \
    o/$(MODE)/third_party/ruby/irb_exports.o \
    $(CRT) \
    $(APE_NO_MODIFY_SELF) \
    $(RUBY_ALL_ORDER_ONLY)
	@$(APELINK)

# Miniruby final binary - uses miniruby-specific stamp
o/$(MODE)/third_party/ruby/miniruby.dbg: \
    $(RUBY_CORE_DEPS_STAMP) \
    $(MINIRUBY_EXTS_STAMP) \
    o/$(MODE)/third_party/ruby/miniruby.pkg \
    o/$(MODE)/third_party/ruby/miniruby.main.o \
    o/$(MODE)/third_party/ruby/miniruby_exports.o \
    $(CRT) \
    $(APE_NO_MODIFY_SELF) \
    $(MINIRUBY_ALL_ORDER_ONLY)
	@$(APELINK)
```

### Step 4: Handle Intermediate Build Stages

The multi-stage linking (pre, stage1, stage2, final) also needs updating:

```makefile
# Phase 1: pre binary (no exports)
o/$(MODE)/third_party/ruby/ruby.pre.dbg: \
    $(RUBY_CORE_DEPS_STAMP) \
    $(RUBY_FULL_EXTS_STAMP) \
    o/$(MODE)/third_party/ruby/ruby.main.o \
    $(CRT) \
    $(APE_NO_MODIFY_SELF) \
    | $(RUBY_YJIT_ORDER_ONLY)
	@$(APELINK)
```

### Step 5: Clean Integration

Add stamp files to clean targets:

```makefile
RUBY_STAMP_FILES = \
    $(RUBY_CORE_DEPS_STAMP) \
    $(RUBY_FULL_EXTS_STAMP) \
    $(MINIRUBY_EXTS_STAMP)

.PHONY: ruby-clean-stamps
ruby-clean-stamps:
	@rm -f $(RUBY_STAMP_FILES)
```

## Edge Cases

### MODE= variations
- Stamp files are under `o/$(MODE)/` so each build mode gets its own stamps
- Correct behaviour - different modes may have different object files

### Clean builds vs incremental
- Clean build: stamps don't exist, all deps rebuilt, stamps created at end
- Incremental: stamps exist, Make checks if deps changed, rebuilds only if needed
- Stamp files use `touch` so their mtime reflects when deps were last verified

### miniruby differences
- Miniruby has different extension set (monitor, stringio only)
- Uses separate `MINIRUBY_EXTS_STAMP` to track this
- Has slightly different libc deps (adds LIBC_THREAD, LIBC_LOG)

### ruby.plugins dependency
Only required when `RUBY_EXTSTATIC=0` or `RUBY_SLIM_STATIC=1`:

```makefile
ifeq ($(RUBY_EXTSTATIC),0)
$(RUBY_FULL_EXTS_STAMP): | ruby.plugins
else ifeq ($(RUBY_SLIM_STATIC),1)
$(RUBY_FULL_EXTS_STAMP): | ruby.plugins
endif
```

## File Changes Required

| File | Change Type | Description |
|------|-------------|-------------|
| `ruby.deps.mk` | Modify | Add common dependency variable lists |
| `ruby.stamps.mk` | Create | New file with stamp file rules |
| `ruby.link.mk` | Modify | Simplify all 6 binary targets + intermediates |
| `BUILD.mk` | Modify | Add `include third_party/ruby/ruby.stamps.mk` |

## Migration Strategy

1. Create `ruby.stamps.mk` with stamp rules
2. Add include in `BUILD.mk`
3. Incrementally update one binary at a time in `ruby.link.mk`
4. Test each change with `make -n` to verify dependency graph
5. Full build test after all changes

## Critical Files

- `third_party/ruby-wip-4.0.0/ruby.link.mk` - Main file to refactor
- `third_party/ruby-wip-4.0.0/ruby.deps.mk` - Where common dependency variables should be defined
- `third_party/ruby-wip-4.0.0/BUILD.mk` - Entry point, needs to include new ruby.stamps.mk
- `third_party/ruby-wip-4.0.0/ruby.compile.mk` - Contains DIRECTDEPS definitions
- `build/rules.mk` - Reference for Cosmopolitan's stamp/ok file patterns
