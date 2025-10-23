# Ruby ZIP-Embedded Dynamic Extension Loader

**Status**: Planning Phase
**Created**: 2025-10-23
**Goal**: Enable Ruby native extensions (.so files) to be packaged in ZIP filesystem and loaded dynamically

## Executive Summary

Currently, Ruby native extensions must be statically compiled into the Ruby binary. This requires:
- Modifying extension code for compatibility
- Recompiling Ruby for every extension change
- Large binary size growth

**Proposed Solution**: Package pre-compiled `.so` files in the ZIP filesystem at `/zip/lib/ruby/3.4.0/extensions/` and dynamically load them on-demand using a custom loader that extracts and `dlopen()`s them.

## Motivation

### Current Limitations

**Static Linking Approach** (current):
- ✅ Single binary, truly portable
- ✅ No runtime dependencies
- ❌ Must modify extension code (rb_provide, etc.)
- ❌ Recompile entire Ruby for extension changes
- ❌ Binary grows with every extension (~52MB already)
- ❌ Can't use unmodified gems with native extensions
- ❌ Currently: 6 bundled gems unusable (bigdecimal, debug, nkf, racc, rbs, syslog)

**Dynamic Loading Approach** (proposed):
- ✅ Extensions unchanged (standard .so files)
- ✅ Rebuild extensions independently
- ✅ Smaller base binary
- ✅ Standard gem installation workflow
- ✅ Can install any gem with native extensions
- ⚠️ Need custom loader (one-time implementation)
- ⚠️ Runtime extraction overhead (mitigated by caching)

### Use Cases Enabled

1. **Bundled gem native extensions**: bigdecimal, debug, nkf, racc, rbs, syslog
2. **User-installed gems**: `gem.com install nokogiri` (C extensions)
3. **Development workflow**: Rebuild single extension without full Ruby rebuild
4. **Binary size**: Keep core Ruby small, extensions loaded on-demand

## Architecture

### Directory Structure

```
/zip/
  lib/
    ruby/
      3.4.0/
        *.rb                           # Ruby stdlib files
        extensions/
          x86_64-linux/                # Platform-specific extensions
            3.4.0/
              bigdecimal.so            # Bundled gem extensions
              debug.so
              nkf.so
              racc.so
              rbs.so
              syslog.so
        gems/
          3.4.0/
            gems/
              nokogiri-1.16.0/         # User-installed gems
                lib/
                  nokogiri/
                    2.4/
                      nokogiri.so      # Gem's native extension
```

### Component Design

#### 1. Extension Loader Hook

**File**: `third_party/ruby/lib/rubygems/cosmopolitan_loader.rb`

Intercepts `require` for `.so` files:

```ruby
module Gem
  class CosmopolitanLoader
    CACHE_DIR = ENV['RUBY_EXT_CACHE'] || '/tmp/.ruby-extensions'

    def self.require_so(path)
      # 1. Check if .so exists in ZIP
      zip_path = find_so_in_zip(path)
      return false unless zip_path

      # 2. Extract to cache if not present
      cached_path = cache_so(zip_path)

      # 3. Load via standard dlopen
      require cached_path
      true
    end

    private

    def self.find_so_in_zip(name)
      # Search order:
      # 1. /zip/lib/ruby/3.4.0/extensions/x86_64-linux/3.4.0/#{name}.so
      # 2. /zip/lib/ruby/gems/3.4.0/gems/*/lib/**/#{name}.so
    end

    def self.cache_so(zip_path)
      cache_path = "#{CACHE_DIR}/#{Digest::SHA256.file(zip_path)}/#{File.basename(zip_path)}"

      unless File.exist?(cache_path)
        FileUtils.mkdir_p(File.dirname(cache_path))
        File.binwrite(cache_path, File.binread(zip_path))
        File.chmod(0755, cache_path)
      end

      cache_path
    end
  end
end

# Hook into require
module Kernel
  alias_method :original_require, :require

  def require(path)
    if path.end_with?('.so')
      Gem::CosmopolitanLoader.require_so(path) || original_require(path)
    else
      original_require(path)
    end
  end
end
```

#### 2. Build System for Extensions

**File**: `third_party/ruby/ext/BUILD_EXTENSIONS.mk` (new)

```makefile
# Build native extensions as .so files

# Extension source directories
RUBY_EXT_BIGDECIMAL_SRCS = $(wildcard third_party/ruby/ext/bigdecimal/*.c)
RUBY_EXT_DEBUG_SRCS = $(wildcard third_party/ruby/ext/debug/*.c)
# ... etc

# Extension .so targets
o/$(MODE)/third_party/ruby/extensions/bigdecimal.so: $(RUBY_EXT_BIGDECIMAL_SRCS)
	@mkdir -p $(@D)
	$(CC) -shared -fPIC $(CFLAGS) $(INCLUDES) -o $@ $^

# Similar for other extensions...
```

#### 3. Packaging Integration

**Modify**: `o/scripts/package_ruby.sh`

