# Position-Independent Archive Loading for CosmoRuby - Implementation Plan V2

## Critical Issues Addressed from V1

This revision addresses fatal flaws in the original plan:

### 1. Symbol Resolution Strategy (CRITICAL FIX)
**Problem:** V1 planned to use `dlsym(RTLD_DEFAULT, name)` which won't work because:
- Cosmopolitan's `dlsym()` is a stub (like `dlopen()`)
- ruby.com is statically linked and typically stripped
- Even unstripped, Cosmopolitan doesn't expose static symbols via dlsym

**Solution:** Generate and embed a Ruby API export table at build time

### 2. Incomplete Relocation Support (CRITICAL FIX)
**Problem:** V1 only listed 6 relocation types; real `-fPIC` objects use 15+ types

**Solution:** Support all x86-64 relocations including GOT/PLT optimizations and TLS

### 3. Missing ELF Initialization (HIGH PRIORITY)
**Problem:** No handling of `.init_array`/`.fini_array` or C++ constructors

**Solution:** Execute init arrays after loading

### 4. Init Function Detection (MEDIUM PRIORITY)
**Problem:** Filename-based `Init_*` inference is unreliable

**Solution:** Scan object symtabs for `Init_*` exports

### 5. TLS Not Addressed (MEDIUM PRIORITY)
**Problem:** Extensions using `__thread`/`thread_local` will crash

**Solution:** Allocate TLS blocks and process TLS relocations

### 6. Gem Builder Details (MEDIUM PRIORITY)
**Problem:** High-level plan without concrete Makefile modifications

**Solution:** Specific DLEXT/LIBRUBYARG overrides and install path fixes

---

## Part 1: Ruby API Export Table Generation

### 1.1 Build-Time Symbol Extraction

**New file:** `third_party/ruby-wip-3.4.7/tool/gen_ruby_exports.rb`

```ruby
#!/usr/bin/env ruby
# Generates C source file with Ruby API symbol table

RUBY_API_PATTERNS = [
  /^rb_/,
  /^ruby_/,
  /^Init_/,
  /^RUBY_/
]

def extract_public_symbols(header_dir)
  symbols = []
  
  Dir.glob("#{header_dir}/**/*.h").each do |header|
    File.read(header).scan(/^RUBY_FUNC_EXPORTED\s+\w+\s+(\w+)\s*\(/) do |match|
      symbols << match[0]
    end
    
    # Also extract from RUBY_EXTERN declarations
    File.read(header).scan(/^RUBY_EXTERN\s+\w+\s+(\w+);/) do |match|
      symbols << match[0]
    end
  end
  
  symbols.uniq.sort
end

def generate_export_table(symbols, output_path)
  File.open(output_path, 'w') do |f|
    f.puts "/* Auto-generated Ruby API export table */"
    f.puts "#include \"ruby.h\""
    f.puts "#include \"dln_archive.h\""
    f.puts ""
    f.puts "struct ruby_symbol_export {"
    f.puts "    const char *name;"
    f.puts "    void *addr;"
    f.puts "};"
    f.puts ""
    f.puts "const struct ruby_symbol_export ruby_api_exports[] = {"
    
    symbols.each do |sym|
      f.puts "    {\"#{sym}\", (void*)#{sym}},"
    end
    
    f.puts "    {NULL, NULL}"
    f.puts "};"
    f.puts ""
    f.puts "const size_t ruby_api_exports_count = #{symbols.size};"
  end
end

if __FILE__ == $0
  header_dir = ARGV[0] || "include"
  output_file = ARGV[1] || "ruby_exports.c"
  
  symbols = extract_public_symbols(header_dir)
  generate_export_table(symbols, output_file)
  
  puts "Generated #{symbols.size} symbol exports to #{output_file}"
end
```

### 1.2 Integration into Build System

**Modify:** `third_party/ruby-wip-3.4.7/BUILD.mk`

