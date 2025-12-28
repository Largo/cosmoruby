# CosmoRuby Build Targets Reference

This document explains the different Ruby build artifacts, what they are, when to use them, and how they differ.

## Quick Reference

| Artifact | Size | Stdlib | Use Case |
|----------|------|--------|----------|
| `ruby.com` | ~15MB | ✅ Embedded | **Distribution** - Give to users |
| `ruby` | ~6MB | ❌ Needs RUBYLIB | **Development** - Testing during build |
| `ruby.dbg` | ~35MB | ❌ Needs RUBYLIB | **Debugging** - Use with gdb |
| `miniruby` | ~6MB | ❌ Minimal | **Build system** - Code generation only |

## Tests and Validation

### Bootstrap Tests (Cosmo-Aware)

Use the wrapper to ensure extension archives are discoverable during bootstrap:

```bash
HOST_RUBY=ruby sh third_party/ruby-wip-3.4.7/cosmo_tests/run_bootstrap.sh
```

Override the target interpreter if needed:

```bash
TARGET_RUBY=$PWD/o/third_party/ruby/ruby.zipless \
  HOST_RUBY=ruby sh third_party/ruby-wip-3.4.7/cosmo_tests/run_bootstrap.sh
```

### Export Table Check

Validate that generated export tables match final binaries:

```bash
HOST_RUBY=ruby sh third_party/ruby-wip-3.4.7/cosmo_tests/check_export_tables.sh
```

### Export Table Check (Binary-Extracted)

Verify the export table embedded in the final binary matches `nm` without
relying on the generated `*_exports.c` file:

```bash
HOST_RUBY=ruby sh third_party/ruby-wip-3.4.7/cosmo_tests/check_export_tables_binary.sh
```

### Plugin Loader Sanity Check

Verify that core extensions load without relocation overflows:

```bash
TARGET_RUBY=$PWD/o/third_party/ruby/ruby.zipless \
  sh third_party/ruby-wip-3.4.7/cosmo_tests/check_plugin_loads.sh
```

### Combined Verification Target

Run all CosmoRuby verification checks (exports + loader sanity):

```bash
make ruby_verify
```

### Missing Artifacts Report

Print missing binaries and extension archives for CosmoRuby:

```bash
make ruby_missing
```

## Extension Modes

Configure extension mode with `cosmo_configure.sh`:
```bash
# Plugin mode (default): extensions loaded from /zip as .a archives
third_party/ruby/cosmo_configure.sh --with-plugin-ext

# Static mode: extensions baked into the executable
third_party/ruby/cosmo_configure.sh --with-static-linked-ext

# Static mode with zero-byte markers for extension paths
third_party/ruby/cosmo_configure.sh --with-static-linked-ext --with-slim-static
```

## The Three Ruby Interpreters

### 1. ruby - Full Ruby Interpreter

**Purpose**: Main Ruby interpreter with all features enabled

**Built by**: `make -j8 o//third_party/ruby/ruby`

**Features**:
- Complete Ruby 3.4.7 language
- Extensions linked or plugin-loaded depending on `cosmo_configure.sh` (EXTSTATIC=1/0)
- Threading, fibers, ractors
- Full stdlib support (when RUBYLIB is set)

**Usage**:
```bash
# Requires RUBYLIB environment variable
RUBYLIB=$PWD/third_party/ruby-wip-3.4.7/lib o//third_party/ruby/ruby script.rb

# Or use the packaged version (no RUBYLIB needed)
o//third_party/ruby/ruby.com script.rb
```

### 2. irb - Interactive Ruby Shell

**Purpose**: Interactive REPL (Read-Eval-Print Loop)

**Built by**: `make -j8 o//third_party/ruby/irb`

**Features**:
- Same as `ruby` but with IRB as the main entry point
- Syntax highlighting, code completion
- Multi-line editing with linenoise

**Usage**:
```bash
# Development version (needs RUBYLIB)
RUBYLIB=$PWD/third_party/ruby-wip-3.4.7/lib o//third_party/ruby/irb

# Packaged version (self-contained)
o//third_party/ruby/irb.com
```

### 3. miniruby - Bootstrap Ruby

**Purpose**: Minimal Ruby for build-time code generation

**Built by**: `make -j8 o//third_party/ruby/miniruby`

