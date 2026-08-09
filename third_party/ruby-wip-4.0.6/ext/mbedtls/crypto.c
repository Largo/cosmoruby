/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:4;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=4 sts=4 sw=4 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2026 Cosmopolitan Contributors                                     │
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
#include <errno.h>
#include <string.h>
#include "libc/stdio/rand.h"
#include "libc/str/str.h"
#include "third_party/mbedtls/cipher.h"
#include "third_party/mbedtls/error.h"
#include "third_party/mbedtls/md.h"
#include "third_party/mbedtls/pkcs5.h"

/**
 * @fileoverview Symmetric crypto primitives for Ruby, backed by mbedtls.
 *
 * This file binds mbedtls' generic layers -- mbedtls_cipher_*, mbedtls_md_*
 * and mbedtls_pkcs5_pbkdf2_hmac -- so that lib/openssl.rb can offer
 * OpenSSL::Cipher, OpenSSL::HMAC, OpenSSL::KDF and OpenSSL::Digest without
 * any cryptography being implemented in this repository.  Every byte of key
 * schedule, block function, GHASH, HMAC and PBKDF2 arithmetic comes out of
 * third_party/mbedtls, which is already linked into ruby.com for TLS.
 *
 * Because the *generic* layers are used, adding another algorithm is a table
 * entry in lib/openssl.rb plus (if it is not already compiled) one #define in
 * third_party/mbedtls/config.h -- no code here changes.
 *
 * The API here is deliberately low level and un-OpenSSL-ish; the OpenSSL
 * semantics (padding defaults, error classes, name spelling) live in Ruby.
 */

static VALUE mMbedTLS;
static VALUE cCipher;
static VALUE cDigest;
static VALUE cHMAC;
static VALUE eCryptoError;

static void
crypto_raise(int ret, const char *what)
{
    char buf[128];
    mbedtls_strerror(ret, buf, sizeof(buf));
    rb_raise(eCryptoError, "%s: %s (mbedtls -0x%04x)", what, buf,
             (unsigned int)-ret);
}

static void
crypto_wipe(void *p, size_t n)
{
    volatile unsigned char *q = (volatile unsigned char *)p;
    while (n--) *q++ = 0;
}

/* ══════════════════════════════════════════════════════════════════════════
 * MbedTLS::Cipher -- mbedtls_cipher_* multi-part API
 * ══════════════════════════════════════════════════════════════════════════
 *
 * Lifecycle mirrors mbedtls': setup(info) at construction, then
 * setkey/set_iv/reset/update_ad/update.../finish/write_tag.  Key and IV are
 * *copied* into this struct and (re)applied at #start time so that #reset
 * can rewind an object that has already been used -- mbedtls mutates
 * ctx->iv in place for CBC, so replaying from the caller's IV is the only
 * way to get repeatable results.
 */

typedef struct {
    mbedtls_cipher_context_t ctx;
    int have_info;
    int operation;              /* MBEDTLS_ENCRYPT/DECRYPT/OPERATION_NONE */
    int key_set;
    int iv_set;
    int started;
    int padding;                /* MBEDTLS_PADDING_PKCS7 or _NONE */
    unsigned char key[64];
    size_t key_len;
    unsigned char iv[MBEDTLS_MAX_IV_LENGTH];
    size_t iv_len;
    unsigned char *aad;
    size_t aad_len;
    /* AEAD block staging: mbedtls_gcm_update() only tolerates a non-multiple
     * of 16 on the *last* call, but OpenSSL::Cipher#update takes any length,
     * so partial blocks are held back here until a full block is available
     * or #final arrives. */
    unsigned char pending[16];
    size_t pending_len;
} cipher_t;

static void
cipher_free(void *ptr)
{
    cipher_t *c = (cipher_t *)ptr;
    if (!c) return;
    if (c->have_info) mbedtls_cipher_free(&c->ctx);
    if (c->aad) {
        crypto_wipe(c->aad, c->aad_len);
        xfree(c->aad);
    }
    crypto_wipe(c->key, sizeof(c->key));
    crypto_wipe(c->iv, sizeof(c->iv));
    xfree(c);
}

static size_t
cipher_memsize(const void *ptr)
{
    const cipher_t *c = (const cipher_t *)ptr;
    return sizeof(cipher_t) + (c ? c->aad_len : 0);
}

