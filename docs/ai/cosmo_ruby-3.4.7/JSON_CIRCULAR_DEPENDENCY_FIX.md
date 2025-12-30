# JSON Circular Dependency Fix

## Problem

The Ruby build was failing with:
```
third_party/ruby/tool/add_to_manifest.rb:5:in 'Kernel#require': cannot load such file -- json (LoadError)
```

## Root Cause Analysis

### The Circular Dependency

1. **Code Generation Phase**: The build system runs `ruby.codegen.mk` to generate config files
2. **Manifest Script**: `add_to_manifest.rb` is used to track generated files
3. **JSON Requirement**: The script used `require 'json'` (line 5)
4. **Extension System**: JSON is a C extension that needs to be compiled and linked
5. **Dynamic Extensions**: `config.h` has `#define EXTSTATIC 0` (line 707)
   - This means extensions are **dynamic plugins**, not statically linked
   - `THIRD_PARTY_RUBY_EXTENSIONS` becomes empty (ruby.deps.mk:60)
6. **Bootstrap Failure**: Code generation runs before Ruby is built, so JSON isn't available

### Build Flow

```
make o//third_party/ruby/ruby
  ↓
ruby.codegen target (generates config.h, rbconfig.rb, etc.)
  ↓
Runs: $(HOST_RUBY) add_to_manifest.rb manifest.json config.h ...
  ↓
add_to_manifest.rb: require 'json'  ← FAILS
  ↓
JSON extension not available (Ruby not built yet, EXTSTATIC=0)
```

### Why EXTSTATIC=0 Matters

From `ruby.deps.mk`:
```makefile
# Line 40: Read EXTSTATIC from config.h
RUBY_EXTSTATIC := $(shell sed -n 's/^#define[[:space:]]\\+EXTSTATIC[[:space:]]\\+\\([0-9]\\+\\)/\\1/p' third_party/ruby/include/ruby/config.h | head -1)
RUBY_EXTSTATIC ?= 1

# Lines 59-63: If EXTSTATIC=0, no static extensions
ifeq ($(RUBY_EXTSTATIC),0)
THIRD_PARTY_RUBY_EXTENSIONS :=
else
THIRD_PARTY_RUBY_EXTENSIONS := $(RUBY_ALL_EXTENSIONS)
endif
```

When `EXTSTATIC=0`:
- Extensions are built as `.a` archives in `o/$(MODE)/third_party/ruby/plugins/`
- Ruby binary doesn't have extensions statically linked
- Extensions are loaded dynamically at runtime via `dln_load()`
- This includes the JSON extension

## Solution

Rewrote `third_party/ruby/tool/add_to_manifest.rb` to **not** require the `json` library.

### Changes Made

**Before:**
```ruby
require 'json'

manifest = if File.exist?(manifest_path)
  JSON.parse(File.read(manifest_path))
else
  {}
end

File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")
```

**After:**
```ruby
# Parse JSON manually (simple key-value object only)
def parse_manifest(content)
  manifest = {}
  content.scan(/"([^"]+)":\s*"([^"]*)"/) do |k, v|
    manifest[k] = v
  end
  manifest
end

# Generate pretty JSON manually
def generate_json(manifest)
  return "{\n}\n" if manifest.empty?

  lines = ["{"]
  manifest.each_with_index do |(k, v), idx|
    comma = idx < manifest.size - 1 ? "," : ""
    lines << "  \"#{k}\": \"#{v}\"#{comma}"
  end
  lines << "}\n"
  lines.join("\n")
end

manifest = if File.exist?(manifest_path)
  parse_manifest(File.read(manifest_path))
else
  {}
end

File.write(manifest_path, generate_json(manifest))
```

### Why This Works

1. **No External Dependencies**: Uses only Ruby core features (String#scan, Array, Hash)
2. **Hermetic Build**: No reliance on C extensions during code generation
3. **Breaks Circular Dependency**: Code generation can run before any extensions are built
4. **Simple JSON Structure**: The manifest only contains string key-value pairs, so simple regex parsing is sufficient

### Testing

```bash
# Test with new manifest
$ ruby third_party/ruby/tool/add_to_manifest.rb /tmp/test.json foo bar
$ cat /tmp/test.json
{
  "foo": "bar"
}

# Test with existing manifest (parsing)
$ ruby third_party/ruby/tool/add_to_manifest.rb o//third_party/ruby/generated/manifest.json test value
# Successfully parses and updates existing 13-entry manifest
```

## Alternative Solutions Considered

### 1. Set EXTSTATIC=1 in config.h
**Pros**: JSON would be statically linked and available
**Cons**:
- Changes extension loading strategy for entire build
- Increases binary size
- Goes against the dynamic plugin system being developed

### 2. Use system Ruby for code generation
**Pros**: System Ruby has json library
**Cons**:
- Violates hermetic build principle (ruby.deps.mk lines 7-11)
- Unreliable across different development environments
- Not portable

### 3. Build miniruby with JSON first
**Pros**: Bootstrap-style approach, pure Cosmo
**Cons**:
- Adds build complexity
- miniruby already links only monitor/stringio/pathname (ruby.link.mk:214-216)
- Still circular: miniruby build would need codegen too

## Impact

- **Build System**: Code generation no longer depends on C extensions
- **Extensions**: Dynamic extension system (`EXTSTATIC=0`) continues to work
- **Hermetic Build**: Build remains self-contained without system Ruby dependency
- **Future**: Any code generation scripts should avoid requiring C extensions

## Files Modified

- `third_party/ruby/tool/add_to_manifest.rb` - Removed json dependency
- `third_party/ruby-wip-3.4.7/ruby.codegen.mk` - Fixed RUBYLIB paths (see follow-up issue)

## Build Verification

After this fix, the build should proceed past code generation:
```bash
$ bin/build_ruby.sh
# Should no longer fail with "cannot load such file -- json"
```

## Follow-up Issue: Missing stdlib in RUBYLIB

After fixing the JSON dependency, the build revealed a second issue where `make_encmake.rb` couldn't load `fileutils`:

```
third_party/ruby-wip-3.4.7/lib/mkmf.rb:7:in 'Kernel#require': cannot load such file -- fileutils (LoadError)
```

### Root Cause

The codegen makefiles were setting `RUBYLIB` without including the stdlib `lib/` directory:

```makefile
# Before (ruby.codegen.mk lines 270, 295, 319):
RUBYLIB=$(abspath $(RUBY_GENDIR)):$(abspath $(RUBY_SRCDIR))
# Results in: /path/to/o//third_party/ruby/generated:/path/to/third_party/ruby-wip-3.4.7
```

But Ruby standard library files are in `third_party/ruby-wip-3.4.7/lib/`, so they couldn't be loaded.

### Fix

Added `/lib` to RUBYLIB paths in three locations in `ruby.codegen.mk`:

```makefile
# After:
RUBYLIB=$(abspath $(RUBY_SRCDIR))/lib:$(abspath $(RUBY_GENDIR)):$(abspath $(RUBY_SRCDIR))
# Results in: /path/to/.../lib:/path/to/generated:/path/to/ruby-wip-3.4.7
```

**Modified lines:**
- Line 270: `enc.mk` generation
- Line 295: `ext/configure-ext.mk` generation
- Line 319: `exts.mk` generation

(Line 192 already had `./lib:` as a relative path)
