# mtdeps - Mexican Toaster Dependency Analyzer

**Based on**: `tool/build/mkdeps.c` from Cosmopolitan Libc
**Purpose**: Enhanced dependency analyzer with context-key shim support for Ruby header automation

## Why a Separate Tool?

Rather than modifying Cosmopolitan's core `mkdeps` tool, we created `mtdeps` as a standalone enhancement for the Ruby build automation system. This follows the same pattern as `mtsh` (Mexican Toaster Shell), which is an enhanced version of `cocmd`.

## Enhancements Over Standard mkdeps

### Context-Key Shim Support

When a quoted `#include` fails lookup in the standard header paths, mtdeps synthesizes a context-aware shim path:

```
shims/<sanitized-include>@<sanitized-source>
```

**Sanitization rules**:
- Lowercase all characters
- Keep: `a-z`, `0-9`, `_`, `.`
- Convert `/` → `+`
- Convert `..` → `_dotdot`
- Encode other bytes as `_xx` (hex)

**Example**:
```c
// In third_party/ruby/ext/date/date_core.c
#include "ruby.h"
```

If `ruby.h` isn't found in standard paths, mtdeps looks for:
```
shims/ruby.h@third_party+ruby+ext+date+date_core.c
```

This allows the Ruby build automation to:
1. Create shim files at predictable locations
2. Have shims redirect to the actual header files
3. Avoid polluting the global namespace with bare header names

## Usage

### In Build System

The Ruby automation scripts override the `MKDEPS` variable:

```bash
make MODE=dbg MKDEPS=o/dbg/third_party/mexican_toaster/mtdeps o/dbg/depend
```

### Build mtdeps

```bash
make -j8 o//third_party/mexican_toaster/mtdeps
```

## Integration with Ruby Build Automation

See `docs/ai/MKDEPS_AUTOMATION_SYSTEM.md` for complete documentation of how mtdeps integrates with:
- `bin/automate_mkdeps.sh` - Single iteration of header discovery
- `bin/loop_automate_mkdeps.sh` - Automated loop driver
- `bin/create_shims.sh` - Shim file generation

## Implementation Details

The modifications to mkdeps are minimal and focused:

1. Added `BuildContextEntry()` function to generate shim paths
2. Added `AppendSanitizedComponent()` helper for path sanitization
3. Modified header lookup to try context-key shim before failing

The core mkdeps logic remains unchanged, ensuring compatibility with Cosmopolitan's build system.

## Provenance

- Original: `tool/build/mkdeps.c` from Cosmopolitan Libc
- License: ISC (same as Cosmopolitan)
- Modifications: Context-key shim support added 2025-11-02
- Location: `third_party/mexican_toaster/mtdeps.c`
