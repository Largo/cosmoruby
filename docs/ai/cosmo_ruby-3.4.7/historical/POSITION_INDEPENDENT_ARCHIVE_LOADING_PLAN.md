# Implementation Plan: Position-Independent Archive Loading for CosmoRuby Extensions

## Executive Summary

Implement a complete end-to-end system for building and loading Ruby C extensions in CosmoRuby using position-independent `.a` archives. This consists of two major components:

1. **Archive Loader** (`dln_archive.c`): Runtime ELF loader that extracts `.o` files from archives, applies relocations, and calls `Init_*` functions
2. **Gem Builder** (RubyGems extension): Automated build system that compiles extensions with `cosmocc -fPIC` and creates `.a` archives

This enables third-party gems with native extensions to work in CosmoRuby without modifying core Cosmopolitan files or requiring static linking.

## Overview

Implement a runtime position-independent archive (`.a`) loading system for Ruby C extensions in CosmoRuby. This enables dynamic loading of native extensions without `dlopen()`, which is incompatible with Cosmopolitan's architecture.

**The complete workflow:**
```
gem install nokogiri
  → RubyGems uses CosmoExtconfBuilder
  → Compiles with: cosmocc -fPIC
  → Creates: nokogiri.a
  → Installs to: ~/.gem/ruby.com/3.4.0/extensions/.../nokogiri.a

require 'nokogiri'
  → Ruby searches $LOAD_PATH
  → Finds nokogiri.a
  → Calls dln_load_archive()
  → Extracts .o files, applies relocations
  → Calls Init_nokogiri()
  → Extension loaded!
```

## Background

**Why this is needed:**
- Cosmopolitan's `dlopen()` is a stub that returns NULL
- `cosmo_dlopen()` exists but cannot link executable symbols to loaded libraries
- Ruby extensions need to call `rb_define_class()`, `rb_provide()`, etc. from ruby.com
- Current solution (static linking all extensions) doesn't scale to third-party gems

**Solution:**
Load position-independent `.a` archives at runtime by:
1. Extracting `.o` files from AR archives
2. Allocating executable memory
3. Manually applying ELF relocations
4. Resolving symbols from ruby.com's symbol table
5. Calling `Init_*()` functions

## Critical Files

### Files to Create
1. `third_party/ruby-wip-3.4.7/dln_archive.c` - Archive loader implementation
2. `third_party/ruby-wip-3.4.7/dln_archive.h` - Archive loader API

### Files to Modify
1. `third_party/ruby-wip-3.4.7/load.c` - Hook archive loader into `require`
2. `third_party/ruby-wip-3.4.7/BUILD.mk` - Add new source files to build
3. `third_party/ruby-wip-3.4.7/ruby.deps.mk` - Update dependencies

### Files to Reference (No Changes)
- `tool/build/lib/ar.c`, `tool/build/lib/ar.h` - AR archive utilities
- `libc/elf/elf.h` - ELF parsing API
- `libc/dlopen/dlopen.c` - Memory allocation patterns
- `lib/rubygems/` - Gem installation infrastructure (already works)

## Implementation Steps

### Phase 1: Core Archive Loader (dln_archive.c)

**Location:** `third_party/ruby-wip-3.4.7/dln_archive.c`

**Components:**

#### 1.1 Symbol Table Builder
```c
struct SymbolTable {
    char **names;           // Symbol names
    void **addresses;       // Symbol addresses
    size_t count;
    size_t capacity;
};

// Build symbol table from ruby.com executable
void build_ruby_symbol_table(struct SymbolTable *table);
void symbol_table_add(struct SymbolTable *table, const char *name, void *addr);
void *symbol_table_lookup(struct SymbolTable *table, const char *name);
```

**Implementation approach:**
- Use `dlsym(RTLD_DEFAULT, name)` to get Ruby API addresses
- Pre-populate common symbols: `rb_define_class`, `rb_define_method`, `rb_provide`, etc.
- Cache for performance (build once per Ruby process)

#### 1.2 Object File Loader
```c
struct LoadedSection {
    void *data;             // Allocated memory for section
    size_t size;
    Elf64_Addr base_addr;   // Base address where loaded
    int prot;               // Memory protection flags
};

struct LoadedObject {
    char *name;
    struct LoadedSection *sections;
    size_t section_count;
    void *init_func;        // Init_* function pointer
};

// Load single .o file from memory
struct LoadedObject *load_object_file(void *elf_data, size_t elf_size,
                                     const char *name,
                                     struct SymbolTable *ruby_symbols);
```

