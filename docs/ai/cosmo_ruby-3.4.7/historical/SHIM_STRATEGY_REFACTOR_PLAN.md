# Shim Strategy Refactor Plan

**STATUS: COMPLETED (2025-12-06)**
**IMPLEMENTED: Per-Includer and Per-Header strategies**
**REMOVED: Monolithic strategy (fundamentally flawed, see note below)**

## Overview
Refactor the Ruby dependency automation system to support two different shim generation strategies via command-line flag, with Per-Header as the default.

## Background
Currently, the system creates one shim file per (header, includer) pair, resulting in 2,476 shim files. Many of these are duplicates pointing to the same target header. We support two strategies:

1. **Per-Includer Shims**: One shim per (header, includer) pair (original behavior)
2. **Per-Header Shims** (default): One shim per unique target header, with comments listing includers

## Note on Monolithic Strategy
An earlier version included a "monolithic" strategy (single shim with all headers), but this was removed because:
- Header inclusion order matters; bulk includes cause compilation errors
- Discovery stops after first iteration, missing transitive dependencies
- The approach is fundamentally incompatible with incremental dependency resolution

## Files to Modify

### 1. `third_party/ruby-wip-3.4.7/automate_mkdeps.c`
**Changes needed:**
- Add command-line flag parsing for `--per-includer`, `--per-header`, `--monolithic`
- Add enum for shim strategy: `SHIM_STRATEGY_PER_INCLUDER`, `SHIM_STRATEGY_PER_HEADER`, `SHIM_STRATEGY_MONOLITHIC`
- Default to `SHIM_STRATEGY_PER_HEADER`
- Modify `ENTRY_PATH` generation based on strategy:
  - Per-Includer: `shims/FILENAME@INCLUDER` (current behavior)
  - Per-Header: `shims/FILENAME` (no includer suffix)
  - Monolithic: `shims/ruby_headers.h` (always the same)
- Update stage1 log format to include strategy information
- Modify `BatchAppendEntries()` to deduplicate INCS entries for per-header and monolithic modes
- Update `--info` output to show current strategy

**Specific sections to modify:**
- Line ~100: Add global variable for strategy
- Line ~600-650: Add flag parsing in `main()`
- Line ~1014-1020: Modify `ENTRY_PATH` calculation based on strategy
- Line ~1033-1040: Stage1 log writing (includer field still needed for per-header comments)
- Line ~470-530: `BatchAppendEntries()` needs deduplication logic for INCS

### 2. `bin/create_shims.sh`
**Changes needed:**
- Read strategy from stage1 log header
- Three different code paths for creating shims:

**Per-Includer mode:**
- Current behavior: create `shims/FILENAME@INCLUDER` files
- One file per log entry

**Per-Header mode:**
- Parse all log entries first, group by FULLPATH
- For each unique FULLPATH, create one shim file
- Shim file header includes comments listing all includers
- Template:
```c
/* Auto-generated shim for Cosmopolitan Ruby port
 * Target: third_party/ruby/include/ruby/internal/attr/nonnull.h
 * Included by:
 *   - third_party/ruby/include/ruby/internal/intern/select/largesize.h
 *   - third_party/ruby/include/ruby/internal/intern/select/win32.h
 *   - third_party/ruby/include/ruby/internal/intern/select/posix.h
 */
#ifndef __RUBY_INTERNAL_ATTR_NONNULL_H__
#define __RUBY_INTERNAL_ATTR_NONNULL_H__
#include "third_party/ruby/include/ruby/internal/attr/nonnull.h"
#endif
```

**Monolithic mode:**
- Create single `shims/ruby_headers.h` file
- Include all unique FULLPATH targets
- NO comments about includers (simplest implementation)
- Template:
```c
/* Auto-generated monolithic shim for Cosmopolitan Ruby port */
#ifndef __RUBY_HEADERS_H__
#define __RUBY_HEADERS_H__

#include "third_party/ruby/include/ruby/internal/attr/nonnull.h"
#include "third_party/ruby/include/ruby/internal/attr/pure.h"
/* ... all other headers ... */

#endif
```

### 3. Stage1 Log Format
**Current format:**
```
FILENAME|INCLUDER|LIST|ENTRY_PATH|FULLPATH
```

**Proposed changes:**
- Add header line indicating strategy:
```
# Shim Strategy: per-header
# Generated: 2025-12-06 13:45:23
# Fields: FILENAME|INCLUDER|LIST|ENTRY_PATH|FULLPATH
```

