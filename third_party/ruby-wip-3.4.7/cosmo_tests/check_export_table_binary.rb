#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "open3"

def read_sections(path)
  out, status = Open3.capture2("readelf", "-S", "-W", path)
  raise "readelf failed for #{path}" unless status.success?

  sections = []
  out.each_line do |line|
    next unless line =~ /^\s*\[\s*\d+\]\s+(\S+)\s+\S+\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)/
    name = Regexp.last_match(1)
    addr = Regexp.last_match(2).to_i(16)
    off = Regexp.last_match(3).to_i(16)
    size = Regexp.last_match(4).to_i(16)
    sections << [name, addr, off, size]
  end
  sections
end

def section_for_addr(sections, addr)
  sections.find { |_name, sec_addr, _off, size| addr >= sec_addr && addr < sec_addr + size }
end

def section_named(sections, name)
  sections.find { |sec_name, _addr, _off, _size| sec_name == name }
end

def addr_to_file_offset(sections, addr)
  sec = section_for_addr(sections, addr)
  return nil unless sec
  _name, sec_addr, sec_off, _size = sec
  sec_off + (addr - sec_addr)
end

def read_ptr64(bin, sections, addr)
  off = addr_to_file_offset(sections, addr)
  raise "address out of range: 0x#{addr.to_s(16)}" unless off
  bin.byteslice(off, 8).unpack1("Q<")
end

def read_section_bytes(path, section_name)
  out, status = Open3.capture2("readelf", "-x", section_name, "-W", path)
  raise "readelf failed for #{path}" unless status.success?
  bytes = []
  out.each_line do |line|
    next unless line =~ /^\s*0x[0-9a-fA-F]+\s+/
    fields = line.split
    fields.shift
    fields.take_while { |f| f.match?(/\A[0-9a-fA-F]{8}\z/) }.each do |word|
      bytes << [word].pack("H*")
    end
  end
  bytes.join
end

def find_blob_in_binary(bin, blob)
  [64, 128, 256, 512].each do |n|
    needle = blob.byteslice(0, n)
    next unless needle && needle.bytesize == n
    idx = bin.index(needle)
    return [idx, n] if idx
  end
  [nil, nil]
end

def parse_exports_from_binary_without_symbols(path)
  base = File.basename(path, ".dbg")
  exports_obj = File.join(File.dirname(path), "#{base}_exports.o")
  raise "missing #{exports_obj}" unless File.file?(exports_obj)

  exports_syms = parse_readelf_symbols(exports_obj)
  names_off = exports_syms["__cosmo_exports_names"]
  exports_off = exports_syms["__cosmo_exports"]
  raise "missing __cosmo_exports_names in #{exports_obj}" unless names_off
  raise "missing __cosmo_exports in #{exports_obj}" unless exports_off

  names_section = read_section_bytes(exports_obj, ".rodata.cosmo_exports")
  names_blob = names_section.byteslice(names_off, 4096)
  raise "names blob read failed" unless names_blob && names_blob.bytesize >= 64

  bin = File.binread(path)
  names_idx, names_len = find_blob_in_binary(bin, names_blob)
  if names_idx.nil?
    warn "debug: names_off=0x#{names_off.to_s(16)} exports_off=0x#{exports_off.to_s(16)}"
    warn "debug: names_section size=#{names_section.bytesize}"
    warn "debug: names_blob head=#{names_blob.byteslice(0, 32).inspect}"
    warn "debug: names_blob size=#{names_blob.bytesize}"
    warn "debug: binary size=#{bin.bytesize}"
    cosmo_idx = bin.index(".cosmo\0")
    warn "debug: binary has .cosmo at offset=#{cosmo_idx}" if cosmo_idx
    alg_idx = bin.index("AF_ALG\0")
    warn "debug: binary has AF_ALG at offset=#{alg_idx}" if alg_idx
    raise "could not locate export names in binary"
  end
  warn "debug: names_blob matched length=#{names_len} at offset=#{names_idx}"
  exports_idx = names_idx - names_off + exports_off
  raise "exports offset out of range" if exports_idx.negative?

  exports = {}
  entry_size = 16
  idx = 0
  loop do
    off = exports_idx + idx * entry_size
    break if off + entry_size > bin.bytesize
    name_off = bin.byteslice(off, 4).unpack1("V")
    addr = bin.byteslice(off + 8, 8).unpack1("Q<")
    break if name_off == 0 && addr == 0
    name = read_string(bin, names_idx + name_off)
    raise "bad name offset #{name_off}" unless name
    exports[name] = addr
    idx += 1
  end
  exports
