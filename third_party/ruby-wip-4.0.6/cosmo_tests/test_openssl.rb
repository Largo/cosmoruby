# OpenSSL surface exercise for the CosmoRuby APE.
# Run with:  env -i /path/to/ruby.com /path/to/test_openssl.rb
#
# CosmoRuby has no OpenSSL.  `require "openssl"` loads a compatibility layer
# (third_party/ruby/lib/openssl.rb) built on mbedtls, which is already linked
# into ruby.com for TLS.  This file is the correctness evidence for that
# layer, so it is deliberately built out of *published* test vectors rather
# than round-trips: a round-trip proves only that the code agrees with
# itself, which for cryptography is worth nothing.
#
#   * AES-GCM   -- NIST "The Galois/Counter Mode of Operation (GCM)" spec
#                  test cases 2, 3, 4, 7, 8, 13, 14, 15, 16 (the vectors
#                  SP 800-38D was published with).
#   * AES-CBC   -- NIST SP 800-38A appendix F.2 (128/192/256).
#   * AES-CTR   -- NIST SP 800-38A appendix F.5 (128/256).
#   * HMAC      -- RFC 4231 (SHA-224/256/384/512) and RFC 2202 (SHA-1).
#   * PBKDF2    -- RFC 6070 (HMAC-SHA1) and RFC 7914 section 11 (HMAC-SHA256).
#   * SHA/MD5   -- FIPS 180-2 / RFC 1321 sample digests.
#
# It also carries a block of ciphertexts, tags and derived keys produced by a
# *real* OpenSSL (ruby 3.3.8, OpenSSL 3.x, on the machine this port is
# developed on) so that the APE is checked against another implementation and
# not only against the standards documents.
#
# The whole file runs unchanged on a Ruby with genuine OpenSSL, which is how
# the vectors themselves were validated.

require "openssl"

$failures = 0

def check(desc)
  got = yield
  puts "PASS: #{desc}#{got == true ? "" : " :: #{got.inspect}"}"
rescue => e
  $failures += 1
  puts "FAIL: #{desc} :: #{e.class}: #{e.message}"
  puts e.backtrace.first(3).map { |l| "      #{l}" }
end

def hex(s)  = [s.delete(" \n")].pack("H*")
def unhex(s) = s.unpack1("H*")

def assert_eq(want, got, what)
  return true if want == got
  w = want.is_a?(String) && !want.valid_encoding? ? unhex(want) : want
  g = got.is_a?(String)  && !got.valid_encoding?  ? unhex(got)  : got
  raise "#{what}: want #{w.inspect}, got #{g.inspect}"
end

puts "ruby      = #{RUBY_VERSION} #{RUBY_PLATFORM}"
puts "backend   = #{defined?(MbedTLS) ? "mbedtls (CosmoRuby shim)" : "OpenSSL"}"
puts "ciphers   = #{OpenSSL::Cipher.ciphers.size} algorithms"
puts

# ══════════════════════════════════════════════════════════════════════════
# 1. Digests -- FIPS 180-2 / RFC 1321 samples
# ══════════════════════════════════════════════════════════════════════════

DIGEST_VECTORS = [
  # [algorithm, message, expected hex]
  ["SHA1",   "abc", "a9993e364706816aba3e25717850c26c9cd0d89d"],
  ["SHA256", "abc",
   "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"],
  ["SHA256", "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
   "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"],
  ["SHA384", "abc",
   "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed" \
   "8086072ba1e7cc2358baeca134c825a7"],
  ["SHA512", "abc",
   "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a" \
   "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"],
  ["SHA224", "abc",
   "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7"],
  ["MD5",    "abc", "900150983cd24fb0d6963f7d28e17f72"],
].freeze

check("digest known answers (FIPS 180-2 / RFC 1321)") do
  DIGEST_VECTORS.each do |algo, msg, want|
    got = OpenSSL::Digest.hexdigest(algo, msg)
    assert_eq(want, got, "#{algo}(#{msg[0, 12]})")
  end
  DIGEST_VECTORS.size
end

check("OpenSSL::Digest is a real class hierarchy") do
  # ActiveSupport::KeyGenerator.hash_digest_class= rejects anything that is
  # not a subclass of OpenSSL::Digest, so this is load bearing for Rails.
  raise "Digest is not a Class" unless OpenSSL::Digest.is_a?(Class)
  %w[SHA1 SHA256 SHA384 SHA512 MD5].each do |n|
    k = OpenSSL::Digest.const_get(n)
    raise "#{n} is not a Class" unless k.is_a?(Class)
    raise "#{n} is not < OpenSSL::Digest" unless k < OpenSSL::Digest
  end
  raise "not < Digest::Class" unless OpenSSL::Digest < ::Digest::Class
  raise "subclassing broken" unless Class.new(OpenSSL::Digest) < OpenSSL::Digest
  true
end

