# mkdeps Automation System for Ruby Headers

**Date**: 2025-11-02
**Status**: Stage 1 working, Stage 2 pending
**Context**: Automating Ruby header dependency tracking for Cosmopolitan build system

## Overview

The mkdeps tool analyzes C source files to track header dependencies. For Ruby, we have ~hundreds of headers that need to be registered. Manual registration is impractical, so we built an automation system.

## The mkdeps Two-Stage Resolution System

### Stage 1: Hash Table Registration
**Error**: `file.h: path not specified by HDRS/SRCS/INCS make variables (it was included by source.c)`

**What it means**: mkdeps loads all files from HDRS/SRCS/INCS into an internal hash table during initialization. When scanning source files, it looks up `#include` directives in this hash table. If not found → Stage 1 error.

**Solution**: Add the filename **as it appears in the #include directive** to `THIRD_PARTY_RUBY_A_HDRS` in `third_party/ruby/ruby.deps.mk`.

**Example**:
```c
// In third_party/ruby/ext/date/date_core.c
#include "ruby.h"
```
Add to deps.mk:
```makefile
THIRD_PARTY_RUBY_A_HDRS =\
    ruby.h
```

### Stage 2: File Reading
**Error**: `third_party/ruby/include/ruby.h: No such file or directory`

**What it means**: mkdeps found the header in Stage 1 (in the hash table), but when trying to read the actual file to scan its dependencies, it doesn't exist at that path.

**Why this happens**: mkdeps runs from the repository root. The header is registered as `ruby.h` (from the `#include`), but the actual file is at `third_party/ruby/include/ruby.h`.

**Solution**: Create a **shim** file at the registered path that redirects to the actual file location.

**Example**: Create `ruby.h` in repo root:
```c
/* Auto-generated shim for Cosmopolitan Ruby port */
#ifndef __RUBY_H__
#define __RUBY_H__
#include "third_party/ruby/include/ruby.h"
#endif
```

## The Automation Scripts

### 1. `bin/strip_ruby_hdrs.sh`
**Purpose**: Clear all entries from HDRS and INCS to start fresh.

**Usage**:
```bash
bin/strip_ruby_hdrs.sh
```

**What it does**:
- Empties `THIRD_PARTY_RUBY_A_HDRS` in `third_party/ruby/ruby.deps.mk`
- Empties `THIRD_PARTY_RUBY_A_INCS` in `third_party/ruby/ruby.deps.mk`
- Leaves just the variable declarations: `HDRS =` and `INCS =`

### 2. `bin/automate_mkdeps.sh`
**Purpose**: ONE iteration of finding and adding missing headers.

**How it works**:

1. **Cleans dependency files**: `rm -f o/$MODE/{srcs,hdrs,incs}.txt`

2. **Runs mkdeps**: `make MODE=$MODE -j1 o/$MODE/depend`

3. **Parses errors**: Looks for "path not specified by HDRS/SRCS/INCS" errors

4. **For each missing header**:
   - **Resolves using C header resolution**:
     1. Try includer's directory: `$(dirname includer)/$FILENAME`
     2. Try `-I` directories in order (from `ruby.compile.mk`):
        - `third_party/ruby/include`
        - `third_party/ruby`
        - `third_party/ruby/prism`
        - `third_party/ruby/enc/unicode/15.0.0`
        - `third_party/zlib`

   - **Adds to HDRS**:
     - Filename as it appears in `#include`: `ruby.h`
     - Adds to `THIRD_PARTY_RUBY_A_HDRS` in deps.mk

   - **Logs for shim creation**:
     - Format: `FILENAME|INCLUDER|HDRS|ENTRY_PATH|FULLPATH`
     - Example: `ruby.h|third_party/ruby/ext/date/date_core.c|THIRD_PARTY_RUBY_A_HDRS|ruby.h|third_party/ruby/include/ruby.h`
     - Appends to `o/$MODE/automate_mkdeps_stage1.log`

5. **Exits**:
   - Exit 0 if headers were added or no errors found
   - Exit 1 if file not found (indicates broken code or missing -I path)

### 3. `bin/loop_automate_mkdeps.sh`
**Purpose**: Run `automate_mkdeps.sh` repeatedly until completion or stuck.

**Stops when**:
1. `automate_mkdeps.sh` exits non-zero (error)
2. Duplicate consecutive entry detected (stuck in loop)
3. Max iterations (500) reached

**Duplicate detection**: Checks `o/$MODE/automate_mkdeps_stage1.log` for same entry twice in a row.

**Usage**:
```bash
bin/loop_automate_mkdeps.sh
# Or with different mode:
MODE=opt bin/loop_automate_mkdeps.sh
```

### 4. `bin/create_shims.sh`
**Purpose**: Create shim headers to satisfy Stage 2 file reading.

**Usage**:
```bash
# Preview what will be created
bin/create_shims.sh

# Actually create the shims
bin/create_shims.sh shims
```

