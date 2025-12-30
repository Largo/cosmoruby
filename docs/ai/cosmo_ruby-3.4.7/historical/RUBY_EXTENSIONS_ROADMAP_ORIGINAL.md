# Ruby Extensions Roadmap for Cosmopolitan

**⚠️ ARCHIVED - 2025-12-07**

**This document is outdated.** SSL/TLS support via MbedTLS was already implemented and working when this document was written, but was incorrectly documented as "blocked" or "not recommended."

**Current documentation:** See `docs/ai/RUBY_EXTENSIONS_ROADMAP.md` and `docs/ai/RUBY_SSL_TLS.md` for accurate, up-to-date information.

**Why archived:** This document recommended avoiding OpenSSL and using workarounds for HTTPS. In reality, a complete MbedTLS extension and OpenSSL compatibility shim were already implemented and HTTPS gem downloads were working. This document has been preserved for historical reference showing the planning process.

---

# Original Document (2025-10-30)

## Current State (as of 2025-10-30)

### ✅ Working Extensions
- **zlib** - Fully functional, enables gem decompression
  - Added `get_crc_table()` declaration to third_party/zlib/zlib.h
  - Integrated into Ruby build via ext/extinit.c
  - Testing: `ruby.com -e "require 'zlib'; puts Zlib::VERSION"` → 3.2.1

- **socket** - TCP/UDP networking
- **stringio** - In-memory string I/O
- **pathname** - Filesystem path manipulation
- **monitor** - Thread synchronization

### ❌ Blocked Extensions

#### 1. psych (YAML parser)
**Status:** Blocked - requires libyaml

**Why it's needed:**
RubyGems stores checksums in `checksums.yaml.gz` files inside .gem archives. The `Gem::Package#read_checksums` method calls `Gem.load_yaml` which requires psych.

**Error when missing:**
```
cannot load such file -- psych (LoadError)
  from /zip/lib/ruby/3.4.0/rubygems/package.rb:555:in 'Gem::Package#read_checksums'
```

**Current workaround:**
None - gem install fails completely without psych.

#### 2. openssl (SSL/TLS for HTTPS)
**Status:** Blocked - requires OpenSSL API compatibility

**Why it's needed:**
HTTPS gem downloads from rubygems.org require SSL/TLS support.

**Error when missing:**
```
ERROR: While executing gem ... (Gem::Exception)
    OpenSSL is not available. Install OpenSSL and rebuild Ruby or use non-HTTPS sources
```

**Current workaround:**
- Use HTTP sources (insecure): `gem install --source http://...`
- Use local gem files: `gem install /path/to/file.gem --local`

---

## Path Forward: Adding libyaml

### What is libyaml?

libyaml is the canonical C library for parsing and emitting YAML. Ruby's psych extension is a thin wrapper around libyaml. Current stable version: 0.2.5

**Repository:** https://github.com/yaml/libyaml
**Size:** ~20 C files, ~13,000 lines of code
**License:** MIT
**Dependencies:** None (standalone C library)

### Implementation Steps

#### Step 1: Obtain and integrate libyaml source

```bash
# Download libyaml 0.2.5
cd /tmp
curl -L https://github.com/yaml/libyaml/archive/refs/tags/0.2.5.tar.gz -o libyaml-0.2.5.tar.gz
tar xzf libyaml-0.2.5.tar.gz

# Copy to Cosmopolitan
cd ~/Code/jart/cosmopolitan
mkdir -p third_party/libyaml
cp -r /tmp/libyaml-0.2.5/src/* third_party/libyaml/
cp -r /tmp/libyaml-0.2.5/include/* third_party/libyaml/include/
```

**Create README.cosmo:**
```
third_party/libyaml/README.cosmo
Source: https://github.com/yaml/libyaml/archive/refs/tags/0.2.5.tar.gz
Version: 0.2.5
License: MIT
Purpose: YAML parser for Ruby's psych extension
```

#### Step 2: Create BUILD.mk for libyaml

Create `third_party/libyaml/BUILD.mk`:

