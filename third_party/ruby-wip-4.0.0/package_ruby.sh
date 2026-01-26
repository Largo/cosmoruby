#!/bin/bash
# Package Ruby with embedded stdlib
#
# Usage: package_ruby.sh [RUBY_BINARY]
# Where RUBY_BINARY is the path to the Ruby interpreter to use (defaults to third_party/ruby/ruby)
# This script should be called from third_party/ruby directory

# Get Ruby binary from parameter or use default
RUBY_BIN="${1:-../../o/third_party/ruby/ruby}"

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
# Copy digest/sha2 extension Ruby library files
mkdir -p cosmo-ruby/lib/ruby/4.0.0/digest
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/digest/sha2/lib/* cosmo-ruby/lib/ruby/4.0.0/digest/

# Copy json extension Ruby library files
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/json/lib/json* cosmo-ruby/lib/ruby/4.0.0/

# Copy monitor extension Ruby library files
cp /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/monitor/lib/monitor.rb cosmo-ruby/lib/ruby/4.0.0/

# Copy objspace extension Ruby library files
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/objspace/lib/objspace* cosmo-ruby/lib/ruby/4.0.0/

# Note: pathname is now a built-in library in Ruby 4.0.0 (lib/pathname.rb), not an extension

# Copy socket extension Ruby library files (required for Socket methods)
cp /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/socket/lib/socket.rb cosmo-ruby/lib/ruby/4.0.0/

# Copy ripper extension Ruby library files (required for IRB's ruby-lex)
cp -r /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/ext/ripper/lib/ripper* cosmo-ruby/lib/ruby/4.0.0/

# Get DLEXT and ARCH early for patching and plugin copying
ARCH="$(sed -n 's/^  CONFIG\["arch"\] = "\(.*\)"/\1/p' ../third_party/ruby/lib/rbconfig.rb | head -1)"
ARCH=${ARCH:-x86_64-cosmo}
DLEXT="$(sed -n 's/^#define DLEXT "\.\?\(.*\)"/\1/p' ../third_party/ruby/include/ruby/config.mode.h | head -1)"
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
# Plugins must go in the archdir (lib/ruby/4.0.0/x86_64-cosmo/) which is in $LOAD_PATH,
# NOT in extensions/ subdirectory which is NOT searched by require.
EXTSTATIC="$(sed -n 's/^#define[[:space:]]\+EXTSTATIC[[:space:]]\+\([0-9]\+\)/\1/p' ../third_party/ruby/include/ruby/config.mode.h | head -1)"
SLIM_STATIC="$(sed -n 's/^#define[[:space:]]\+SLIM_STATIC[[:space:]]\+\([0-9]\+\)/\1/p' ../third_party/ruby/include/ruby/config.mode.h | head -1)"
if [[ "$EXTSTATIC" == "0" ]]; then
  plugins_dir="cosmo-ruby/lib/ruby/4.0.0/${ARCH}"
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
continuation continuation
coverage coverage
date_core date
digest digest
digest/md5 digest
digest/sha1 digest
digest/sha2 digest
etc etc
fcntl fcntl
io/nonblock io/nonblock
json/ext/generator json
json/ext/parser json
monitor monitor
objspace objspace
psych psych
rbconfig/sizeof rbconfig/sizeof
ripper ripper
io/console io/console
io/wait io/wait
socket socket
stringio stringio
strscan strscan
zlib zlib
mbedtls mbedtls
EOF

  # Copy test extensions only in debug/test mode (MODE=dbg or RUBY_TEST_EXTENSIONS=1)
  # These are Ruby's internal test helpers, not needed for production
  if [[ "$MODE" == "dbg" || "$RUBY_TEST_EXTENSIONS" == "1" ]]; then
    echo "Including test extensions (MODE=$MODE, RUBY_TEST_EXTENSIONS=$RUBY_TEST_EXTENSIONS)"
    while read -r feature archive; do
      src="third_party/ruby/ext/${archive}/${archive##*/}.${DLEXT}"
      dst="${plugins_dir}/${feature}.${DLEXT}"
      if [[ -f "$src" ]]; then
        mkdir -p "$(dirname "$dst")"
        cp -a "$src" "$dst"
      else
        echo "Warning: test extension archive missing: $src"
      fi
    done <<'TEST_EOF'
