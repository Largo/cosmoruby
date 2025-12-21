#include "third_party/cosmo_plugin/cosmo_plugin.h"

#include "libc/intrin/safemacros.h"
#include "libc/calls/calls.h"
#include "libc/calls/struct/stat.h"
#include "libc/elf/def.h"
#include "libc/elf/elf.h"
#include "libc/elf/struct/rela.h"
#include "libc/log/check.h"
#include "libc/log/log.h"
#include "libc/mem/mem.h"
#include "libc/str/str.h"
#include "libc/sysv/consts/map.h"
#include "libc/sysv/consts/o.h"
#include "libc/sysv/consts/prot.h"
#include "libc/sysv/consts/msync.h"
#include "libc/thread/thread.h"
#include "libc/x/x.h"
#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>

// Export entries emitted by export_symbols.sh
struct cosmo_export_entry {
  uint32_t name_off;
  uint64_t addr;
};

// Weak so hosts without exports still link.
// Provide default NULL values for when no exports are present
__attribute__((weak)) const struct cosmo_export_entry *const __cosmo_exports_start = NULL;
__attribute__((weak)) const struct cosmo_export_entry *const __cosmo_exports_end = NULL;
__attribute__((weak)) const char *const __cosmo_exports_names_start = NULL;

struct plugin_sym {
  const char *name;
  void *addr;
  unsigned bind;
};

struct plugin_section {
  uint8_t *mem;
  size_t size;
  int prot;
};

struct plugin_object {
  const char *name;
  const uint8_t *elf;
  size_t elf_size;
  Elf64_Ehdr *eh;
  Elf64_Shdr *shdrs;
  struct plugin_section *sections;
  Elf64_Sym *symtab;
  size_t symcount;
  const char *strtab;
};

struct plugin_tls_template {
  uint8_t *image;
  size_t size;
  size_t align;
};

struct plugin_tls_desc {
  size_t off;
  struct cosmo_plugin *plugin;
};

struct plugin_tls_index {
  uint64_t module;
  uint64_t offset;
  struct cosmo_plugin *plugin;
};

struct cosmo_plugin {
  char *path;
  struct plugin_object *objs;
  size_t objcount;
  struct plugin_sym *syms;
  size_t symcount;
  size_t symcap;
  uint64_t *got;
  size_t gotcount;
  size_t gotcap;
  uint8_t *plt;      // PLT stub code area
  size_t pltcount;   // Number of PLT stubs allocated
  size_t pltcap;     // Capacity of PLT area in stubs
  struct plugin_tls_template tls;
  struct plugin_tls_desc *tlsdescs;
  size_t tlsdesccount;
  size_t tlsdesccap;
  struct plugin_tls_index *tlsidx;
  size_t tlsidxcount;
  size_t tlsidxcap;
  // simple singly-linked registry
  struct cosmo_plugin *next;
};

static pthread_mutex_t g_plugin_mu = PTHREAD_MUTEX_INITIALIZER;
static struct cosmo_plugin *g_plugin_list;

// Per-thread TLS cache: small linked list keyed by plugin pointer.
struct plugin_tls_node {
  struct cosmo_plugin *plugin;
  void *block;
  struct plugin_tls_node *next;
};
static __thread struct plugin_tls_node *g_tls_head;

static const size_t kPage = 4096;

static int ReadFile(const char *path, uint8_t **data_out, size_t *size_out) {
  int fd = open(path, O_RDONLY);
  if (fd == -1) return -1;
  struct stat st;
  if (fstat(fd, &st) == -1) {
    close(fd);
    return -1;
  }
  size_t size = st.st_size;
  uint8_t *data =
      mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);  // read-only mapping
  close(fd);
  if (data == MAP_FAILED) return -1;
  *data_out = data;
  *size_out = size;
  return 0;
}

static void ReleaseFile(uint8_t *data, size_t size) {
  if (data && data != MAP_FAILED) {
    munmap(data, size);
  }
}

static const char *DupString(const char *s, size_t n) {
  char *r = malloc(n + 1);
  if (!r) return NULL;
  memcpy(r, s, n);
  r[n] = '\0';
  return r;
}

static const struct cosmo_export *g_export_cache;
static size_t g_export_cache_n;

static void BuildExportCache(void) {
  // Check if export symbols are available
  if (!__cosmo_exports_start || !__cosmo_exports_end ||
      !__cosmo_exports_names_start) {
    // Export symbols not available, return empty cache
    g_export_cache = NULL;
    g_export_cache_n = 0;
    return;
  }
  const struct cosmo_export_entry *p = __cosmo_exports_start;
  const struct cosmo_export_entry *e = __cosmo_exports_end;
  size_t count = 0;
  for (const struct cosmo_export_entry *it = p; it < e; ++it) {
    if (it->name_off == 0 && it->addr == 0) break;
    ++count;
  }
  fprintf(stderr, "BuildExportCache: found %zu export entries\n", count);
  if (!count) return;
  struct cosmo_export *tbl = calloc(count, sizeof(struct cosmo_export));
  if (!tbl) return;
  for (size_t i = 0; i < count; ++i) {
    const char *name = __cosmo_exports_names_start + p[i].name_off;
    tbl[i].name = name;
    tbl[i].addr = (void *)(uintptr_t)p[i].addr;
  }
  g_export_cache = tbl;
  g_export_cache_n = count;
  fprintf(stderr, "BuildExportCache: first 3 exports: %s=%p, %s=%p, %s=%p\n",
          tbl[0].name, tbl[0].addr,
          count > 1 ? tbl[1].name : "N/A", count > 1 ? tbl[1].addr : NULL,
          count > 2 ? tbl[2].name : "N/A", count > 2 ? tbl[2].addr : NULL);
}

