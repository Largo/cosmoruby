# Cosmopolitan Plugin Export Tables

## Overview

The Cosmopolitan plugin system uses **export tables** to enable dynamic symbol resolution without traditional dynamic linking. Each binary (ruby, irb, miniruby) embeds a table of its exported symbols with their runtime addresses, allowing plugins to resolve symbols at load time.

## Export Table Structure

### Data Layout

The export table consists of two parts stored in the `.rodata.cosmo_exports` section:

1. **String table** (`__cosmo_exports_names`): Null-terminated symbol names packed sequentially
2. **Entry array** (`__cosmo_exports`): Array of `{name_offset, address}` pairs, null-terminated with `{0, 0}`

```c
struct cosmo_export_entry {
    uint32_t name_off;  // Offset into string table
    uint64_t addr;      // Runtime address of symbol
};
```

### Generated Code Structure

The build system generates `{ruby,irb,miniruby}_exports.c` files with this pattern:

```c
// Actual data - STATIC (internal linkage)
static const struct cosmo_export_entry __cosmo_exports[] = {
    { 0, 0x401000 },  // symbol at offset 0
    { 7, 0x402000 },  // symbol at offset 7
    { 0, 0 }          // sentinel
};

static const char __cosmo_exports_names[] =
    "symbol1\0symbol2\0...";

// Exported pointers - PUBLIC (external linkage)
const struct cosmo_export_entry *const __cosmo_exports_start = __cosmo_exports;
const struct cosmo_export_entry *const __cosmo_exports_end =
    __cosmo_exports + (sizeof(__cosmo_exports)/sizeof(__cosmo_exports[0]));

const char *const __cosmo_exports_names_start = __cosmo_exports_names;
const char *const __cosmo_exports_names_end =
    __cosmo_exports_names + sizeof(__cosmo_exports_names);
```

### Consumer Code (cosmo_plugin.c)

```c
// Weak references - if not defined, linker sets address to NULL
extern __attribute__((weak))
const struct cosmo_export_entry *const __cosmo_exports_start;

extern __attribute__((weak))
const struct cosmo_export_entry *const __cosmo_exports_end;

extern __attribute__((weak))
const char *const __cosmo_exports_names_start;

// Usage - check if symbols are defined before accessing
if ((void*)&__cosmo_exports_start != NULL && __cosmo_exports_start != NULL) {
    for (const struct cosmo_export_entry *e = __cosmo_exports_start;
         e < __cosmo_exports_end && e->name_off != 0; e++) {
        // Use export entry
    }
}
```

## Design Rationale

### Why Pointer Indirection?

The export table uses **pointer variables** rather than exporting arrays directly:

**Current Design:**
- Arrays are `static` (internal linkage)
- Pointers to arrays are exported (external linkage)
- Weak NULL pointers provide graceful fallback

**Alternative (Direct Export):**
```c
// Why NOT this?
extern const struct cosmo_export_entry __cosmo_exports[];
```

**Advantages of pointer indirection:**
1. **Data hiding**: Implementation details (array size, layout) are hidden
2. **Bounds checking**: `_start` and `_end` pointers enable safe iteration without scanning for sentinel
3. **Weak fallback**: NULL pointers indicate "no export table" cleanly
4. **Flexibility**: Pointers could theoretically be initialized dynamically

**Disadvantages:**
1. **Garbage collection issues**: Pointer variables are separate objects that can be GC'd independently (see below)
2. **Extra indirection**: One pointer dereference to access data

## The Garbage Collection Problem and Solution

### What is `--gc-sections`?

The linker flag `--gc-sections` performs **garbage collection** on sections:

1. **Mark phase**: Start from entry points (`main`, `-u` symbols) and transitively mark all referenced sections
2. **Sweep phase**: Delete all unmarked sections
3. **Result**: Only reachable code/data remains in the binary

This is essential for Cosmopolitan to produce small binaries (2-6MB instead of 20MB+).

### The Original Problem: Weak Definitions

An earlier approach used **weak definitions** in `cosmo_plugin.c`:

```c
// OLD APPROACH (BROKEN):
__attribute__((weak)) const struct cosmo_export_entry *const __cosmo_exports_start = NULL;
```

This caused export symbols to be garbage collected because **weak definitions satisfy their own references**:

```
Step 1: cosmo_plugin.c uses __cosmo_exports_start
  ↓
Step 2: Linker finds weak definition in cosmo_plugin.o
  ↓
Step 3: Reference satisfied! (weak def satisfies itself)
  ↓
Step 4: Linker never searches irb_exports.o
  ↓
Step 5: .rodata.cosmo_exports section is unmarked
  ↓
Step 6: --gc-sections deletes it
  ↓
Result: Only weak NULL definitions remain in final binary!
```

