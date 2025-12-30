#!/usr/bin/env ruby
#-*-mode:ruby;indent-tabs-mode:nil;tab-width:2;coding:utf-8-*-┐
#── devolab.cosmopolitan.dev ──────────────────────────────────────────────────┘
# frozen_string_literal: true
#
# DESCRIPTION
#
#   Synchronise generated files from o/third_party/ruby/generated/ to source tree
#
# USAGE
#
#   tool/sync_generated_files.rb <manifest.json> [--dry-run]
#
# NOTE
#
#   This script was created for the Cosmopolitan Ruby port. It reads the
#   manifest.json produced by ruby.codegen and copies generated files to
#   their destination paths in the source tree.

require 'json'
require 'fileutils'

def format_size(bytes)
  if bytes < 1024
    "#{bytes}B"
  elsif bytes < 1024 * 1024
    "#{(bytes / 1024.0).round(1)}KB"
  else
    "#{(bytes / (1024.0 * 1024)).round(1)}MB"
  end
end

def file_status(path)
  if File.exist?(path)
    size = File.size(path)
    mtime = File.mtime(path).strftime('%Y-%m-%d %H:%M:%S')
    "#{format_size(size).rjust(10)} #{mtime}"
  else
    "   MISSING #{' ' * 19}"
  end
end

manifest_path = ARGV[0]
dry_run = ARGV.include?('--dry-run')

unless manifest_path && File.exist?(manifest_path)
  abort "Usage: #{File.basename($PROGRAM_NAME)} <manifest.json> [--dry-run]"
end

repo_root = Dir.pwd
gendir = File.dirname(File.expand_path(manifest_path))
manifest = JSON.parse(File.read(manifest_path))

puts "=" * 80
puts "Generated Files Sync #{dry_run ? '(DRY RUN)' : ''}"
puts "=" * 80
puts "Manifest: #{manifest_path}"
puts "Source:   #{gendir}"
puts "Dest:     #{repo_root}"
puts "=" * 80
puts

copied_count = 0
skipped_count = 0
missing_count = 0

manifest.keys.sort.each do |relative_src|
  dest_path = manifest[relative_src]
  src_full = File.join(gendir, relative_src)
  dest_full = File.join(repo_root, dest_path)

  puts relative_src
  puts "  Source: #{file_status(src_full)} #{src_full}"
  puts "  Dest:   #{file_status(dest_full)} #{dest_full}"

  unless File.exist?(src_full)
    puts "  Status: ⚠️  SOURCE MISSING - skipping"
    missing_count += 1
    puts
    next
  end

  if File.exist?(dest_full)
    src_content = File.read(src_full)
    dest_content = File.read(dest_full)

    if src_content == dest_content
      puts "  Status: ✓ Already up-to-date"
      skipped_count += 1
      puts
      next
    end
  end

  if dry_run
    puts "  Status: 📋 Would copy (#{format_size(File.size(src_full))})"
    copied_count += 1
  else
    FileUtils.mkdir_p(File.dirname(dest_full))
    FileUtils.cp(src_full, dest_full)
    puts "  Status: ✅ Copied (#{format_size(File.size(src_full))})"
    copied_count += 1
  end

  puts
end

puts "=" * 80
puts "Summary:"
puts "  Copied:  #{copied_count}" unless dry_run
puts "  Would copy: #{copied_count}" if dry_run && copied_count > 0
puts "  Up-to-date: #{skipped_count}"
puts "  Missing: #{missing_count}" if missing_count > 0
puts "  Total:   #{manifest.size}"
puts "=" * 80

if dry_run && copied_count > 0
  puts
  puts "Run without --dry-run to perform the copy."
end
