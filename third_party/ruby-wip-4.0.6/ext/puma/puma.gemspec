# frozen_string_literal: true
#
# Static gemspec for the puma gem as vendored into CosmoRuby.
#
# assemble_stdlib.sh scans third_party/ruby/{lib,ext} for *.gemspec files and
# installs each as a *default gem* specification under
# /zip/lib/ruby/gems/4.0.0/specifications/default/, which is what makes
# `gem list`, Bundler and ocran's payload-provides-gem check see puma as
# provided by the interpreter.
#
# NOTE: no `extensions` -- upstream lists ext/puma_http11/extconf.rb, but
# puma_http11 is already linked into ruby.com.
#
# The `nio4r ~> 2.0` runtime dependency is kept, because it is real and because
# CosmoRuby now genuinely provides nio4r as a default gem too; dropping it
# would hide a dependency that Bundler ought to see.
#
# This puma has NO SSL support: mini_ssl.c is compiled without
# HAVE_OPENSSL_BIO_H (see BUILD.mk).  Puma::HAS_SSL is false, and
# Puma::MiniSSL does not exist.

version = File.foreach(File.join(__dir__, "lib/puma/const.rb")) do |line|
  /^\s*PUMA_VERSION\s*=\s*VERSION\s*=\s*"(.*)"/ =~ line and break $1
end rescue nil
version ||= "8.0.2"

Gem::Specification.new do |s|
  s.name = "puma"
  s.version = version

  s.summary = "A Ruby/Rack web server built for parallelism."
  s.description = "Puma is a simple, fast, multi-threaded, and highly parallel HTTP 1.1 " \
                  "server for Ruby/Rack applications. Vendored into CosmoRuby and " \
                  "statically linked into ruby.com, without SSL support."
  s.homepage = "https://puma.io"
  s.licenses = ["BSD-3-Clause"]
  s.authors = ["Evan Phoenix"]

  s.metadata = {
    "homepage_uri" => "https://puma.io",
    "source_code_uri" => "https://github.com/puma/puma",
    "changelog_uri" => "https://github.com/puma/puma/blob/master/History.md",
    "bug_tracker_uri" => "https://github.com/puma/puma/issues"
  }

  s.required_ruby_version = Gem::Requirement.new(">= 3.0")

  s.add_runtime_dependency "nio4r", "~> 2.0"

  s.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb"] }
  s.require_paths = ["lib"]
end