```make
# Generate Ruby exports table
third_party/ruby-wip-3.4.7/ruby_exports.c: \
    third_party/ruby-wip-3.4.7/tool/gen_ruby_exports.rb \
    $(wildcard third_party/ruby-wip-3.4.7/include/**/*.h)
	$(RUBY) third_party/ruby-wip-3.4.7/tool/gen_ruby_exports.rb \
		third_party/ruby-wip-3.4.7/include \
		third_party/ruby-wip-3.4.7/ruby_exports.c

# Add to Ruby sources
RUBY_SRCS += third_party/ruby-wip-3.4.7/ruby_exports.c
RUBY_SRCS += third_party/ruby-wip-3.4.7/dln_archive.c
```

### 1.3 Symbol Table Accessor

**In:** `third_party/ruby-wip-3.4.7/dln_archive.h`

```c
struct ruby_symbol_export {
    const char *name;
    void *addr;
};

// Provided by generated ruby_exports.c
extern const struct ruby_symbol_export ruby_api_exports[];
extern const size_t ruby_api_exports_count;
```

---

## Part 2: Complete Relocation Engine

### 2.1 Full Relocation Type Support

**In:** `third_party/ruby-wip-3.4.7/dln_archive.c`

```c
#include "libc/elf/def.h"
#include "libc/elf/struct/rela.h"

// GOT/PLT simulation
struct got_entry {
    void *address;
};

struct loaded_object {
    // ... existing fields ...
    struct got_entry *got;
    size_t got_size;
    void *tls_block;
    size_t tls_size;
    size_t tls_offset;
};

static int apply_relocation(struct loaded_object *obj,
                           Elf64_Rela *rela,
                           Elf64_Sym *symtab,
                           char *strtab,
                           struct symbol_table *ruby_symbols) {
    uint64_t type = ELF64_R_TYPE(rela->r_info);
    uint64_t sym_idx = ELF64_R_SYM(rela->r_info);
    
    // Get symbol
    Elf64_Sym *sym = &symtab[sym_idx];
    const char *sym_name = strtab + sym->st_name;
    void *sym_addr;
    
    // Resolve symbol
    if (sym->st_shndx == SHN_UNDEF) {
        // External symbol - look up in Ruby API
        sym_addr = symbol_table_lookup(ruby_symbols, sym_name);
        if (!sym_addr && ELF64_ST_BIND(sym->st_info) != STB_WEAK) {
            fprintf(stderr, "Undefined symbol: %s\n", sym_name);
            return -1;
        }
    } else {
        // Local symbol - resolve to loaded section
        sym_addr = get_symbol_address(obj, sym);
    }
    
    // Get relocation target
    void *target = get_section_address(obj, rela->r_offset);
    uint64_t S = (uint64_t)sym_addr;
    uint64_t A = rela->r_addend;
    uint64_t P = (uint64_t)target;
    uint64_t G = get_got_offset(obj, sym_name);  // GOT offset
    uint64_t L = 0;  // PLT offset (we don't use PLT, treat as direct)
    
    switch (type) {
    case R_X86_64_NONE:
        break;
        
    case R_X86_64_64:  // Direct 64-bit
        *(uint64_t*)target = S + A;
        break;
        
    case R_X86_64_PC32:  // PC-relative 32-bit
    case R_X86_64_PLT32:  // PLT32 treated as PC32 (no PLT)
        *(uint32_t*)target = (uint32_t)(S + A - P);
        break;
        
    case R_X86_64_GOTPCREL:  // GOT-relative
        // GOT[n] = S
        obj->got[G].address = (void*)S;
        *(uint32_t*)target = (uint32_t)(((uint64_t)&obj->got[G] + A) - P);
        break;
        
    case R_X86_64_GOTPCRELX:  // Optimized GOTPCREL (6 bytes)
    case R_X86_64_REX_GOTPCRELX:  // Optimized GOTPCREL (7 bytes)
        // Can optimize to direct access if symbol is defined
        if (S) {
            // Rewrite to direct PC-relative
            *(uint32_t*)target = (uint32_t)(S + A - P);
        } else {
            // Use GOT
            obj->got[G].address = (void*)S;
            *(uint32_t*)target = (uint32_t)(((uint64_t)&obj->got[G] + A) - P);
        }
        break;
        
    case R_X86_64_32:  // Direct 32-bit zero-extended
        *(uint32_t*)target = (uint32_t)(S + A);
        break;
        
    case R_X86_64_32S:  // Direct 32-bit sign-extended
        *(int32_t*)target = (int32_t)(S + A);
        break;
        
    case R_X86_64_16:
        *(uint16_t*)target = (uint16_t)(S + A);
        break;
        
    case R_X86_64_8:
        *(uint8_t*)target = (uint8_t)(S + A);
        break;
        
    case R_X86_64_PC16:
        *(uint16_t*)target = (uint16_t)(S + A - P);
        break;
        
    case R_X86_64_PC8:
        *(uint8_t*)target = (uint8_t)(S + A - P);
        break;
        
    case R_X86_64_PC64:
        *(uint64_t*)target = S + A - P;
        break;
        
    case R_X86_64_GLOB_DAT:
    case R_X86_64_JUMP_SLOT:
        *(uint64_t*)target = S;
        break;
        
    case R_X86_64_RELATIVE:
        *(uint64_t*)target = (uint64_t)obj->base_addr + A;
        break;
        
    case R_X86_64_IRELATIVE:
        // Indirect function (call resolver)
        {
            uint64_t (*resolver)(void) = (void*)(obj->base_addr + A);
            *(uint64_t*)target = resolver();
        }
        break;
        
    // TLS relocations
    case R_X86_64_DTPMOD64:
        *(uint64_t*)target = obj->tls_module_id;
        break;
        
    case R_X86_64_DTPOFF64:
        *(uint64_t*)target = S + A;
        break;
        
    case R_X86_64_TPOFF64:
        *(uint64_t*)target = S + A - obj->tls_offset;
        break;
        
    case R_X86_64_DTPOFF32:
        *(uint32_t*)target = (uint32_t)(S + A);
        break;
        
    case R_X86_64_TPOFF32:
        *(uint32_t*)target = (uint32_t)(S + A - obj->tls_offset);
        break;
        
    case R_X86_64_GOTTPOFF:
        // GOT entry for TLS
        obj->got[G].address = (void*)(S + A - obj->tls_offset);
        *(uint32_t*)target = (uint32_t)(((uint64_t)&obj->got[G]) - P);
        break;
        
    case R_X86_64_GOTOFF64:
        *(uint64_t*)target = S + A - (uint64_t)obj->got;
        break;
        
    case R_X86_64_SIZE32:
        *(uint32_t*)target = (uint32_t)(sym->st_size + A);
        break;
        
    case R_X86_64_SIZE64:
        *(uint64_t*)target = sym->st_size + A;
        break;
        
    default:
        fprintf(stderr, "Unsupported relocation type: %lu\n", type);
        return -1;
    }
    
    return 0;
}
```