**Features**:
- Core Ruby language only
- No gems, no RubyGems
- No encoding support (ASCII only)
- Used by build system to generate:
  - `rbconfig.rb`
  - Encoding tables
  - Builtin method tables

**Limitations**:
- Cannot load extensions
- Cannot require most stdlib files
- Not intended for running user scripts

**Usage**:
```bash
# Only use for build scripts
o//third_party/ruby/miniruby build_script.rb
```

## Build Artifact Types

### Base Executables (No Embedded Stdlib)

```
o//third_party/ruby/ruby           # Stripped binary, ~6MB
o//third_party/ruby/irb            # Stripped binary, ~6MB
o//third_party/ruby/miniruby       # Stripped binary, ~6MB
```

**Characteristics**:
- Stripped of debug symbols (smaller, faster)
- Require `RUBYLIB` environment variable to find stdlib
- Used during development and testing

**When to use**:
- Testing changes during development
- Debugging with custom RUBYLIB paths
- Understanding build process

**Example**:
```bash
# Set RUBYLIB to find the standard library
export RUBYLIB=$PWD/third_party/ruby-wip-3.4.7/lib

# Run Ruby
o//third_party/ruby/ruby -e "puts 'Hello'"

# Run IRB
o//third_party/ruby/irb
```

### Debug Symbols (For Debugging with gdb)

```
o//third_party/ruby/ruby.dbg       # With debug symbols, ~35MB
o//third_party/ruby/irb.dbg        # With debug symbols, ~35MB
o//third_party/ruby/miniruby.dbg   # With debug symbols, ~35MB
```

**Characteristics**:
- Contains full debug information (function names, line numbers, variables)
- Unstripped binaries
- Still require `RUBYLIB` for stdlib

**When to use**:
- Debugging crashes with gdb
- Profiling with perf/callgrind
- Understanding Ruby VM internals

**Example**:
```bash
# Debug a crash
export RUBYLIB=$PWD/third_party/ruby-wip-3.4.7/lib
gdb o//third_party/ruby/ruby.dbg

# Run with gdb
(gdb) run -e "some_code_that_crashes"

# Get backtrace
(gdb) bt
```

### Pre-fixup Debug Symbols

```
o//third_party/ruby/ruby.pre.dbg
o//third_party/ruby/irb.pre.dbg
o//third_party/ruby/miniruby.pre.dbg
```

**Characteristics**:
- Debug symbols before `fixupobj` post-processing
- Rarely needed by users
- Used by build system diagnostics

**When to use**:
- Debugging build system issues
- Understanding fixupobj transformations
- Generally: you don't need these

### Zipless Versions (Testing Convenience)

```
o//third_party/ruby/ruby.zipless
o//third_party/ruby/ruby.zipless.dbg
```

**Characteristics**:
- Identical to base `ruby` and `ruby.dbg`
- Exist as separate targets for Makefile clarity
- Used to verify code works before packaging

**When to use**:
- Makefile explicitly builds these before packaging
- Users typically don't interact with these directly

### Packaged Versions (Distribution) ⭐

```
o//third_party/ruby/ruby.com       # Self-contained, ~15MB
o//third_party/ruby/irb.com        # Self-contained, ~15MB
o//third_party/ruby/miniruby.com   # Self-contained, ~15MB
```

**Characteristics**:
- ✅ **Self-contained** - No RUBYLIB needed
- ✅ **Stdlib embedded** - ZIP filesystem at `/zip/lib/ruby/3.4.0/`
- ✅ **Distribution ready** - Give these to end users
- ✅ **Cross-platform** - Run on Linux, macOS, Windows, BSD

**Created by**:
```bash
cd third_party/ruby
bash package_ruby.sh
```

**What package_ruby.sh does**:
1. Creates directory structure: `o/cosmo-ruby/lib/ruby/3.4.0/`
2. Copies Ruby stdlib from `third_party/ruby-wip-3.4.7/lib/*`
3. Copies terminfo database for terminal support
4. Extracts any existing ZIP content from `/zip/`
5. Creates `o/ruby-stdlib.zip` containing all the above
6. Uses `zipcopy` to embed ZIP into `.com` files

**Example**:
```bash
# No RUBYLIB needed!
./ruby.com -e "puts 'Hello, World!'"

# Works anywhere
./irb.com

# Check what's embedded
unzip -l ruby.com | grep "\.rb$" | head -20
```

