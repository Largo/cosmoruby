# Ruby Code Generation Plan - Amended

**Date:** 2025-11-01
**Status:** Ready for Implementation
**Goal:** Generate ALL files that MRI generates, compare with our versions, create patches

## Executive Summary

This plan extends the existing code generation system in `third_party/ruby-wip-3.4.7/ruby.codegen.mk` to generate every file that MRI's build process generates. Generated files go to `o//third_party/ruby/generated/`, are compared against source tree versions, and differences are captured as patches.

## Current State

### Already Implemented (7 file types)
1. ✅ `config.h` - Copied from reference
2. ✅ `rbconfig.rb` - Generated via mkconfig.rb
3. ✅ `verconf.h` - Generated from template
4. ✅ `revision.h` - Generated via file2lastrev.rb
5. ✅ `parse.c` and `parse.h` - Generated via lrama
6. ✅ `builtin_binary.inc` - Generated from template
7. ✅ Timestamp files - Various .time markers

### Infrastructure Already in Place
- ✅ Manifest system (`manifest.json`)
- ✅ Patch system (`patches/*.diff`)
- ✅ Helper script (`tool/add_to_manifest.rb`)
- ✅ Directory structure (`o//third_party/ruby/generated/`)

## Files to Add (6 new artifacts)

### 1. encdb.h (Encoding Database Header)

**Location in source:** `third_party/ruby/enc/encdb.h`
**Generated to:** `o//third_party/ruby/generated/encdb.h`
**Patch file:** `third_party/ruby/patches/encdb.diff`

**How MRI generates it:**
```bash
ruby --disable=gems ./tool/generic_erb.rb -c -o encdb.h \
    ./template/encdb.h.tmpl ./enc enc
```

**Dependencies:**
- `tool/generic_erb.rb` (exists)
- `template/encdb.h.tmpl` (exists)
- `enc/` directory with encoding sources (exists)

**Purpose:** Lists all available character encodings (ASCII, UTF-8, etc.)

---

### 2. transdb.h (Transcoding Database Header)

**Location in source:** `third_party/ruby/enc/transdb.h`
**Generated to:** `o//third_party/ruby/generated/transdb.h`
**Patch file:** `third_party/ruby/patches/transdb.diff`

**How MRI generates it:**
```bash
ruby --disable=gems ./tool/generic_erb.rb -c -o transdb.h \
    ./template/transdb.h.tmpl ./enc/trans enc/trans
```

**Dependencies:**
- `tool/generic_erb.rb` (exists)
- `template/transdb.h.tmpl` (exists)
- `enc/trans/` directory (exists)

**Purpose:** Lists all encoding transcoding pairs (UTF-8 ↔ Shift_JIS, etc.)

---

### 3. probes.h (DTrace/SystemTap Probes)

