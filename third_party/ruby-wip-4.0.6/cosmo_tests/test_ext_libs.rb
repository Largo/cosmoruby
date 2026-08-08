# frozen_string_literal: true
# Test that ALL extensions and their Ruby library files are packaged correctly.
# Covers every C extension in extinit.c and every ext/*/lib Ruby file.
#
# Run with: ruby.com third_party/ruby-wip-4.0.6/cosmo_tests/test_ext_libs.rb

passed = 0
failed = 0
errors = []

def test(name)
  print "  #{name.ljust(55)}"
  begin
    result = yield
    if result
      puts "ok"
      return true
    else
      puts "FAIL"
      return false
    end
  rescue => e
    puts "ERROR: #{e.class}: #{e.message}"
    return false
  end
end

puts "CosmoRuby extension packaging tests"
puts "=" * 65
puts "Ruby: #{RUBY_VERSION} (#{RUBY_PLATFORM})"
puts

########################################################################
# C EXTENSIONS (from extinit.c)
########################################################################

puts "C Extensions (extinit.c)"
puts "-" * 65

# -- continuation --
puts "\ncontinuation:"
if test("require 'continuation'") { require 'continuation'; true }
  passed += 1
else
  failed += 1
  errors << "continuation: require failed"
end
if test("callcc defined (private)") { Kernel.private_method_defined?(:callcc) }
  passed += 1
else
  failed += 1
  errors << "continuation: callcc not defined"
end

# -- coverage --
puts "\ncoverage:"
if test("require 'coverage'") { require 'coverage'; true }
  passed += 1
else
  failed += 1
  errors << "coverage: require failed"
end
if test("Coverage.start / .result cycle") {
  Coverage.start
  Coverage.result
  true
}
  passed += 1
else
  failed += 1
  errors << "coverage: start/result cycle failed"
end

# -- date --
puts "\ndate:"
if test("require 'date'") { require 'date'; true }
  passed += 1
else
  failed += 1
  errors << "date: require failed"
end
if test("Date.today works") { Date.today.is_a?(Date) }
  passed += 1
else
  failed += 1
  errors << "date: Date.today failed"
end
if test("DateTime.now works") { DateTime.now.is_a?(DateTime) }
  passed += 1
else
  failed += 1
  errors << "date: DateTime.now failed"
end

# -- digest (core + md5 + sha1 + sha2) --
puts "\ndigest:"
if test("require 'digest'") { require 'digest'; true }
  passed += 1
else
  failed += 1
  errors << "digest: require failed"
end
if test("Digest::MD5") {
  require 'digest/md5'
  Digest::MD5.hexdigest('test') == '098f6bcd4621d373cade4e832627b4f6'
}
  passed += 1
else
  failed += 1
  errors << "digest: MD5 failed"
end
if test("Digest::SHA1") {
  require 'digest/sha1'
  Digest::SHA1.hexdigest('test').length == 40
}
  passed += 1
else
  failed += 1
  errors << "digest: SHA1 failed"
end
if test("Digest::SHA256") {
  require 'digest/sha2'
  Digest::SHA256.hexdigest('test').length == 64
}
  passed += 1
else
  failed += 1
  errors << "digest: SHA256 failed"
end
if test("Digest::SHA512") {
  Digest::SHA512.hexdigest('test').length == 128
}
  passed += 1
else
  failed += 1
  errors << "digest: SHA512 failed"
end

# -- etc --
puts "\netc:"
if test("require 'etc'") { require 'etc'; true }
  passed += 1
else
  failed += 1
  errors << "etc: require failed"
end
if test("Etc.getlogin or Etc.nprocessors") {
  Etc.respond_to?(:getlogin) && Etc.respond_to?(:nprocessors)
}
  passed += 1
else
  failed += 1
  errors << "etc: missing methods"
end

# -- fcntl --
puts "\nfcntl:"
if test("require 'fcntl'") { require 'fcntl'; true }
  passed += 1
else
  failed += 1
  errors << "fcntl: require failed"
end
if test("Fcntl::O_RDONLY defined") { defined?(Fcntl::O_RDONLY) }
  passed += 1
else
  failed += 1
  errors << "fcntl: constants missing"
end

# -- io/console --
puts "\nio/console:"
if test("require 'io/console'") { require 'io/console'; true }
  passed += 1
else
  failed += 1
  errors << "io/console: require failed"
end
if test("$stdout.winsize responds") { $stdout.respond_to?(:winsize) }
  passed += 1
else
  failed += 1
  errors << "io/console: $stdout.winsize missing"
end
if test("require 'console/size' + IO.console_size") {
  require 'console/size'
  IO.respond_to?(:console_size)
}
  passed += 1
else
  failed += 1
  errors << "io/console: console/size.rb not loaded"
end

# -- io/nonblock --
puts "\nio/nonblock:"
if test("require 'io/nonblock'") { require 'io/nonblock'; true }
  passed += 1
else
  failed += 1
  errors << "io/nonblock: require failed"
