#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_SOCKET

THIRD_PARTY_RUBY_EXT_SOCKET_A = o/$(MODE)/third_party/ruby/ext/socket/socket.a
THIRD_PARTY_RUBY_EXT_SOCKET_FILES := $(wildcard third_party/ruby/ext/socket/*)
THIRD_PARTY_RUBY_EXT_SOCKET_HDRS = $(filter %.h,$(THIRD_PARTY_RUBY_EXT_SOCKET_FILES))

THIRD_PARTY_RUBY_EXT_SOCKET_SRCS =			\
	third_party/ruby/ext/socket/ancdata.c		\
	third_party/ruby/ext/socket/basicsocket.c	\
	third_party/ruby/ext/socket/constants.c		\
	third_party/ruby/ext/socket/ifaddr.c		\
	third_party/ruby/ext/socket/init.c		\
	third_party/ruby/ext/socket/ipsocket.c		\
	third_party/ruby/ext/socket/option.c		\
	third_party/ruby/ext/socket/raddrinfo.c		\
	third_party/ruby/ext/socket/socket.c		\
	third_party/ruby/ext/socket/sockssocket.c	\
	third_party/ruby/ext/socket/tcpserver.c		\
	third_party/ruby/ext/socket/tcpsocket.c		\
	third_party/ruby/ext/socket/udpsocket.c		\
	third_party/ruby/ext/socket/unixserver.c	\
	third_party/ruby/ext/socket/unixsocket.c

THIRD_PARTY_RUBY_EXT_SOCKET_OBJS = $(THIRD_PARTY_RUBY_EXT_SOCKET_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_SOCKET_A):			\
		third_party/ruby/ext/socket/		\
		$(THIRD_PARTY_RUBY_EXT_SOCKET_OBJS)


# Compiler flags for socket extension
o/$(MODE)/third_party/ruby/ext/socket/%.o: private	\
	CPPFLAGS +=					\
		-DRUBY_EXTCONF_H=\"ext/socket/extconf.h\"

o/$(MODE)/third_party/ruby/ext/socket/%.o: private	\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-Ithird_party/ruby/ext/socket		\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN			\
		-DINET6

$(THIRD_PARTY_RUBY_EXT_SOCKET_OBJS): third_party/ruby/ext/socket/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/socket
o/$(MODE)/third_party/ruby/ext/socket: $(THIRD_PARTY_RUBY_EXT_SOCKET_A)