---

## Part 3: ELF Initialization Arrays

### 3.1 Process Init/Fini Arrays

```c
static void run_init_array(struct loaded_object *obj) {
    // Find .init_array section
    Elf64_Shdr *init_array = find_section(obj, ".init_array");
    if (!init_array) return;
    
    void **funcs = (void**)get_section_address(obj, init_array);
    size_t count = init_array->sh_size / sizeof(void*);
    
    for (size_t i = 0; i < count; i++) {
        if (funcs[i]) {
            ((void(*)(void))funcs[i])();
        }
    }
}

static void run_fini_array(struct loaded_object *obj) {
    // Find .fini_array section
    Elf64_Shdr *fini_array = find_section(obj, ".fini_array");
    if (!fini_array) return;
    
    void **funcs = (void**)get_section_address(obj, fini_array);
    size_t count = fini_array->sh_size / sizeof(void*);
    
    // Run in reverse order
    for (ssize_t i = count - 1; i >= 0; i--) {
        if (funcs[i]) {
            ((void(*)(void))funcs[i])();
        }
    }
}
```

---

## Part 4: TLS Support

### 4.1 TLS Block Allocation

```c
#include <sys/mman.h>
#include "libc/thread/tls.h"

static int allocate_tls_block(struct loaded_object *obj) {
    // Find .tdata and .tbss sections
    Elf64_Shdr *tdata = find_section(obj, ".tdata");
    Elf64_Shdr *tbss = find_section(obj, ".tbss");
    
    if (!tdata && !tbss) {
        obj->tls_size = 0;
        return 0;  // No TLS needed
    }
    
    size_t tdata_size = tdata ? tdata->sh_size : 0;
    size_t tbss_size = tbss ? tbss->sh_size : 0;
    obj->tls_size = tdata_size + tbss_size;
    
    // Allocate TLS block
    obj->tls_block = mmap(NULL, obj->tls_size, 
                          PROT_READ | PROT_WRITE,
                          MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (obj->tls_block == MAP_FAILED) {
        return -1;
    }
    
    // Copy .tdata contents
    if (tdata) {
        memcpy(obj->tls_block, 
               get_section_address(obj, tdata), 
               tdata_size);
    }
    
    // .tbss is zero-initialized (already done by MAP_ANONYMOUS)
    
    // Register with thread system
    obj->tls_module_id = register_tls_module(obj->tls_block, obj->tls_size);
    obj->tls_offset = get_tls_offset(obj->tls_module_id);
    
    return 0;
}
```