end
if test("IO#nonblock? method exists") {
  IO.method_defined?(:nonblock?)
}
  passed += 1
else
  failed += 1
  errors << "io/nonblock: nonblock? missing"
end

# -- io/wait --
puts "\nio/wait:"
if test("require 'io/wait'") { require 'io/wait'; true }
  passed += 1
else
  failed += 1
  errors << "io/wait: require failed"
end
if test("IO#wait_readable method exists") {
  IO.method_defined?(:wait_readable)
}
  passed += 1
else
  failed += 1
  errors << "io/wait: wait_readable missing"
end

# -- json --
puts "\njson:"
if test("require 'json'") { require 'json'; true }
  passed += 1
else
  failed += 1
  errors << "json: require failed"
end
if test("JSON.parse round-trip") {
  JSON.parse(JSON.generate({'a' => 1, 'b' => [2, 3]})) == {'a' => 1, 'b' => [2, 3]}
}
  passed += 1
else
  failed += 1
  errors << "json: parse/generate round-trip failed"
end

# -- mbedtls (Cosmopolitan's TLS) --
puts "\nmbedtls:"
if test("require 'mbedtls'") { require 'mbedtls'; true }
  passed += 1
else
  failed += 1
  errors << "mbedtls: require failed"
end
if test("MbedTLS::SSL class defined") { defined?(MbedTLS::SSL) }
  passed += 1
else
  failed += 1
  errors << "mbedtls: MbedTLS::SSL missing"
end

# -- openssl (compatibility shim over mbedtls) --
puts "\nopenssl (mbedtls shim):"
if test("require 'openssl'") { require 'openssl'; true }
  passed += 1
else
  failed += 1
  errors << "openssl: require failed"
end
if test("OpenSSL::SSL::SSLSocket defined") { defined?(OpenSSL::SSL::SSLSocket) }
  passed += 1
else
  failed += 1
  errors << "openssl: SSLSocket missing"
end
if test("OpenSSL::SSL::SSLContext defined") { defined?(OpenSSL::SSL::SSLContext) }
  passed += 1
else
  failed += 1
  errors << "openssl: SSLContext missing"
end
if test("OpenSSL::SSL::VERIFY_PEER constant") { OpenSSL::SSL::VERIFY_PEER.is_a?(Integer) }
  passed += 1
else
  failed += 1
  errors << "openssl: VERIFY_PEER constant missing"
end

# -- monitor --
puts "\nmonitor:"
if test("require 'monitor'") { require 'monitor'; true }
  passed += 1
else
  failed += 1
  errors << "monitor: require failed"
end
if test("Monitor#synchronize works") {
  m = Monitor.new
  m.synchronize { 42 } == 42
}
  passed += 1
else
  failed += 1
  errors << "monitor: synchronize failed"
end

# -- psych (YAML) --
puts "\npsych:"
if test("require 'psych'") { require 'psych'; true }
  passed += 1
else
  failed += 1
  errors << "psych: require failed"
end
if test("Psych.dump / .load round-trip") {
  data = {'key' => [1, 2, 'three']}
  Psych.safe_load(Psych.dump(data), permitted_classes: [Symbol]) == data
}
  passed += 1
else
  failed += 1
  errors << "psych: dump/load round-trip failed"
end

# -- rbconfig/sizeof --
puts "\nrbconfig/sizeof:"
if test("require 'rbconfig/sizeof'") { require 'rbconfig/sizeof'; true }
  passed += 1
else
  failed += 1
  errors << "rbconfig/sizeof: require failed"
end
if test("RbConfig::SIZEOF has entries") {
  RbConfig::SIZEOF.is_a?(Hash) && RbConfig::SIZEOF.size > 0
}
  passed += 1
else
  failed += 1
  errors << "rbconfig/sizeof: SIZEOF hash empty"
end

# -- ripper --
puts "\nripper:"
if test("require 'ripper'") { require 'ripper'; true }
  passed += 1
else
  failed += 1
  errors << "ripper: require failed"
end
if test("Ripper.sexp parses Ruby code") {
  sexp = Ripper.sexp('puts "hello"')
  sexp.is_a?(Array) && sexp[0] == :program
}
  passed += 1
else
  failed += 1
  errors << "ripper: sexp parsing failed"
end

# -- socket --
puts "\nsocket:"
if test("require 'socket'") { require 'socket'; true }
  passed += 1
else
  failed += 1
  errors << "socket: require failed"
end
if test("Socket constants defined") {
  defined?(Socket::AF_INET) && defined?(Socket::SOCK_STREAM)
}
  passed += 1
else
  failed += 1
  errors << "socket: constants missing"
end
if test("TCPServer bind/close") {
  srv = TCPServer.new('127.0.0.1', 0)
  port = srv.addr[1]
  srv.close
  port > 0
}
  passed += 1
else
  failed += 1
  errors << "socket: TCPServer failed"
end

# -- stringio --
puts "\nstringio:"
if test("require 'stringio'") { require 'stringio'; true }
  passed += 1
