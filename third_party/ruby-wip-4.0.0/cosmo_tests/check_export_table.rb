#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "open3"

def parse_exports(path)
  data = File.read(path, mode: "rb")
  names = data.scan(/"([^"]*)\\0"/).flatten
  entries = data.scan(/\{\s*(\d+)U,\s*0x([0-9a-fA-F]+)ULL\s*\}/)
  raise "#{path}: missing export names or entries" if names.empty? || entries.empty?

  if entries.length == names.length + 1 && entries.last == ["0", "0"]
    entries.pop
  end
  if entries.length != names.length
    raise "#{path}: name/entry count mismatch (#{names.length} vs #{entries.length})"
  end
  exports = {}
  names.each_with_index do |name, i|
    exports[name] = entries[i][1].to_i(16)
  end
  exports
end

def parse_nm(path)
  out, status = Open3.capture2("nm", "-g", path.to_s)
  raise "nm failed for #{path}" unless status.success?

  sym = {}
  out.each_line do |line|
    parts = line.split
    next if parts.length < 2
    next if parts.length == 2 && parts[0] == "U"
    next unless parts.length >= 3

    addr, _type, name = parts[0], parts[1], parts[2]
    next unless addr.match?(/\A[0-9a-fA-F]+\z/)

    sym[name] = addr.to_i(16)
  end
  sym
end

def check_exports(label, dbg_path, exports_path)
  exports = parse_exports(exports_path)
  nm_syms = parse_nm(dbg_path)
  missing = []
  mismatched = []
  exports.each do |name, addr|
    actual = nm_syms[name]
    if actual.nil?
      missing << name
      next
    end
    mismatched << [name, addr, actual] if actual != addr
  end
  if missing.any? || mismatched.any?
    puts "#{label}: #{missing.length} missing, #{mismatched.length} mismatched of #{exports.length} exports"
    missing.first(20).each { |name| puts "  missing #{name}" }
    mismatched.first(20).each do |name, expected, actual|
      puts format("  mismatch %s expected=0x%x actual=0x%x", name, expected, actual)
    end
    return 1
  end
  puts "#{label}: ok (#{exports.length} exports)"
  0
end

options = {}
OptionParser.new do |opts|
  opts.on("--label LABEL") { |v| options[:label] = v }
end.parse!

label = options[:label]
dbg = ARGV.shift
exports = ARGV.shift

raise "missing --label" unless label
raise "missing #{dbg}" unless dbg && File.file?(dbg)
raise "missing #{exports}" unless exports && File.file?(exports)

exit(check_exports(label, dbg, exports))