-test-/file -test-/file
-test-/iter -test-/iter
-test-/memory_view -test-/memory_view
-test-/rb_call_super_kw -test-/rb_call_super_kw
TEST_EOF
  fi

  # Copy encoding plugin archives in plugin mode
  enc_dir="${plugins_dir}/enc"
  mkdir -p "${enc_dir}"
  for enc in big5 cesu_8 cp949 emacs_mule euc_jp euc_kr euc_tw \
             gb2312 gb18030 gbk iso_8859_1 iso_8859_2 iso_8859_3 \
             iso_8859_4 iso_8859_5 iso_8859_6 iso_8859_7 iso_8859_8 \
             iso_8859_9 iso_8859_10 iso_8859_11 iso_8859_13 iso_8859_14 \
             iso_8859_15 iso_8859_16 koi8_r koi8_u shift_jis \
             utf_16be utf_16le utf_32be utf_32le windows_31j \
             windows_1250 windows_1251 windows_1252 windows_1253 \
             windows_1254 windows_1257; do
    src="third_party/ruby/enc/${enc}.${DLEXT}"
    dst="${enc_dir}/${enc}.${DLEXT}"
    if [[ -f "$src" ]]; then
      cp -a "$src" "$dst"
    else
      echo "Warning: encoding archive missing: $src"
    fi
  done

  # Copy encoding database (encdb and transdb) in plugin mode
  mkdir -p "${plugins_dir}/enc/trans"
  for db in enc/encdb enc/trans/transdb; do
    src="third_party/ruby/${db}.${DLEXT}"
    dst="${plugins_dir}/${db}.${DLEXT}"
    if [[ -f "$src" ]]; then
      cp -a "$src" "$dst"
    else
      echo "Warning: encoding database missing: $src"
    fi
  done

  # Copy transcoder plugin archives in plugin mode
  trans_dir="${plugins_dir}/enc/trans"
  mkdir -p "${trans_dir}"
  for trans in big5 cesu_8 chinese ebcdic emoji emoji_iso2022_kddi \
               emoji_sjis_docomo emoji_sjis_kddi emoji_sjis_softbank \
               escape gb18030 gbk iso2022 japanese japanese_euc \
               japanese_sjis korean single_byte utf8_mac utf_16_32; do
    src="third_party/ruby/enc/trans/${trans}.${DLEXT}"
    dst="${trans_dir}/${trans}.${DLEXT}"
    if [[ -f "$src" ]]; then
      cp -a "$src" "$dst"
    else
      echo "Warning: transcoder archive missing: $src"
    fi
  done
elif [[ "$EXTSTATIC" == "1" && "$SLIM_STATIC" == "1" ]]; then
  # In slim static mode (EXTSTATIC=1, SLIM_STATIC=1), extensions are linked but
  # require still needs to find stub files to trigger their statically-linked init functions.
  # Create zero-byte stub files for the require mechanism.
  # Stubs must go in archdir which is in $LOAD_PATH.
  plugins_dir="cosmo-ruby/lib/ruby/4.0.0/${ARCH}"
  mkdir -p "${plugins_dir}"
  while read -r feature archive; do
    dst="${plugins_dir}/${feature}.${DLEXT}"
    mkdir -p "$(dirname "$dst")"
    : > "$dst"
  done <<'EOF'