```makefile
#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_LIBYAML

THIRD_PARTY_LIBYAML_A = o/$(MODE)/third_party/libyaml/libyaml.a
THIRD_PARTY_LIBYAML = $(THIRD_PARTY_LIBYAML_A_DEPS) $(THIRD_PARTY_LIBYAML_A)
THIRD_PARTY_LIBYAML_A_FILES := $(wildcard third_party/libyaml/*)
THIRD_PARTY_LIBYAML_A_HDRS = $(filter %.h,$(THIRD_PARTY_LIBYAML_A_FILES))
THIRD_PARTY_LIBYAML_A_SRCS = $(filter %.c,$(THIRD_PARTY_LIBYAML_A_FILES))

THIRD_PARTY_LIBYAML_A_OBJS =					\\
	$(THIRD_PARTY_LIBYAML_A_SRCS:%.c=o/$(MODE)/%.o)

THIRD_PARTY_LIBYAML_A_DIRECTDEPS =				\\
	LIBC_CALLS							\\
	LIBC_FMT							\\
	LIBC_INTRIN							\\
	LIBC_MEM							\\
	LIBC_NEXGEN32E						\\
	LIBC_RUNTIME						\\
	LIBC_STDIO							\\
	LIBC_STR							\\
	LIBC_SYSV

THIRD_PARTY_LIBYAML_A_DEPS :=					\\
	$(call uniq,$(foreach x,$(THIRD_PARTY_LIBYAML_A_DIRECTDEPS),$($(x))))

$(THIRD_PARTY_LIBYAML_A):					\\
		third_party/libyaml/					\\
		$(THIRD_PARTY_LIBYAML_A).pkg			\\
		$(THIRD_PARTY_LIBYAML_A_OBJS)

$(THIRD_PARTY_LIBYAML_A).pkg:					\\
		$(THIRD_PARTY_LIBYAML_A_OBJS)			\\
		$(foreach x,$(THIRD_PARTY_LIBYAML_A_DIRECTDEPS),$($(x)_A).pkg)

# Compiler flags for libyaml
o/$(MODE)/third_party/libyaml/%.o: private			\\
	CFLAGS +=							\\
		-Ithird_party/libyaml/include			\\
		-DHAVE_CONFIG_H

THIRD_PARTY_LIBYAML_LIBS = $(foreach x,$(THIRD_PARTY_LIBYAML_ARTIFACTS),$($(x)))
THIRD_PARTY_LIBYAML_SRCS = $(foreach x,$(THIRD_PARTY_LIBYAML_ARTIFACTS),$($(x)_SRCS))
THIRD_PARTY_LIBYAML_HDRS = $(foreach x,$(THIRD_PARTY_LIBYAML_ARTIFACTS),$($(x)_HDRS))
THIRD_PARTY_LIBYAML_CHECKS = $(foreach x,$(THIRD_PARTY_LIBYAML_ARTIFACTS),$($(x)_CHECKS))
THIRD_PARTY_LIBYAML_OBJS = $(foreach x,$(THIRD_PARTY_LIBYAML_ARTIFACTS),$($(x)_OBJS))
$(THIRD_PARTY_LIBYAML_OBJS): third_party/libyaml/BUILD.mk

.PHONY: o/$(MODE)/third_party/libyaml
o/$(MODE)/third_party/libyaml: $(THIRD_PARTY_LIBYAML_CHECKS)
```

**Register in main Makefile** - Add to package includes section.

#### Step 3: Add psych extension to Ruby build

Edit `third_party/ruby-wip-3.4.7/BUILD.mk`:

```makefile
# Add psych source files to Ruby build
THIRD_PARTY_RUBY_A_SRCS_C =					\\
    # ... existing files ...
    third_party/ruby/ext/zlib/zlib.c				\\
    third_party/ruby/ext/psych/psych.c			\\
    third_party/ruby/ext/psych/psych_emitter.c		\\
    third_party/ruby/ext/psych/psych_parser.c		\\
    third_party/ruby/ext/psych/psych_to_ruby.c		\\
    third_party/ruby/ext/psych/psych_yaml_tree.c

# Add libyaml to Ruby dependencies
THIRD_PARTY_RUBY_A_DIRECTDEPS =				\\
    # ... existing deps ...
    THIRD_PARTY_LIBYAML					\\
    THIRD_PARTY_ZLIB

# Compiler flags for psych extension
o/$(MODE)/third_party/ruby/ext/psych/%.o: private		\\
    CFLAGS +=							\\
            -Ithird_party/libyaml/include			\\
            -DHAVE_LIBYAML
```