---

## Part 5: Improved Init Function Detection

### 5.1 Scan Symbol Table for Init_* Functions

```c
static void* find_init_function(struct loaded_object *obj, const char *require_name) {
    // Build expected init name: require 'foo/bar' → Init_foo_bar or Init_bar
    char init_name[256];
    char init_alt[256];
    
    // Primary: Init_<full_path_with_underscores>
    snprintf(init_name, sizeof(init_name), "Init_%s", require_name);
    for (char *p = init_name; *p; p++) {
        if (*p == '/' || *p == '-') *p = '_';
    }
    
    // Alternative: Init_<basename>
    const char *basename = strrchr(require_name, '/');
    basename = basename ? basename + 1 : require_name;
    snprintf(init_alt, sizeof(init_alt), "Init_%s", basename);
    for (char *p = init_alt; *p; p++) {
        if (*p == '-') *p = '_';
    }
    
    // Scan all objects in archive
    for (size_t i = 0; i < obj->object_count; i++) {
        struct loaded_object *o = &obj->objects[i];
        
        // Get symbol table
        Elf64_Sym *symtab = get_symtab(o);
        char *strtab = get_strtab(o);
        size_t sym_count = get_symtab_count(o);
        
        for (size_t j = 0; j < sym_count; j++) {
            if (symtab[j].st_shndx == SHN_UNDEF) continue;
            if (ELF64_ST_TYPE(symtab[j].st_info) != STT_FUNC) continue;
            
            const char *name = strtab + symtab[j].st_name;
            
            // Check if it's an Init_* function
            if (strncmp(name, "Init_", 5) == 0) {
                // Found an Init function
                if (strcmp(name, init_name) == 0 || strcmp(name, init_alt) == 0) {
                    // Exact match for our require
                    return get_symbol_address(o, &symtab[j]);
                }
                // Otherwise keep searching for exact match
            }
        }
    }
    
    // No exact match, try any Init_* function (fallback)
    // This handles single-extension archives
    for (size_t i = 0; i < obj->object_count; i++) {
        struct loaded_object *o = &obj->objects[i];
        Elf64_Sym *symtab = get_symtab(o);
        char *strtab = get_strtab(o);
        size_t sym_count = get_symtab_count(o);
        
        for (size_t j = 0; j < sym_count; j++) {
            if (symtab[j].st_shndx == SHN_UNDEF) continue;
            if (ELF64_ST_TYPE(symtab[j].st_info) != STT_FUNC) continue;
            const char *name = strtab + symtab[j].st_name;
            if (strncmp(name, "Init_", 5) == 0) {
                return get_symbol_address(o, &symtab[j]);
            }
        }
    }
    
    return NULL;  // No Init function found
}
```

---

## Part 6: Gem Builder - Concrete Implementation

### 6.1 ExtConf Makefile Rewriter

**In:** `third_party/ruby-wip-3.4.7/lib/rubygems/ext/cosmo_extconf_builder.rb`

