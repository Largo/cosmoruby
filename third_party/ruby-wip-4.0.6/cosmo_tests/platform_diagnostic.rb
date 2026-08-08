#!/usr/bin/env ruby
# frozen_string_literal: true

# CosmoRuby Cross-Platform Diagnostic Test Suite
#
# Self-contained script that verifies ruby.com works correctly on any
# platform. No external gems required -- works with --disable-gems.
#
# Usage:
#   ruby.com --disable-gems platform_diagnostic.rb [OPTIONS]
#
# Options:
#   --json          Machine-parseable JSON output
#   --no-network    Skip network-dependent tests
#   --strict        Treat expected failures as actual failures
#   --verbose       Detailed platform info on failure
#   --timeout SECS  Override default timeout per test section
#   --retry N       Override default retry count for flaky tests
#
# Exit codes:
#   0 = pass (or only expected failures/warnings)
#   1 = one or more unexpected failures
#   2 = script crash (Ruby exception or infrastructure failure)
#   3 = command-line argument error

require 'etc'
require 'rbconfig'
require 'tempfile'
require 'fileutils'

# ── Platform detection ────────────────────────────────────────────────

PLATFORM_MAP = {
  'Linux'      => 'linux',
  'Darwin'     => 'macos',
  'Windows_NT' => 'windows',
  'MINGW'      => 'windows',
  'FreeBSD'    => 'freebsd',
  'OpenBSD'    => 'openbsd',
  'NetBSD'     => 'netbsd'
}.freeze

ARCH_MAP = {
  'x86_64'  => 'x86_64',
  'amd64'   => 'x86_64',
  'aarch64' => 'aarch64',
  'arm64'   => 'aarch64'
}.freeze

# ── Expected failures registry ───────────────────────────────────────

EXPECTED_FAILURES = {
  'windows' => {
    'fork'    => 'Windows does not support fork()',
    'yjit'    => 'YJIT not yet supported on Windows',
    'signals' => 'Limited POSIX signal support on Windows'
  },
  'netbsd' => {
    'network' => 'Intermittent socket issues on NetBSD under emulation'
  }
}.freeze

# ── Status constants ─────────────────────────────────────────────────

module Status
  PASS          = 'pass'
  FAIL          = 'fail'
  EXPECTED_FAIL = 'expected_fail'
  WARN          = 'warn'
  SKIP          = 'skip'
  INFO          = 'info'
end

# ── CLI argument parsing ─────────────────────────────────────────────

class Options
  attr_accessor :json, :no_network, :strict, :verbose, :timeout, :retry_count

  def initialize
    @json = false
    @no_network = false
    @strict = false
    @verbose = false
    @timeout = nil
    @retry_count = nil
  end

  def self.parse(argv)
    opts = new
    i = 0
    while i < argv.length
      case argv[i]
      when '--json'
        opts.json = true
      when '--no-network'
        opts.no_network = true
      when '--strict'
        opts.strict = true
      when '--verbose'
        opts.verbose = true
      when '--timeout'
        i += 1
        val = argv[i]
        if val.nil? || val.start_with?('-')
          $stderr.puts "Error: --timeout requires a numeric argument"
          exit 3
        end
        opts.timeout = val.to_i
      when '--retry'
        i += 1
        val = argv[i]
        if val.nil? || val.start_with?('-')
          $stderr.puts "Error: --retry requires a numeric argument"
          exit 3
        end
        opts.retry_count = val.to_i
      when '--help', '-h'
        puts <<~HELP
          CosmoRuby Cross-Platform Diagnostic Test Suite

          Usage: ruby.com --disable-gems platform_diagnostic.rb [OPTIONS]

          Options:
            --json          Machine-parseable JSON output
            --no-network    Skip network-dependent tests
            --strict        Treat expected failures as actual failures
            --verbose       Detailed platform info on failure
            --timeout SECS  Override default timeout per test section
            --retry N       Override default retry count for flaky tests
            --help          Show this help
        HELP
        exit 0
      else
        $stderr.puts "Error: unknown option '#{argv[i]}'"
        exit 3
      end
      i += 1
    end
    opts
  end
end

# ── Main diagnostic class ────────────────────────────────────────────

