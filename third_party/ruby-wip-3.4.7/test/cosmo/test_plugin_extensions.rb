# frozen_string_literal: true

# Minimal self-check for Cosmo plugin-loaded extensions.
# Exits nonzero on failure; no test/unit dependency.

require "rbconfig"

PLUGIN_ENV = "COSMO_RUBY_PLUGIN_PATH"

def plugin_dir
  ENV[PLUGIN_ENV] || "/zip/lib/ruby/3.4.0/extensions/#{RbConfig::CONFIG['arch']}"
end

def assert(cond, msg)
  return if cond
  warn("FAIL: #{msg}")
  exit 1
end

extensions = %w[
  date
  digest
  digest/md5
  digest/sha1
  digest/sha2
  etc
  io/nonblock
  json
  monitor
  pathname
  psych
  socket
  stringio
  zlib
  mbedtls
]

extensions.each do |feature|
  require_result = require(feature)
  assert(require_result != false, "require('#{feature}') failed")
  loaded = $LOADED_FEATURES.find { |f| f.end_with?("#{feature}.a") }
  assert(loaded, "expected #{feature} to be loaded from .a plugin, LOADED_FEATURES does not include #{feature}.a")
  if ENV.key?(PLUGIN_ENV)
    assert(loaded.start_with?(plugin_dir), "expected #{loaded} to come from #{plugin_dir}")
  end
end

puts "All plugin extensions loaded from archives: #{extensions.join(', ')}"
