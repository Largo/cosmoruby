#!/usr/bin/env ruby
#-*-mode:ruby;indent-tabs-mode:nil;tab-width:2;coding:utf-8-*-┐
#── devolab.cosmopolitan.dev ──────────────────────────────────────────────────┘
# frozen_string_literal: true
#
# DESCRIPTION
#
#   Compare manifest.json entries against actual files for debugging
#
# USAGE
#
#   tool/compare_manifest.rb o//third_party/ruby/generated/manifest.json [patch_dir]
#
# NOTE
#
#   This script was created for the Cosmopolitan Ruby port and does not
#   exist in upstream Ruby. For each manifest entry, prints ls-style
#   metadata for:
#     * the generated artefact (relative key in the manifest)
#     * the source file recorded in the manifest
#     * the corresponding patch file under third_party/ruby/patches

require 'json'
require 'etc'

abort "Usage: #{File.basename($PROGRAM_NAME)} <manifest.json> [patch_dir]" if ARGV.empty?

manifest_path = File.expand_path(ARGV[0])
patch_dir = File.expand_path(ARGV[1] || File.join(File.dirname(__dir__), 'patches'))
repo_root = Dir.pwd
gendir = File.dirname(manifest_path)

unless File.exist?(manifest_path)
  warn "manifest not found: #{manifest_path}"
  exit 1
end

manifest = JSON.parse(File.read(manifest_path))

def perm_string(stat)
  mode = stat.mode
  type = case stat.ftype
         when 'directory' then 'd'
         when 'link' then 'l'
         when 'socket' then 's'
         when 'fifo' then 'p'
         when 'characterSpecial' then 'c'
         when 'blockSpecial' then 'b'
         else '-'
         end
  perms = (0..2).map do |i|
    shift = 6 - (i * 3)
    bits = (mode >> shift) & 0b111
    [
      (bits & 0b100).zero? ? '-' : 'r',
      (bits & 0b010).zero? ? '-' : 'w',
      (bits & 0b001).zero? ? '-' : 'x'
    ].join
  end.join
  type + perms
end

def ls_line(path)
  return format('%-10s %-8s %-8s %8s %8s %s', 'MISSING', '-', '-', '-', '-', path) unless File.exist?(path)

  stat = File.lstat(path)
  perms = perm_string(stat)
  user = Etc.getpwuid(stat.uid).name rescue stat.uid
  group = Etc.getgrgid(stat.gid).name rescue stat.gid
  size = stat.size
  mtime = stat.mtime.strftime('%b %e %H:%M')
  target = stat.symlink? ? " -> #{File.readlink(path)}" : ''
  format('%s %-8s %-8s %8d %s %s%s', perms, user, group, size, mtime, path, target)
end

manifest.keys.sort.each do |relative|
  generated_path = File.expand_path(relative, gendir)
  source_entry = manifest.fetch(relative)
  source_path = File.expand_path(source_entry, repo_root)
  patch_name = relative.tr('/', '-') + '.diff'
  patch_path = File.join(patch_dir, patch_name)

  puts relative
  puts "  generated: #{ls_line(generated_path)}"
  puts "  source:    #{ls_line(source_path)}"
  puts "  patch:     #{ls_line(patch_path)}"
  puts
end