**Visual representation of the problem:**

```
┌─────────────────────┐
│  cosmo_plugin.o     │
│  - Uses __cosmo_    │ ──weak def──┐
│    exports_start    │             │
└─────────────────────┘             │
                                    ▼
                        ┌──────────────────────┐
                        │ weak definition in   │
                        │ cosmo_plugin.o:      │
                        │ = NULL               │ ◄── Satisfies itself!
                        └──────────────────────┘

┌─────────────────────┐
│  irb_exports.o      │
│  .rodata.cosmo_     │ ◄── Never marked, GC deletes it!
│  exports section:   │
│  - __cosmo_exports  │
│  - pointers to it   │
└─────────────────────┘
```

**Key insight**: A weak **definition** satisfies its own reference during the mark phase, so the linker has no reason to look at `irb_exports.o`. The export table section never gets marked and is garbage collected.

### The Solution: Weak References

The fix is to use weak **references** instead of weak **definitions**:

```c
// CURRENT APPROACH (WORKING):
extern __attribute__((weak)) const struct cosmo_export_entry *const __cosmo_exports_start;
```

**Why this works:**
- A weak **reference** (with `extern`) declares that a symbol *may* exist elsewhere
- It does NOT create a definition that can satisfy the reference
- The linker must search for a strong definition in other object files
- If found (e.g., in `irb_exports.o`), the strong definition is used and its section is marked
- If not found, the symbol address becomes NULL at link time

**Visual representation of the solution:**

```
┌─────────────────────┐
│  cosmo_plugin.o     │
│  - Uses __cosmo_    │ ──weak ref──┐
│    exports_start    │             │
└─────────────────────┘             │
                                    ▼
                        ┌──────────────────────┐
                        │ NO definition in     │
                        │ cosmo_plugin.o       │ ◄── Cannot satisfy itself!
                        └──────────────────────┘
                                    │
                                    │ Linker must search...
                                    ▼
┌─────────────────────┐
│  irb_exports.o      │
│  .rodata.cosmo_     │ ◄── Found! Mark this section.
│  exports section:   │
│  - strong def of    │ ◄── Gets linked and kept!
│    __cosmo_exports  │
│    _start, etc.     │
└─────────────────────┘
```

### Safe Access Pattern

Because weak references may be undefined, the code must check before accessing:

```c
// Two-stage check in BuildExportCache():

// 1. Is the symbol defined? (check address of symbol)
if ((void*)&__cosmo_exports_start == NULL) {
    // Symbol not defined by linker - no export table linked
    return;
}

// 2. Is the value NULL? (check value of symbol)
if (__cosmo_exports_start == NULL) {
    // Symbol defined but value is NULL
    return;
}

// Safe to use
for (const struct cosmo_export_entry *e = __cosmo_exports_start; ...) {
    // ...
}
```

## Belt-and-Suspenders: Linker `-u` Flags

While **weak references** are the primary solution, the build also uses `-u` flags for additional safety.

The `-u` flag tells the linker: **"Pretend there's an external reference to this symbol that MUST be satisfied"**

This forces the linker to:
1. Search ALL input files for the symbol
2. Find strong definitions (e.g., in `irb_exports.o`)
3. Mark the section containing the strong definition as **needed**
4. Keep it in the final binary even if no code directly references it

### Why Both Weak References AND `-u` Flags?

**Weak references alone should be sufficient**, but `-u` flags provide defense-in-depth:

- **Weak references**: Prevent self-satisfaction, allow linker to find strong definitions
- **`-u` flags**: Force symbol retention even if optimization passes might eliminate references

This belt-and-suspenders approach ensures export tables survive aggressive optimization.

### Implementation

Add to link flags in `ruby.link.mk`:

```makefile
o/$(MODE)/third_party/ruby/ruby.dbg: private \
	LDFLAGS += \
		@$(RUBY_UNDEFS_ARGS) \
		-u __cosmo_exports_start \
		-u __cosmo_exports_end \
		-u __cosmo_exports_names_start \
		-u __cosmo_exports_names_end \
		--whole-archive \
		$(foreach x,$(THIRD_PARTY_RUBY_EXTENSIONS),$($(x)_A)) \
		--no-whole-archive
```

Apply same pattern to `irb.dbg` and `miniruby.dbg` link rules.

## Multi-Stage Build Process

The Ruby build uses a **4-stage link process** to handle the circular dependency between export tables and symbol addresses.

### The Circular Dependency Problem

**Problem**: The export table contains symbol addresses, but embedding the export table changes those addresses!

- Export table is ~230KB of data
- Adding it to the binary shifts all subsequent symbols
- Addresses in the export table become stale