#### Step 4: Register psych in ext/extinit.c

Edit `third_party/ruby-wip-3.4.7/ext/extinit.c`:

```c
void Init_ext(void)
{
    init(Init_monitor, "monitor");
    init(Init_pathname, "pathname");
    init(Init_psych, "psych");      // Add this line
    init(Init_socket, "socket");
    init(Init_stringio, "stringio");
    init(Init_zlib, "zlib");
}
```

#### Step 5: Build and test

```bash
# Build Ruby with psych
make -j24 o//third_party/ruby/ruby

# Package
cd o/scripts && bash package_ruby.sh

# Test
ruby.com -e "require 'psych'; puts Psych::VERSION"
ruby.com -e "require 'yaml'; puts YAML.dump({foo: 'bar'})"

# Test gem install
gem.com install rack --no-document
```

### Estimated Complexity

**Difficulty:** Medium
**Time estimate:** 1-2 hours (assuming no major issues)
**Risk level:** Low-Medium

**Potential issues:**
1. libyaml may have POSIX-specific code that needs patching
2. Header paths may need adjustment
3. Config.h may need to be generated/stubbed
4. Namespace collisions unlikely (yaml_ prefix is unique)

**Success indicators:**
- ✅ libyaml compiles without errors
- ✅ psych extension loads: `ruby.com -e "require 'psych'"`
- ✅ YAML parsing works: `YAML.load("foo: bar")`
- ✅ gem install succeeds with local gems

---

## Path Forward: Adding OpenSSL (NOT RECOMMENDED)

### The Challenge

Ruby's openssl extension expects the **OpenSSL C API** (headers like `openssl/ssl.h`, `openssl/x509.h`, functions like `SSL_new()`, `X509_verify()`, etc.).

Cosmopolitan uses **mbedtls**, which has a **completely different API** with different:
- Header structure
- Function names
- Type definitions
- Error handling
- State management
- Feature sets

### Option 1: Port OpenSSL itself

**What's involved:**
1. Download OpenSSL 3.x source (~500,000 lines of C code)
2. Extract to `third_party/openssl/`
3. Port OpenSSL's configure/build system to Cosmopolitan's BUILD.mk
4. Resolve conflicts with existing mbedtls
5. Handle platform-specific assembly optimizations
6. Deal with OpenSSL's complex build-time code generation

**Estimated complexity:** Very High
**Time estimate:** Days to weeks
**Risk level:** High

**Why this is hard:**
- OpenSSL has a complex perl-based build system (Configure script)
- Heavy platform detection and conditional compilation
- Assembly language optimizations for multiple platforms
- Would duplicate TLS functionality (both OpenSSL and mbedtls in binary)
- Binary size impact: +2-3 MB
- Two different SSL/TLS implementations to maintain

### Option 2: Create OpenSSL compatibility shim over mbedtls

**What's involved:**

