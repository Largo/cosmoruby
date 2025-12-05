#include "libc/calls/calls.h"
#include "libc/errno.h"
#include "libc/sysv/consts/clone.h"
#include "libc/sysv/consts/o.h"
#include "libc/stdio/stdio.h"
#include "libc/str/str.h"
#include "libc/runtime/runtime.h"

int main(void) {
  printf("=== UID Mapping Diagnostic ===\n\n");

  printf("Step 1: Checking current user...\n");
  printf("  UID: %d\n", getuid());
  printf("  GID: %d\n", getgid());
  printf("  EUID: %d\n", geteuid());

  printf("\nStep 2: Checking /proc/self/setgroups...\n");
  int fd = open("/proc/self/setgroups", O_RDONLY);
  if (fd != -1) {
    char buf[64];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    if (n > 0) {
      buf[n] = '\0';
      printf("  Current value: %s", buf);
    }
    close(fd);
  } else {
    printf("  Cannot read: %s\n", strerror(errno));
  }

  fd = open("/proc/self/setgroups", O_WRONLY);
  if (fd != -1) {
    printf("  Writable: YES\n");
    close(fd);
  } else {
    printf("  Writable: NO (%s)\n", strerror(errno));
  }

  printf("\nStep 3: Creating user namespace...\n");
  int rc = unshare(CLONE_NEWUSER);
  if (rc == -1) {
    printf("  ❌ unshare(CLONE_NEWUSER) failed: %s\n", strerror(errno));
    return 1;
  }
  printf("  ✅ User namespace created!\n");

  printf("\nStep 4: Checking /proc/self/setgroups AFTER unshare...\n");
  fd = open("/proc/self/setgroups", O_RDONLY);
  if (fd != -1) {
    char buf[64];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    if (n > 0) {
      buf[n] = '\0';
      printf("  Current value: %s", buf);
    }
    close(fd);
  }

  fd = open("/proc/self/setgroups", O_WRONLY);
  if (fd != -1) {
    printf("  Writable: YES\n");

    printf("\nStep 5: Trying to write 'deny' to setgroups...\n");
    ssize_t n = write(fd, "deny\n", 5);
    if (n == 5) {
      printf("  ✅ Successfully wrote 'deny'\n");
      close(fd);

      printf("\nStep 6: Trying to write uid_map...\n");
      char map[64];
      snprintf(map, sizeof(map), "0 %d 1\n", getuid());

      fd = open("/proc/self/uid_map", O_WRONLY);
      if (fd != -1) {
        n = write(fd, map, strlen(map));
        if (n > 0) {
          printf("  ✅ Successfully wrote uid_map: %s", map);
          printf("  New UID in namespace: %d\n", getuid());
        } else {
          printf("  ❌ Failed to write uid_map: %s\n", strerror(errno));
        }
        close(fd);
      } else {
        printf("  ❌ Cannot open uid_map: %s\n", strerror(errno));
      }
    } else {
      printf("  ❌ Failed to write: %s\n", strerror(errno));
    }
    close(fd);
  } else {
    printf("  Writable: NO (%s)\n", strerror(errno));
    printf("\n⚠️  This is the problem! After creating user namespace,\n");
    printf("    /proc/self/setgroups should be writable but isn't.\n");
    printf("\nPossible causes:\n");
    printf("  1. AppArmor/SELinux policy blocking it\n");
    printf("  2. Kernel compiled without proper CONFIG_USER_NS support\n");
    printf("  3. Security module restriction\n");
  }

  return 0;
}
