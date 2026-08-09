/* errno_wrapper.h - Cosmopolitan errno compatibility for Ruby
 *
 * Cosmopolitan uses extern const for errno values (runtime polymorphic),
 * but Ruby needs compile-time constants for switch/case statements.
 * This header MUST be included BEFORE any system errno.h.
 *
 * IMPORTANT: This header only applies when compiling Ruby itself.
 * External code including Ruby headers should use Cosmopolitan's
 * runtime constants normally.
 */
#ifndef COSMOPOLITAN_RUBY_ERRNO_WRAPPER_H_
#define COSMOPOLITAN_RUBY_ERRNO_WRAPPER_H_

/* Only apply these overrides when compiling Ruby source files */
#ifdef RUBY_COSMOPOLITAN

/* Define errno constants as compile-time values (Linux x86_64 from libc/sysv/consts.sh) */
#define ENOSYS 38
#define EPERM 1
#define ENOENT 2
#define ESRCH 3
#define EINTR 4
#define ENXIO 6
#define ENOEXEC 8
#define EBADF 9
#define ECHILD 10
#define EAGAIN 11
#define ENOMEM 12
#define EACCES 13
#define EBUSY 16
#define EEXIST 17
#define EXDEV 18
#define ENOTDIR 20
#define EISDIR 21
#define EINVAL 22
#define ENFILE 23
#define EMFILE 24
#define ENOTTY 25
#define ESPIPE 29
#define EPIPE 32
#define EDOM 33
#define ERANGE 34
#define ENAMETOOLONG 36
#define ENOSYS 38
#define ELOOP 40
#define EPROTO 71
#define EILSEQ 84
#define ERESTART 85
#define ENOTSUP 95
#define EOPNOTSUPP 95
#define ECONNABORTED 103
#define EISCONN 106
#define ETIMEDOUT 110
#define ECONNREFUSED 111
#define EHOSTUNREACH 113
#define EALREADY 114
#define EINPROGRESS 115
#define EWOULDBLOCK EAGAIN

/* fcntl constants (Linux x86_64 from libc/sysv/consts.sh) */
#define F_DUPFD 0
#define F_GETFD 1
#define F_SETFD 2
#define F_GETFL 3
#define F_SETFL 4
#define F_GETLK 5
#define F_SETLK 6
#define F_SETLKW 7
#define FD_CLOEXEC 1
#define F_DUPFD_CLOEXEC 0x0406

/* open() flags (Linux x86_64 values) */
#define O_RDONLY    0
#define O_WRONLY    1
#define O_RDWR      2
#define O_CREAT     0100
#define O_EXCL      0200
#define O_NOCTTY    0400
#define O_TRUNC     01000
#define O_APPEND    02000
#define O_NONBLOCK  04000
#define O_SYNC      04010000
#define O_CLOEXEC   02000000

/* Signal constants (standard Linux values) */
#define SIGHUP 1
#define SIGINT 2
#define SIGQUIT 3
#define SIGILL 4
#define SIGTRAP 5
#define SIGABRT 6
#define SIGBUS 7
#define SIGFPE 8
#define SIGKILL 9
#define SIGUSR1 10
#define SIGSEGV 11
#define SIGUSR2 12
#define SIGPIPE 13
#define SIGALRM 14
#define SIGTERM 15
#define SIGCHLD 17
#define SIGCONT 18
#define SIGSTOP 19
#define SIGTSTP 20
#define SIGTTIN 21
#define SIGTTOU 22
#define SIGURG 23
#define SIGXCPU 24
#define SIGXFSZ 25
#define SIGVTALRM 26
#define SIGPROF 27
#define SIGWINCH 28
#define SIGIO 29
#define SIGSYS 31

/* Wait constants */
#define WNOHANG 1
#define WUNTRACED 2

/* Signal mask constants
 *
 * cosmo: guarded. Cosmopolitan's <signal.h> (libc/sysv/consts/sig.h) defines
 * these as host-correct `extern const int`s, and any translation unit that
 * reaches <signal.h> before this header -- e.g. ext/nio4r, whose nio4r.h
 * includes libev's ev.h ahead of ruby.h -- would otherwise fail with
 * "SIG_BLOCK redefined" under -Werror. Every use of these three in the tree
 * is a function argument (sigprocmask/pthread_sigmask), never a case label,
 * so letting cosmopolitan's runtime values win where they got there first is
 * both harmless and more correct than the hardcoded Linux numbers below.
 */
#ifndef SIG_BLOCK
#define SIG_BLOCK 0
#endif
#ifndef SIG_UNBLOCK
#define SIG_UNBLOCK 1
#endif
#ifndef SIG_SETMASK
#define SIG_SETMASK 2
#endif

