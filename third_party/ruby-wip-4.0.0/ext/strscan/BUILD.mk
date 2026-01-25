#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_STRSCAN

THIRD_PARTY_RUBY_EXT_STRSCAN_A = o/$(MODE)/third_party/ruby/ext/strscan/strscan.a
THIRD_PARTY_RUBY_EXT_STRSCAN_SRCS = third_party/ruby/ext/strscan/strscan.c
THIRD_PARTY_RUBY_EXT_STRSCAN_OBJS = $(THIRD_PARTY_RUBY_EXT_STRSCAN_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_STRSCAN_A):			\
		$(THIRD_PARTY_RUBY_EXT_STRSCAN_OBJS)

# Compiler flags for strscan extension
o/$(MODE)/third_party/ruby/ext/strscan/%.o: private	\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN			\
		-DHAVE_RB_REG_ONIG_MATCH

$(THIRD_PARTY_RUBY_EXT_STRSCAN_OBJS): third_party/ruby/ext/strscan/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/strscan
o/$(MODE)/third_party/ruby/ext/strscan: $(THIRD_PARTY_RUBY_EXT_STRSCAN_A)
