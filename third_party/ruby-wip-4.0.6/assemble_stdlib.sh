#!/bin/bash
# Assemble CosmoRuby stdlib tree and create ruby-stdlib.zip
#
# Copies the Ruby standard library, extensions, gems, terminfo, and
# executable scripts into o/cosmo-ruby/, then zips it into o/ruby-stdlib.zip.
#
# Usage: assemble_stdlib.sh [RUBY_BINARY]
#   RUBY_BINARY  Path to Ruby interpreter for gemspec generation
#                 (defaults to <repo>/o/third_party/ruby/ruby)
#
# Environment:
#   MODE                  Build mode (dbg includes test extensions)
#   RUBY_TEST_EXTENSIONS  Set to 1 to include test extensions
#
# Output: <repo>/o/ruby-stdlib.zip

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)" || { echo "Error: not inside a git repo"; exit 1; }

# Get Ruby binary from parameter or use default
RUBY_BIN="${1:-$REPO_ROOT/o/third_party/ruby/ruby}"

# Convert relative path to absolute
[[ "$RUBY_BIN" != /* ]] && RUBY_BIN="$PWD/$RUBY_BIN"

# Work in the o/ directory
cd "$REPO_ROOT/o"

# Repo root is one level up from o/
RUBY_SRC=../third_party/ruby

# Verify zip/zipless pairs differ and have correct load paths
bash "$RUBY_SRC/verify_zip_zipless.sh" third_party/ruby

# Clean up any existing cosmo-ruby directory and ruby-stdlib.zip file
rm -rf cosmo-ruby
rm -f ruby-stdlib.zip

mkdir -p cosmo-ruby/bin

# Create directory structure for Ruby stdlib
mkdir -p cosmo-ruby/lib/ruby/4.0.0

# Copy Ruby standard library
cp -r "$RUBY_SRC"/lib/* cosmo-ruby/lib/ruby/4.0.0/

# Copy extension Ruby library files into stdlib tree
cp -r "$RUBY_SRC"/ext/psych/lib/psych*          cosmo-ruby/lib/ruby/4.0.0/
cp -r "$RUBY_SRC"/ext/date/lib/date*             cosmo-ruby/lib/ruby/4.0.0/
cp -r "$RUBY_SRC"/ext/digest/lib/digest*         cosmo-ruby/lib/ruby/4.0.0/
mkdir -p cosmo-ruby/lib/ruby/4.0.0/digest
cp -r "$RUBY_SRC"/ext/digest/sha2/lib/*          cosmo-ruby/lib/ruby/4.0.0/digest/
cp -r "$RUBY_SRC"/ext/json/lib/json*             cosmo-ruby/lib/ruby/4.0.0/
cp    "$RUBY_SRC"/ext/monitor/lib/monitor.rb     cosmo-ruby/lib/ruby/4.0.0/
cp -r "$RUBY_SRC"/ext/objspace/lib/objspace*     cosmo-ruby/lib/ruby/4.0.0/
# Note: pathname is a built-in library in Ruby 4.0.0 (lib/pathname.rb), not an extension
cp    "$RUBY_SRC"/ext/socket/lib/socket.rb       cosmo-ruby/lib/ruby/4.0.0/
cp -r "$RUBY_SRC"/ext/sqlite3/lib/sqlite3*       cosmo-ruby/lib/ruby/4.0.0/
cp -r "$RUBY_SRC"/ext/ripper/lib/ripper*         cosmo-ruby/lib/ruby/4.0.0/
cp -r "$RUBY_SRC"/ext/strscan/lib/strscan*       cosmo-ruby/lib/ruby/4.0.0/
cp -r "$RUBY_SRC"/ext/io/console/lib/console*    cosmo-ruby/lib/ruby/4.0.0/
cp    "$RUBY_SRC"/ext/coverage/lib/coverage.rb    cosmo-ruby/lib/ruby/4.0.0/
cp    "$RUBY_SRC"/ext/pty/lib/expect.rb           cosmo-ruby/lib/ruby/4.0.0/
mkdir -p cosmo-ruby/lib/ruby/4.0.0/forwardable
cp    "$RUBY_SRC"/ext/rubyvm/lib/forwardable/impl.rb cosmo-ruby/lib/ruby/4.0.0/forwardable/
mkdir -p cosmo-ruby/lib/ruby/4.0.0/win32
cp -r "$RUBY_SRC"/ext/win32/lib/win32/*          cosmo-ruby/lib/ruby/4.0.0/win32/

# Get DLEXT and ARCH early for patching and plugin copying
ARCH="$(sed -n 's/^  CONFIG\["arch"\] = "\(.*\)"/\1/p' "$RUBY_SRC"/lib/rbconfig.rb | head -1)"
ARCH=${ARCH:-x86_64-cosmo}
DLEXT="$(sed -n 's/^#define DLEXT "\.\?\(.*\)"/\1/p' "$RUBY_SRC"/include/ruby/config.mode.h | head -1)"
DLEXT=${DLEXT:-a}

# Patch extension wrapper files to use correct DLEXT in plugin mode
# Ruby extension wrapper files have hardcoded 'require "ext.so"' but in plugin mode
# we build .a files. Static mode uses DLEXT=".so" and extensions are linked in, so skip patching.
if [[ "$DLEXT" != "so" ]]; then
  find cosmo-ruby/lib/ruby/4.0.0 -name "*.rb" -type f -exec sed -i "s/require ['\"]\\([^'\"]*\\)\\.so['\"]/require '\\1.$DLEXT'/g" {} \;
fi

# Copy bundled gems (rake, minitest, etc.)
mkdir -p cosmo-ruby/lib/ruby/gems/4.0.0
cp -r "$RUBY_SRC"/.bundle/* cosmo-ruby/lib/ruby/gems/4.0.0/

# Copy plugin extension archives when building in plugin mode (EXTSTATIC=0)
# Plugins must go in the archdir (lib/ruby/4.0.0/x86_64-cosmo/) which is in $LOAD_PATH,
# NOT in extensions/ subdirectory which is NOT searched by require.
EXTSTATIC="$(sed -n 's/^#define[[:space:]]\+EXTSTATIC[[:space:]]\+\([0-9]\+\)/\1/p' "$RUBY_SRC"/include/ruby/config.mode.h | head -1)"
SLIM_STATIC="$(sed -n 's/^#define[[:space:]]\+SLIM_STATIC[[:space:]]\+\([0-9]\+\)/\1/p' "$RUBY_SRC"/include/ruby/config.mode.h | head -1)"
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
sqlite3/sqlite3_native sqlite3
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
sqlite3/sqlite3_native sqlite3
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
    "Andre Arko", "Samuel Giddins", "Colby Swandale", "Hiroshi Shibata",
    "David Rodriguez", "Grey Baker", "Stephanie Morillo", "Chris Morris", "James Wen", "Tim Moore",
    "Andre Medeiros", "Jessica Lynn Suttles", "Terence Lee", "Carl Lerche",
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
RUBYOPT=--disable-gems RUBYLIB="${RUBYLIB:-$RUBY_SRC/lib}" "$RUBY_BIN" --disable-gems - "$RUBY_SRC" <<'RUBY'
require 'rubygems'
require 'rubygems/specification'
require 'find'

ruby_root = File.expand_path(ARGV[0])
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

# Copy terminfo database for terminal support
mkdir -p cosmo-ruby/usr/share/terminfo
cp -r ../usr/share/terminfo/* cosmo-ruby/usr/share/terminfo

# Copy SSL root certificates for HTTPS support (gem install, net/http, etc.)
# Cosmopolitan's GetSslRoots() reads from /zip/usr/share/ssl/root/
SSL_ROOT=../usr/share/ssl/root
if [ -d "$SSL_ROOT" ]; then
  mkdir -p cosmo-ruby/usr/share/ssl/root
  cp "$SSL_ROOT"/*.pem cosmo-ruby/usr/share/ssl/root/
  echo "  Copied $(ls cosmo-ruby/usr/share/ssl/root/*.pem | wc -l) SSL root certs"
else
  echo "  Warning: SSL root certs not found at $SSL_ROOT"
fi

# Copy executable scripts to /zip/bin for ruby.com -S to find them
echo "Copying executable scripts to bin/..."

# Copy libexec scripts (erb, syntax_suggest, bundle, bundler)
for exe in "$RUBY_SRC"/libexec/*; do
  [ -f "$exe" ] && cp "$exe" "cosmo-ruby/bin/$(basename "$exe")"
done

# Copy gem executables from .bundle/gems/*/exe/* (the real scripts, not binstubs)
for exe in "$RUBY_SRC"/.bundle/gems/*/exe/*; do
  [ -f "$exe" ] && cp "$exe" "cosmo-ruby/bin/$(basename "$exe")"
done

# Copy bin/gem
cp "$RUBY_SRC"/bin/gem cosmo-ruby/bin/

# Copy additional useful executables from bundled gems (in bin/, not exe/)
for exe in racc typeprof test-unit; do
  src=$(find "$RUBY_SRC"/.bundle/gems -path "*/bin/$exe" -type f 2>/dev/null | head -1)
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

# in o/cosmo-ruby
# NOTE: We rebuild stdlib from scratch (copying from ext/*/lib and patching .so->.a),
# so we don't need to preserve old ZIP content.
echo "ZIP extraction skipped (rebuilding from source)"
touch .cosmo

# Create marker file for packaged Ruby detection
# This is checked at runtime to set RUBY_COSMO_PACKAGED constant
echo "CosmoRuby packaged $(date -Iseconds)" > .cosmo_ruby_packaged

# Create the ZIP file (include dotfiles like .cosmo_ruby_packaged)
RUBYOPT=--disable-gems RUBYLIB="$RUBY_SRC/lib" zip -q -r -dd ../ruby-stdlib.zip * .cosmo_ruby_packaged

cd ..

echo "Created $(wc -c < ruby-stdlib.zip | tr -d ' ') byte ruby-stdlib.zip"
