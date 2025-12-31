#!/bin/bash
# Package Ruby with embedded stdlib
#
# Usage: cd o && bash ../third_party/ruby/package_ruby.sh
# This script must be run from the 'o' directory

# Ensure we're in the o directory
cd "$(dirname "$0")/../../o" 2>/dev/null || true

# in o

# Exit if current working directory is not o (does not end in /o)
if [[ ! "$PWD" =~ /o$ ]]; then
  echo "Error: Script must be run from the 'o' directory."
  exit 1
fi

# Clean up any existing cosmo-ruby directory and ruby-stdlib.zip file
rm -rf cosmo-ruby
rm -f ruby-stdlib.zip

mkdir -p cosmo-ruby/bin

# Create directory structure for Ruby stdlib
mkdir -p cosmo-ruby/lib/ruby/4.0.0

# Copy Ruby standard library
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/lib/* cosmo-ruby/lib/ruby/4.0.0/

# Copy psych extension Ruby library files (required for YAML support)
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/psych/lib/psych* cosmo-ruby/lib/ruby/4.0.0/

# Copy date extension Ruby library files (required by psych)
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/date/lib/date* cosmo-ruby/lib/ruby/4.0.0/

# Copy digest extension Ruby library files
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/digest/lib/digest* cosmo-ruby/lib/ruby/4.0.0/

# Copy json extension Ruby library files
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/json/lib/json* cosmo-ruby/lib/ruby/4.0.0/

# Copy monitor extension Ruby library files
cp /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/monitor/lib/monitor.rb cosmo-ruby/lib/ruby/4.0.0/

# Note: pathname is now a built-in library in Ruby 4.0.0 (lib/pathname.rb), not an extension

# Copy socket extension Ruby library files (required for Socket methods)
cp /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/socket/lib/socket.rb cosmo-ruby/lib/ruby/4.0.0/

# Copy ripper extension Ruby library files (required for IRB's ruby-lex)
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/ripper/lib/ripper* cosmo-ruby/lib/ruby/4.0.0/

# Get DLEXT and ARCH early for patching and plugin copying
ARCH="$(sed -n 's/^  CONFIG\["arch"\] = "\(.*\)"/\1/p' ../third_party/ruby/lib/rbconfig.rb | head -1)"
ARCH=${ARCH:-x86_64-cosmo}
DLEXT="$(sed -n 's/^  CONFIG\["DLEXT"\] = "\(.*\)"/\1/p' ../third_party/ruby/lib/rbconfig.rb | head -1)"
DLEXT=${DLEXT:-a}

# Patch extension wrapper files to use correct DLEXT in plugin mode
# Ruby extension wrapper files have hardcoded 'require "ext.so"' but in plugin mode
# we build .a files. Static mode uses DLEXT=".so" and extensions are linked in, so skip patching.
if [[ "$DLEXT" != "so" ]]; then
  find cosmo-ruby/lib/ruby/4.0.0 -name "*.rb" -type f -exec sed -i "s/require ['\"]\\([^'\"]*\\)\\.so['\"]/require '\\1.$DLEXT'/g" {} \;
fi

# Copy bundled gems (rake, minitest, etc.)
mkdir -p cosmo-ruby/lib/ruby/gems/4.0.0
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/.bundle/* cosmo-ruby/lib/ruby/gems/4.0.0/

# Copy plugin extension archives when building in plugin mode (EXTSTATIC=0)
EXTSTATIC="$(sed -n 's/^#define[[:space:]]\+EXTSTATIC[[:space:]]\+\([0-9]\+\)/\1/p' ../third_party/ruby/include/ruby/config.h | head -1)"
SLIM_STATIC="$(sed -n 's/^#define[[:space:]]\+SLIM_STATIC[[:space:]]\+\([0-9]\+\)/\1/p' ../third_party/ruby/include/ruby/config.h | head -1)"
if [[ "$EXTSTATIC" == "0" ]]; then
  plugins_dir="cosmo-ruby/lib/ruby/4.0.0/extensions/${ARCH}"
  mkdir -p "${plugins_dir}"
  # Map feature path -> archive path
  while read -r feature archive; do
    archive_dir="${archive}"
    archive_base="${archive##*/}"
    src="third_party/ruby/ext/${archive_dir}/${archive_base}.${DLEXT}"
    dst="${plugins_dir}/${feature}.${DLEXT}"
    if [[ -f "$src" ]]; then
      mkdir -p "$(dirname "$dst")"
      cp -a "$src" "$dst"
    else
      echo "Warning: plugin archive missing: $src"
    fi
  done <<'EOF'
date_core date
digest digest
digest/md5 digest
digest/sha1 digest
digest/sha2 digest
etc etc
io/nonblock io/nonblock
json/ext/generator json
json/ext/parser json
monitor monitor
psych psych
ripper ripper
io/console io/console
io/wait io/wait
socket socket
stringio stringio
zlib zlib
mbedtls mbedtls
EOF
elif [[ "$EXTSTATIC" == "1" && "$SLIM_STATIC" == "1" ]]; then
  # In slim static mode (EXTSTATIC=1, SLIM_STATIC=1), extensions are linked but
  # require still needs to find stub files to trigger their statically-linked init functions.
  # Create zero-byte stub files for the require mechanism.
  plugins_dir="cosmo-ruby/lib/ruby/4.0.0/extensions/${ARCH}"
  mkdir -p "${plugins_dir}"
  while read -r feature archive; do
    dst="${plugins_dir}/${feature}.${DLEXT}"
    mkdir -p "$(dirname "$dst")"
    : > "$dst"
  done <<'EOF'