check("digest instance API (streaming, dup, reset, lengths, name)") do
  d = OpenSSL::Digest::SHA256.new
  d << "a"
  d.update("b")
  snapshot = d.dup            # must not disturb the running state
  assert_eq("fb8e20fc2e4c3f248c60c39bd652f3c1347298bb977b8b4d5903b85055620603",
            snapshot.hexdigest, "partial 'ab'")
  d << "c"
  assert_eq("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            d.hexdigest, "streamed 'abc'")
  # #hexdigest must be non-destructive
  assert_eq("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            d.hexdigest, "hexdigest is repeatable")
  d.reset
  assert_eq("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            d.hexdigest, "after reset")
  assert_eq(32, OpenSSL::Digest::SHA256.new.digest_length, "digest_length")
  assert_eq(64, OpenSSL::Digest::SHA256.new.block_length, "block_length")
  assert_eq(128, OpenSSL::Digest::SHA512.new.block_length, "sha512 block_length")
  assert_eq("SHA256", OpenSSL::Digest::SHA256.new.name, "name")
  assert_eq("SHA256", OpenSSL::Digest.new("sha256").name, "name from lowercase")
  assert_eq("SHA256", OpenSSL::Digest.new("SHA2-256").name, "name from SHA2-256")
  assert_eq("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            OpenSSL::Digest::SHA256.hexdigest("abc"), "class hexdigest")
  assert_eq(OpenSSL::Digest::SHA256.digest("abc"),
            OpenSSL::Digest.digest("SHA256", "abc"), "digest arg order")
  true
end

check("unknown digest raises") do
  begin
    OpenSSL::Digest.new("not-a-digest")
    raise "expected an exception"
  rescue RuntimeError, OpenSSL::OpenSSLError => e
    e.class
  end
end

# ══════════════════════════════════════════════════════════════════════════
# 2. AES-GCM -- NIST GCM specification test cases
# ══════════════════════════════════════════════════════════════════════════
#
# [name, key, iv, aad, plaintext, ciphertext, tag] -- all hex.

GCM_VECTORS = [
  ["case 2 (AES-128, one zero block)",
   "00000000000000000000000000000000",
   "000000000000000000000000",
   "",
   "00000000000000000000000000000000",
   "0388dace60b6a392f328c2b971b2fe78",
   "ab6e47d42cec13bdf53a67b21257bddf"],

  ["case 3 (AES-128, 64 bytes)",
   "feffe9928665731c6d6a8f9467308308",
   "cafebabefacedbaddecaf888",
   "",
   "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72" \
   "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255",
   "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e" \
   "21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985",
   "4d5c2af327cd64a62cf35abd2ba6fab4"],

  ["case 4 (AES-128, 60 bytes + AAD)",
   "feffe9928665731c6d6a8f9467308308",
   "cafebabefacedbaddecaf888",
   "feedfacedeadbeeffeedfacedeadbeefabaddad2",
   "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72" \
   "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39",
   "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e" \
   "21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091",
   "5bc94fbc3221a5db94fae95ae7121a47"],

  ["case 7 (AES-192, empty)",
   "000000000000000000000000000000000000000000000000",
   "000000000000000000000000",
   "", "", "",
   "cd33b28ac773f74ba00ed1f312572435"],

  ["case 8 (AES-192, one zero block)",
   "000000000000000000000000000000000000000000000000",
   "000000000000000000000000",
   "",
   "00000000000000000000000000000000",
   "98e7247c07f0fe411c267e4384b0f600",
   "2ff58d80033927ab8ef4d4587514f0fb"],

  ["case 13 (AES-256, empty)",
   "0000000000000000000000000000000000000000000000000000000000000000",
   "000000000000000000000000",
   "", "", "",
   "530f8afbc74536b9a963b4f1c4cb738b"],

  ["case 14 (AES-256, one zero block)",
   "0000000000000000000000000000000000000000000000000000000000000000",
   "000000000000000000000000",
   "",
   "00000000000000000000000000000000",
   "cea7403d4d606b6e074ec5d3baf39d18",
   "d0d1c8a799996bf0265b98b5d48ab919"],

  ["case 15 (AES-256, 64 bytes)",
   "feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308",
   "cafebabefacedbaddecaf888",
   "",
   "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72" \
   "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255",
   "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa" \
   "8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662898015ad",
   "b094dac5d93471bdec1a502270e3cc6c"],

  ["case 16 (AES-256, 60 bytes + AAD)",
   "feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308",
   "cafebabefacedbaddecaf888",
   "feedfacedeadbeeffeedfacedeadbeefabaddad2",
   "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72" \
   "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39",
   "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa" \
   "8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662",
   "76fc6ece0f4e1768cddf8853bb2d551b"],
].freeze

def gcm_name_for(key_hex) = "aes-#{key_hex.length * 4}-gcm"

check("AES-GCM encryption known answers (NIST GCM spec)") do
  GCM_VECTORS.each do |name, k, iv, aad, pt, ct, tag|
    c = OpenSSL::Cipher.new(gcm_name_for(k))
    c.encrypt
    c.key = hex(k)
    c.iv  = hex(iv)
    c.auth_data = hex(aad)
    out = c.update(hex(pt)) + c.final
    assert_eq(hex(ct), out, "#{name} ciphertext")
    assert_eq(hex(tag), c.auth_tag, "#{name} tag")
  end
  GCM_VECTORS.size
end

check("AES-GCM decryption known answers (NIST GCM spec)") do
  GCM_VECTORS.each do |name, k, iv, aad, pt, ct, tag|
    c = OpenSSL::Cipher.new(gcm_name_for(k))
    c.decrypt
    c.key = hex(k)
    c.iv  = hex(iv)
    c.auth_data = hex(aad)
    c.auth_tag  = hex(tag)
    out = c.update(hex(ct)) + c.final
    assert_eq(hex(pt), out, "#{name} plaintext")
  end
  GCM_VECTORS.size
end

check("AES-GCM streaming in odd-sized chunks matches one-shot") do
  # mbedtls_gcm_update() only tolerates a partial block on the last call, so
  # the binding has to stage sub-block input itself.  This is that test.
  name, k, iv, aad, pt, ct, tag = GCM_VECTORS[8] # 60-byte case with AAD
  [1, 3, 7, 16, 17, 31, 59].each do |chunk|
    c = OpenSSL::Cipher.new(gcm_name_for(k))
    c.encrypt
    c.key = hex(k)
    c.iv = hex(iv)
    c.auth_data = hex(aad)
    out = +""
    hex(pt).each_char.each_slice(chunk) { |s| out << c.update(s.join) }
    out << c.final
    assert_eq(hex(ct), out, "#{name} chunk=#{chunk} ciphertext")
    assert_eq(hex(tag), c.auth_tag, "#{name} chunk=#{chunk} tag")

    d = OpenSSL::Cipher.new(gcm_name_for(k))
    d.decrypt
    d.key = hex(k)
    d.iv = hex(iv)
    d.auth_data = hex(aad)
    d.auth_tag = hex(tag)
    back = +""
    hex(ct).each_char.each_slice(chunk) { |s| back << d.update(s.join) }
    back << d.final
    assert_eq(hex(pt), back, "#{name} chunk=#{chunk} plaintext")
  end
  true
end

check("AES-GCM properties (block_size 1, authenticated?, iv_len 12)") do
  c = OpenSSL::Cipher.new("aes-256-gcm")
  assert_eq(true, c.authenticated?, "authenticated?")
  assert_eq(1,  c.block_size, "block_size")
  assert_eq(12, c.iv_len, "iv_len")
  assert_eq(32, c.key_len, "key_len")
  assert_eq(false, OpenSSL::Cipher.new("aes-256-cbc").authenticated?, "cbc")
  assert_eq(16, OpenSSL::Cipher.new("aes-256-cbc").block_size, "cbc block")
  true
end

# ══════════════════════════════════════════════════════════════════════════
# 3. AES-CBC and AES-CTR -- NIST SP 800-38A appendix F
# ══════════════════════════════════════════════════════════════════════════

SP80038A_PLAINTEXT =
  "6bc1bee22e409f96e93d7e117393172a" \
  "ae2d8a571e03ac9c9eb76fac45af8e51" \
  "30c81c46a35ce411e5fbc1191a0a52ef" \
  "f69f2445df4f9b17ad2b417be66c3710"

CBC_VECTORS = [
  ["F.2.1 CBC-AES128", "2b7e151628aed2a6abf7158809cf4f3c",
   "000102030405060708090a0b0c0d0e0f",
   "7649abac8119b246cee98e9b12e9197d" \
   "5086cb9b507219ee95db113a917678b2" \
   "73bed6b8e3c1743b7116e69e22229516" \
   "3ff1caa1681fac09120eca307586e1a7"],
  ["F.2.3 CBC-AES192", "8e73b0f7da0e6452c810f32b809079e562f8ead2522c6b7b",
   "000102030405060708090a0b0c0d0e0f",
   "4f021db243bc633d7178183a9fa071e8" \
   "b4d9ada9ad7dedf4e5e738763f69145a" \
   "571b242012fb7ae07fa9baac3df102e0" \
   "08b0e27988598881d920a9e64f5615cd"],
  ["F.2.5 CBC-AES256",
   "603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4",
   "000102030405060708090a0b0c0d0e0f",
   "f58c4c04d6e5f1ba779eabfb5f7bfbd6" \
   "9cfc4e967edb808d679f777bc6702c7d" \
   "39f23369a9d9bacfa530e26304231461" \
   "b2eb05e2c39be9fcda6c19078c6a9d1b"],
].freeze

CTR_VECTORS = [
  ["F.5.1 CTR-AES128", "2b7e151628aed2a6abf7158809cf4f3c",
   "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff",
   "874d6191b620e3261bef6864990db6ce" \
   "9806f66b7970fdff8617187bb9fffdff" \
   "5ae4df3edbd5d35e5b4f09020db03eab" \
   "1e031dda2fbe03d1792170a0f3009cee"],
  ["F.5.5 CTR-AES256",
   "603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4",
   "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff",
   "601ec313775789a5b7a7f504bbf3d228" \
   "f443e3ca4d62b59aca84e990cacaf5c5" \
   "2b0930daa23de94ce87017ba2d84988d" \
   "dfc9c58db67aada613c2dd08457941a6"],
].freeze

check("AES-CBC known answers (NIST SP 800-38A F.2)") do
  CBC_VECTORS.each do |name, k, iv, ct|
    e = OpenSSL::Cipher.new("aes-#{k.length * 4}-cbc")
    e.encrypt
    e.key = hex(k)
    e.iv = hex(iv)
    e.padding = 0   # the vectors are exact multiples of the block size
    assert_eq(hex(ct), e.update(hex(SP80038A_PLAINTEXT)) + e.final,
              "#{name} ciphertext")

    d = OpenSSL::Cipher.new("aes-#{k.length * 4}-cbc")
    d.decrypt
    d.key = hex(k)
    d.iv = hex(iv)
    d.padding = 0
    assert_eq(hex(SP80038A_PLAINTEXT), d.update(hex(ct)) + d.final,
              "#{name} plaintext")
  end
  CBC_VECTORS.size
end

check("AES-CTR known answers (NIST SP 800-38A F.5)") do
  CTR_VECTORS.each do |name, k, ctr, ct|
    e = OpenSSL::Cipher.new("aes-#{k.length * 4}-ctr")
    e.encrypt
    e.key = hex(k)
    e.iv = hex(ctr)
    assert_eq(hex(ct), e.update(hex(SP80038A_PLAINTEXT)) + e.final,
              "#{name} ciphertext")

    d = OpenSSL::Cipher.new("aes-#{k.length * 4}-ctr")
    d.decrypt
    d.key = hex(k)
    d.iv = hex(ctr)
    assert_eq(hex(SP80038A_PLAINTEXT), d.update(hex(ct)) + d.final,
              "#{name} plaintext")
  end
  CTR_VECTORS.size
end

check("AES-CBC PKCS#7 padding round-trip at every offset 0..32") do
  key = hex("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4")
  iv  = hex("000102030405060708090a0b0c0d0e0f")
  (0..32).each do |n|
    msg = "A" * n
    e = OpenSSL::Cipher.new("aes-256-cbc")
    e.encrypt
    e.key = key
    e.iv = iv
    ct = e.update(msg) + e.final
    # PKCS#7 always adds 1..16 bytes, so the ciphertext grows past the input
    expected_len = ((n / 16) + 1) * 16
    assert_eq(expected_len, ct.bytesize, "padded length for #{n} bytes")
    d = OpenSSL::Cipher.new("aes-256-cbc")
    d.decrypt
    d.key = key
    d.iv = iv
    assert_eq(msg, d.update(ct) + d.final, "round-trip #{n} bytes")
  end
  true
end

check("AES-CBC streaming in odd-sized chunks matches one-shot") do
  key = hex("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4")
  iv  = hex("000102030405060708090a0b0c0d0e0f")
  msg = "the quick brown fox jumps over the lazy dog, twice over" * 3
  one = begin
    e = OpenSSL::Cipher.new("aes-256-cbc"); e.encrypt; e.key = key; e.iv = iv
    e.update(msg) + e.final
  end
  [1, 5, 16, 17, 64].each do |chunk|
    e = OpenSSL::Cipher.new("aes-256-cbc"); e.encrypt; e.key = key; e.iv = iv
    out = +""
    msg.each_char.each_slice(chunk) { |s| out << e.update(s.join) }
    out << e.final
    assert_eq(one, out, "chunk=#{chunk} encrypt")

    d = OpenSSL::Cipher.new("aes-256-cbc"); d.decrypt; d.key = key; d.iv = iv
    back = +""
    one.each_char.each_slice(chunk) { |s| back << d.update(s.join) }
    back << d.final
    assert_eq(msg, back, "chunk=#{chunk} decrypt")
  end
  true
end

# ══════════════════════════════════════════════════════════════════════════
# 4. Negative cases -- these MUST raise, not return plausible garbage
# ══════════════════════════════════════════════════════════════════════════

check("tampered GCM tag raises instead of returning plaintext") do
  key = OpenSSL::Random.random_bytes(32)
  iv  = OpenSSL::Random.random_bytes(12)
  e = OpenSSL::Cipher.new("aes-256-gcm")
  e.encrypt; e.key = key; e.iv = iv; e.auth_data = "hdr"
  ct = e.update("attack at dawn") + e.final
  tag = e.auth_tag

  raised = 0
  16.times do |i|
    bad = tag.dup
    bad.setbyte(i, bad.getbyte(i) ^ 0x80)
    d = OpenSSL::Cipher.new("aes-256-gcm")
    d.decrypt; d.key = key; d.iv = iv; d.auth_data = "hdr"; d.auth_tag = bad
    begin
      out = d.update(ct) + d.final
      raise "byte #{i}: no exception, returned #{out.inspect}"
    rescue OpenSSL::Cipher::CipherError
      raised += 1
    end
  end
  assert_eq(16, raised, "every tampered tag byte rejected")
end

check("tampered GCM ciphertext raises") do
  key = OpenSSL::Random.random_bytes(32)
  iv  = OpenSSL::Random.random_bytes(12)
  e = OpenSSL::Cipher.new("aes-256-gcm")
  e.encrypt; e.key = key; e.iv = iv
  ct = e.update("attack at dawn") + e.final
  tag = e.auth_tag
  bad = ct.dup
  bad.setbyte(0, bad.getbyte(0) ^ 0x01)
  d = OpenSSL::Cipher.new("aes-256-gcm")
  d.decrypt; d.key = key; d.iv = iv; d.auth_tag = tag
  begin
    out = d.update(bad) + d.final
    raise "no exception, returned #{out.inspect}"
  rescue OpenSSL::Cipher::CipherError => e2
    e2.class
  end
end

check("tampered GCM AAD raises") do
  key = OpenSSL::Random.random_bytes(32)
  iv  = OpenSSL::Random.random_bytes(12)
  e = OpenSSL::Cipher.new("aes-256-gcm")
  e.encrypt; e.key = key; e.iv = iv; e.auth_data = "header-v1"
  ct = e.update("payload") + e.final
  tag = e.auth_tag
  d = OpenSSL::Cipher.new("aes-256-gcm")
  d.decrypt; d.key = key; d.iv = iv; d.auth_data = "header-v2"; d.auth_tag = tag
  begin
    d.update(ct) + d.final
    raise "no exception"
  rescue OpenSSL::Cipher::CipherError => e2
    e2.class
  end
end

check("wrong key length raises") do
  raised = []
  [["aes-256-gcm", 31], ["aes-256-gcm", 33], ["aes-128-cbc", 32],
   ["aes-256-cbc", 16], ["aes-256-ctr", 8]].each do |name, len|
    c = OpenSSL::Cipher.new(name)
    c.encrypt
    begin
      c.key = "k" * len
      raise "#{name}: accepted a #{len}-byte key"
    rescue ArgumentError => e2
      raised << "#{name}/#{len}"
    end
  end
  raised.size
end

check("wrong iv length raises for fixed-iv modes") do
  c = OpenSSL::Cipher.new("aes-256-cbc")
  c.encrypt
  begin
    c.iv = "i" * 12
    raise "accepted a 12-byte CBC iv"
  rescue ArgumentError => e2
    e2.class
  end
end

check("truncated CBC ciphertext raises") do
  key = OpenSSL::Random.random_bytes(32)
  iv  = OpenSSL::Random.random_bytes(16)
  e = OpenSSL::Cipher.new("aes-256-cbc")
  e.encrypt; e.key = key; e.iv = iv
  ct = e.update("a message that spans several blocks of ciphertext") + e.final
  [1, 5, 15, 17, ct.bytesize - 1].each do |n|
    d = OpenSSL::Cipher.new("aes-256-cbc")
    d.decrypt; d.key = key; d.iv = iv
    begin
      d.update(ct[0, n]) + d.final
      raise "truncation to #{n} bytes was accepted"
    rescue OpenSSL::Cipher::CipherError
      # expected
    end
  end
  true
end

check("corrupt CBC padding raises") do
  key = OpenSSL::Random.random_bytes(32)
  iv  = OpenSSL::Random.random_bytes(16)
  e = OpenSSL::Cipher.new("aes-256-cbc")
  e.encrypt; e.key = key; e.iv = iv
  ct = e.update("padded message") + e.final
  bad = ct.dup
  bad.setbyte(0, bad.getbyte(0) ^ 0xff)  # garbles the final block's padding
  d = OpenSSL::Cipher.new("aes-256-cbc")
  d.decrypt; d.key = key; d.iv = iv
  begin
    d.update(bad) + d.final
    raise "no exception"
  rescue OpenSSL::Cipher::CipherError => e2
    e2.class
  end
end

check("decrypting with the wrong key fails (GCM authenticates)") do
  key = OpenSSL::Random.random_bytes(32)
  iv  = OpenSSL::Random.random_bytes(12)
  e = OpenSSL::Cipher.new("aes-256-gcm")
  e.encrypt; e.key = key; e.iv = iv
  ct = e.update("top secret") + e.final
  tag = e.auth_tag
  d = OpenSSL::Cipher.new("aes-256-gcm")
  d.decrypt; d.key = OpenSSL::Random.random_bytes(32); d.iv = iv; d.auth_tag = tag
  begin
    d.update(ct) + d.final
    raise "no exception"
  rescue OpenSSL::Cipher::CipherError => e2
    e2.class
  end
end

check("unsupported cipher raises") do
  begin
    OpenSSL::Cipher.new("aes-256-nonsense")
    raise "expected an exception"
  rescue RuntimeError, OpenSSL::OpenSSLError => e2
    e2.class
  end
end

# ══════════════════════════════════════════════════════════════════════════
# 5. HMAC -- RFC 4231 and RFC 2202
# ══════════════════════════════════════════════════════════════════════════

# [name, key hex, data (String or :hex prefixed), sha1, sha224, sha256,
#  sha384, sha512] -- nil where the RFC does not give a value.
HMAC_VECTORS = [
  ["RFC 4231 case 1",
   "0b" * 20, "Hi There",
   "b617318655057264e28bc0b6fb378c8ef146be00",
   "896fb1128abbdf196832107cd49df33f47b4b1169912ba4f53684b22",
   "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
   "afd03944d84895626b0825f4ab46907f15f9dadbe4101ec682aa034c7cebc59c" \
   "faea9ea9076ede7f4af152e8b2fa9cb6",
   "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cde" \
   "daa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854"],

  ["RFC 4231 case 2 (short key)",
   "4a656665", "what do ya want for nothing?",
   "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79",
   "a30e01098bc6dbbf45690f3a7e9e6d0f8bbea2a39e6148008fd05e44",
   "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
   "af45d2e376484031617f78d2b58a6b1b9c7ef464f5a01b47e42ec3736322445e" \
   "8e2240ca5e69e2c78b3239ecfab21649",
   "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea250554" \
   "9758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737"],

  ["RFC 4231 case 3 (all 0xdd data)",
   "aa" * 20, :hex_dd50,
   "125d7342b9ac11cd91a39af48aa17b4f63f175d3",
   "7fb3cb3588c6c1f6ffa9694d7d6ad2649365b0c1f65d69d1ec8333ea",
   "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe",
   "88062608d3e6ad8a0aa2ace014c8a86f0aa635d947ac9febe83ef4e55966144b" \
   "2a5ab39dc13814b94e3ab6e101a34f27",
   "fa73b0089d56a284efb0f0756c890be9b1b5dbdd8ee81a3655f83e33b2279d39" \
   "bf3e848279a722c806b485a47e67c807b946a337bee8942674278859e13292fb"],

  ["RFC 4231 case 4 (0x01..0x19 key)",
   "0102030405060708090a0b0c0d0e0f10111213141516171819", :hex_cd50,
   "4c9007f4026250c6bc8414f9bf50c86c2d7235da",
   "6c11506874013cac6a2abc1bb382627cec6a90d86efc012de7afec5a",
   "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b",
   "3e8a69b7783c25851933ab6290af6ca77a9981480850009cc5577c6e1f573b4e" \
   "6801dd23c4a7d679ccf8a386c674cffb",
   "b0ba465637458c6990e5a8c5f61d4af7e576d97ff94b872de76f8050361ee3db" \
   "a91ca5c11aa25eb4d679275cc5788063a5f19741120c4f2de2adebeb10a298dd"],

  ["RFC 4231 case 6 (131-byte key)",
   "aa" * 131, "Test Using Larger Than Block-Size Key - Hash Key First",
   nil,
   "95e9a0db962095adaebe9b2d6f0dbce2d499f112f2d2b7273fa6870e",
   "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54",
   "4ece084485813e9088d2c63a041bc5b44f9ef1012a2b588f3cd11f05033ac4c6" \
   "0c2ef6ab4030fe8296248df163f44952",
   "80b24263c7c1a3ebb71493c1dd7be8b49b46d1f41b4aeec1121b013783f8f352" \
   "6b56d037e05f2598bd0fd2215d6a1e5295e64f73f63f0aec8b915a985d786598"],

  ["RFC 4231 case 7 (131-byte key, long data)",
   "aa" * 131,
   "This is a test using a larger than block-size key and a larger " \
   "than block-size data. The key needs to be hashed before being " \
   "used by the HMAC algorithm.",
   nil,
   "3a854166ac5d9f023f54d517d0b39dbd946770db9c2b95c9f6f565d1",
   "9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2",
   "6617178e941f020d351e2f254e8fd32c602420feb0b8fb9adccebb82461e99c5" \
   "a678cc31e799176d3860e6110c46523e",
   "e37b6a775dc87dbaa4dfa9f96e5e3ffddebd71f8867289865df5a32d20cdc944" \
   "b6022cac3c4982b10d5eeb55c3e4de15134676fb6de0446065c97440fa8c6a58"],
].freeze

def hmac_data(spec)
  case spec
  when :hex_dd50 then "\xdd".b * 50
  when :hex_cd50 then "\xcd".b * 50
  else spec.b
  end
end

check("HMAC known answers (RFC 4231 / RFC 2202)") do
  n = 0
  HMAC_VECTORS.each do |name, key_hex, data_spec, *digests|
    key = hex(key_hex)
    data = hmac_data(data_spec)
    %w[SHA1 SHA224 SHA256 SHA384 SHA512].each_with_index do |algo, i|
      want = digests[i]
      next unless want
      assert_eq(want, OpenSSL::HMAC.hexdigest(algo, key, data),
                "#{name} HMAC-#{algo}")
      assert_eq(hex(want), OpenSSL::HMAC.digest(algo, key, data),
                "#{name} HMAC-#{algo} (binary)")
      # digest object instead of a name
      assert_eq(want,
                OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new(algo), key, data),
                "#{name} HMAC-#{algo} (digest instance)")
      n += 1
    end
  end
  n
end

check("HMAC instance API (streaming, non-destructive digest, reset, dup)") do
  key = hex("0b" * 20)
  h = OpenSSL::HMAC.new(key, "SHA256")
  h << "Hi "
  half = h.dup
  h.update("There")
  want = "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
  assert_eq(want, h.hexdigest, "streamed")
  assert_eq(want, h.hexdigest, "digest is repeatable (non-destructive)")
  half << "There"
  assert_eq(want, half.hexdigest, "dup carried the HMAC state")
  h.reset
  h << "Hi There"
  assert_eq(want, h.hexdigest, "after reset")
  assert_eq(hex(want), h.digest, "binary digest")
  assert_eq([hex(want)].pack("m0"), h.base64digest, "base64digest")
  true
end

# ══════════════════════════════════════════════════════════════════════════
# 6. PBKDF2 -- RFC 6070 (SHA-1) and RFC 7914 section 11 (SHA-256)
# ══════════════════════════════════════════════════════════════════════════

PBKDF2_SHA1_VECTORS = [
  ["password", "salt", 1, 20, "0c60c80f961f0e71f3a9b524af6012062fe037a6"],
  ["password", "salt", 2, 20, "ea6c014dc72d6f8ccd1ed92ace1d41f0d8de8957"],
  ["password", "salt", 4096, 20, "4b007901b765489abead49d926f721d065a429c1"],
  ["passwordPASSWORDpassword", "saltSALTsaltSALTsaltSALTsaltSALTsalt",
   4096, 25, "3d2eec4fe41c849b80c8d83662c0e44a8b291a964cf2f07038"],
  ["pass\0word", "sa\0lt", 4096, 16, "56fa6aa75548099dcc37d7f03425e0c3"],
].freeze

PBKDF2_SHA256_VECTORS = [
  ["passwd", "salt", 1, 64,
   "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc" \
   "49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783"],
  ["Password", "NaCl", 80000, 64,
   "4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56" \
   "a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d"],
].freeze

check("PBKDF2-HMAC-SHA1 known answers (RFC 6070)") do
  PBKDF2_SHA1_VECTORS.each do |pass, salt, iter, len, want|
    assert_eq(hex(want),
              OpenSSL::KDF.pbkdf2_hmac(pass, salt: salt, iterations: iter,
                                             length: len, hash: "SHA1"),
              "KDF pbkdf2 #{pass.inspect}/#{iter}")
    assert_eq(hex(want),
              OpenSSL::PKCS5.pbkdf2_hmac(pass, salt, iter, len, "SHA1"),
              "PKCS5 pbkdf2 #{pass.inspect}/#{iter}")
    assert_eq(hex(want),
              OpenSSL::PKCS5.pbkdf2_hmac_sha1(pass, salt, iter, len),
              "PKCS5 pbkdf2_hmac_sha1 #{pass.inspect}/#{iter}")
  end
  PBKDF2_SHA1_VECTORS.size
end

check("PBKDF2-HMAC-SHA256 known answers (RFC 7914 section 11)") do
  PBKDF2_SHA256_VECTORS.each do |pass, salt, iter, len, want|
    assert_eq(hex(want),
              OpenSSL::KDF.pbkdf2_hmac(pass, salt: salt, iterations: iter,
                                             length: len, hash: "SHA256"),
              "pbkdf2-sha256 #{pass.inspect}/#{iter}")
  end
  PBKDF2_SHA256_VECTORS.size
end

check("PBKDF2 accepts a digest instance and an odd output length") do
  want = hex("0c60c80f961f0e71f3a9b524af6012062fe037a6")
  got = OpenSSL::KDF.pbkdf2_hmac("password", salt: "salt", iterations: 1,
                                 length: 20, hash: OpenSSL::Digest.new("SHA1"))
  assert_eq(want, got, "digest instance")
  # Non-multiple of the digest size exercises the final partial block.
  short = OpenSSL::KDF.pbkdf2_hmac("password", salt: "salt", iterations: 1,
                                   length: 13, hash: "SHA1")
  assert_eq(want[0, 13], short, "truncated output")
  long = OpenSSL::KDF.pbkdf2_hmac("password", salt: "salt", iterations: 1,
                                  length: 45, hash: "SHA1")
  assert_eq(want, long[0, 20], "prefix property")
  assert_eq(45, long.bytesize, "length honoured")
  true
end

# ══════════════════════════════════════════════════════════════════════════
# 7. secure compare
# ══════════════════════════════════════════════════════════════════════════

check("fixed_length_secure_compare / secure_compare") do
  a = "0123456789abcdef"
  raise "equal strings compared false" unless
    OpenSSL.fixed_length_secure_compare(a, a.dup)
  raise "different strings compared true" if
    OpenSSL.fixed_length_secure_compare(a, "0123456789abcdeF")
  begin
    OpenSSL.fixed_length_secure_compare("short", "much longer string")
    raise "length mismatch was accepted"
  rescue ArgumentError
    # expected
  end
  raise "secure_compare equal failed" unless OpenSSL.secure_compare("x" * 40, "x" * 40)
  raise "secure_compare unequal passed" if OpenSSL.secure_compare("abc", "abcd")
  raise "secure_compare unequal passed" if OpenSSL.secure_compare("abc", "abd")
  true
end

# ══════════════════════════════════════════════════════════════════════════
# 8. Randomness
# ══════════════════════════════════════════════════════════════════════════

check("OpenSSL::Random / random_key / random_iv") do
  a = OpenSSL::Random.random_bytes(32)
  b = OpenSSL::Random.random_bytes(32)
  assert_eq(32, a.bytesize, "length")
  raise "two 32-byte draws were identical" if a == b
  raise "all-zero output" if a == "\0".b * 32

  c = OpenSSL::Cipher.new("aes-256-gcm")
  c.encrypt
  k = c.random_key
  iv = c.random_iv
  assert_eq(32, k.bytesize, "random_key length")
  assert_eq(12, iv.bytesize, "random_iv length")
  # random_key/random_iv must also install what they generated
  ct = c.update("ping") + c.final
  d = OpenSSL::Cipher.new("aes-256-gcm")
  d.decrypt; d.key = k; d.iv = iv; d.auth_tag = c.auth_tag
  assert_eq("ping", d.update(ct) + d.final, "random_key/iv were installed")

  # crude sanity: 4096 random bytes should hit most byte values
  seen = OpenSSL::Random.random_bytes(4096).bytes.uniq.size
  raise "only #{seen} distinct byte values in 4096 bytes" if seen < 200
  seen
end

# ══════════════════════════════════════════════════════════════════════════
# 9. Cross-implementation fixtures
# ══════════════════════════════════════════════════════════════════════════
#
# Produced by a real OpenSSL (ruby 3.3.8 / OpenSSL 3.x).  Decrypting these
# inside the APE is what proves wire-format compatibility -- it is the same
# property that makes a Rails credentials file written on a developer's
# machine readable by a packaged CosmoRuby binary.  The tools/regenerate
# recipe is in PORTING-NOTES.md.

# Recorded with: ruby 3.3.8 / OpenSSL 3.5.0 (see PORTING-NOTES.md for the
# one-liner that regenerates them).
HOST_KEY     = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
HOST_GCM_IV  = "0f0e0d0c0b0a090807060504"
HOST_CBC_IV  = "0f0e0d0c0b0a09080706050403020100"
HOST_AAD     = "header-v1"
HOST_PT      = "Rails-style message, encrypted by a real OpenSSL."
HOST_GCM_CT  = "f651d83028fadcda92b3d47f55fffa7208017a4cef3c9f072430de8b576e9048" \
               "7daaa260592c1ae200fa5c88fd5f7b4939"
HOST_GCM_TAG = "3b1a36c833e34c6495d029b30b6fb6ca"
HOST_CBC_CT  = "1be16faf56b676222b02b8fa5abd2889d889f3fb7376131b09e11ef132122994" \
               "24c94050eae2ab54003bbff742ae91ed45844d130c00800b69acd22ac559e66d"
HOST_PBKDF2  = "f7f9a977539f5f4719258fd5603db03feb54a1080c01865b395f4ecd705903ff" \
               "870ec18b6954a18ff67d302839a781a1"
HOST_HMAC    = "d09e139f226ee3c16edf602d6572fcad9e345ea3c2d9a0dd46237f22fc530d19" \
               "6b5f1bd467f081cdd3a9719b4586cc9de27c2aef9533c5a72a682351436e3496"

check("host-produced AES-256-GCM ciphertext decrypts here (and re-encrypts identically)") do
  key = hex(HOST_KEY)
  iv  = hex(HOST_GCM_IV)
  aad = HOST_AAD
  pt  = HOST_PT
  ct  = hex(HOST_GCM_CT)
  tag = hex(HOST_GCM_TAG)

  d = OpenSSL::Cipher.new("aes-256-gcm")
  d.decrypt; d.key = key; d.iv = iv; d.auth_data = aad; d.auth_tag = tag
  assert_eq(pt, d.update(ct) + d.final, "decrypt host ciphertext")

  e = OpenSSL::Cipher.new("aes-256-gcm")
  e.encrypt; e.key = key; e.iv = iv; e.auth_data = aad
  assert_eq(ct, e.update(pt) + e.final, "re-encrypt matches host byte for byte")
  assert_eq(tag, e.auth_tag, "tag matches host byte for byte")
  true
end

check("host-produced AES-256-CBC ciphertext decrypts here (and re-encrypts identically)") do
  key = hex(HOST_KEY)
  iv  = hex(HOST_CBC_IV)
  pt  = HOST_PT
  ct  = hex(HOST_CBC_CT)

  d = OpenSSL::Cipher.new("aes-256-cbc")
  d.decrypt; d.key = key; d.iv = iv
  assert_eq(pt, d.update(ct) + d.final, "decrypt host ciphertext")

  e = OpenSSL::Cipher.new("aes-256-cbc")
  e.encrypt; e.key = key; e.iv = iv
  assert_eq(ct, e.update(pt) + e.final, "re-encrypt matches host byte for byte")
  true
end

check("host-produced PBKDF2 keys and HMACs match") do
  assert_eq(hex(HOST_PBKDF2),
            OpenSSL::KDF.pbkdf2_hmac("correct horse battery staple",
                                     salt: "cosmoruby", iterations: 20000,
                                     length: 48, hash: "SHA256"),
            "pbkdf2-sha256/20000")
  assert_eq(HOST_HMAC,
            OpenSSL::HMAC.hexdigest("SHA512", "cosmo-key", "cosmo-message"),
            "hmac-sha512")
  true
end

# ══════════════════════════════════════════════════════════════════════════
# 10. The shape ActiveSupport::MessageEncryptor actually uses
# ══════════════════════════════════════════════════════════════════════════
#
# Rails is not available on the CI runners, so this reproduces
# MessageEncryptor's exact call sequence (KeyGenerator PBKDF2 -> AES-256-GCM
# with a random iv and a base64 "payload--iv--tag" envelope) directly on the
# OpenSSL surface.  If this passes, MessageEncryptor works; the real Rails
# round-trip is exercised separately and recorded in PORTING-NOTES.md.

require "base64"

check("ActiveSupport::MessageEncryptor call sequence (AES-256-GCM)") do
  secret = "a" * 64
  key = OpenSSL::KDF.pbkdf2_hmac(secret, salt: "encrypted cookie",
                                 iterations: 1000, length: 32,
                                 hash: OpenSSL::Digest::SHA256.new)
  message = '{"_rails":{"message":"aGVsbG8=","exp":null,"pur":null}}'

  cipher = OpenSSL::Cipher.new("aes-256-gcm")
  cipher.encrypt
  cipher.key = key
  iv = cipher.random_iv
  cipher.auth_data = ""
  encrypted = cipher.update(message) + cipher.final
  envelope = [encrypted, iv, cipher.auth_tag].map { |p| Base64.strict_encode64(p) }.join("--")

  parts = envelope.split("--").map { |p| Base64.strict_decode64(p) }
  d = OpenSSL::Cipher.new("aes-256-gcm")
  d.decrypt
  d.key = key
  d.iv = parts[1]
  d.auth_tag = parts[2]
  d.auth_data = ""
  assert_eq(message, d.update(parts[0]) + d.final, "round-trip")

  # A flipped bit anywhere in the envelope must be refused.
  bad = parts.dup
  bad[2] = bad[2].dup.tap { |t| t.setbyte(0, t.getbyte(0) ^ 1) }
  d2 = OpenSSL::Cipher.new("aes-256-gcm")
  d2.decrypt; d2.key = key; d2.iv = bad[1]; d2.auth_tag = bad[2]; d2.auth_data = ""
  begin
    d2.update(bad[0]) + d2.final
    raise "tampered envelope was accepted"
  rescue OpenSSL::Cipher::CipherError
    # expected
  end
  true
end

check("ActiveSupport::MessageEncryptor call sequence (AES-256-CBC + HMAC)") do
  secret = "b" * 64
  key = OpenSSL::KDF.pbkdf2_hmac(secret, salt: "signed encrypted cookie",
                                 iterations: 1000, length: 32, hash: "SHA256")
  sign_key = OpenSSL::KDF.pbkdf2_hmac(secret, salt: "signed encrypted cookie",
                                      iterations: 1000, length: 64,
                                      hash: "SHA256")
  message = "the quick brown fox"

  cipher = OpenSSL::Cipher.new("aes-256-cbc")
  cipher.encrypt
  cipher.key = key
  iv = cipher.random_iv
  encrypted = cipher.update(message) + cipher.final
  blob = [encrypted, iv].map { |p| Base64.strict_encode64(p) }.join("--")
  signed = "#{blob}--#{OpenSSL::HMAC.hexdigest("SHA256", sign_key, blob)}"

  data, sig = signed.split("--").last(2)
  body = signed[0, signed.rindex("--")]
  raise "signature mismatch" unless
    OpenSSL.fixed_length_secure_compare(
      OpenSSL::HMAC.hexdigest("SHA256", sign_key, body), sig)

  parts = body.split("--").map { |p| Base64.strict_decode64(p) }
  d = OpenSSL::Cipher.new("aes-256-cbc")
  d.decrypt
  d.key = key
  d.iv = parts[1]
  assert_eq(message, d.update(parts[0]) + d.final, "round-trip")
  true
end

# ══════════════════════════════════════════════════════════════════════════
# 11. Things that are deliberately absent must say so
# ══════════════════════════════════════════════════════════════════════════

if defined?(MbedTLS)
  check("unimplemented operations raise NotImplementedError, never fake a result") do
    checks = [
      -> { OpenSSL::PKey::RSA.new(2048) },
      -> { OpenSSL::PKey::RSA.generate(2048) },
      -> { OpenSSL::PKey.read("junk") },
      -> { OpenSSL::KDF.hkdf("x", salt: "s", info: "i", length: 32, hash: "SHA256") },
      -> { OpenSSL::KDF.scrypt("x", salt: "s", N: 2, r: 1, p: 1, length: 32) },
      -> { OpenSSL::Cipher.new("aes-256-cbc").pkcs5_keyivgen("pw") },
    ]
    checks.each_with_index do |fn, i|
      begin
        fn.call
        raise "check #{i} returned instead of raising"
      rescue NotImplementedError
        # expected
      end
    end
    checks.size
  end
end

puts
puts "RESULT: failures=#{$failures}"
exit($failures.zero? ? 0 : 1)
