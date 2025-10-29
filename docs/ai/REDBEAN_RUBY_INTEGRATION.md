# Redbean Ruby Integration - Complete Implementation Guide

**Status:** ✅ **IMPLEMENTED AND WORKING** (as of 2025-10-29)

## Overview

Redbean now supports serving Ruby scripts (`.rb` files) using the **Rack interface standard**. This means you can write Rack-compliant Ruby applications that run directly in Redbean, similar to how Puma, Unicorn, or WEBrick work, but as a single Actually Portable Executable.

## Quick Start

### 1. Create a Rack Application

```ruby
# /tmp/my-app/index.rb
lambda do |env|
  status = 200
  headers = {"Content-Type" => "text/html"}
  body = ["<h1>Hello from Ruby on Redbean!</h1>",
          "<p>Method: #{env['REQUEST_METHOD']}</p>",
          "<p>Path: #{env['PATH_INFO']}</p>"]
  [status, headers, body]
end
```

### 2. Build Redbean with Ruby Support

```bash
# Build redbean binary
make -j8 o//tool/net/redbean

# Copy and prepare for distribution
cp o/tool/net/redbean /tmp/my-redbean.com

# Embed your Ruby app
cd /tmp/my-app && zip -r ../app.zip .
cd /tmp && cat app.zip >> my-redbean.com

# CRITICAL: Fix ZIP offsets
zip -A /tmp/my-redbean.com
```

### 3. Run

```bash
/tmp/my-redbean.com -p 8080
# Visit http://localhost:8080/index.rb
```

## Architecture

### Ruby Port Status

Ruby 3.4.7 has been **fully ported** to Cosmopolitan Libc:
- ✅ All 2005 bootstrap tests passing (100% success rate)
- ✅ Full Ruby language support (classes, modules, blocks, fibers, threads, ractors)
- ✅ IRB (Interactive Ruby) with syntax highlighting
- ✅ RubyGems package manager working
- ✅ Bundler dependency manager working
- ✅ 24 pure Ruby gems functional
- ✅ Socket extension (networking) working
- ⚠️ Native extensions not yet supported (requires dynamic .so loader)

See `RUBY_PORT_PROGRESS.md` for complete porting details.

### Rack Interface Implementation

Instead of creating a custom Ruby API (like Lua has), we implemented the **standard Rack interface**. This means:

1. **Rack apps work as-is** - No Redbean-specific code needed
2. **Middleware ecosystem** - Standard Rack middleware can be used
3. **Familiar to Rubyists** - Follows established conventions
4. **Future-compatible** - Sinatra, Rails metal, etc. could work

## Complete Request Flow

### Overview Diagram

```
HTTP Request
    ↓
[Redbean Request Handler]
    ↓
[Route by Extension]
    ↓
Is .rb file?
    ↓ Yes
[ServeRuby() Function]
    ↓
[Load .rb from ZIP] → Ruby source code
    ↓
[Build Rack env Hash] → {"REQUEST_METHOD" => "GET", ...}
    ↓
[Execute Ruby Code] → rack_app = lambda { ... }
    ↓
[Call rack_app.call(env)] → [status, headers, body]
    ↓
[Parse Rack Response]
    ↓
[Build HTTP Response] → "HTTP/1.1 200 OK\r\n..."
    ↓
[Send to Client]
```

### Detailed Step-by-Step Flow

#### Step 1: Server Initialization (Startup)

**Location:** `tool/net/redbean.c` line 7542: `RedBean()` function

```c
void RedBean(int argc, char *argv[]) {
  // ... initial setup ...

  // Line 7596: Initialize Lua (existing)
  LuaStart();

  // Lines 7597-7600: Initialize Ruby
  #ifndef STATIC
    RUBY_INIT_STACK;  // CRITICAL: Must be in function with argc/argv
  #endif
  RubyStart();

  // Line 7601: Parse command-line arguments
  GetOpts(argc, argv);

  // ... continue server startup ...
}
```

**Why RUBY_INIT_STACK placement matters:**
- Ruby's GC needs to know where the stack starts to scan for references
- Must be in the same function that has `argc` and `argv` parameters
- Cannot be in a sub-function like `RubyStart()`

**RubyStart() Implementation (lines 5648-5653):**

```c
static void RubyStart(void) {
#ifndef STATIC
  ruby_init();  // Initialize Ruby VM
  DEBUGF("(ruby) Ruby interpreter initialized with Rack support");
#endif
}
```

#### Step 2: HTTP Request Arrives

When a client makes a request to `http://localhost:8080/index.rb`:

1. **TCP connection accepted** on port 8080
2. **HTTP parsed** into `cpm.msg` structure:
   - `cpm.msg.method` - HTTP method (GET, POST, etc.) as 64-bit constant
   - `url.path.p` - Path pointer: `/index.rb`
   - `url.path.n` - Path length: 9
   - `url.params` - Query string parameters array
   - `cpm.msg.headers[]` - HTTP headers array with byte offsets into `inbuf`

