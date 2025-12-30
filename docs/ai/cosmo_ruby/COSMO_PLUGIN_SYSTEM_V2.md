# Cosmopolitan Plugin System V2: Safe, Language-Agnostic Position-Independent Archive Loading

## Goals (Revalidated)
- Runtime load of PIC `.a` archives without `dlopen`.
- Host symbol resolution that works on stripped, statically linked Cosmopolitan binaries.
- Complete relocation/TLS/ctor support for real-world PIC objects (x86_64 + aarch64).
- Safe memory layout (page-aligned `mmap`, W^X) and thread-safe plugin tracking.
- Language-agnostic API; bindings live outside Cosmopolitan core to respect “no core edits”.

## Core Architecture

```
Layer 3: Language Bindings (Ruby/Python/Lua/...)
  - thin shims in third_party/* calling cosmo_plugin_load()

Layer 2: Plugin API (third_party/cosmo_plugin/cosmo_plugin.h/.c)
  - load/archive/relocate/symbol lookup; thread-safe registry
  - no modifications to libc/ or build/

Layer 1: Export Table (per-host binary)
  - generated from final linked .dbg image
  - embedded as a relocation-free .rodata blob inside the host
```

### Policy Compliance
- **Do not touch** `libc/*`, `Makefile`, `build/*`, `tool/build/*`. All new code in `third_party/cosmo_plugin/` plus language shims in their respective third_party trees. Build integration via opt-in includes from language packages (e.g., `third_party/ruby-wip-3.4.7/BUILD.mk`).

## Export Table (Fixed)

### Problems Addressed
- Header scraping misses/over-includes symbols.
- V1/V2 attempted to paste an object via `objcopy --add-section`, leaving relocations unresolved and using invalid `extern void *foo;`.

### Robust Export Flow
1. **Inputs:** `o/$(MODE)/<lang>/<binary>.dbg` (unstripped, fully linked).
2. **Extractor script:** `third_party/cosmo_plugin/export_symbols.sh`:
   - Uses `readelf -Ws` on the `.dbg`.
   - Selects defined `GLOBAL`/`WEAK` `FUNC`/`OBJECT` symbols.
   - Optional prefix filter is configurable; default is *no filter* to keep this language-agnostic.
3. **Blob generator:** Produces a relocation-free C array of `{name, address}` by:
   - Emitting a `static const char[]` name pool.
   - Emitting a `static const struct cosmo_export { uint32_t name_off; uint64_t addr; }` table with **absolute addresses** taken from the `.dbg` symbols (no relocation needed).
   - No `extern` declarations; no references to host symbols at compile time.
4. **Linking:** Compile the generated C into an object and **link** it with the host binary in the language package link step (e.g., Ruby’s `ruby.link.mk` equivalent inside third_party). No `objcopy --add-section`.
5. **Stripping:** Strip after linking; the export blob is pure data and survives stripping.
6. **Runtime accessor:** `cosmo_get_exports()` returns a pointer to the blob inside the host; if absent, caller can supply a table explicitly.

## Plugin Loader (Safe Design)

### Location
- `third_party/cosmo_plugin/cosmo_plugin.h`
- `third_party/cosmo_plugin/cosmo_plugin.c`
- Optional: `third_party/cosmo_plugin/BUILD.mk` to build a static archive `cosmo_plugin.a` for consumers.

### Responsibilities
- Parse AR archives (reuse `tool/build/lib/ar.c` helpers via a local copy/wrapper; do **not** modify tool/build).
- Load ELF64 objects (x86-64 initially; plan for aarch64 later).
- Allocate segments with page-aligned `mmap`, group sections into RX/RW segments to keep PC-relative distances sane; set W^X after relocation.
- Apply **all** x86-64 relocations, including TLS descriptors and GOT/PLT forms.
- Handle `.init_array`/`.fini_array`/C++ ctors/dtors.
- Provide symbol resolution: host exports → other plugins → builtin libc set.
- Manage TLS for plugins in a way consistent with Cosmopolitan’s static TLS model.
- Thread-safe plugin registry with load-once semantics.

