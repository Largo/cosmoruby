/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:4;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=4 sts=4 sw=4 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2025 Cosmopolitan Contributors                                     │
│                                                                              │
│ Permission to use, copy, modify, and/or distribute this software for         │
│ any purpose with or without fee is hereby granted, provided that the         │
│ above copyright notice and this permission notice appear in all copies.      │
│                                                                              │
│ THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL                │
│ WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED                │
│ WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE             │
│ AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL         │
│ DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR        │
│ PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER               │
│ TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR             │
│ PERFORMANCE OF THIS SOFTWARE.                                                │
╚─────────────────────────────────────────────────────────────────────────────*/
#include "ruby/ruby.h"
#include "ruby/io.h"
#include <errno.h>
#include <string.h>
#include "third_party/mbedtls/ctr_drbg.h"
#include "third_party/mbedtls/entropy.h"
#include "third_party/mbedtls/error.h"
#include "third_party/mbedtls/ssl.h"
#include "third_party/mbedtls/x509_crt.h"
#include "third_party/mbedtls/net_sockets.h"
#include "net/https/https.h"

/**
 * @fileoverview Ruby extension for mbedtls SSL/TLS support
 *
 * This extension provides SSL/TLS functionality for Ruby using mbedtls.
 * It's designed to enable HTTPS downloads for RubyGems without requiring OpenSSL.
 *
 * Basic usage:
 *   require 'mbedtls'
 *   socket = TCPSocket.new('example.com', 443)
 *   ssl = MbedTLS::SSL.new(socket, hostname: 'example.com')
 *   ssl.connect
 *   ssl.write("GET / HTTP/1.0\r\n\r\n")
 *   puts ssl.read(1024)
 *   ssl.close
 */

static VALUE mMbedTLS;
static VALUE cSSL;
static VALUE cSSLError;

/* SSL context structure */
typedef struct {
    int fd;
    int connected;
    VALUE io_obj;  /* Ruby IO object (socket) */
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config conf;
    mbedtls_ctr_drbg_context rng;
    mbedtls_entropy_context entropy;
} mbedtls_ssl_t;

/* Forward declarations */
static void ruby_mbedtls_ssl_free(void *ptr);
static VALUE mbedtls_ssl_alloc(VALUE klass);

static const rb_data_type_t mbedtls_ssl_type = {
    "MbedTLS::SSL",
    {0, ruby_mbedtls_ssl_free, 0},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY
};

/*
 * Raise a Ruby exception with mbedtls error message
 */
static void
raise_ssl_error(int ret, const char *context)
{
    char error_buf[128];
    mbedtls_strerror(ret, error_buf, sizeof(error_buf));
    rb_raise(cSSLError, "%s: %s (mbedtls error -0x%04x)",
             context, error_buf, (unsigned int)-ret);
}

/*
 * Send callback for mbedtls
 */
static int
ssl_send_callback(void *ctx, const unsigned char *buf, size_t len)
{
    mbedtls_ssl_t *ssl = (mbedtls_ssl_t *)ctx;
    ssize_t n;

    if (ssl->fd < 0) {
        return MBEDTLS_ERR_NET_SEND_FAILED;
    }

    while (1) {
        n = write(ssl->fd, buf, len);
        if (n >= 0) {
            return n;
        }
        if (errno == EINTR) {
            continue;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return MBEDTLS_ERR_SSL_WANT_WRITE;
        }
        return MBEDTLS_ERR_NET_SEND_FAILED;
    }
}

/*
 * Receive callback for mbedtls
 */
static int
ssl_recv_callback(void *ctx, unsigned char *buf, size_t len, uint32_t timeout)
{
    mbedtls_ssl_t *ssl = (mbedtls_ssl_t *)ctx;
    ssize_t n;

    if (ssl->fd < 0) {
        return MBEDTLS_ERR_NET_RECV_FAILED;
    }

    while (1) {
        n = read(ssl->fd, buf, len);
        if (n >= 0) {
            return n;
        }
        if (errno == EINTR) {
            continue;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return MBEDTLS_ERR_SSL_WANT_READ;
        }
        return MBEDTLS_ERR_NET_RECV_FAILED;
    }
}

/*
 * Free SSL context
 */
static void
ruby_mbedtls_ssl_free(void *ptr)
{
    mbedtls_ssl_t *ssl = (mbedtls_ssl_t *)ptr;

    if (ssl) {
        mbedtls_ssl_free(&ssl->ssl);
        mbedtls_ssl_config_free(&ssl->conf);
        mbedtls_ctr_drbg_free(&ssl->rng);
        mbedtls_entropy_free(&ssl->entropy);
        xfree(ssl);
    }
}

/*
 * Allocate SSL context
 */