3. **Route determination** - Redbean checks file extension:
   ```c
   if (ends_with(path, ".lua")) {
     return ServeLua(...);
   } else if (ends_with(path, ".rb")) {
     return ServeRuby(...);  // ← Ruby routing
   } else {
     return ServeAsset(...);  // Static files
   }
   ```

#### Step 3: ServeRuby() Function Execution

**Location:** `tool/net/redbean.c` lines 3341-3489

##### Step 3a: Load Ruby Script from Embedded ZIP

```c
static char *ServeRuby(struct Asset *a, const char *s, size_t n) {
  char *code;
  size_t codelen;

  // Line 3354-3357: Load the .rb file from ZIP
  if (!(code = FreeLater(LoadAsset(a, &codelen)))) {
    return ServeError(500, "Internal Server Error");
  }

  // code now contains: "lambda do |env|\n  status = 200\n  ..."
  // codelen = file size in bytes
```

**How ZIP loading works:**
- `struct Asset *a` points to entry in Redbean's ZIP index
- `LoadAsset()` decompresses (if needed) and returns file contents
- `FreeLater()` marks memory for cleanup at request end
- ZIP is embedded at end of APE binary, offsets fixed by `zip -A`

##### Step 3b: Build Rack Environment Hash

**Rack Specification:** https://github.com/rack/rack/blob/main/SPEC.rdoc

```c
  // Line 3362: Create empty Ruby hash
  env = rb_hash_new();

  // Lines 3365-3368: Convert HTTP method to string
  char method[9] = {0};
  WRITE64LE(method, cpm.msg.method);
  // Example: 0x0000000054455047 (GET in little-endian) → "GET\0\0\0\0\0"
```

**CGI Environment Variables:**

```c
  // Line 3371-3372: REQUEST_METHOD
  rb_hash_aset(env, rb_str_new2("REQUEST_METHOD"), rb_str_new2(method));
  // env["REQUEST_METHOD"] = "GET"

  // Line 3373: PATH_INFO
  rb_hash_aset(env, rb_str_new2("PATH_INFO"), rb_str_new(url.path.p, url.path.n));
  // env["PATH_INFO"] = "/index.rb"

  // Lines 3375-3389: QUERY_STRING
  if (url.params.n > 0) {
    // Build "key1=value1&key2=value2" from url.params array
    qs = NULL; qslen = 0;
    for (i = 0; i < url.params.n; ++i) {
      if (i > 0) appendd(&qs, "&", 1);
      appendd(&qs, url.params.p[i].key.p, url.params.p[i].key.n);
      if (url.params.p[i].val.p) {
        appendd(&qs, "=", 1);
        appendd(&qs, url.params.p[i].val.p, url.params.p[i].val.n);
      }
    }
    rb_hash_aset(env, rb_str_new2("QUERY_STRING"), rb_str_new(qs, qslen));
    free(qs);
  } else {
    rb_hash_aset(env, rb_str_new2("QUERY_STRING"), rb_str_new2(""));
  }

  // Lines 3392-3396: SERVER_* variables
  GetServerAddr(&serverip, &serverport);
  rb_hash_aset(env, rb_str_new2("SERVER_NAME"), rb_str_new2("localhost"));
  rb_hash_aset(env, rb_str_new2("SERVER_PORT"),
               rb_str_new2(gc(xasprintf("%d", serverport))));
  rb_hash_aset(env, rb_str_new2("SERVER_PROTOCOL"), rb_str_new2("HTTP/1.1"));
```

**HTTP Headers as HTTP_* Variables:**

```c
  // Lines 3399-3412: Convert HTTP headers to HTTP_* env vars
  for (i = 0; i < kHttpHeadersMax; ++i) {
    if (cpm.msg.headers[i].a) {  // If this header exists
      const char *hdr_name = GetHttpHeaderName(i);  // "Host", "User-Agent", etc.
      char *header_name = gc(xasprintf("HTTP_%s", hdr_name));  // "HTTP_Host"

      // Convert to uppercase and replace - with _
      for (char *c = header_name + 5; *c; ++c) {
        if (*c == '-') *c = '_';      // "User-Agent" → "User_Agent"
        else *c = toupper(*c);        // "User_Agent" → "USER_AGENT"
      }
      // Result: "HTTP_USER_AGENT"

      // Extract header value from input buffer
      rb_hash_aset(env, rb_str_new2(header_name),
                   rb_str_new(inbuf.p + cpm.msg.headers[i].a,
                              cpm.msg.headers[i].b - cpm.msg.headers[i].a));
      // env["HTTP_USER_AGENT"] = "curl/8.5.0"
      // env["HTTP_HOST"] = "localhost:8080"
    }
  }
```

**Rack-Specific Variables:**

