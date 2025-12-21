# mkdeps Automation System - Module-Generic Implementation

**Date**: 2025-12-13
**Status**: ✅ WORKING - Fully automated, module-generic
**Context**: Automated header dependency tracking for third-party modules in Cosmopolitan

## Overview

The mkdeps automation system automatically discovers and registers header dependencies for third-party modules (Ruby, Python, Lua, etc.) by:
1. Running mkdeps and capturing errors about missing headers
2. Resolving headers using C header search rules
3. Creating context-keyed shim files to handle include path mismatches
4. Iterating until all dependencies are resolved

**Key Achievement**: Fully generic - works for any module with `--module=NAME` flag.

## Quick Start

```bash
# From repo root:
bin/run_mkdeps_and_shims.sh --module=ruby

# Or manually:
build/bootstrap/automate_mkdeps --module=ruby --truncate  # Clear and restart
build/bootstrap/automate_mkdeps --module=ruby             # Add dependencies
bin/create_shims.sh --module=ruby shims                   # Create shim files
# Repeat until clean
```

## Architecture

### Core Components

1. **`build/bootstrap/automate_mkdeps`** (C binary from `third_party/mexican_toaster/automate_mkdeps.c`)
   - Parses mkdeps errors
   - Resolves headers using C search rules
   - Adds entries to module's deps.mk file
   - Logs actions to stage1 log

2. **`build/bootstrap/mtdeps`** (Enhanced mkdeps from `third_party/mexican_toaster/mtdeps.c`)
   - Standard mkdeps with context-key synthesis
   - Accepts `-P <prefix>` for module-specific shim directories
   - Synthesizes `{module}_shims/SANITIZED_HEADER` for missing includes

3. **`bin/create_shims.sh`**
   - Reads stage1 log
   - Creates shim files with proper include redirects
   - Supports per-header and per-includer strategies

4. **`bin/loop_automate_mkdeps.sh`**
   - Runs automate_mkdeps repeatedly
   - Detects completion (exit code 2)
   - Detects infinite loops (duplicate entries)

5. **`bin/run_mkdeps_and_shims.sh`**
   - Orchestrates: loop → create_shims → loop → ...
   - Stops when mkdeps reports no errors

### Module Configuration

Each module needs:
- `third_party/{module}/{module}.deps.mk` - Contains HDRS/INCS variables
- `third_party/{module}/{module}.pc` (optional) - pkg-config file for include paths

Example for Ruby:
```makefile
# In third_party/ruby/ruby.deps.mk
THIRD_PARTY_RUBY_A_HDRS =\
    internal.h\
    internal/array.h\
    ...

THIRD_PARTY_RUBY_A_INCS =\
    ruby_shims/ruby.h\
    ruby_shims/debug_counter.h\
    ...
```

## The Two-Stage Resolution System

### Stage 1: Hash Table Registration

**Error**: `file.h: path not specified by HDRS/SRCS/INCS make variables (it was included by source.c)`

**What it means**: mkdeps loads all HDRS/SRCS/INCS into a hash table. When it encounters `#include "file.h"`, it looks up `file.h` in the hash table. If not found → Stage 1 error.

**Solution**: Add an entry to HDRS or INCS that matches the include directive exactly.

### Stage 2: File Reading

**Error**: `ruby_shims/ruby.h: No such file or directory`

**What it means**: mkdeps found the entry in Stage 1, but when trying to read the actual file, it doesn't exist.

**Solution**: Create a shim file at that path.

## Context-Keyed Shims

### Why Context Keys?

When `third_party/ruby/array.c` includes `"internal.h"`, mkdeps looks for `internal.h` in its hash table. But many different files might include headers with the same name:
- `array.c` includes `"internal.h"` → `third_party/ruby/internal.h`
- `prism/api_node.c` includes `"internal.h"` → `third_party/ruby/prism/internal.h`

We need different shims for different contexts!

### Shim Strategies

**Per-Header (default)**: One shim per unique header
- Entry: `ruby_shims/internal.h`
- Shim created: `ruby_shims/internal.h` → includes real header
- Simpler, fewer files (~200-400 shims for Ruby)

**Per-Includer**: One shim per (header, includer) pair
- Entry: `ruby_shims/internal.h@third_party+ruby+array.c`
- More granular, more files (~2400 shims for Ruby)
- Original shell script behavior

### Sanitization