### Memory Layout
- Group sections by flags into segments:
  - RX segment: executable + RO data.
  - RW segment: data/BSS.
  - Optional TLS template segment (not mapped executable).
- Each segment allocated via `mmap(PROT_READ|PROT_WRITE)`; after relocations and ctors, downgrade permissions (`mprotect`).
- `plugin->base_addr` is the RX segment base; relative relocations use this base.

### Relocation Coverage (x86_64 + aarch64)
Implemented:
- x86_64: full GNU set including GOTPCREL[X], PLT32, RELATIVE/IRELATIVE, SIZE*, PC* variants, and the complete TLS suite: TLSGD/TLSLD, DTPMOD/DTPOFF/TPOFF, GOTTPOFF, GOTPC32_TLSDESC, TLSDESC/TLSDESC_CALL. COPY is rejected. Overflow checks on 32-bit displacements.
- aarch64: ADRP/ADD pairs, GOT_PAGE/LO12, PC-relative forms, ABS*, RELATIVE/IRELATIVE, PLT/GOT, and TLS (DTPMOD/DTPOFF/TPREL + TLSDESC equivalents) with the same offset-based TLS shim semantics.
Notes:
- Thin/long-name/multi-member archives are parsed; fat archives are filtered per-arch.
- PLT stubs are emitted for far calls (x86_64) to handle large archives.

### GOT Management
- Dynamic GOT table (hash map: symbol → slot). Allocate on demand; store pointers or TLS offsets.
- GOT entries live in the RW segment; relocations to GOTPCREL compute displacements to these slots.

### TLS Handling (Cosmopolitan-Compatible, now dual-arch)
- Extract TLS template (`.tdata` + `.tbss`), honor `sh_addralign`, **zero-init after memalign** before copying (fixed bug).
- Because Cosmopolitan uses static TLS, we emulate dynamic TLS via a shim:
  - Per-thread map keyed by plugin pointer → aligned template copy.
  - TLS relocations resolve to offsets; TLSDESC/GOTTPOFF/TPOFF/GD/LD consume those offsets and the resolver returns `cosmo_plugin_tls_get(p, off)`.
- __tls_get_addr ABI: resolver now reads module/offset directly from GOT slots (two uint64_t words) as stored by TLSGD/LD relocations.
- No automatic dtors (Cosmo lacks dynamic TLS dtors); document plugins must register thread cleanup if needed.

### Init/Fini
- Run `.init_array` in order; `.fini_array` on unload (unload still not exposed).
- Support multiple `Init_*`/`PyInit_*`/`luaopen_*` symbols per archive; binding layers decide which to call based on the requested module.

### Thread Safety
- Plugin registry protected by a mutex; double-checked load to avoid duplicate loads.
- Symbol lookup across plugins locks the registry or uses RCU-style read lock to prevent races.

## Language Bindings (Non-Core)

### Ruby
- New file: `third_party/ruby-wip-3.4.7/dln_cosmo.c` using `cosmo_load_plugin`.
- Init resolution: scan loaded objects for `Init_*`; pick the one matching require path (`foo/bar` → `Init_foo_bar` or basename), allow multiple extensions per archive.
- Do not change global `DLEXT`; perform dual lookup: `.a` first, then existing `.so` path for compatibility.
- Build integration in Ruby’s BUILD.mk only (no core build changes).

### Python
- `third_party/python/Python/dynload_cosmo.c`: wire into import machinery; find `PyInit_<mod>` via `cosmo_plugin_sym`.

### Lua
- Hook `package.loadlib` equivalent; call `luaopen_<mod>` from the plugin.

## Build Integration (Opt-In, Non-Core)

### Export Generation Rule (Template)
```
# Inputs: o/<mode>/<lang>/<bin>.dbg
o/$(MODE)/third_party/<lang>/<bin>_exports.c: o/$(MODE)/third_party/<lang>/<bin>.dbg
	third_party/cosmo_plugin/export_symbols.sh $< $@

o/$(MODE)/third_party/<lang>/<bin>_exports.o: o/$(MODE)/third_party/<lang>/<bin>_exports.c
	$(COMPILE) -c $< -o $@

# Link binary with exports + cosmo_plugin.a (no objcopy)
o/$(MODE)/third_party/<lang>/<bin>: ... o/$(MODE)/third_party/<lang>/<bin>_exports.o third_party/cosmo_plugin/cosmo_plugin.a
	$(LINK) ... $^ -o $@
```