- For per-header mode, ENTRY_PATH would be the same for multiple entries with same FULLPATH
- For monolithic mode, ENTRY_PATH would always be `shims/ruby_headers.h`

## Implementation Steps

### Step 1: Add Command-Line Flag Parsing to automate_mkdeps.c
- [ ] Add `enum ShimStrategy` type (around line 100)
- [ ] Add global `g_shim_strategy` variable (default: `SHIM_STRATEGY_PER_HEADER`)
- [ ] Add flag parsing in `main()` (around line 600-650):
  ```c
  if (!strcmp(argv[i], "--per-includer")) {
    g_shim_strategy = SHIM_STRATEGY_PER_INCLUDER;
  } else if (!strcmp(argv[i], "--per-header")) {
    g_shim_strategy = SHIM_STRATEGY_PER_HEADER;
  } else if (!strcmp(argv[i], "--monolithic")) {
    g_shim_strategy = SHIM_STRATEGY_MONOLITHIC;
  }
  ```
- [ ] Update `--help` output to document new flags

### Step 2: Modify ENTRY_PATH Generation
- [ ] Create `GenerateEntryPath()` function that takes strategy into account:
  ```c
  static char *GenerateEntryPath(const char *filename, const char *includer, ShimStrategy strategy) {
    switch (strategy) {
      case SHIM_STRATEGY_PER_INCLUDER:
        return FormPath("shims/", filename, "@", includer, NULL);
      case SHIM_STRATEGY_PER_HEADER:
        return FormPath("shims/", filename, NULL);
      case SHIM_STRATEGY_MONOLITHIC:
        return strdup("shims/ruby_headers.h");
    }
  }
  ```
- [ ] Replace current ENTRY_PATH generation (line ~1014-1020) with call to this function

### Step 3: Add Stage1 Log Header
- [ ] Write header lines when creating new stage1 log:
  ```c
  const char *strategy_name =
      g_shim_strategy == SHIM_STRATEGY_PER_INCLUDER ? "per-includer" :
      g_shim_strategy == SHIM_STRATEGY_PER_HEADER ? "per-header" :
      "monolithic";
  fprintf(f, "# Shim Strategy: %s\n", strategy_name);
  fprintf(f, "# Generated: [timestamp]\n");
  fprintf(f, "# Fields: FILENAME|INCLUDER|LIST|ENTRY_PATH|FULLPATH\n");
  ```

### Step 4: Implement INCS Deduplication
- [ ] Modify `BatchAppendEntries()` to track unique ENTRY_PATH values
- [ ] For per-header and monolithic modes, only add each unique ENTRY_PATH once to INCS list
- [ ] Keep all entries in stage1 log (needed for per-header shim comments)
- [ ] Implementation approach:
  ```c
  // In BatchAppendEntries, add deduplication check
  static bool IsEntryPathInIncs(const char *entry_path, const char *incs_content) {
    // Check if entry_path already exists in INCS list
    // Return true if found, false otherwise
  }

  // Only append if not duplicate (for per-header/monolithic modes)
  if (g_shim_strategy == SHIM_STRATEGY_PER_INCLUDER ||
      !IsEntryPathInIncs(entry_path, current_incs_content)) {
    // Append to INCS
  }
  ```

### Step 5: Update create_shims.sh for Per-Header Mode
- [ ] Add strategy detection (read from log header line 1)
- [ ] Implement per-header grouping logic:
  ```bash
  # Read strategy from log header
  STRATEGY=$(grep "^# Shim Strategy:" "$STAGE1_LOG" | cut -d: -f2 | tr -d ' ')

  if [ "$STRATEGY" = "per-header" ]; then
    # First pass: collect all entries by FULLPATH
    declare -A FULLPATH_TO_INCLUDERS
    declare -A FULLPATH_TO_ENTRY_PATH

    while IFS='|' read -r FILENAME INCLUDER LIST ENTRY_PATH FULLPATH; do
      [[ "$FILENAME" =~ ^# ]] && continue
      [ -z "$ENTRY_PATH" ] && continue
      [[ "$ENTRY_PATH" == third_party/ruby/* ]] && continue

      # Append includer to list
      if [ -z "${FULLPATH_TO_INCLUDERS[$FULLPATH]}" ]; then
        FULLPATH_TO_INCLUDERS[$FULLPATH]="$INCLUDER"
      else
        FULLPATH_TO_INCLUDERS[$FULLPATH]="${FULLPATH_TO_INCLUDERS[$FULLPATH]}|$INCLUDER"
      fi
      FULLPATH_TO_ENTRY_PATH[$FULLPATH]="$ENTRY_PATH"
    done < "$STAGE1_LOG"

    # Second pass: create one shim per FULLPATH
    for FULLPATH in "${!FULLPATH_TO_INCLUDERS[@]}"; do
      ENTRY_PATH="${FULLPATH_TO_ENTRY_PATH[$FULLPATH]}"
      INCLUDERS="${FULLPATH_TO_INCLUDERS[$FULLPATH]}"
      # Create shim with includer comments...
    done
  fi
  ```