**Implementation approach:**
- Parse ELF header with `IsElf64Binary()`
- Allocate memory for each section (`.text`, `.data`, `.rodata`, `.bss`)
- Copy section contents to allocated memory
- Build local symbol table from object's `.symtab`
- Apply relocations (next section)
- Find `Init_*()` function address
- Set memory protections: `.text` = RX, `.data`/`.bss` = RW, `.rodata` = R

#### 1.3 Relocation Engine
```c
// Apply relocations to loaded object
int apply_relocations(struct LoadedObject *obj,
                     void *elf_data,
                     size_t elf_size,
                     struct SymbolTable *ruby_symbols);
```

**Supported relocation types (x86-64):**
- `R_X86_64_64` - Direct 64-bit (S + A)
- `R_X86_64_PC32` - PC-relative 32-bit signed (S + A - P)
- `R_X86_64_PLT32` - PC-relative PLT (S + A - P)
- `R_X86_64_GOTPCREL` - PC-relative GOT offset
- `R_X86_64_32` - Direct 32-bit zero-extended (S + A)
- `R_X86_64_32S` - Direct 32-bit sign-extended (S + A)

Where:
- S = symbol value (from ruby_symbols or local symbols)
- A = addend (from relocation entry)
- P = place (address being modified)

**Implementation approach:**
- Iterate through all `.rela.*` sections
- For each relocation:
  - Extract symbol index and type
  - Look up symbol (check local table first, then ruby_symbols)
  - Calculate relocation value based on type
  - Write to target location
- Handle undefined symbols gracefully (error message with symbol name)

#### 1.4 Archive Loader (Main Entry Point)
```c
// Load .a archive and call Init_* function
void *dln_load_archive(const char *archive_path);
```

**Implementation approach:**
- Use `openar()` / `readar()` / `closear()` from `tool/build/lib/ar.h`
- Build Ruby symbol table (once per process)
- For each `.o` file in archive:
  - Call `load_object_file()`
  - Track loaded object in global list
- Find the `Init_*()` function (deduce name from archive filename)
- Call the `Init_*()` function
- Return handle (for potential unloading in future)

### Phase 2: Integration with Ruby's `require` (load.c)

**Location:** `third_party/ruby-wip-3.4.7/load.c`

#### 2.1 Check for `.a` Archives (line ~1123)

Modify `search_required()` to check for `.a` archives in extension directories:

```c
// CURRENT CODE (line 1121-1138):
if (!ft && type != loadable_ext_rb && vm->static_ext_inits) {
    // Check static_ext_inits table...
}

// NEW CODE:
if (!ft && type != loadable_ext_rb) {
    // First: Check static_ext_inits (existing)
    if (vm->static_ext_inits && st_lookup(...)) { ... }

    // Second: Check for .a archives in gem extension dirs
    VALUE archive_path = check_for_archive(lookup_name);
    if (!NIL_P(archive_path)) {
        *path = archive_path;
        return 's';  // Treat as shared object
    }
}
```

**Helper function to add:**
```c
static VALUE check_for_archive(VALUE name) {
    // 1. Build path: ~/.gem/ruby.com/3.4.0/extensions/x86_64-cosmo/3.4.0-static/
    // 2. Append gem name and .a extension
    // 3. Check if file exists with rb_file_load_ok()
    // 4. Return path or Qnil
}
```

#### 2.2 Load Archive (line ~1310)

Modify extension loading to handle `.a` archives:

