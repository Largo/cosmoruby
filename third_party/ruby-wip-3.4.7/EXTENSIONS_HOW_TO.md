# Ruby Extensions - Modular Build System

## Overview

Ruby extensions are now modular - each extension is built as a separate `.a` library and linked into the final `ruby.com` binary. The system uses **weak symbols** so extensions are only initialized if their `.a` files are actually linked. This means:

✅ **Changing one extension only rebuilds that extension** (~5 seconds)
✅ **Adding/removing extensions only rebuilds extinit.o** (~5 seconds)
✅ **Easy to add/remove extensions** - just edit one list and one file
✅ **Clean separation** - each extension has its own build configuration
✅ **Faster development** - no full Ruby rebuild when tweaking extensions

## How to Add a New Extension

1. **Create `ext/YOUR_EXT/BUILD.mk`** following this template:

```makefile
PKGS += THIRD_PARTY_RUBY_EXT_YOUR_EXT

THIRD_PARTY_RUBY_EXT_YOUR_EXT_A = o/$(MODE)/third_party/ruby/ext/YOUR_EXT/your_ext.a
THIRD_PARTY_RUBY_EXT_YOUR_EXT_SRCS = third_party/ruby/ext/YOUR_EXT/your_ext.c
THIRD_PARTY_RUBY_EXT_YOUR_EXT_OBJS = $(THIRD_PARTY_RUBY_EXT_YOUR_EXT_SRCS:%.c=o/$(MODE)/%.o)

THIRD_PARTY_RUBY_EXT_YOUR_EXT_DIRECTDEPS = LIBC_INTRIN LIBC_MEM

THIRD_PARTY_RUBY_EXT_YOUR_EXT_DEPS := \
    $(call uniq,$(foreach x,$(THIRD_PARTY_RUBY_EXT_YOUR_EXT_DIRECTDEPS),$($(x))))

$(THIRD_PARTY_RUBY_EXT_YOUR_EXT_A): \
    third_party/ruby/ext/YOUR_EXT/ \
    $(THIRD_PARTY_RUBY_EXT_YOUR_EXT_A).pkg \
    $(THIRD_PARTY_RUBY_EXT_YOUR_EXT_OBJS)

$(THIRD_PARTY_RUBY_EXT_YOUR_EXT_A).pkg: \
    $(THIRD_PARTY_RUBY_EXT_YOUR_EXT_OBJS) \
    $(foreach x,$(THIRD_PARTY_RUBY_EXT_YOUR_EXT_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/third_party/ruby/ext/YOUR_EXT/%.o: private \
    CFLAGS += -Ithird_party/ruby/include -Ithird_party/ruby -DRUBY_EXPORT

$(THIRD_PARTY_RUBY_EXT_YOUR_EXT_OBJS): third_party/ruby/ext/YOUR_EXT/BUILD.mk
```

2. **Include it in `BUILD.mk`** (at the top, around line 7-13):

```makefile
include third_party/ruby/ext/YOUR_EXT/BUILD.mk
```

3. **Add to extensions list** (around line 18-25):

```makefile
THIRD_PARTY_RUBY_EXTENSIONS = \
    THIRD_PARTY_RUBY_EXT_YOUR_EXT \
    ... existing extensions ...
```

4. **Register in `ext/extinit.c`**:

```c
void Init_ext(void)
{
    init(Init_YOUR_EXT, "YOUR_EXT");
    // ... existing extensions ...
}
```

5. **If extension has Ruby library files**, add to `third_party/ruby/package_ruby.sh`:

```bash
cp -r /path/to/cosmopolitan/third_party/ruby/ext/YOUR_EXT/lib/* cosmo-ruby/lib/ruby/3.4.0/
```

6. **Build and test**:

```bash
make -j24 o//third_party/ruby/ruby
bash third_party/ruby/package_ruby.sh
ruby.com -e "require 'YOUR_EXT'; puts 'works!'"
```

## How to Disable an Extension

1. **Comment out the include** in `BUILD.mk`:

```makefile
# include third_party/ruby/ext/YOUR_EXT/BUILD.mk  # DISABLED
```