end

def parse_readelf_symbols(path)
  out, status = Open3.capture2("readelf", "-s", "-W", path)
  raise "readelf failed for #{path}" unless status.success?

  sym = {}
  out.each_line do |line|
    next unless line =~ /^\s*\d+:\s+([0-9a-fA-F]+)\s+(?:\d+|0x[0-9a-fA-F]+)\s+\S+\s+\S+\s+\S+\s+\S+\s+(.+)$/
    addr = Regexp.last_match(1)
    name = Regexp.last_match(2).strip
    next if name.empty? || name == "<null>"
    next unless addr.match?(/\A[0-9a-fA-F]+\z/)
    sym[name] = addr.to_i(16)
  end
  sym
end

def read_string(blob, offset)
  return nil if offset >= blob.bytesize
  end_idx = blob.index("\0", offset)
  return nil unless end_idx
  blob[offset...end_idx]
end

def parse_exports_from_binary(path)
  bin = File.binread(path)
  sections = read_sections(path)
  symtab = parse_readelf_symbols(path)
  names_addr = symtab["__cosmo_exports_names"]
  exports_addr = symtab["__cosmo_exports"]
  if names_addr.nil? && (names_ptr = symtab["__cosmo_exports_names_start"])
    names_addr = read_ptr64(bin, sections, names_ptr)
  end
  if exports_addr.nil? && (exports_ptr = symtab["__cosmo_exports_start"])
    exports_addr = read_ptr64(bin, sections, exports_ptr)
  end
  if names_addr.nil? || exports_addr.nil?
    return parse_exports_from_binary_without_symbols(path)
  end

  names_sec = section_for_addr(sections, names_addr)
  exports_sec = section_for_addr(sections, exports_addr)
  raise "section not found for __cosmo_exports_names" unless names_sec
  raise "section not found for __cosmo_exports" unless exports_sec

  _nname, naddr, noff, nsize = names_sec
  _ename, eaddr, eoff, esize = exports_sec
  names_blob = bin.byteslice(noff, nsize)
  exports_blob = bin.byteslice(eoff, esize)
  raise "names section read failed" unless names_blob && names_blob.bytesize == nsize
  raise "exports section read failed" unless exports_blob && exports_blob.bytesize == esize

  names_base = names_addr - naddr
  exports_base = exports_addr - eaddr
  if names_base.negative? || exports_base.negative?
    raise "export section offsets are out of range"
  end

  exports = {}
  entry_size = 16
  idx = 0
  loop do
    off = exports_base + idx * entry_size
    break if off + entry_size > exports_blob.bytesize
    name_off = exports_blob.byteslice(off, 4).unpack1("V")
    addr = exports_blob.byteslice(off + 8, 8).unpack1("Q<")
    break if name_off == 0 && addr == 0
    name = read_string(names_blob, names_base + name_off)
    raise "bad name offset #{name_off}" unless name
    exports[name] = addr
    idx += 1
  end
  exports
end

def check_exports(label, binary_path)
  exports = parse_exports_from_binary(binary_path)
  nm_syms = parse_readelf_symbols(binary_path)
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
binary = ARGV.shift

raise "missing --label" unless label
raise "missing #{binary}" unless binary && File.file?(binary)

exit(check_exports(label, binary))