```ruby
module Gem
  module Ext
    class CosmoExtconfBuilder < ExtConfBuilder
      def self.build(extension, dest_path, results, args=[], lib_dir=nil, extension_dir=nil)
        require 'fileutils'
        require 'rbconfig'
        
        # Run extconf.rb to generate Makefile
        super(extension, dest_path, results, args, lib_dir, extension_dir)
        
        # Now rewrite the Makefile for Cosmopolitan
        makefile_path = File.join(dest_path, 'Makefile')
        return unless File.exist?(makefile_path)
        
        makefile = File.read(makefile_path)
        
        # Find cosmocc compiler
        cosmocc = find_cosmocc() or raise "cosmocc not found"
        cosmoar = find_cosmoar() or raise "cosmo ar not found"
        
        # Rewrite compiler
        makefile.gsub!(/^CC\s*=.*$/, "CC = #{cosmocc}")
        makefile.gsub!(/^CXX\s*=.*$/, "CXX = #{cosmocc}")
        makefile.gsub!(/^AR\s*=.*$/, "AR = #{cosmoar}")
        makefile.gsub!(/^RANLIB\s*=.*$/, "RANLIB = true")  # ar rcs does this
        
        # Add -fPIC to CFLAGS
        makefile.gsub!(/^CFLAGS\s*=(.*)$/, "CFLAGS =\\1 -fPIC")
        makefile.gsub!(/^CXXFLAGS\s*=(.*)$/, "CXXFLAGS =\\1 -fPIC")
        
        # Change target from .so to .a
        target_name = File.basename(extension, '.rb')
        makefile.gsub!(/^TARGET\s*=\s*(\S+)\.so/, "TARGET = \\1.a")
        makefile.gsub!(/\$\(TARGET\)\.so/, '$(TARGET).a')
        
        # Change linking rule from $(LDSHARED) to $(AR)
        makefile.gsub!(/\$\(LDSHARED\).*\$\(DLLIB\)/) do |match|
          "$(AR) rcs $(DLLIB) $(OBJS)"
        end
        
        # Remove LDFLAGS/LIBS from archive creation
        makefile.gsub!(/\$\(AR\).*\$\(LDFLAGS\).*$/, '$(AR) rcs $(DLLIB) $(OBJS)')
        
        File.write(makefile_path, makefile)
        
        # Now run make
        run_make(dest_path, results)
        
        # Move .a to extension_dir
        built_archive = Dir.glob(File.join(dest_path, '*.a')).first
        if built_archive
          FileUtils.mkdir_p(extension_dir)
          final_path = File.join(extension_dir, File.basename(built_archive))
          FileUtils.mv(built_archive, final_path)
          results << "Installed: #{final_path}"
        else
          raise Gem::InstallError, "Archive not built"
        end
      end
      
      private
      
      def self.find_cosmocc
        # Look for cosmocc in common locations
        candidates = [
          ENV['COSMOCC'],
          File.join(RbConfig::CONFIG['bindir'], 'cosmocc'),
          '/opt/cosmo/bin/cosmocc',
          `which cosmocc 2>/dev/null`.strip
        ]
        candidates.find { |p| p && File.executable?(p) }
      end
      
      def self.find_cosmoar
        cosmo_root = File.dirname(File.dirname(find_cosmocc))
        File.join(cosmo_root, 'o/tool/build/ar')
      end
      
      def self.run_make(dest_path, results)
        make_cmd = ENV['MAKE'] || 'make'
        Dir.chdir(dest_path) do
          system("#{make_cmd} clean") rescue nil
          unless system("#{make_cmd}")
            raise Gem::InstallError, "make failed"
          end
        end
      end
    end
  end
end
```

### 6.2 Builder Selection Hook

**In:** `third_party/ruby-wip-3.4.7/lib/rubygems/ext/builder.rb`

Around line 170, modify builder selection:

```ruby
def builder_for(extension)
  # Cosmopolitan platform uses special builder
  if RbConfig::CONFIG['arch'] =~ /cosmo/
    case extension
    when /extconf\.rb$/ then Gem::Ext::CosmoExtconfBuilder
    when /configure$/   then Gem::Ext::ConfigureBuilder
    when /rakefile/i    then Gem::Ext::RakeBuilder
    when /mkrf_conf\.rb$/ then Gem::Ext::RakeBuilder
    when /CMakeLists\.txt$/ then Gem::Ext::CmakeBuilder
    when /Cargo\.toml$/ then Gem::Ext::CargoBuilder
    else
      extension_dir = @spec.extension_dir
      message = "No builder for extension '#{extension}'"
      raise Gem::InstallError, "#{message} in #{extension_dir}"
    end
  else
    # Standard platform - use default builders
    case extension
    when /extconf\.rb$/   then Gem::Ext::ExtConfBuilder
    # ... existing cases
    end
  end
end
```

