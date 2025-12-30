#!/usr/bin/env ruby
#-*-mode:ruby;indent-tabs-mode:nil;tab-width:2;coding:utf-8-*-┐
#── devolab.cosmopolitan.dev ──────────────────────────────────────────────────┘
#
# DESCRIPTION
#
#   Add an entry to the Ruby code generation manifest.json
#
# USAGE
#
#   add_to_manifest.rb <manifest.json> <key> <value>
#
# NOTE
#
#   This script was created for the Cosmopolitan Ruby port and does not
#   exist in upstream Ruby. It MUST NOT require 'json' to avoid circular
#   dependency. JSON is a C extension that needs to be built, but code
#   generation runs before extensions are available. We use pure Ruby
#   string manipulation instead.

manifest_path = ARGV[0]
key = ARGV[1]
value = ARGV[2]

if !manifest_path || !key || !value
  STDERR.puts "Usage: #{$0} <manifest.json> <key> <value>"
  exit 1
end

# Parse JSON manually (simple key-value object only)
def parse_manifest(content)
  manifest = {}
  # Match "key": "value" patterns
  content.scan(/"([^"]+)":\s*"([^"]*)"/) do |k, v|
    manifest[k] = v
  end
  manifest
end

# Generate pretty JSON manually
def generate_json(manifest)
  return "{\n}\n" if manifest.empty?

  lines = ["{"]
  manifest.each_with_index do |(k, v), idx|
    comma = idx < manifest.size - 1 ? "," : ""
    lines << "  \"#{k}\": \"#{v}\"#{comma}"
  end
  lines << "}\n"
  lines.join("\n")
end

# Read existing manifest or start with empty hash
manifest = if File.exist?(manifest_path)
  parse_manifest(File.read(manifest_path))
else
  {}
end

# Add the new entry
manifest[key] = value

# Write back with pretty formatting
File.write(manifest_path, generate_json(manifest))