Filenames are sanitized to create valid filesystem paths:
- Lowercase everything
- `/` → `+`
- `..` → `_dotdot`
- Non-alphanumeric → `_xx` (hex encoding)

Examples:
- `internal.h` → `internal.h`
- `ruby/encoding.h` → `ruby+encoding.h`
- `../digest.h` → `_dotdot+digest.h`
- `third_party/ruby/include/ruby.h` → `third_party+ruby+include+ruby.h`

### Shim Directory Structure

Module-specific shim directories at repo root:
```
{module}_shims/
  ruby.h              # Shim for "ruby.h"
  debug_counter.h     # Shim for "debug_counter.h"
  ruby+encoding.h     # Shim for "ruby/encoding.h"
  third_party+ruby+include+ruby.h  # Shim for full path
```

### Shim File Format

```c
/* Auto-generated shim for Cosmopolitan Ruby port
 * Target: third_party/ruby/debug_counter.h
 * Included by:
 *   - third_party/ruby/array.c
 *   - third_party/ruby/gc.c
 */
#ifndef __RUBY_SHIMS_DEBUG_COUNTER_H__
#define __RUBY_SHIMS_DEBUG_COUNTER_H__
#include "third_party/ruby/debug_counter.h"
#endif
```

**Note**: Uses quotes `""` not angle brackets `<>` - semantically correct for project headers.

## C Header Resolution

When resolving `#include "file.h"` from `includer.c`:

1. **Includer's directory**: `$(dirname includer)/file.h`
   - Handles relative paths like `#include "../digest.h"`

2. **-I directories in order** (from module.pc or defaults):
   - `.` (repo root) - **CRITICAL** for full-path includes!
   - `third_party/{module}/include`
   - `third_party/{module}`
   - Additional module-specific paths

3. **First match wins** - order matters!

## The HDRS vs INCS Decision

When processing a missing header:

```c
if (includer contains "{module}_shims/") {
    // Includer is a shim, so this is a REAL header
    entry_path = filename;  // Use as-is from #include directive
    target = HDRS;
} else {
    // Includer is real code, create a SHIM
    entry_path = "{module}_shims/" + sanitize(filename);
    target = INCS;
}
```

**Key insight**: When the includer is already a shim file, the header being included is real code, so add it to HDRS using the exact string from the `#include` directive (for hash table matching).

## Critical Implementation Details

### Fix 1: Hash Table Matching

**Bug**: When `is_real_header = true`, code was returning `NormalizePath(found)` (full path) instead of `filename` (include directive string).

**Problem**: mkdeps looks up the exact string from `#include` in its hash table. If we add the full path instead, lookup fails.

**Fix** (in `automate_mkdeps.c` line 672):
```c
if (is_real_header) {
    return strdup(filename);  // Use include directive string, not resolved path
}
```

### Fix 2: Include Path Configuration

**Bug**: `ruby.pc` was missing `-I.` in its Cflags.

**Problem**: When files outside the Ruby module used full paths like `#include "third_party/ruby/include/ruby.h"`, resolution tried:
- `third_party/ruby/include` + `third_party/ruby/include/ruby.h` ✗
- But NOT: `.` + `third_party/ruby/include/ruby.h` ✓

**Fix** (in `ruby.pc` line 14):
```
Cflags: -I. \
        -I${includedir} \
        ...
```

**Why it matters**: Full-path includes are common from files outside the module (e.g., `tool/net/redbean.c` including Ruby headers).

### Fix 3: Shim Include Format

**Bug**: Shims used `#include <path>` (angle brackets).

**Fix**: Changed to `#include "path"` (quotes) - semantically correct for project headers and matches historical documentation.

## Complete Workflow

### Initial Run (from clean state)

```bash
# 1. Clear everything
bin/run_mkdeps_and_shims.sh --module=ruby
```

This will:
1. Truncate HDRS/INCS in deps.mk
2. Remove shims directory
3. Loop:
   - Run automate_mkdeps → finds missing headers → adds to INCS/HDRS
   - Create shims for INCS entries
   - Repeat until mkdeps reports no errors

### Typical Progression

```
Iteration 1: 0 HDRS, 214 INCS, 187 shims created
Iteration 2: 207 HDRS, 299 INCS, 85 more shims
Iteration 3: 283 HDRS, 369 INCS, 70 more shims
Iteration 4: 350 HDRS, 383 INCS, 14 more shims
Iteration 5: mkdeps clean; done.

Final: 350 HDRS, 383 INCS, 352 shim files
```

## Files and Paths

