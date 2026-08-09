# frozen_string_literal: true
#
# Static gemspec for the racc gem as vendored into CosmoRuby.
#
# racc ships with Ruby as a *bundled* gem, but the CosmoRuby build never
# installed its gemspec because it declares a C extension (ext/racc/cparse).
# That extension is now linked into ruby.com, so the gemspec can be installed
# for real: assemble_stdlib.sh scans third_party/ruby/{lib,ext} for *.gemspec
# and writes each one into
# /zip/lib/ruby/gems/4.0.0/specifications/default/, which is what makes
# `require "racc"`, `gem list`, a Bundler dependency on racc, and ocran's
# payload-provides-gem check all work.
#
# NOTE: no `extensions` -- upstream lists ext/racc/cparse/extconf.rb, but the
# native part is already linked in.

version = File.foreach(File.join(__dir__, "lib/racc/info.rb")) do |line|
  /^\s*VERSION\s*=\s*'(.*)'/ =~ line and break $1
end rescue nil
version ||= "1.8.1"

Gem::Specification.new do |s|
  s.name = "racc"
  s.version = version

  s.summary = "Racc is a LALR(1) parser generator"
  s.description = "Racc is a LALR(1) parser generator. It is written in Ruby itself, " \
                  "and generates Ruby program. Vendored into CosmoRuby; the cparse " \
                  "runtime extension is statically linked into ruby.com."
  s.homepage = "https://github.com/ruby/racc"
  s.licenses = ["Ruby", "BSD-2-Clause"]
  s.authors = ["Minero Aoki", "Aaron Patterson"]

  s.metadata = {
    "homepage_uri" => "https://github.com/ruby/racc",
    "source_code_uri" => "https://github.com/ruby/racc",
    "changelog_uri" => "https://github.com/ruby/racc/blob/master/ChangeLog"
  }

  s.required_ruby_version = Gem::Requirement.new(">= 2.5")

  s.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb"] }
  s.require_paths = ["lib"]
end