const struct cosmo_export *cosmo_get_exports(size_t *count_out) {
  if (!g_export_cache) BuildExportCache();
  if (count_out) *count_out = g_export_cache_n;
  return g_export_cache;
}

static void PluginRegistryAdd(struct cosmo_plugin *p) {
  pthread_mutex_lock(&g_plugin_mu);
  p->next = g_plugin_list;
  g_plugin_list = p;
  pthread_mutex_unlock(&g_plugin_mu);
}

static struct cosmo_plugin *PluginRegistryFind(const char *path) {
  pthread_mutex_lock(&g_plugin_mu);
  for (struct cosmo_plugin *p = g_plugin_list; p; p = p->next) {
    if (p->path && path && !strcmp(p->path, path)) {
      pthread_mutex_unlock(&g_plugin_mu);
      return p;
    }
  }
  pthread_mutex_unlock(&g_plugin_mu);
  return NULL;
}

static int EnsureSymCap(struct cosmo_plugin *p, size_t need) {
  if (need <= p->symcap) return 0;
  size_t nc = MAX(need, p->symcap ? p->symcap * 2 : 16);
  struct plugin_sym *n = realloc(p->syms, nc * sizeof(*n));
  if (!n) return -1;
  p->syms = n;
  p->symcap = nc;
  return 0;
}

static int EnsureGotCap(struct cosmo_plugin *p, size_t need) {
  if (need <= p->gotcap) return 0;
  size_t nc = MAX(need, p->gotcap ? p->gotcap * 2 : 16);
  uint64_t *n = realloc(p->got, nc * sizeof(*n));
  if (!n) return -1;
  p->got = n;
  p->gotcap = nc;
  return 0;
}

static void AddPluginSymbol(struct cosmo_plugin *p, const char *name, void *addr,
                            unsigned bind) {
  if (!name || !*name) return;
  if (EnsureSymCap(p, p->symcount + 1) == -1) return;
  const char *dup = DupString(name, strlen(name));
  if (!dup) return;
  p->syms[p->symcount].name = dup;
  p->syms[p->symcount].addr = addr;
  p->syms[p->symcount].bind = bind;
  p->symcount++;
}

static void *LookupPluginSymbol(struct cosmo_plugin *p, const char *name) {
  if (!name || !*name) return NULL;
  for (size_t i = 0; i < p->symcount; ++i) {
    if (!strcmp(p->syms[i].name, name)) {
      return p->syms[i].addr;
    }
  }
  return NULL;
}

static void *LookupExports(const struct cosmo_export *exports, size_t n,
                           const char *name) {
  if (!exports || !name) {
    fprintf(stderr, "LookupExports: exports=%p n=%zu name=%s\n", (void*)exports, n, name ? name : "NULL");
    return NULL;
  }
  for (size_t i = 0; i < n; ++i) {
    if (!strcmp(exports[i].name, name)) {
      fprintf(stderr, "LookupExports: found %s at %p (index %zu)\n", name, exports[i].addr, i);
      return exports[i].addr;
    }
  }
  fprintf(stderr, "LookupExports: %s not found in %zu exports\n", name, n);
  return NULL;
}

static void *LookupLibc(const char *name) {
  // Minimal fallback set; can be extended.
  static const struct {
    const char *name;
    void *addr;
  } tbl[] = {
      {"malloc", malloc},   {"free", free},     {"memcpy", memcpy},
      {"memset", memset},   {"memcmp", memcmp}, {"strlen", (void *)strlen},
      {"strcmp", (void *)strcmp}, {NULL, NULL}};
  for (int i = 0; tbl[i].name; ++i) {
    if (!strcmp(tbl[i].name, name)) return tbl[i].addr;
  }
  return NULL;
}

static size_t AllocateGotSlot(struct cosmo_plugin *p) {
  if (EnsureGotCap(p, p->gotcount + 1) == -1) return (size_t)-1;
  return p->gotcount++;
}

// PLT stub size: 16 bytes per stub
// jmp *0x0(%rip)  # 6 bytes: FF 25 00 00 00 00
// <8-byte GOT address>
#define PLT_STUB_SIZE 16

