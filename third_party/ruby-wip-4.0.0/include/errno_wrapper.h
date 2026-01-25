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

/* Signal mask constants */
#define SIG_BLOCK 0
#define SIG_UNBLOCK 1
#define SIG_SETMASK 2

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

/* Socket level constants (Linux x86_64 values) */
#define SOL_SOCKET 1
#define SOL_IP 0
#define SOL_TCP 6
#define SOL_UDP 17
#define SOL_IPV6 41

/* Socket control message types (Linux x86_64 values) */
#define SCM_RIGHTS 1
#define SCM_TIMESTAMP 29
#define SCM_TIMESTAMPNS 35
/* Note: SCM_CREDENTIALS intentionally omitted - requires struct ucred which Cosmopolitan doesn't provide */

/* Address families: Use Cosmopolitan's compile-time constants from af.h */
/* AF_UNIX, AF_INET, AF_INET6 are already defined as compile-time constants in libc/sysv/consts/af.h */

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

/* Now block Cosmopolitan's errno.h, fcntl, signal, wait, open, poll, and socket constant headers */
#define COSMOPOLITAN_LIBC_ERRNO_H_
#define COSMOPOLITAN_LIBC_SYSV_CONSTS_F_H_
#define COSMOPOLITAN_LIBC_SYSV_CONSTS_O_H_
#define COSMOPOLITAN_LIBC_SYSV_CONSTS_SIG_H_
#define COSMOPOLITAN_LIBC_SYSV_CONSTS_W_H_
#define LIBC_ISYSTEM_POLL_H_
#define COSMOPOLITAN_LIBC_ISYSTEM_SYS_POLL_H_
#define COSMOPOLITAN_LIBC_SOCK_STRUCT_POLLFD_H_
#define COSMOPOLITAN_LIBC_SYSV_CONSTS_POLL_H_
#define COSMOPOLITAN_LIBC_SYSV_CONSTS_SOL_H_
#define COSMOPOLITAN_LIBC_SYSV_CONSTS_SCM_H_
/* Note: NOT blocking AF_H_ because AF_UNIX and AF_INET are already compile-time constants */

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