**Location in source:** Would be at `third_party/ruby/probes.h` (doesn't exist, created at build time)
**Generated to:** `o//third_party/ruby/generated/probes.h`
**Patch file:** `third_party/ruby/patches/probes.diff`

**How MRI generates it:**
```bash
echo making dummy probes.h
echo '#include "probes.dmyh"' > probes.h
```

**Dependencies:**
- None (simple echo command)

**Purpose:** Dynamic tracing support (Cosmopolitan uses dummy version)

---

### 4. enc.mk (Encoding Build Makefile)

**Location in source:** Not in source tree (generated only)
**Generated to:** `o//third_party/ruby/generated/enc.mk`
**Patch file:** `third_party/ruby/patches/enc.mk.diff` (will be empty - file doesn't exist in source)

**How MRI generates it:**
```bash
ruby --disable=gems -r./x86_64-linux-fake ./enc/make_encmake.rb \
    --builtin-encs="enc/ascii.o enc/us_ascii.o enc/unicode.o enc/utf_8.o" \
    --builtin-transes="enc/trans/newline.o" \
    --modulestatic enc.mk
```

**Dependencies:**
- `enc/make_encmake.rb` (exists)
- `x86_64-linux-fake.rb` (would need to generate first, OR use rbconfig.rb)

**Purpose:** MRI uses this to build encoding .so files. CosmoRuby statically links encodings, so this is for comparison only.

**Note:** This is tricky - it requires loading RbConfig. We'll generate it but won't use it in the build.

---

### 5. ext/configure-ext.mk (Extension Configuration Makefile)

**Location in source:** Not in source tree (generated only)
**Generated to:** `o//third_party/ruby/generated/ext/configure-ext.mk`
**Patch file:** `third_party/ruby/patches/ext-configure-ext.mk.diff`

**How MRI generates it:**
```bash
./miniruby -I./lib -I. -I.ext/common ./tool/generic_erb.rb \
    -o ext/configure-ext.mk -c \
    ./template/configure-ext.mk.tmpl --srcdir="." \
    --miniruby="./miniruby -I./lib -I. -I.ext/common" \
    --script-args='--dest-dir="" --extout=".ext" --ext-build-dir="./ext" --mflags="" --make-flags=""'
```

**Dependencies:**
- `tool/generic_erb.rb` (exists)
- `template/configure-ext.mk.tmpl` (exists)
- miniruby OR HOST_RUBY

**Purpose:** MRI uses this to configure dynamic extensions. CosmoRuby uses static BUILD.mk files. For comparison only.

---

### 6. exts.mk (Extension Build Makefile)

**Location in source:** Not in source tree (generated only)
**Generated to:** `o//third_party/ruby/generated/exts.mk`
**Patch file:** `third_party/ruby/patches/exts.mk.diff`

**How MRI generates it:**
```bash
./miniruby -I./lib -I. -I.ext/common ./tool/generic_erb.rb \
    -o exts.mk -c \
    ./template/exts.mk.tmpl --gnumake=yes \
    --configure-exts=ext/configure-ext.mk
```

**Dependencies:**
- `tool/generic_erb.rb` (exists)
- `template/exts.mk.tmpl` (exists)
- `ext/configure-ext.mk` (see #5 above)
- miniruby OR HOST_RUBY

**Purpose:** MRI uses this to build dynamic extensions. CosmoRuby uses static BUILD.mk files. For comparison only.

---

## Implementation Pattern

Each artifact follows this pattern in `ruby.codegen.mk`:

```makefile
################################################################################
# <artifact_name> generation (<description>)

RUBY_<NAME>_GEN := $(RUBY_GENDIR)/<filename>

$(<RUBY_NAME>_GEN): <dependencies> | $(RUBY_GENDIR)
	@<generation command>
	@$(HOST_RUBY) $(RUBY_ADD_TO_MANIFEST) $(RUBY_MANIFEST) <filename> <source_path>

THIRD_PARTY_RUBY_GENERATED += $(RUBY_<NAME>_GEN)

RUBY_<NAME>_PATCH := $(RUBY_PATCHDIR)/<filename>.diff

$(RUBY_<NAME>_PATCH): $(RUBY_<NAME>_GEN) | $(RUBY_PATCHDIR)
	@if [ -f <source_path> ]; then \
		diff -u <source_path> $(RUBY_<NAME>_GEN) > $@ || true; \
	else \
		touch $@; \
	fi

THIRD_PARTY_RUBY_PATCHES += $(RUBY_<NAME>_PATCH)
```

## Outstanding Follow-Ups

- `encinit.c` is still copied from the upstream port even though MRI generates it from the encoding registry. Add a generation rule mirroring MRI’s `tool/make_encinit.rb` pipeline so we refresh it alongside `encdb.h` and `transdb.h`.
- Confirm whether `third_party/ruby/ruby_cosmo_main.h` and `third_party/ruby/timezoneapi.h` are bespoke Cosmopolitan shims or generated artifacts. Document the decision; if upstream generates them, bring the generators into this plan.

## Detailed Implementation Steps

### Step 1: Add encdb.h Generation

**Add to ruby.codegen.mk after builtin_binary.inc section:**

```makefile
################################################################################
# encdb.h generation (encoding database header)

RUBY_ENCDB_GEN := $(RUBY_GENDIR)/encdb.h

$(RUBY_ENCDB_GEN): $(RUBY_TOOLDIR)/generic_erb.rb third_party/ruby/template/encdb.h.tmpl | $(RUBY_GENDIR)
	@cd $(RUBY_SRCDIR) && $(HOST_RUBY) tool/generic_erb.rb -c -o $(abspath $@) template/encdb.h.tmpl enc enc
	@$(HOST_RUBY) $(RUBY_ADD_TO_MANIFEST) $(RUBY_MANIFEST) encdb.h third_party/ruby/enc/encdb.h

THIRD_PARTY_RUBY_GENERATED += $(RUBY_ENCDB_GEN)

RUBY_ENCDB_PATCH := $(RUBY_PATCHDIR)/encdb.diff

$(RUBY_ENCDB_PATCH): $(RUBY_ENCDB_GEN) | $(RUBY_PATCHDIR)
	@if [ -f third_party/ruby/enc/encdb.h ]; then \
		diff -u third_party/ruby/enc/encdb.h $(RUBY_ENCDB_GEN) > $@ || true; \
	else \
		touch $@; \
	fi

THIRD_PARTY_RUBY_PATCHES += $(RUBY_ENCDB_PATCH)
```

### Step 2: Add transdb.h Generation

**Add to ruby.codegen.mk after encdb.h section:**

```makefile
################################################################################
# transdb.h generation (transcoding database header)

RUBY_TRANSDB_GEN := $(RUBY_GENDIR)/transdb.h

$(RUBY_TRANSDB_GEN): $(RUBY_TOOLDIR)/generic_erb.rb third_party/ruby/template/transdb.h.tmpl | $(RUBY_GENDIR)
	@cd $(RUBY_SRCDIR) && $(HOST_RUBY) tool/generic_erb.rb -c -o $(abspath $@) template/transdb.h.tmpl enc/trans enc/trans
	@$(HOST_RUBY) $(RUBY_ADD_TO_MANIFEST) $(RUBY_MANIFEST) transdb.h third_party/ruby/enc/transdb.h

THIRD_PARTY_RUBY_GENERATED += $(RUBY_TRANSDB_GEN)

RUBY_TRANSDB_PATCH := $(RUBY_PATCHDIR)/transdb.diff

$(RUBY_TRANSDB_PATCH): $(RUBY_TRANSDB_GEN) | $(RUBY_PATCHDIR)
	@if [ -f third_party/ruby/enc/transdb.h ]; then \
		diff -u third_party/ruby/enc/transdb.h $(RUBY_TRANSDB_GEN) > $@ || true; \
	else \
		touch $@; \
	fi

THIRD_PARTY_RUBY_PATCHES += $(RUBY_TRANSDB_PATCH)
```

### Step 3: Add probes.h Generation

**Add to ruby.codegen.mk after transdb.h section:**

```makefile
################################################################################
# probes.h generation (DTrace/SystemTap probes - dummy version)

RUBY_PROBES_GEN := $(RUBY_GENDIR)/probes.h

$(RUBY_PROBES_GEN): | $(RUBY_GENDIR)
	@echo '#include "probes.dmyh"' > $@
	@$(HOST_RUBY) $(RUBY_ADD_TO_MANIFEST) $(RUBY_MANIFEST) probes.h third_party/ruby/probes.h

THIRD_PARTY_RUBY_GENERATED += $(RUBY_PROBES_GEN)

RUBY_PROBES_PATCH := $(RUBY_PATCHDIR)/probes.diff

$(RUBY_PROBES_PATCH): $(RUBY_PROBES_GEN) | $(RUBY_PATCHDIR)
	@# probes.h is created dynamically by MRI, not checked into source
	@touch $@

THIRD_PARTY_RUBY_PATCHES += $(RUBY_PROBES_PATCH)
```

### Step 4: Add enc.mk Generation

**Add to ruby.codegen.mk after probes.h section:**

```makefile
################################################################################
# enc.mk generation (encoding build makefile - for comparison only)
# NOTE: CosmoRuby doesn't use this (static linking), but we generate it to
# compare against MRI's build process.

RUBY_ENCMK_GEN := $(RUBY_GENDIR)/enc.mk

$(RUBY_ENCMK_GEN): third_party/ruby/enc/make_encmake.rb $(RUBY_RBCONFIG_GEN) | $(RUBY_GENDIR)
	@cd $(RUBY_SRCDIR) && $(HOST_RUBY) -I./lib -I. -r ./lib/rbconfig.rb enc/make_encmake.rb \
		--builtin-encs="enc/ascii.o enc/us_ascii.o enc/unicode.o enc/utf_8.o" \
		--builtin-transes="enc/trans/newline.o" \
		--modulestatic $(abspath $@) 2>/dev/null || touch $@
	@$(HOST_RUBY) $(RUBY_ADD_TO_MANIFEST) $(RUBY_MANIFEST) enc.mk third_party/ruby/enc.mk

THIRD_PARTY_RUBY_GENERATED += $(RUBY_ENCMK_GEN)

RUBY_ENCMK_PATCH := $(RUBY_PATCHDIR)/enc.mk.diff

$(RUBY_ENCMK_PATCH): $(RUBY_ENCMK_GEN) | $(RUBY_PATCHDIR)
	@# enc.mk is not in source tree - it's generated at build time
	@touch $@

THIRD_PARTY_RUBY_PATCHES += $(RUBY_ENCMK_PATCH)
```

### Step 5: Add ext/configure-ext.mk Generation

**Add to ruby.codegen.mk after enc.mk section:**

```makefile
################################################################################
# ext/configure-ext.mk generation (extension config - for comparison only)
# NOTE: CosmoRuby doesn't use this (static BUILD.mk), but we generate it to
# compare against MRI's build process.

RUBY_EXT_CONFIGURE_GEN := $(RUBY_GENDIR)/ext/configure-ext.mk

$(RUBY_EXT_CONFIGURE_GEN): $(RUBY_TOOLDIR)/generic_erb.rb third_party/ruby/template/configure-ext.mk.tmpl | $(RUBY_GENDIR)
	@mkdir -p $(dir $@)
	@cd $(RUBY_SRCDIR) && $(HOST_RUBY) -I./lib -I. tool/generic_erb.rb \
		-o $(abspath $@) -c template/configure-ext.mk.tmpl \
		--srcdir="." \
		--miniruby="$(HOST_RUBY) -I./lib -I." \
		--script-args='--dest-dir="" --extout=".ext" --ext-build-dir="./ext" --mflags="" --make-flags=""' \
		2>/dev/null || touch $@
	@$(HOST_RUBY) $(RUBY_ADD_TO_MANIFEST) $(RUBY_MANIFEST) ext/configure-ext.mk third_party/ruby/ext/configure-ext.mk

THIRD_PARTY_RUBY_GENERATED += $(RUBY_EXT_CONFIGURE_GEN)

RUBY_EXT_CONFIGURE_PATCH := $(RUBY_PATCHDIR)/ext-configure-ext.mk.diff

$(RUBY_EXT_CONFIGURE_PATCH): $(RUBY_EXT_CONFIGURE_GEN) | $(RUBY_PATCHDIR)
	@# ext/configure-ext.mk is not in source tree - generated at build time
	@touch $@

THIRD_PARTY_RUBY_PATCHES += $(RUBY_EXT_CONFIGURE_PATCH)
```

### Step 6: Add exts.mk Generation

**Add to ruby.codegen.mk after ext/configure-ext.mk section:**

```makefile
################################################################################
# exts.mk generation (extension build makefile - for comparison only)
# NOTE: CosmoRuby doesn't use this (static BUILD.mk), but we generate it to
# compare against MRI's build process.

RUBY_EXTSMK_GEN := $(RUBY_GENDIR)/exts.mk

$(RUBY_EXTSMK_GEN): $(RUBY_TOOLDIR)/generic_erb.rb third_party/ruby/template/exts.mk.tmpl $(RUBY_EXT_CONFIGURE_GEN) | $(RUBY_GENDIR)
	@cd $(RUBY_SRCDIR) && $(HOST_RUBY) -I./lib -I. tool/generic_erb.rb \
		-o $(abspath $@) -c template/exts.mk.tmpl \
		--gnumake=yes \
		--configure-exts=$(abspath $(RUBY_EXT_CONFIGURE_GEN)) \
		2>/dev/null || touch $@
	@$(HOST_RUBY) $(RUBY_ADD_TO_MANIFEST) $(RUBY_MANIFEST) exts.mk third_party/ruby/exts.mk

THIRD_PARTY_RUBY_GENERATED += $(RUBY_EXTSMK_GEN)

RUBY_EXTSMK_PATCH := $(RUBY_PATCHDIR)/exts.mk.diff

$(RUBY_EXTSMK_PATCH): $(RUBY_EXTSMK_GEN) | $(RUBY_PATCHDIR)
	@# exts.mk is not in source tree - generated at build time
	@touch $@

THIRD_PARTY_RUBY_PATCHES += $(RUBY_EXTSMK_PATCH)
```

## Expected Outcomes

After implementation:

### Directory Structure
```
o/$(MODE)/third_party/ruby/generated/
├── manifest.json                    # Maps generated → source
├── config.h                         # Already done
├── rbconfig.rb                      # Already done
├── verconf.h                        # Already done
├── revision.h                       # Already done
├── parse.c                          # Already done
├── parse.h                          # Already done
├── builtin_binary.inc              # Already done
├── encdb.h                         # NEW
├── transdb.h                       # NEW
├── probes.h                        # NEW
├── enc.mk                          # NEW
├── ext/
│   └── configure-ext.mk            # NEW
└── exts.mk                         # NEW
```

### Patch Files
```
third_party/ruby/patches/
├── rbconfig.diff                   # Already created
├── verconf.diff                    # Already created
├── revision.diff                   # Already created
├── parse.c.diff                    # Already created
├── parse.h.diff                    # Already created
├── builtin_binary.inc.diff        # Already created
├── encdb.diff                      # NEW - compares enc/encdb.h
├── transdb.diff                    # NEW - compares enc/transdb.h
├── probes.diff                     # NEW - empty (not in source)
├── enc.mk.diff                     # NEW - empty (not in source)
├── ext-configure-ext.mk.diff      # NEW - empty (not in source)
└── exts.mk.diff                    # NEW - empty (not in source)
```

### Manifest JSON
```json
{
  "config.h": "third_party/ruby/include/ruby/config.h",
  "rbconfig.rb": "third_party/ruby/lib/rbconfig.rb",
  "verconf.h": "third_party/ruby/verconf.h",
  "revision.h": "third_party/ruby/revision.h",
  "parse.c": "third_party/ruby/parse.c",
  "parse.h": "third_party/ruby/parse.h",
  "builtin_binary.inc": "third_party/ruby/builtin_binary.inc",
  "encdb.h": "third_party/ruby/enc/encdb.h",
  "transdb.h": "third_party/ruby/enc/transdb.h",
  "probes.h": "third_party/ruby/probes.h",
  "enc.mk": "third_party/ruby/enc.mk",
  "ext/configure-ext.mk": "third_party/ruby/ext/configure-ext.mk",
  "exts.mk": "third_party/ruby/exts.mk"
}
```

## Testing & Verification

### Build Test
```bash
make -j8 o//third_party/ruby/ruby.codegen
```

Should generate all files without errors.

### Comparison Test
```bash
# Check which files match
for patch in third_party/ruby/patches/*.diff; do
    if [ -s "$patch" ]; then
        echo "DIFFERS: $(basename $patch)"
    else
        echo "MATCHES: $(basename $patch)"
    fi
done
```

### Manifest Test
```bash
# Verify manifest is valid JSON
python3 -m json.tool o/$(MODE)/third_party/ruby/generated/manifest.json

# Count entries
jq 'length' o/$(MODE)/third_party/ruby/generated/manifest.json
# Should output: 13
```

## Future Work

After this is complete:

1. **Review patches** - Examine non-empty .diff files to understand differences
2. **Decide per file:**
   - If generated matches source → remove source file, use generated version
   - If they differ → keep source file, document why in patch comments
3. **Update build** - For files we switch to generated versions, update ruby.compile.mk includes
4. **Document** - Create CODEGEN_DIFFERENCES.md explaining architectural choices

## Notes

### Why Some Files Won't Be Used

- **enc.mk, exts.mk, ext/configure-ext.mk**: MRI's dynamic loading system. CosmoRuby uses static linking via BUILD.mk files.
- **Generated for comparison only** to ensure we're not missing anything important.

### cocmd Limitations

Some generation commands use `2>/dev/null || touch $@` as fallback because:
- cocmd has limited shell feature support
- If generation fails, we create empty file so build continues
- Patch file will show it's empty/different from MRI's version

### Dependencies

- All generation happens in dependency order
- `rbconfig.rb` generated before `enc.mk` (enc.mk needs RbConfig)
- `ext/configure-ext.mk` before `exts.mk` (exts.mk references it)

## Template Directory Analysis 🙂

```
# done (- builtin_binary.inc.tmpl ✓)
-rw-r--r-- 1 groobiest groobiest    860 Oct  7 17:42 builtin_binary.inc.tmpl

# mentioned, not done (→ vm_call_iseq_optimized.inc exists)
-rw-r--r-- 1 groobiest groobiest   1792 Oct  7 17:42 call_iseq_optimized.inc.tmpl

# (- configure-ext.mk.tmpl ✓)
-rw-r--r-- 1 groobiest groobiest   1192 Oct  7 17:42 configure-ext.mk.tmpl

# (dependency management, optional)
-rw-r--r-- 1 groobiest groobiest     68 Oct  7 17:42 depend.tmpl

# Doxyfile.tmpl (documentation generation, optional)
-rw-r--r-- 1 groobiest groobiest 125563 Oct  7 17:42 Doxyfile.tmpl

# mentioned, not done (enc stuff) (- encdb.h.tmpl ✓) (- transdb.h.tmpl ✓)
-rw-r--r-- 1 groobiest groobiest   2675 Oct  7 17:42 encdb.h.tmpl
-rw-r--r-- 1 groobiest groobiest   1556 Oct  7 17:42 transdb.h.tmpl

# (extension initialization, generated differently)
-rw-r--r-- 1 groobiest groobiest    336 Oct  7 17:42 extinit.c.tmpl

# (- exts.mk.tmpl ✓)
-rw-r--r-- 1 groobiest groobiest   4873 Oct  7 17:42 exts.mk.tmpl

(- fake.rb.in ✓  (note: not .tmpl but used))
-rw-r--r-- 1 groobiest groobiest   1946 Oct  7 17:42 fake.rb.in

-rw-r--r-- 1 groobiest groobiest    728 Oct  7 17:42 GNUmakefile.in

# mentioned, not done (pre-generated in tarball)
-rw-r--r-- 1 groobiest groobiest    973 Oct  7 17:42 id.c.tmpl
-rw-r--r-- 1 groobiest groobiest   2814 Oct  7 17:42 id.h.tmpl

# mentioned, not done (pre-generated in tarball)
-rw-r--r-- 1 groobiest groobiest    565 Oct  7 17:42 known_errors.inc.tmpl

# (pre-generated in tarball?)
-rw-r--r-- 1 groobiest groobiest   2858 Oct  7 17:42 limits.c.tmpl

-rw-r--r-- 1 groobiest groobiest  24488 Oct  7 17:42 Makefile.in

# mentioned, not done (pre-generated as miniprelude.c in tarball)
-rw-r--r-- 1 groobiest groobiest   4848 Oct  7 17:42 prelude.c.tmpl

-rwxr-xr-x 1 groobiest groobiest    170 Oct  7 17:42 ruby-gdb.in

-rwxr-xr-x 1 groobiest groobiest    190 Oct  7 17:42 ruby-lldb.in

-rw-r--r-- 1 groobiest groobiest   1535 Oct  7 17:42 ruby.pc.in

-rw-r--r-- 1 groobiest groobiest    246 Oct  7 17:42 ruby-runner.h.in

(pre-generated in tarball?)
-rw-r--r-- 1 groobiest groobiest   1802 Oct  7 17:42 sizes.c.tmpl

(Unicode normalization, optional)
-rw-r--r-- 1 groobiest groobiest   6791 Oct  7 17:42 unicode_norm_gen.tmpl

(documentation, optional)
-rwxr-xr-x 1 groobiest groobiest   2051 Oct  7 17:42 unicode_properties.rdoc.tmpl

# done (- verconf.h.tmpl ✓)
-rw-r--r-- 1 groobiest groobiest   2399 Oct  7 17:42 verconf.h.tmpl
```

### Template Outcomes

1. **Pre-generated in the Ruby release tarball** (MRI ships these already expanded)
   - `id.c.tmpl`, `id.h.tmpl`
   - `known_errors.inc.tmpl`
   - `prelude.c.tmpl` → `miniprelude.c`
   - `call_iseq_optimized.inc.tmpl` → `vm_call_iseq_optimized.inc`
   - `limits.c.tmpl`, `sizes.c.tmpl`

2. **Generated during `make` (but not always during `make test`)**
   - `encdb.h.tmpl` → `enc/encdb.h`
   - `transdb.h.tmpl` → `enc/transdb.h`
   - `extinit.c.tmpl` → `ext/extinit.c`

3. **Regenerated on every build**
   - `verconf.h.tmpl` → `include/verconf.h`
   - `builtin_binary.inc.tmpl` → `builtin_binary.inc`

`.in` templates (e.g., `Makefile.in`, `GNUmakefile.in`, `ruby.pc.in`, `ruby-gdb.in`, `ruby-lldb.in`, `ruby-runner.h.in`, `fake.rb.in`) are processed at configure-time. They rely on `@VAR@` substitution, so the Cosmopolitan plan only needs to focus on `.tmpl` files that run through ERB at build time.

## Current Implementation Status

### Code Generation Makefile

- Added ERB-backed rules for `encdb.h`, `transdb.h`, `probes.h`, `enc.mk`, `ext/configure-ext.mk`, and `exts.mk`, mirroring MRI’s dependency order.
- Introduced a Ruby helper (`ruby_write_patch`) so cocmd-safe recipes can emit `.diff` files without shell conditionals.
- Normalised patch naming (e.g., `verconf.h.diff`, `rbconfig.rb.diff`), and cleaned the patch directory before each `ruby.codegen` run.
- Ensured `verconf.h` entries point to `third_party/ruby/include/verconf.h`; manifest generation records accurate source paths.
- Stubbed `builtin_binary.inc` generation via the host Ruby in cross mode; once Cosmopolitan’s `miniruby` exposes `RubyVM.each_builtin`, the rule can switch to native generation.

### Encoding Database Prep

- Added `ruby_prepare_encdir` helper to clone `enc/` into `o//…/enc-src`, excluding `encdb.h` and `transdb.h`, so templates don’t re-ingest previously generated headers. Both `encdb.h` and `transdb.h` recipes now run against that sanitized tree.

### Patch Hygiene

- `ruby.codegen.cleanpatches` removes stale `*.diff` files (and the historical `rbconfig.diff.tmp`) ahead of every build, guaranteeing the patch directory only contains fresh comparisons.

### Verification Helper

- New script `third_party/ruby-wip-3.4.7/tool/compare_manifest.rb` walks the manifest and, for each entry, prints `ls -l` metadata for the generated artifact, its source counterpart, and the corresponding patch file. This quickly highlights mismatches (missing sources, zero-length diffs, etc.) and complements the build/patch workflow.