continuation continuation
coverage coverage
date_core date
digest digest
digest/md5 digest
digest/sha1 digest
digest/sha2 digest
etc etc
fcntl fcntl
io/nonblock io/nonblock
json/ext/generator json
json/ext/parser json
monitor monitor
objspace objspace
prism/prism prism
psych psych
rbconfig/sizeof rbconfig/sizeof
ripper ripper
io/console io/console
io/wait io/wait
socket socket
stringio stringio
strscan strscan
zlib zlib
mbedtls mbedtls
EOF

  # Create test extension stubs only in debug/test mode
  if [[ "$MODE" == "dbg" || "$RUBY_TEST_EXTENSIONS" == "1" ]]; then
    echo "Including test extension stubs (MODE=$MODE, RUBY_TEST_EXTENSIONS=$RUBY_TEST_EXTENSIONS)"
    for feature in "-test-/file" "-test-/iter" "-test-/memory_view" "-test-/rb_call_super_kw"; do
      dst="${plugins_dir}/${feature}.${DLEXT}"
      mkdir -p "$(dirname "$dst")"
      : > "$dst"
    done
  fi

  # Create zero-byte encoding stubs in slim static mode
  enc_dir="${plugins_dir}/enc"
  mkdir -p "${enc_dir}"
  for enc in big5 cesu_8 cp949 emacs_mule euc_jp euc_kr euc_tw \
             gb2312 gb18030 gbk iso_8859_1 iso_8859_2 iso_8859_3 \
             iso_8859_4 iso_8859_5 iso_8859_6 iso_8859_7 iso_8859_8 \
             iso_8859_9 iso_8859_10 iso_8859_11 iso_8859_13 iso_8859_14 \
             iso_8859_15 iso_8859_16 koi8_r koi8_u shift_jis \
             utf_16be utf_16le utf_32be utf_32le windows_31j \
             windows_1250 windows_1251 windows_1252 windows_1253 \
             windows_1254 windows_1257; do
    dst="${enc_dir}/${enc}.${DLEXT}"
    : > "$dst"
  done

  # Create zero-byte encoding database stubs in slim static mode
  mkdir -p "${plugins_dir}/enc/trans"
  : > "${plugins_dir}/enc/encdb.${DLEXT}"
  : > "${plugins_dir}/enc/trans/transdb.${DLEXT}"

  # Create zero-byte transcoder stubs in slim static mode
  trans_dir="${plugins_dir}/enc/trans"
  mkdir -p "${trans_dir}"
  for trans in big5 cesu_8 chinese ebcdic emoji emoji_iso2022_kddi \
               emoji_sjis_docomo emoji_sjis_kddi emoji_sjis_softbank \
               escape gb18030 gbk iso2022 japanese japanese_euc \
               japanese_sjis korean single_byte utf8_mac utf_16_32; do
    dst="${trans_dir}/${trans}.${DLEXT}"
    : > "$dst"
  done
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
# With cosmo_plugin integration, we can now generate gemspecs even in plugin mode
# since extensions will be dynamically loaded when needed
echo "Generating default gemspecs for built-in extensions and stdlib..."
RUBYOPT=--disable-gems RUBYLIB="${RUBYLIB:-../third_party/ruby/lib}" "$RUBY_BIN" --disable-gems - <<'RUBY'
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

# Copy executable scripts to /zip/bin for ruby.com -S to find them
echo "Copying executable scripts to bin/..."

# Copy libexec scripts (erb, syntax_suggest, bundle, bundler)
for exe in /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/libexec/*; do
  [ -f "$exe" ] && cp "$exe" "cosmo-ruby/bin/$(basename "$exe")"
done

# Copy gem executables from .bundle/gems/*/exe/* (the real scripts, not binstubs)
for exe in /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/.bundle/gems/*/exe/*; do
  [ -f "$exe" ] && cp "$exe" "cosmo-ruby/bin/$(basename "$exe")"
done

# Copy bin/gem
cp /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/bin/gem cosmo-ruby/bin/

# Copy additional useful executables from bundled gems (in bin/, not exe/)
for exe in racc typeprof test-unit; do
  src=$(find /home/groobiest/Code/jart/cosmopolitan/third_party/ruby/.bundle/gems -path "*/bin/$exe" -type f 2>/dev/null | head -1)
  [ -f "$src" ] && cp "$src" "cosmo-ruby/bin/$exe"
done

echo "  Copied: $(ls cosmo-ruby/bin/ | tr '\n' ' ')"

# Patch ALL shebangs from "#!/usr/bin/env ruby" to "#!/usr/bin/env ruby.com"
# This ensures scripts in /zip work with CosmoRuby and don't pick up system ruby
echo "Patching shebangs to use ruby.com..."

# Find files with ruby shebangs first (much faster than running sed on every file)
shebang_files=$(grep -rl '^#!/usr/bin/env ruby' cosmo-ruby 2>/dev/null || true)
if [ -n "$shebang_files" ]; then
  echo "$shebang_files" | while read -r f; do
    sed -i '1s|^#!/usr/bin/env ruby$|#!/usr/bin/env ruby.com|; 1s|^#!/usr/bin/env ruby |#!/usr/bin/env ruby.com |' "$f"
  done
  echo "  Patched $(echo "$shebang_files" | wc -l) files"
else
  echo "  No files with ruby shebangs found"
fi

echo "  Shebang patching complete"

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

# Create marker file for packaged Ruby detection
# This is checked at runtime to set RUBY_COSMO_PACKAGED constant
echo "CosmoRuby packaged $(date -Iseconds)" > .cosmo_ruby_packaged

# Create the ZIP file (include dotfiles like .cosmo_ruby_packaged)
RUBYOPT=--disable-gems RUBYLIB=../third_party/ruby/lib zip -q -r -dd ../ruby-stdlib.zip * .cosmo_ruby_packaged

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
