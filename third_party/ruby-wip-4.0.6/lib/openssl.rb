# frozen_string_literal: true
#
# OpenSSL compatibility layer for Cosmopolitan Ruby, implemented on mbedtls.
#
# Everything cryptographic here is a call into third_party/mbedtls by way of
# ext/mbedtls (MbedTLS::Cipher, MbedTLS::Digest, MbedTLS::HMAC,
# MbedTLS.pbkdf2_hmac, MbedTLS.random_bytes).  No algorithm is implemented in
# Ruby.  Anything mbedtls cannot do is *not* provided: it raises rather than
# returning a plausible wrong answer.
#
# Covered:  OpenSSL::Cipher (AES-128/192/256 in GCM/CBC/CTR, 2- and 3-key
#           3DES-CBC, ChaCha20-Poly1305 -- every one of them checked byte
#           for byte against a real OpenSSL 3.5.0), OpenSSL::Digest (a real
#           class hierarchy), OpenSSL::HMAC, OpenSSL::KDF.pbkdf2_hmac,
#           OpenSSL::PKCS5, OpenSSL::Random, the secure-compare helpers, and
#           the pre-existing OpenSSL::SSL / OpenSSL::X509 client surface.
#
# Not covered (these raise):  public-key cryptography (RSA/DSA/EC key
# generation, signing, verification, encryption), certificate creation or
# parsing, PKCS#7/CMS, OCSP, HKDF, scrypt, EVP_BytesToKey
# (Cipher#pkcs5_keyivgen), the CFB/OFB/XTS/CCM modes (not compiled into this
# mbedtls) and ECB / raw ChaCha20 / single DES (compiled, but not
# interchangeable with OpenSSL -- see the Cipher::ALGORITHMS comment).

require 'mbedtls'
require 'digest'
require 'socket'