date_core date
digest digest
digest/md5 digest
digest/sha1 digest
digest/sha2 digest
etc etc
io/nonblock io/nonblock
json/ext/generator json
json/ext/parser json
monitor monitor
psych psych
ripper ripper
io/console io/console
io/wait io/wait
socket socket
stringio stringio
zlib zlib
mbedtls mbedtls
EOF
fi

# Create default gem specification for bundler (must be static, no require_relative)
mkdir -p cosmo-ruby/lib/ruby/gems/4.0.0/specifications/default
cat > cosmo-ruby/lib/ruby/gems/4.0.0/specifications/default/bundler.gemspec <<'EOF'
# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = "bundler"
  s.version     = "2.6.9"
  s.license     = "MIT"
  s.authors     = [
    "André Arko", "Samuel Giddins", "Colby Swandale", "Hiroshi Shibata",
    "David Rodríguez", "Grey Baker", "Stephanie Morillo", "Chris Morris", "James Wen", "Tim Moore",
    "André Medeiros", "Jessica Lynn Suttles", "Terence Lee", "Carl Lerche",
    "Yehuda Katz"
  ]
  s.email       = ["team@bundler.io"]
  s.homepage    = "https://bundler.io"
  s.summary     = "The best way to manage your application's dependencies"
  s.description = "Bundler manages an application's dependencies through its entire life, across many machines, systematically and repeatably"

  s.required_ruby_version     = ">= 3.0.0"
  s.required_rubygems_version = ">= 3.0.0"

  s.files = Dir.glob("lib/**/*", File::FNM_DOTMATCH).reject { |f| File.directory?(f) }
  s.require_paths = ["lib"]
end
EOF

# Generate default gemspecs for built-in extensions and stdlib
# Ruby 4.0.0 moved IRB and other components to bundled gems, which depend on
# built-in extensions and stdlib gems. These need default gemspecs for gem resolution.
echo "Generating default gemspecs for built-in extensions and stdlib..."
RUBYOPT=--disable-gems RUBYLIB=../third_party/ruby/lib third_party/ruby/ruby --disable-gems - <<'RUBY'
require 'rubygems'
require 'rubygems/specification'
require 'find'

ruby_root = '/home/groobiest/Code/jart/cosmopolitan/third_party/ruby'
dest_dir = 'cosmo-ruby/lib/ruby/gems/4.0.0/specifications/default'

# Find all .gemspec files in lib/ and ext/ directories
gemspec_files = []
['lib', 'ext'].each do |dir|
  search_path = File.join(ruby_root, dir)
  Find.find(search_path) do |path|
    gemspec_files << path if path.end_with?('.gemspec')
  end
end

puts "  Found #{gemspec_files.size} gemspec files"

gemspec_files.each do |gemspec_path|
  begin
    spec = Gem::Specification.load(gemspec_path)
    next unless spec

    output_file = File.join(dest_dir, "#{spec.name}-#{spec.version}.gemspec")
    File.write(output_file, spec.to_ruby)
    puts "  Generated: #{spec.name}-#{spec.version}.gemspec"
  rescue => e
    puts "  Warning: Failed to generate #{File.basename(gemspec_path)}: #{e.message}"
  end
end
RUBY

#
mkdir -p cosmo-ruby/usr/share/terminfo

#
cp -r /home/groobiest/Code/jart/cosmopolitan/usr/share/terminfo/* cosmo-ruby/usr/share/terminfo

cd cosmo-ruby

# in o/cosmo-ruby !!
# NOTE: We used to extract existing ZIP content here, but that overwrites our patched files!
# Since we're rebuilding stdlib from scratch (copying from ext/*/lib and patching .so->.a),
# we don't need to preserve old ZIP content. If you need to preserve user-added content,
# extract BEFORE the file copying step above.
# RUBYOPT=--disable-gems RUBYLIB=../../third_party/ruby/lib \
#   ../third_party/ruby/ruby --disable-gems ../../third_party/ruby/extract_zip.rb /zip/
echo "ZIP extraction skipped (rebuilding from source)"
touch .cosmo

# Create the ZIP file
RUBYOPT=--disable-gems RUBYLIB=../third_party/ruby/lib zip -q -r -dd ../ruby-stdlib.zip *

cd ..

# in o

# Prepare the Ruby binary for packaging
cp third_party/ruby/ruby third_party/ruby/ruby.com
cp third_party/ruby/irb third_party/ruby/irb.com
cp third_party/ruby/miniruby third_party/ruby/miniruby.com
# Use zipcopy to embed the stdlib ZIP into the Ruby binary
../.cosmocc/current/bin/zipcopy ruby-stdlib.zip third_party/ruby/ruby.com
../.cosmocc/current/bin/zipcopy ruby-stdlib.zip third_party/ruby/irb.com
../.cosmocc/current/bin/zipcopy ruby-stdlib.zip third_party/ruby/miniruby.com