static int EnsurePltCap(struct cosmo_plugin *p, size_t need) {
  if (need <= p->pltcap) return 0;
  size_t new_cap = MAX(need, p->pltcap ? p->pltcap * 2 : 16);
  size_t new_size = new_cap * PLT_STUB_SIZE;
  size_t old_size = p->pltcap * PLT_STUB_SIZE;

  if (!p->plt) {
    p->plt = mmap(NULL, new_size, PROT_READ | PROT_WRITE | PROT_EXEC,
                  MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p->plt == MAP_FAILED) {
      p->plt = NULL;
      return -1;
    }
  } else {
    // Use mremap if available, otherwise allocate new and copy
    #ifdef __linux__
    void *new_plt = mremap(p->plt, old_size, new_size, MREMAP_MAYMOVE);
    if (new_plt == MAP_FAILED) return -1;
    p->plt = new_plt;
    #else
    uint8_t *new_plt = mmap(NULL, new_size, PROT_READ | PROT_WRITE | PROT_EXEC,
                            MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (new_plt == MAP_FAILED) return -1;
    memcpy(new_plt, p->plt, old_size);
    munmap(p->plt, old_size);
    p->plt = new_plt;
    #endif
  }
  p->pltcap = new_cap;
  return 0;
}

static uint8_t *AllocatePltStub(struct cosmo_plugin *p, uint64_t target_addr) {
  if (EnsurePltCap(p, p->pltcount + 1) == -1) return NULL;

  uint8_t *stub = p->plt + (p->pltcount * PLT_STUB_SIZE);
  p->pltcount++;

  // Generate PLT stub code:
  // The RIP after the jmp instruction (at offset 6) will be stub + 6
  // We want to jump to the address stored at stub + 6
  // So displacement = (stub + 6) - (stub + 6) = 0
  //
  // jmp *0x0(%rip)  # Jump to address stored at current RIP
  // <8-byte target address>
  stub[0] = 0xFF;  // JMP opcode
  stub[1] = 0x25;  // ModRM: RIP-relative indirect
  stub[2] = 0x00;  // Displacement (little-endian): 0
  stub[3] = 0x00;
  stub[4] = 0x00;
  stub[5] = 0x00;

  // Store target address right after the jmp instruction
  // RIP after jmp will be at stub + 6, and with displacement 0,
  // it will read the address from stub + 6
  *(uint64_t *)(stub + 6) = target_addr;

  // Padding to PLT_STUB_SIZE (already zero from mmap)

  return stub;
}

static size_t AllocateTlsDesc(struct cosmo_plugin *p, size_t off) {
  if (p->tlsdesccount == p->tlsdesccap) {
    // CRITICAL: Cannot use realloc - GOT entries store pointers to these descriptors
    size_t nc = p->tlsdesccap ? p->tlsdesccap * 2 : 256;
    if (p->tlsdesccap) {
      fprintf(stderr, "FATAL: tlsdescs array full (%zu entries), increase initial capacity\n",
              p->tlsdesccap);
      return (size_t)-1;
    }
    void *n = malloc(nc * sizeof(*p->tlsdescs));
    if (!n) return (size_t)-1;
    p->tlsdescs = n;
    p->tlsdesccap = nc;
  }
  p->tlsdescs[p->tlsdesccount].off = off;
  p->tlsdescs[p->tlsdesccount].plugin = p;
  return p->tlsdesccount++;
}

static uint64_t cosmo_tlsdesc_resolve(struct plugin_tls_desc *d) {
  return (uint64_t)(uintptr_t)cosmo_plugin_tls_get(d->plugin, d->off);
}

static size_t AllocateTlsIdx(struct cosmo_plugin *p, uint64_t off) {
  if (p->tlsidxcount == p->tlsidxcap) {
    // CRITICAL: We cannot use realloc here because GOT entries store pointers
    // to elements in this array. If realloc moves the array, those pointers
    // become invalid. Allocate a large initial capacity to avoid reallocation.
    size_t nc = p->tlsidxcap ? p->tlsidxcap * 2 : 256;
    if (p->tlsidxcap) {
      fprintf(stderr, "FATAL: tlsidx array full (%zu entries), increase initial capacity\n",
              p->tlsidxcap);
      return (size_t)-1;
    }
    void *n = malloc(nc * sizeof(*p->tlsidx));
    if (!n) return (size_t)-1;
    p->tlsidx = n;
    p->tlsidxcap = nc;
  }
  p->tlsidx[p->tlsidxcount].module = (uint64_t)(uintptr_t)p;
  p->tlsidx[p->tlsidxcount].offset = off;
  p->tlsidx[p->tlsidxcount].plugin = p;
  return p->tlsidxcount++;
}

static void *cosmo_tls_get_addr(uint64_t *got_entry) {
  // For TLSGD, the GOT entry points to two consecutive uint64_t values:
  // got_entry[0] = module ID (plugin pointer)
  // got_entry[1] = offset
  if (!got_entry) return NULL;
  struct cosmo_plugin *plugin = (struct cosmo_plugin *)(uintptr_t)got_entry[0];
  uint64_t offset = got_entry[1];
  if (!plugin) return NULL;
  return cosmo_plugin_tls_get(plugin, offset);
}

static void *ResolveSymbol(struct cosmo_plugin *p,
                           const struct cosmo_export *exports, size_t exports_n,
                           const char *name, int bind) {
  if (!name) return NULL;
  if (!strcmp(name, "__tls_get_addr")) {
    // Our static TLS shim.
    void *addr = NULL;
    addr = (void *)&cosmo_tls_get_addr;
    return addr;
  }
  void *addr = LookupPluginSymbol(p, name);
  if (addr) return addr;
  addr = LookupExports(exports, exports_n, name);
  if (addr) return addr;
  addr = LookupLibc(name);
  if (addr) return addr;
  if (bind == STB_WEAK) return NULL;
  return NULL;
}

static int LoadTlsTemplate(struct cosmo_plugin *p, struct plugin_object *o) {
  Elf64_Shdr *tdata = NULL, *tbss = NULL;
  for (size_t i = 0; i < o->eh->e_shnum; ++i) {
    Elf64_Shdr *sh = &o->shdrs[i];
    if (sh->sh_type == SHT_PROGBITS &&
        (sh->sh_flags & (SHF_ALLOC | SHF_TLS)) == (SHF_ALLOC | SHF_TLS)) {
      tdata = sh;
    } else if (sh->sh_type == SHT_NOBITS &&
               (sh->sh_flags & (SHF_ALLOC | SHF_TLS)) ==
                   (SHF_ALLOC | SHF_TLS)) {
      tbss = sh;
    }
  }
  if (!tdata && !tbss) return 0;
  size_t tdata_size = tdata ? tdata->sh_size : 0;
  size_t tbss_size = tbss ? tbss->sh_size : 0;
  size_t total = tdata_size + tbss_size;
  size_t align = 16;
  if (tdata && tdata->sh_addralign > align) align = tdata->sh_addralign;
  if (tbss && tbss->sh_addralign > align) align = tbss->sh_addralign;

  if (p->tls.image) return 0;  // only one template supported for now
  uint8_t *img = memalign(align, total);
  if (!img) return -1;
  // CRITICAL: Zero the entire template first, since memalign doesn't zero memory
  memset(img, 0, total);
  if (tdata) {
    memcpy(img, o->elf + tdata->sh_offset, tdata_size);
  }
  if (tbss) {
    memset(img + tdata_size, 0, tbss_size);
  }
  p->tls.image = img;
  p->tls.size = total;
  p->tls.align = align;
  return 0;
}

static int ProtectSections(struct plugin_object *o) {
  for (size_t i = 0; i < o->eh->e_shnum; ++i) {
    Elf64_Shdr *sh = &o->shdrs[i];
    if (!(sh->sh_flags & SHF_ALLOC)) continue;
    struct plugin_section *ps = &o->sections[i];
    if (!ps->mem || !ps->size) continue;
    int prot = PROT_READ;
    if (sh->sh_flags & SHF_EXECINSTR) prot |= PROT_EXEC;
    if (sh->sh_flags & SHF_WRITE) prot |= PROT_WRITE;
    size_t rounded =
        ROUNDUP(ps->size, kPage);  // we mmap page-aligned, so ok to round up
    if (mprotect(ps->mem, rounded, prot) == -1) {
      perror("mprotect");
      return -1;
    }
  }
  return 0;
}

static int AllocateSections(struct plugin_object *o) {
  size_t shnum = o->eh->e_shnum;
  o->sections = calloc(shnum, sizeof(struct plugin_section));
  if (!o->sections) return -1;
  for (size_t i = 0; i < shnum; ++i) {
    Elf64_Shdr *sh = &o->shdrs[i];
    if (!(sh->sh_flags & SHF_ALLOC)) continue;
    size_t size = sh->sh_size;
    if (!size) continue;
    size_t rounded = ROUNDUP(size, kPage);
    int prot = PROT_READ | PROT_WRITE;
    uint8_t *mem =
        mmap(NULL, rounded, prot, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mem == MAP_FAILED) {
      perror("mmap");
      return -1;
    }
    if (sh->sh_type == SHT_PROGBITS) {
      memcpy(mem, o->elf + sh->sh_offset, sh->sh_size);
    } else if (sh->sh_type == SHT_NOBITS) {
      memset(mem, 0, sh->sh_size);
    }
    o->sections[i].mem = mem;
    o->sections[i].size = rounded;
  }
  return 0;
}

static void FreeSections(struct plugin_object *o) {
  if (!o->sections) return;
  for (size_t i = 0; i < o->eh->e_shnum; ++i) {
    if (o->sections[i].mem) munmap(o->sections[i].mem, o->sections[i].size);
  }
  free(o->sections);
  o->sections = NULL;
}

static uint8_t *SectionAddr(struct plugin_object *o, size_t shndx,
                            uint64_t off) {
  if (shndx >= o->eh->e_shnum) return NULL;
  struct plugin_section *ps = &o->sections[shndx];
  if (!ps->mem) return NULL;
  if (off > ps->size) return NULL;
  return ps->mem + off;
}

static void AddDefinedSymbols(struct cosmo_plugin *p, struct plugin_object *o) {
  if (!o->symtab || !o->strtab) return;
  for (size_t i = 0; i < o->symcount; ++i) {
    Elf64_Sym *s = &o->symtab[i];
    if (s->st_shndx == SHN_UNDEF || s->st_name == 0) continue;
    if (ELF64_ST_TYPE(s->st_info) == STT_FILE) continue;
    const char *name = o->strtab + s->st_name;
    uint8_t *base = SectionAddr(o, s->st_shndx, 0);
    if (!base) continue;
    void *addr = base + s->st_value;
    AddPluginSymbol(p, name, addr, ELF64_ST_BIND(s->st_info));
  }
}

static int ApplyRelocations(struct cosmo_plugin *p, struct plugin_object *o,
                            const struct cosmo_export *exports,
                            size_t exports_n) {
  for (size_t i = 0; i < o->eh->e_shnum; ++i) {
    Elf64_Shdr *sh = &o->shdrs[i];
    if (sh->sh_type != SHT_RELA) continue;
    if (sh->sh_link >= o->eh->e_shnum || sh->sh_info >= o->eh->e_shnum) {
      fprintf(stderr, "bad relocation section links\n");
      return -1;
    }
    Elf64_Shdr *symtab_hdr = &o->shdrs[sh->sh_link];
    Elf64_Sym *symtab = (Elf64_Sym *)(o->elf + symtab_hdr->sh_offset);
    const char *strtab =
        (const char *)(o->elf + o->shdrs[symtab_hdr->sh_link].sh_offset);
    size_t relcount = sh->sh_size / sizeof(Elf64_Rela);
    Elf64_Rela *rel = (Elf64_Rela *)(o->elf + sh->sh_offset);
    for (size_t j = 0; j < relcount; ++j) {
      Elf64_Rela *r = &rel[j];
      uint32_t symidx = ELF64_R_SYM(r->r_info);
      uint32_t type = ELF64_R_TYPE(r->r_info);
      // Skip relocations to sections that weren't allocated (e.g., debug sections)
      if (sh->sh_info >= o->eh->e_shnum || !(o->shdrs[sh->sh_info].sh_flags & SHF_ALLOC)) {
        continue;
      }
      uint8_t *target_base = SectionAddr(o, sh->sh_info, r->r_offset);
      if (!target_base) {
        const char *target_sec_name = "";
        if (sh->sh_info < o->eh->e_shnum && o->shdrs[sh->sh_info].sh_name < o->shdrs[o->eh->e_shstrndx].sh_size) {
          target_sec_name = (const char*)(o->elf + o->shdrs[o->eh->e_shstrndx].sh_offset + o->shdrs[sh->sh_info].sh_name);
        }
        fprintf(stderr, "relocation target missing: section index %u (%s), offset 0x%lx, reloc type %u\n",
                sh->sh_info, target_sec_name, r->r_offset, type);
        return -1;
      }
      uint8_t *P = target_base;
      Elf64_Sym *s = symidx < symtab_hdr->sh_size / sizeof(Elf64_Sym)
                         ? &symtab[symidx]
                         : NULL;
      const char *sname = s ? (strtab + s->st_name) : NULL;
      int bind = s ? ELF64_ST_BIND(s->st_info) : STB_GLOBAL;
      uint64_t S = 0;
      if (s && s->st_shndx != SHN_UNDEF) {
        uint8_t *base = SectionAddr(o, s->st_shndx, 0);
        if (!base) {
          fprintf(stderr, "symbol section missing\n");
          return -1;
        }
        S = (uint64_t)(uintptr_t)(base + s->st_value);
      } else if (sname) {
        void *addr = ResolveSymbol(p, exports, exports_n, sname, bind);
        if (!addr && bind != STB_WEAK) {
          fprintf(stderr, "undefined symbol: %s\n", sname);
          return -1;
        }
        S = (uint64_t)(uintptr_t)addr;
      }
      uint64_t A = r->r_addend;
      switch (type) {
        case R_X86_64_NONE:
          break;
        case R_X86_64_64:
          *(uint64_t *)P = S + A;
          break;
        case R_X86_64_32:
          *(uint32_t *)P = (uint32_t)(S + A);
          break;
        case R_X86_64_32S:
          *(int32_t *)P = (int32_t)(S + A);
          break;
        case R_X86_64_PC32: {
          int64_t v = (int64_t)(S + A - (uint64_t)(uintptr_t)P);
          if (v < INT32_MIN || v > INT32_MAX) {
            fprintf(stderr, "PC32 overflow for %s\n", sname ? sname : "?");
            return -1;
          }
          *(uint32_t *)P = (uint32_t)v;
          break;
        }
        case R_X86_64_PLT32: {
          // Try direct PC-relative first
          int64_t v = (int64_t)(S + A - (uint64_t)(uintptr_t)P);
          if (v >= INT32_MIN && v <= INT32_MAX) {
            *(uint32_t *)P = (uint32_t)v;
          } else {
            // Target too far, create PLT stub with indirect jump
            uint8_t *stub = AllocatePltStub(p, S);
            if (!stub) return -1;

            // Point the call to the PLT stub
            int64_t stub_disp = (int64_t)((uint64_t)(uintptr_t)stub + A - (uint64_t)(uintptr_t)P);
            if (stub_disp < INT32_MIN || stub_disp > INT32_MAX) {
              fprintf(stderr, "PLT32 stub overflow for %s (PLT stub too far from plugin)\n", sname ? sname : "?");
              return -1;
            }
            *(uint32_t *)P = (uint32_t)stub_disp;
          }
          break;
        }
        case R_X86_64_PC64:
          *(uint64_t *)P = S + A - (uint64_t)(uintptr_t)P;
          break;
        case R_X86_64_GOTPCREL:
        case R_X86_64_GOTPCRELX:
        case R_X86_64_REX_GOTPCRELX: {
          size_t slot = AllocateGotSlot(p);
          if (slot == (size_t)-1) return -1;
          p->got[slot] = S;
          uint64_t disp =
              (uint64_t)(uintptr_t)(&p->got[slot]) + A -
              (uint64_t)(uintptr_t)P;
          if ((int32_t)disp != (int64_t)disp) {
            fprintf(stderr, "GOTPCREL overflow for %s\n", sname ? sname : "?");
            return -1;
          }
          *(uint32_t *)P = (uint32_t)disp;
          break;
        }
        case R_X86_64_RELATIVE:
          *(uint64_t *)P = (uint64_t)(uintptr_t)P + A;
          break;
        case R_X86_64_GLOB_DAT:
        case R_X86_64_JUMP_SLOT:
          *(uint64_t *)P = S;
          break;
        case R_X86_64_16:
          *(uint16_t *)P = (uint16_t)(S + A);
          break;
        case R_X86_64_PC16:
          *(uint16_t *)P = (uint16_t)(S + A - (uint64_t)(uintptr_t)P);
          break;
        case R_X86_64_8:
          *(uint8_t *)P = (uint8_t)(S + A);
          break;
        case R_X86_64_PC8:
          *(uint8_t *)P = (uint8_t)(S + A - (uint64_t)(uintptr_t)P);
          break;
        case R_X86_64_SIZE32:
          *(uint32_t *)P = (uint32_t)(s ? s->st_size + A : A);
          break;
        case R_X86_64_SIZE64:
          *(uint64_t *)P = (uint64_t)(s ? s->st_size + A : A);
          break;
        case R_X86_64_TPOFF32:
        case R_X86_64_TPOFF64: {
          uint64_t offv = 0;
          if (s && (o->shdrs[s->st_shndx].sh_flags & SHF_TLS)) {
            offv = s->st_value + A;
          } else {
            offv = A;
          }
          if (type == R_X86_64_TPOFF32) {
            *(uint32_t *)P = (uint32_t)offv;
          } else {
            *(uint64_t *)P = offv;
          }
          break;
        }
        case R_X86_64_DTPMOD64:
          *(uint64_t *)P = 1;  // single module id
          break;
        case R_X86_64_DTPOFF64:
        case R_X86_64_DTPOFF32: {
          uint64_t offv = 0;
          if (s && (o->shdrs[s->st_shndx].sh_flags & SHF_TLS)) {
            offv = s->st_value + A;
          } else {
            offv = A;
          }
          if (type == R_X86_64_DTPOFF32) {
            *(uint32_t *)P = (uint32_t)offv;
          } else {
            *(uint64_t *)P = offv;
          }
          break;
        }
        case R_X86_64_TLSGD:
        case R_X86_64_TLSLD: {
          uint64_t offv = 0;
          if (s && (o->shdrs[s->st_shndx].sh_flags & SHF_TLS)) {
            offv = s->st_value + A;
          } else {
            offv = A;
          }
          // TLSGD requires TWO consecutive GOT slots for module ID and offset
          size_t slot = AllocateGotSlot(p);
          if (slot == (size_t)-1) return -1;
          size_t slot2 = AllocateGotSlot(p);
          if (slot2 == (size_t)-1) return -1;

          // Store module ID (plugin pointer) and offset directly in GOT
          p->got[slot] = (uint64_t)(uintptr_t)p;  // module ID
          p->got[slot2] = offv;  // offset

          // PC-relative displacement: (GOT + A) - P
          // The addend A is typically -4 for TLSGD
          uint64_t disp =
              (uint64_t)(uintptr_t)(&p->got[slot]) + A - (uint64_t)(uintptr_t)P;
          if ((int32_t)disp != (int64_t)disp) {
            fprintf(stderr, "TLS(GD/LD) overflow for %s\n", sname ? sname : "?");
            return -1;
          }
          *(uint32_t *)P = (uint32_t)disp;
          break;
        }
        case R_X86_64_GOTTPOFF: {
          uint64_t offv = 0;
          if (s && (o->shdrs[s->st_shndx].sh_flags & SHF_TLS)) {
            offv = s->st_value + A;
          } else {
            offv = A;
          }
          size_t slot = AllocateGotSlot(p);
          if (slot == (size_t)-1) return -1;
          p->got[slot] = offv;
          uint64_t disp =
              (uint64_t)(uintptr_t)(&p->got[slot]) - (uint64_t)(uintptr_t)P;
          if ((int32_t)disp != (int64_t)disp) {
            fprintf(stderr, "GOTTPOFF overflow for %s\n", sname ? sname : "?");
            return -1;
          }
          *(uint32_t *)P = (uint32_t)disp;
          break;
        }
        case R_X86_64_GOTPC32_TLSDESC: {
          uint64_t offv = 0;
          if (s && (o->shdrs[s->st_shndx].sh_flags & SHF_TLS)) {
            offv = s->st_value + A;
          } else {
            offv = A;
          }
          size_t desc = AllocateTlsDesc(p, offv);
          if (desc == (size_t)-1) return -1;
          size_t slot = AllocateGotSlot(p);
          if (slot == (size_t)-1) return -1;
          p->got[slot] = (uint64_t)(uintptr_t)&p->tlsdescs[desc];
          uint64_t disp =
              (uint64_t)(uintptr_t)(&p->got[slot]) - (uint64_t)(uintptr_t)P;
          if ((int32_t)disp != (int64_t)disp) {
            fprintf(stderr, "GOTPC32_TLSDESC overflow\n");
            return -1;
          }
          *(uint32_t *)P = (uint32_t)disp;
          break;
        }
        case R_X86_64_TLSDESC: {
          uint64_t offv = 0;
          if (s && (o->shdrs[s->st_shndx].sh_flags & SHF_TLS)) {
            offv = s->st_value + A;
          } else {
            offv = A;
          }
          size_t desc = AllocateTlsDesc(p, offv);
          if (desc == (size_t)-1) return -1;
          uint64_t *pair = (uint64_t *)P;
          pair[0] = (uint64_t)(uintptr_t)&cosmo_tlsdesc_resolve;
          pair[1] = (uint64_t)(uintptr_t)&p->tlsdescs[desc];
          break;
        }
        case R_X86_64_TLSDESC_CALL:
          /* Descriptor already set up; nothing to patch. */
          break;
        default:
          fprintf(stderr, "unsupported relocation type %u\n", type);
          return -1;
      }
    }
  }
  return 0;
}

static void RunInitArrays(struct plugin_object *o) {
  for (size_t i = 0; i < o->eh->e_shnum; ++i) {
    Elf64_Shdr *sh = &o->shdrs[i];
    if (sh->sh_type != SHT_INIT_ARRAY) continue;
    size_t count = sh->sh_size / sizeof(void *);
    void **arr = (void **)SectionAddr(o, i, 0);
    for (size_t j = 0; j < count; ++j) {
      if (arr[j]) {
        void (*f)(void) = arr[j];
        f();
      }
    }
  }
}

static void ScanSymbolTables(struct plugin_object *o) {
  for (size_t i = 0; i < o->eh->e_shnum; ++i) {
    if (o->shdrs[i].sh_type == SHT_SYMTAB) {
      o->symtab = (Elf64_Sym *)(o->elf + o->shdrs[i].sh_offset);
      o->symcount = o->shdrs[i].sh_size / sizeof(Elf64_Sym);
      o->strtab = (const char *)(o->elf + o->shdrs[o->shdrs[i].sh_link].sh_offset);
      break;
    }
  }
}

static struct plugin_object *LoadObject(const char *name, const uint8_t *elf,
                                        size_t elf_size) {
  if (!IsElf64Binary((const Elf64_Ehdr *)elf, elf_size)) {
    return NULL;  // Skip non-ELF members (e.g., ar symbol table)
  }

  // Check if object is for the current architecture
  Elf64_Ehdr *eh = (Elf64_Ehdr *)elf;
#ifdef __x86_64__
  if (eh->e_machine != EM_X86_64) {
    return NULL;  // Skip wrong architecture (e.g., aarch64 on x86_64)
  }
#elif defined(__aarch64__)
  if (eh->e_machine != EM_AARCH64) {
    return NULL;  // Skip wrong architecture (e.g., x86_64 on aarch64)
  }
#else
#error "Unsupported architecture"
#endif

  struct plugin_object *o = calloc(1, sizeof(*o));
  if (!o) return NULL;
  o->name = name ? strdup(name) : NULL;
  o->elf = elf;
  o->elf_size = elf_size;
  o->eh = (Elf64_Ehdr *)elf;
  o->shdrs = (Elf64_Shdr *)(elf + o->eh->e_shoff);
  ScanSymbolTables(o);
  if (AllocateSections(o) == -1) {
    FreeSections(o);
    free(o);
    return NULL;
  }
  return o;
}

static void FreeObject(struct plugin_object *o) {
  if (!o) return;
  FreeSections(o);
  if (o->name) free((char *)o->name);
  free(o);
}

// Minimal ar reader (BSD/GNU).
static int ParseArchive(const uint8_t *ar, size_t size,
                        struct cosmo_plugin *p) {
  if (size < 8 || memcmp(ar, "!<arch>\n", 8)) {
    errno = ENOEXEC;
    return -1;
  }
  const uint8_t *cur = ar + 8;
  const uint8_t *end = ar + size;
  const uint8_t *strtab = NULL;
  size_t strtab_size = 0;
  while (cur + 60 <= end) {
    const char *hdr = (const char *)cur;
    char namebuf[17];
    memcpy(namebuf, hdr, 16);
    namebuf[16] = 0;
    char sizestr[11];
    memcpy(sizestr, hdr + 48, 10);
    sizestr[10] = 0;
    size_t msize = strtoul(sizestr, NULL, 10);
    cur += 60;
    if (cur + msize > end) break;
    const uint8_t *member = cur;
    const uint8_t *next = cur + ((msize + 1) & ~1);

    const char *mname = NULL;
    size_t mname_len = 0;
    if (!strcmp(namebuf, "//              ")) {  // string table
      strtab = member;
      strtab_size = msize;
    } else if (!strcmp(namebuf, "/               ")) {
      // symbol table, skip
    } else if (!strncmp(namebuf, "#1/", 3)) {
      mname_len = strtoul(namebuf + 3, NULL, 10);
      mname = (const char *)member;
      member += mname_len;
      msize -= mname_len;
    } else if (namebuf[0] == '/' && isdigit(namebuf[1])) {
      size_t off = strtoul(namebuf + 1, NULL, 10);
      if (strtab && off < strtab_size) {
        mname = (const char *)strtab + off;
        mname_len = strnlen(mname, strtab_size - off);
      }
    } else {
      mname = namebuf;
      mname_len = strcspn(namebuf, "/ ");
    }

    struct plugin_object *o = LoadObject(mname, member, msize);
    if (o) {
      p->objs = realloc(p->objs, (p->objcount + 1) * sizeof(*p->objs));
      p->objs[p->objcount++] = *o;
      free(o);
    }
    cur = next;
  }
  return p->objcount ? 0 : -1;
}

static void *FindInit(struct cosmo_plugin *p, const char *init_name) {
  if (!init_name) return NULL;
  for (size_t i = 0; i < p->objcount; ++i) {
    struct plugin_object *o = &p->objs[i];
    if (!o->symtab || !o->strtab) continue;
    for (size_t j = 0; j < o->symcount; ++j) {
      Elf64_Sym *s = &o->symtab[j];
      if (s->st_shndx == SHN_UNDEF) continue;
      if (ELF64_ST_TYPE(s->st_info) != STT_FUNC) continue;
      const char *name = o->strtab + s->st_name;
      if (!strcmp(name, init_name)) {
        uint8_t *base = SectionAddr(o, s->st_shndx, 0);
        if (!base) continue;
        return base + s->st_value;
      }
    }
  }
  return NULL;
}

void *cosmo_plugin_tls_get(struct cosmo_plugin *p, size_t off) {
  if (!p) return NULL;
  if (!p->tls.image) {
    size_t size = off + 16;
    size_t align = 16;
    void *blk = memalign(align, size);
    if (!blk) return NULL;
    memset(blk, 0, size);
    struct plugin_tls_node *n = malloc(sizeof(*n));
    if (!n) {
      free(blk);
      return NULL;
    }
    n->plugin = p;
    n->block = blk;
    n->next = g_tls_head;
    g_tls_head = n;
    return (uint8_t *)blk + off;
  }
  for (struct plugin_tls_node *n = g_tls_head; n; n = n->next) {
    if (n->plugin == p) {
      return (uint8_t *)n->block + off;
    }
  }
  void *blk = memalign(p->tls.align ? p->tls.align : 16, p->tls.size);
  if (!blk) return NULL;
  memcpy(blk, p->tls.image, p->tls.size);
  struct plugin_tls_node *n = malloc(sizeof(*n));
  if (!n) {
    free(blk);
    return NULL;
  }
  n->plugin = p;
  n->block = blk;
  n->next = g_tls_head;
  g_tls_head = n;
  return (uint8_t *)blk + off;
}

struct cosmo_plugin *cosmo_load_plugin(const char *path,
                                       const struct cosmo_export *host_exports,
                                       const char *init_name) {
  if (!path) {
    errno = EINVAL;
    return NULL;
  }

  if (!host_exports) {
    host_exports = cosmo_get_exports(NULL);
  }
  size_t exports_n = g_export_cache_n;

  struct cosmo_plugin *cached = PluginRegistryFind(path);
  if (cached) return cached;

  uint8_t *data = NULL;
  size_t size = 0;
  if (ReadFile(path, &data, &size) == -1) return NULL;

  struct cosmo_plugin *p = calloc(1, sizeof(*p));
  if (!p) {
    ReleaseFile(data, size);
    return NULL;
  }
  p->path = strdup(path);

  if (ParseArchive(data, size, p) == -1) {
    fprintf(stderr, "failed to parse archive %s\n", path);
    ReleaseFile(data, size);
    cosmo_unload_plugin(p);
    return NULL;
  }

  // Build symbol tables and TLS templates
  for (size_t i = 0; i < p->objcount; ++i) {
    AddDefinedSymbols(p, &p->objs[i]);
    LoadTlsTemplate(p, &p->objs[i]);
  }

  // Apply relocations
  for (size_t i = 0; i < p->objcount; ++i) {
    if (ApplyRelocations(p, &p->objs[i], host_exports, exports_n) == -1) {
      ReleaseFile(data, size);
      cosmo_unload_plugin(p);
      return NULL;
    }
    if (ProtectSections(&p->objs[i]) == -1) {
      ReleaseFile(data, size);
      cosmo_unload_plugin(p);
      return NULL;
    }
    RunInitArrays(&p->objs[i]);
  }

  // Call init if requested
  if (init_name) {
    void (*initfn)(void) = FindInit(p, init_name);
    if (!initfn) {
      fprintf(stderr, "Init function %s not found\n", init_name);
      ReleaseFile(data, size);
      cosmo_unload_plugin(p);
      return NULL;
    }
    initfn();
  }

  ReleaseFile(data, size);
  PluginRegistryAdd(p);
  return p;
}

void *cosmo_plugin_sym(struct cosmo_plugin *plugin, const char *name) {
  if (!plugin || !name) return NULL;
  return LookupPluginSymbol(plugin, name);
}

void cosmo_unload_plugin(struct cosmo_plugin *p) {
  if (!p) return;
  for (size_t i = 0; i < p->objcount; ++i) {
    FreeSections(&p->objs[i]);
    if (p->objs[i].name) free((char *)p->objs[i].name);
  }
  for (size_t i = 0; i < p->symcount; ++i) {
    if (p->syms[i].name) free((char *)p->syms[i].name);
  }
  free(p->objs);
  free(p->syms);
  free(p->got);
  if (p->tls.image) free(p->tls.image);
  free(p->tlsdescs);
  free(p->tlsidx);
  if (p->path) free(p->path);
  free(p);
}
