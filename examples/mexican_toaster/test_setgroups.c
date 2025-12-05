#include "libc/calls/calls.h"
#include "libc/errno.h"
#include "libc/sysv/consts/clone.h"
#include "libc/sysv/consts/o.h"
#include "libc/stdio/stdio.h"
#include "libc/str/str.h"

int main() {
    printf("Before unshare:\n");
    printf("  UID: %d, EUID: %d\n", getuid(), geteuid());

    char path[256];
    snprintf(path, sizeof(path), "/proc/%d/setgroups", getpid());
    printf("  Trying to open: %s\n", path);

    int fd = open(path, O_WRONLY);
    printf("  open() returned: %d\n", fd);
    if (fd == -1) printf("  errno: %s\n", strerror(errno));
    else close(fd);

    printf("\nCalling unshare(CLONE_NEWUSER)...\n");
    if (unshare(CLONE_NEWUSER) == -1) {
        printf("  unshare failed: %s\n", strerror(errno));
        return 1;
    }

    printf("\nAfter unshare:\n");
    printf("  UID: %d, EUID: %d\n", getuid(), geteuid());

    fd = open(path, O_WRONLY);
    printf("  open() returned: %d\n", fd);
    if (fd == -1) printf("  errno: %s\n", strerror(errno));
    else {
        printf("  Success! Now writing 'deny'...\n");
        ssize_t n = write(fd, "deny\n", 5);
        printf("  write() returned: %zd\n", n);
        if (n == -1) printf("  errno: %s\n", strerror(errno));
        close(fd);
    }

    return 0;
}
