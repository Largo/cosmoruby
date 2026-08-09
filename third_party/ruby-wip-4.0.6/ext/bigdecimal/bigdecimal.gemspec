# frozen_string_literal: true
#
# Static gemspec for the bigdecimal gem as vendored into CosmoRuby.
#
# Same reasoning as ext/sqlite3/sqlite3.gemspec and ext/nokogiri/nokogiri.gemspec:
# assemble_stdlib.sh scans third_party/ruby/{lib,ext} for *.gemspec files and
# installs each as a *default gem* specification under
# /zip/lib/ruby/gems/4.0.0/specifications/default/, which is what makes
# `gem list`, Bundler and ocran's payload-provides-gem check see bigdecimal as
# provided by the interpreter.
#
# NOTE: no `extensions` -- upstream's gemspec lists ext/bigdecimal/extconf.rb,
# but the native part is already linked into ruby.com, and a default gem with
# an `extensions` entry makes RubyGems look for a build artefact that will
# never exist.

version = File.foreach(File.join(__dir__, "bigdecimal.c")) do |line|
  /^#define\s+BIGDECIMAL_VERSION\s+"?([0-9][^"\s]*)"?/ =~ line and break $1
end rescue nil
version ||= "4.0.1"

Gem::Specification.new do |s|
  s.name = "bigdecimal"
  s.version = version

  s.summary = "Arbitrary-precision decimal floating-point number library."
  s.description = "This library provides arbitrary-precision decimal floating-point number class. " \
                  "Vendored into CosmoRuby and statically linked into ruby.com."
  s.homepage = "https://github.com/ruby/bigdecimal"
  s.licenses = ["Ruby", "BSD-2-Clause"]
  s.authors = ["Kenta Murata", "Zachary Scott", "Shigeo Kobayashi"]

  s.metadata = {
    "homepage_uri" => "https://github.com/ruby/bigdecimal",
    "source_code_uri" => "https://github.com/ruby/bigdecimal",
    "changelog_uri" => "https://github.com/ruby/bigdecimal/blob/master/CHANGES.md"
  }

  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0")

  s.files = [
    "lib/bigdecimal.rb",
    "lib/bigdecimal/jacobian.rb",
    "lib/bigdecimal/ludcmp.rb",
    "lib/bigdecimal/math.rb",
    "lib/bigdecimal/newton.rb",
    "lib/bigdecimal/util.rb"
  ]
  s.require_paths = ["lib"]
end
