/* extconf.h - Socket extension configuration for Cosmopolitan */
#ifndef EXTCONF_H
#define EXTCONF_H

/* Cosmopolitan provides all standard socket types */
#define HAVE_TYPE_STRUCT_ADDRINFO 1
#define HAVE_TYPE_SOCKLEN_T 1
#define HAVE_TYPE_STRUCT_SOCKADDR_STORAGE 1
#define HAVE_TYPE_STRUCT_SOCKADDR_IN 1
#define HAVE_TYPE_STRUCT_SOCKADDR_IN6 1
#define HAVE_TYPE_STRUCT_SOCKADDR_UN 1
#define HAVE_TYPE_STRUCT_IP_MREQ 1
#define HAVE_TYPE_STRUCT_IPV6_MREQ 1

/* Cosmopolitan provides all standard socket functions */
#define HAVE_SOCKET 1
#define HAVE_SOCKETPAIR 1
#define HAVE_BIND 1
#define HAVE_LISTEN 1
#define HAVE_ACCEPT 1
#define HAVE_CONNECT 1
#define HAVE_GETADDRINFO 1
#define HAVE_GETNAMEINFO 1
#define HAVE_GETHOSTNAME 1
#define HAVE_GETSERVBYNAME 1
#define HAVE_GETSERVBYPORT 1
#define HAVE_GETPEERNAME 1
#define HAVE_GETSOCKNAME 1
#define HAVE_GETSOCKOPT 1
#define HAVE_SETSOCKOPT 1
#define HAVE_INET_ATON 1
#define HAVE_INET_NTOA 1
#define HAVE_INET_NTOP 1
#define HAVE_INET_PTON 1
#define HAVE_SHUTDOWN 1
#define HAVE_SEND 1
#define HAVE_SENDTO 1
#define HAVE_SENDMSG 1
#define HAVE_RECV 1
#define HAVE_RECVFROM 1
#define HAVE_RECVMSG 1

/* System headers */
#define HAVE_UNISTD_H 1
#define HAVE_SYS_UIO_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_NETINET_IN_H 1
#define HAVE_NETINET_TCP_H 1
#define HAVE_ARPA_INET_H 1
#define HAVE_NETDB_H 1
#define HAVE_SYS_UN_H 1
#define HAVE_SYS_SELECT_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_FCNTL_H 1
#define HAVE_IFADDRS_H 1
#define HAVE_SYS_IOCTL_H 1
#define HAVE_NET_IF_H 1
#define HAVE_SYS_PARAM_H 1

/* Socket message structures */
#define HAVE_STRUCT_MSGHDR_MSG_CONTROL 1
#define HAVE_STRUCT_MSGHDR_MSG_CONTROLLEN 1
#define HAVE_STRUCT_MSGHDR_MSG_FLAGS 1

/* Control message macros */
#define HAVE_ST_MSG_CONTROL 1

/* Socket options and flags */
#define HAVE_CONST_SO_REUSEADDR 1
#define HAVE_CONST_SO_KEEPALIVE 1
#define HAVE_CONST_SO_BROADCAST 1
#define HAVE_CONST_TCP_NODELAY 1

/* POSIX/Unix features */
#define HAVE_FCNTL 1
#define HAVE_GETIFADDRS 1

/* Socket address features */
/* Linux/Cosmopolitan doesn't have sa_len, so leave HAVE_STRUCT_SOCKADDR_SA_LEN undefined */

#endif /* EXTCONF_H */