```c
  // Lines 3415-3421: Rack protocol variables
  rb_hash_aset(env, rb_str_new2("rack.version"),
               rb_ary_new3(2, INT2NUM(1), INT2NUM(3)));
  // env["rack.version"] = [1, 3]

  rb_hash_aset(env, rb_str_new2("rack.url_scheme"),
               rb_str_new2(usingssl ? "https" : "http"));
  // env["rack.url_scheme"] = "http"

  rb_hash_aset(env, rb_str_new2("rack.input"), Qnil);       // TODO: wrap request body
  rb_hash_aset(env, rb_str_new2("rack.errors"), Qnil);      // TODO: wrap stderr
  rb_hash_aset(env, rb_str_new2("rack.multithread"), Qtrue);
  rb_hash_aset(env, rb_str_new2("rack.multiprocess"), Qtrue);
  rb_hash_aset(env, rb_str_new2("rack.run_once"), Qfalse);
```

**Complete env Hash Example:**

```ruby
{
  # CGI Variables
  "REQUEST_METHOD" => "GET",
  "PATH_INFO" => "/index.rb",
  "QUERY_STRING" => "",
  "SERVER_NAME" => "localhost",
  "SERVER_PORT" => "8080",
  "SERVER_PROTOCOL" => "HTTP/1.1",

  # HTTP Headers
  "HTTP_HOST" => "localhost:8080",
  "HTTP_USER_AGENT" => "curl/8.5.0",
  "HTTP_ACCEPT" => "*/*",

  # Rack Protocol
  "rack.version" => [1, 3],
  "rack.url_scheme" => "http",
  "rack.input" => nil,
  "rack.errors" => nil,
  "rack.multithread" => true,
  "rack.multiprocess" => true,
  "rack.run_once" => false
}
```

##### Step 3c: Execute Ruby Code to Get Rack App

```c
  // Lines 3424-3433: Evaluate the Ruby source code
  rack_app = rb_eval_string_protect(code, &state);

  if (state != 0) {
    // Ruby exception occurred during evaluation
    VALUE exception = rb_errinfo();
    VALUE message = rb_funcall(exception, rb_intern("message"), 0);
    const char *error_msg = StringValueCStr(message);
    ERRORF("(ruby) failed to load Rack app: %s", error_msg);
    return ServeErrorWithDetail(500, "Internal Server Error",
                                ShouldServeCrashReportDetails() ? error_msg : NULL);
  }
```

**What happens inside Ruby:**

```ruby
# code = "lambda do |env|\n  status = 200\n  ..."
rack_app = eval(code)
# Returns a Proc/Lambda object that responds to .call(env)
```

For our example:
```ruby
rack_app = lambda do |env|
  status = 200
  headers = {"Content-Type" => "text/html"}
  body = ["<h1>Hello from Ruby on Redbean!</h1>",
          "<p>Method: #{env['REQUEST_METHOD']}</p>",
          "<p>Path: #{env['PATH_INFO']}</p>"]
  [status, headers, body]
end
```

##### Step 3d: Call the Rack App

```c
  // Line 3436: Invoke the Rack app with env hash
  response = rb_funcall(rack_app, rb_intern("call"), 1, env);
  // Equivalent Ruby: response = rack_app.call(env)
```

**Execution inside Ruby:**

```ruby
env = {
  "REQUEST_METHOD" => "GET",
  "PATH_INFO" => "/index.rb",
  # ...
}

# Lambda executes:
status = 200
headers = {"Content-Type" => "text/html"}
body = ["<h1>Hello from Ruby on Redbean!</h1>",
        "<p>Method: GET</p>",
        "<p>Path: /index.rb</p>"]

# Returns array:
[200, {"Content-Type" => "text/html"}, ["<h1>...", "<p>...", "<p>..."]]
```

##### Step 3e: Validate Rack Response Format

```c
  // Lines 3439-3446: Validate response is [status, headers, body]
  if (TYPE(response) != T_ARRAY || RARRAY_LEN(response) != 3) {
    ERRORF("(ruby) Rack app returned invalid response (expected [status, headers, body])");
    return ServeError(500, "Internal Server Error");
  }

  status_val = rb_ary_entry(response, 0);   // Ruby Integer: 200
  headers_val = rb_ary_entry(response, 1);  // Ruby Hash: {"Content-Type" => ...}
  body_val = rb_ary_entry(response, 2);     // Ruby Array: ["<h1>...", ...]
```

##### Step 3f: Build HTTP Status Line

```c
  // Lines 3448-3449: Convert status to C integer and build status line
  status = NUM2INT(status_val);  // 200
  p = SetStatus(status, GetHttpReason(status));
  // p now points to buffer containing: "HTTP/1.1 200 OK\r\n"
```

##### Step 3g: Process Response Headers

```c
  // Lines 3452-3467: Iterate through headers hash
  if (TYPE(headers_val) == T_HASH) {
    VALUE keys = rb_funcall(headers_val, rb_intern("keys"), 0);
    // keys = ["Content-Type"]

    long hdr_count = RARRAY_LEN(keys);  // 1

    for (long j = 0; j < hdr_count; ++j) {
      VALUE key = rb_ary_entry(keys, j);        // "Content-Type"
      VALUE val = rb_hash_aref(headers_val, key); // "text/html"

      const char *key_str = StringValueCStr(key);  // Convert to C string
      const char *val_str = StringValueCStr(val);

      if (strcasecmp(key_str, "Content-Type") == 0) {
        p = AppendContentType(p, val_str);
        // Appends: "Content-Type: text/html\r\n"
      } else {
        p = AppendHeader(p, key_str, val_str);
        // Appends: "Key: value\r\n" for other headers
      }
    }
  }
```

