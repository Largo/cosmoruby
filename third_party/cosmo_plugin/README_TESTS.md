# cosmo_plugin Test Suite - Quick Start

## Running Tests

### Run All Tests (Recommended)
```bash
# From repository root
make -f third_party/cosmo_plugin/sanity_test.mk && \
make -f third_party/cosmo_plugin/tls_test.mk
```

### Run Individual Test Suites

**Sanity Tests** (comprehensive functionality tests):
```bash
make -f third_party/cosmo_plugin/sanity_test.mk
```

**TLS Tests** (thread-local storage):
```bash
make -f third_party/cosmo_plugin/tls_test.mk
```

## What Gets Tested

### Sanity Test Suite
- ✓ Plugin loading and unloading
- ✓ Symbol resolution (plugin symbols, libc, host exports)
- ✓ Multi-object archives (cross-object references)
- ✓ Global data access (.data, .bss, .rodata)
- ✓ Calling conventions (multiple arguments)
- ✓ Init function invocation
- ✓ Multiple plugins simultaneously
- ✓ Plugin caching
- ✓ Export table functionality

### TLS Test Suite
- ✓ Thread-local variables
- ✓ Per-thread TLS isolation
- ✓ TLS relocations (TLSGD, TLSDESC, etc.)

## Test Output

### Expected Output (Success)
```
=== cosmo_plugin Sanity Tests ===
Basic plugin: o/default/third_party/cosmo_plugin/test_basic.a
Init plugin:  o/default/third_party/cosmo_plugin/test_init.a

TEST: export table retrieval ... (found 0 exports)  PASS
TEST: basic plugin loading ... PASS
TEST: symbol resolution ... PASS
TEST: cross-object symbol references ... PASS
TEST: global data access and modification ... PASS
TEST: read-only data (.rodata) access ... PASS
TEST: libc symbol resolution from host ... PASS
TEST: calling convention (5+ arguments) ... PASS
TEST: init function invocation ... PASS
TEST: multiple plugins loaded simultaneously ... PASS
TEST: plugin caching (same path loaded twice) ... PASS

=== Summary ===
All tests PASSED
```

### Failure Output
If a test fails, you'll see:
```
TEST: symbol resolution ... FAIL: failed to find basic_add symbol
```

## Build Modes

### Default Mode (Optimized)
```bash
make -f third_party/cosmo_plugin/sanity_test.mk
```

### Debug Mode (For GDB)
```bash
make MODE=dbg -f third_party/cosmo_plugin/sanity_test.mk
gdb o/dbg/third_party/cosmo_plugin/sanity_test
```

## Cleaning Up
```bash
make -f third_party/cosmo_plugin/sanity_test.mk clean
make -f third_party/cosmo_plugin/tls_test.mk clean
```

## Troubleshooting

### "PC32 overflow" Error
This means plugin sections were allocated too far from the main executable. This is a bug in the `MapNear()` allocation strategy. Check:
- Export table location via `cosmo_get_exports()`
- Section allocation hints in `AllocateSections()`

### "undefined symbol" Error
Symbol not found in export table. Check:
- Is the symbol exported from the host?
- Run export generation scripts
- Verify with `objdump -t` on host binary

### Segmentation Fault
Likely relocation error. Debug with:
```bash
objdump -r o/default/third_party/cosmo_plugin/test_basic_plugin.o
```

### Test Hangs
Likely deadlock in threading test. Check:
- TLS allocation
- Thread creation/join logic

## File Organization

```
third_party/cosmo_plugin/
├── cosmo_plugin.h              # Public API
├── cosmo_plugin.c              # Implementation
├── BUILD.mk                    # Main package build file
│
├── tls_plugin.c                # TLS test plugin
├── tls_loader_test.c           # TLS test loader
├── tls_test.mk                 # TLS test Makefile
│
├── test_basic_plugin.c         # Sanity test plugin (basic functions)
├── test_helper_plugin.c        # Sanity test plugin (cross-object refs)
├── test_init_plugin.c          # Sanity test plugin (init function)
├── sanity_test.c               # Sanity test loader
├── sanity_test.mk              # Sanity test Makefile
│
├── TESTING.md                  # Detailed test documentation
└── README_TESTS.md             # This file (quick start)
```

## When to Run These Tests

Run before:
- Committing changes to `cosmo_plugin.c`
- Rebasing Cosmopolitan upstream
- Releasing Ruby builds (Ruby extensions use cosmo_plugin)

## Need More Details?

See `third_party/cosmo_plugin/TESTING.md` for:
- Detailed test coverage
- Architecture notes
- Adding new tests
- Debugging guide
- Known limitations
