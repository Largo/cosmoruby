#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_MBEDTLS

THIRD_PARTY_RUBY_EXT_MBEDTLS_A = o/$(MODE)/third_party/ruby/ext/mbedtls/mbedtls.a
THIRD_PARTY_RUBY_EXT_MBEDTLS_FILES := $(wildcard third_party/ruby/ext/mbedtls/*)
THIRD_PARTY_RUBY_EXT_MBEDTLS_HDRS = $(filter %.h,$(THIRD_PARTY_RUBY_EXT_MBEDTLS_FILES))
THIRD_PARTY_RUBY_EXT_MBEDTLS_SRCS = third_party/ruby/ext/mbedtls/mbedtls.c
THIRD_PARTY_RUBY_EXT_MBEDTLS_OBJS = $(THIRD_PARTY_RUBY_EXT_MBEDTLS_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_MBEDTLS_A):			\
		$(THIRD_PARTY_RUBY_EXT_MBEDTLS_OBJS)


# Compiler flags for mbedtls extension
o/$(MODE)/third_party/ruby/ext/mbedtls/%.o: private	\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-Ithird_party/mbedtls			\
		-Inet/https				\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN

$(THIRD_PARTY_RUBY_EXT_MBEDTLS_OBJS): third_party/ruby/ext/mbedtls/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/mbedtls
o/$(MODE)/third_party/ruby/ext/mbedtls: $(THIRD_PARTY_RUBY_EXT_MBEDTLS_A)