### Export Script Knobs
- Optional env vars to filter symbols (e.g., `EXPORT_PREFIXES="rb_|ruby_|Py|lua_|__cosmo"`); default is no filter to keep it general.
- Verifies generated C has zero relocations (addresses baked from `readelf`).
- Export blob layout and symbols:
  - Generated C emits:
    - `static const char __cosmo_exports_names[] = { ... }` (null-terminated names concatenated).
    - `const struct cosmo_export __cosmo_exports[]` with `{uint32_t name_off; uint64_t addr;}` entries.
    - Sentinel `{0, 0}`.
  - Linker-visible symbols: `__cosmo_exports_start` (alias of `__cosmo_exports`), `__cosmo_exports_end` (past-the-end pointer), plus `__cosmo_exports_names_start/end` if needed. `cosmo_get_exports()` returns the start pointer; length is `__cosmo_exports_end - __cosmo_exports_start`.
  - Place the table in `.rodata` via `__attribute__((section(".rodata.cosmo_exports"), aligned(8)))` to avoid section spelunking and keep it strip-safe.

### Testing Targets
- Add test-only plugin fixtures under `third_party/cosmo_plugin/testdata/` with:
  - TLS (including TLSDESC), C++ ctors/dtors.
  - Multi-object archives, long filenames, thin archives.
  - Overflowing PC32 relocations to assert rejection.

## Testing Matrix
- Relocations: unit tests that each relocation kind patches the expected value (table-driven golden tests), including error cases for overflow (PC32/PLT32), unsupported types, and COPY rejection.
- TLS: per-thread isolation; TLSDESC/GOTTPOFF/TPOFF paths; stress with many threads; ensure offsets remain stable and blocks are distinct.
- Init/Fini: ordering correctness; multiple init symbols per archive; ensure chosen init matches require/import path; ensure unrelated init symbols are not run spuriously.
- GOTPCRELX/REX_GOTPCRELX: ensure optimized sequences resolve correctly with/without symbol definitions; measure that fallbacks don’t crash.
- Archives: thin archives, long filenames (>16), multi-object, mixed PIC/non-PIC rejection, and overflow distances for PC-relative relocations.
- Concurrency: concurrent loads of the same archive → single instantiation; concurrent loads of different archives → no deadlocks; registry lock correctness.
- W^X: after relocation, RX pages are non-writable; RW pages non-executable; verify with `mprotect` checks in tests.
- Compatibility: Ruby/Python/Lua bindings load simple and multi-extension archives; fallback to `.so` still works for existing extensions.

## Rollout Steps (Now)
1. Library + tests landed under `third_party/cosmo_plugin/` (fat builds for x86_64/aarch64).
2. Ruby integration enabled (exports + `.a` loader path). Repeat pattern for Python/Lua as needed.
3. Expand test matrix (thin archives, long names, concurrency, real-world gems), then consider optional unload support.

## Remaining Follow-Ups
- Optional: export filtering knobs per language.
- Optional: unload/fini and TLS block cleanup (dtors remain a limitation).
- Optional: quiet/guard debug logging once the matrix is green.

## Why This Fixes Prior Issues
- Export table is relocation-free, linked (not pasted), and derives from the actual linked image → survives strip and matches reality.
- No core build/libc modifications; everything lives in third_party and is opt-in per language.
- Complete relocation/TLS coverage on x86_64 and aarch64; TLSDESC/GD/LD are implemented with correct module/offset storage.
- W^X-safe, page-aligned mmap; far-call PLT stubs for large archives; fat archive arch filtering to avoid wrong-arch loads.
- Multi-init support and dual-extension lookup keep compatibility with existing `.so` flows while enabling `.a` plugins.