**How it works**:
- Reads `o/$MODE/automate_mkdeps_stage1.log`
- For each entry where `ENTRY_PATH` doesn't start with `third_party/ruby/`:
  - Creates directory if needed: `mkdir -p $(dirname ENTRY_PATH)`
  - Creates shim file at `ENTRY_PATH`:
    ```c
    #ifndef __GUARD__
    #define __GUARD__
    #include "FULLPATH"
    #endif
    ```

**Example**:
```bash
# Log entry:
# ruby.h|...|HDRS|ruby.h|third_party/ruby/include/ruby.h

# Creates shim at repo root: ruby.h
#ifndef __RUBY_H__
#define __RUBY_H__
#include "third_party/ruby/include/ruby.h"
#endif
```

## C Header Resolution Rules

For `#include "file.h"` (double quotes), the compiler searches:

1. **Current directory of source file**: If `source.c` is in `foo/bar/`, try `foo/bar/file.h`
   - This handles relative paths: `#include "../digest.h"` resolves to parent directory

2. **-I directories in ORDER**: Try each `-I` path until found
   - Order matters! First match wins

For `#include <file.h>` (angle brackets):
- Only searches system/standard library paths
- mkdeps doesn't error on these (handled by Cosmopolitan)

## Complete Workflow

### Initial Setup
```bash
# 1. Strip existing HDRS/INCS
bin/strip_ruby_hdrs.sh

# 2. Run Stage 1 automation (populates HDRS)
bin/loop_automate_mkdeps.sh
```

**Expected output**: Loop runs multiple iterations, each adding more headers to `THIRD_PARTY_RUBY_A_HDRS`. Eventually completes with no Stage 1 errors.

**Result**:
- `third_party/ruby/ruby.deps.mk` has populated `THIRD_PARTY_RUBY_A_HDRS`
- `o/dbg/automate_mkdeps_stage1.log` has all discovered headers with their full paths

### Stage 2: Shim Creation
```bash
# 3. Preview shims to be created
bin/create_shims.sh

# 4. Create the shims
bin/create_shims.sh shims

# 5. Run loop again (should hit Stage 2 errors or complete)
bin/loop_automate_mkdeps.sh
```

**Expected**: mkdeps can now read files via shims, discovers more headers nested inside.

**Loop continues**: More Stage 1 errors for headers included BY the shimmed headers.

### Iteration
Repeat until one of:
1. **Success**: No more mkdeps errors, `o/dbg/depend` generated successfully
2. **Stage 2 blocker**: A file truly doesn't exist (need manual intervention)
3. **Stuck**: Same error repeating (indicates code bug or missing -I path)

## Key Files

### Source Files
- `bin/strip_ruby_hdrs.sh` - Clear HDRS/INCS
- `bin/automate_mkdeps.sh` - Single iteration of automation
- `bin/loop_automate_mkdeps.sh` - Loop driver
- `bin/create_shims.sh` - Shim generation

### Generated Files
- `third_party/ruby/ruby.deps.mk` - Contains `THIRD_PARTY_RUBY_A_HDRS` and `THIRD_PARTY_RUBY_A_INCS`
- `o/$MODE/automate_mkdeps_stage1.log` - Log of all headers added (used by create_shims.sh)
- `o/$MODE/mkdeps_output.log` - Full make output from each iteration
- Shim files: `ruby.h`, `ruby/encoding.h`, etc. (created in repo root)

### Config Files
- `third_party/ruby/ruby.compile.mk` - Source of truth for `-I` paths (lines ~24-25)
- `third_party/ruby/ruby.deps.mk` - Contains HDRS/INCS/SRCS (lines ~87-90)

## Current State (as of 2025-11-02)

**Stage 1**: ✅ Working correctly
- Loop runs without infinite loops
- Finds files using C header resolution
- Adds to HDRS correctly
- Logs for shim creation

**Stage 2**: ⏳ Pending
- Shim creation tested and working
- Need to run full loop with shims to discover Stage 2 issues
- Expected blocker: TBD (user knows what it is, not documented yet)

