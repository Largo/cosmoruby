# MbedTLS Ruby Extension

This extension provides SSL/TLS support for Ruby using the mbedtls library that's already included in Cosmopolitan Libc.

## Purpose

Enable HTTPS connections for Ruby applications, particularly for RubyGems to download gems from rubygems.org over HTTPS.

## Features

- SSL/TLS client connections using mbedtls
- Certificate verification with trusted root CAs
- SNI (Server Name Indication) support
- Simple, focused API

## Usage

### Basic HTTPS Connection

```ruby
require 'socket'
require 'mbedtls'

# Open TCP socket
socket = TCPSocket.new('example.com', 443)

# Create SSL connection with verification
ssl = MbedTLS::SSL.new(socket, hostname: 'example.com', verify: true)
ssl.connect

# Send HTTP request
ssl.write("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")

# Read response
response = ssl.read(4096)
puts response

# Close
ssl.close
socket.close
```

### Without Certificate Verification (not recommended)

```ruby
ssl = MbedTLS::SSL.new(socket, hostname: 'example.com', verify: false)
```

## API Reference

### `MbedTLS::SSL`

#### `MbedTLS::SSL.new(socket, hostname: nil, verify: true)`

Create a new SSL context wrapping a TCP socket.

- `socket`: A Ruby IO object (typically TCPSocket)
- `hostname`: Server hostname for SNI and certificate verification
- `verify`: Whether to verify the server's certificate (default: true)

#### `ssl.connect`

Perform the SSL/TLS handshake with the server.

#### `ssl.write(data)`

Write data through the SSL connection. Returns the number of bytes written.

#### `ssl.read(maxlen)`

Read up to `maxlen` bytes from the SSL connection. Returns a String.

#### `ssl.close`

Close the SSL connection gracefully.

### `MbedTLS::SSLError`

Exception raised for SSL-related errors.

## Integration with Net::HTTP

To use this with Ruby's standard `Net::HTTP` library, you would need to create an adapter. For now, you can use the low-level API directly as shown above.

## Testing

Run the test script:

```bash
ruby.com third_party/ruby/ext/mbedtls/test_mbedtls.rb
```

## Implementation Notes

- Uses mbedtls from Cosmopolitan's `third_party/mbedtls/`
- Certificate roots come from `GetSslRoots()` in `net/https/https.h`
- Designed to be minimal and focused on client connections
- Does not currently support server-side SSL or advanced features

## Future Enhancements

Possible future additions:

1. OpenSSL compatibility shim (monkey-patch `OpenSSL::SSL::SSLSocket`)
2. Server-side SSL support
3. Client certificates
4. Session resumption
5. ALPN support

## License

Copyright 2025 Cosmopolitan Contributors

Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted.
