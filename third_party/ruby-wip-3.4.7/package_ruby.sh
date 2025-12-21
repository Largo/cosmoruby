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
mkdir -p cosmo-ruby/lib/ruby/3.4.0

# Copy Ruby standard library
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/lib/* cosmo-ruby/lib/ruby/3.4.0/

# Copy psych extension Ruby library files (required for YAML support)
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/psych/lib/psych* cosmo-ruby/lib/ruby/3.4.0/

# Copy date extension Ruby library files (required by psych)
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/date/lib/date* cosmo-ruby/lib/ruby/3.4.0/

# Copy digest extension Ruby library files
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/digest/lib/digest* cosmo-ruby/lib/ruby/3.4.0/

# Copy json extension Ruby library files
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/json/lib/json* cosmo-ruby/lib/ruby/3.4.0/

# Copy monitor extension Ruby library files
cp /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/monitor/lib/monitor.rb cosmo-ruby/lib/ruby/3.4.0/

# Copy pathname extension Ruby library files
cp /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/pathname/lib/pathname.rb cosmo-ruby/lib/ruby/3.4.0/

# Copy socket extension Ruby library files (required for Socket methods)
cp /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/socket/lib/socket.rb cosmo-ruby/lib/ruby/3.4.0/

# Copy bundled gems (rake, minitest, etc.)
mkdir -p cosmo-ruby/lib/ruby/gems/3.4.0
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/.bundle/* cosmo-ruby/lib/ruby/gems/3.4.0/

# Copy plugin extension archives when building in plugin mode (EXTSTATIC=0)
ARCH="$(sed -n 's/^  CONFIG\["arch"\] = "\(.*\)"/\1/p' ../third_party/ruby/lib/rbconfig.rb | head -1)"
ARCH=${ARCH:-x86_64-cosmo}
EXTSTATIC="$(sed -n 's/^#define[[:space:]]\+EXTSTATIC[[:space:]]\+\([0-9]\+\)/\1/p' ../third_party/ruby/include/ruby/config.h | head -1)"
if [[ "$EXTSTATIC" == "0" ]]; then
  plugins_dir="cosmo-ruby/lib/ruby/3.4.0/extensions/${ARCH}"
  mkdir -p "${plugins_dir}"
  # Map feature path -> archive path
  while read -r feature archive; do
    archive_dir="${archive}"
    archive_base="${archive##*/}"
    src="third_party/ruby/ext/${archive_dir}/${archive_base}.a"
    dst="${plugins_dir}/${feature}.a"
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
pathname pathname
psych psych
socket socket
stringio stringio
zlib zlib
mbedtls mbedtls
EOF
fi

# Create default gem specification for bundler (must be static, no require_relative)
mkdir -p cosmo-ruby/lib/ruby/gems/3.4.0/specifications/default
cat > cosmo-ruby/lib/ruby/gems/3.4.0/specifications/default/bundler.gemspec <<'EOF'
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

#
mkdir -p cosmo-ruby/usr/share/terminfo

#
cp -r /home/groobiest/Code/jart/cosmopolitan/usr/share/terminfo/* cosmo-ruby/usr/share/terminfo

cd cosmo-ruby

# in o/cosmo-ruby !!
# Extract the existing ZIP fs stuff into the current directory
RUBYLIB=../../third_party/ruby/lib ../third_party/ruby/ruby ../../third_party/ruby/extract_zip.rb /zip/
touch .cosmo

# Create the ZIP file
RUBYOPT=--disable-gems RUBYLIB=../third_party/ruby/lib zip -q -r -dd ../ruby-stdlib.zip *
echo Zip creation complete

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