else
  failed += 1
  errors << "stringio: require failed"
end
if test("StringIO read/write") {
  sio = StringIO.new
  sio.write('hello')
  sio.rewind
  sio.read == 'hello'
}
  passed += 1
else
  failed += 1
  errors << "stringio: read/write failed"
end

# -- strscan --
puts "\nstrscan:"
if test("require 'strscan'") { require 'strscan'; true }
  passed += 1
else
  failed += 1
  errors << "strscan: require failed"
end
if test("StringScanner scan/rest") {
  s = StringScanner.new('hello world')
  s.scan(/\w+/) == 'hello' && s.rest == ' world'
}
  passed += 1
else
  failed += 1
  errors << "strscan: scan/rest failed"
end
if test("strscan/strscan.rb loaded (scan_integer)") {
  StringScanner.new('42').respond_to?(:scan_integer)
}
  passed += 1
else
  failed += 1
  errors << "strscan: strscan/strscan.rb not loaded"
end

# -- zlib --
puts "\nzlib:"
if test("require 'zlib'") { require 'zlib'; true }
  passed += 1
else
  failed += 1
  errors << "zlib: require failed"
end
if test("Zlib deflate/inflate round-trip") {
  original = 'hello cosmoruby zlib test'
  Zlib::Inflate.inflate(Zlib::Deflate.deflate(original)) == original
}
  passed += 1
else
  failed += 1
  errors << "zlib: deflate/inflate round-trip failed"
end

# -- objspace --
puts "\nobjspace:"
if test("require 'objspace'") { require 'objspace'; true }
  passed += 1
else
  failed += 1
  errors << "objspace: require failed"
end
if test("ObjectSpace.memsize_of works") {
  ObjectSpace.memsize_of('hello').is_a?(Integer)
}
  passed += 1
else
  failed += 1
  errors << "objspace: memsize_of failed"
end

########################################################################
# RUBY LIB FILES FROM ext/*/lib (not C extensions, but Ruby companions)
########################################################################

puts "\n"
puts "Extension Ruby library files (ext/*/lib)"
puts "-" * 65

# -- expect (from ext/pty/lib) --
puts "\nexpect (pty):"
if test("require 'expect'") { require 'expect'; true }
  passed += 1
else
  failed += 1
  errors << "expect: require failed"
end
if test("IO#expect method defined") { IO.method_defined?(:expect) }
  passed += 1
else
  failed += 1
  errors << "expect: IO#expect not defined"
end

# -- forwardable/impl (from ext/rubyvm/lib) --
puts "\nforwardable/impl (rubyvm):"
if test("require 'forwardable'") { require 'forwardable'; true }
  passed += 1
else
  failed += 1
  errors << "forwardable: require failed"
end
if test("require 'forwardable/impl'") { require 'forwardable/impl'; true }
  passed += 1
else
  failed += 1
  errors << "forwardable/impl: require failed"
end
if test("Forwardable._valid_method? defined") {
  Forwardable.respond_to?(:_valid_method?)
}
  passed += 1
else
  failed += 1
  errors << "forwardable/impl: _valid_method? missing"
end
if test("Forwardable._compile_method defined") {
  Forwardable.respond_to?(:_compile_method)
}
  passed += 1
else
  failed += 1
  errors << "forwardable/impl: _compile_method missing"
end

# -- win32/resolv (from ext/win32/lib) --
puts "\nwin32:"
if test("win32/resolv.rb findable on $LOAD_PATH") {
  $LOAD_PATH.any? { |p| File.exist?(File.join(p, 'win32', 'resolv.rb')) }
}
  passed += 1
else
  failed += 1
  errors << "win32/resolv: not on load path"
end
if test("win32/registry.rb findable on $LOAD_PATH") {
  $LOAD_PATH.any? { |p| File.exist?(File.join(p, 'win32', 'registry.rb')) }
}
  passed += 1
else
  failed += 1
  errors << "win32/registry: not on load path"
end
# Only try to require on Windows; on other platforms just check file exists
if RUBY_PLATFORM =~ /mingw|mswin|cosmo.*nt/i || (defined?(IsWindows) && IsWindows())
  if test("require 'win32/resolv' (Windows)") { require 'win32/resolv'; true }
    passed += 1
  else
    failed += 1
    errors << "win32/resolv: require failed on Windows"
  end
else
  if test("require 'win32/resolv' (non-Windows, may fail)") {
    begin
      require 'win32/resolv'
      true
    rescue LoadError, RuntimeError
      # Expected on non-Windows - the file exists but may need Win32 APIs
      true
    end
  }
    passed += 1
  else
    failed += 1
    errors << "win32/resolv: unexpected error"
  end
end

########################################################################
# SUMMARY
########################################################################

puts "\n" + "=" * 65
total = passed + failed
puts "#{total} tests, #{passed} passed, #{failed} failed"
if failed > 0
  puts "\nFailures:"
  errors.each { |e| puts "  - #{e}" }
  exit 1
else
  puts "\nAll extensions packaged and functional."
  exit 0
end