1. **Create stub headers** (openssl/*.h):
   ```c
   // third_party/openssl-compat/openssl/ssl.h
   #include <mbedtls/ssl.h>

   typedef mbedtls_ssl_context SSL;
   typedef mbedtls_ssl_config SSL_CTX;
   // ... hundreds more type mappings
   ```

2. **Implement wrapper functions**:
   ```c
   // Map OpenSSL API to mbedtls
   SSL* SSL_new(SSL_CTX* ctx) {
       // Translate OpenSSL call to mbedtls equivalent
       // Different initialization sequences
       // Different error handling
       // Return type mapping
   }

   int SSL_connect(SSL* ssl) {
       // Map connection logic
       // Different state machines
       // Different return codes
   }

   // ... hundreds more functions
   ```

3. **Handle API incompatibilities**:
   - OpenSSL uses callbacks, mbedtls uses different pattern
   - Certificate handling completely different
   - Error codes don't map 1:1
   - Memory management differs
   - Threading models differ

**Estimated complexity:** Very High
**Time estimate:** Weeks of work
**Risk level:** Very High

**Why this is hard:**
- OpenSSL has 300+ public API functions
- Many functions have complex behavior that doesn't map cleanly
- Ruby's openssl extension uses advanced OpenSSL features
- Subtle bugs will occur from API mismatches
- Ongoing maintenance burden as Ruby evolves
- Debugging TLS issues through translation layer is extremely difficult

### Option 3: Write Ruby mbedtls extension

**What's involved:**

Instead of wrapping OpenSSL's API, write a new Ruby extension that directly wraps Cosmopolitan's existing mbedtls library. This would provide SSL/TLS functionality through a Ruby-native interface.

**Approach:**

1. **Create new extension** `ext/mbedtls_ssl/`:
   ```c
   // Minimal Ruby interface to mbedtls
   // Focus on what RubyGems actually needs

   module MbedTLS
     class SSLContext
       # Initialize mbedtls_ssl_context
     end

     class SSLSocket < IO
       # Wrap socket with SSL
       # Forward read/write to mbedtls_ssl_read/write
     end
   end
   ```

2. **Monkey-patch Net::HTTP** to use MbedTLS instead of OpenSSL:
   ```ruby
   # lib/rubygems/mbedtls_compat.rb
   module Net
     class HTTP
       def connect
         # Use MbedTLS::SSLSocket instead of OpenSSL::SSL::SSLSocket
       end
     end
   end
   ```

3. **Scope to RubyGems needs only**:
   - SSL/TLS socket wrapper
   - Basic certificate verification
   - HTTPS connections
   - SHA256 digests (already in mbedtls)
   - HMAC (for S3 signing)

**What's NOT needed:**
- Full X.509 certificate generation (only validation)
- All the crypto primitives (DSA, EC key generation, etc.)
- Compatibility with openssl gem API
- Support for all Ruby programs (just RubyGems)

**Estimated complexity:** High
**Time estimate:** 1-2 weeks
**Risk level:** Medium-High

**Advantages:**
- Uses Cosmopolitan's existing mbedtls (no new dependencies)
- No binary size increase (already have mbedtls)
- Scoped to specific use case (RubyGems HTTPS)
- Clean architecture (native to platform)
- Could be reusable for other Ruby apps

**Challenges:**
- Still significant C extension work
- Need to understand mbedtls API deeply
- Monkey-patching Net::HTTP is fragile (breaks on Ruby updates)
- May not cover all edge cases RubyGems uses
- Debugging SSL/TLS issues is complex
- Would need ongoing maintenance

**Prerequisites:**
- Study what RubyGems actually needs from OpenSSL
- Audit all `OpenSSL::` usage in lib/rubygems/**/*.rb
- Map those needs to mbedtls equivalents
- Design minimal Ruby API that satisfies those needs

**Success criteria:**
- ✅ `gem install` works over HTTPS
- ✅ Certificate verification works
- ✅ Can download from rubygems.org
- ✅ HMAC signing works (for S3 sources)
- ✅ No crashes or SSL errors

**Verdict:** Viable medium-term solution if HTTPS becomes critical. More work than libyaml, but tractable. Could potentially be upstreamed to help other Cosmopolitan Ruby users.

### Option 4: Skip OpenSSL (RECOMMENDED)

**Workarounds available:**

1. **Use HTTP sources** (insecure but functional):
   ```bash
   gem install rack --source http://rubygems.org
   ```

2. **Use local gem files**:
   ```bash
   # Download on another machine with SSL support
   gem fetch rack

   # Transfer .gem file to Cosmopolitan environment
   gem install rack-3.0.8.gem --local
   ```

3. **Use bundler with vendored gems**:
   ```bash
   # On development machine with SSL
   bundle install --path vendor/bundle

   # Transfer entire vendor/ directory
   # Ruby app works without network access
   ```

4. **Document clearly** in README:
   ```
   ## Known Limitations

   - HTTPS gem downloads not supported (use HTTP sources or local gems)
   - Workaround: gem install --source http://rubygems.org
   - For production: vendor gems with bundler
   ```

**Why this is the right approach:**
- Focuses effort on Ruby functionality, not TLS plumbing
- Cosmopolitan already has mbedtls for network tools
- Workarounds are well-established in Ruby ecosystem
- Can revisit if OpenSSL shim becomes critical
- Avoids massive engineering effort for marginal benefit

---

## Recommendation: Prioritized Roadmap

### Phase 1: Essential (Do Now)
1. ✅ **zlib extension** - DONE
2. 🔄 **libyaml + psych** - IN PROGRESS (this document)
   - Enables gem install to work properly
   - Clean, tractable solution
   - Low risk, medium complexity
   - Estimated: 1-2 hours

### Phase 2: Validation (Next)
3. **Run Ruby test suite** (`make test-all`)
   - Validate core Ruby functionality
   - Identify remaining issues
   - Measure compatibility

4. **Test real-world apps**
   - Sinatra web framework
   - Rack applications
   - Rails routing (subset)
   - Pure Ruby gems

### Phase 3: Nice-to-Have (Future)
5. **OpenSSL/HTTPS support** - MULTIPLE OPTIONS
   - **Option A (Recommended for now):** Skip it, use workarounds (HTTP sources, local gems)
   - **Option B (If HTTPS becomes critical):** Write Ruby mbedtls extension (1-2 weeks)
   - **Option C (Not recommended):** Port OpenSSL or create compatibility shim (weeks/months)
   - Document current limitations and workarounds clearly

6. **Native extension support** (.so loading)
   - Dynamic loading of compiled gems
   - Requires DLL infrastructure
   - Low priority (most useful gems are pure Ruby)

### Phase 4: Polish (Later)
7. **Fix mkdeps for Ruby**
   - Non-blocker, development tool issue
   - Long finger task

---

## Testing Strategy

### After adding libyaml/psych:

```bash
# Unit tests
ruby.com -e "require 'psych'; puts Psych::VERSION"
ruby.com -e "require 'yaml'; data = YAML.load('foo: bar'); puts data['foo']"

# Integration tests
gem.com install rack --no-document
ruby.com -e "require 'rack'; puts Rack::VERSION"

# Real-world test
cat > test_rack.rb <<'EOF'
require 'rack'

app = lambda do |env|
  [200, {"Content-Type" => "text/plain"}, ["Hello from Rack!"]]
end

Rack::Handler::WEBrick.run app, Port: 9292
EOF

ruby.com test_rack.rb &
curl http://localhost:9292
```

---

## Reference: Key Files

- `third_party/zlib/zlib.h` - Added get_crc_table() declaration
- `third_party/ruby-wip-3.4.7/BUILD.mk` - Ruby build configuration
- `third_party/ruby-wip-3.4.7/ext/extinit.c` - Extension registration
- `third_party/ruby-wip-3.4.7/inits.c` - Core initialization (NOT for extensions)
- `third_party/ruby-wip-3.4.7/lib/rubygems/package.rb` - Where YAML is required

## Reference: Extension Architecture

**How Ruby loads statically-linked extensions:**

1. `rb_call_inits()` in `inits.c` - Initializes core Ruby classes (Array, Hash, etc.)
2. `Init_ext()` in `ext/extinit.c` - Initializes statically-linked extensions
   - Calls `ruby_init_ext("zlib.so", Init_zlib)` etc.
   - Registers extensions in `$LOADED_FEATURES` as if dynamically loaded
3. When `require 'zlib'` is called:
   - Ruby checks `$LOADED_FEATURES`
   - Finds "zlib.so" already loaded
   - Returns immediately (extension already initialized)

**Why we had double-initialization:**
- Extensions were called in both `rb_call_inits()` AND `Init_ext()`
- Caused "already initialized constant" warnings
- Fixed by removing extension calls from `rb_call_inits()`

---

## Conclusion

**Immediate action:** Add libyaml to enable psych/YAML support. This unblocks gem install and is a tractable 1-2 hour task.

**HTTPS/SSL options (in priority order):**
1. **Defer for now** - Use workarounds (HTTP sources, local gems). Document limitations clearly.
2. **If HTTPS becomes critical** - Write Ruby mbedtls extension (~1-2 weeks, viable medium-term solution)
3. **Avoid** - Porting OpenSSL or creating compatibility shim (weeks/months, high risk)

**Focus:** Get Ruby working well for local development and pure Ruby applications. This is the 80/20 win. The mbedtls extension option provides a clear path forward if HTTPS support becomes essential later.
