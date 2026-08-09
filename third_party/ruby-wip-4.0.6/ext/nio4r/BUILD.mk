#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘
#
# OVERVIEW
#
#   nio4r 2.7.5 ruby gem (native extension, bundles libev 4.x), statically
#   linked.  This is puma's selector, and therefore a hard requirement for
#   running Rails inside an APE.
#
# NOTES
#
#   The gem's own directory layout is preserved (ext/nio4r/ and ext/libev/
#   below this directory) because ext/nio4r/nio4r_ext.c does
#   `#include "../libev/ev.c"` -- libev is a unity build, ev.c is the only
#   libev translation unit and it #includes the enabled backends.  Keeping the
#   layout is what makes this a *zero patch* vendoring.
#
# BACKEND SELECTION -- THE ONE REAL PORTABILITY DECISION
#
#   Cosmopolitan has poll() and select() on every host it supports (Linux,
#   macOS, Windows, FreeBSD, OpenBSD, NetBSD): libc/sock/poll.c plus the
#   poll-nt.c / poll-sysv.c / poll-metal.c backends.  It has *no* epoll and
#   *no* kqueue: there is no <sys/epoll.h> or <sys/event.h> anywhere in the
#   tree, only bare sys_epoll_*.S / sys_kqueue.S syscall stubs with no libc
#   wrapper and no non-Linux fallback.  So:
#
#     EV_USE_POLL=1     the backend we actually run on, everywhere
#     EV_USE_SELECT=1   libev's unconditional fallback; also what it uses if
#                       poll() ever refuses an fd
#     EV_USE_EPOLL=0    no <sys/epoll.h> under cosmopolitan
#     EV_USE_KQUEUE=0   no <sys/event.h> under cosmopolitan
#     EV_USE_PORT=0     Solaris only
#     EV_USE_LINUXAIO=0 / EV_USE_IOURING=0    Linux only, and both need
#                       <linux/*.h> headers cosmopolitan does not ship
#
#   The Linux-only *notification* helpers are off for the same reason -- they
#   would compile to Linux syscalls that return ENOSYS on a Mac or on Windows:
#
#     EV_USE_EVENTFD=0  libev falls back to a pipe for its async wakeup
#     EV_USE_SIGNALFD=0 / EV_USE_INOTIFY=0 / EV_USE_TIMERFD=0
#
#   Left on, because cosmopolitan implements them portably:
#
#     EV_USE_MONOTONIC=1   clock_gettime(CLOCK_MONOTONIC)
#     EV_USE_REALTIME=1    clock_gettime(CLOCK_REALTIME)
#     EV_USE_NANOSLEEP=1   nanosleep()
#     EV_USE_CLOCK_SYSCALL=0  glibc-specific raw-syscall shortcut; cosmopolitan
#                          is not glibc, so use the libc entry points
#
#   This is deliberately the slow-but-portable choice the task asked for: poll
#   is O(n) in watched descriptors where epoll/kqueue are O(1).  For a packaged
#   single-process Rails app serving a handful of connections that is
#   irrelevant; for 10k connections it would not be.
#
#   EV_STANDALONE=1 stops libev looking for an autoconf "config.h".
#
#   COSMO_RUBY_HOST_POLL is NOT a libev flag: it tells
#   third_party/ruby/include/errno_wrapper.h to keep its hands off <poll.h>
#   for these translation units. That header otherwise hard-codes the Linux
#   POLL* numbering, which on Windows means POLLIN(1) is really Winsock's
#   POLLERR and cosmopolitan's poll-nt.c masks it away -- poll() then never
#   reports a socket ready and every select() times out. Linux and macOS did
#   not care; Windows CI failed six checks in test_nio4r.rb until this flag
#   was added. See the comment in errno_wrapper.h.
#
#   extconf.rb's other probes:
#
#     HAVE_UNISTD_H         yes
#     HAVE_SYS_SELECT_H     yes (needed by ev_select.c)
#     HAVE_SYS_RESOURCE_H   yes (libev uses getrlimit to size the select fd set)
#     HAVE_POLL_H           yes (needed by ev_poll.c)
#     HAVE_RB_IO_DESCRIPTOR ruby >= 3.1 -> yes
#
#   Escape hatch if libev ever misbehaves on some host: NIO4R_PURE=true in the
#   environment makes lib/nio.rb use the pure-Ruby Kernel.select engine, which
#   is shipped alongside (lib/nio/selector.rb).
#
#   -fno-strict-aliasing mirrors what extconf.rb appends to CONFIG["optflags"];
#   libev's watcher type-punning needs it.

PKGS += THIRD_PARTY_RUBY_EXT_NIO4R

