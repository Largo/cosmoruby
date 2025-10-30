# frozen_string_literal: true
# OpenSSL compatibility shim for Cosmopolitan Ruby
# Uses MbedTLS under the hood

require 'mbedtls'
require 'socket'

module OpenSSL
  class OpenSSLError < StandardError; end

  # Message digest (hash) functions wrapper
  module Digest
    class DigestError < OpenSSLError; end

    def self.new(name)
      # Factory method - return Ruby's native Digest wrapped
      case name.to_s.upcase.gsub('-', '')
      when 'SHA1'
        require 'digest/sha1'
        ::Digest::SHA1.new
      when 'SHA256', 'SHA2256'
        require 'digest/sha2'
        ::Digest::SHA256.new
      when 'SHA384', 'SHA2384'
        require 'digest/sha2'
        ::Digest::SHA384.new
      when 'SHA512', 'SHA2512'
        require 'digest/sha2'
        ::Digest::SHA512.new
      when 'MD5'
        require 'digest/md5'
        ::Digest::MD5.new
      else
        raise DigestError, "Unsupported digest algorithm: #{name}"
      end
    end

    # Lazy-loaded constant aliases for compatibility
    def self.const_missing(name)
      case name
      when :SHA1
        require 'digest/sha1'
        const_set(:SHA1, ::Digest::SHA1)
      when :SHA256
        require 'digest/sha2'
        const_set(:SHA256, ::Digest::SHA256)
      when :SHA384
        require 'digest/sha2'
        const_set(:SHA384, ::Digest::SHA384)
      when :SHA512
        require 'digest/sha2'
        const_set(:SHA512, ::Digest::SHA512)
      when :MD5
        require 'digest/md5'
        const_set(:MD5, ::Digest::MD5)
      else
        super
      end
    end
  end

  # Public key cryptography (stub implementation)
  module PKey
    class PKeyError < OpenSSLError; end

    class RSA
      def initialize(data = nil, password = nil)
        @data = data
        # Not actually implementing RSA key operations
        # This is just for RubyGems compatibility
      end

      def public?
        true
      end

      def private?
        true
      end
    end

    class DSA
      def initialize(data = nil)
        @data = data
      end
    end

    class EC
      def initialize(data = nil)
        @data = data
      end
    end
  end

  # X.509 certificate management (stub implementation)
  module X509
    class StoreError < OpenSSLError; end

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
        # Would verify a certificate
        # For now, verification is done during SSL handshake
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