### Source Code
- `third_party/mexican_toaster/automate_mkdeps.c` - Main automation logic (C)
- `third_party/mexican_toaster/mtdeps.c` - Enhanced mkdeps with shim synthesis
- `bin/create_shims.sh` - Shim file generator (Bash)
- `bin/loop_automate_mkdeps.sh` - Iteration driver
- `bin/run_mkdeps_and_shims.sh` - Full orchestration

### Generated Files
- `{module}_shims/*.h` - Shim files at repo root
- `o/{MODE}/automate_mkdeps_{module}_stage1.log` - Detailed log of additions
- `o/{MODE}/mkdeps_output.log` - Full make output for debugging
- `third_party/{module}/{module}.deps.mk` - Updated with HDRS/INCS

### Historical Reference
- `docs/ai/historical/AUTOMATE_MKDEPS_SHELL_ORIGINAL.sh` - Original shell implementation
- `docs/ai/historical/MKDEPS_AUTOMATION_SYSTEM_ORIGINAL.md` - Original docs
- `docs/ai/historical/SHIM_STRATEGY_REFACTOR_PLAN.md` - Strategy design

## Troubleshooting

### Infinite Loop

**Symptom**: Same errors appear repeatedly, nothing added to deps.mk

**Causes**:
1. Resolution failing - check include paths in module.pc
2. Hash table mismatch - ensure HDRS entries match include directives exactly
3. Missing `-I.` - full-path includes won't resolve

**Debug**:
```bash
build/bootstrap/automate_mkdeps --module=ruby 2>&1 | less
# Look for "File not found using C header resolution"
```

### Stage 2 Errors

**Symptom**: "No such file or directory" after Stage 1 succeeds

**Causes**:
1. Shim file not created - check create_shims.sh skip logic
2. Wrong shim path - check sanitization matches between automate_mkdeps and mtdeps

**Debug**:
```bash
# Check what shims exist
ls -la {module}_shims/

# Check what's in stage1 log
tail o/dbg/automate_mkdeps_{module}_stage1.log
```

### Shim Count Mismatch

**Symptom**: More INCS entries than shim files

**Cause**: Per-header mode deduplicates - multiple includers use same shim

**Expected**: Normal! e.g., 383 INCS entries → 352 unique shims

## Extending to Other Modules

To add automation for a new module (e.g., Python):

1. **Create module.pc** (optional but recommended):
```
# third_party/python/python.pc
prefix=third_party/python
includedir=${prefix}/Include

Cflags: -I. \
        -I${includedir} \
        -I${prefix}
```

2. **Run automation**:
```bash
bin/run_mkdeps_and_shims.sh --module=python
```

3. **Module conventions**:
   - deps.mk: `third_party/{module}/{module}.deps.mk`
   - Variables: `THIRD_PARTY_{MODULE}_A_HDRS` / `THIRD_PARTY_{MODULE}_A_INCS`
   - Shims: `{module}_shims/` at repo root

That's it! The system handles the rest.

## Performance Notes

- **Per-header mode**: ~200-400 shims for Ruby, fewer file stats
- **Per-includer mode**: ~2400 shims for Ruby, more granular
- **Build time**: First run ~5-10 iterations, subsequent rebuilds use cached deps.mk
- **Incremental**: Adding new files only processes new dependencies

## Known Limitations

1. **Quotes required**: Shims use `#include "path"` so code must use quotes or have path in -I list
2. **Module isolation**: Each module has its own shims directory (can't share)
3. **Manual triggers**: Need to rerun automation when adding new source files
4. **Static analysis only**: Doesn't handle conditional includes or macro magic

## Success Criteria

Automation completes successfully when:
- `automate_mkdeps` exits with code 2 ("No missing headers found")
- `make o/{MODE}/depend` succeeds without errors
- No Stage 1 or Stage 2 mkdeps errors remain

## Future Improvements

- [ ] Incremental mode: only process new errors, don't truncate
- [ ] Parallel processing: handle multiple modules concurrently
- [ ] Smart regeneration: detect when deps.mk needs updating
- [ ] Build system integration: automatic rerun when needed

## References

- mkdeps source: `tool/build/mkdeps.c` (original) and `third_party/mexican_toaster/mtdeps.c` (enhanced)
- Original shell implementation: `docs/ai/historical/AUTOMATE_MKDEPS_SHELL_ORIGINAL.sh`
- C header search rules: ISO C standard, section 6.10.2
