#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_TEST_FILE

THIRD_PARTY_RUBY_EXT_TEST_FILE_A = o/$(MODE)/third_party/ruby/ext/-test-/file/file.a
THIRD_PARTY_RUBY_EXT_TEST_FILE_SRCS = \
	third_party/ruby/ext/-test-/file/init.c \
	third_party/ruby/ext/-test-/file/fs.c \
	third_party/ruby/ext/-test-/file/newline_conv.c \
	third_party/ruby/ext/-test-/file/stat.c

THIRD_PARTY_RUBY_EXT_TEST_FILE_OBJS = $(THIRD_PARTY_RUBY_EXT_TEST_FILE_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_TEST_FILE_A):		\
		$(THIRD_PARTY_RUBY_EXT_TEST_FILE_OBJS)

# Compiler flags for test file extension
o/$(MODE)/third_party/ruby/ext/-test-/file/%.o: private	\
	CFLAGS +=				\
		-Ithird_party/ruby/include	\
		-Ithird_party/ruby		\
		-DRUBY_EXPORT			\
		-DRUBY_COSMOPOLITAN		\
		-D'TEST_INIT_FUNCS(X)=X(fs);X(newline_conv);X(stat);'

$(THIRD_PARTY_RUBY_EXT_TEST_FILE_OBJS): third_party/ruby/ext/-test-/file/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/-test-/file
o/$(MODE)/third_party/ruby/ext/-test-/file: $(THIRD_PARTY_RUBY_EXT_TEST_FILE_A)