2. **Remove from extensions list**:

```makefile
THIRD_PARTY_RUBY_EXTENSIONS = \
    # THIRD_PARTY_RUBY_EXT_YOUR_EXT \  # DISABLED
    ...
```

3. **Optional: Comment out in `ext/extinit.c`** (not strictly required due to weak symbols, but keeps code clean):

```c
void Init_ext(void)
{
    // init(Init_YOUR_EXT, "YOUR_EXT");  // DISABLED
    ...
}
```

Note: With weak symbols, the extension won't initialize even if left in extinit.c (the symbol will be NULL). But commenting it out is cleaner and rebuilds extinit.o (~5 seconds).

4. **Rebuild** - just relinks binaries, very fast

## How to Modify an Extension

**Before** (monolithic system):
- Edit `ext/psych/psych.c`
- Run `make` → rebuilds ALL of Ruby + all extensions (~60 seconds)

**Now** (modular system):
- Edit `ext/psych/psych.c`
- Run `make` → rebuilds ONLY psych extension + relinks Ruby (~5 seconds)

## Currently Enabled Extensions

See `ruby_extensions.txt` for the full list and dependencies.

## Troubleshooting

### Extensions not loading: "dlopen() isn't supported"

**Symptom**: After building and packaging, `ruby.com` fails to load extensions:
```
dlopen() isn't supported; consider using cosmo_dlopen() - /zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.so (LoadError)
```

**Diagnosis**: Check if `Init_ext()` is properly initialized:
```bash
# Check if Init_ext has code (should show multiple test/call instructions)
objdump -d o//third_party/ruby/ext/extinit.o | head -50

# If it's just "nop; ret", EXTSTATIC wasn't defined during compilation
```

**Cause**: The `extinit.c` file requires `EXTSTATIC` to be defined during compilation. Without it, the entire initialization block is compiled out.

**Fix**: Ensure `ruby.deps.mk` has the target-specific CFLAGS for `extinit.o`:
```makefile
o/$(MODE)/third_party/ruby/ext/extinit.o: private		\
	CFLAGS +=						\
		-DEXTSTATIC=$(RUBY_EXTSTATIC)			\
		-DSLIM_STATIC=$(RUBY_SLIM_STATIC)
```

**Verify**: After rebuilding, `Init_ext()` should contain code for each extension.

See `docs/ai/STATIC_EXTENSION_INIT_FIX.md` for complete details.

### Extension not found in static_ext_inits table

**Symptom**: Extension is built and linked, but `run_static_ext_init()` returns false.

**Diagnosis**: Check stub path vs registration name:
- Stub path: `/zip/lib/ruby/3.4.0/extensions/x86_64-cosmo/monitor.so`
- Registration: `monitor.so` (basename only)

**Fix**: The stub path detection in `load.c` should extract the basename. Verify it strips `/extensions/<arch>/` correctly.

### Weak symbol is NULL

**Symptom**: `Init_ext()` runs but `if (func)` checks fail (weak symbols are NULL).

**Cause**: Extension `.a` archive wasn't extracted during linking.

**Fix**: Verify `--whole-archive` is used in LDFLAGS:
```bash
# Check if extension archives are in RUBY_LINK_EXT_ARCHIVES
make -j1 -p o//third_party/ruby/ruby.dbg 2>/dev/null | grep RUBY_LINK_EXT_ARCHIVES

# Should show: --whole-archive <all extension .a files> --no-whole-archive
```

## File Locations

- **Extension BUILD.mk files**: `third_party/ruby/ext/*/BUILD.mk`
- **Main Ruby BUILD.mk**: `third_party/ruby/BUILD.mk`
- **Extension registration**: `third_party/ruby/ext/extinit.c`
- **Extension initialization fix**: `third_party/ruby/ruby.deps.mk` (extinit.o CFLAGS)
- **Stub path detection**: `third_party/ruby/load.c` (run_static_ext_init)
- **Packaging script**: `third_party/ruby/package_ruby.sh`
- **Documentation**: `third_party/ruby/ruby_extensions.txt`