static VALUE
mbedtls_ssl_alloc(VALUE klass)
{
    mbedtls_ssl_t *ssl;
    VALUE obj = TypedData_Make_Struct(klass, mbedtls_ssl_t, &mbedtls_ssl_type, ssl);

    ssl->fd = -1;
    ssl->connected = 0;
    ssl->io_obj = Qnil;
    mbedtls_ssl_init(&ssl->ssl);
    mbedtls_ssl_config_init(&ssl->conf);
    mbedtls_ctr_drbg_init(&ssl->rng);
    mbedtls_entropy_init(&ssl->entropy);

    return obj;
}

/*
 * call-seq:
 *   MbedTLS::SSL.new(socket, hostname: nil, verify: true) -> ssl
 *
 * Create a new SSL context wrapping the given socket.
 *
 * - socket: A Ruby IO object (typically TCPSocket)
 * - hostname: Server hostname for SNI and certificate verification
 * - verify: Whether to verify server certificate (default: true)
 */
static VALUE
ruby_mbedtls_ssl_initialize(int argc, VALUE *argv, VALUE self)
{
    mbedtls_ssl_t *ssl;
    VALUE socket, opts, hostname_val, verify_val;
    const char *hostname = NULL;
    int verify = 1;
    int ret;
    rb_io_t *fptr;

    TypedData_Get_Struct(self, mbedtls_ssl_t, &mbedtls_ssl_type, ssl);

    rb_scan_args(argc, argv, "1:", &socket, &opts);

    /* Extract options */
    if (!NIL_P(opts)) {
        hostname_val = rb_hash_aref(opts, ID2SYM(rb_intern("hostname")));
        verify_val = rb_hash_aref(opts, ID2SYM(rb_intern("verify")));

        if (!NIL_P(hostname_val)) {
            hostname = StringValueCStr(hostname_val);
        }
        if (!NIL_P(verify_val)) {
            verify = RTEST(verify_val);
        }
    }

    /* Get file descriptor from socket */
    GetOpenFile(socket, fptr);
    ssl->fd = rb_io_descriptor(socket);
    ssl->io_obj = socket;
    RB_GC_GUARD(ssl->io_obj);

    /* Initialize random number generator */
    ret = mbedtls_ctr_drbg_seed(&ssl->rng, mbedtls_entropy_func,
                                 &ssl->entropy, NULL, 0);
    if (ret != 0) {
        raise_ssl_error(ret, "Failed to seed random number generator");
    }

    /* Configure SSL context */
    ret = mbedtls_ssl_config_defaults(&ssl->conf,
                                      MBEDTLS_SSL_IS_CLIENT,
                                      MBEDTLS_SSL_TRANSPORT_STREAM,
                                      MBEDTLS_SSL_PRESET_DEFAULT);
    if (ret != 0) {
        raise_ssl_error(ret, "Failed to set SSL config defaults");
    }

    /* Set RNG */
    mbedtls_ssl_conf_rng(&ssl->conf, mbedtls_ctr_drbg_random, &ssl->rng);

    /* Set certificate verification */
    if (verify && hostname) {
        mbedtls_ssl_conf_authmode(&ssl->conf, MBEDTLS_SSL_VERIFY_REQUIRED);
        mbedtls_ssl_conf_ca_chain(&ssl->conf, GetSslRoots(), NULL);
    } else {
        mbedtls_ssl_conf_authmode(&ssl->conf, MBEDTLS_SSL_VERIFY_NONE);
    }

    /* Setup SSL context */
    ret = mbedtls_ssl_setup(&ssl->ssl, &ssl->conf);
    if (ret != 0) {
        raise_ssl_error(ret, "Failed to setup SSL context");
    }

    /* Set hostname for SNI */
    if (hostname) {
        ret = mbedtls_ssl_set_hostname(&ssl->ssl, hostname);
        if (ret != 0) {
            raise_ssl_error(ret, "Failed to set hostname");
        }
    }

    /* Set BIO callbacks */
    mbedtls_ssl_set_bio(&ssl->ssl, ssl, ssl_send_callback, NULL, ssl_recv_callback);

    return self;
}

/*
 * call-seq:
 *   ssl.connect -> self
 *
 * Perform SSL/TLS handshake with the server.
 */
static VALUE
ruby_mbedtls_ssl_connect(VALUE self)
{
    mbedtls_ssl_t *ssl;
    int ret;

    TypedData_Get_Struct(self, mbedtls_ssl_t, &mbedtls_ssl_type, ssl);

    if (ssl->connected) {
        return self;
    }

    while ((ret = mbedtls_ssl_handshake(&ssl->ssl)) != 0) {
        if (ret != MBEDTLS_ERR_SSL_WANT_READ &&
            ret != MBEDTLS_ERR_SSL_WANT_WRITE) {
            raise_ssl_error(ret, "SSL handshake failed");
        }
    }

    ssl->connected = 1;
    return self;
}

