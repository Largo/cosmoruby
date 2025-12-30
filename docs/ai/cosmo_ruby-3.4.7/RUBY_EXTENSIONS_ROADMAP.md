# Ruby Extensions Status for Cosmopolitan

**Last Updated:** 2025-12-07
**Status:** SSL/TLS WORKING ✅ | HTTPS gem downloads WORKING ✅

## Executive Summary

CosmoRuby now has **full SSL/TLS support** via a native MbedTLS extension with OpenSSL compatibility layer. HTTPS gem downloads from rubygems.org are working. Most critical extensions are statically linked and operational.

## ✅ Working Extensions

### Core Extensions (Statically Linked)

1. **mbedtls** - SSL/TLS support ✅ **NEW!**
   - Native C extension wrapping Cosmopolitan's mbedtls library
   - Location: `third_party/ruby-wip-3.4.7/ext/mbedtls/`
   - Certificate verification via `GetSslRoots()` from `net/https/https.h`
   - SNI (Server Name Indication) support
   - Testing: `ruby.com third_party/ruby/ext/mbedtls/test_mbedtls.rb`

2. **openssl** - OpenSSL compatibility shim ✅ **NEW!**
   - Pure Ruby compatibility layer over MbedTLS
   - Location: `third_party/ruby-wip-3.4.7/lib/openssl.rb`
   - Implements: `OpenSSL::SSL::SSLSocket`, `OpenSSL::SSL::SSLContext`
   - Implements: `OpenSSL::Digest` (delegates to Ruby's native Digest)
   - Stub implementations: `OpenSSL::X509::Store`, `OpenSSL::PKey::RSA`
   - **Enables Net::HTTP SSL and RubyGems HTTPS downloads**
   - Testing: `ruby.com third_party/ruby/ext/mbedtls/test_openssl_compat.rb`

3. **zlib** - Compression/decompression
   - Enables gem decompression
   - Added `get_crc_table()` declaration to `third_party/zlib/zlib.h`
   - Testing: `ruby.com -e "require 'zlib'; puts Zlib::VERSION"` → 3.2.1

4. **socket** - TCP/UDP networking
   - 15 C source files
   - Full socket operations including shutdown, setsockopt, etc.
   - Required for gem networking

5. **stringio** - In-memory string I/O
6. **pathname** - Filesystem path manipulation
7. **monitor** - Thread synchronization
8. **ripper** - Ruby parser introspection
9. **io/console** - Terminal control (raw mode, cursor positioning)
10. **io/wait** - Non-blocking I/O support
11. **io/nonblock** - Non-blocking I/O mode

### Encoding Transcoders

All statically compiled for backtrace support:
- `trans_single_byte` - US-ASCII ↔ UTF-8 (essential for error messages)
- Additional transcoders: big5, chinese, ebcdic, emoji, escape, gb18030, gbk, iso2022, japanese, korean, utf_16_32, utf8_mac

## 🎯 Verified Working Use Cases

### ✅ HTTPS Gem Downloads
```bash
$ gem.com update rack
Updating rack
Fetching rack-3.2.4.gem  # ← Downloaded over HTTPS!
Successfully installed rack-3.2.4
Gems updated: rack
```

### ✅ Remote Gem Queries
```bash
$ gem.com outdated
base64 (0.2.0 < 0.3.0)
bundler (2.6.9 < 4.0.0)
# ... 18 gems checked via HTTPS API
```

### ✅ User Gem Installation
```bash
$ gem.com env
USER INSTALLATION DIRECTORY: /home/groobiest/.gem/ruby.com/3.4.0
REMOTE SOURCES:
  - https://rubygems.org/  # ← HTTPS by default!
```

## ⏳ Extensions Not Yet Integrated

### Bundled Gems with Native Extensions

These gems ship with Ruby but are not yet compiled/loadable:
- **bigdecimal** - Arbitrary precision decimal arithmetic
- **debug** - Ruby debugger
- **nkf** - Network Kanji Filter (Japanese encoding)
- **racc** - Parser generator
- **rbs** - Ruby type signatures
- **syslog** - System logger

**Status:** Need to be either:
1. Statically linked (add to BUILD.mk, inits.c)
2. Compiled as .so and loaded dynamically from ZIP (see RUBY_ZIP_EXTENSION_LOADER.md)

### Optional Extensions

#### psych (YAML parser)
**Status:** Not yet integrated - requires libyaml

**Current situation:**
- RubyGems appears to work WITHOUT psych (gem install/update working)
- May be optional or have fallback behavior
- **TODO:** Test if any gems actually require YAML parsing

**If needed, implementation steps:**
1. Add libyaml to `third_party/` (MIT license, ~20 files, 13k LOC)
2. Create `third_party/libyaml/BUILD.mk`
3. Add psych extension sources to Ruby BUILD.mk
4. Register in `ext/extinit.c`

See archived planning docs in `docs/ai/historical/RUBY_EXTENSIONS_ROADMAP_ORIGINAL.md` for detailed libyaml integration plan.

## 📊 Extension Architecture

### Static Linking Pattern (Current Approach)

For each extension:

1. **Add sources to BUILD.mk:**
   ```makefile
   THIRD_PARTY_RUBY_A_SRCS_C = \
       third_party/ruby/ext/EXTENSION/file.c
   ```

2. **Register in ext/extinit.c:**
   ```c
   init(Init_extension_name, "extension_name");
   ```

3. **Mark as loaded in extension Init function:**
   ```c
   void Init_extension_name(void) {
       // ... initialization ...
       rb_provide("extension_name.so");  // Critical!
   }
   ```

4. **Add special CFLAGS if needed:**
   ```makefile
   o/$(MODE)/third_party/ruby/ext/NAME/file.o: private \
       CFLAGS += -DSPECIAL_FLAG
   ```

### Dynamic Loading from ZIP (Future Option)

See `RUBY_ZIP_EXTENSION_LOADER.md` for detailed design of on-demand .so loading from embedded ZIP filesystem. This would enable:
- Installing gems with native extensions via `gem install`
- Smaller core Ruby binary (extensions loaded on-demand)
- Easier development (rebuild single extension)

## 🔍 Testing Extensions

### Test MbedTLS Extension
```bash
ruby.com third_party/ruby-wip-3.4.7/ext/mbedtls/test_mbedtls.rb
```

### Test OpenSSL Compatibility
```bash
ruby.com third_party/ruby-wip-3.4.7/ext/mbedtls/test_openssl_compat.rb
```

### Test Gem Installation
```bash
# Over HTTPS
gem.com install rack

# Check what's available
gem.com list

# Query remote repository
gem.com outdated
```

## 📚 Related Documentation

- `RUBY_SSL_TLS.md` - Detailed SSL/TLS implementation documentation
- `RUBY_PORT_PROGRESS.md` - Overall Ruby porting progress
- `RUBY_ZIP_EXTENSION_LOADER.md` - Dynamic extension loading design
- `docs/ai/historical/RUBY_EXTENSIONS_ROADMAP_ORIGINAL.md` - Original planning document (archived)

## 🎉 Success Metrics

- ✅ **SSL/TLS working** - MbedTLS extension + OpenSSL compatibility layer
- ✅ **HTTPS gem downloads** - `gem.com install/update` over HTTPS
- ✅ **Certificate verification** - Trusted root CAs from Cosmopolitan
- ✅ **Net::HTTP SSL** - Standard Ruby HTTPS client working
- ✅ **RubyGems API access** - Can query rubygems.org for versions
- ✅ **User gem installation** - Gems install to `~/.gem/ruby.com/3.4.0/`
- ✅ **Pure Ruby gems work** - 23+ bundled gems + installed gems functional

## 🔜 Next Steps

1. **Test psych requirement** - Determine if any gems actually need YAML
2. **Test native extension compilation** - Try `gem install nokogiri` (has C extensions)
3. **Consider bundled gem extensions** - Decide: static linking vs ZIP dynamic loading
4. **Benchmark extension loading** - Measure static vs dynamic performance
5. **Document gem installation workflow** - Guide for users installing gems

## Historical Notes

**Previous Status (2025-10-30):** OpenSSL was documented as "NOT RECOMMENDED" and HTTPS was blocked. This was incorrect - the mbedtls extension and OpenSSL compatibility layer were already implemented and working, just not documented.

**Discovery (2025-12-07):** User testing revealed `gem.com update rack` successfully downloads over HTTPS, proving SSL/TLS support is fully functional.