```bash
# After copying stdlib and gems...

# Copy compiled extensions
mkdir -p cosmo-ruby/lib/ruby/3.4.0/extensions/x86_64-linux/3.4.0
cp o//third_party/ruby/extensions/*.so \
   cosmo-ruby/lib/ruby/3.4.0/extensions/x86_64-linux/3.4.0/
```

## Implementation Plan

### Phase 1: Proof of Concept (Single Extension)

**Target**: Get `bigdecimal` working via dynamic loading

**Steps**:

1. **Build bigdecimal.so**
   - Create minimal Makefile for bigdecimal extension
   - Compile with `-shared -fPIC` flags
   - Output: `o//third_party/ruby/extensions/bigdecimal.so`
   - Verify: `ldd o//third_party/ruby/extensions/bigdecimal.so` (should link to Ruby symbols)

2. **Manual ZIP embedding test**
   ```bash
   # Create test structure
   mkdir -p /tmp/ruby-ext-test/lib/ruby/3.4.0/extensions/x86_64-linux/3.4.0
   cp o//third_party/ruby/extensions/bigdecimal.so /tmp/ruby-ext-test/lib/ruby/3.4.0/extensions/x86_64-linux/3.4.0/

   # Create ZIP
   cd /tmp/ruby-ext-test
   zip -r /tmp/ext-test.zip *

   # Embed in ruby.com
   zipcopy /tmp/ext-test.zip o//third_party/ruby/ruby.com
   ```

3. **Create minimal loader**
   - Simple Ruby script that:
     - Checks `/zip/lib/ruby/3.4.0/extensions/x86_64-linux/3.4.0/bigdecimal.so`
     - Copies to `/tmp/bigdecimal.so`
     - Calls `require '/tmp/bigdecimal.so'`

4. **Test**
   ```bash
   ruby.com -e "require 'bigdecimal'; puts BigDecimal('1.5')"
   ```

5. **Validate**
   - Extension loads successfully
   - Functions work correctly
   - No memory leaks (run with valgrind)

### Phase 2: Loader Infrastructure

**Goal**: Robust, production-ready loader

**Tasks**:

1. **Create cosmopolitan_loader.rb** (as designed above)
   - Implement search path logic
   - Implement caching mechanism
   - Add error handling
   - Add logging/debugging

2. **Hook into RubyGems**
   - Ensure `Gem.find_files` knows about ZIP paths
   - Update `Gem.default_ext_dir` to return ZIP path
   - Make `gem install` put .so files in correct location

3. **Cache management**
   - Default: `/tmp/.ruby-extensions-#{Process.pid}/`
   - Cleanup on Ruby exit (at_exit hook)
   - Optional: persistent cache with SHA checksums

### Phase 3: Build System Integration

**Goal**: Automate extension building

**Tasks**:

1. **Create extension build rules**
   - Add to `third_party/ruby/BUILD.mk`
   - Each extension gets `.so` target
   - Shared flags: `-shared -fPIC -I... -L...`

2. **Extension discovery**
   - Auto-detect extensions in `ext/*/extconf.rb`
   - Generate build rules dynamically

3. **Packaging automation**
   - Update `package_ruby.sh` to include extensions
   - Organize by architecture (`x86_64-linux/`, `aarch64-linux/`)

### Phase 4: All Bundled Extensions

**Goal**: All 6 bundled gem native extensions working

**Extensions**:
- bigdecimal
- debug
- nkf
- racc
- rbs
- syslog

**Validation**: `gem.com list` shows all 29 gems as loadable

### Phase 5: User Gem Installation

**Goal**: `gem.com install GEMNAME` works for gems with native extensions

**Challenges**:
1. Gem build needs working compiler in ZIP
2. Or: pre-compile extensions during installation
3. Extension paths must work with ZIP filesystem

**Solutions**:
- Option A: Ship cosmocc in ZIP, use for compilation
- Option B: Extract gem, compile outside ZIP, copy .so back
- Option C: Pre-compiled gem repository for common gems

## Technical Challenges & Solutions

### Challenge 1: Symbol Resolution

**Problem**: Extension `.so` needs to resolve Ruby symbols (e.g., `rb_define_class`)

**Solution**: Ruby binary must export symbols
```makefile
# In BUILD.mk
$(THIRD_PARTY_RUBY_A): private LDFLAGS += -Wl,--export-dynamic
```

**Verify**:
```bash
nm -D o//third_party/ruby/ruby | grep rb_define_class
```

### Challenge 2: Extension Dependencies

**Problem**: Extensions depend on each other (e.g., `rbs` depends on `bigdecimal`)

**Solution**:
- Load dependencies first (topological sort)
- Or: link dependencies into each .so
- Or: lazy loading - let dlopen resolve

### Challenge 3: Platform Detection

**Problem**: Cosmopolitan binaries run on multiple platforms

**Solution**:
- Detect platform at runtime: `RbConfig::CONFIG['arch']`
- Package multiple .so versions:
  ```
  /zip/lib/ruby/3.4.0/extensions/
    x86_64-linux/
    aarch64-linux/
    x86_64-darwin/
    x86_64-windows/
  ```
