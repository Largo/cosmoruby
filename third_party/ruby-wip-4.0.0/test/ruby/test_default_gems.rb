# frozen_string_literal: false
require 'rubygems'

class TestDefaultGems < Test::Unit::TestCase
  def self.load(file)
    code = File.read(file, mode: "r:UTF-8:-", &:read)

    # These regex patterns are from load_gemspec method of rbinstall.rb.
    # - `git ls-files` is useless under ruby's repository
    # - `2>/dev/null` works only on Unix-like platforms
    code.gsub!(/(?:`git[^\`]*`|%x\[git[^\]]*\])\.split\([^\)]*\)/m, '[]')
    code.gsub!(/IO\.popen\(.*git.*?\)/, '[] || itself')

    # Dir.chdir doesn't work with /zip/ virtual filesystem in Cosmopolitan.
    # Replace `Dir.chdir(...) do` with `begin` so the block executes in place.
    # The git commands inside are already patched to [], so spec.files = [].
    # Use greedy .* to handle nested parens like Dir.chdir(File.expand_path('..', __FILE__))
    code.gsub!(/Dir\.chdir\(.*\)\s+do\b/, 'begin')

    eval(code, binding, file)
  end

  def test_validate_gemspec
    # When running packaged Cosmopolitan Ruby (ruby.com), load gemspecs from /zip/
    # to avoid double-loading version.rb from both /zip/ and filesystem.
    if defined?(RUBY_COSMO_PACKAGED) && RUBY_COSMO_PACKAGED
      srcdir = "/zip/lib/ruby/#{RUBY_VERSION.sub(/\.\d+$/, '.0')}"
      glob_pattern = "#{srcdir}/**/*.gemspec"
      # Dir.chdir doesn't work with /zip/ virtual filesystem, use absolute paths
      specs = 0
      all_assertions_foreach(nil, *Dir[glob_pattern]) do |src|
        specs += 1
        assert_kind_of(Gem::Specification, self.class.load(src), "invalid spec in #{src}")
      end
      assert_operator specs, :>, 0, "gemspecs not found"
    else
      srcdir = File.expand_path('../../..', __FILE__)
      glob_pattern = "{lib,ext}/**/*.gemspec"
      specs = 0
      Dir.chdir(srcdir) do
        all_assertions_foreach(nil, *Dir[glob_pattern]) do |src|
          specs += 1
          assert_kind_of(Gem::Specification, self.class.load(src), "invalid spec in #{src}")
        end
      end
      assert_operator specs, :>, 0, "gemspecs not found"
    end
  end

end