```c
// CURRENT CODE (line 1308-1313):
case 's':
    reset_ext_config = true;
    ext_config_push(th, &prev_ext_config);
    handle = rb_vm_call_cfunc(rb_vm_top_self(), load_ext,
                              path, VM_BLOCK_HANDLER_NONE, path);
    rb_hash_aset(ruby_dln_libmap, path, SVALUE2NUM((SIGNED_VALUE)handle));
    break;

// NEW CODE:
case 's':
    reset_ext_config = true;
    ext_config_push(th, &prev_ext_config);

    // Check if path ends with .a
    const char *path_cstr = RSTRING_PTR(path);
    if (strlen(path_cstr) > 2 &&
        strcmp(path_cstr + strlen(path_cstr) - 2, ".a") == 0) {
        // Load .a archive
        handle = (VALUE)dln_load_archive(path_cstr);
    } else {
        // Load .so (existing path)
        handle = rb_vm_call_cfunc(rb_vm_top_self(), load_ext,
                                  path, VM_BLOCK_HANDLER_NONE, path);
    }

    rb_hash_aset(ruby_dln_libmap, path, SVALUE2NUM((SIGNED_VALUE)handle));
    break;
```

### Phase 3: Build System Integration

#### 3.1 Update BUILD.mk

**Location:** `third_party/ruby-wip-3.4.7/BUILD.mk`

Add new source file:
```make
RUBY_SRCS += third_party/ruby-wip-3.4.7/dln_archive.c
```

#### 3.2 Update Dependencies

The build system should automatically regenerate `ruby.deps.mk`, but verify:
```make
o/third_party/ruby-wip-3.4.7/dln_archive.o: \
  third_party/ruby-wip-3.4.7/dln_archive.c \
  tool/build/lib/ar.h \
  libc/elf/elf.h
```

### Phase 4: Gem Building Automation

#### 4.1 Cosmo ExtConf Builder

**Location:** `third_party/ruby-wip-3.4.7/lib/rubygems/ext/cosmo_extconf_builder.rb` (new file)

Create a custom extension builder for Cosmopolitan that:
- Inherits from `Gem::Ext::ExtConfBuilder`
- Overrides compilation to use `cosmocc` with `-fPIC`
- Generates `.a` archives instead of `.so` files
- Uses Cosmopolitan's `ar` tool

```ruby
module Gem
  module Ext
    class CosmoExtconfBuilder < ExtConfBuilder
      def self.build(extension, dest_path, results, args=[], lib_dir=nil, extension_dir=nil)
        # 1. Run extconf.rb to generate Makefile
        # 2. Modify Makefile to:
        #    - Use cosmocc instead of gcc
        #    - Add -fPIC flag
        #    - Change .so targets to .a targets
        #    - Use Cosmo ar instead of system ar
        # 3. Run make to compile
        # 4. Move .a to extension_dir
      end
    end
  end
end
```

**Integration point:** `lib/rubygems/ext/builder.rb` line ~170
- Detect if running on Cosmopolitan platform
- If yes, use `CosmoExtconfBuilder` instead of `ExtConfBuilder`

#### 4.2 Platform Detection

Add to `lib/rubygems/platform.rb`:
```ruby
def cosmopolitan?
  RbConfig::CONFIG["arch"] =~ /cosmo/
end
```

Use this to conditionally select Cosmo builder.

#### 4.3 Extension Compilation Workflow

Automated process (triggered by `gem install`):

```
gem install nokogiri
  ↓
1. Download gem
  ↓
2. Extract to ~/.gem/ruby.com/3.4.0/gems/nokogiri-1.x.x/
  ↓
3. Find extension: ext/nokogiri/extconf.rb
  ↓
4. Detect platform: x86_64-cosmo
  ↓
5. Use CosmoExtconfBuilder:
   • Run: ruby extconf.rb
   • Modify Makefile:
     - CC = cosmocc
     - CFLAGS += -fPIC
     - TARGET = nokogiri.a (not .so)
     - AR = /path/to/cosmo/ar
   • Run: make clean && make
   • Result: nokogiri.a
  ↓
6. Install to: ~/.gem/ruby.com/3.4.0/extensions/x86_64-cosmo/3.4.0-static/nokogiri-1.x.x/nokogiri.a
  ↓
7. Write gemspec
  ↓
8. Gem ready for use
```

#### 4.4 Archive Resolution Logic

When `require 'nokogiri'`:

