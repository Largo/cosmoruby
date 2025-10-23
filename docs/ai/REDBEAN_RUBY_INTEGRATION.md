# Redbean Ruby Integration Project

## Request
Add Ruby support to redbean (https://redbean.dev/) alongside the existing Lua support, so that redbean can execute `.rb` files in addition to `.lua` files.

## Current Progress

### Completed Tasks
1. ✅ Added Ruby header includes to `tool/net/redbean.c`
2. ✅ Created `RubyStart()` initialization function (similar to `LuaStart()`)
3. ✅ Created `IsRuby()` function to detect `.rb` file extensions
4. ✅ Created `ServeRuby()` function (similar to `ServeLua()`)
5. ✅ Modified `HandleAsset()` to route `.rb` files to `ServeRuby()`
6. ✅ Updated `TOOL_NET_DIRECTDEPS` in `tool/net/BUILD.mk` to include `THIRD_PARTY_RUBY`

### Pending Tasks
7. ⏳ Test Ruby integration with a simple `.rb` file
8. ⏳ Run full test suite

## Critical Realization: Cosmopolitan libc Integration

### The Issue
Cosmopolitan has its own libc (not glibc/musl in the traditional sense). This means:

1. **Lua Integration**: The built-in Lua in `third_party/lua/` has been specifically adapted to work with Cosmopolitan's libc
2. **Ruby Integration**: Ruby in `third_party/ruby/` likely needs similar adaptations

### Evidence to Investigate

#### 1. Check Ruby's Current State in Cosmopolitan
- Location: `third_party/ruby/` (symlink to `ruby-3.4.2/`)
- BUILD.mk exists at `third_party/ruby/BUILD.mk`
- Need to verify:
  - Has Ruby been fully ported to Cosmopolitan's libc?
  - Are there any Cosmopolitan-specific patches?
  - Does it actually build and work?

#### 2. Compare with Lua Integration
Need to examine:
- How Lua headers are structured (`third_party/lua/cosmo.h`)
- What Cosmopolitan-specific modifications exist in Lua
- How Lua links against Cosmopolitan's libc primitives

#### 3. Ruby-Specific Challenges

**Ruby is more complex than Lua:**
- **Larger runtime**: Ruby has a much bigger standard library
- **C extensions**: Ruby's extension system expects POSIX/glibc APIs
- **Thread model**: Ruby has its own threading (GVL) that may conflict
- **IO operations**: Ruby's IO expects standard POSIX file descriptors
- **Memory allocation**: Ruby has its own GC that needs to work with Cosmopolitan's allocator

**Ruby initialization sequence:**
```c
RUBY_INIT_STACK;
ruby_init();         // Initializes Ruby VM
ruby_sysinit();      // System-specific init
rb_call_inits();     // Initialize all built-in classes
```

This is more involved than Lua's simple `luaL_newstate()`.

## Deep Analysis: What's Actually Required

### Phase 1: Verify Ruby Build Status (CRITICAL)
Before anything else, we need to know:

```bash
# Can we build Ruby standalone?
make -j8 o//third_party/ruby/ruby

# Does the rubyapp example work?
make -j8 o//examples/rubyapp/rubyapp
o//examples/rubyapp/rubyapp
```

If these don't work, we have a much bigger problem - Ruby isn't properly ported yet.

### Phase 2: Understand Ruby's Cosmopolitan Adaptations

Look for:
1. **Configuration headers**: `third_party/ruby/include/ruby/config.h`
2. **Cosmopolitan patches**: Any `#ifdef RUBY_COSMOPOLITAN` or similar
3. **Build flags**: Check BUILD.mk for special compilation flags
4. **Missing functions**: Ruby may need shims for missing libc functions

### Phase 3: Redbean Integration Challenges

#### A. Ruby Initialization in Web Server Context
```c
// Current approach (may be wrong):
static void RubyStart(void) {
  RUBY_INIT_STACK;
  ruby_init();
}
```

**Problems:**
- `RUBY_INIT_STACK` expects to be called from `main()` with stack variables
- We're calling it from a function, not main
- Ruby's VM may need proper argc/argv
- May need `ruby_sysinit(&argc, &argv)` before `ruby_init()`

#### B. Per-Request Ruby Execution
```c
// Current approach (definitely incomplete):
static char *ServeRuby(struct Asset *a, const char *s, size_t n) {
  result = rb_eval_string_protect(code, &state);
  // ...
}
```

**Problems:**
- No mechanism to capture Ruby's stdout/stderr
- No way for Ruby code to set HTTP headers
- No way for Ruby code to return response body
- Need Ruby API bindings (like Lua has with `kLuaFuncs[]`)

#### C. Ruby API for HTTP (Like Lua's API)

Lua provides functions like:
- `SetStatus(code, reason)`
- `SetHeader(name, value)`
- `Write(data)`
- `GetParam(name)`
- `GetHeader(name)`
- etc.

Ruby needs similar bindings:
```ruby
# Example of what Ruby code should be able to do:
Redbean.set_status(200, "OK")
Redbean.set_header("Content-Type", "text/html")
Redbean.write("<h1>Hello from Ruby!</h1>")

params = Redbean.params
headers = Redbean.headers
```

This requires:
```c
// Define Ruby module and methods
static VALUE rb_redbean_set_status(VALUE self, VALUE code, VALUE reason) {
  // Implementation
}

// In RubyStart():
rb_mRedbean = rb_define_module("Redbean");
rb_define_module_function(rb_mRedbean, "set_status", rb_redbean_set_status, 2);
// ... many more functions
```

### Phase 4: Architecture Comparison

#### Lua Architecture (Working):
```
Request → HandleAsset() → IsLua() → ServeLua()
                                     ↓
                                     lua_State *L (global)
                                     ↓
                                     luaL_loadbuffer() + LuaCallWithYield()
                                     ↓
                                     Lua can call C functions (kLuaFuncs[])
                                     ↓
                                     GetLuaResponse() → HTTP response
```

#### Ruby Architecture (Needed):
```
Request → HandleAsset() → IsRuby() → ServeRuby()
                                      ↓
                                      Ruby VM (global? per-request?)
                                      ↓
                                      rb_eval_string_protect()
                                      ↓
                                      Ruby can call Redbean module methods
                                      ↓
                                      Capture output → HTTP response
```

**Key Differences:**
- Lua: Designed for embedding, lightweight, simple C API
- Ruby: Designed as standalone, heavier, complex C API
- Lua: Single-threaded, no GVL issues
- Ruby: Has GVL, threading complications
- Lua: Output captured via custom functions
- Ruby: Need to redirect stdout/stderr or use different approach

## What We Need to Do

### Immediate Next Steps

1. **Test Basic Ruby Build**
   ```bash
   make -j8 o//third_party/ruby/ruby
   o//third_party/ruby/ruby -e 'puts "Hello from Ruby"'
   ```

2. **Test Ruby Example App**
   ```bash
   make -j8 o//examples/rubyapp/rubyapp
   o//examples/rubyapp/rubyapp
   ```

3. **Examine Lua's Cosmopolitan Integration**
   ```bash
   # Look for Cosmopolitan-specific code
   grep -r "COSMO" third_party/lua/
   cat third_party/lua/cosmo.h
   cat third_party/lua/BUILD.mk
   ```

4. **Examine Ruby's Cosmopolitan Integration**
   ```bash
   grep -r "COSMO\|RUBY_COSMOPOLITAN" third_party/ruby/
   cat third_party/ruby/include/ruby/config.h
   cat third_party/ruby/BUILD.mk
   ```

### Medium-Term Tasks

5. **Fix Ruby Initialization** (if needed)
   - Proper stack initialization
   - Proper argc/argv handling
   - Check if Ruby needs special Cosmopolitan adaptations

6. **Implement Ruby HTTP API**
   - Create `Redbean` module in C
   - Bind functions for HTTP operations
   - Match Lua's API where possible

7. **Handle Ruby Output**
   - Redirect stdout/stderr to response buffer
   - Or use a different execution model

8. **Test with Simple Ruby Script**
   - Create `/test.rb` in redbean
   - Access via HTTP
   - Verify it works

### Long-Term Considerations

9. **Performance**
   - Ruby startup is slower than Lua
   - May need to cache Ruby VM state
   - Consider Ractor for concurrency?

10. **Error Handling**
    - Ruby exceptions → HTTP 500 errors
    - Stack traces in development mode
    - Clean error messages in production

11. **Security**
    - Ruby has more attack surface than Lua
    - Need to sandbox properly
    - Disable dangerous functions (File.open?, system?, etc.)

12. **Documentation**
    - Document Ruby API for users
    - Examples of Ruby scripts in redbean
    - Migration guide from Lua to Ruby

## Open Questions

1. **Is Ruby actually fully ported to Cosmopolitan?**
   - Status: UNKNOWN - needs testing

2. **Can we reuse the same Ruby VM across requests?**
   - Or do we need a new VM per request?
   - Performance implications

3. **How do we handle Ruby's thread model?**
   - Redbean is multi-process/multi-threaded
   - Ruby has GVL (Global VM Lock)
   - Compatibility concerns

4. **What about Ruby gems/stdlib?**
   - Does Ruby's stdlib work with Cosmopolitan?
   - Can users require gems?
   - Are they embedded in the APE?

5. **Should Ruby replace Lua or coexist?**
   - Current plan: coexist
   - Both .lua and .rb files supported
   - Shared API where possible

## Risk Assessment

### High Risk Items
- ❗ Ruby may not be fully ported to Cosmopolitan yet
- ❗ Ruby's complex initialization may not work in redbean's context
- ❗ Ruby's stdlib may have missing dependencies

### Medium Risk Items
- ⚠️ Performance overhead of Ruby vs Lua
- ⚠️ Complexity of implementing full HTTP API for Ruby
- ⚠️ Security implications of Ruby's power

### Low Risk Items
- ✓ File extension detection (.rb vs .lua)
- ✓ Build system integration
- ✓ Basic routing logic

## Success Criteria

### Minimum Viable Product
- [ ] Redbean can execute simple .rb files
- [ ] Ruby code can output plain text to HTTP response
- [ ] Basic error handling works

### Full Integration
- [ ] Ruby has full HTTP API (status, headers, body)
- [ ] Ruby can access request data (params, headers, etc.)
- [ ] Error messages are helpful
- [ ] Performance is acceptable
- [ ] Works on all Cosmopolitan platforms
- [ ] Documentation exists

### Stretch Goals
- [ ] Ruby REPL in redbean (like Lua has)
- [ ] Hot reload of Ruby code
- [ ] Ruby can interact with Lua code
- [ ] Gem support
- [ ] Ruby standard library fully functional

## CRITICAL DISCOVERY: Ruby Is Not Yet Ported!

### Build Test Results
```bash
$ make -j8 o//third_party/ruby/ruby
# FAILS with:
fatal error: ruby/internal/config.h: No such file or directory
```

### Root Cause
The file `third_party/ruby/include/ruby/config.h` **does not exist**. This is THE fundamental configuration header that Ruby requires. Examination shows:

1. `third_party/ruby/include/ruby/internal/config.h` exists (line 22)
2. It includes `"ruby/config.h"` (which doesn't exist!)
3. `ruby/config.h` is normally generated by Ruby's `./configure` script
4. It contains ~500+ platform-specific `#define` statements

### What This Means
**Ruby is INCOMPLETE in Cosmopolitan.** Someone started the integration work:
- ✅ Downloaded Ruby 3.4.2 source
- ✅ Created `third_party/ruby/BUILD.mk`
- ✅ Set up directory structure
- ❌ **Did NOT create the required config.h**
- ❌ **Did NOT test if it builds**
- ❌ **Did NOT complete the port**

### What config.h Normally Contains
This file defines hundreds of platform-specific features:
```c
// Examples of what should be in ruby/config.h:
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_MEMORY_H 1
#define HAVE_FORK 1
#define HAVE_VFORK 1
#define HAVE_GETPID 1
#define HAVE_MALLOC 1
#define HAVE_REALLOC 1
#define SIZEOF_INT 4
#define SIZEOF_LONG 8
#define SIZEOF_VOID_P 8
// ... and 400+ more
```

For Cosmopolitan, this needs to be hand-crafted to match Cosmopolitan's libc capabilities.

## The Real Scope of Work

### What We Thought We Needed
1. Link Ruby into redbean ✅ (Done)
2. Call Ruby APIs ✅ (Done)
3. Test and debug (Blocked!)

### What We Actually Need
**Phase 0: Port Ruby to Cosmopolitan (100+ hours of work)**
1. Create `ruby/config.h` for Cosmopolitan
   - Study Ruby's configure.ac
   - Determine what features Cosmopolitan's libc supports
   - Hand-craft config.h with correct defines
   - Test each subsystem incrementally

2. Fix compatibility issues
   - Ruby expects certain POSIX functions
   - Cosmopolitan may implement them differently or not at all
   - Need shims/wrappers for missing functions
   - May need to patch Ruby source code

3. Build and test Ruby standalone
   - Get `o//third_party/ruby/ruby` to build
   - Get it to actually run
   - Test basic Ruby features work
   - Verify stdlib works

4. **Only then** can we integrate it into redbean

### Comparison: Why Lua Works But Ruby Doesn't

**Lua (working):**
- Much simpler: ~30K lines of code
- Designed for embedding from day one
- Minimal external dependencies
- Simple build system
- Already ported to Cosmopolitan

**Ruby (not working):**
- Much larger: ~500K lines of code
- Designed as standalone language
- Complex dependencies on libc features
- Complex build system (autoconf)
- **NOT PORTED TO COSMOPOLITAN YET**

## Revised Project Assessment

### Option 1: Complete Ruby Port First (Recommended)
**Effort:** 100-200 hours
**Steps:**
1. Create proper ruby/config.h
2. Build and test standalone Ruby
3. Fix all compatibility issues
4. Verify stdlib works
5. **Then** integrate into redbean

**Pros:**
- Proper foundation
- Ruby would work for all Cosmopolitan users
- Reusable work

**Cons:**
- Huge time investment
- Deep knowledge of both Ruby and Cosmopolitan required
- May discover insurmountable blockers

### Option 2: Use External Ruby (Alternative)
**Effort:** 5-10 hours
**Approach:**
- Don't embed Ruby
- Have redbean shell out to system Ruby
- Similar to CGI

**Pros:**
- Works immediately
- No porting needed
- Uses whatever Ruby version is installed

**Cons:**
- Not actually portable (defeats Cosmopolitan's purpose)
- Slower (process spawning overhead)
- Less integrated

### Option 3: Wait for Someone Else
**Effort:** 0 hours
**Approach:**
- Document what's needed
- File issue / create RFC
- Wait for Cosmopolitan community to port Ruby

**Pros:**
- No work for us
- Might get better result from experts

**Cons:**
- Could take months or years
- Might never happen

### Option 4: Use a Different Language
**Effort:** Varies
**Consider:**
- Python (check if already ported to Cosmopolitan)
- JavaScript (V8/QuickJS)
- Another embedded language already in Cosmopolitan

## Next Action
**STOP CODING AND DECIDE:**

1. Are you willing to invest 100+ hours porting Ruby to Cosmopolitan?
2. Should we explore alternative approaches?
3. Should we check if Python or another language is already working?

**Do NOT proceed with redbean integration until Ruby actually builds standalone!**
