#!/bin/sh
# Generate export table for Ruby shared library
# Usage: generate_exports.sh <ruby.dbg> <output.c>

set -e

RUBY_DBG="$1"
OUTPUT="$2"

if test -f "$RUBY_DBG"; then
  EXPORT_PREFIXES="rb_|ruby_" bash third_party/cosmo_plugin/export_symbols.sh "$RUBY_DBG" "$OUTPUT"
else
  # Create stub export table until ruby.dbg exists
  printf "/* stub export table until ruby.dbg exists */\n" >"$OUTPUT"
  printf "struct cosmo_export_entry { unsigned name_off; unsigned long long addr; };\n" >>"$OUTPUT"
  printf "const struct cosmo_export_entry __cosmo_exports[] = {{0,0}};\n" >>"$OUTPUT"
  printf "const char __cosmo_exports_names[] = \"\";\n" >>"$OUTPUT"
  printf "const struct cosmo_export_entry *const __cosmo_exports_start = __cosmo_exports;\n" >>"$OUTPUT"
  printf "const struct cosmo_export_entry *const __cosmo_exports_end = __cosmo_exports;\n" >>"$OUTPUT"
  printf "const char *const __cosmo_exports_names_start = __cosmo_exports_names;\n" >>"$OUTPUT"
  printf "const char *const __cosmo_exports_names_end = __cosmo_exports_names;\n" >>"$OUTPUT"
fi