```
1. Search $LOAD_PATH for nokogiri.rb or nokogiri.so → NOT FOUND
  ↓
2. Trigger RubyGems activation
  ↓
3. Find nokogiri gemspec
  ↓
4. Activate gem (add to $LOAD_PATH):
   • ~/.gem/ruby.com/3.4.0/gems/nokogiri-1.x.x/lib/
   • ~/.gem/ruby.com/3.4.0/extensions/x86_64-cosmo/3.4.0-static/nokogiri-1.x.x/
  ↓
5. Retry require 'nokogiri'
  ↓
6. Search $LOAD_PATH:
   • Check gems/.../lib/nokogiri.rb → NOT FOUND
   • Check extensions/.../nokogiri.so → NOT FOUND
   • Check extensions/.../nokogiri.a → FOUND!
  ↓
7. Call dln_load_archive(path)
  ↓
8. Extract .o files, apply relocations, call Init_nokogiri()
  ↓
9. Mark nokogiri.a as loaded in $LOADED_FEATURES
  ↓
10. SUCCESS
```

#### 4.5 Gem Installation Locations

Standard RubyGems structure with `.a` archives:

```
~/.gem/ruby.com/3.4.0/
├── gems/
│   └── nokogiri-1.16.0/
│       ├── lib/
│       │   └── nokogiri.rb          # Pure Ruby wrapper
│       └── ext/
│           └── nokogiri/
│               ├── extconf.rb       # Build script
│               └── *.c              # Source (kept for reference)
├── extensions/
│   └── x86_64-cosmo/
│       └── 3.4.0-static/
│           └── nokogiri-1.16.0/
│               ├── gem_make.out     # Build log
│               ├── nokogiri/        # Subdirectory matches require path
│               │   └── nokogiri.a   # The archive!
│               └── mkmf.log
└── specifications/
    └── nokogiri-1.16.0.gemspec
```

**Key insight:** Archive location must match the require path structure.

## Testing Strategy

### Phase 1: Simple Test Extension

Create a minimal test extension:

```c
// test_ext.c
#include "ruby.h"

static VALUE test_hello(VALUE self) {
    return rb_str_new_cstr("Hello from archive!");
}

void Init_test_ext(void) {
    VALUE mod = rb_define_module("TestExt");
    rb_define_module_function(mod, "hello", test_hello, 0);
}
```

Build and test:
```bash
cosmocc -fPIC -I third_party/ruby-wip-3.4.7/include -c test_ext.c -o test_ext.o
o/tool/build/ar rcs test_ext.a test_ext.o
mkdir -p test_extensions
mv test_ext.a test_extensions/

# Test loading:
ruby.com -e "
  $LOAD_PATH << './test_extensions'
  require 'test_ext'
  puts TestExt.hello
"
```

### Phase 2: Existing Statically-Linked Extension

Test with an existing extension (e.g., `stringio`):

```bash
# Build as .a instead of static linking:
cosmocc -fPIC -c third_party/ruby-wip-3.4.7/ext/stringio/stringio.c -o stringio.o
o/tool/build/ar rcs stringio.a stringio.o

# Test loading
```

### Phase 3: Simple Gem

Create a test gem with native extension:
- Use simple C code (no dependencies)
- Build as `x86_64-cosmo` platform gem
- Test `gem install` and `require`

### Phase 4: Complex Gem

Test with production gem (e.g., `json`, `msgpack`):
- Multiple source files
- Inter-object symbol references
- Full gem workflow

## Technical Considerations

### Memory Management
- Use `mmap()` for allocations (following `cosmo_dlopen()` pattern)
- Track all allocations for potential unloading
- Set appropriate memory protections (RX for code, RW for data)

### Symbol Resolution Order
1. Local symbols within the object file
2. Ruby API symbols (`rb_*`, `ruby_*`)
3. Libc symbols (already linked into ruby.com)
4. Other loaded extension symbols (for inter-extension dependencies)

### Error Handling
- Graceful failures with descriptive error messages
- Report missing symbols by name
- Validate ELF format before processing
- Handle malformed `.a` archives

### Platform Support
- Initial implementation: x86-64 only
- Future: Add ARM64 support (different relocation types)
- Platform detection via `RbConfig::CONFIG["arch"]`