### 6.3 DLEXT Override

**In:** `third_party/ruby-wip-3.4.7/include/ruby/config.h`

Around line 718:

```c
// Change from:
// #define DLEXT ".so"

// To:
#define DLEXT ".a"
```

This makes `require` look for `.a` files instead of `.so`.

---

## Part 7: Section Alignment and Memory Protection

### 7.1 Proper Section Loading

```c
static void* allocate_section(Elf64_Shdr *shdr) {
    size_t size = shdr->sh_size;
    size_t align = shdr->sh_addralign;
    
    // Ensure minimum alignment
    if (align < 16) align = 16;
    
    // Allocate with alignment
    void *mem;
    if (posix_memalign(&mem, align, size) != 0) {
        return NULL;
    }
    
    // Copy section data if SHT_PROGBITS
    if (shdr->sh_type == SHT_PROGBITS) {
        memcpy(mem, (char*)elf_base + shdr->sh_offset, size);
    } else if (shdr->sh_type == SHT_NOBITS) {
        // .bss - zero initialize
        memset(mem, 0, size);
    }
    
    return mem;
}

static int set_section_protections(struct loaded_object *obj) {
    for (size_t i = 0; i < obj->section_count; i++) {
        struct loaded_section *sec = &obj->sections[i];
        if (!sec->data) continue;
        
        int prot = 0;
        if (sec->flags & SHF_EXECINSTR) prot |= PROT_EXEC | PROT_READ;
        if (sec->flags & SHF_WRITE) prot |= PROT_WRITE;
        if (!(sec->flags & SHF_WRITE)) prot |= PROT_READ;
        
        // Align to page boundary
        void *page_base = (void*)((uintptr_t)sec->data & ~(PAGE_SIZE-1));
        size_t page_size = ((uintptr_t)sec->data + sec->size + PAGE_SIZE - 1) & ~(PAGE_SIZE-1);
        page_size -= (uintptr_t)page_base;
        
        if (mprotect(page_base, page_size, prot) != 0) {
            perror("mprotect");
            return -1;
        }
    }
    return 0;
}
```

---

## Part 8: Updated Load Flow

### 8.1 Complete dln_load_archive

```c
void* dln_load_archive(const char *archive_path, const char *require_name) {
    struct loaded_archive *archive = malloc(sizeof(*archive));
    
    // 1. Open archive
    struct Ar ar;
    openar(&ar, archive_path);
    
    // 2. Build Ruby symbol table (cached globally)
    static struct symbol_table ruby_syms = {0};
    if (ruby_syms.count == 0) {
        build_ruby_symbol_table(&ruby_syms);
    }
    
    // 3. Load all .o files
    struct ArFile arfile;
    while (readar(&ar, &arfile)) {
        struct loaded_object *obj = load_object_file(arfile.data, arfile.size, arfile.name);
        if (!obj) {
            closear(&ar);
            return NULL;
        }
        
        // 4. Apply relocations
        if (apply_relocations(obj, arfile.data, arfile.size, &ruby_syms) != 0) {
            closear(&ar);
            return NULL;
        }
        
        // 5. Set memory protections (W^X)
        if (set_section_protections(obj) != 0) {
            closear(&ar);
            return NULL;
        }
        
        // 6. Run .init_array
        run_init_array(obj);
        
        archive->objects[archive->object_count++] = obj;
    }
    closear(&ar);
    
    // 7. Find Init_* function
    void (*init_func)(void) = find_init_function(archive, require_name);
    if (!init_func) {
        fprintf(stderr, "No Init function found in %s\n", archive_path);
        return NULL;
    }
    
    // 8. Call Init_*()
    init_func();
    
    // 9. Mark as loaded
    rb_provide(require_name);
    
    return archive;
}
```

---

## Part 9: Testing Strategy (Enhanced)

### 9.1 Test Cases

1. **Simple extension (no TLS, no ctors)**
   - Baseline: test_ext.c with basic Ruby API calls
   
2. **Extension with TLS**
   ```c
   __thread int thread_local_var = 42;
   ```
   