## File Size Breakdown

```
Base executable:          ~6MB   (stripped Ruby interpreter)
+ Embedded stdlib:        ~9MB   (all .rb files, terminfo, etc.)
─────────────────────────────────
= Packaged .com file:     ~15MB  (distribution binary)

Debug symbols:            ~29MB  (function names, line info, etc.)
+ Base executable:        ~6MB
─────────────────────────────────
= Debug .dbg file:        ~35MB  (for debugging)
```

## Common Workflows

### End User (Download Binaries)

```bash
# Download ruby.com, irb.com from release
chmod +x ruby.com irb.com

# Use immediately (no installation)
./ruby.com script.rb
./irb.com
```

### Developer (Build from Source)

```bash
# Build Ruby
make -j8 o//third_party/ruby/ruby
make -j8 o//third_party/ruby/irb

# Test with RUBYLIB
export RUBYLIB=$PWD/third_party/ruby-wip-3.4.7/lib
o//third_party/ruby/ruby -e "puts 'test'"

# Package for distribution
cd third_party/ruby
bash package_ruby.sh

# Now test the packaged version
o//third_party/ruby/ruby.com -e "puts 'test'"
```

### Developer (Debug a Crash)

```bash
# Build debug version
make -j8 MODE=dbg o//third_party/ruby/ruby

# Set RUBYLIB
export RUBYLIB=$PWD/third_party/ruby-wip-3.4.7/lib

# Debug with gdb
gdb o/dbg/third_party/ruby/ruby.dbg
(gdb) run script_that_crashes.rb
(gdb) bt
```

## Build Modes

Ruby can be built in different optimization modes:

```bash
# Default mode (optimized with debug info)
make -j8 o//third_party/ruby/ruby

# Debug mode (no optimization, sanitizers)
make -j8 MODE=dbg o//third_party/ruby/ruby

# Optimized mode (maximum optimization)
make -j8 MODE=opt o//third_party/ruby/ruby

# Release mode (no asserts, no debug info)
make -j8 MODE=rel o//third_party/ruby/ruby

# Tiny mode (minimal size)
make -j8 MODE=tiny o//third_party/ruby/ruby
```

**Note**: The packaging script always uses the default mode binary.

## Environment Variables

### RUBYLIB

**Purpose**: Tell Ruby where to find standard library

**Required for**:
- `ruby`, `irb`, `miniruby` (base executables)
- `ruby.dbg`, `irb.dbg`, `miniruby.dbg` (debug versions)

**NOT required for**:
- `ruby.com`, `irb.com`, `miniruby.com` (packaged versions)

**Example**:
```bash
export RUBYLIB=$PWD/third_party/ruby-wip-3.4.7/lib
o//third_party/ruby/ruby -e "require 'json'; puts JSON.generate({a: 1})"
```

### RUBYOPT

**Purpose**: Pass default options to Ruby interpreter

**Example**:
```bash
# Disable RubyGems
export RUBYOPT="--disable-gems"
ruby.com script.rb
```

## Troubleshooting

### "cannot load such file" errors

**Problem**: Base executable can't find stdlib

**Solution**: Set RUBYLIB
```bash
export RUBYLIB=$PWD/third_party/ruby-wip-3.4.7/lib
```

**Or**: Use packaged version
```bash
o//third_party/ruby/ruby.com script.rb
```

### "uninitialized constant" errors

**Problem**: May indicate packaging issue or load order problem

**Diagnosis**:
```bash
# Test without RubyGems
ruby.com --disable-gems -e "puts 'hi'"

# Check what's in the ZIP
unzip -l ruby.com | grep rubygems
```

### Large file sizes

**Expected**:
- Base executables: ~6MB (stripped interpreter)
- Packaged .com files: ~15MB (interpreter + ~9MB stdlib)
- Debug files: ~35MB (interpreter + debug symbols)

**Unexpected**: If files are much larger, check for:
- Build mode (MODE=dbg creates larger binaries)
- Duplicate ZIP content in packaged files

## Related Documentation

- `README.cosmo` - User-facing quickstart guide
- `docs/ai/RUBY_PORT_PROGRESS.md` - Technical porting details
- `EXTENSIONS_HOW_TO.md` - Building C extensions
- `CLAUDE.md` (in repository root) - Developer build instructions
