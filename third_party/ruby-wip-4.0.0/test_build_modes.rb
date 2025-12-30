#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive test suite for CosmoRuby build modes
# Tests $LOADED_FEATURES, ZIP filesystem, extension loading, and build mode expectations

require 'rbconfig'

class BuildModeTest
  attr_reader :results, :errors

  def initialize
    @results = {}
    @errors = []

    # Read actual config values
    @dlext = RbConfig::CONFIG['DLEXT']
    @extstatic = RbConfig::CONFIG['EXTSTATIC']
    @slim_static = RbConfig::CONFIG['SLIM_STATIC']

    detect_build_mode
  end

  def detect_build_mode
    # Determine mode from actual config values, not filesystem inspection
    # RbConfig uses "no"/"yes" strings, not "0"/"1"
    if @extstatic == '0' || @extstatic == 'no'
      @mode = :dynamic
      @mode_name = "Dynamic (plugin mode)"
      @expected_dlext = 'a'  # Without dot
    elsif @extstatic == '1' || @extstatic == 'yes'
      if @slim_static == '1' || @slim_static == 'yes'
        @mode = :static_slim
        @mode_name = "Static Slim (zero-byte stubs)"
        @expected_dlext = 'so'  # Without dot
      else
        @mode = :static_bare
        @mode_name = "Static Bare (no stubs)"
        @expected_dlext = 'so'  # Without dot
      end
    else
      @mode = :unknown
      @mode_name = "Unknown"
      @expected_dlext = nil
    end

    @results[:mode] = @mode
    @results[:mode_name] = @mode_name
    @results[:dlext] = @dlext
    @results[:expected_dlext] = @expected_dlext
    @results[:extstatic] = @extstatic
    @results[:slim_static] = @slim_static
  end

  def run_all_tests
    puts "=" * 80
    puts "CosmoRuby Build Mode Test Suite"
    puts "=" * 80
    puts "Build Mode: #{@mode_name}"
    puts "Config Values:"
    puts "  DLEXT: #{@dlext} (expected: #{@expected_dlext})"
    puts "  EXTSTATIC: #{@extstatic}"
    puts "  SLIM_STATIC: #{@slim_static}"
    puts "=" * 80
    puts

    # Validate config consistency first
    test_config_consistency

    test_loaded_features
    test_zip_filesystem
    test_extension_functionality
    test_build_mode_expectations

    print_summary
  end

  def test_config_consistency
    puts "TEST: Config consistency"
    puts "-" * 80

    # Check DLEXT matches expectations
    if @expected_dlext && @dlext != @expected_dlext
      puts "❌ DLEXT mismatch: got '#{@dlext}', expected '#{@expected_dlext}'"
      @errors << "DLEXT mismatch for #{@mode_name}"
    else
      puts "✅ DLEXT is correct for mode"
    end

    # Check EXTSTATIC/SLIM_STATIC consistency
    if @extstatic == '0' && @slim_static != '0' && @slim_static != 'no'
      puts "⚠️  SLIM_STATIC is '#{@slim_static}' but EXTSTATIC=0 (dynamic mode doesn't use SLIM_STATIC)"
    end

    puts
  end

  def test_loaded_features
    puts "TEST: $LOADED_FEATURES validation"
    puts "-" * 80

    features = $LOADED_FEATURES.dup
    @results[:total_features] = features.size

    # Check for duplicates
    duplicates = features.group_by { |f| f }.select { |_, v| v.size > 1 }.keys
    @results[:duplicates] = duplicates

    if duplicates.empty?
      puts "✅ No duplicate entries in $LOADED_FEATURES"
    else
      puts "❌ DUPLICATES found in $LOADED_FEATURES:"
      duplicates.each { |dup| puts "   - #{dup}" }
      @errors << "Duplicate entries in $LOADED_FEATURES"
    end

    # Categorize features
    built_ins = features.select { |f| f =~ /^[^\/]+\.so$/ && !f.include?('/') }
    extensions_with_paths = features.select { |f| f =~ /\.(a|so)$/ && f.include?('/') }
    extensions_short = features.select { |f|
      f =~ /\.(a|so)$/ && !f.include?('/') && !f.match?(/^(enumerator|fiber|thread|rational|complex)\.so$/)
    }
    ruby_files = features.select { |f| f =~ /\.rb$/ }

    @results[:built_ins] = built_ins
    @results[:extensions_with_paths] = extensions_with_paths
    @results[:extensions_short] = extensions_short
    @results[:ruby_files] = ruby_files

    puts "📊 Feature breakdown:"
    puts "   Built-ins (.so, short): #{built_ins.size} (e.g., #{built_ins.first(3).join(', ')})"
    puts "   Extensions (full path): #{extensions_with_paths.size}"
    puts "   Extensions (short name): #{extensions_short.size}"
    if extensions_short.any?
      puts "     Examples: #{extensions_short.first(5).join(', ')}"
    end
    puts "   Ruby files: #{ruby_files.size}"

    # Check for double registration (short name + full path for same extension)
    extension_basenames = extensions_with_paths.map { |e| File.basename(e) }
    double_registered = extensions_short.select { |short|
      extension_basenames.include?(short)
    }

    if double_registered.empty?
      puts "✅ No extensions appearing as BOTH short name and full path"
    else
      puts "❌ Extensions with DOUBLE REGISTRATION (short + full path):"
      double_registered.each do |short|
        full_paths = extensions_with_paths.select { |e| File.basename(e) == short }
        puts "   - #{short}"
        full_paths.each { |fp| puts "     AND #{fp}" }
        @errors << "Double registration: #{short}"
      end
    end

    # Mode-specific expectations for $LOADED_FEATURES
    case @mode
    when :dynamic
      if extensions_short.any?
        puts "⚠️  Found #{extensions_short.size} extensions with short names (dynamic mode should use full paths)"
        # Note: Some extensions like ripper might load early with short names, this might be OK
        puts "     Extensions: #{extensions_short.join(', ')}"
      end
    when :static_slim, :static_bare
      if extensions_with_paths.any?
        puts "⚠️  Found #{extensions_with_paths.size} extensions with full paths (static mode should use short names)"
        puts "     Extensions: #{extensions_with_paths.map { |e| File.basename(e) }.join(', ')}"
      end
    end

    puts
  end

  def test_zip_filesystem
    puts "TEST: ZIP filesystem structure"
    puts "-" * 80

    if !Dir.exist?('/zip')
      puts "ℹ️  No /zip filesystem"
      @results[:has_zip] = false

      # Validate against expectations
      if @mode == :static_bare
        puts "✅ Expected for static bare mode"
      else
        puts "⚠️  Unexpected: #{@mode_name} should have /zip filesystem"
      end

      puts
      return
    end

    @results[:has_zip] = true
    puts "✅ /zip filesystem exists"

    # Check for extension files
    ext_dir = '/zip/lib/ruby/3.4.0/extensions'
    if !Dir.exist?(ext_dir)
      puts "ℹ️  No extensions directory in /zip"
      @results[:has_extensions_dir] = false

      # Validate against expectations
      if @mode == :static_bare
        puts "✅ Expected for static bare mode"
      elsif @mode == :dynamic
        puts "❌ Dynamic mode should have extensions directory"
        @errors << "Missing extensions directory in dynamic mode"
      end

      puts
      return
    end

    @results[:has_extensions_dir] = true
    puts "✅ Extensions directory exists: #{ext_dir}"

    # Analyze extension files
    ext_files = Dir["#{ext_dir}/**/*.{a,so}"]
    @results[:extension_files] = ext_files

    zero_byte_files = []
    actual_files = []

    ext_files.each do |file|
      size = File.size(file) rescue -1
      if size == 0
        zero_byte_files << file
      elsif size > 0
        actual_files << [file, size]
      end
    end

    @results[:zero_byte_stubs] = zero_byte_files
    @results[:actual_extension_files] = actual_files.map(&:first)

    puts
    puts "📁 Extension files in /zip:"
    puts "   Total files: #{ext_files.size}"
    puts "   Zero-byte stubs: #{zero_byte_files.size}"
    puts "   Actual files: #{actual_files.size}"

    if zero_byte_files.any?
      puts
      puts "   Zero-byte stubs:"
      zero_byte_files.sort.each { |f| puts "     - #{f.sub('/zip/lib/ruby/3.4.0/extensions/', '')}" }
    end

    if actual_files.any?
      puts
      puts "   Actual files (size > 0):"
      actual_files.sort_by { |_, size| -size }.each do |f, size|
        kb = size / 1024.0
        puts "     - #{f.sub('/zip/lib/ruby/3.4.0/extensions/', '')} (#{kb.round(1)} KB)"
      end
    end

    # Validate against mode expectations
    puts
    case @mode
    when :dynamic
      if actual_files.empty?
        puts "❌ Dynamic mode should have actual .a files"
        @errors << "Missing actual extension files in dynamic mode"
      else
        puts "✅ Found actual extension files (expected for dynamic mode)"
      end

      if zero_byte_files.any?
        puts "❌ Dynamic mode should NOT have zero-byte stubs"
        @errors << "Unexpected zero-byte stubs in dynamic mode"
      else
        puts "✅ No zero-byte stubs (expected for dynamic mode)"
      end

    when :static_slim
      if zero_byte_files.empty?
        puts "❌ Static slim mode should have zero-byte stubs"
        @errors << "Missing zero-byte stubs in static slim mode"
      else
        puts "✅ Found zero-byte stubs (expected for static slim mode)"
      end

      if actual_files.any?
        puts "❌ Static slim mode should NOT have actual files (only stubs)"
        @errors << "Unexpected actual files in static slim mode"
      else
        puts "✅ No actual extension files (expected for static slim mode)"
      end

    when :static_bare
      if ext_files.any?
        puts "⚠️  Static bare mode has extension files (expected none)"
      end
    end

    puts
  end

  def test_extension_functionality
    puts "TEST: Extension functionality"
    puts "-" * 80

    # Test that key extensions actually work (not just registered)
    tests = {
      'monitor' => -> {
        require 'monitor'
        m = Monitor.new
        result = m.synchronize { "works" }
        result == "works"
      },
      'pathname' => -> {
        require 'pathname'
        p = Pathname.new('/tmp')
        p.to_s == '/tmp' && p.absolute?
      },
      'stringio' => -> {
        require 'stringio'
        io = StringIO.new("test")
        io.read == "test"
      },
      'io/console' => -> {
        require 'io/console'
        # Just check the module loaded, don't try to use STDIN
        defined?(IO::ConsoleMode)
      }
    }

    @results[:extension_tests] = {}

    tests.each do |name, test|
      begin
        result = test.call
        @results[:extension_tests][name] = result
        if result
          puts "✅ #{name}: functional and verified"
        else
          puts "❌ #{name}: loaded but test failed"
          @errors << "Extension #{name} test returned false"
        end
      rescue => e
        @results[:extension_tests][name] = false
        puts "❌ #{name}: FAILED (#{e.class}: #{e.message})"
        @errors << "Extension #{name} not functional: #{e.message}"
      end
    end

    puts
  end

  def test_build_mode_expectations
    puts "TEST: Build mode expectations summary"
    puts "-" * 80

    case @mode
    when :dynamic
      test_dynamic_mode_expectations
    when :static_slim
      test_static_slim_expectations
    when :static_bare
      test_static_bare_expectations
    else
      puts "⚠️  Unknown build mode, skipping expectations"
    end

    puts
  end

  def test_dynamic_mode_expectations
    puts "DYNAMIC MODE expectations:"
    puts "  ✓ EXTSTATIC=0, DLEXT='.a'"
    puts "  ✓ Extensions loaded via cosmo_plugin from /zip"
    puts "  ✓ Actual .a files in /zip/lib/ruby/3.4.0/extensions/"
    puts "  ✓ Extensions appear with full paths in $LOADED_FEATURES"
    puts "  ✓ No zero-byte stubs"
    puts "  ✓ No double registration (short + full path)"
    puts

    # All validations done in previous tests, just summary here
    issues = @errors.select { |e|
      e.include?('dynamic') || e.include?('DLEXT') || e.include?('Double registration')
    }

    if issues.empty?
      puts "✅ Dynamic mode behaving as expected"
    else
      puts "❌ Dynamic mode issues detected (see errors above)"
    end
  end

  def test_static_slim_expectations
    puts "STATIC SLIM MODE expectations:"
    puts "  ✓ EXTSTATIC=1, SLIM_STATIC=1, DLEXT='.so'"
    puts "  ✓ Extensions pre-initialized (baked into binary)"
    puts "  ✓ Zero-byte .so stubs in /zip/lib/ruby/3.4.0/extensions/"
    puts "  ✓ Extensions appear with short names in $LOADED_FEATURES"
    puts "  ✓ No actual extension files in /zip (only stubs)"
    puts

    issues = @errors.select { |e|
      e.include?('slim') || e.include?('stub') || e.include?('DLEXT')
    }

    if issues.empty?
      puts "✅ Static slim mode behaving as expected"
    else
      puts "❌ Static slim mode issues detected (see errors above)"
    end
  end

  def test_static_bare_expectations
    puts "STATIC BARE MODE expectations:"
    puts "  ✓ EXTSTATIC=1, SLIM_STATIC=0, DLEXT='.so'"
    puts "  ✓ Extensions pre-initialized (baked into binary)"
    puts "  ✓ NO extension files in /zip at all"
    puts "  ✓ Extensions appear with short names in $LOADED_FEATURES"
    puts

    issues = @errors.select { |e|
      e.include?('bare') || e.include?('DLEXT')
    }

    if issues.empty?
      puts "✅ Static bare mode behaving as expected"
    else
      puts "❌ Static bare mode issues detected (see errors above)"
    end
  end

  def print_summary
    puts "=" * 80
    puts "TEST SUMMARY"
    puts "=" * 80
    puts "Build Mode: #{@mode_name}"
    puts "Total Features Loaded: #{@results[:total_features]}"
    puts "Extensions Tested: #{@results[:extension_tests]&.size || 0}"
    puts "=" * 80

    if @errors.empty?
      puts "✅ ALL TESTS PASSED"
      puts
      puts "No errors detected. Build is behaving as expected."
      exit 0
    else
      puts "❌ TESTS FAILED"
      puts
      puts "Errors detected: #{@errors.size}"
      puts
      @errors.each_with_index do |error, i|
        puts "   #{i + 1}. #{error}"
      end
      puts
      puts "Please review the detailed output above for more information."
      exit 1
    end
  end
end

# Run tests if executed directly
if __FILE__ == $0
  tester = BuildModeTest.new
  tester.run_all_tests
end