class PlatformDiagnostic
  VERSION = '1.0'

  def initialize(options)
    @options = options
    @platform = detect_platform
    @arch = detect_arch
    @sections = {}
    @start_time = Time.now
  end

  # ── Platform helpers ──────────────────────────────────────────────

  def detect_platform
    sysname = begin
      Etc.uname[:sysname]
    rescue
      RUBY_PLATFORM
    end
    PLATFORM_MAP.each do |pattern, key|
      return key if sysname.to_s.start_with?(pattern)
    end
    'unknown'
  end

  def detect_arch
    machine = begin
      Etc.uname[:machine]
    rescue
      RbConfig::CONFIG['host_cpu']
    end
    ARCH_MAP.each do |pattern, key|
      return key if machine.to_s == pattern
    end
    'unknown'
  end

  def windows?
    @platform == 'windows'
  end

  def expected_failure?(section_key)
    failures = EXPECTED_FAILURES[@platform] || {}
    failures.key?(section_key)
  end

  def expected_failure_reason(section_key)
    failures = EXPECTED_FAILURES[@platform] || {}
    failures[section_key]
  end

  # ── Check recording ───────────────────────────────────────────────

  def record_check(section, name, status, value: nil, error: nil, retries: nil)
    @sections[section] ||= { status: Status::PASS, checks: [] }
    check = { name: name, status: status }
    check[:value] = value if value
    check[:error] = error if error
    check[:retries] = retries if retries

    @sections[section][:checks] << check

    # Promote section status: fail > expected_fail > warn > skip > info > pass
    priority = [Status::PASS, Status::INFO, Status::SKIP, Status::WARN,
                Status::EXPECTED_FAIL, Status::FAIL]
    current = priority.index(@sections[section][:status]) || 0
    new_pri = priority.index(status) || 0
    @sections[section][:status] = status if new_pri > current
  end

  # ── Output helpers ────────────────────────────────────────────────

  def status_tag(status)
    case status
    when Status::PASS          then '[PASS]'
    when Status::FAIL          then '[FAIL]'
    when Status::EXPECTED_FAIL then '[EXPECTED_FAIL]'
    when Status::WARN          then '[WARN]'
    when Status::SKIP          then '[SKIP]'
    when Status::INFO          then '[INFO]'
    else "[#{status.upcase}]"
    end
  end

  def print_check(section, name, status, detail = nil)
    return if @options.json
    tag = status_tag(status)
    line = "  #{tag} #{name}"
    line += " -- #{detail}" if detail
    puts line
  end

  def print_section_header(name)
    return if @options.json
    puts
    puts "== #{name} " + '=' * (70 - name.length)
  end

  # ── Test sections ─────────────────────────────────────────────────

  def test_identity
    section = 'identity'
    print_section_header('Identity')

    # RUBY_VERSION
    ver = RUBY_VERSION
    if ver && !ver.empty?
      record_check(section, 'ruby_version', Status::PASS, value: ver)
      print_check(section, 'ruby_version', Status::PASS, ver)
    else
      record_check(section, 'ruby_version', Status::FAIL, error: 'RUBY_VERSION is empty')
      print_check(section, 'ruby_version', Status::FAIL, 'empty')
    end

    # RUBY_ENGINE
    engine = defined?(RUBY_ENGINE) ? RUBY_ENGINE : nil
    if engine == 'ruby'
      record_check(section, 'ruby_engine', Status::PASS, value: engine)
      print_check(section, 'ruby_engine', Status::PASS, engine)
    else
      record_check(section, 'ruby_engine', Status::FAIL,
                   value: engine, error: "Expected 'ruby', got '#{engine}'")
      print_check(section, 'ruby_engine', Status::FAIL, engine.inspect)
    end

    # RUBY_PLATFORM
    plat = RUBY_PLATFORM
    if plat && !plat.empty?
      record_check(section, 'ruby_platform', Status::PASS, value: plat)
      print_check(section, 'ruby_platform', Status::PASS, plat)
    else
      record_check(section, 'ruby_platform', Status::FAIL, error: 'RUBY_PLATFORM is empty')
      print_check(section, 'ruby_platform', Status::FAIL, 'empty')
    end

    # Cosmopolitan-specific constants
    cosmo = defined?(Cosmo) ? true : false
    record_check(section, 'cosmo_constant', Status::INFO, value: cosmo.to_s)
    print_check(section, 'cosmo_constant', Status::INFO, "defined=#{cosmo}")
  end

  def test_platform
    section = 'platform'
    print_section_header('Platform Detection')

    # Etc.uname
    begin
      uname = Etc.uname
      sysname = uname[:sysname]
      release = uname[:release]
      machine = uname[:machine]

      record_check(section, 'uname_sysname', Status::PASS, value: sysname)
      print_check(section, 'uname_sysname', Status::PASS, sysname)

      record_check(section, 'uname_release', Status::PASS, value: release)
      print_check(section, 'uname_release', Status::PASS, release)

      record_check(section, 'uname_machine', Status::PASS, value: machine)
      print_check(section, 'uname_machine', Status::PASS, machine)
    rescue => e
      record_check(section, 'uname', Status::FAIL, error: e.message)
      print_check(section, 'uname', Status::FAIL, e.message)
    end

    # Architecture detection
    record_check(section, 'detected_arch', Status::INFO, value: @arch)
    print_check(section, 'detected_arch', Status::INFO, @arch)

    record_check(section, 'detected_platform', Status::INFO, value: @platform)
    print_check(section, 'detected_platform', Status::INFO, @platform)

    # Etc.nprocessors
    begin
      nproc = Etc.nprocessors
      if nproc > 0
        record_check(section, 'nprocessors', Status::PASS, value: nproc.to_s)
        print_check(section, 'nprocessors', Status::PASS, nproc.to_s)
      else
        record_check(section, 'nprocessors', Status::WARN, value: nproc.to_s,
                     error: 'nprocessors returned 0')
        print_check(section, 'nprocessors', Status::WARN, "#{nproc} (unexpected)")
      end
    rescue => e
      record_check(section, 'nprocessors', Status::WARN, error: e.message)
      print_check(section, 'nprocessors', Status::WARN, e.message)
    end

    # RbConfig host
    host = RbConfig::CONFIG['host']
    record_check(section, 'rbconfig_host', Status::INFO, value: host)
    print_check(section, 'rbconfig_host', Status::INFO, host)
  end

  def test_zip
    section = 'zip'
    print_section_header('ZIP Filesystem')

    # /zip/ exists
    if Dir.exist?('/zip')
      record_check(section, 'zip_exists', Status::PASS, value: 'true')
      print_check(section, 'zip_exists', Status::PASS)
    else
      record_check(section, 'zip_exists', Status::FAIL, error: '/zip directory not found')
      print_check(section, 'zip_exists', Status::FAIL, '/zip not found')
      return  # no point checking further
    end

    # Count stdlib files
    begin
      all_files = Dir['/zip/**/*'].select { |f| File.file?(f) }
      count = all_files.size
      if count > 100
        record_check(section, 'stdlib_count', Status::PASS,
                     value: count.to_s)
        print_check(section, 'stdlib_count', Status::PASS, "#{count} files")
      else
        record_check(section, 'stdlib_count', Status::FAIL,
                     value: count.to_s, error: "Expected >100 files, got #{count}")
        print_check(section, 'stdlib_count', Status::FAIL, "only #{count} files")
      end
    rescue => e
      record_check(section, 'stdlib_count', Status::FAIL, error: e.message)
      print_check(section, 'stdlib_count', Status::FAIL, e.message)
    end

    # Key files
    key_files = [
      '/zip/lib/ruby/4.0.0/rubygems.rb',
      '/zip/lib/ruby/4.0.0/bundler.rb',
      '/zip/lib/ruby/4.0.0/json.rb',
      '/zip/lib/ruby/4.0.0/yaml.rb',
      '/zip/lib/ruby/4.0.0/irb.rb',
      '/zip/bin/gem',
      '/zip/bin/irb',
      '/zip/bin/rake'
    ]

    key_files.each do |path|
      short = path.sub('/zip/', '')
      if File.exist?(path)
        record_check(section, "file_#{short}", Status::PASS, value: path)
        print_check(section, short, Status::PASS)
      else
        record_check(section, "file_#{short}", Status::WARN,
                     error: "#{path} not found")
        print_check(section, short, Status::WARN, 'not found')
      end
    end

    # Packaging marker
    marker = '/zip/.cosmo_ruby_packaged'
    if File.exist?(marker)
      record_check(section, 'packaging_marker', Status::PASS, value: marker)
      print_check(section, 'packaging_marker', Status::PASS)
    else
      record_check(section, 'packaging_marker', Status::WARN,
                   error: 'Packaging marker not found')
      print_check(section, 'packaging_marker', Status::WARN, 'not found')
    end
  end

  def test_extensions
    section = 'extensions'
    print_section_header('Extension Loading')

    extensions = {
      'stringio'  => -> { require 'stringio'; StringIO.new('test').read == 'test' },
      'pathname'  => -> { require 'pathname'; Pathname.new('/tmp').absolute? },
      'json'      => -> { require 'json'; JSON.generate({ a: 1 }) == '{"a":1}' },
      'zlib'      => -> { require 'zlib'; Zlib.crc32('test').is_a?(Integer) },
      'digest'    => -> { require 'digest'; Digest::SHA256.hexdigest('test').length == 64 },
      'date'      => -> { require 'date'; Date.today.is_a?(Date) },
      'monitor'   => -> { require 'monitor'; m = Monitor.new; m.synchronize { true } },
      'erb'       => -> { require 'erb'; ERB.new('<%= 1+1 %>').result == '2' },
      'set'       => -> { require 'set'; Set.new([1,2,3]).size == 3 },
      'tempfile'  => -> { require 'tempfile'; true },
      'open-uri'  => -> { require 'open-uri'; true },
      'uri'       => -> { require 'uri'; URI.parse('https://example.com').host == 'example.com' },
      'yaml'      => -> { require 'yaml'; YAML.dump({ a: 1 }) =~ /a:/ ? true : false },
      'psych'     => -> { require 'psych'; Psych.dump([1]).include?('1') },
      'io/console' => -> { require 'io/console'; defined?(IO::ConsoleMode) ? true : false }
    }

    extensions.each do |name, test_proc|
      begin
        result = test_proc.call
        if result
          record_check(section, name, Status::PASS)
          print_check(section, name, Status::PASS)
        else
          record_check(section, name, Status::FAIL,
                       error: "Loaded but functional test returned false")
          print_check(section, name, Status::FAIL, 'loaded but test failed')
        end
      rescue LoadError => e
        record_check(section, name, Status::FAIL, error: "LoadError: #{e.message}")
        print_check(section, name, Status::FAIL, "LoadError: #{e.message}")
      rescue => e
        record_check(section, name, Status::WARN,
                     error: "#{e.class}: #{e.message}")
        print_check(section, name, Status::WARN, "#{e.class}: #{e.message}")
      end
    end
  end

  def test_file_io
    section = 'file_io'
    print_section_header('File I/O')

    # Tempfile create/read/delete
    begin
      tf = Tempfile.new('cosmo_diag')
      tf.write("hello cosmo\n")
      tf.rewind
      content = tf.read
      path = tf.path
      tf.close
      tf.unlink

      if content == "hello cosmo\n"
        record_check(section, 'tempfile_rw', Status::PASS)
        print_check(section, 'tempfile_rw', Status::PASS)
      else
        record_check(section, 'tempfile_rw', Status::FAIL,
                     error: "Content mismatch: #{content.inspect}")
        print_check(section, 'tempfile_rw', Status::FAIL, 'content mismatch')
      end

      # Verify deletion
      if !File.exist?(path)
        record_check(section, 'tempfile_delete', Status::PASS)
        print_check(section, 'tempfile_delete', Status::PASS)
      else
        record_check(section, 'tempfile_delete', Status::WARN,
                     error: 'Tempfile still exists after unlink')
        print_check(section, 'tempfile_delete', Status::WARN, 'still exists after unlink')
      end
    rescue => e
      record_check(section, 'tempfile_rw', Status::FAIL, error: e.message)
      print_check(section, 'tempfile_rw', Status::FAIL, e.message)
    end

    # Directory operations
    begin
      dir = Dir.mktmpdir('cosmo_diag')
      sub = File.join(dir, 'subdir')
      Dir.mkdir(sub)
      exists = Dir.exist?(sub)
      FileUtils.rm_rf(dir)

      if exists
        record_check(section, 'directory_ops', Status::PASS)
        print_check(section, 'directory_ops', Status::PASS)
      else
        record_check(section, 'directory_ops', Status::FAIL,
                     error: 'mkdir succeeded but directory not found')
        print_check(section, 'directory_ops', Status::FAIL)
      end
    rescue => e
      record_check(section, 'directory_ops', Status::FAIL, error: e.message)
      print_check(section, 'directory_ops', Status::FAIL, e.message)
    end

    # Path expansion
    begin
      home = File.expand_path('~')
      if home && !home.empty? && home != '~'
        record_check(section, 'path_expand', Status::PASS, value: home)
        print_check(section, 'path_expand', Status::PASS, home)
      else
        record_check(section, 'path_expand', Status::WARN,
                     value: home, error: 'Home expansion returned unexpected value')
        print_check(section, 'path_expand', Status::WARN, home.inspect)
      end
    rescue => e
      record_check(section, 'path_expand', Status::WARN, error: e.message)
      print_check(section, 'path_expand', Status::WARN, e.message)
    end

    # File.realpath
    begin
      rp = File.realpath('.')
      if rp && !rp.empty?
        record_check(section, 'realpath', Status::PASS, value: rp)
        print_check(section, 'realpath', Status::PASS, rp)
      else
        record_check(section, 'realpath', Status::WARN, error: 'realpath returned empty')
        print_check(section, 'realpath', Status::WARN, 'empty')
      end
    rescue => e
      record_check(section, 'realpath', Status::WARN, error: e.message)
      print_check(section, 'realpath', Status::WARN, e.message)
    end
  end

  def test_encoding
    section = 'encoding'
    print_section_header('Encoding')

    # Default encoding
    enc = Encoding.default_external
    if enc == Encoding::UTF_8
      record_check(section, 'default_encoding', Status::PASS, value: enc.name)
      print_check(section, 'default_encoding', Status::PASS, enc.name)
    else
      record_check(section, 'default_encoding', Status::WARN,
                   value: enc.name, error: "Expected UTF-8, got #{enc.name}")
      print_check(section, 'default_encoding', Status::WARN, enc.name)
    end

    # String#encode
    begin
      s = "Hello"
      encoded = s.encode('UTF-16LE')
      back = encoded.encode('UTF-8')
      if back == s
        record_check(section, 'string_encode', Status::PASS)
        print_check(section, 'string_encode', Status::PASS)
      else
        record_check(section, 'string_encode', Status::FAIL,
                     error: 'Round-trip encoding failed')
        print_check(section, 'string_encode', Status::FAIL, 'round-trip failed')
      end
    rescue => e
      record_check(section, 'string_encode', Status::FAIL, error: e.message)
      print_check(section, 'string_encode', Status::FAIL, e.message)
    end

    # Unicode operations
    begin
      s = "\u{1F600}"  # grinning face emoji
      if s.length == 1 && s.bytesize == 4 && s.encoding == Encoding::UTF_8
        record_check(section, 'unicode_ops', Status::PASS,
                     value: "length=#{s.length} bytesize=#{s.bytesize}")
        print_check(section, 'unicode_ops', Status::PASS)
      else
        record_check(section, 'unicode_ops', Status::FAIL,
                     error: "length=#{s.length} bytesize=#{s.bytesize} enc=#{s.encoding}")
        print_check(section, 'unicode_ops', Status::FAIL)
      end
    rescue => e
      record_check(section, 'unicode_ops', Status::FAIL, error: e.message)
      print_check(section, 'unicode_ops', Status::FAIL, e.message)
    end
  end

  def test_signals
    section = 'signals'
    print_section_header('Signals')

    if windows?
      if expected_failure?(section)
        reason = expected_failure_reason(section)
        record_check(section, 'signals', Status::EXPECTED_FAIL, error: reason)
        print_check(section, 'signals', Status::EXPECTED_FAIL, reason)
      else
        record_check(section, 'signals', Status::SKIP, error: 'Windows platform')
        print_check(section, 'signals', Status::SKIP, 'Windows')
      end
      return
    end

    # SIGINT handler
    begin
      old = Signal.trap('INT') { }
      Signal.trap('INT', old || 'DEFAULT')
      record_check(section, 'sigint_handler', Status::PASS)
      print_check(section, 'sigint_handler', Status::PASS)
    rescue => e
      record_check(section, 'sigint_handler', Status::WARN, error: e.message)
      print_check(section, 'sigint_handler', Status::WARN, e.message)
    end

    # SIGTERM handler
    begin
      old = Signal.trap('TERM') { }
      Signal.trap('TERM', old || 'DEFAULT')
      record_check(section, 'sigterm_handler', Status::PASS)
      print_check(section, 'sigterm_handler', Status::PASS)
    rescue => e
      record_check(section, 'sigterm_handler', Status::WARN, error: e.message)
      print_check(section, 'sigterm_handler', Status::WARN, e.message)
    end

    # Signal.list
    begin
      sigs = Signal.list
      if sigs.is_a?(Hash) && sigs.size > 0
        record_check(section, 'signal_list', Status::PASS,
                     value: "#{sigs.size} signals")
        print_check(section, 'signal_list', Status::PASS, "#{sigs.size} signals")
      else
        record_check(section, 'signal_list', Status::WARN, error: 'Signal.list empty')
        print_check(section, 'signal_list', Status::WARN, 'empty')
      end
    rescue => e
      record_check(section, 'signal_list', Status::WARN, error: e.message)
      print_check(section, 'signal_list', Status::WARN, e.message)
    end
  end

  def test_process
    section = 'process'
    print_section_header('Process & Threading')

    # PID
    begin
      pid = Process.pid
      if pid > 0
        record_check(section, 'pid', Status::PASS, value: pid.to_s)
        print_check(section, 'pid', Status::PASS, pid.to_s)
      else
        record_check(section, 'pid', Status::FAIL, value: pid.to_s,
                     error: 'PID should be positive')
        print_check(section, 'pid', Status::FAIL, pid.to_s)
      end
    rescue => e
      record_check(section, 'pid', Status::FAIL, error: e.message)
      print_check(section, 'pid', Status::FAIL, e.message)
    end

    # ENV
    begin
      path = ENV['PATH']
      if path && !path.empty?
        record_check(section, 'env_path', Status::PASS,
                     value: "#{path.length} chars")
        print_check(section, 'env_path', Status::PASS, "#{path.length} chars")
      else
        record_check(section, 'env_path', Status::WARN, error: 'PATH is empty or nil')
        print_check(section, 'env_path', Status::WARN, 'empty or nil')
      end
    rescue => e
      record_check(section, 'env_path', Status::WARN, error: e.message)
      print_check(section, 'env_path', Status::WARN, e.message)
    end

    # Thread.new
    begin
      result = nil
      t = Thread.new { result = 42 }
      t.join(5)
      if result == 42
        record_check(section, 'thread', Status::PASS)
        print_check(section, 'thread', Status::PASS)
      else
        record_check(section, 'thread', Status::FAIL,
                     error: "Thread returned #{result.inspect}")
        print_check(section, 'thread', Status::FAIL, result.inspect)
      end
    rescue => e
      record_check(section, 'thread', Status::FAIL, error: e.message)
      print_check(section, 'thread', Status::FAIL, e.message)
    end

    # Mutex
    begin
      m = Mutex.new
      m.synchronize { true }
      record_check(section, 'mutex', Status::PASS)
      print_check(section, 'mutex', Status::PASS)
    rescue => e
      record_check(section, 'mutex', Status::FAIL, error: e.message)
      print_check(section, 'mutex', Status::FAIL, e.message)
    end

    # fork (skip on Windows)
    if windows?
      if expected_failure?('fork')
        reason = expected_failure_reason('fork')
        record_check(section, 'fork', Status::EXPECTED_FAIL, error: reason)
        print_check(section, 'fork', Status::EXPECTED_FAIL, reason)
      else
        record_check(section, 'fork', Status::SKIP, error: 'Windows platform')
        print_check(section, 'fork', Status::SKIP, 'Windows')
      end
    else
      begin
        rd, wr = IO.pipe
        pid = Process.fork do
          rd.close
          wr.write('ok')
          wr.close
        end
        wr.close
        data = rd.read
        rd.close
        Process.waitpid(pid)

        if data == 'ok'
          record_check(section, 'fork', Status::PASS)
          print_check(section, 'fork', Status::PASS)
        else
          record_check(section, 'fork', Status::FAIL,
                       error: "fork child sent #{data.inspect}")
          print_check(section, 'fork', Status::FAIL, data.inspect)
        end
      rescue NotImplementedError => e
        record_check(section, 'fork', Status::SKIP, error: e.message)
        print_check(section, 'fork', Status::SKIP, e.message)
      rescue => e
        record_check(section, 'fork', Status::FAIL, error: e.message)
        print_check(section, 'fork', Status::FAIL, e.message)
      end
    end
  end

  def test_network
    section = 'network'
    print_section_header('Network')

    if @options.no_network
      record_check(section, 'network', Status::SKIP, error: '--no-network flag')
      print_check(section, 'network', Status::SKIP, 'skipped (--no-network)')
      return
    end

    require 'socket'

    # Socket.gethostname
    begin
      hostname = Socket.gethostname
      if hostname && !hostname.empty?
        record_check(section, 'gethostname', Status::PASS, value: hostname)
        print_check(section, 'gethostname', Status::PASS, hostname)
      else
        record_check(section, 'gethostname', Status::WARN,
                     error: 'gethostname returned empty')
        print_check(section, 'gethostname', Status::WARN, 'empty')
      end
    rescue => e
      record_check(section, 'gethostname', Status::WARN, error: e.message)
      print_check(section, 'gethostname', Status::WARN, e.message)
    end

    # Ephemeral TCPServer with retry
    max_retries = @options.retry_count || 3
    retry_delay = 5
    attempt = 0
    tcp_pass = false

    while attempt < max_retries && !tcp_pass
      attempt += 1
      begin
        server = TCPServer.new('127.0.0.1', 0)
        port = server.addr[1]
        server.close

        if port > 0
          tcp_pass = true
          record_check(section, 'tcp_server', Status::PASS,
                       value: "port=#{port}", retries: attempt)
          print_check(section, 'tcp_server', Status::PASS,
                      "port=#{port} (attempt #{attempt})")
        end
      rescue => e
        if attempt < max_retries
          sleep(retry_delay) unless @options.json
        else
          record_check(section, 'tcp_server', Status::WARN,
                       error: e.message, retries: attempt)
          print_check(section, 'tcp_server', Status::WARN,
                      "#{e.message} (#{attempt} attempts)")
        end
      end
    end
  end

  def test_gems
    section = 'gems'
    print_section_header('Gems')

    # require rubygems
    begin
      require 'rubygems'
      record_check(section, 'rubygems', Status::PASS,
                   value: Gem::VERSION)
      print_check(section, 'rubygems', Status::PASS, "v#{Gem::VERSION}")
    rescue LoadError => e
      record_check(section, 'rubygems', Status::WARN, error: e.message)
      print_check(section, 'rubygems', Status::WARN, e.message)
    rescue => e
      record_check(section, 'rubygems', Status::WARN, error: e.message)
      print_check(section, 'rubygems', Status::WARN, e.message)
    end

    # require bundler
    begin
      require 'bundler'
      ver = defined?(Bundler::VERSION) ? Bundler::VERSION : 'unknown'
      record_check(section, 'bundler', Status::PASS, value: ver)
      print_check(section, 'bundler', Status::PASS, "v#{ver}")
    rescue LoadError => e
      record_check(section, 'bundler', Status::WARN, error: e.message)
      print_check(section, 'bundler', Status::WARN, e.message)
    rescue => e
      record_check(section, 'bundler', Status::WARN, error: e.message)
      print_check(section, 'bundler', Status::WARN, e.message)
    end
  end

  def test_yjit
    section = 'yjit'
    print_section_header('YJIT')

    begin
      if defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enabled?)
        enabled = RubyVM::YJIT.enabled?
        if windows? && !enabled
          if expected_failure?(section)
            reason = expected_failure_reason(section)
            record_check(section, 'yjit_enabled', Status::EXPECTED_FAIL,
                         value: 'false', error: reason)
            print_check(section, 'yjit_enabled', Status::EXPECTED_FAIL, reason)
          else
            record_check(section, 'yjit_enabled', Status::INFO,
                         value: 'false', error: 'YJIT disabled on Windows (expected)')
            print_check(section, 'yjit_enabled', Status::INFO,
                        'disabled on Windows (expected)')
          end
        else
          record_check(section, 'yjit_enabled', Status::INFO,
                       value: enabled.to_s)
          print_check(section, 'yjit_enabled', Status::INFO, enabled.to_s)
        end
      else
        record_check(section, 'yjit_available', Status::INFO,
                     value: 'false', error: 'RubyVM::YJIT not defined')
        print_check(section, 'yjit_available', Status::INFO, 'not available')
      end
    rescue => e
      record_check(section, 'yjit', Status::INFO, error: e.message)
      print_check(section, 'yjit', Status::INFO, e.message)
    end
  end

  def test_resources
    section = 'resources'
    print_section_header('Resources')

    # Memory info (via GC stats)
    begin
      gc = GC.stat
      heap_pages = gc[:heap_allocated_pages] || gc[:heap_live_slots]
      record_check(section, 'gc_stats', Status::PASS,
                   value: "heap_pages=#{heap_pages}")
      print_check(section, 'gc_stats', Status::PASS, "heap_pages=#{heap_pages}")
    rescue => e
      record_check(section, 'gc_stats', Status::WARN, error: e.message)
      print_check(section, 'gc_stats', Status::WARN, e.message)
    end

    # Object space
    begin
      count = ObjectSpace.count_objects[:TOTAL]
      record_check(section, 'object_count', Status::PASS, value: count.to_s)
      print_check(section, 'object_count', Status::PASS, "#{count} objects")
    rescue => e
      record_check(section, 'object_count', Status::WARN, error: e.message)
      print_check(section, 'object_count', Status::WARN, e.message)
    end

    # Process memory (RSS via /proc if available)
    begin
      if File.exist?('/proc/self/status')
        status = File.read('/proc/self/status')
        if status =~ /VmRSS:\s+(\d+)\s+kB/
          rss_kb = $1.to_i
          record_check(section, 'memory_rss', Status::PASS,
                       value: "#{rss_kb} kB")
          print_check(section, 'memory_rss', Status::PASS, "#{rss_kb} kB")
        end
      else
        record_check(section, 'memory_rss', Status::SKIP,
                     error: '/proc not available')
        print_check(section, 'memory_rss', Status::SKIP, '/proc not available')
      end
    rescue => e
      record_check(section, 'memory_rss', Status::SKIP, error: e.message)
      print_check(section, 'memory_rss', Status::SKIP, e.message)
    end
  end

  # ── Run all tests ─────────────────────────────────────────────────

  def run
    unless @options.json
      puts "CosmoRuby Cross-Platform Diagnostic v#{VERSION}"
      puts '=' * 72
      puts "Platform: #{@platform}/#{@arch}"
      puts "Ruby:     #{RUBY_VERSION} (#{RUBY_ENGINE})"
      puts "Binary:   #{RbConfig.ruby}"
      puts "Time:     #{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S+00:00')}"
      puts '=' * 72
    end

    test_identity
    test_platform
    test_zip
    test_extensions
    test_file_io
    test_encoding
    test_signals
    test_process
    test_network
    test_gems
    test_yjit
    test_resources

    duration = Time.now - @start_time
    summary = compute_summary(duration)

    if @options.json
      output_json(summary, duration)
    else
      output_human(summary, duration)
    end

    # Verbose output on failure
    if @options.verbose && summary[:fail] > 0
      output_verbose_debug
    end

    summary[:exit_code]
  end

  # ── Summary computation ───────────────────────────────────────────

  def compute_summary(duration)
    total = 0
    pass = 0
    fail = 0
    expected_fail = 0
    warn = 0
    skip = 0

    @sections.each_value do |sec|
      sec[:checks].each do |check|
        total += 1
        case check[:status]
        when Status::PASS          then pass += 1
        when Status::FAIL          then fail += 1
        when Status::EXPECTED_FAIL then expected_fail += 1
        when Status::WARN          then warn += 1
        when Status::SKIP          then skip += 1
        # INFO counts towards total but not any category
        end
      end
    end

    # In strict mode, expected failures count as failures
    if @options.strict
      fail += expected_fail
      expected_fail = 0
    end

    verdict = fail > 0 ? 'FAIL' : 'PASS'
    exit_code = fail > 0 ? 1 : 0

    {
      total: total, pass: pass, fail: fail,
      expected_fail: expected_fail, warn: warn, skip: skip,
      verdict: verdict, exit_code: exit_code,
      duration_seconds: duration.round(1)
    }
  end

  # ── JSON output ───────────────────────────────────────────────────

  def output_json(summary, duration)
    # Build JSON manually to avoid requiring json gem before testing it
    require 'json'

    uname_data = begin
      u = Etc.uname
      { sysname: u[:sysname], release: u[:release], machine: u[:machine] }
    rescue
      { sysname: 'unknown', release: 'unknown', machine: 'unknown' }
    end

    result = {
      version: VERSION,
      timestamp: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S+00:00'),
      binary: RbConfig.ruby,
      ruby_version: RUBY_VERSION,
      platform: {
        os: @platform,
        arch: @arch,
        sysname: uname_data[:sysname],
        release: uname_data[:release],
        machine: uname_data[:machine]
      },
      sections: {},
      summary: summary
    }

    @sections.each do |name, sec|
      result[:sections][name] = {
        status: sec[:status],
        checks: sec[:checks]
      }
    end

    puts JSON.pretty_generate(result)
  end

  # ── Human-readable output ─────────────────────────────────────────

  def output_human(summary, duration)
    puts
    puts '=' * 72
    puts 'SUMMARY'
    puts '=' * 72
    puts "  Total:         #{summary[:total]}"
    puts "  Pass:          #{summary[:pass]}"
    puts "  Fail:          #{summary[:fail]}"
    puts "  Expected Fail: #{summary[:expected_fail]}"
    puts "  Warn:          #{summary[:warn]}"
    puts "  Skip:          #{summary[:skip]}"
    puts "  Duration:      #{summary[:duration_seconds]}s"
    puts
    puts "  Verdict: #{summary[:verdict]}"
    puts '=' * 72
  end

  # ── Verbose debug output ──────────────────────────────────────────

  def output_verbose_debug
    puts
    puts '== Verbose Debug Info ' + '=' * 50
    puts
    puts "RbConfig::CONFIG:"
    %w[host host_cpu host_os DLEXT EXTSTATIC target_cpu].each do |key|
      val = RbConfig::CONFIG[key]
      puts "  #{key} = #{val}" if val
    end
    puts
    puts "Key ENV variables:"
    %w[PATH HOME RUBYLIB RUBYOPT GEM_HOME GEM_PATH LANG LC_ALL].each do |key|
      val = ENV[key]
      puts "  #{key} = #{val}" if val
    end
    puts
    puts "Loaded features: #{$LOADED_FEATURES.size}"
    puts '=' * 72
  end
end

# ── Main ──────────────────────────────────────────────────────────────

if __FILE__ == $0
  begin
    options = Options.parse(ARGV)
    diag = PlatformDiagnostic.new(options)
    exit_code = diag.run
    exit(exit_code)
  rescue SystemExit => e
    raise  # re-raise explicit exits
  rescue => e
    $stderr.puts "FATAL: #{e.class}: #{e.message}"
    $stderr.puts e.backtrace.first(10).join("\n") if e.backtrace
    exit 2
  end
end
