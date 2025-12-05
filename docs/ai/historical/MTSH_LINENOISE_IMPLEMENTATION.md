# mtsh v0.2.0 - Line Editing Implementation

## Summary

Added professional line editing support to mtsh (Mexican Toaster Shell) using linenoise, fixing the issue where Alt-keys and other escape sequences would crash the shell in interactive mode.

## Changes Made

### 1. Version Management (NEW)

Created version headers for all Mexican Toaster tools following semantic versioning:

**Files Created:**
- `third_party/mexican_toaster/mtsh_version.h` - mtsh v0.2.0
- `third_party/mexican_toaster/mtdeps_version.h` - mtdeps v1.0.0
- `third_party/mexican_toaster/rubybean_version.h` - rubybean v1.0.0

Each tool now has independent versioning following semver.org (MAJOR.MINOR.PATCH).

### 2. Line Editing Integration

**Modified Files:**
- `third_party/mexican_toaster/mtsh.c` - Added linenoise include and version header
- `third_party/mexican_toaster/mtsh/entry.inc` - Completely rewrote `InteractiveShell()`
- `third_party/mexican_toaster/BUILD.mk` - Added `THIRD_PARTY_LINENOISE` dependency

**Key Implementation Details:**

The `InteractiveShell()` function now has two modes:

1. **TTY Mode (isatty(0) == true)**: Uses linenoise for full line editing
   - Arrow keys (← → for navigation, ↑ ↓ for history)
   - Backspace/Delete
   - Home/End keys
   - Command history persistence (`linenoiseWithHistory`)
   - Separate history files: "mtsh" and "mtsh-toast"
   - Proper escape sequence handling
   - Version displayed in welcome message

2. **Non-TTY Mode (pipes/redirection)**: Falls back to simple char-by-char reading
   - Maintains compatibility with scripts and automation
   - No overhead from line editing when not needed

### 3. Version Display

Modified files to include version information:
- `third_party/mexican_toaster/mtsh.c` - Shows version in file overview
- `third_party/mexican_toaster/mtdeps.c` - Shows version in --version output
- `third_party/mexican_toaster/rubybean.c` - Includes version header

### 4. Build System Updates

**third_party/mexican_toaster/BUILD.mk**:
- Added `THIRD_PARTY_LINENOISE` to `THIRD_PARTY_MEXICAN_TOASTER_DIRECTDEPS`
- Added `mtsh_version.h` as dependency for `mtsh.o`

## Technical Design Decisions

### Why Only Interactive Mode?

The restriction on control characters (including ESC=27) in mtsh/cocmd is **by design**:

- **Non-interactive mode** (Make recipes, `-c "command"`): ESC should never appear in valid shell commands. The error is correct behavior - it catches malformed scripts.

- **Interactive mode**: Users naturally generate ESC sequences via keyboard (Alt-keys, arrow keys). Line editing intercepts these **before** they reach the command parser.

This approach:
- ✅ Keeps script execution fast and minimal
- ✅ Provides professional UX for interactive use
- ✅ Maintains backward compatibility
- ✅ Zero impact on automation/Make recipes

### Why linenoise?

- Already available in Cosmopolitan (`third_party/linenoise/`)
- BSD licensed (compatible with project)
- Battle-tested (used in `examples/linenoise.c`)
- Simple API (`linenoiseWithHistory()` replaces ~20 lines of raw input)
- Full feature set (history, editing, escape handling)
- Small footprint (~1000 LOC total)

## Version History

### mtsh 0.2.0 (this release)
- Integrated linenoise for line editing in interactive mode
- Arrow keys, backspace, history support
- Proper escape sequence handling (fixes Alt-key crashes)
- Version headers and display
- Non-interactive mode unchanged

### mtsh 0.1.0 (e1401d183c)
- Initial release based on cocmd
- Enhanced features: subshells, command substitution, `command -v`
- Toast mode for containerization
- Fixed redirection handling

### mtdeps 1.0.0 (e1401d183c)
- Initial release based on mkdeps
- Context-key shim support for Ruby header automation

### rubybean 1.0.0 (e1401d183c)
- Initial release based on Redbean
- Ruby/Rack integration

## Testing

To test the fix:

```bash
# Build mtsh
make -j1 o//third_party/mexican_toaster/mtsh.com

# Test interactive mode
o//third_party/mexican_toaster/mtsh.com

# Try pressing:
#   - Alt-a (should no longer crash)
#   - Arrow keys (should navigate/recall history)
#   - Backspace (should delete characters)
#   - Ctrl-D (clean exit)

# Test caboose toast mode
o//third_party/mexican_toaster/caboose.com toast
# Same keyboard tests as above
```

## Files Modified

### New Files (4):
- third_party/mexican_toaster/mtsh_version.h
- third_party/mexican_toaster/mtdeps_version.h
- third_party/mexican_toaster/rubybean_version.h
- MTSH_LINENOISE_IMPLEMENTATION.md (this file)

### Modified Files (5):
- third_party/mexican_toaster/BUILD.mk
- third_party/mexican_toaster/mtsh.c
- third_party/mexican_toaster/mtsh/entry.inc
- third_party/mexican_toaster/mtdeps.c
- third_party/mexican_toaster/rubybean.c

## Breaking Changes

None - all changes are backward compatible. Non-interactive mode behavior is identical to v0.1.0.

## Future Enhancements

Potential improvements for future versions:
- Tab completion support (linenoise provides hooks)
- Customizable key bindings
- Multiline editing for complex commands
- Syntax highlighting hints
- Integration with shell history across sessions

## Credits

- linenoise library by Salvatore Sanfilippo
- Based on cocmd by Justine Tunney
- Mexican Toaster Shell enhancements