### Step 6: Update create_shims.sh for Monolithic Mode
- [ ] Detect monolithic strategy from log header
- [ ] Collect all unique FULLPATH values
- [ ] Create single `shims/ruby_headers.h` with all includes
- [ ] NO includer comments (simplest implementation):
  ```bash
  if [ "$STRATEGY" = "monolithic" ]; then
    echo "Creating monolithic shim: shims/ruby_headers.h"
    mkdir -p shims

    # Collect all unique FULLPATH entries
    UNIQUE_HEADERS=$(awk -F'|' '!/^#/ && NF>=5 {print $5}' "$STAGE1_LOG" | sort -u)

    # Create monolithic shim
    cat > shims/ruby_headers.h <<EOF
  /* Auto-generated monolithic shim for Cosmopolitan Ruby port */
  #ifndef __RUBY_HEADERS_H__
  #define __RUBY_HEADERS_H__

  EOF

    # Add all includes
    while IFS= read -r FULLPATH; do
      echo "#include \"$FULLPATH\"" >> shims/ruby_headers.h
    done <<< "$UNIQUE_HEADERS"

    cat >> shims/ruby_headers.h <<EOF

  #endif
  EOF
  fi
  ```

### Step 7: Testing
- [ ] Test per-includer mode (should match current behavior):
  ```bash
  o//third_party/ruby/automate_mkdeps --truncate --per-includer
  o//third_party/ruby/automate_mkdeps --per-includer
  bin/create_shims.sh shims
  # Should create ~2476 shim files
  ```

- [ ] Test per-header mode (new default):
  ```bash
  o//third_party/ruby/automate_mkdeps --truncate --per-header
  o//third_party/ruby/automate_mkdeps --per-header
  bin/create_shims.sh shims
  # Should create ~few hundred shim files
  # Verify includer comments in shim files
  ```

- [ ] Test monolithic mode:
  ```bash
  o//third_party/ruby/automate_mkdeps --truncate --monolithic
  o//third_party/ruby/automate_mkdeps --monolithic
  bin/create_shims.sh shims
  # Should create 1 shim file
  # Verify no includer comments
  ```

- [ ] Test default behavior (should be per-header):
  ```bash
  o//third_party/ruby/automate_mkdeps --truncate
  o//third_party/ruby/automate_mkdeps
  bin/create_shims.sh shims
  # Should match per-header mode
  ```

- [ ] Verify Ruby still builds with each mode:
  ```bash
  make -j1 o//third_party/ruby/ruby
  ```

### Step 8: Update Documentation
- [ ] Update `automate_mkdeps.c` help text with new flags
- [ ] Update any relevant docs in `docs/ai/` about the shim system
- [ ] Add comments explaining the three strategies

## Expected Outcomes

### Per-Includer Mode
- Files: ~2476 shim files
- INCS entries: ~2547
- Behavior: Identical to current system

### Per-Header Mode (Default)
- Files: ~few hundred shim files (one per unique target header)
- INCS entries: ~few hundred (deduplicated)
- Behavior: Same functionality, much fewer files, includer tracking via comments

### Monolithic Mode
- Files: 1 shim file (`shims/ruby_headers.h`)
- INCS entries: 1
- Behavior: All headers included everywhere (less granular but simplest)
- NO includer comments (simplest implementation)

## Rollback Plan
If issues arise, can always revert to per-includer mode:
```bash
o//third_party/ruby/automate_mkdeps --truncate --per-includer
o//third_party/ruby/automate_mkdeps --per-includer
bin/create_shims.sh shims
```

## Notes
- The stage1 log format remains backward compatible (just adds header comments)
- All three strategies can coexist; switch with `--truncate` and flag
- Per-header mode provides best balance of simplicity and granularity
- Monolithic mode is simplest to implement (no includer comment tracking needed)