**HTTP response buffer so far:**
```
HTTP/1.1 200 OK\r\n
Content-Type: text/html\r\n
```

##### Step 3h: Process Response Body

**Rack Spec:** Body must respond to `#each` and yield String values.

```c
  // Lines 3470-3487: Handle body (must be iterable per Rack spec)
  if (TYPE(body_val) == T_ARRAY) {
    // Body is already an array - iterate directly
    long body_count = RARRAY_LEN(body_val);  // 3 chunks

    for (long j = 0; j < body_count; ++j) {
      str = rb_ary_entry(body_val, j);
      // j=0: "<h1>Hello from Ruby on Redbean!</h1>"
      // j=1: "<p>Method: GET</p>"
      // j=2: "<p>Path: /index.rb</p>"

      const char *chunk = StringValuePtr(str);  // C string pointer
      size_t chunk_len = RSTRING_LEN(str);      // Byte length

      appendd(&cpm.outbuf, chunk, chunk_len);
      // Append to output buffer
    }
  } else {
    // Body responds to #each but isn't Array - convert to array first
    VALUE body_array = rb_funcall(body_val, rb_intern("to_a"), 0);
    long body_count = RARRAY_LEN(body_array);
    for (long j = 0; j < body_count; ++j) {
      str = rb_ary_entry(body_array, j);
      const char *chunk = StringValuePtr(str);
      size_t chunk_len = RSTRING_LEN(str);
      appendd(&cpm.outbuf, chunk, chunk_len);
    }
  }

  // Lines 3490-3492: Call close on body if it responds to it (Rack spec)
  if (rb_respond_to(body_val, rb_intern("close"))) {
    rb_funcall(body_val, rb_intern("close"), 0);
    // Allows body to clean up resources (e.g., close file handles)
  }
```

**Output buffer (`cpm.outbuf`) now contains:**
```html
<h1>Hello from Ruby on Redbean!</h1><p>Method: GET</p><p>Path: /index.rb</p>
```

##### Step 3i: Finalize HTTP Response

```c
  // Line 3494: Commit output and return
  return CommitOutput(p);
```

**What CommitOutput() does:**
1. Calculates `Content-Length` from `cpm.outbuf.n`
2. Adds `Content-Length: 76\r\n`
3. Adds blank line: `\r\n`
4. Returns pointer to complete HTTP response

**Complete HTTP Response:**
```http
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 76

<h1>Hello from Ruby on Redbean!</h1><p>Method: GET</p><p>Path: /index.rb</p>
```

#### Step 4: Send Response to Client

Redbean sends the HTTP response over the TCP socket and either:
- Closes connection (HTTP/1.0)
- Keeps connection alive for next request (HTTP/1.1 Keep-Alive)

## Memory Management

### Memory Allocation Namespace Collision

**Problem:** Ruby's headers redefine Cosmopolitan's memory allocation functions:

```c
// Ruby's third_party/ruby/include/ruby/internal/xmalloc.h:
#define xmalloc   ruby_xmalloc
#define xcalloc   ruby_xcalloc
#define xrealloc  ruby_xrealloc
#define xfree     ruby_xfree

// But Cosmopolitan already has:
// libc/x/x.h:
#define xmalloc   __xmalloc
#define xcalloc   __xcalloc
#define xrealloc  __xrealloc
```

**Solution:** Header include sequence with macro isolation:

```c
// tool/net/redbean.c lines 122-137:
#ifndef STATIC
  // 1. Undefine Cosmopolitan's macros BEFORE including Ruby
  #undef xmalloc
  #undef xcalloc
  #undef xrealloc

  // 2. Include Ruby headers (which define their own versions)
  #define _GETOPT_CORE_H  /* Block getopt conflicts */
  #include "third_party/ruby/include/ruby.h"

  // 3. Undefine Ruby's macros AFTER including Ruby
  #undef xmalloc
  #undef xcalloc
  #undef xrealloc
  #undef xfree

  // 4. Restore Cosmopolitan's allocators for Redbean code
  #define xmalloc       __xmalloc
  #define xcalloc       __xcalloc
  #define xrealloc      __xrealloc
#endif
```