/* Socket errno constants */
#define EMSGSIZE 90
#define ENOTSOCK 88
#define EDESTADDRREQ 89
#define EPROTOTYPE 91
#define ENOPROTOOPT 92
#define EPROTONOSUPPORT 93
#define ESOCKTNOSUPPORT 94
#define EPFNOSUPPORT 96
#define EAFNOSUPPORT 97
#define EADDRINUSE 98
#define EADDRNOTAVAIL 99
#define ENETDOWN 100
#define ENETUNREACH 101
#define ENETRESET 102
#define ENOTCONN 107
#define ESHUTDOWN 108
#define ETOOMANYREFS 109
#define EHOSTDOWN 112

/* NOTE: SOL_* and SCM_* are deliberately NOT defined here.
 *
 * Unlike errno / signal / open flags -- which Cosmopolitan normalises to
 * the Linux numbering on every host -- SOL_SOCKET and the SCM_* values
 * really are polymorphic: SOL_SOCKET is 1 on Linux but 0xffff on Windows,
 * MacOS and the BSDs, and Cosmopolitan hands the value straight to the
 * host's setsockopt()/getsockopt().  Hard-coding 1 here made every
 * SOL_SOCKET socket option fail with EINVAL off Linux.  Let
 * libc/sysv/consts/{sol,scm}.h supply the runtime values instead; the few
 * places Ruby used them as `case` labels are now if/else chains.
 */

/* Address families: Use Cosmopolitan's compile-time constants from af.h */
/* AF_UNIX, AF_INET, AF_INET6 are already defined as compile-time constants in libc/sysv/consts/af.h */

/* cosmo: the POLL* block below hard-codes the *Linux* numbering and then
 * blocks cosmopolitan's own <poll.h>.  That is wrong off Linux -- cosmopolitan
 * drives Windows poll() in Winsock's numbering (POLLIN 0x0300, POLLOUT 0x0010,
 * POLLERR 0x0001, see libc/calls/poll-nt.c), so a caller passing the Linux
 * POLLIN (1) is really asking for Winsock's POLLERR, which poll-nt.c masks
 * away: poll() then never reports a socket ready and simply times out.
 *
 * It was left alone up to the xml-libs branch because *Ruby* never calls
 * poll() in this build (thread.c only defines USE_POLL for __linux__ /
 * FreeBSD, and cosmocc defines neither), which made the whole block dead
 * code.  ext/nio4r changed that: libev's poll(2) backend is a real caller,
 * and with the Linux numbering it worked on Linux and macOS and reported
 * nothing at all on Windows.
 *
 * Rather than change the numbering for the entire tree, a translation unit
 * that genuinely calls poll() defines COSMO_RUBY_HOST_POLL and gets
 * cosmopolitan's host-correct `extern const int16_t` POLL* values and its
 * real struct pollfd instead.  ext/nio4r/BUILD.mk is the only user today.
 * The general fix -- deleting this block outright -- is safe as far as
 * anyone can tell (nothing else compiles a POLL* reference) but has a much
 * larger blast radius, so it is left for a branch of its own.
 */
#ifndef COSMO_RUBY_HOST_POLL

/* Poll constants (Linux values) */
#define POLLIN 0x0001
#define POLLPRI 0x0002
#define POLLOUT 0x0004
#define POLLERR 0x0008
#define POLLHUP 0x0010
#define POLLNVAL 0x0020

/* Poll structure */
struct pollfd {
    int fd;
    short events;
    short revents;
};

/* Poll function declaration */
int poll(struct pollfd *, unsigned long, int);

#endif /* !COSMO_RUBY_HOST_POLL */

/* Now block Cosmopolitan's errno.h, fcntl, signal, wait, open, poll, and socket constant headers */
#define COSMOPOLITAN_LIBC_ERRNO_H_
#define COSMOPOLITAN_LIBC_SYSV_CONSTS_F_H_
#define COSMOPOLITAN_LIBC_SYSV_CONSTS_O_H_
#define COSMOPOLITAN_LIBC_SYSV_CONSTS_SIG_H_
#define COSMOPOLITAN_LIBC_SYSV_CONSTS_W_H_
#ifndef COSMO_RUBY_HOST_POLL
#define LIBC_ISYSTEM_POLL_H_
#define COSMOPOLITAN_LIBC_ISYSTEM_SYS_POLL_H_
#define COSMOPOLITAN_LIBC_SOCK_STRUCT_POLLFD_H_
#define COSMOPOLITAN_LIBC_SYSV_CONSTS_POLL_H_
#endif
/* Note: NOT blocking SOL_H_/SCM_H_/AF_H_ -- those constants are runtime
 * polymorphic in Cosmopolitan and must keep their host values. */

/* But we still need errno_t,  __errno_location, and fcntl function */
typedef int errno_t;
extern errno_t __errno;
errno_t *__errno_location(void);
#define errno (*__errno_location())

/* Forward declare fcntl() and related types/structs Ruby needs */
struct flock;
int fcntl(int, int, ...);
int open(const char *, int, ...);
int creat(const char *, unsigned);

#endif /* RUBY_COSMOPOLITAN */

#endif /* COSMOPOLITAN_RUBY_ERRNO_WRAPPER_H_ */
