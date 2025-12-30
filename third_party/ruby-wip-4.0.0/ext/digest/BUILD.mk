#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_DIGEST

THIRD_PARTY_RUBY_EXT_DIGEST_A = o/$(MODE)/third_party/ruby/ext/digest/digest.a
THIRD_PARTY_RUBY_EXT_DIGEST_FILES := $(wildcard third_party/ruby/ext/digest/*.c third_party/ruby/ext/digest/*/*.c)
THIRD_PARTY_RUBY_EXT_DIGEST_HDRS = $(wildcard third_party/ruby/ext/digest/*.h third_party/ruby/ext/digest/*/*.h)
THIRD_PARTY_RUBY_EXT_DIGEST_SRCS = \
	third_party/ruby/ext/digest/digest.c \
	third_party/ruby/ext/digest/md5/md5init.c \
	third_party/ruby/ext/digest/md5/md5.c \
	third_party/ruby/ext/digest/sha1/sha1init.c \
	third_party/ruby/ext/digest/sha1/sha1.c \
	third_party/ruby/ext/digest/sha2/sha2init.c \
	third_party/ruby/ext/digest/sha2/sha2.c

THIRD_PARTY_RUBY_EXT_DIGEST_OBJS = $(THIRD_PARTY_RUBY_EXT_DIGEST_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_DIGEST_A):			\
		third_party/ruby/ext/digest/		\
		$(THIRD_PARTY_RUBY_EXT_DIGEST_OBJS)


# Compiler flags for digest extension
o/$(MODE)/third_party/ruby/ext/digest/%.o: private	\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-Ithird_party/ruby/ext/digest		\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN

$(THIRD_PARTY_RUBY_EXT_DIGEST_OBJS): third_party/ruby/ext/digest/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/digest
o/$(MODE)/third_party/ruby/ext/digest: $(THIRD_PARTY_RUBY_EXT_DIGEST_A)
