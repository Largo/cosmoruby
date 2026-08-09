#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘
#
# OVERVIEW
#
#   puma 8.0.2 ruby gem -- the `puma/puma_http11` native extension (Ragel HTTP
#   parser), statically linked.
#
# NOTES
#
#   Sources come from the `puma` rubygem (see README.cosmo).  http11_parser.c
#   is generated from http11_parser.rl by Ragel and is shipped pre-generated,
#   so no Ragel is needed at build time; the .rl files are vendored for
#   reference only.
#
# SSL IS COMPILED OUT -- ON PURPOSE
#
#   ext/puma_http11/mini_ssl.c is upstream's OpenSSL binding.  This build's
#   `openssl` is a ~400 line MbedTLS shim (third_party/ruby/ext/openssl), not
#   Ruby's OpenSSL extension, and it exposes none of the OpenSSL C API that
#   mini_ssl.c uses (BIO_*, SSL_CTX_*, X509_*, DH_*).  So mini_ssl.c is
#   compiled with HAVE_OPENSSL_BIO_H undefined, which is exactly what upstream
#   does when extconf.rb cannot find OpenSSL (or when PUMA_DISABLE_SSL is set):
#   the whole file is `#ifdef HAVE_OPENSSL_BIO_H`, so it becomes an empty
#   translation unit, and puma_http11.c skips its Init_mini_ssl() call under
#   the same guard.
#
#   The Ruby side handles this natively.  lib/puma.rb computes
#
#       HAS_SSL = const_defined?(:MiniSSL, false) && MiniSSL.const_defined?(:Engine, false)
#
#   which becomes false, and `Puma::Server#run` then simply never takes an SSL
#   path.  Consequences: `bind "ssl://..."` and puma's `ssl_bind` DSL raise,
#   and `Puma::MiniSSL::Context` does not exist.  A packaged Rails app behind a
#   reverse proxy (or serving plain HTTP on localhost) is unaffected.
#
#   mini_ssl.c is still listed as a source so that the vendored tree and the
#   build stay in one-to-one correspondence, and so a future MbedTLS-backed
#   port only has to flip a flag.  It contributes zero bytes today.
#
#   extconf.rb's remaining probe:
#
#     HAVE_RB_EXT_RACTOR_SAFE   ruby >= 3.0 -> yes (mkmf defines it from
#                               ruby/ruby.h; puma_http11.c marks itself
#                               ractor-safe under this guard)
#
#   -Wno-implicit-fallthrough matches what upstream passes when it turns
#   warnings into errors: the Ragel-generated state machine in
#   http11_parser.c falls through between states by construction.

PKGS += THIRD_PARTY_RUBY_EXT_PUMA

THIRD_PARTY_RUBY_EXT_PUMA_A = o/$(MODE)/third_party/ruby/ext/puma/puma.a
THIRD_PARTY_RUBY_EXT_PUMA_FILES :=					\
	$(wildcard third_party/ruby/ext/puma/puma_http11/*)
THIRD_PARTY_RUBY_EXT_PUMA_HDRS =					\
	$(filter %.h,$(THIRD_PARTY_RUBY_EXT_PUMA_FILES))

THIRD_PARTY_RUBY_EXT_PUMA_SRCS =					\
	third_party/ruby/ext/puma/puma_http11/http11_parser.c		\
	third_party/ruby/ext/puma/puma_http11/mini_ssl.c		\
	third_party/ruby/ext/puma/puma_http11/puma_http11.c

THIRD_PARTY_RUBY_EXT_PUMA_OBJS =					\
	$(THIRD_PARTY_RUBY_EXT_PUMA_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_PUMA_A):						\
		$(THIRD_PARTY_RUBY_EXT_PUMA_OBJS)

o/$(MODE)/third_party/ruby/ext/puma/%.o: private				\
	CFLAGS +=							\
		-Ithird_party/ruby/include				\
		-Ithird_party/ruby					\
		-Ithird_party/ruby/ext/puma/puma_http11			\
		-Wno-implicit-fallthrough				\
		-DRUBY_EXPORT						\
		-DRUBY_COSMOPOLITAN					\
		-DHAVE_RB_EXT_RACTOR_SAFE

$(THIRD_PARTY_RUBY_EXT_PUMA_OBJS):					\
	$(THIRD_PARTY_RUBY_EXT_PUMA_HDRS) third_party/ruby/ext/puma/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/puma
o/$(MODE)/third_party/ruby/ext/puma: $(THIRD_PARTY_RUBY_EXT_PUMA_A)
