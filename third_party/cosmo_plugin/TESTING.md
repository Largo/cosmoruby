# cosmo_plugin Testing Documentation

## Overview

The `cosmo_plugin` system provides position-independent archive loading for Cosmopolitan binaries. This document describes the test infrastructure designed to validate the dynamic loading implementation, especially the fixes for proper memory allocation and relocation handling.

## Test Suites

### 1. TLS Test (`tls_test.mk`)

**Purpose:** Validate Thread-Local Storage (TLS) support in plugins.

**Test Coverage:**
- TLS variable allocation and initialization
- Per-thread TLS isolation (main thread vs spawned threads)
- TLS relocations (TLSGD, TLSDESC, GOTTPOFF, TPOFF)
- Cross-thread TLS independence

**Files:**
- `tls_plugin.c` - Plugin with `__thread` variables
- `tls_loader_test.c` - Loader that spawns threads and validates TLS isolation

**Run:**
```bash
make -f third_party/cosmo_plugin/tls_test.mk
```

### 2. Sanity Test Suite (`sanity_test.mk`)

**Purpose:** Comprehensive validation of core plugin loading functionality.

**Test Coverage:**

#### Plugin Loading & Symbol Resolution
- ✓ **Basic loading:** Load a simple `.a` archive
- ✓ **Symbol lookup:** Resolve exported symbols via `cosmo_plugin_sym()`
- ✓ **Plugin caching:** Second load of same path returns cached handle

#### Multi-Object Archives
- ✓ **Cross-object references:** Plugin object files can call functions in other objects within the same archive
- ✓ **Archive parsing:** Properly handle both GNU and BSD `.a` formats

#### Relocation & Memory Layout
- ✓ **PC32 relocations:** Verify sections allocated within ±2GB of main executable
- ✓ **GOTPCREL relocations:** Verify GOT allocated within ±2GB range
- ✓ **PLT stubs:** Test far function calls use PLT correctly
- ✓ **Data sections:** `.data` and `.bss` properly allocated and accessible
- ✓ **Read-only data:** `.rodata` sections accessible and write-protected

#### Symbol Resolution Chain
- ✓ **Libc symbols:** Plugin can call standard library functions (e.g., `strlen`)
- ✓ **Host exports:** Plugin can resolve symbols from main executable's export table
- ✓ **Plugin symbols:** Plugin objects can find symbols in other plugin objects

#### Calling Conventions
- ✓ **Multiple arguments:** Functions with 5+ arguments work correctly (tests register spilling)
- ✓ **Return values:** Proper ABI compliance

#### Init Functions
- ✓ **Init invocation:** `init_name` parameter calls specified init function
- ✓ **No-init loading:** Loading without init_name works correctly

#### Multiple Plugins
- ✓ **Simultaneous loading:** Multiple plugins can be loaded and used concurrently
- ✓ **Independent state:** Each plugin maintains independent global data

#### Export Table
- ✓ **Export retrieval:** `cosmo_get_exports()` returns valid table
- ✓ **Weak symbol handling:** Works on hosts without export tables

**Files:**
- `test_basic_plugin.c` - Plugin with various function types and data access patterns
- `test_helper_plugin.c` - Helper object for cross-object reference testing
- `test_init_plugin.c` - Plugin with `Init_*` function
- `sanity_test.c` - Comprehensive test loader

**Run:**
```bash
make -f third_party/cosmo_plugin/sanity_test.mk
```

## Key Implementation Details Tested

### Memory Allocation Strategy

The recent fixes ensure that plugin sections, GOT, and PLT are allocated within ±2GB of the main executable's exports. This is critical because:

1. **PC32 relocations** use 32-bit signed displacement (±2GB range)
2. **GOTPCREL relocations** use RIP-relative addressing with 32-bit displacement
3. **PLT32 relocations** require reachability or use indirect jumps

The tests verify this by:
- Loading plugins compiled with `-fPIC` (generates PC32/GOTPCREL relocations)
- Calling functions across object boundaries (triggers relocations)
- Accessing global data (triggers GOT-based access)

### MapNear() Strategy

The `MapNear()` function allocates memory near a specific anchor address:
- Tries addresses within ±1.75GB of anchor in 16MB steps
- Uses `MAP_FIXED_NOREPLACE` to avoid overwriting existing mappings
- Falls back to unrestricted allocation if all near attempts fail

Tests validate this indirectly by ensuring relocations succeed.

### PLT Stub Generation

For far calls (>2GB away), the loader generates PLT stubs:
```asm
jmp *0x0(%rip)    # 6 bytes: FF 25 00 00 00 00
<8-byte target>   # Target address
```

The sanity tests call functions from the plugin, which may trigger PLT usage if the linker decides functions are too far apart.

### GOT Allocation

The GOT is allocated using `MapNear()` with a hint based on the first export address. This ensures GOTPCREL relocations work correctly.

Tests verify GOT functionality by:
- Accessing global variables (may use GOT)
- Calling libc functions (uses GOT for position-independent access)

