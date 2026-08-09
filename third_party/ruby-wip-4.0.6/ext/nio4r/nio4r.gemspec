# frozen_string_literal: true
#
# Static gemspec for the nio4r gem as vendored into CosmoRuby.
#
# assemble_stdlib.sh scans third_party/ruby/{lib,ext} for *.gemspec files and
# installs each as a *default gem* specification under
# /zip/lib/ruby/gems/4.0.0/specifications/default/, which is what makes
# `gem list`, Bundler and ocran's payload-provides-gem check see nio4r as
# provided by the interpreter.  puma declares `nio4r ~> 2.0`, so this spec is
# what stops RubyGems trying to install nio4r inside a packaged app.
#
# NOTE: no `extensions` -- upstream lists ext/nio4r/extconf.rb, but the native
# part (nio4r_ext, with libev's poll backend) is already linked into ruby.com.

version = File.foreach(File.join(__dir__, "lib/nio/version.rb")) do |line|
  /^\s*VERSION\s*=\s*"(.*)"/ =~ line and break $1
end rescue nil
version ||= "2.7.5"

Gem::Specification.new do |s|
  s.name = "nio4r"
  s.version = version

  s.summary = "New IO for Ruby"
  s.description = "NIO provides a high performance selector API for monitoring IO objects. " \
                  "Vendored into CosmoRuby; libev is built with its poll(2) backend, the " \
                  "only one Cosmopolitan supports on every target OS."
  s.homepage = "https://github.com/socketry/nio4r"
  s.licenses = ["MIT"]
  s.authors = ["Tony Arcieri", "Samuel Williams"]

  s.metadata = {
    "homepage_uri" => "https://github.com/socketry/nio4r",
    "source_code_uri" => "https://github.com/socketry/nio4r",
    "changelog_uri" => "https://github.com/socketry/nio4r/blob/master/CHANGES.md"
  }

  s.required_ruby_version = Gem::Requirement.new(">= 2.4")

  s.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb"] }
  s.require_paths = ["lib"]
end