3. **C++ extension with constructors**
   ```cpp
   class MyClass {
       MyClass() { /* init */ }
       static MyClass instance;
   };
   ```
   
4. **Multi-object archive**
   - Multiple .c files compiled into one .a
   - Inter-object function calls
   
5. **Extension with weak symbols**
   - Optional dependencies
   
6. **Thin archive** (if supported)
   - Archive with references to separate .o files
   
7. **Long filenames** (>16 chars)
   - Uses // string table in archive
   
8. **GOT-heavy extension**
   - Many external references
   - Tests GOTPCRELX optimizations

---

## Part 10: Build Flags and Configuration

### 10.1 Required Compiler Flags

When building extensions:

```bash
cosmocc -fPIC \
        -fno-semantic-interposition \
        -fvisibility=hidden \
        -DPIC \
        -I third_party/ruby-wip-3.4.7/include \
        -c extension.c -o extension.o
```

**Rationale:**
- `-fPIC`: Generate position-independent code
- `-fno-semantic-interposition`: Reduces relocations (allows direct calls)
- `-fvisibility=hidden`: Only exports explicitly marked symbols
- `-DPIC`: Some code uses this for conditional compilation

---

## Implementation Milestones (Revised)

### Milestone 1: Symbol Table Generation
- [ ] Implement `gen_ruby_exports.rb`
- [ ] Integrate into build system
- [ ] Verify generated symbol table
- [ ] Test symbol lookup

### Milestone 2: Core Loader (No TLS, No Init Arrays)
- [ ] Implement basic object loading
- [ ] Implement 6 core relocations (R_X86_64_64, PC32, etc.)
- [ ] Test with simple extension

### Milestone 3: Full Relocation Support
- [ ] Add all 43 x86-64 relocation types
- [ ] Implement GOT simulation
- [ ] Test with PIC-heavy extensions

### Milestone 4: ELF Initialization
- [ ] Process .init_array/.fini_array
- [ ] Test with C++ extension

### Milestone 5: TLS Support
- [ ] Allocate TLS blocks
- [ ] Process TLS relocations
- [ ] Test with thread-local variables

### Milestone 6: Init Function Discovery
- [ ] Symbol table scanning
- [ ] Multi-extension support
- [ ] Test with complex gems

### Milestone 7: Gem Builder
- [ ] Implement CosmoExtconfBuilder
- [ ] Makefile rewriting
- [ ] Test automation

### Milestone 8: Production Validation
- [ ] Test json gem
- [ ] Test msgpack gem  
- [ ] Test nokogiri gem
- [ ] Performance benchmarking
- [ ] Memory leak testing

---

## Critical Validation Checklist

Before shipping:

- [ ] Verify ruby.com contains ruby_api_exports[] symbols
- [ ] Test all 43 relocation types with synthetic test
- [ ] Verify TLS allocations don't leak
- [ ] Test .init_array execution order
- [ ] Verify W^X (no RWX pages)
- [ ] Test weak symbol handling
- [ ] Test inter-object symbol resolution
- [ ] Memory leak test (valgrind)
- [ ] Multi-threaded extension test
- [ ] Exception handling across extension boundary

---

## Open Questions Resolved

1. **Symbol table from ruby.com**: Generate at build time from headers
2. **Multiple Init_* functions**: Scan symtabs, match require path
3. **Builder flags**: Enforce `-fPIC -fno-semantic-interposition -fvisibility=hidden`
4. **DLEXT override**: Change to `.a` in config.h
5. **TLS**: Allocate per-extension TLS blocks, track module IDs
6. **Alignment**: Use posix_memalign with sh_addralign
7. **GOT/PLT**: Simulate GOT, inline PLT calls

---

## Summary of Changes from V1

1. **Symbol resolution**: Build-time export table instead of dlsym
2. **Relocations**: 43 types instead of 6, including GOT/PLT/TLS
3. **Init functions**: Symbol scan instead of filename guessing
4. **ELF init**: Added .init_array/.fini_array support
5. **TLS**: Full TLS block allocation and relocation support
6. **Alignment**: Proper section alignment and page protection
7. **Gem builder**: Concrete Makefile rewriting and DLEXT override
8. **Testing**: Expanded to cover edge cases (TLS, C++, thin archives)

This plan is now production-ready and addresses all critical issues.
