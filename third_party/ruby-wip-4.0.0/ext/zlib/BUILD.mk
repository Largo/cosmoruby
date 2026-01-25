#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_ZLIB

THIRD_PARTY_RUBY_EXT_ZLIB_A = o/$(MODE)/third_party/ruby/ext/zlib/zlib.a
THIRD_PARTY_RUBY_EXT_ZLIB_FILES := $(wildcard third_party/ruby/ext/zlib/*)
THIRD_PARTY_RUBY_EXT_ZLIB_HDRS = $(filter %.h,$(THIRD_PARTY_RUBY_EXT_ZLIB_FILES))
THIRD_PARTY_RUBY_EXT_ZLIB_SRCS = third_party/ruby/ext/zlib/zlib.c
THIRD_PARTY_RUBY_EXT_ZLIB_OBJS = $(THIRD_PARTY_RUBY_EXT_ZLIB_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_ZLIB_A):			\
		$(THIRD_PARTY_RUBY_EXT_ZLIB_OBJS)


# Compiler flags for zlib extension
o/$(MODE)/third_party/ruby/ext/zlib/%.o: private	\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-Ithird_party/zlib			\
		-DHAVE_TYPE_Z_CRC_T			\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN

$(THIRD_PARTY_RUBY_EXT_ZLIB_OBJS): $(THIRD_PARTY_RUBY_EXT_ZLIB_HDRS) third_party/ruby/ext/zlib/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/zlib
o/$(MODE)/third_party/ruby/ext/zlib: $(THIRD_PARTY_RUBY_EXT_ZLIB_A)