THIRD_PARTY_RUBY_EXT_NIO4R_A = o/$(MODE)/third_party/ruby/ext/nio4r/nio4r.a
THIRD_PARTY_RUBY_EXT_NIO4R_FILES :=					\
	$(wildcard third_party/ruby/ext/nio4r/ext/nio4r/*)		\
	$(wildcard third_party/ruby/ext/nio4r/ext/libev/*)
THIRD_PARTY_RUBY_EXT_NIO4R_HDRS =					\
	$(filter %.h,$(THIRD_PARTY_RUBY_EXT_NIO4R_FILES))		\
	third_party/ruby/ext/nio4r/ext/libev/ev.c			\
	third_party/ruby/ext/nio4r/ext/libev/ev_poll.c			\
	third_party/ruby/ext/nio4r/ext/libev/ev_select.c

# Only ext/nio4r/*.c are translation units.  ext/libev/*.c are #included by
# nio4r_ext.c (ev.c) and by ev.c itself (ev_poll.c, ev_select.c).
THIRD_PARTY_RUBY_EXT_NIO4R_SRCS =					\
	third_party/ruby/ext/nio4r/ext/nio4r/bytebuffer.c		\
	third_party/ruby/ext/nio4r/ext/nio4r/monitor.c			\
	third_party/ruby/ext/nio4r/ext/nio4r/nio4r_ext.c		\
	third_party/ruby/ext/nio4r/ext/nio4r/selector.c

THIRD_PARTY_RUBY_EXT_NIO4R_OBJS =					\
	$(THIRD_PARTY_RUBY_EXT_NIO4R_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_NIO4R_A):					\
		$(THIRD_PARTY_RUBY_EXT_NIO4R_OBJS)

o/$(MODE)/third_party/ruby/ext/nio4r/%.o: private			\
	CFLAGS +=							\
		-Ithird_party/ruby/include				\
		-Ithird_party/ruby					\
		-Ithird_party/ruby/ext/nio4r/ext/nio4r			\
		-Ithird_party/ruby/ext/nio4r/ext/libev			\
		-fno-strict-aliasing					\
		-DRUBY_EXPORT						\
		-DRUBY_COSMOPOLITAN					\
		-DCOSMO_RUBY_HOST_POLL					\
		-DEV_STANDALONE=1					\
		-DEV_USE_POLL=1						\
		-DEV_USE_SELECT=1					\
		-DEV_USE_EPOLL=0					\
		-DEV_USE_KQUEUE=0					\
		-DEV_USE_PORT=0						\
		-DEV_USE_LINUXAIO=0					\
		-DEV_USE_IOURING=0					\
		-DEV_USE_INOTIFY=0					\
		-DEV_USE_SIGNALFD=0					\
		-DEV_USE_EVENTFD=0					\
		-DEV_USE_TIMERFD=0					\
		-DEV_USE_CLOCK_SYSCALL=0				\
		-DEV_USE_MONOTONIC=1					\
		-DEV_USE_REALTIME=1					\
		-DEV_USE_NANOSLEEP=1					\
		-DHAVE_UNISTD_H						\
		-DHAVE_POLL_H						\
		-DHAVE_SYS_SELECT_H					\
		-DHAVE_SYS_RESOURCE_H					\
		-DHAVE_RB_IO_DESCRIPTOR

# nio4r_ext.c is the translation unit that #includes libev's ev.c, i.e. it is
# where ~5,700 lines of foreign C meet this tree's -Wall -Werror. libev is not
# warning-clean under GCC 14: nested "/*" inside comments (ev.c:573, 5682-3),
# `suggest parentheses around arithmetic in operand of |` (ev.c:4417), and
# `'ev_default_loop_ptr' initialized and declared 'extern'` (ev.c:2136, an
# unconditional GCC diagnostic with no -Wno- spelling, so -Wno-error is the
# only lever). Relaxing -Werror for this ONE object -- not for nio4r's own
# four files, which stay strict -- keeps the vendored libev unpatched. Warnings
# are still printed.
o/$(MODE)/third_party/ruby/ext/nio4r/ext/nio4r/nio4r_ext.o: private	\
	CFLAGS +=							\
		-Wno-comment						\
		-Wno-parentheses					\
		-Wno-error

$(THIRD_PARTY_RUBY_EXT_NIO4R_OBJS):					\
	$(THIRD_PARTY_RUBY_EXT_NIO4R_HDRS) third_party/ruby/ext/nio4r/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/nio4r
o/$(MODE)/third_party/ruby/ext/nio4r: $(THIRD_PARTY_RUBY_EXT_NIO4R_A)