## Test Architecture

### Test Plugin Design

The test plugins are intentionally simple but exercise key features:

1. **test_basic_plugin.c:**
   - Simple functions (arithmetic)
   - Global data access (read/write)
   - String constants (.rodata)
   - Libc calls (tests host symbol resolution)
   - Cross-object calls (tests intra-archive linking)

2. **test_helper_plugin.c:**
   - Provides functions called by test_basic_plugin
   - Validates that archives with multiple `.o` files work

3. **test_init_plugin.c:**
   - Has an `Init_*` function
   - Validates init function calling

### Test Loader Design

The `sanity_test.c` loader uses a simple test framework:
- Each test is a separate function returning 0 (pass) or 1 (fail)
- Tests are isolated (load/unload plugins per test)
- Clear pass/fail output with diagnostic messages

## Adding New Tests

To add a new test:

1. **Add test function to `sanity_test.c`:**
   ```c
   static int test_my_feature(const char *plugin_path) {
     TEST("my feature description");

     struct cosmo_plugin *p = cosmo_load_plugin(plugin_path, NULL, NULL);
     ASSERT(p != NULL, "failed to load");

     // Test logic here

     cosmo_unload_plugin(p);
     PASS();
   }
   ```

2. **Call test from `main()`:**
   ```c
   failures += test_my_feature(basic_path);
   ```

3. **If needed, add new plugin features:**
   - Edit `test_*_plugin.c` files
   - Rebuild: `make -f third_party/cosmo_plugin/sanity_test.mk clean all`

## Known Limitations

### Current Test Gaps

1. **Architecture-specific tests:** Tests currently run on host architecture only
   - Aarch64-specific relocation handling not explicitly tested
   - Could add arch-conditional test cases

2. **Error path testing:** Limited negative test coverage
   - Should test: invalid archives, missing symbols, corrupt ELF files
   - Should test: out-of-memory conditions, mapping failures

3. **Stress testing:** No tests for:
   - Very large plugins (>100MB)
   - Many plugins (>100 loaded simultaneously)
   - Deep symbol resolution chains

4. **Unloading:** Currently tests basic unload but not:
   - Unload while TLS blocks allocated
   - Unload with outstanding function calls
   - Memory leak validation

### Future Test Ideas

- **Relocation overflow testing:** Artificially create scenarios where PC32 would overflow (requires special linking)
- **Export table exhaustive test:** Create host with large export table, verify all symbols resolve
- **Thread safety:** Concurrent plugin loading from multiple threads
- **Weak symbol resolution:** Test `STB_WEAK` symbols (currently in LookupLibc but not explicitly tested)

## Debugging Failed Tests

### Common Failure Modes

1. **"PC32 overflow" error:**
   - Plugin sections allocated too far from exports
   - Check `MapNear()` logic
   - Verify export table location with `cosmo_get_exports()`

2. **"undefined symbol" error:**
   - Symbol not in export table
   - Check export generation scripts
   - Verify symbol is actually exported from host

3. **Segmentation fault:**
   - Relocation applied incorrectly
   - Check relocation type handling in `ApplyRelocations()`
   - Use `objdump -r plugin.o` to see what relocations are expected

4. **TLS-related failures:**
   - TLS template not loaded correctly
   - Check `LoadTlsTemplate()` logic
   - Verify TLS relocations with `objdump -r`

### Debug Workflow

1. **Build with debug symbols:**
   ```bash
   make MODE=dbg -f third_party/cosmo_plugin/sanity_test.mk
   ```

2. **Run under GDB:**
   ```bash
   gdb o/dbg/third_party/cosmo_plugin/sanity_test
   (gdb) run o/dbg/third_party/cosmo_plugin/test_basic.a ...
   ```

3. **Inspect relocations:**
   ```bash
   objdump -r o/default/third_party/cosmo_plugin/test_basic_plugin.o | less
   ```

4. **Check export table:**
   Enable debug output in `cosmo_plugin.c` (re-add `fprintf` statements) to see:
   - Export table construction
   - Symbol lookup attempts
   - Relocation application

## Integration with CI/CD

These tests should be run:
- Before committing changes to `cosmo_plugin.c`
- After rebasing Cosmopolitan upstream changes
- Before releasing new Ruby builds (since Ruby uses cosmo_plugin for extensions)

**Recommended test command:**
```bash
# Run both test suites
make -f third_party/cosmo_plugin/tls_test.mk && \
make -f third_party/cosmo_plugin/sanity_test.mk
```

## References

- `third_party/cosmo_plugin/cosmo_plugin.h` - Public API
- `third_party/cosmo_plugin/cosmo_plugin.c` - Implementation
- `docs/ai/COSMO_PLUGIN_SYSTEM*.md` - Design documentation
- ELF specification: https://refspecs.linuxfoundation.org/elf/elf.pdf
- x86-64 psABI: https://gitlab.com/x86-psABI/x86-64-ABI