**Why this works:**
- Ruby code (inside Ruby VM) uses `ruby_xmalloc` (requires Ruby initialized)
- Redbean code (C) uses `__xmalloc` (Cosmopolitan's allocator)
- No collision because they operate in separate namespaces

### Memory Scopes

1. **Request-scoped:** `FreeLater()`, `gc()` - Freed at request end
2. **Global:** Ruby VM state, Lua state - Persists across requests
3. **Ruby GC:** Ruby objects managed by Ruby's garbage collector
4. **Cosmopolitan GC:** Redbean's request-scoped garbage collection

## Key Data Structures

### `struct Asset`
Represents a file in the embedded ZIP:
```c
struct Asset {
  uint32_t hash;        // Hash of filename
  uint32_t offset;      // Offset in ZIP
  uint32_t size;        // Uncompressed size
  uint16_t method;      // Compression method
  // ... more fields
};
```

### `cpm` (Connection Process Message)
```c
struct {
  struct {
    uint64_t method;           // HTTP method (GET, POST, etc.)
    struct Header headers[kHttpHeadersMax];  // HTTP headers
    // ... more request fields
  } msg;

  struct {
    char *p;      // Output buffer pointer
    size_t n;     // Output buffer length
  } outbuf;
} cpm;
```

### `url`
```c
struct {
  struct {
    const char *p;  // Path pointer
    size_t n;       // Path length
  } path;

  struct {
    size_t n;                // Number of parameters
    struct Param {
      struct String key;
      struct String val;
    } *p;                    // Parameter array
  } params;
} url;
```

## Error Handling

### Ruby Load Errors

**Syntax errors in .rb file:**
```c
if (state != 0) {
  VALUE exception = rb_errinfo();
  VALUE message = rb_funcall(exception, rb_intern("message"), 0);
  const char *error_msg = StringValueCStr(message);
  ERRORF("(ruby) failed to load Rack app: %s", error_msg);
  return ServeErrorWithDetail(500, "Internal Server Error", error_msg);
}
```

**Example error:**
```
error: (ruby) failed to load Rack app: syntax error, unexpected end-of-input
HTTP/1.1 500 Internal Server Error
```

### Rack Protocol Violations

**Invalid response format:**
```c
if (TYPE(response) != T_ARRAY || RARRAY_LEN(response) != 3) {
  ERRORF("(ruby) Rack app returned invalid response (expected [status, headers, body])");
  return ServeError(500, "Internal Server Error");
}
```

**Example:** If Ruby returns `"Hello"` instead of `[200, {}, ["Hello"]]`

## Performance Considerations

### Ruby VM Initialization

- **One-time cost:** Ruby VM initialized once at server startup
- **Per-request cost:** Only loading and executing script
- **VM state:** Shared across all requests (thread-safe via Ruby's GVL)

### Comparison with Lua

| Aspect | Lua | Ruby |
|--------|-----|------|
| VM initialization | ~0.1ms | ~10ms |
| Per-request overhead | ~0.01ms | ~0.1ms |
| Memory footprint | ~1MB | ~20MB |
| Script execution | Very fast | Fast |
| Standard library | Minimal | Extensive |

### Optimization Opportunities

1. **Pre-compile Ruby scripts** - Use `RubyVM::InstructionSequence`
2. **Cache Rack apps** - Keep lambda objects in memory
3. **Connection pooling** - Reuse Ruby threads across requests
4. **JIT compilation** - Enable YJIT (disabled in current port)

## Testing

### The Test/Build/Verify Workflow

This is the standard cycle for testing Ruby apps in Redbean:

#### Step 1: Create Test Structure

```bash
# Create directory for your test app
mkdir -p /tmp/my-test-app

# Create Ruby script(s)
cat > /tmp/my-test-app/hello.rb <<'EOF'
lambda do |env|
  [200,
   {"Content-Type" => "text/plain"},
   ["Hello from #{env['SERVER_NAME']}:#{env['SERVER_PORT']}"]]
end
EOF

# Can create multiple files
cat > /tmp/my-test-app/api.rb <<'EOF'
lambda do |env|
  [200,
   {"Content-Type" => "application/json"},
   ['{"status":"ok","path":"' + env['PATH_INFO'] + '"}']]
end
EOF
```

#### Step 2: Build Redbean with Test App

```bash
# 1. Build redbean (if not already built)
make -j8 o//tool/net/redbean

# 2. Copy base binary
cp o/tool/net/redbean /tmp/my-test.com

# 3. Create ZIP of your app
cd /tmp/my-test-app && zip -r ../my-app.zip .

# 4. Append ZIP to binary
cd /tmp && cat my-app.zip >> my-test.com

# 5. CRITICAL: Fix ZIP offsets
zip -A /tmp/my-test.com
# Output: "Zip entry offsets appear off by 8080286 bytes - correcting..."
```

#### Step 3: Test Your App

```bash
# Start server in background
/tmp/my-test.com -p 8080 &
REDBEAN_PID=$!

# Wait for startup
sleep 2

# Test your endpoints
curl http://localhost:8080/hello.rb
# Output: Hello from localhost:8080

curl http://localhost:8080/api.rb
# Output: {"status":"ok","path":"/api.rb"}

# Stop server
kill $REDBEAN_PID
wait $REDBEAN_PID 2>/dev/null
```

#### Complete Example Script

```bash
#!/bin/bash
# test-ruby-app.sh - Complete test workflow

set -e

# 1. Create test app
mkdir -p /tmp/my-test-app
cat > /tmp/my-test-app/hello.rb <<'EOF'
lambda do |env|
  [200,
   {"Content-Type" => "text/html"},
   ["<h1>Hello!</h1><p>Method: #{env['REQUEST_METHOD']}</p>"]]
end
EOF

# 2. Build
echo "Building redbean..."
make -j8 o//tool/net/redbean

# 3. Package
echo "Packaging app..."
cp o/tool/net/redbean /tmp/test.com
cd /tmp/my-test-app && zip -q -r ../app.zip .
cd /tmp && cat app.zip >> test.com
zip -A test.com 2>&1 | grep -q "correcting" && echo "ZIP offsets fixed"

# 4. Test
echo "Starting server..."
/tmp/test.com -p 8080 &
REDBEAN_PID=$!
sleep 2

echo "Testing endpoint..."
curl -s http://localhost:8080/hello.rb

# 5. Cleanup
kill $REDBEAN_PID
wait $REDBEAN_PID 2>/dev/null
echo "Done"
```

### Routing and Index Files

#### How Routing Works

Redbean routes requests **by file extension** and **exact path**:

```
URL Path                  →  Action
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/hello.rb                 →  Execute /hello.rb as Ruby
/api/users.rb             →  Execute /api/users.rb as Ruby
/script.lua               →  Execute /script.lua as Lua
/style.css                →  Serve /style.css as static file
/                         →  Show directory listing (NOT index.rb)
```

#### Index File Behavior

**IMPORTANT:** Unlike traditional web servers, Redbean does **NOT** automatically serve `index.rb` when you access `/`.

```bash
# Test this behavior
mkdir -p /tmp/index-test
cat > /tmp/index-test/index.rb <<'EOF'
lambda do |env|
  [200, {"Content-Type" => "text/html"}, ["<h1>This is the index!</h1>"]]
end
EOF

cp o/tool/net/redbean /tmp/index-test.com
cd /tmp/index-test && zip -r ../index.zip .
cd /tmp && cat index.zip >> index-test.com
zip -A /tmp/index-test.com

/tmp/index-test.com -p 8081 &
sleep 2

# Accessing root shows directory listing, NOT index.rb
curl http://localhost:8081/
# Output: HTML directory listing with link to /index.rb

# Must explicitly request the file
curl http://localhost:8081/index.rb
# Output: <h1>This is the index!</h1>

pkill -f index-test.com
```

#### Workarounds for Index Behavior

If you want "index" functionality, you have options:

**Option 1: Explicit paths**
```ruby
# Just document that users should access /index.rb explicitly
# http://localhost:8080/index.rb
```

**Option 2: HTML redirect**
```bash
# Create an index.html that redirects
cat > index.html <<'EOF'
<!DOCTYPE html>
<meta http-equiv="refresh" content="0; url=/app.rb">
<p>Redirecting to <a href="/app.rb">app.rb</a>...</p>
EOF
```

**Option 3: Use full paths in documentation**
```markdown
# Your app documentation:
Visit http://localhost:8080/app.rb to access the application
```

### Debug with Verbose Logging

Enable verbose logging to see detailed request/response information:

```bash
/tmp/test.com -v -p 8080
```

**Output shows:**
```
I2025-10-29T09:32:30:tool/net/redbean.c:7283 (srvr) listen http://127.0.0.1:8080
I2025-10-29T09:32:30+000028:tool/net/redbean.c:7283 (srvr) listen http://192.168.43.181:8080
I2025-10-29T09:32:32:tool/net/redbean.c:6320 (req) received 127.0.0.1:53982 HTTP11 GET http://localhost:8080/hello.rb "" "curl/8.5.0"
I2025-10-29T09:32:32:tool/net/redbean.c:3359 (ruby) executing Rack app `/hello.rb` (272 bytes)
```

**What each log line means:**
- `(srvr) listen` - Server listening on address:port
- `(req) received` - HTTP request received (shows client IP, method, URL, User-Agent)
- `(ruby) executing Rack app` - Ruby script being executed (shows path and size)

### Testing Multiple Ruby Files

Create a multi-file app structure:

```bash
mkdir -p /tmp/multi-test/api /tmp/multi-test/admin

# Main page
cat > /tmp/multi-test/main.rb <<'EOF'
lambda do |env|
  [200, {"Content-Type" => "text/html"},
   ["<h1>Main Page</h1>",
    "<ul>",
    "<li><a href='/api/users.rb'>Users API</a></li>",
    "<li><a href='/admin/dashboard.rb'>Admin</a></li>",
    "</ul>"]]
end
EOF

# API endpoint
cat > /tmp/multi-test/api/users.rb <<'EOF'
lambda do |env|
  [200, {"Content-Type" => "application/json"},
   ['{"users":[{"id":1,"name":"Alice"},{"id":2,"name":"Bob"}]}']]
end
EOF

# Admin page
cat > /tmp/multi-test/admin/dashboard.rb <<'EOF'
lambda do |env|
  [200, {"Content-Type" => "text/html"},
   ["<h1>Admin Dashboard</h1><p>Server: #{env['SERVER_NAME']}</p>"]]
end
EOF

# Build and test
cp o/tool/net/redbean /tmp/multi-test.com
cd /tmp/multi-test && zip -r ../multi.zip .
cd /tmp && cat multi.zip >> multi-test.com
zip -A /tmp/multi-test.com

/tmp/multi-test.com -p 8080 &
sleep 2

curl http://localhost:8080/main.rb
curl http://localhost:8080/api/users.rb
curl http://localhost:8080/admin/dashboard.rb

pkill -f multi-test.com
```

### Testing with Query Parameters

```ruby
# /tmp/test-app/search.rb
lambda do |env|
  query = env['QUERY_STRING']
  [200,
   {"Content-Type" => "text/html"},
   ["<h1>Search</h1>",
    "<p>Query string: #{query}</p>",
    "<p>Full path: #{env['PATH_INFO']}?#{query}</p>"]]
end
```

```bash
# Test with parameters
curl "http://localhost:8080/search.rb?q=ruby&limit=10"
# Output: <h1>Search</h1><p>Query string: q=ruby&limit=10</p>...
```

### Testing Error Handling

Test how errors are handled:

```ruby
# /tmp/test-app/error.rb
lambda do |env|
  # This will cause a Ruby exception
  unknown_variable
end
```

```bash
curl http://localhost:8080/error.rb
# Output: HTTP/1.1 500 Internal Server Error
# (error details in server logs if in debug mode)
```

**Check server logs:**
```bash
/tmp/test.com -v -p 8080
# Shows: (ruby) failed to load Rack app: undefined local variable or method `unknown_variable'
```

## Current Limitations

### Not Yet Implemented

1. **rack.input** - Request body reading
   - Need to wrap `cpm.msg.entity` buffer
   - Implement `read()`, `gets()`, `each()` methods

2. **rack.errors** - Error stream
   - Need to redirect Ruby's stderr
   - Capture warnings and exceptions

3. **File uploads** - Multipart parsing
   - Need to implement `Rack::Multipart` equivalent
   - Handle `multipart/form-data` requests

4. **.init.rb / .reload.rb** - Auto-run scripts
   - Similar to Lua's `.init.lua` and `.reload.lua`
   - Run on server start and hot reload

5. **Native extension gems** - .so loading
   - Need dynamic extension loader (see `RUBY_ZIP_EXTENSION_LOADER.md`)
   - Would enable nokogiri, pg, mysql2, etc.

### Known Issues

1. **Missing help.txt** - Harmless warning on startup
2. **Missing SSL root certs** - Warning: `/zip/usr/share/ssl/root: No such file or directory`
3. **mkdeps warnings** - Ruby files not in HDRS/SRCS/INCS (non-blocker)

## Future Enhancements

### High Priority

1. **Implement rack.input** - Enable POST/PUT requests
2. **Add .init.rb support** - Initialization scripts
3. **Add .reload.rb support** - Hot reloading
4. **Test with Sinatra** - Real-world Rack app

### Medium Priority

5. **Dynamic .so loader** - Native extension support
6. **Performance benchmarking** - Compare with Puma/Unicorn
7. **Error page improvements** - Better 500 error pages
8. **Documentation** - User-facing Ruby API docs

### Low Priority

9. **REPL integration** - Interactive Ruby console in redbean
10. **Rack middleware examples** - Common middleware patterns
11. **Rails Metal support** - Minimal Rails integration
12. **RubyGems in ZIP** - Package gems into APE

## Build System Integration

### Dependencies

```makefile
# tool/net/BUILD.mk line 67:
TOOL_NET_DIRECTDEPS = \
    # ... other deps ...
    THIRD_PARTY_RUBY \
    # ...
```

### Compiler Flags

```makefile
# Lines 124-132: Ruby include paths for all redbean variants
o/$(MODE)/tool/net/redbean.o: private \
    CFLAGS += \
        -Ithird_party/ruby/include \
        -Wno-unused-but-set-variable

o/$(MODE)/tool/net/redbean-unsecure.o: private \
    CFLAGS += \
        -Ithird_party/ruby/include \
        -Wno-unused-but-set-variable

o/$(MODE)/tool/net/redbean-original.o: private \
    CFLAGS += \
        -Ithird_party/ruby/include \
        -Wno-unused-but-set-variable
```

### Static Build Exclusion

```c
// Ruby is excluded from STATIC builds (like redbean-static)
#ifndef STATIC
  // Ruby code here
#endif
```

## Creating Distributable Binaries

### Proper ZIP Embedding Process

**CRITICAL:** Must use `zip -A` after appending ZIP to fix offsets!

```bash
# 1. Build base redbean
make -j8 o//tool/net/redbean

# 2. Copy and rename for distribution
cp o/tool/net/redbean my-app.com

# 3. Create ZIP of your Ruby app
cd my-ruby-app/
zip -r ../app.zip .

# 4. Append ZIP to binary
cd ..
cat app.zip >> my-app.com

# 5. FIX ZIP OFFSETS (REQUIRED!)
zip -A my-app.com
# Output: "Zip entry offsets appear off by 8080286 bytes - correcting..."

# 6. Distribute
chmod +x my-app.com
./my-app.com -p 8080
```

**Why `zip -A` is required:**
- ZIP central directory contains byte offsets to each file
- When you `cat` a ZIP onto a binary, offsets are wrong by the binary size
- `zip -A` (adjust self-extracting) recalculates these offsets
- Without it, Redbean fails with: `CHECK_EQ(kZipCfileHdrMagic, ZIP_CFILE_MAGIC(zmap + cf))`

### Directory Structure in ZIP

```
/                       # Root of ZIP filesystem
├── index.rb           # Served at http://host/index.rb
├── api/
│   └── users.rb      # Served at http://host/api/users.rb
├── lib/
│   └── helpers.rb    # Can be required by other scripts
└── public/
    └── style.css     # Static assets
```

## Debugging Tips

### Enable Verbose Logging

```bash
# -v flag shows detailed request/response logs
./redbean.com -v -p 8080
```

### Check ZIP Contents

```bash
# View files embedded in APE
zipinfo redbean.com

# Extract all files
unzip redbean.com -d /tmp/extracted
```

### Test Ruby Standalone

```bash
# Test Ruby interpreter works
o//third_party/ruby/ruby -e 'puts "Hello"'

# Test with RUBYLIB
RUBYLIB=$PWD/third_party/ruby/lib o//third_party/ruby/ruby script.rb
```

### GDB Debugging

```bash
# Debug with symbols
gdb o/tool/net/redbean.dbg
(gdb) run -p 8080
# Make request in another terminal
(gdb) bt   # Backtrace when it crashes
```

## Comparison: Lua vs Ruby in Redbean

### Lua Implementation (Existing)

```lua
-- .lua file executed directly
SetStatus(200, "OK")
SetHeader("Content-Type", "text/html")
Write("<h1>Hello from Lua!</h1>")
Write("<p>Method: " .. GetMethod() .. "</p>")
```

**Architecture:**
- Custom C API: `SetStatus()`, `Write()`, `GetMethod()`
- Functions registered in `kLuaFuncs[]` array
- Direct output to response buffer
- No standard interface

### Ruby Implementation (New)

```ruby
# .rb file returns Rack app
lambda do |env|
  [200,
   {"Content-Type" => "text/html"},
   ["<h1>Hello from Ruby!</h1>",
    "<p>Method: #{env['REQUEST_METHOD']}</p>"]]
end
```

**Architecture:**
- Standard Rack interface
- No Redbean-specific API needed
- Returns structured data
- Compatible with Rack ecosystem

### Coexistence

Both work simultaneously:
- `.lua` files → `ServeLua()` → Lua VM
- `.rb` files → `ServeRuby()` → Ruby VM
- Static files → `ServeAsset()`
- Both can coexist in same APE

## References

### Documentation

- **Rack Specification:** https://github.com/rack/rack/blob/main/SPEC.rdoc
- **Ruby C API:** https://docs.ruby-lang.org/en/master/extension_rdoc.html
- **Redbean Documentation:** https://redbean.dev/
- **Cosmopolitan Libc:** https://justine.lol/cosmopolitan/

### Related Docs

- `RUBY_PORT_PROGRESS.md` - Complete Ruby porting history
- `RUBY_RELEASE_READINESS.md` - Release status and known issues
- `RUBY_ZIP_EXTENSION_LOADER.md` - Future native extension loading plan
- `COSMORUBY_MAKEFILE_ANALYSIS.md` - Build system details

## Success Criteria

### ✅ Completed

- [x] Ruby 3.4.7 fully ported to Cosmopolitan
- [x] Redbean serves `.rb` files
- [x] Full Rack interface implemented
- [x] CGI environment variables populated correctly
- [x] HTTP headers converted to HTTP_* variables
- [x] Status, headers, body extracted from Rack response
- [x] Error handling for Ruby exceptions
- [x] Memory allocation namespace collision resolved
- [x] RUBY_INIT_STACK placement fixed
- [x] ZIP embedding process documented
- [x] Test application working end-to-end

### 🔄 In Progress

- [ ] Add `.init.rb` and `.reload.rb` auto-run functionality
- [ ] Implement `rack.input` for request body reading
- [ ] Implement `rack.errors` for error stream
- [ ] Test gem install workflow with pure Ruby gems
- [ ] Run full Ruby test suite (test-all)

### 📋 Planned

- [ ] Test real-world Ruby programs (Sinatra, etc.)
- [ ] Plan native extension support (dynamic .so loading)
- [ ] Performance benchmarking vs other Rack servers
- [ ] User-facing documentation and examples
- [ ] Production readiness validation

---

**Last Updated:** 2025-10-29
**Status:** ✅ Working implementation, actively being enhanced
**Maintainer:** See git history for contributors