**HDRS entries** (example of what's populated):
```makefile
THIRD_PARTY_RUBY_A_HDRS =\
    ruby.h\
    ruby/encoding.h\
    ruby/util.h\
    ruby/re.h\
    ruby/ruby.h\
    ../digest.h\
    ...
```

**INCS entries**: Currently empty (shims handle file location)

## Troubleshooting

### Infinite Loop
**Symptom**: Same file processed repeatedly, loop never advances.

**Causes**:
1. File not found → add missing `-I` path to INCLUDE_PATHS in `automate_mkdeps.sh`
2. "Already exists" check broken → verify regex in line ~184
3. Not logging entry → verify Stage1_LOG append happens

**Fix**: Check `o/dbg/automate_mkdeps_stage1.log` for duplicates. Loop script should detect and stop.

### File Not Found Error
**Symptom**: Script exits with "File not found using C header resolution"

**Causes**:
1. Typo in `#include` directive (broken Ruby code)
2. Missing `-I` path in `ruby.compile.mk` or `automate_mkdeps.sh` INCLUDE_PATHS
3. File truly doesn't exist

**Fix**:
```bash
# Check what was searched
cat o/dbg/mkdeps_output.log

# Find the actual file
find third_party/ruby -name "filename.h"

# If found, add its parent directory to INCLUDE_PATHS
```

### Script Won't Continue
**Symptom**: Loop exits immediately, no progress.

**Causes**:
1. No Stage 1 errors found (success or already complete)
2. Parse error (mkdeps output format changed)
3. Script permissions

**Fix**:
```bash
# Check for Stage 1 errors manually
make MODE=dbg -j1 o/dbg/depend 2>&1 | grep "path not specified"

# Verify script is executable
chmod +x bin/*.sh
```

## Implementation Details

### Why HDRS Not INCS?
Initially tried adding to INCS. Problem: INCS is for `.inc` files (include snippets), HDRS is for `.h` files (headers).

Current approach: Everything goes to HDRS. Shims provide file location indirection.

### Why Shims Instead of Full Paths in INCS?
mkdeps expects the path in HDRS to match the file on disk. If we add `ruby.h` to HDRS but the file is `third_party/ruby/include/ruby.h`, mkdeps can't read it.

Shims solve this: `ruby.h` (shim) includes `third_party/ruby/include/ruby.h` (real file).

### Why Not Add Both Bare and Full Paths?
Tried adding both `ruby.h` and `third_party/ruby/include/ruby.h` to HDRS. Problem: mkdeps finds `ruby.h` in hash table, tries to read `ruby.h` from disk → doesn't exist.

Shims are cleaner: Single HDRS entry + shim file.

## Next Steps

1. **Complete Stage 1**: Let current loop finish (in progress)
2. **Create shims**: Run `bin/create_shims.sh shims`
3. **Stage 2 loop**: Run `bin/loop_automate_mkdeps.sh` again
4. **Hit blocker**: User mentioned a known blocker in Stage 2
5. **Document blocker**: Update this file with Stage 2 blocker details
6. **Continue**: Iterate until mkdeps succeeds

## Historical Context

### Build System Reorg
Scripts were moved from root to `bin/` directory. Updated to calculate `REPO_ROOT` and `cd` there before operating.

### HDRS vs INCS Location
Originally in `third_party/ruby/BUILD.mk`, now in `third_party/ruby/ruby.deps.mk` due to build system modularization.

### Failed Approaches
1. **Adding full paths to INCS**: Didn't solve Stage 1 lookup
2. **Adding both forms to HDRS and INCS**: Created maintenance burden, still needed shims
3. **Using find for all resolution**: Too slow, didn't match C semantics
4. **Ignoring -I order**: Wrong file selected when duplicates exist

### What Finally Worked
Implement exact C header resolution:
1. Source directory first
2. -I directories in order
3. Add bare filename to HDRS
4. Create shims for file location

## References

- mkdeps source: `tool/build/mkdeps.c`
- Ruby compile flags: `third_party/ruby/ruby.compile.mk` lines 20-30
- Ruby dependencies: `third_party/ruby/ruby.deps.mk` lines 87-270
- Main Makefile: `Makefile` lines 397-420 (HDRS/INCS aggregation)

## Contact

If resuming with different AI or after context loss, provide:
1. This document
2. Current contents of `third_party/ruby/ruby.deps.mk` (HDRS section)
3. Last few lines of `o/dbg/automate_mkdeps_stage1.log`
4. Current error from `make MODE=dbg -j1 o/dbg/depend`

## Planned Context-Key Integration

- **mkdeps enhancements**  
  Patch `tool/build/mkdeps.c` so that, when a quoted include still fails lookup, it synthesizes `shims/<sanitize(include)>@<sanitize(source)>` where sanitization lowercases, keeps `a–z 0–9 _.`, maps `/ → +`, converts `..` to `_dotdot`, and encodes any other byte as `_xx`. Successful hits skip the fatal Stage 1 error and later let Stage 2 mmap the shim.

- **Automation rewrite**  
  Refactor `bin/automate_mkdeps.sh` to compute the same sanitized strings, append the context key to `THIRD_PARTY_RUBY_A_HDRS`, and log `ENTRY_PATH` as `shims/include@source` alongside the resolved real header path.

- **Shim generator overhaul**  
  Update `bin/create_shims.sh` to read the new log format, ensure `shims/` exists, and emit guards plus `#include "<real path>"` for each `ENTRY_PATH`, deleting stale shims before regeneration if needed.

- **Verification steps**  
  Rebuild mkdeps, rerun the automation, generate shims, then `make o/$MODE/depend` to confirm both Stage 1 and Stage 2 pass without manual intervention.
