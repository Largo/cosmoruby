# cocmd Enhancements

This document describes the enhancements made to Cosmopolitan's `cocmd` shell to support more complex build scripts, particularly for the Ruby port.

## Summary of Changes

**Total code added:** ~150 lines
**Total tests:** 51 tests (all passing)
**Backward compatible:** Yes

### 1. Colon Command (`:`)
**Purpose:** No-op command, commonly used for timestamps and placeholders

**Implementation:**
- Added `:` as a builtin that returns success (exit 0)
- Enables patterns like: `: > timestamp.file`

**Usage:**
```bash
: > file.time          # Create empty file
: && echo "always runs"  # No-op that succeeds
```

### 2. Comment Support (`#`)
**Purpose:** Document recipes and ignore portions of command lines

**Implementation:**
- Added `#` detection in tokenizer
- Skips from `#` to end of line (or end of string)
- Finishes current token before skipping

**Usage:**
```bash
# This is a comment
echo hello # inline comment
```

### 3. Subshell Grouping `()`
**Purpose:** Group commands for precedence control and isolation

**Implementation:**
- Added `(` and `)` handling in tokenizer
- Tracks nesting depth to find matching parentheses
- Forks child process and recursively calls `_cocmd()`
- Returns exit status from subshell

**Usage:**
```bash
(echo hello)                    # Simple grouping
((nested))                      # Nested subshells
(cmd1; cmd2)                    # Multiple commands
true && (echo yes)              # Precedence control
(false || true) && echo success # Complex logic
```

## Code Changes

### Files Modified
- `libc/system/cocmd.c` (~90 lines added)
  - Removed `(` and `)` from unsupported characters
  - Added `ExecuteSubshell()` helper function
  - Added `:` to builtin commands
  - Added `#` comment parsing
  - Added `(` and `)` detection and handling

### New Functions
```c
static int ExecuteSubshell(char *subcmd)
```
Forks a child process and executes the given command string by recursively calling `_cocmd()`.

## Test Coverage

### test_cocmd_features.sh
Tests for `:` and `#` features (7 tests)

### test_cocmd_grouping.sh
Tests for `()` grouping (21 tests)

### test_cocmd_all_features.sh
Comprehensive integration tests (24 tests)

All tests pass successfully.

## Practical Use Cases

### Ruby Build Pattern
Before (workaround):
```makefile
@diff -u file1 file2 > patch || touch patch
```

With grouping:
```makefile
@(diff -u file1 file2 > patch) && rm -f patch || touch patch
```

### Complex Conditionals
```bash
# Without grouping - doesn't work as intended
test -f x && cmd1 || cmd2 && cmd3

# With grouping - explicit precedence
(test -f x && cmd1) || (cmd2 && cmd3)
```

### Directory Isolation
```bash
(cd /tmp && do_something)  # cd doesn't affect parent
pwd  # Still in original directory
```

## Implementation Details

### Re-entrancy
`cocmd` uses global state and is not re-entrant. The `()` implementation works by:
1. Forking a new process
2. Child process gets fresh copy of globals
3. Child calls `_cocmd()` with the substring
4. Parent waits for child and captures exit status

This approach avoids the complexity of making the parser re-entrant.

### Memory Management
The subshell command buffer is limited to 4096 bytes to avoid stack overflow issues. This is sufficient for typical build script usage.

### Error Handling
- Unmatched `(` → exit code 15
- Unmatched `)` → exit code 15
- Subshell command too long → exit code 12

### 4. Command Substitution `` ` ` `` and `$()`
**Purpose:** Capture command output and use it as part of another command

**Implementation:**
- Added `CaptureCommand()` helper (~45 lines)
- Forks child process, captures stdout via pipe
- Strips trailing whitespace/newlines
- Preserves internal newlines (bash-compatible)
- Works in both unquoted and quoted contexts
- No nesting support (simple `strchr` search)

**Usage:**
```bash
echo `date`                    # Backtick syntax
echo $(date)                   # Modern syntax
echo "Today is $(date)"        # In quotes
VAR=$(pwd) && echo $VAR        # Assignment (with &&)
test "$(echo yes)" = "yes"     # In conditionals
```

**Limitations:**
- No nesting: `$(echo $(date))` not supported
- This is intentional for simplicity
- Build scripts rarely need nesting anyway

## Future Enhancements

### Possible additions (not implemented)
1. **Tilde expansion `~`:**
   - Expand `~` to `$HOME`
   - Trivial implementation (~20 lines)

2. **Nested command substitution:**
   - Would require depth tracking
   - Adds complexity for rare use case

## Testing

Run all tests:
```bash
bash libc/system/test_cocmd_all_features.sh        # Core features (24 tests)
bash libc/system/test_cocmd_substitution_final.sh  # Command substitution (27 tests)
```

Individual test suites:
```bash
bash libc/system/test_cocmd_features.sh      # : and # (7 tests)
bash libc/system/test_cocmd_grouping.sh      # () grouping (21 tests)
```

**Total: 51 tests, all passing**

## Compatibility

These enhancements maintain backward compatibility:
- No existing cocmd syntax is changed
- New features gracefully error on syntax violations
- All original cocmd tests continue to pass