### Performance
- Cache Ruby symbol table (build once per process)
- Memory map archive files (don't copy entire files)
- Lazy loading (only load when required)

## Rollout Plan

### Milestone 1: Core Archive Loader
- [ ] Implement `dln_archive.c` with all components:
  - [ ] Symbol table builder (`build_ruby_symbol_table`)
  - [ ] Object file loader (`load_object_file`)
  - [ ] Relocation engine (`apply_relocations`)
  - [ ] Archive loader entry point (`dln_load_archive`)
- [ ] Create header file `dln_archive.h`
- [ ] Add to build system (BUILD.mk, ruby.deps.mk)
- [ ] Compile ruby.com with new code

### Milestone 2: Ruby Integration
- [ ] Hook into `load.c`:
  - [ ] Modify `search_required()` to detect `.a` archives
  - [ ] Modify extension loading to call `dln_load_archive()`
  - [ ] Update `$LOADED_FEATURES` handling
- [ ] Test with manually-created test extension:
  - [ ] Build simple test_ext.c → test_ext.a
  - [ ] Load via `require 'test_ext'`
  - [ ] Verify extension functions work
- [ ] Test with existing extension (e.g., stringio):
  - [ ] Compile stringio as .a instead of static
  - [ ] Load dynamically
- [ ] Verify error handling and debugging

### Milestone 3: Gem Builder Automation
- [ ] Create `CosmoExtconfBuilder`:
  - [ ] Implement in `lib/rubygems/ext/cosmo_extconf_builder.rb`
  - [ ] Override Makefile generation for cosmocc
  - [ ] Add `-fPIC` flag
  - [ ] Change targets from `.so` to `.a`
  - [ ] Use Cosmopolitan's ar tool
- [ ] Integrate with RubyGems:
  - [ ] Add platform detection in `lib/rubygems/platform.rb`
  - [ ] Hook builder selection in `lib/rubygems/ext/builder.rb`
  - [ ] Update file search logic to include `.a`
- [ ] Test automation:
  - [ ] Create simple test gem with extension
  - [ ] Run `gem build` and verify .a creation
  - [ ] Run `gem install` locally
  - [ ] Verify `require` works end-to-end

### Milestone 4: Production Validation
- [ ] Test with real gems:
  - [ ] json (simple, single file)
  - [ ] msgpack (medium complexity)
  - [ ] nokogiri (complex, multiple files)
- [ ] Performance benchmarking:
  - [ ] Measure load time vs static linking
  - [ ] Memory usage comparison
- [ ] Stability testing:
  - [ ] Memory leak detection
  - [ ] Stress test (load many extensions)
  - [ ] Edge cases (malformed archives, missing symbols)
- [ ] Documentation:
  - [ ] Update RUBY_EXTENSIONS_ROADMAP.md
  - [ ] Update RUBY_PORT_PROGRESS.md
  - [ ] Create COSMO_GEM_BUILDING.md guide

## Decisions Made

1. **Archive naming convention**: Use intelligent resolution based on require path
   - Archive names can be flexible (gem name with version, or simple name)
   - Resolution logic searches multiple locations and patterns
   - Prioritizes correctness and completeness over simplicity

2. **Init function deduction**: Deduce `Init_*` name from require path
   - For `require 'nokogiri'`, call `Init_nokogiri()`
   - Matches standard `.so` behavior for predictability
   - Single entry point per extension archive

3. **Archive location**: Special lib install directory
   - Use `archlib` directory: `~/.gem/ruby.com/3.4.0/extensions/x86_64-cosmo/3.4.0-static/<gem>/`
   - Separate from source (`ext/`) and Ruby code (`lib/`)
   - Follows gem directory structure conventions

4. **Gem building**: Build automation tool from the start
   - Create or extend gem build tools to automate `.a` creation
   - Integrate with RubyGems extension builder infrastructure
   - Make it seamless for gem developers

## Success Criteria

- [ ] Can load simple test extension from `.a` file
- [ ] All existing statically-linked extensions work when loaded from `.a`
- [ ] Can install and use a gem with native extension (e.g., `json`)
- [ ] Error messages are clear and actionable
- [ ] Performance is acceptable (< 10ms load time per extension)
- [ ] No memory leaks or segfaults
- [ ] Documentation is complete

## Future Enhancements

- **ARM64 support**: Add ARM64 relocation types
- **Extension unloading**: Implement unloading and memory cleanup
- **Hot reloading**: Reload extensions during development
- **Gem server**: Host pre-compiled gems for common libraries
- **Dependency linking**: Support extensions with external library dependencies
- **Debug symbols**: Preserve debug info for better error messages
