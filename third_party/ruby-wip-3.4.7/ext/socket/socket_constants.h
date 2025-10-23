/* socket_constants.h - Compile-time socket constants for Ruby socket extension
 *
 * Cosmopolitan uses extern const for cross-platform socket constants,
 * but Ruby's socket extension uses them in switch statements which require
 * compile-time constants. This header provides compile-time definitions.
 *
 * Since we're building for Cosmopolitan (which handles OS detection at runtime),
 * we use Linux values as the canonical constants.
 */
#ifndef SOCKET_CONSTANTS_H
#define SOCKET_CONSTANTS_H

/* Undefine Cosmopolitan's runtime constants */
#ifdef AF_PACKET
#undef AF_PACKET
/* AF_PACKET not redefined - Cosmopolitan doesn't provide struct sockaddr_ll */
#endif
#ifdef SOL_SOCKET
#undef SOL_SOCKET
#endif
#ifdef SCM_RIGHTS
#undef SCM_RIGHTS
#endif
#ifdef SCM_CREDENTIALS
#undef SCM_CREDENTIALS
#endif
#ifdef SCM_TIMESTAMP
#undef SCM_TIMESTAMP
#endif
#ifdef SCM_TIMESTAMPNS
#undef SCM_TIMESTAMPNS
#endif
#ifdef AF_INET6
#undef AF_INET6
#endif
#ifdef SO_ERROR
#undef SO_ERROR
#endif
#ifdef SO_TYPE
#undef SO_TYPE
#endif
#ifdef SO_DEBUG
#undef SO_DEBUG
#endif
#ifdef SO_ACCEPTCONN
#undef SO_ACCEPTCONN
#endif
#ifdef SO_BROADCAST
#undef SO_BROADCAST
#endif
#ifdef SO_REUSEADDR
#undef SO_REUSEADDR
#endif
#ifdef SO_KEEPALIVE
#undef SO_KEEPALIVE
#endif
#ifdef SO_OOBINLINE
#undef SO_OOBINLINE
#endif
#ifdef SO_SNDBUF
#undef SO_SNDBUF
#endif
#ifdef SO_RCVBUF
#undef SO_RCVBUF
#endif
#ifdef SO_DONTROUTE
#undef SO_DONTROUTE
#endif
#ifdef SO_RCVLOWAT
#undef SO_RCVLOWAT
#endif
#ifdef SO_SNDLOWAT
#undef SO_SNDLOWAT
#endif
#ifdef SO_LINGER
#undef SO_LINGER
#endif
#ifdef SO_RCVTIMEO
#undef SO_RCVTIMEO
#endif
#ifdef SO_SNDTIMEO
#undef SO_SNDTIMEO
#endif
#ifdef SO_PEERCRED
#undef SO_PEERCRED
#endif
#ifdef IP_ADD_MEMBERSHIP
#undef IP_ADD_MEMBERSHIP
#endif
#ifdef IP_DROP_MEMBERSHIP
#undef IP_DROP_MEMBERSHIP
#endif
#ifdef IP_MULTICAST_LOOP
#undef IP_MULTICAST_LOOP
#endif
#ifdef IP_MULTICAST_TTL
#undef IP_MULTICAST_TTL
#endif
#ifdef IPV6_MULTICAST_HOPS
#undef IPV6_MULTICAST_HOPS
#endif
#ifdef IPV6_MULTICAST_IF
#undef IPV6_MULTICAST_IF
#endif
#ifdef IPV6_MULTICAST_LOOP
#undef IPV6_MULTICAST_LOOP
#endif
#ifdef IPV6_JOIN_GROUP
#undef IPV6_JOIN_GROUP
#endif
#ifdef IPV6_LEAVE_GROUP
#undef IPV6_LEAVE_GROUP
#endif
#ifdef IPV6_UNICAST_HOPS
#undef IPV6_UNICAST_HOPS
#endif
#ifdef IPV6_V6ONLY
#undef IPV6_V6ONLY
#endif
#ifdef EMSGSIZE
#undef EMSGSIZE
#endif
#ifdef EMFILE
#undef EMFILE
#endif

/* Address family constants (from Linux) */
#define AF_INET6      10

/* Socket level constants (from Linux) */
#define SOL_SOCKET    1

/* Socket option names (from Linux) */
#define SO_DEBUG        1
#define SO_REUSEADDR    2
#define SO_TYPE         3
#define SO_ERROR        4
#define SO_DONTROUTE    5
#define SO_BROADCAST    6
#define SO_SNDBUF       7
#define SO_RCVBUF       8
#define SO_KEEPALIVE    9
#define SO_OOBINLINE    10
#define SO_LINGER       13
#define SO_RCVLOWAT     18
#define SO_SNDLOWAT     19
#define SO_RCVTIMEO     20
#define SO_SNDTIMEO     21
#define SO_ACCEPTCONN   30
/* Note: SO_PEERCRED not defined - not available in all environments */

/* IP protocol options (from Linux) */
#define IP_MULTICAST_TTL    33
#define IP_MULTICAST_LOOP   34
#define IP_ADD_MEMBERSHIP   35
#define IP_DROP_MEMBERSHIP  36

/* IPv6 protocol options (from Linux) */
#define IPV6_UNICAST_HOPS    16
#define IPV6_MULTICAST_IF    17
#define IPV6_MULTICAST_HOPS  18
#define IPV6_MULTICAST_LOOP  19
#define IPV6_JOIN_GROUP      20
#define IPV6_LEAVE_GROUP     21
#define IPV6_V6ONLY          26

/* Socket control message types (from Linux) */
#define SCM_RIGHTS         0x01
#define SCM_CREDENTIALS    0x02
#define SCM_TIMESTAMP      29
#define SCM_TIMESTAMPNS    35

/* Error numbers needed by socket code (from Linux) */
#define EMSGSIZE    90
#define EMFILE      24

/* Linux credentials structure for SCM_CREDENTIALS */
#include <sys/types.h>
struct ucred {
    pid_t pid;    /* Process ID */
    uid_t uid;    /* User ID */
    gid_t gid;    /* Group ID */
};

#endif /* SOCKET_CONSTANTS_H */