### Build Stages

**Stage 1: pre.dbg**
- Link everything WITHOUT any export table
- Produces baseline binary with initial symbol addresses
- Used to bootstrap the process

**Stage 2: stage1.dbg**
- Generate `exports.pre.c` from pre.dbg symbols
- Link with `exports.pre.o` embedded
- Problem: Export table has **stale addresses** from pre.dbg (before table was added)
- Binary layout changes due to 230KB export table insertion

**Stage 3: stage2.dbg**
- Generate `exports.stage1.c` from stage1.dbg symbols
- Link with `exports.stage1.o` embedded
- Better: Addresses now account for having an export table present
- May still have minor layout differences (alignment, section ordering)

**Stage 4: final.dbg**
- Generate `exports.c` from stage2.dbg symbols
- Link with `exports.o` embedded
- Should be **identical** to stage2 if addresses have converged
- Verification that the build is stable

### Why So Many Stages?

Each stage lets the addresses **converge** toward their final values:

1. **Baseline** (pre): No export overhead
2. **First approximation** (stage1): Export table added, but addresses are from baseline
3. **Second approximation** (stage2): Addresses account for export table presence
4. **Final** (convergence): Addresses should be stable

The iteration handles:
- Direct size changes (export table takes space)
- Indirect layout changes (alignment, padding, section reordering)
- Self-referential symbols (export table symbols appearing in the table itself)

### Alternative: Why Not Single Stage?

A naive single-stage approach would embed an export table with **wrong addresses**:

```
pre.dbg: symbol foo at 0x401000
         Generate exports: { "foo", 0x401000 }
final.dbg: Insert 230KB export table at 0x400000
           Now foo is actually at 0x441000, but export table says 0x401000!
           ❌ Plugins would jump to wrong addresses
```

Multiple stages ensure the addresses in the export table match the actual runtime addresses in the final binary.

## Related Files

- `third_party/cosmo_plugin/cosmo_plugin.c` - Plugin loader with weak symbol references and safe access pattern
- `third_party/ruby-wip-3.4.7/ruby.link.mk` - Link rules with stage definitions and `-u` flags
- `third_party/ruby-wip-3.4.7/ruby.compile.mk` - Export generation rules
- `third_party/ruby-wip-3.4.7/generate_exports.sh` - Symbol extraction script
- `third_party/ruby-wip-3.4.7/cosmo_tests/check_export_table_binary.rb` - Export table verification
- `third_party/ruby-wip-3.4.7/dln_cosmo.c` - Ruby bridge to cosmo_plugin loader

## Debugging Tips

### Check if exports exist in object file
```bash
nm o//third_party/ruby/irb_exports.o | grep cosmo_exports
```

### Check if exports exist in final binary
```bash
nm o//third_party/ruby/irb.dbg | grep cosmo_exports
readelf -s o//third_party/ruby/irb.dbg | grep cosmo_exports
```

### Verify export table contents
```bash
# Use the Ruby verification script
bash third_party/ruby-wip-3.4.7/cosmo_tests/check_export_tables_binary.sh
```

### Test plugin loading at runtime
```bash
RUBYLIB=$PWD/third_party/ruby-wip-3.4.7/lib o//third_party/ruby/irb
> require 'json'  # Should work if exports are present
```

## Historical Context

### The Bug Discovery

This issue was discovered when:
1. Ruby's export verification started failing
2. `irb.com` crashed with "undefined symbol: rb_gc_mark" when loading extensions
3. Investigation revealed export symbols existed in `irb_exports.o` but not in `irb.dbg`
4. Root cause: `--gc-sections` was deleting the export table due to weak **definitions** satisfying themselves

### The Solution Evolution

**Initial approach**: Use weak **definitions** in `cosmo_plugin.c`
- Problem: Weak definitions satisfy their own references, preventing linker from finding strong definitions
- Result: Export table gets garbage collected

**First fix attempt**: Add `-u` flags only
- Would force symbol retention but doesn't address root cause
- Weak definitions would still satisfy themselves

**Correct solution**: Change to weak **references** + `-u` flags
- Weak references (`extern __attribute__((weak))`) don't create definitions
- Linker must search for strong definitions in export files
- `-u` flags provide belt-and-suspenders safety
- `BuildExportCache()` updated with two-stage NULL checks for safe access

### Key Insight

The fundamental issue was **weak definitions vs weak references**:
- Weak **definition**: Creates a symbol that satisfies its own reference
- Weak **reference**: Declares a symbol that *may* exist, forcing linker to search

Using weak references allows graceful fallback (standalone tests) while enabling proper symbol resolution (Ruby with export tables).