static const rb_data_type_t cipher_type = {
    "MbedTLS::Cipher",
    {0, cipher_free, cipher_memsize},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static cipher_t *
get_cipher(VALUE self)
{
    cipher_t *c;
    TypedData_Get_Struct(self, cipher_t, &cipher_type, c);
    if (!c->have_info) rb_raise(eCryptoError, "cipher not initialized");
    return c;
}

static VALUE
cipher_alloc(VALUE klass)
{
    cipher_t *c;
    VALUE obj = TypedData_Make_Struct(klass, cipher_t, &cipher_type, c);
    mbedtls_cipher_init(&c->ctx);
    c->have_info = 0;
    c->operation = MBEDTLS_OPERATION_NONE;
    c->padding = MBEDTLS_PADDING_PKCS7;
    return obj;
}

static int
cipher_is_aead(cipher_t *c)
{
    mbedtls_cipher_mode_t m = mbedtls_cipher_get_cipher_mode(&c->ctx);
    return m == MBEDTLS_MODE_GCM || m == MBEDTLS_MODE_CHACHAPOLY ||
           m == MBEDTLS_MODE_CCM;
}

/*
 * call-seq: MbedTLS::Cipher.new("AES-256-GCM") -> cipher
 *
 * The name is an mbedtls cipher name (see mbedtls_cipher_info_from_string);
 * translating OpenSSL spellings is lib/openssl.rb's job.
 */
static VALUE
cipher_initialize(VALUE self, VALUE name)
{
    cipher_t *c;
    const mbedtls_cipher_info_t *info;
    int ret;

    TypedData_Get_Struct(self, cipher_t, &cipher_type, c);
    if (c->have_info) rb_raise(eCryptoError, "already initialized");

    info = mbedtls_cipher_info_from_string(StringValueCStr(name));
    if (!info) {
        rb_raise(eCryptoError, "unsupported cipher: %s",
                 StringValueCStr(name));
    }
    if ((ret = mbedtls_cipher_setup(&c->ctx, info)) != 0) {
        crypto_raise(ret, "mbedtls_cipher_setup");
    }
    c->have_info = 1;
    return self;
}

static VALUE
cipher_name(VALUE self)
{
    cipher_t *c = get_cipher(self);
    return rb_str_new_cstr(mbedtls_cipher_get_name(&c->ctx));
}

static VALUE
cipher_key_len(VALUE self)
{
    cipher_t *c = get_cipher(self);
    return INT2NUM(mbedtls_cipher_get_key_bitlen(&c->ctx) / 8);
}

static VALUE
cipher_iv_len(VALUE self)
{
    cipher_t *c = get_cipher(self);
    return INT2NUM(mbedtls_cipher_get_iv_size(&c->ctx));
}

static VALUE
cipher_block_size(VALUE self)
{
    cipher_t *c = get_cipher(self);
    return INT2NUM(mbedtls_cipher_get_block_size(&c->ctx));
}

static VALUE
cipher_mode(VALUE self)
{
    cipher_t *c = get_cipher(self);
    const char *s;
    switch (mbedtls_cipher_get_cipher_mode(&c->ctx)) {
        case MBEDTLS_MODE_ECB:        s = "ecb";        break;
        case MBEDTLS_MODE_CBC:        s = "cbc";        break;
        case MBEDTLS_MODE_CFB:        s = "cfb";        break;
        case MBEDTLS_MODE_OFB:        s = "ofb";        break;
        case MBEDTLS_MODE_CTR:        s = "ctr";        break;
        case MBEDTLS_MODE_GCM:        s = "gcm";        break;
        case MBEDTLS_MODE_STREAM:     s = "stream";     break;
        case MBEDTLS_MODE_CCM:        s = "ccm";        break;
        case MBEDTLS_MODE_XTS:        s = "xts";        break;
        case MBEDTLS_MODE_CHACHAPOLY: s = "chachapoly"; break;
        default:                      s = "none";       break;
    }
    return ID2SYM(rb_intern(s));
}

static VALUE
cipher_set_operation(VALUE self, VALUE op)
{
    cipher_t *c = get_cipher(self);
    int want = NUM2INT(op);
    if (want != MBEDTLS_ENCRYPT && want != MBEDTLS_DECRYPT) {
        rb_raise(eCryptoError, "bad operation");
    }
    c->operation = want;
    c->started = 0;
    c->pending_len = 0;
    return self;
}

static VALUE
cipher_set_key(VALUE self, VALUE key)
{
    cipher_t *c = get_cipher(self);
    size_t want = mbedtls_cipher_get_key_bitlen(&c->ctx) / 8;
    size_t len;

    StringValue(key);
    len = (size_t)RSTRING_LEN(key);
    if (len != want) {
        rb_raise(eCryptoError, "key must be %zu bytes, got %zu", want, len);
    }
    if (len > sizeof(c->key)) rb_raise(eCryptoError, "key too long");
    memcpy(c->key, RSTRING_PTR(key), len);
    c->key_len = len;
    c->key_set = 1;
    c->started = 0;
    c->pending_len = 0;
    return key;
}

static VALUE
cipher_set_iv(VALUE self, VALUE iv)
{
    cipher_t *c = get_cipher(self);
    size_t fixed = (size_t)mbedtls_cipher_get_iv_size(&c->ctx);
    size_t len;
    int aead = cipher_is_aead(c);

    StringValue(iv);
    len = (size_t)RSTRING_LEN(iv);
    /* AEAD modes take a variable-length nonce; everything else wants exactly
     * one block.  MBEDTLS_MAX_IV_LENGTH is 16, so a GCM nonce longer than
     * that cannot be represented -- say so rather than truncating. */
    if (aead) {
        if (len < 1 || len > MBEDTLS_MAX_IV_LENGTH) {
            rb_raise(eCryptoError,
                     "iv must be 1..%d bytes for this mode, got %zu",
                     MBEDTLS_MAX_IV_LENGTH, len);
        }
    } else if (len != fixed) {
        rb_raise(eCryptoError, "iv must be %zu bytes, got %zu", fixed, len);
    }
    memcpy(c->iv, RSTRING_PTR(iv), len);
    c->iv_len = len;
    c->iv_set = 1;
    c->started = 0;
    c->pending_len = 0;
    return iv;
}

static VALUE
cipher_set_padding(VALUE self, VALUE on)
{
    cipher_t *c = get_cipher(self);
    c->padding = RTEST(on) ? MBEDTLS_PADDING_PKCS7 : MBEDTLS_PADDING_NONE;
    c->started = 0;
    return on;
}

static VALUE
cipher_set_aad(VALUE self, VALUE aad)
{
    cipher_t *c = get_cipher(self);
    size_t len;

    if (!cipher_is_aead(c)) {
        rb_raise(eCryptoError, "cipher does not support authenticated data");
    }
    if (c->started) {
        rb_raise(eCryptoError,
                 "authenticated data must be set before any update");
    }
    StringValue(aad);
    len = (size_t)RSTRING_LEN(aad);
    if (c->aad) {
        crypto_wipe(c->aad, c->aad_len);
        xfree(c->aad);
        c->aad = 0;
        c->aad_len = 0;
    }
    if (len) {
        c->aad = (unsigned char *)xmalloc(len);
        memcpy(c->aad, RSTRING_PTR(aad), len);
        c->aad_len = len;
    }
    return aad;
}

/* Apply key/IV/padding and open the multi-part operation. */
static void
cipher_start(cipher_t *c)
{
    int ret;

    if (c->started) return;
    if (c->operation == MBEDTLS_OPERATION_NONE) {
        rb_raise(eCryptoError,
                 "cipher not initialized for encryption or decryption");
    }
    if (!c->key_set) rb_raise(eCryptoError, "key not set");

    /* mbedtls_cipher_set_padding_mode() accepts CBC and nothing else -- the
     * cipher layer has no padding for ECB, which is why lib/openssl.rb does
     * not offer the ECB modes at all. */
    if (mbedtls_cipher_get_cipher_mode(&c->ctx) == MBEDTLS_MODE_CBC) {
        if ((ret = mbedtls_cipher_set_padding_mode(&c->ctx, c->padding)) != 0) {
            crypto_raise(ret, "mbedtls_cipher_set_padding_mode");
        }
    }
    if ((ret = mbedtls_cipher_setkey(&c->ctx, c->key,
                                     (int)(c->key_len * 8),
                                     c->operation)) != 0) {
        crypto_raise(ret, "mbedtls_cipher_setkey");
    }
    if (mbedtls_cipher_get_iv_size(&c->ctx) > 0 || cipher_is_aead(c)) {
        if (!c->iv_set) {
            /* With no IV set, OpenSSL encrypts CBC/CTR/ECB with an all-zero
             * one -- verified against OpenSSL 3.5.0, byte for byte -- so we
             * do the same and stay interchangeable.
             *
             * For AEAD modes OpenSSL has no such default: it runs with
             * whatever happens to be in the EVP context, and the ciphertext
             * differs from run to run.  There is therefore nothing to be
             * compatible with, and quietly substituting a fixed zero nonce
             * would be the worst possible answer -- repeating a GCM nonce
             * under one key leaks the authentication key outright.  So we
             * refuse. */
            size_t n;
            if (cipher_is_aead(c)) {
                rb_raise(eCryptoError,
                         "iv (nonce) must be set explicitly for authenticated "
                         "ciphers");
            }
            n = (size_t)mbedtls_cipher_get_iv_size(&c->ctx);
            if (n == 0 || n > MBEDTLS_MAX_IV_LENGTH) n = MBEDTLS_MAX_IV_LENGTH;
            memset(c->iv, 0, sizeof(c->iv));
            c->iv_len = n;
            c->iv_set = 1;
        }
        if ((ret = mbedtls_cipher_set_iv(&c->ctx, c->iv, c->iv_len)) != 0) {
            crypto_raise(ret, "mbedtls_cipher_set_iv");
        }
    }
    if ((ret = mbedtls_cipher_reset(&c->ctx)) != 0) {
        crypto_raise(ret, "mbedtls_cipher_reset");
    }
    /* For GCM this is what calls mbedtls_gcm_starts(), so it has to happen
     * even when there is no additional data at all. */
    if (cipher_is_aead(c)) {
        if ((ret = mbedtls_cipher_update_ad(&c->ctx, c->aad,
                                            c->aad_len)) != 0) {
            crypto_raise(ret, "mbedtls_cipher_update_ad");
        }
    }
    c->pending_len = 0;
    c->started = 1;
}

static VALUE
cipher_start_m(VALUE self)
{
    cipher_start(get_cipher(self));
    return self;
}

static VALUE
cipher_reset(VALUE self)
{
    cipher_t *c = get_cipher(self);
    c->started = 0;
    c->pending_len = 0;
    return self;
}

static VALUE
cipher_update(VALUE self, VALUE data)
{
    cipher_t *c = get_cipher(self);
    const unsigned char *in;
    size_t ilen, olen = 0;
    VALUE out;
    int ret;

    StringValue(data);
    cipher_start(c);
    in = (const unsigned char *)RSTRING_PTR(data);
    ilen = (size_t)RSTRING_LEN(data);

    if (cipher_is_aead(c)) {
        size_t total = c->pending_len + ilen;
        size_t take = total & ~(size_t)15;
        size_t from_input;
        unsigned char *tmp;

        if (take == 0) {
            if (ilen) memcpy(c->pending + c->pending_len, in, ilen);
            c->pending_len = total;
            RB_GC_GUARD(data);
            return rb_str_new(0, 0);
        }
        from_input = take - c->pending_len;
        tmp = (unsigned char *)xmalloc(take);
        memcpy(tmp, c->pending, c->pending_len);
        memcpy(tmp + c->pending_len, in, from_input);
        out = rb_str_new(0, (long)take);
        ret = mbedtls_cipher_update(&c->ctx, tmp, take,
                                    (unsigned char *)RSTRING_PTR(out), &olen);
        crypto_wipe(tmp, take);
        xfree(tmp);
        if (ret != 0) crypto_raise(ret, "mbedtls_cipher_update");
        c->pending_len = total - take;
        if (c->pending_len) {
            memcpy(c->pending, in + from_input, c->pending_len);
        }
        rb_str_set_len(out, (long)olen);
        RB_GC_GUARD(data);
        return out;
    }

    /* CBC keeps at most one block back internally; CTR/stream emit 1:1. */
    out = rb_str_new(0, (long)(ilen + mbedtls_cipher_get_block_size(&c->ctx)
                               + MBEDTLS_MAX_BLOCK_LENGTH));
    ret = mbedtls_cipher_update(&c->ctx, in, ilen,
                                (unsigned char *)RSTRING_PTR(out), &olen);
    if (ret != 0) crypto_raise(ret, "mbedtls_cipher_update");
    rb_str_set_len(out, (long)olen);
    RB_GC_GUARD(data);
    return out;
}

static VALUE
cipher_final(VALUE self)
{
    cipher_t *c = get_cipher(self);
    size_t olen = 0, tail = 0;
    VALUE out;
    int ret;

    cipher_start(c);
    out = rb_str_new(0, (long)(2 * MBEDTLS_MAX_BLOCK_LENGTH));

    if (cipher_is_aead(c) && c->pending_len) {
        ret = mbedtls_cipher_update(&c->ctx, c->pending, c->pending_len,
                                    (unsigned char *)RSTRING_PTR(out), &tail);
        c->pending_len = 0;
        if (ret != 0) crypto_raise(ret, "mbedtls_cipher_update");
    }
    ret = mbedtls_cipher_finish(&c->ctx,
                                (unsigned char *)RSTRING_PTR(out) + tail,
                                &olen);
    if (ret != 0) crypto_raise(ret, "mbedtls_cipher_finish");
    rb_str_set_len(out, (long)(tail + olen));
    return out;
}

/* call-seq: cipher.write_tag(16) -> String */
static VALUE
cipher_write_tag(VALUE self, VALUE lenv)
{
    cipher_t *c = get_cipher(self);
    long len = NUM2LONG(lenv);
    VALUE out;
    int ret;

    if (!cipher_is_aead(c)) {
        rb_raise(eCryptoError, "cipher is not authenticated");
    }
    if (len < 1 || len > 16) rb_raise(eCryptoError, "bad tag length");
    out = rb_str_new(0, len);
    ret = mbedtls_cipher_write_tag(&c->ctx,
                                   (unsigned char *)RSTRING_PTR(out),
                                   (size_t)len);
    if (ret != 0) crypto_raise(ret, "mbedtls_cipher_write_tag");
    return out;
}

/* call-seq: cipher.check_tag(tag) -> true, or raises */
static VALUE
cipher_check_tag(VALUE self, VALUE tag)
{
    cipher_t *c = get_cipher(self);
    int ret;

    if (!cipher_is_aead(c)) {
        rb_raise(eCryptoError, "cipher is not authenticated");
    }
    StringValue(tag);
    ret = mbedtls_cipher_check_tag(&c->ctx,
                                   (const unsigned char *)RSTRING_PTR(tag),
                                   (size_t)RSTRING_LEN(tag));
    if (ret != 0) crypto_raise(ret, "authentication tag mismatch");
    return Qtrue;
}

/* ══════════════════════════════════════════════════════════════════════════
 * MbedTLS::Digest -- mbedtls_md_*
 * ══════════════════════════════════════════════════════════════════════════ */

typedef struct {
    mbedtls_md_context_t ctx;
    int setup;
} md_t;

static void
md_free_(void *ptr)
{
    md_t *m = (md_t *)ptr;
    if (!m) return;
    if (m->setup) mbedtls_md_free(&m->ctx);
    xfree(m);
}

static size_t
md_memsize(const void *ptr)
{
    return sizeof(md_t);
}

static const rb_data_type_t md_data_type = {
    "MbedTLS::Digest",
    {0, md_free_, md_memsize},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static const rb_data_type_t hmac_data_type = {
    "MbedTLS::HMAC",
    {0, md_free_, md_memsize},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static const mbedtls_md_info_t *
md_info_or_raise(VALUE name)
{
    const mbedtls_md_info_t *info;
    info = mbedtls_md_info_from_string(StringValueCStr(name));
    if (!info) {
        rb_raise(eCryptoError, "unsupported digest: %s", StringValueCStr(name));
    }
    return info;
}

static VALUE
md_alloc(VALUE klass)
{
    md_t *m;
    VALUE obj = TypedData_Make_Struct(klass, md_t, &md_data_type, m);
    mbedtls_md_init(&m->ctx);
    return obj;
}

static md_t *
get_md(VALUE self, const rb_data_type_t *t)
{
    md_t *m;
    TypedData_Get_Struct(self, md_t, t, m);
    if (!m->setup) rb_raise(eCryptoError, "digest not initialized");
    return m;
}

static VALUE
md_initialize(VALUE self, VALUE name)
{
    md_t *m;
    const mbedtls_md_info_t *info;
    int ret;

    TypedData_Get_Struct(self, md_t, &md_data_type, m);
    if (m->setup) rb_raise(eCryptoError, "already initialized");
    info = md_info_or_raise(name);
    if ((ret = mbedtls_md_setup(&m->ctx, info, 0)) != 0) {
        crypto_raise(ret, "mbedtls_md_setup");
    }
    m->setup = 1;
    if ((ret = mbedtls_md_starts(&m->ctx)) != 0) {
        crypto_raise(ret, "mbedtls_md_starts");
    }
    return self;
}

static VALUE
md_initialize_copy(VALUE self, VALUE other)
{
    md_t *dst, *src;
    int ret;

    if (self == other) return self;
    TypedData_Get_Struct(self, md_t, &md_data_type, dst);
    src = get_md(other, &md_data_type);
    if (dst->setup) {
        mbedtls_md_free(&dst->ctx);
        dst->setup = 0;
    }
    mbedtls_md_init(&dst->ctx);
    if ((ret = mbedtls_md_setup(&dst->ctx, src->ctx.md_info, 0)) != 0) {
        crypto_raise(ret, "mbedtls_md_setup");
    }
    dst->setup = 1;
    if ((ret = mbedtls_md_clone(&dst->ctx, &src->ctx)) != 0) {
        crypto_raise(ret, "mbedtls_md_clone");
    }
    return self;
}

static VALUE
md_update(VALUE self, VALUE data)
{
    md_t *m = get_md(self, &md_data_type);
    int ret;
    StringValue(data);
    ret = mbedtls_md_update(&m->ctx,
                            (const unsigned char *)RSTRING_PTR(data),
                            (size_t)RSTRING_LEN(data));
    if (ret != 0) crypto_raise(ret, "mbedtls_md_update");
    RB_GC_GUARD(data);
    return self;
}

static VALUE
md_finish(VALUE self)
{
    md_t *m = get_md(self, &md_data_type);
    unsigned char buf[MBEDTLS_MD_MAX_SIZE];
    size_t n = mbedtls_md_get_size(m->ctx.md_info);
    int ret = mbedtls_md_finish(&m->ctx, buf);
    if (ret != 0) crypto_raise(ret, "mbedtls_md_finish");
    return rb_str_new((const char *)buf, (long)n);
}

static VALUE
md_reset(VALUE self)
{
    md_t *m = get_md(self, &md_data_type);
    int ret = mbedtls_md_starts(&m->ctx);
    if (ret != 0) crypto_raise(ret, "mbedtls_md_starts");
    return self;
}

static VALUE
md_digest_length(VALUE self)
{
    md_t *m = get_md(self, &md_data_type);
    return INT2NUM(mbedtls_md_get_size(m->ctx.md_info));
}

static VALUE
md_block_length(VALUE self)
{
    md_t *m = get_md(self, &md_data_type);
    return INT2NUM(mbedtls_md_get_block_size(m->ctx.md_info));
}

static VALUE
md_name(VALUE self)
{
    md_t *m = get_md(self, &md_data_type);
    return rb_str_new_cstr(mbedtls_md_get_name(m->ctx.md_info));
}

/* ══════════════════════════════════════════════════════════════════════════
 * MbedTLS::HMAC -- mbedtls_md_hmac_*
 * ══════════════════════════════════════════════════════════════════════════ */

static VALUE
hmac_alloc(VALUE klass)
{
    md_t *m;
    VALUE obj = TypedData_Make_Struct(klass, md_t, &hmac_data_type, m);
    mbedtls_md_init(&m->ctx);
    return obj;
}

static VALUE
hmac_initialize(VALUE self, VALUE name, VALUE key)
{
    md_t *m;
    const mbedtls_md_info_t *info;
    int ret;

    TypedData_Get_Struct(self, md_t, &hmac_data_type, m);
    if (m->setup) rb_raise(eCryptoError, "already initialized");
    info = md_info_or_raise(name);
    StringValue(key);
    if ((ret = mbedtls_md_setup(&m->ctx, info, 1)) != 0) {
        crypto_raise(ret, "mbedtls_md_setup");
    }
    m->setup = 1;
    ret = mbedtls_md_hmac_starts(&m->ctx,
                                 (const unsigned char *)RSTRING_PTR(key),
                                 (size_t)RSTRING_LEN(key));
    if (ret != 0) crypto_raise(ret, "mbedtls_md_hmac_starts");
    RB_GC_GUARD(key);
    return self;
}

/*
 * mbedtls_md_clone() only copies the hash half of the context; the HMAC half
 * (the 2 * block_size ipad/opad scratch that mbedtls_md_setup allocates when
 * hmac=1) has to come along too, otherwise the clone cannot finish.
 */
static void
hmac_copy_ctx(mbedtls_md_context_t *dst, const mbedtls_md_context_t *src)
{
    int ret;
    if ((ret = mbedtls_md_setup(dst, src->md_info, 1)) != 0) {
        crypto_raise(ret, "mbedtls_md_setup");
    }
    if ((ret = mbedtls_md_clone(dst, src)) != 0) {
        mbedtls_md_free(dst);
        crypto_raise(ret, "mbedtls_md_clone");
    }
    memcpy(dst->hmac_ctx, src->hmac_ctx,
           (size_t)(2 * mbedtls_md_get_block_size(src->md_info)));
}

static VALUE
hmac_initialize_copy(VALUE self, VALUE other)
{
    md_t *dst, *src;

    if (self == other) return self;
    TypedData_Get_Struct(self, md_t, &hmac_data_type, dst);
    src = get_md(other, &hmac_data_type);
    if (dst->setup) {
        mbedtls_md_free(&dst->ctx);
        dst->setup = 0;
    }
    mbedtls_md_init(&dst->ctx);
    hmac_copy_ctx(&dst->ctx, &src->ctx);
    dst->setup = 1;
    return self;
}

static VALUE
hmac_update(VALUE self, VALUE data)
{
    md_t *m = get_md(self, &hmac_data_type);
    int ret;
    StringValue(data);
    ret = mbedtls_md_hmac_update(&m->ctx,
                                 (const unsigned char *)RSTRING_PTR(data),
                                 (size_t)RSTRING_LEN(data));
    if (ret != 0) crypto_raise(ret, "mbedtls_md_hmac_update");
    RB_GC_GUARD(data);
    return self;
}

/*
 * Non-destructive: the running state is cloned and the clone is finished, so
 * #update may continue afterwards (this is what OpenSSL::HMAC#digest does).
 */
static VALUE
hmac_digest(VALUE self)
{
    md_t *m = get_md(self, &hmac_data_type);
    mbedtls_md_context_t tmp;
    unsigned char buf[MBEDTLS_MD_MAX_SIZE];
    size_t n = mbedtls_md_get_size(m->ctx.md_info);
    int ret;

    mbedtls_md_init(&tmp);
    hmac_copy_ctx(&tmp, &m->ctx);
    ret = mbedtls_md_hmac_finish(&tmp, buf);
    mbedtls_md_free(&tmp);
    if (ret != 0) crypto_raise(ret, "mbedtls_md_hmac_finish");
    return rb_str_new((const char *)buf, (long)n);
}

static VALUE
hmac_reset(VALUE self)
{
    md_t *m = get_md(self, &hmac_data_type);
    int ret = mbedtls_md_hmac_reset(&m->ctx);
    if (ret != 0) crypto_raise(ret, "mbedtls_md_hmac_reset");
    return self;
}

static VALUE
hmac_digest_length(VALUE self)
{
    md_t *m = get_md(self, &hmac_data_type);
    return INT2NUM(mbedtls_md_get_size(m->ctx.md_info));
}

static VALUE
hmac_block_length(VALUE self)
{
    md_t *m = get_md(self, &hmac_data_type);
    return INT2NUM(mbedtls_md_get_block_size(m->ctx.md_info));
}

static VALUE
hmac_name(VALUE self)
{
    md_t *m = get_md(self, &hmac_data_type);
    return rb_str_new_cstr(mbedtls_md_get_name(m->ctx.md_info));
}

/* ══════════════════════════════════════════════════════════════════════════
 * Module functions
 * ══════════════════════════════════════════════════════════════════════════ */

/* call-seq: MbedTLS.hmac("SHA256", key, data) -> String */
static VALUE
crypto_hmac(VALUE self, VALUE name, VALUE key, VALUE data)
{
    const mbedtls_md_info_t *info = md_info_or_raise(name);
    unsigned char buf[MBEDTLS_MD_MAX_SIZE];
    int ret;

    StringValue(key);
    StringValue(data);
    ret = mbedtls_md_hmac(info,
                          (const unsigned char *)RSTRING_PTR(key),
                          (size_t)RSTRING_LEN(key),
                          (const unsigned char *)RSTRING_PTR(data),
                          (size_t)RSTRING_LEN(data), buf);
    if (ret != 0) crypto_raise(ret, "mbedtls_md_hmac");
    RB_GC_GUARD(key);
    RB_GC_GUARD(data);
    return rb_str_new((const char *)buf, mbedtls_md_get_size(info));
}

/* call-seq: MbedTLS.digest("SHA256", data) -> String */
static VALUE
crypto_digest(VALUE self, VALUE name, VALUE data)
{
    const mbedtls_md_info_t *info = md_info_or_raise(name);
    unsigned char buf[MBEDTLS_MD_MAX_SIZE];
    int ret;

    StringValue(data);
    ret = mbedtls_md(info, (const unsigned char *)RSTRING_PTR(data),
                     (size_t)RSTRING_LEN(data), buf);
    if (ret != 0) crypto_raise(ret, "mbedtls_md");
    RB_GC_GUARD(data);
    return rb_str_new((const char *)buf, mbedtls_md_get_size(info));
}

/* call-seq: MbedTLS.pbkdf2_hmac("SHA256", pass, salt, iters, keylen) */
static VALUE
crypto_pbkdf2_hmac(VALUE self, VALUE name, VALUE pass, VALUE salt,
                   VALUE iters, VALUE keylen)
{
    const mbedtls_md_info_t *info = md_info_or_raise(name);
    mbedtls_md_context_t ctx;
    unsigned long n = NUM2ULONG(iters);
    long outlen = NUM2LONG(keylen);
    VALUE out;
    int ret;

    if (n < 1) rb_raise(rb_eArgError, "iterations must be positive");
    if (outlen < 0) rb_raise(rb_eArgError, "length must not be negative");
    if (n > 0xffffffffUL) rb_raise(rb_eArgError, "iterations too large");
    StringValue(pass);
    StringValue(salt);

    mbedtls_md_init(&ctx);
    if ((ret = mbedtls_md_setup(&ctx, info, 1)) != 0) {
        mbedtls_md_free(&ctx);
        crypto_raise(ret, "mbedtls_md_setup");
    }
    out = rb_str_new(0, outlen);
    ret = mbedtls_pkcs5_pbkdf2_hmac(&ctx,
                                    RSTRING_PTR(pass), (size_t)RSTRING_LEN(pass),
                                    RSTRING_PTR(salt), (size_t)RSTRING_LEN(salt),
                                    (unsigned)n, (uint32_t)outlen,
                                    (unsigned char *)RSTRING_PTR(out));
    mbedtls_md_free(&ctx);
    if (ret != 0) crypto_raise(ret, "mbedtls_pkcs5_pbkdf2_hmac");
    RB_GC_GUARD(pass);
    RB_GC_GUARD(salt);
    return out;
}

/*
 * call-seq: MbedTLS.random_bytes(n) -> String
 *
 * Bytes come from cosmopolitan's getrandom(), i.e. the operating system
 * CSPRNG (getrandom(2) on Linux, RtlGenRandom on Windows, arc4random on the
 * BSDs, /dev/urandom as the last resort).  That is deliberately preferred
 * over seeding an mbedtls_ctr_drbg here, because in *this* tree
 * mbedtls_hardware_poll() -- the only entropy source mbedtls_entropy has --
 * is itself a call to getrandom() (third_party/mbedtls/rando.c).  Layering a
 * userspace DRBG on top would add fork-unsafe state and a seeding failure
 * mode without adding a single bit of entropy.  There is no fallback: if the
 * kernel will not give us randomness we raise.
 */
static VALUE
crypto_random_bytes(VALUE self, VALUE lenv)
{
    long n = NUM2LONG(lenv);
    VALUE out;
    unsigned char *p;
    size_t got = 0;

    if (n < 0) rb_raise(rb_eArgError, "negative length");
    out = rb_str_new(0, n);
    p = (unsigned char *)RSTRING_PTR(out);
    while (got < (size_t)n) {
        ssize_t rc = getrandom(p + got, (size_t)n - got, 0);
        if (rc < 0) {
            if (errno == EINTR) continue;
            rb_raise(eCryptoError, "getrandom failed (errno %d)", errno);
        }
        if (rc == 0) rb_raise(eCryptoError, "getrandom returned no bytes");
        got += (size_t)rc;
    }
    return out;
}

/* call-seq: MbedTLS.constant_time_equal?(a, b) -> true/false */
static VALUE
crypto_ct_equal(VALUE self, VALUE a, VALUE b)
{
    StringValue(a);
    StringValue(b);
    if (RSTRING_LEN(a) != RSTRING_LEN(b)) {
        rb_raise(rb_eArgError, "inputs must be of equal length");
    }
    return timingsafe_bcmp(RSTRING_PTR(a), RSTRING_PTR(b),
                           (size_t)RSTRING_LEN(a)) == 0 ? Qtrue : Qfalse;
}

/* call-seq: MbedTLS.cipher_supported?("AES-256-GCM") -> true/false */
static VALUE
crypto_cipher_supported(VALUE self, VALUE name)
{
    return mbedtls_cipher_info_from_string(StringValueCStr(name)) ? Qtrue
                                                                 : Qfalse;
}

/* call-seq: MbedTLS.digest_supported?("SHA256") -> true/false */
static VALUE
crypto_digest_supported(VALUE self, VALUE name)
{
    return mbedtls_md_info_from_string(StringValueCStr(name)) ? Qtrue : Qfalse;
}

void
Init_mbedtls_crypto(VALUE mod)
{
    mMbedTLS = mod;

    eCryptoError = rb_define_class_under(mMbedTLS, "CryptoError",
                                         rb_eStandardError);

    cCipher = rb_define_class_under(mMbedTLS, "Cipher", rb_cObject);
    rb_define_alloc_func(cCipher, cipher_alloc);
    rb_define_method(cCipher, "initialize", cipher_initialize, 1);
    rb_define_method(cCipher, "name", cipher_name, 0);
    rb_define_method(cCipher, "key_len", cipher_key_len, 0);
    rb_define_method(cCipher, "iv_len", cipher_iv_len, 0);
    rb_define_method(cCipher, "block_size", cipher_block_size, 0);
    rb_define_method(cCipher, "mode", cipher_mode, 0);
    rb_define_method(cCipher, "operation=", cipher_set_operation, 1);
    rb_define_method(cCipher, "key=", cipher_set_key, 1);
    rb_define_method(cCipher, "iv=", cipher_set_iv, 1);
    rb_define_method(cCipher, "padding=", cipher_set_padding, 1);
    rb_define_method(cCipher, "auth_data=", cipher_set_aad, 1);
    rb_define_method(cCipher, "start", cipher_start_m, 0);
    rb_define_method(cCipher, "reset", cipher_reset, 0);
    rb_define_method(cCipher, "update", cipher_update, 1);
    rb_define_method(cCipher, "final", cipher_final, 0);
    rb_define_method(cCipher, "write_tag", cipher_write_tag, 1);
    rb_define_method(cCipher, "check_tag", cipher_check_tag, 1);
    rb_define_const(cCipher, "ENCRYPT", INT2NUM(MBEDTLS_ENCRYPT));
    rb_define_const(cCipher, "DECRYPT", INT2NUM(MBEDTLS_DECRYPT));

    cDigest = rb_define_class_under(mMbedTLS, "Digest", rb_cObject);
    rb_define_alloc_func(cDigest, md_alloc);
    rb_define_method(cDigest, "initialize", md_initialize, 1);
    rb_define_method(cDigest, "initialize_copy", md_initialize_copy, 1);
    rb_define_method(cDigest, "update", md_update, 1);
    rb_define_method(cDigest, "finish", md_finish, 0);
    rb_define_method(cDigest, "reset", md_reset, 0);
    rb_define_method(cDigest, "digest_length", md_digest_length, 0);
    rb_define_method(cDigest, "block_length", md_block_length, 0);
    rb_define_method(cDigest, "name", md_name, 0);

    cHMAC = rb_define_class_under(mMbedTLS, "HMAC", rb_cObject);
    rb_define_alloc_func(cHMAC, hmac_alloc);
    rb_define_method(cHMAC, "initialize", hmac_initialize, 2);
    rb_define_method(cHMAC, "initialize_copy", hmac_initialize_copy, 1);
    rb_define_method(cHMAC, "update", hmac_update, 1);
    rb_define_method(cHMAC, "digest", hmac_digest, 0);
    rb_define_method(cHMAC, "reset", hmac_reset, 0);
    rb_define_method(cHMAC, "digest_length", hmac_digest_length, 0);
    rb_define_method(cHMAC, "block_length", hmac_block_length, 0);
    rb_define_method(cHMAC, "name", hmac_name, 0);

    rb_define_module_function(mMbedTLS, "hmac", crypto_hmac, 3);
    rb_define_module_function(mMbedTLS, "digest", crypto_digest, 2);
    rb_define_module_function(mMbedTLS, "pbkdf2_hmac", crypto_pbkdf2_hmac, 5);
    rb_define_module_function(mMbedTLS, "random_bytes", crypto_random_bytes, 1);
    rb_define_module_function(mMbedTLS, "constant_time_equal?",
                              crypto_ct_equal, 2);
    rb_define_module_function(mMbedTLS, "cipher_supported?",
                              crypto_cipher_supported, 1);
    rb_define_module_function(mMbedTLS, "digest_supported?",
                              crypto_digest_supported, 1);
}