- Loader selects correct directory

### Challenge 4: ZIP Filesystem Extraction

**Problem**: `dlopen()` requires real file, not ZIP entry

**Solution** (already designed):
- Extract to `/tmp` on first `require`
- Cache extracted files
- Clean up on exit

**Optimization**:
- Use mmap for faster extraction
- Persistent cache with SHA verification

### Challenge 5: Build-Time Compilation

**Problem**: Building .so requires compiler configuration

**Solution**:
- Use Ruby's existing extconf.rb infrastructure
- Set up proper include paths: `-Ithird_party/ruby/include`
- Link against Ruby symbols: `-Lbuild/dir -lruby` (or use --export-dynamic)

### Challenge 6: Gem Installation Workflow

**Problem**: `gem install` expects writeable filesystem

**Solution**:
- User gems go to `~/.gem/ruby/3.4.0/` (outside ZIP)
- Bundled gems stay in `/zip/lib/ruby/gems/3.4.0/`
- Loader searches both locations

## Benefits & Trade-offs

### Benefits

1. **Standard Ruby Gems Work**: Unmodified gems with native extensions install and run
2. **Smaller Core Binary**: Extensions loaded on-demand, not linked statically
3. **Faster Development**: Rebuild single extension, not entire Ruby
4. **Familiar Workflow**: Standard `gem install`, `bundle install` commands
5. **Platform Flexibility**: Ship multiple .so versions for different platforms

### Trade-offs

1. **Extraction Overhead**: First load ~1-5ms per extension (mitigated by caching)
2. **Disk Space**: Temporary cache in `/tmp` (cleaned on exit)
3. **Complexity**: Custom loader adds ~200 lines of Ruby code
4. **Not Pure Single-File**: Cache files in /tmp (but auto-cleaned)

### Comparison Matrix

| Aspect | Static Linking | ZIP Dynamic Loading |
|--------|---------------|-------------------|
| Binary size | Large (~52MB+) | Smaller (~30MB core) |
| Portability | Single file | Single file + /tmp cache |
| Gem compatibility | Modified gems only | Standard gems work |
| Development speed | Slow (full rebuild) | Fast (rebuild .so only) |
| Runtime overhead | None | ~1-5ms first load |
| Implementation | Simple | Moderate complexity |

## Success Criteria

### Proof of Concept (Phase 1)
- [ ] bigdecimal.so compiles with correct flags
- [ ] bigdecimal.so embeds in ZIP successfully
- [ ] Loader extracts and caches .so file
- [ ] `require 'bigdecimal'` works via loader
- [ ] BigDecimal operations return correct results
- [ ] No memory leaks (valgrind clean)

### Production Ready (Phases 2-4)
- [ ] All 6 bundled extensions load dynamically
- [ ] `gem.com list` shows 29 working gems
- [ ] Loader handles errors gracefully
- [ ] Cache cleanup works correctly
- [ ] Performance acceptable (<5ms overhead)
- [ ] Works on Linux, macOS, Windows

### User Gems (Phase 5)
- [ ] `gem.com install nokogiri` succeeds
- [ ] Nokogiri functions correctly
- [ ] User gems isolated from bundled gems
- [ ] Build process documented

## Open Questions

1. **Symbol export strategy**:
   - Export all Ruby symbols? (--export-dynamic)
   - Or export specific symbols? (linker script)
   - Trade-off: binary size vs compatibility

2. **Multi-platform support**:
   - Ship .so for all platforms in one ZIP?
   - Or platform-specific builds?
   - How big would multi-platform ZIP be?

3. **Cache persistence**:
   - Always use /tmp (ephemeral)?
   - Or persistent cache in ~/.ruby-cosmo/?
   - Security implications of persistent cache?

4. **Extension build location**:
   - Compile during `make` (build-time)?
   - Or compile during `package_ruby.sh` (packaging-time)?
   - Or compile on-demand during `gem install` (runtime)?

5. **RubyGems integration depth**:
   - Minimal hook (just intercept require)?
   - Or deep integration (modify Gem::Installer)?
   - How to handle gem specifications?

## Next Steps

1. **Review this plan** - Validate architecture and approach
2. **Prototype Phase 1** - Build bigdecimal.so and test manual loading
3. **Measure performance** - Benchmark extraction and load time
4. **Decide on open questions** - Resolve architectural choices
5. **Implement Phase 2** - Build production loader
6. **Integrate Phase 3** - Automate build system
7. **Complete Phase 4** - Enable all bundled extensions
8. **Document Phase 5** - User gem installation guide

## References

- Ruby Extension Loading: `rubygems/core_ext/kernel_require.rb`
- Cosmopolitan dlopen: `libc/dlopen/dlopen.c`
- ZIP filesystem: Cosmopolitan's built-in ZIP support
- Extension building: Ruby's `ext/extmk.rb` and `mkmf.rb`

---

**Status**: Awaiting review and approval to proceed with Phase 1 proof of concept.