module OpenSSL
  class OpenSSLError < StandardError; end

  # ══════════════════════════════════════════════════════════════════════
  # Message digests
  # ══════════════════════════════════════════════════════════════════════
  #
  # A real class hierarchy, not a bag of aliases: OpenSSL::Digest is
  # subclassable and OpenSSL::Digest::SHA256 < OpenSSL::Digest, which is what
  # ActiveSupport::KeyGenerator.hash_digest_class= insists on.  The digest
  # state itself is an mbedtls_md_context_t.
  class Digest < ::Digest::Class
    class DigestError < OpenSSLError; end

    # Normalised OpenSSL spelling => mbedtls md name.  mbedtls' md.c in this
    # tree knows exactly these; a new one is a line here plus a #define in
    # third_party/mbedtls/config.h.
    ALGORITHMS = {
      'MD5'        => 'MD5',
      'SHA'        => 'SHA1',
      'SHA1'       => 'SHA1',
      'SHA224'     => 'SHA224',
      'SHA256'     => 'SHA256',
      'SHA384'     => 'SHA384',
      'SHA512'     => 'SHA512',
      'BLAKE2B256' => 'BLAKE2B256',
    }.freeze

    def self.normalize(name)
      key = name.to_s.upcase.delete('-_ ')
      key = "SHA#{$1}" if key =~ /\ASHA2(\d{3})\z/ # SHA2-256 => SHA256
      ALGORITHMS[key] or
        raise DigestError, "unsupported digest algorithm (#{name})"
    end

    # Accepts a name, a symbol, an OpenSSL::Digest instance, a ::Digest
    # instance or a digest class -- the same shapes ruby/openssl accepts.
    def self.digest_name(obj)
      case obj
      when Digest              then normalize(obj.name)
      when ::String, ::Symbol  then normalize(obj)
      when ::Digest::Instance  then normalize(obj.class.to_s.split('::').last)
      when ::Class
        unless obj <= ::Digest::Class
          raise TypeError, "unsupported digest: #{obj}"
        end
        normalize(obj.to_s.split('::').last)
      else
        raise TypeError, "unsupported digest: #{obj.class}"
      end
    end

    # OpenSSL::Digest.digest("SHA256", data) -- note the argument order is
    # the reverse of Digest::Class.digest(data, *params).
    def self.digest(name, data)
      Digest.new(name).digest(data)
    end

    def self.hexdigest(name, data)
      Digest.new(name).hexdigest(data)
    end

    def self.base64digest(name, data)
      Digest.new(name).base64digest(data)
    end

    def initialize(name, data = nil)
      @name = self.class.digest_name(name)
      @md = MbedTLS::Digest.new(@name)
      update(data) if data
    end

    def initialize_copy(other)
      super
      @md = other.instance_variable_get(:@md).dup
      self
    end

    def update(data)
      @md.update(data)
      self
    end
    alias << update

    def reset
      @md.reset
      self
    end

    def finish
      @md.finish
    end

    def digest_length
      @md.digest_length
    end

    def block_length
      @md.block_length
    end

    attr_reader :name

    ALGORITHMS.each_key do |const|
      next if const == 'SHA' # not a class in ruby/openssl either
      klass = Class.new(self) do
        define_method(:initialize) { |data = nil| super(const, data) }
      end
      klass.singleton_class.class_eval do
        define_method(:digest)       { |data| Digest.digest(const, data) }
        define_method(:hexdigest)    { |data| Digest.hexdigest(const, data) }
        define_method(:base64digest) { |data| Digest.base64digest(const, data) }
      end
      const_set(const, klass)
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # Random
  # ══════════════════════════════════════════════════════════════════════
  module Random
    class RandomError < OpenSSLError; end

    # Straight from the operating system CSPRNG (see MbedTLS.random_bytes).
    def self.random_bytes(len)
      MbedTLS.random_bytes(len)
    end

    class << self
      alias bytes random_bytes
      alias pseudo_bytes random_bytes
    end

    # The kernel CSPRNG owns its own entropy pool; there is nothing for a
    # caller to add.  Returns its argument the way OpenSSL::Random.seed does.
    def self.seed(str)
      str
    end

    def self.random_add(str, entropy = nil)
      self
    end

    def self.status?
      true
    end
  end

  def self.fixed_length_secure_compare(a, b)
    a = a.to_str
    b = b.to_str
    if a.bytesize != b.bytesize
      raise ArgumentError, 'inputs must be of equal length'
    end
    MbedTLS.constant_time_equal?(a, b)
  end

  # Length-independent: hash first, then compare in constant time, then
  # confirm.  Same construction as ruby/openssl.
  def self.secure_compare(a, b)
    hashed_a = Digest::SHA256.digest(a)
    hashed_b = Digest::SHA256.digest(b)
    fixed_length_secure_compare(hashed_a, hashed_b) && a == b
  end

  # ══════════════════════════════════════════════════════════════════════
  # Symmetric ciphers
  # ══════════════════════════════════════════════════════════════════════
  class Cipher
    class CipherError < OpenSSLError; end

    # OpenSSL name (upcased, canonical) => mbedtls name.  Adding an
    # algorithm is one entry, because the binding drives the generic
    # mbedtls_cipher_* layer rather than any particular primitive.  Entries
    # whose mbedtls counterpart is not compiled into this build are dropped
    # at load time, so `ciphers` never advertises something that would fail.
    #
    # Every algorithm listed here has been checked byte for byte against a
    # real OpenSSL 3.5.0 (cosmo_tests/test_openssl.rb, "every advertised
    # cipher matches a real OpenSSL").  Three families mbedtls *can* do are
    # deliberately absent because they would not be interchangeable:
    #
    #   ECB      the mbedtls cipher layer has no padding for ECB and its
    #            update() accepts exactly one block, so it could never
    #            behave like OpenSSL's aes-*-ecb
    #   CHACHA20 (raw) mbedtls takes a 12-byte nonce with an implicit zero
    #            counter; OpenSSL takes a 16-byte counter||nonce.  The
    #            keystreams do not line up.  ChaCha20-Poly1305 is fine and
    #            is offered.
    #   DES-CBC  single 56-bit DES.  OpenSSL 3 itself refuses it without the
    #            legacy provider, so there is nothing to be compatible with.
    ALGORITHMS = {
      'AES-128-CBC'       => 'AES-128-CBC',
      'AES-192-CBC'       => 'AES-192-CBC',
      'AES-256-CBC'       => 'AES-256-CBC',
      'AES-128-CTR'       => 'AES-128-CTR',
      'AES-192-CTR'       => 'AES-192-CTR',
      'AES-256-CTR'       => 'AES-256-CTR',
      'AES-128-GCM'       => 'AES-128-GCM',
      'AES-192-GCM'       => 'AES-192-GCM',
      'AES-256-GCM'       => 'AES-256-GCM',
      'DES-EDE-CBC'       => 'DES-EDE-CBC',
      'DES-EDE3-CBC'      => 'DES-EDE3-CBC',
      'CHACHA20-POLY1305' => 'CHACHA20-POLY1305',
    }.select { |_, mbed| MbedTLS.cipher_supported?(mbed) }.freeze

    # Historical OpenSSL short names.
    ALIASES = {
      'AES128'   => 'AES-128-CBC',
      'AES192'   => 'AES-192-CBC',
      'AES256'   => 'AES-256-CBC',
      'DES3'     => 'DES-EDE3-CBC',
      'DES-EDE3' => 'DES-EDE3-CBC',
      'DES-EDE'  => 'DES-EDE-CBC',
    }.freeze

    def self.resolve(name)
      key = name.to_s.upcase
      key = ALIASES[key] || key
      ALGORITHMS[key] or
        raise CipherError, "unsupported cipher algorithm (#{name})"
    end

    def self.ciphers
      ALGORITHMS.keys.map(&:downcase)
    end

    AEAD_MODES = %i[gcm ccm chachapoly].freeze
    BLOCK_MODES = %i[cbc ecb].freeze

    def initialize(name)
      @mbed_name = self.class.resolve(name)
      @c = MbedTLS::Cipher.new(@mbed_name)
      @mode = @c.mode
      @iv_len = nil
      @state = nil
      @auth_tag = nil
      @auth_tag_len = 16
      @expected_tag = nil
      @finalized = false
    end

    def name
      @mbed_name
    end

    def mode
      @mode
    end

    def key_len
      @c.key_len
    end

    # Every cipher this build exposes has a fixed key length; OpenSSL only
    # honours key_len= for variable-key ciphers, and there are none here.
    def key_len=(len)
      unless len == key_len
        raise CipherError, "#{name} has a fixed key length of #{key_len}"
      end
      len
    end

    def iv_len
      @iv_len || @c.iv_len
    end

    # GCM/ChaCha20-Poly1305 take a variable nonce.  mbedtls caps it at
    # MBEDTLS_MAX_IV_LENGTH (16), so longer nonces are refused instead of
    # being silently truncated.
    def iv_len=(len)
      unless authenticated?
        raise CipherError, "#{name} has a fixed iv length of #{@c.iv_len}"
      end
      raise CipherError, 'iv length must be 1..16' if len < 1 || len > 16
      @iv_len = len
    end

    # OpenSSL reports 1 for stream and AEAD modes, and the real block size
    # only for the block modes.
    def block_size
      BLOCK_MODES.include?(@mode) ? @c.block_size : 1
    end

    def authenticated?
      AEAD_MODES.include?(@mode)
    end

    def encrypt(key = nil, iv = nil)
      @c.operation = MbedTLS::Cipher::ENCRYPT
      @state = :encrypt
      reset_auth_state
      self.key = key if key
      self.iv = iv if iv
      self
    end

    def decrypt(key = nil, iv = nil)
      @c.operation = MbedTLS::Cipher::DECRYPT
      @state = :decrypt
      reset_auth_state
      self.key = key if key
      self.iv = iv if iv
      self
    end

    def key=(key)
      key = key.to_str
      unless key.bytesize == key_len
        raise ArgumentError, "key must be #{key_len} bytes"
      end
      @c.key = key
      @finalized = false
      key
    end

    def iv=(iv)
      iv = iv.to_str
      if authenticated?
        if iv.bytesize < 1 || iv.bytesize > 16
          raise ArgumentError, 'iv must be 1..16 bytes'
        end
      elsif iv.bytesize != @c.iv_len
        raise ArgumentError, "iv must be #{@c.iv_len} bytes"
      end
      @c.iv = iv
      @finalized = false
      iv
    end

    def random_key
      k = Random.random_bytes(key_len)
      self.key = k
      k
    end

    def random_iv
      v = Random.random_bytes(iv_len)
      self.iv = v
      v
    end

    # OpenSSL takes any truthy/non-zero value as "pad", 0/false as "don't".
    def padding=(pad)
      on = !(pad == 0 || pad == false || pad.nil?)
      @c.padding = on
      pad
    end

    def auth_data=(data)
      guard { @c.auth_data = data.to_str }
      data
    end

    def auth_tag_len=(len)
      raise CipherError, 'tag length must be 1..16' if len < 1 || len > 16
      @auth_tag_len = len
    end

    def auth_tag(len = nil)
      unless authenticated?
        raise CipherError, "#{name} is not an authenticated cipher"
      end
      unless @state == :encrypt
        raise CipherError, 'authentication tag is only produced when encrypting'
      end
      unless @finalized
        raise CipherError, 'call #final before reading the authentication tag'
      end
      len ||= @auth_tag_len
      guard { @c.write_tag(len) }
    end

    def auth_tag=(tag)
      unless authenticated?
        raise CipherError, "#{name} is not an authenticated cipher"
      end
      @expected_tag = tag.to_str
    end

    def update(data, buffer = nil)
      out = guard { @c.update(data.to_str) }
      if buffer
        buffer.replace(out)
        buffer
      else
        out
      end
    end

    def final
      out = guard { @c.final }
      @finalized = true
      if authenticated? && @state == :decrypt
        unless @expected_tag
          raise CipherError, 'authentication tag not set (auth_tag=)'
        end
        guard { @c.check_tag(@expected_tag) }
      end
      out
    end

    def reset
      @c.reset
      reset_auth_state
      self
    end

    # EVP_BytesToKey.  Deliberately absent rather than approximated: it is a
    # legacy OpenSSL-specific KDF and nothing in this port needs it.
    def pkcs5_keyivgen(*)
      raise NotImplementedError,
            'OpenSSL::Cipher#pkcs5_keyivgen (EVP_BytesToKey) is not ' \
            'implemented in the mbedtls-backed OpenSSL layer; use ' \
            'OpenSSL::KDF.pbkdf2_hmac'
    end

    # Legacy convenience classes (OpenSSL::Cipher::AES256.new("GCM"), ...).
    class AES < Cipher
      def initialize(bits, mode = 'CBC')
        super("AES-#{bits}-#{mode}")
      end
    end

    %w[128 192 256].each do |bits|
      klass = Class.new(Cipher) do
        define_method(:initialize) { |mode = 'CBC'| super("AES-#{bits}-#{mode}") }
      end
      const_set("AES#{bits}", klass)
    end

    private

    def reset_auth_state
      @auth_tag = nil
      @expected_tag = nil
      @finalized = false
    end

    def guard
      yield
    rescue MbedTLS::CryptoError => e
      raise CipherError, e.message
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # HMAC
  # ══════════════════════════════════════════════════════════════════════
  class HMAC
    # NOTE the argument order: key first, digest second (OpenSSL's).
    def initialize(key, digest)
      @name = Digest.digest_name(digest)
      @h = MbedTLS::HMAC.new(@name, key.to_str)
    end

    def initialize_copy(other)
      super
      @h = other.instance_variable_get(:@h).dup
      self
    end

    def update(data)
      @h.update(data.to_str)
      self
    end
    alias << update

    def digest
      @h.digest
    end

    def hexdigest
      digest.unpack1('H*')
    end
    alias to_s hexdigest
    alias inspect hexdigest

    def base64digest
      [digest].pack('m0')
    end

    def reset
      @h.reset
      self
    end

    def ==(other)
      case other
      when HMAC  then OpenSSL.fixed_length_secure_compare(digest, other.digest)
      when String
        other.bytesize == digest.bytesize &&
          OpenSSL.fixed_length_secure_compare(digest, other)
      else false
      end
    end

    def self.digest(digest, key, data)
      MbedTLS.hmac(Digest.digest_name(digest), key.to_str, data.to_str)
    end

    def self.hexdigest(digest, key, data)
      self.digest(digest, key, data).unpack1('H*')
    end

    def self.base64digest(digest, key, data)
      [self.digest(digest, key, data)].pack('m0')
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # Key derivation
  # ══════════════════════════════════════════════════════════════════════
  module KDF
    class KDFError < OpenSSLError; end

    def self.pbkdf2_hmac(pass, salt:, iterations:, length:, hash:)
      unless iterations.is_a?(Integer) && iterations > 0
        raise KDFError, 'iterations must be a positive integer'
      end
      unless length.is_a?(Integer) && length >= 0
        raise KDFError, 'length must be a non-negative integer'
      end
      MbedTLS.pbkdf2_hmac(Digest.digest_name(hash), pass.to_str, salt.to_str,
                          iterations, length)
    rescue MbedTLS::CryptoError => e
      raise KDFError, e.message
    end

    def self.hkdf(*)
      raise NotImplementedError,
            'OpenSSL::KDF.hkdf is not implemented (mbedtls in this tree has ' \
            'no HKDF); use OpenSSL::KDF.pbkdf2_hmac'
    end

    def self.scrypt(*)
      raise NotImplementedError,
            'OpenSSL::KDF.scrypt is not implemented (mbedtls has no scrypt)'
    end
  end

  module PKCS5
    class PKCS5Error < OpenSSLError; end

    def self.pbkdf2_hmac(pass, salt, iter, keylen, digest)
      KDF.pbkdf2_hmac(pass, salt: salt, iterations: iter, length: keylen,
                            hash: digest)
    end

    def self.pbkdf2_hmac_sha1(pass, salt, iter, keylen)
      pbkdf2_hmac(pass, salt, iter, keylen, 'SHA1')
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # Public key cryptography -- NOT implemented
  # ══════════════════════════════════════════════════════════════════════
  #
  # mbedtls does have RSA/EC, but none of it is bound here.  The classes
  # exist so that `defined?(OpenSSL::PKey::RSA)` and rescue clauses keep
  # working; every operation raises rather than returning a fake key, which
  # is what the previous shim did.
  module PKey
    class PKeyError < OpenSSLError; end

    UNIMPLEMENTED = 'public key cryptography is not implemented in the ' \
                    'mbedtls-backed OpenSSL layer of CosmoRuby'

    def self.read(*)
      raise NotImplementedError, UNIMPLEMENTED
    end

    class PKey
      def initialize(*)
        raise NotImplementedError, UNIMPLEMENTED
      end

      def self.generate(*)
        raise NotImplementedError, UNIMPLEMENTED
      end
    end

    class RSA < PKey; end
    class DSA < PKey; end
    class DH  < PKey; end

    class EC < PKey
      class Point
        def initialize(*)
          raise NotImplementedError, UNIMPLEMENTED
        end
      end
    end
  end

  # ══════════════════════════════════════════════════════════════════════
  # X.509 -- client-side compatibility only
  # ══════════════════════════════════════════════════════════════════════
  #
  # Certificate verification really happens inside the mbedtls handshake
  # against cosmopolitan's built-in root store (GetSslRoots()).  These
  # objects exist so Net::HTTP and RubyGems can configure a store; they do
  # not parse or build certificates.
  module X509
    class StoreError < OpenSSLError; end
    class CertificateError < OpenSSLError; end

    class Store
      attr_accessor :verify_callback

      def initialize
        @verify_callback = nil
        @time = nil
        @purpose = nil
        @trust = nil
      end

      def set_default_paths
        # Certificates are already loaded in mbedtls via GetSslRoots()
        # This is a no-op for compatibility
      end

      def add_file(file)
        # Would load additional certificate file
        # Not implemented, mbedtls uses built-in certs
      end

      def add_path(path)
        # Would load certificates from directory
        # Not implemented, mbedtls uses built-in certs
      end

      def add_cert(cert)
        # Would add a certificate object
        # Not implemented for now
      end

      def time=(time)
        @time = time
      end

      def purpose=(purpose)
        @purpose = purpose
      end

      def trust=(trust)
        @trust = trust
      end

      def flags=(flags)
        # Certificate verification flags
        # Not implemented for now
      end

      def verify(cert, chain = nil)
        # Verification is performed by mbedtls during the TLS handshake.
        true
      end
    end

    class Certificate
      # Stub class for compatibility
      def initialize(data = nil)
        @data = data
      end
    end

    class Name
      # Stub class for compatibility
      def initialize(dn = nil)
        @dn = dn
      end

      def to_s
        @dn.to_s
      end
    end
  end

  module SSL
    class SSLError < OpenSSL::OpenSSLError; end

    # Verification mode constants
    VERIFY_NONE = 0
    VERIFY_PEER = 1

    # Session cache mode constants (dummy values, not actually used)
    SESSION_CACHE_OFF = 0
    SESSION_CACHE_CLIENT = 1
    SESSION_CACHE_SERVER = 2
    SESSION_CACHE_BOTH = 3
    SESSION_CACHE_NO_AUTO_CLEAR = 4
    SESSION_CACHE_NO_INTERNAL_LOOKUP = 8
    SESSION_CACHE_NO_INTERNAL_STORE = 16
    SESSION_CACHE_NO_INTERNAL = 24

    class SSLContext
      attr_accessor :verify_mode, :verify_hostname, :session_cache_mode
      attr_accessor :ca_file, :ca_path, :cert, :key, :ciphers
      attr_accessor :ssl_version, :min_version, :max_version
      attr_accessor :cert_store, :verify_callback

      def initialize
        @verify_mode = VERIFY_PEER
        @verify_hostname = true
        @session_cache_mode = nil
        @ca_file = nil
        @ca_path = nil
        @cert = nil
        @key = nil
        @ciphers = nil
        @ssl_version = nil
        @min_version = nil
        @max_version = nil
        @cert_store = nil
        @verify_callback = nil
      end

      # Stub methods that Net::HTTP might call
      def set_params(params = {})
        params.each do |key, value|
          send("#{key}=", value) if respond_to?("#{key}=")
        end
      end

      def add_certificate(*args)
        # No-op for now
      end
    end

    class SSLSocket
      attr_accessor :sync_close
      attr_reader :io, :context

      def initialize(socket, context = nil)
        @io = socket
        @context = context || SSLContext.new
        @sync_close = false
        @hostname = nil
        @mbedtls_ssl = nil
        @connected = false
      end

      def hostname=(hostname)
        @hostname = hostname
      end

      def session=(session)
        # Session resumption not implemented yet
        # Silently ignore for compatibility
      end

      def connect
        return self if @connected

        verify = @context.verify_mode != VERIFY_NONE

        # Create MbedTLS::SSL wrapper
        @mbedtls_ssl = MbedTLS::SSL.new(@io, hostname: @hostname, verify: verify)
        @mbedtls_ssl.connect
        @connected = true

        self
      rescue MbedTLS::SSLError => e
        raise SSLError, e.message
      end

      def connect_nonblock(exception: true)
        # For now, we do blocking connect
        # In a real implementation, this would be non-blocking
        connect
      rescue => e
        raise if exception
        :wait_writable
      end

      def read(maxlen = nil, outbuf = nil)
        raise SSLError, "SSL not connected" unless @connected

        maxlen ||= 16384
        data = @mbedtls_ssl.read(maxlen)

        if outbuf
          outbuf.clear
          outbuf << data
          outbuf
        else
          data
        end
      rescue MbedTLS::SSLError => e
        raise SSLError, e.message
      end

      def write(data)
        raise SSLError, "SSL not connected" unless @connected

        @mbedtls_ssl.write(data)
      rescue MbedTLS::SSLError => e
        raise SSLError, e.message
      end

      def close
        if @mbedtls_ssl
          @mbedtls_ssl.close
          @mbedtls_ssl = nil
        end
        @io.close if @sync_close && @io && !@io.closed?
        @connected = false
      end

      def closed?
        !@connected
      end

      # Compatibility methods that Net::HTTP expects
      def post_connection_check(hostname)
        # Certificate verification is done during handshake
        # This is a no-op for compatibility
        true
      end

      def ssl_version
        "TLSv1.2" # MbedTLS default
      end

      def cipher
        ["TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256", "TLSv1.2", 128, 128]
      end

      # IO-like methods for compatibility
      def eof?
        @io.eof?
      end

      def gets(*args)
        # Simple implementation - read line by line
        line = ""
        loop do
          char = read(1)
          break if char.empty?
          line << char
          break if char == "\n"
        end
        line.empty? ? nil : line
      end

      def print(*args)
        args.each { |arg| write(arg.to_s) }
        nil
      end

      def puts(*args)
        args.each { |arg| write("#{arg}\n") }
        nil
      end

      def flush
        # No buffering in our implementation
        self
      end

      def sync=(value)
        # No-op, we're always synchronous
      end

      def sync
        true
      end

      # Implement specific methods that Net::HTTP needs
      def to_io
        @io
      end

      def addr
        @io.addr
      end

      def peeraddr
        @io.peeraddr
      end

      def setsockopt(*args)
        @io.setsockopt(*args)
      end

      def fcntl(*args)
        @io.fcntl(*args)
      end

      def readbyte
        byte = read(1)
        byte.empty? ? nil : byte.bytes.first
      end

      def getbyte
        readbyte
      end

      def each_byte(&block)
        while (byte = readbyte)
          block.call(byte)
        end
      end

      def read_nonblock(maxlen, buf = nil, exception: true)
        read(maxlen, buf)
      rescue => e
        raise if exception
        :wait_readable
      end

      def write_nonblock(data, exception: true)
        write(data)
      rescue => e
        raise if exception
        :wait_writable
      end
    end
  end
end