/*
 * call-seq:
 *   ssl.write(data) -> integer
 *
 * Write data through the SSL connection. Returns number of bytes written.
 */
static VALUE
ruby_mbedtls_ssl_write(VALUE self, VALUE data)
{
    mbedtls_ssl_t *ssl;
    int ret;
    const char *buf;
    size_t len;

    TypedData_Get_Struct(self, mbedtls_ssl_t, &mbedtls_ssl_type, ssl);

    StringValue(data);
    buf = RSTRING_PTR(data);
    len = RSTRING_LEN(data);

    if (!ssl->connected) {
        rb_raise(cSSLError, "SSL connection not established");
    }

    /* Retry on WANT_READ/WANT_WRITE */
    while (1) {
        ret = mbedtls_ssl_write(&ssl->ssl, (const unsigned char *)buf, len);
        if (ret >= 0) {
            return INT2NUM(ret);
        }
        if (ret != MBEDTLS_ERR_SSL_WANT_READ &&
            ret != MBEDTLS_ERR_SSL_WANT_WRITE) {
            raise_ssl_error(ret, "SSL write failed");
        }
        /* Loop will retry on WANT_READ/WANT_WRITE */
    }
}

/*
 * call-seq:
 *   ssl.read(maxlen) -> string
 *
 * Read up to maxlen bytes from the SSL connection.
 * Returns empty string on EOF.
 */
static VALUE
ruby_mbedtls_ssl_read(VALUE self, VALUE maxlen_val)
{
    mbedtls_ssl_t *ssl;
    int ret;
    size_t maxlen;
    VALUE str;

    TypedData_Get_Struct(self, mbedtls_ssl_t, &mbedtls_ssl_type, ssl);

    maxlen = NUM2SIZET(maxlen_val);

    if (!ssl->connected) {
        rb_raise(cSSLError, "SSL connection not established");
    }

    str = rb_str_new(NULL, maxlen);

    /* Retry on WANT_READ/WANT_WRITE */
    while (1) {
        ret = mbedtls_ssl_read(&ssl->ssl, (unsigned char *)RSTRING_PTR(str), maxlen);

        if (ret >= 0) {
            /* Successful read */
            rb_str_resize(str, ret);
            return str;
        }

        if (ret == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY) {
            /* Clean shutdown */
            rb_str_resize(str, 0);
            return str;
        }

        if (ret != MBEDTLS_ERR_SSL_WANT_READ &&
            ret != MBEDTLS_ERR_SSL_WANT_WRITE) {
            /* Real error */
            raise_ssl_error(ret, "SSL read failed");
        }
        /* Loop will retry on WANT_READ/WANT_WRITE */
    }
}

/*
 * call-seq:
 *   ssl.close -> nil
 *
 * Close the SSL connection gracefully.
 */
static VALUE
ruby_mbedtls_ssl_close(VALUE self)
{
    mbedtls_ssl_t *ssl;

    TypedData_Get_Struct(self, mbedtls_ssl_t, &mbedtls_ssl_type, ssl);

    if (ssl->connected) {
        mbedtls_ssl_close_notify(&ssl->ssl);
        ssl->connected = 0;
    }

    return Qnil;
}

/* third_party/ruby/ext/mbedtls/crypto.c */
void Init_mbedtls_crypto(VALUE mod);

/*
 * Initialize the MbedTLS module
 */
void
Init_mbedtls(void)
{
    /* Define MbedTLS module */
    mMbedTLS = rb_define_module("MbedTLS");

    /* Define MbedTLS::SSL class */
    cSSL = rb_define_class_under(mMbedTLS, "SSL", rb_cObject);
    rb_define_alloc_func(cSSL, mbedtls_ssl_alloc);
    rb_define_method(cSSL, "initialize", ruby_mbedtls_ssl_initialize, -1);
    rb_define_method(cSSL, "connect", ruby_mbedtls_ssl_connect, 0);
    rb_define_method(cSSL, "write", ruby_mbedtls_ssl_write, 1);
    rb_define_method(cSSL, "read", ruby_mbedtls_ssl_read, 1);
    rb_define_method(cSSL, "close", ruby_mbedtls_ssl_close, 0);

    /* Define MbedTLS::SSLError exception */
    cSSLError = rb_define_class_under(mMbedTLS, "SSLError", rb_eStandardError);

    /* Symmetric ciphers, message digests, HMAC and PBKDF2 */
    Init_mbedtls_crypto(mMbedTLS);
}
