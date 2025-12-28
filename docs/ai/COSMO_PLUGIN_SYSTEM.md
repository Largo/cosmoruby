# Cosmopolitan Plugin System: Language-Agnostic Position-Independent Archive Loading

## Executive Summary

Design and implement a **general-purpose plugin loading system** for Cosmopolitan that:
- Loads position-independent `.a` archives at runtime
- Provides symbol resolution from the main executable
- Works for Ruby, Python, Lua, or any embedded language
- Becomes a core Cosmopolitan feature (not language-specific hack)

This is **the right architecture** because:
1. Solves the fundamental limitation (dlopen doesn't work)
2. Benefits entire Cosmopolitan ecosystem
3. Provides clean API for all languages
4. Consolidates complexity in one well-tested implementation

---

## Architecture: Three-Layer Design

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 3: Language Bindings (Ruby, Python, Lua, etc.)       │
│  - require 'extension' → cosmo_load_plugin("extension.a")  │
│  - import extension → cosmo_load_plugin("extension.a")      │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│ Layer 2: Cosmo Plugin API (libc/dlopen/cosmo_plugin.c)     │
│  - cosmo_load_plugin(path, exports) → handle                │
│  - cosmo_plugin_sym(handle, name) → address                 │
│  - Language-agnostic, clean C API                           │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│ Layer 1: Build-Time Export Generation (build/export.sh)    │
│  - Extract symbols from linked executable                   │
│  - Generate .exportmap at link time                         │
│  - Embedded in .rodata section                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Part 1: Build-Time Symbol Export (CRITICAL FIX)

### Problem with V2 Approach
- Header scanning misses symbols, includes non-existent ones
- Doesn't enforce linker keeping symbols
- Doesn't handle stripped binaries

### Correct Approach: Extract from Linked Binary

**New file:** `build/export_symbols.sh`

```bash
#!/bin/sh
# Extract exported symbols from linked executable and generate C source
# Usage: export_symbols.sh executable.dbg output.c

set -e

EXECUTABLE="$1"
OUTPUT="$2"

if [ ! -f "$EXECUTABLE" ]; then
    echo "Error: $EXECUTABLE not found" >&2
    exit 1
fi

# Extract all global function and object symbols
# Use .dbg file (with symbols) before stripping
readelf -s -W "$EXECUTABLE" | \
    awk '
    BEGIN { print "/* Auto-generated symbol export table */"; 
            print "#include <stddef.h>"; 
            print ""; 
            print "struct cosmo_export {"; 
            print "    const char *name;"; 
            print "    void *addr;"; 
            print "};"; 
            print ""; 
            print "extern const struct cosmo_export __cosmo_exports[] = {"; 
          }
    
    # Match global symbols (FUNC or OBJECT) that are defined (not UND)
    $4 == "GLOBAL" && ($3 == "FUNC" || $3 == "OBJECT") && $7 != "UND" {
        # Extract symbol name (last field)
        symbol = $NF
        
        # Filter to interesting namespaces
        if (symbol ~ /^(rb_|ruby_|Init_|RUBY_|Py|py_|lua_|__cosmo)/) {
            # Emit extern declaration and table entry
            printf "extern void *%s;\n", symbol
            printf "    {\"%s\", &%s},\n", symbol, symbol
        }
    }
    
    END { print "    {NULL, NULL}"; 
          print "};"; 
        }
    ' > "$OUTPUT"

echo "Generated $(grep -c '{' "$OUTPUT") exports to $OUTPUT"
```

### Integration into Makefile

**In:** `third_party/ruby-wip-3.4.7/ruby.link.mk`

```make
# Generate symbol export table from linked ruby.dbg (before stripping)
o/$(MODE)/third_party/ruby/ruby_exports.c: o/$(MODE)/third_party/ruby/ruby.dbg
	build/export_symbols.sh $< $@

# Compile exports into object file
o/$(MODE)/third_party/ruby/ruby_exports.o: \
    o/$(MODE)/third_party/ruby/ruby_exports.c
	$(COMPILE) -c $< -o $@

# Link exports.o into final ruby.com
o/$(MODE)/third_party/ruby/ruby: \
    o/$(MODE)/third_party/ruby/ruby.dbg \
    o/$(MODE)/third_party/ruby/ruby_exports.o
	cp $< $@.tmp
	# Append exports object to binary
	objcopy --add-section .cosmo_exports=o/$(MODE)/third_party/ruby/ruby_exports.o $@.tmp
	# Now strip (symbols are preserved in exports table)
	strip $@.tmp -o $@
	# Zip embedding happens after this
```

**Key insight:** Extract symbols from the **actually linked** binary, not headers. This guarantees:
- Only symbols that exist in the binary
- Linker has already kept them (they're referenced)
- Works even after stripping (exports embedded before strip)

---

## Part 2: Core Cosmo Plugin Loader (Language-Agnostic)

### New API: `libc/dlopen/cosmo_plugin.h`

```c
#ifndef COSMOPOLITAN_LIBC_DLOPEN_COSMO_PLUGIN_H_
#define COSMOPOLITAN_LIBC_DLOPEN_COSMO_PLUGIN_H_

struct cosmo_export {
    const char *name;
    void *addr;
};

struct cosmo_plugin {
    char *path;
    void *base_addr;
    size_t size;
    struct cosmo_plugin_section *sections;
    size_t section_count;
    void **got;  // Global Offset Table simulation
    size_t got_size;
    void *tls_image;  // TLS template
    size_t tls_size;
    size_t tls_align;
};

/**
 * Load a position-independent archive as a plugin.
 * 
 * @param path Path to .a archive file
 * @param host_exports Symbol table from host executable (can be NULL to use embedded exports)
 * @param init_name Name of initialization function to call (or NULL to skip)
 * @return Handle to loaded plugin, or NULL on error
 */
struct cosmo_plugin *cosmo_load_plugin(const char *path,
                                       const struct cosmo_export *host_exports,
                                       const char *init_name);

/**
 * Look up a symbol in a loaded plugin.
 * 
 * @param plugin Handle from cosmo_load_plugin()
 * @param name Symbol name
 * @return Symbol address, or NULL if not found
 */
void *cosmo_plugin_sym(struct cosmo_plugin *plugin, const char *name);

/**
 * Unload a plugin and free resources.
 * 
 * @param plugin Handle from cosmo_load_plugin()
 */
void cosmo_unload_plugin(struct cosmo_plugin *plugin);

/**
 * Get embedded export table from current executable.
 * This is automatically generated at build time.
 * 
 * @return Pointer to export table, or NULL if not available
 */
const struct cosmo_export *cosmo_get_exports(void);

#endif /* COSMOPOLITAN_LIBC_DLOPEN_COSMO_PLUGIN_H_ */
```

### Implementation Strategy

**File:** `libc/dlopen/cosmo_plugin.c` (~2000 lines)

Key components:
1. **AR archive parser** (use existing `tool/build/lib/ar.c` functions)
2. **ELF object loader** (use existing `libc/elf/` utilities)
3. **Complete x86-64 relocation engine** (all 43 types)
4. **GOT simulation** (hash table: symbol name → GOT slot)
5. **TLS template extraction** (copy `.tdata` + `.tbss` for per-thread instantiation)
6. **Section memory management** (page-aligned mmap, W^X transitions)
7. **Init array execution** (`.init_array`, `.fini_array`)

---

## Part 3: Symbol Resolution - Three-Tier Fallback

```c
static void *resolve_symbol(const char *name, 
                           const struct cosmo_export *host_exports,
                           struct cosmo_plugin *plugin) {
    // Tier 1: Check embedded exports from executable
    if (!host_exports) {
        host_exports = cosmo_get_exports();
    }
    
    if (host_exports) {
        for (size_t i = 0; host_exports[i].name; i++) {
            if (strcmp(host_exports[i].name, name) == 0) {
                return host_exports[i].addr;
            }
        }
    }
    
    // Tier 2: Check other loaded plugins
    for (struct cosmo_plugin *p = plugin_list; p; p = p->next) {
        void *addr = cosmo_plugin_sym(p, name);
        if (addr) return addr;
    }
    
    // Tier 3: Check libc symbols (always available)
    static const struct {
        const char *name;
        void *addr;
    } libc_symbols[] = {
        {"malloc", malloc},
        {"free", free},
        {"memcpy", memcpy},
        {"memset", memset},
        {"strcmp", strcmp},
        // ... more common libc functions
        {NULL, NULL}
    };
    
    for (size_t i = 0; libc_symbols[i].name; i++) {
        if (strcmp(libc_symbols[i].name, name) == 0) {
            return libc_symbols[i].addr;
        }
    }
    
    return NULL;  // Undefined symbol
}
```

---

## Part 4: TLS Handling (Cosmopolitan-Specific)

### Understanding Cosmopolitan TLS

From `libc/thread/mktls.c`:
- Cosmopolitan uses **static TLS model** (not dynamic)
- TLS layout is fixed at link time
- `_tdata_start`, `_tdata_size`, `_tbss_size` are link-time symbols
- Each thread gets a copy of the TLS template

### Plugin TLS Strategy: **Template + Per-Thread Instantiation**

```c
struct cosmo_plugin_tls {
    void *template;      // Master copy of .tdata + .tbss
    size_t size;
    size_t align;
    size_t tdata_size;
    size_t tbss_offset;
    size_t tbss_size;
};

// Extract TLS template from plugin
static int extract_tls_template(struct cosmo_plugin *plugin, 
                                void *elf_data, 
                                size_t elf_size) {
    // Find .tdata and .tbss sections
    Elf64_Shdr *tdata = find_section_by_name(elf_data, ".tdata");
    Elf64_Shdr *tbss = find_section_by_name(elf_data, ".tbss");
    
    if (!tdata && !tbss) {
        plugin->tls_image = NULL;
        plugin->tls_size = 0;
        return 0;  // No TLS
    }
    
    // Calculate total size
    size_t tdata_size = tdata ? tdata->sh_size : 0;
    size_t tbss_size = tbss ? tbss->sh_size : 0;
    plugin->tls_size = tdata_size + tbss_size;
    plugin->tls_align = tdata ? tdata->sh_addralign : (tbss ? tbss->sh_addralign : 16);
    
    // Allocate template
    plugin->tls_image = memalign(plugin->tls_align, plugin->tls_size);
    if (!plugin->tls_image) return -1;
    
    // Copy .tdata
    if (tdata) {
        memcpy(plugin->tls_image, 
               (char*)elf_data + tdata->sh_offset, 
               tdata_size);
    }
    
    // Zero .tbss
    if (tbss) {
        memset((char*)plugin->tls_image + tdata_size, 0, tbss_size);
    }
    
    return 0;
}

// Per-thread TLS instantiation
// This is called when a new thread accesses plugin TLS for the first time
static void *instantiate_plugin_tls(struct cosmo_plugin *plugin) {
    if (!plugin->tls_image) return NULL;
    
    // Allocate per-thread copy
    void *thread_tls = memalign(plugin->tls_align, plugin->tls_size);
    if (!thread_tls) return NULL;
    
    // Copy from template
    memcpy(thread_tls, plugin->tls_image, plugin->tls_size);
    
    // Register with thread (stored in hash table keyed by pthread_self())
    register_plugin_tls(pthread_self(), plugin, thread_tls);
    
    return thread_tls;
}
```

### TLS Relocations

```c
// For TLS relocations, we return offset into per-thread storage
case R_X86_64_TPOFF64:  // Thread-local offset
    // This is a static TLS offset
    // At relocation time, we don't know the per-thread address yet
    // Store offset for later resolution
    *(uint64_t*)target = get_tls_template_offset(plugin, sym);
    break;

case R_X86_64_GOTTPOFF:  // GOT entry for TLS offset
    // Create GOT entry that will be patched per-thread
    size_t got_slot = allocate_got_entry(plugin);
    plugin->got[got_slot].type = GOT_TLS_OFFSET;
    plugin->got[got_slot].symbol = sym_name;
    *(uint32_t*)target = (uint32_t)(((uint64_t)&plugin->got[got_slot]) - P);
    break;
```

**Key insight:** TLS relocations resolve to **offsets**, not addresses. Actual per-thread addresses are computed at access time.

---

## Part 5: GOT Management

### Problem: GOT Indexing Without Pre-Allocation

V2 plan used `get_got_offset(obj, sym_name)` without defining allocation.

### Solution: Dynamic GOT with Hash Table

```c
struct got_entry {
    enum {
        GOT_ABSOLUTE,    // Direct pointer
        GOT_TLS_OFFSET,  // TLS offset (needs per-thread patching)
    } type;
    char *symbol;
    void *value;
};

struct got_table {
    struct got_entry *entries;
    size_t count;
    size_t capacity;
    // Hash table for O(1) lookup
    struct {
        char *key;
        size_t index;
    } *map;
    size_t map_size;
};

static size_t allocate_got_entry(struct cosmo_plugin *plugin, const char *symbol) {
    struct got_table *got = &plugin->got_table;
    
    // Check if already allocated
    for (size_t i = 0; i < got->map_size; i++) {
        if (got->map[i].key && strcmp(got->map[i].key, symbol) == 0) {
            return got->map[i].index;
        }
    }
    
    // Allocate new entry
    if (got->count >= got->capacity) {
        // Grow table
        got->capacity *= 2;
        got->entries = realloc(got->entries, got->capacity * sizeof(*got->entries));
    }
    
    size_t index = got->count++;
    got->entries[index].symbol = strdup(symbol);
    got->entries[index].value = NULL;
    got->entries[index].type = GOT_ABSOLUTE;
    
    // Add to map
    size_t hash = hash_string(symbol) % got->map_size;
    while (got->map[hash].key) {
        hash = (hash + 1) % got->map_size;
    }
    got->map[hash].key = got->entries[index].symbol;
    got->map[hash].index = index;
    
    return index;
}
```

---

## Part 6: Language Bindings

### Ruby Integration

**File:** `third_party/ruby-wip-3.4.7/dln_cosmo.c`

```c
#include "ruby.h"
#include "libc/dlopen/cosmo_plugin.h"

void *dln_load_cosmo(const char *path) {
    // Use embedded Ruby exports
    const struct cosmo_export *exports = cosmo_get_exports();
    
    // Deduce Init_* function name from path
    char init_name[256];
    deduce_init_name(path, init_name, sizeof(init_name));
    
    // Load plugin
    struct cosmo_plugin *plugin = cosmo_load_plugin(path, exports, init_name);
    if (!plugin) {
        rb_raise(rb_eLoadError, "Failed to load %s", path);
    }
    
    return plugin;
}
```

### Python Integration

**File:** `third_party/python/Python/dynload_cosmo.c`

```c
#include "Python.h"
#include "libc/dlopen/cosmo_plugin.h"

PyObject *_PyImport_LoadDynamicModuleWithSpec_Cosmo(PyObject *spec, FILE *fp) {
    const char *path = PyUnicode_AsUTF8(PyObject_GetAttrString(spec, "origin"));
    
    // Load as cosmo plugin
    struct cosmo_plugin *plugin = cosmo_load_plugin(path, cosmo_get_exports(), NULL);
    if (!plugin) {
        PyErr_SetString(PyExc_ImportError, "Failed to load plugin");
        return NULL;
    }
    
    // Find PyInit_<module> function
    char init_name[256];
    snprintf(init_name, sizeof(init_name), "PyInit_%s", module_name);
    
    PyObject *(*init_func)(void) = cosmo_plugin_sym(plugin, init_name);
    if (!init_func) {
        PyErr_Format(PyExc_ImportError, "Module %s has no %s", module_name, init_name);
        return NULL;
    }
    
    return init_func();
}
```

### Lua Integration

Similar pattern for Lua's `package.loadlib()`.

---

## Part 7: Memory Management - Page-Aligned Segments

### Problem: V2 Used Heap + mprotect

Heap allocations:
- May not be page-aligned
- May share pages with other heap data
- mprotect can affect unrelated memory

### Solution: mmap Per-Segment

```c
struct loaded_segment {
    void *base;
    size_t size;
    int prot;       // PROT_READ | PROT_WRITE | PROT_EXEC
    bool mapped;
};

static struct loaded_segment *allocate_segments(Elf64_Ehdr *elf) {
    // Count loadable sections
    size_t segment_count = 0;
    for (size_t i = 0; i < elf->e_shnum; i++) {
        Elf64_Shdr *shdr = get_section_header(elf, i);
        if (shdr->sh_flags & (SHF_ALLOC | SHF_EXECINSTR | SHF_WRITE)) {
            segment_count++;
        }
    }
    
    struct loaded_segment *segments = calloc(segment_count, sizeof(*segments));
    
    // Allocate each segment with proper alignment and protection
    size_t seg_idx = 0;
    for (size_t i = 0; i < elf->e_shnum; i++) {
        Elf64_Shdr *shdr = get_section_header(elf, i);
        if (!(shdr->sh_flags & SHF_ALLOC)) continue;
        
        // Determine protection
        int prot = PROT_READ;
        if (shdr->sh_flags & SHF_WRITE) prot |= PROT_WRITE;
        if (shdr->sh_flags & SHF_EXECINSTR) prot |= PROT_EXEC;
        
        // Round size up to page boundary
        size_t size = ROUNDUP(shdr->sh_size, 4096);
        
        // mmap with proper alignment
        void *base = mmap(NULL, size, PROT_READ | PROT_WRITE,
                         MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (base == MAP_FAILED) {
            // Cleanup and fail
            for (size_t j = 0; j < seg_idx; j++) {
                munmap(segments[j].base, segments[j].size);
            }
            free(segments);
            return NULL;
        }
        
        segments[seg_idx].base = base;
        segments[seg_idx].size = size;
        segments[seg_idx].prot = prot;
        segments[seg_idx].mapped = true;
        
        // Copy section data
        if (shdr->sh_type == SHT_PROGBITS) {
            memcpy(base, (char*)elf + shdr->sh_offset, shdr->sh_size);
        } else if (shdr->sh_type == SHT_NOBITS) {
            memset(base, 0, shdr->sh_size);
        }
        
        seg_idx++;
    }
    
    return segments;
}

static int finalize_protections(struct loaded_segment *segments, size_t count) {
    for (size_t i = 0; i < count; i++) {
        // After relocations, set final protections
        if (mprotect(segments[i].base, segments[i].size, segments[i].prot) != 0) {
            return -1;
        }
    }
    return 0;
}
```

**Key:** Each section gets its own page-aligned mmap region. No heap involvement.

---

## Part 8: Complete Relocation Coverage

### All x86-64 Relocation Types

```c
static int apply_relocation(struct cosmo_plugin *plugin,
                           Elf64_Rela *rela,
                           Elf64_Sym *sym,
                           const char *sym_name,
                           const struct cosmo_export *exports) {
    uint32_t type = ELF64_R_TYPE(rela->r_info);
    uint64_t *target = (uint64_t*)resolve_address(plugin, rela->r_offset);
    uint64_t S = (uint64_t)resolve_symbol(sym_name, exports, plugin);
    uint64_t A = rela->r_addend;
    uint64_t P = (uint64_t)target;
    
    switch (type) {
    case R_X86_64_NONE: break;
    case R_X86_64_64: *(uint64_t*)target = S + A; break;
    case R_X86_64_PC32: *(uint32_t*)target = (S + A - P); break;
    case R_X86_64_GOT32: /* ... */ break;
    case R_X86_64_PLT32: *(uint32_t*)target = (S + A - P); break;  // No PLT
    case R_X86_64_COPY: /* Not applicable for plugins */ break;
    case R_X86_64_GLOB_DAT: *(uint64_t*)target = S; break;
    case R_X86_64_JUMP_SLOT: *(uint64_t*)target = S; break;
    case R_X86_64_RELATIVE: *(uint64_t*)target = plugin->base_addr + A; break;
    case R_X86_64_GOTPCREL:
    case R_X86_64_GOTPCRELX:
    case R_X86_64_REX_GOTPCRELX: {
        // Allocate GOT entry
        size_t slot = allocate_got_entry(plugin, sym_name);
        plugin->got_table.entries[slot].value = (void*)S;
        *(uint32_t*)target = ((uint64_t)&plugin->got_table.entries[slot].value + A - P);
        break;
    }
    case R_X86_64_32: *(uint32_t*)target = (S + A); break;
    case R_X86_64_32S: *(int32_t*)target = (S + A); break;
    case R_X86_64_16: *(uint16_t*)target = (S + A); break;
    case R_X86_64_PC16: *(uint16_t*)target = (S + A - P); break;
    case R_X86_64_8: *(uint8_t*)target = (S + A); break;
    case R_X86_64_PC8: *(uint8_t*)target = (S + A - P); break;
    
    // TLS relocations
    case R_X86_64_DTPMOD64: *(uint64_t*)target = plugin->tls_module_id; break;
    case R_X86_64_DTPOFF64: *(uint64_t*)target = S + A; break;
    case R_X86_64_TPOFF64: *(uint64_t*)target = get_tls_offset(plugin, sym_name) + A; break;
    case R_X86_64_TLSGD: /* ... */ break;
    case R_X86_64_TLSLD: /* ... */ break;
    case R_X86_64_DTPOFF32: *(uint32_t*)target = S + A; break;
    case R_X86_64_GOTTPOFF: /* ... */ break;
    case R_X86_64_TPOFF32: *(uint32_t*)target = get_tls_offset(plugin, sym_name) + A; break;
    
    // More relocation types
    case R_X86_64_PC64: *(uint64_t*)target = S + A - P; break;
    case R_X86_64_GOTOFF64: *(uint64_t*)target = S + A - (uint64_t)plugin->got_table.entries; break;
    case R_X86_64_GOTPC32: /* ... */ break;
    case R_X86_64_GOT64: /* ... */ break;
    case R_X86_64_GOTPCREL64: /* ... */ break;
    case R_X86_64_GOTPC64: /* ... */ break;
    case R_X86_64_GOTPLT64: /* ... */ break;
    case R_X86_64_PLTOFF64: /* ... */ break;
    case R_X86_64_SIZE32: *(uint32_t*)target = sym->st_size + A; break;
    case R_X86_64_SIZE64: *(uint64_t*)target = sym->st_size + A; break;
    
    // TLS descriptor relocations
    case R_X86_64_GOTPC32_TLSDESC: /* ... */ break;
    case R_X86_64_TLSDESC_CALL: /* NOP - descriptor already set */ break;
    case R_X86_64_TLSDESC: /* ... */ break;
    
    case R_X86_64_IRELATIVE: {
        // Indirect function - call resolver
        uint64_t (*resolver)(void) = (void*)(plugin->base_addr + A);
        *(uint64_t*)target = resolver();
        break;
    }
    
    default:
        fprintf(stderr, "Unsupported relocation: %u\n", type);
        return -1;
    }
    
    return 0;
}
```

---

## Part 9: Build Integration (Language-Agnostic)

### Makefile Template for Any Language

```make
# Generic plugin system integration
# Include this in any language's BUILD.mk

# Step 1: Build .dbg with symbols
o/$(MODE)/$(LANG)/$(BINARY).dbg: $(OBJS) $(DEPS)
	$(LINK) -o $@ $(OBJS) $(LDFLAGS)

# Step 2: Extract exports from .dbg
o/$(MODE)/$(LANG)/$(BINARY)_exports.c: o/$(MODE)/$(LANG)/$(BINARY).dbg
	build/export_symbols.sh $< $@

# Step 3: Compile exports
o/$(MODE)/$(LANG)/$(BINARY)_exports.o: o/$(MODE)/$(LANG)/$(BINARY)_exports.c
	$(CC) -c $< -o $@

# Step 4: Embed exports and strip
o/$(MODE)/$(LANG)/$(BINARY): \
    o/$(MODE)/$(LANG)/$(BINARY).dbg \
    o/$(MODE)/$(LANG)/$(BINARY)_exports.o
	objcopy --add-section .cosmo_exports=$< $< $@.tmp
	strip $@.tmp -o $@
```

---

## Summary: Why This is Better

1. **Language-Agnostic**: Ruby, Python, Lua all use same API
2. **Symbols Guaranteed**: Extracted from linked binary, not headers
3. **Complete Relocations**: All x86-64 types properly handled
4. **Proper TLS**: Template-based per-thread instantiation
5. **Safe Memory**: Page-aligned mmap, proper W^X
6. **Clean API**: Simple C API that any language can bind
7. **Cosmopolitan Feature**: Benefits entire ecosystem

This should be implemented as **core Cosmopolitan infrastructure**, not a Ruby hack.
