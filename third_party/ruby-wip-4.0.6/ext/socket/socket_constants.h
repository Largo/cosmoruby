/* socket_constants.h - Cosmopolitan compatibility shims for ext/socket
 *
 * Cosmopolitan exposes most socket constants as `extern const int` symbols
 * that are filled in at startup with the value the *host* operating system
 * actually uses, e.g.
 *
 *     AF_INET6     linux 10   xnu 30       windows 23
 *     SOL_SOCKET   linux  1   xnu 0xffff   windows 0xffff
 *     SO_REUSEADDR linux  2   xnu 4        windows (emulated)
 *     IPV6_V6ONLY  linux 26   xnu 27       windows 27
 *
 * Those runtime values are the ABI: cosmopolitan's syscall layer passes
 * them straight through to the kernel (or to Winsock), so an APE MUST use
 * them.  This header used to `#undef` them and hard-code the Linux numbers
 * "since we're building for Cosmopolitan"; that made every socket call
 * wrong on Windows and MacOS.  In particular
 *
 *     inet_pton(AF_INET6, "127.0.0.1", buf)   // AF_INET6 forced to 10
 *
 * hit cosmopolitan's `af != AF_INET6 && af != AF_INET` arm, which returns
 * -1 (EAFNOSUPPORT).  raddrinfo.c's numeric_getaddrinfo() only checks for
 * a non-zero return, so it happily built a sockaddr_in6 out of an
 * uninitialised buffer, and bind()/connect() then failed with
 * EAFNOSUPPORT on Windows / EPFNOSUPPORT on MacOS.
 *
 * So: do not redefine anything here.  Constants that are used as `case`
 * labels have been converted to if/else chains in the .c files instead
 * (search for "cosmopolitan" in constants.c, init.c and option.c).
 *
 * What is left below is feature suppression for things cosmopolitan does
 * not implement at all, plus one struct Ruby expects from <sys/socket.h>.
 */
#ifndef SOCKET_CONSTANTS_H
#define SOCKET_CONSTANTS_H

/* Cosmopolitan has no struct sockaddr_ll, so PF_PACKET sockets cannot be
 * described; hide AF_PACKET so socket.c/raddrinfo.c skip those branches. */
#ifdef AF_PACKET
#undef AF_PACKET
#endif

/* Cosmopolitan implements neither SO_PEERCRED nor struct sockpeercred. */
#ifdef SO_PEERCRED
#undef SO_PEERCRED
#endif

/* Cosmopolitan declares SCM_CREDENTIALS but not the struct that goes with
 * it, and ancdata.c needs the type in order to compile. */
#include <sys/types.h>
struct ucred {
    pid_t pid;    /* Process ID */
    uid_t uid;    /* User ID */
    gid_t gid;    /* Group ID */
};

#endif /* SOCKET_CONSTANTS_H */
