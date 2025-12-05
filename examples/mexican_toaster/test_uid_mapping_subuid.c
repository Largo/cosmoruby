#include "libc/calls/calls.h"
#include "libc/errno.h"
#include "libc/sysv/consts/clone.h"
#include "libc/sysv/consts/o.h"
#include "libc/stdio/stdio.h"
#include "libc/str/str.h"
#include "libc/runtime/runtime.h"

int main(void) {
  printf("=== UID Mapping with Subordinate UIDs ===\n\n");

  printf("Step 1: Current user info\n");
  printf("  UID: %d, GID: %d\n", getuid(), getgid());

  printf("\nStep 2: Creating user namespace...\n");
  if (unshare(CLONE_NEWUSER) == -1) {
    printf("  ❌ unshare failed: %s\n", strerror(errno));
    return 1;
  }
  printf("  ✅ User namespace created\n");
  printf("  New UID: %d (should be 65534/nobody)\n", getuid());

  printf("\nStep 3: Writing 'deny' to setgroups...\n");
  int fd = open("/proc/self/setgroups", O_WRONLY);
  if (fd == -1) {
    printf("  ❌ Cannot open setgroups: %s\n", strerror(errno));
    return 1;
  }
  if (write(fd, "deny\n", 5) != 5) {
    printf("  ❌ Failed to write: %s\n", strerror(errno));
    close(fd);
    return 1;
  }
  close(fd);
  printf("  ✅ Successfully wrote 'deny'\n");

  printf("\nStep 4: Mapping UID using subordinate range...\n");
  // Map UID 0 in namespace to subordinate UID 165536 on host
  fd = open("/proc/self/uid_map", O_WRONLY);
  if (fd == -1) {
    printf("  ❌ Cannot open uid_map: %s\n", strerror(errno));
    return 1;
  }

  char map[64];
  snprintf(map, sizeof(map), "0 165536 1\n");
  printf("  Writing: %s", map);

  if (write(fd, map, strlen(map)) == -1) {
    printf("  ❌ Failed to write uid_map: %s\n", strerror(errno));
    close(fd);
    return 1;
  }
  close(fd);
  printf("  ✅ Successfully wrote uid_map\n");

  printf("\nStep 5: Mapping GID...\n");
  fd = open("/proc/self/gid_map", O_WRONLY);
  if (fd == -1) {
    printf("  ❌ Cannot open gid_map: %s\n", strerror(errno));
    return 1;
  }

  snprintf(map, sizeof(map), "0 165536 1\n");
  printf("  Writing: %s", map);

  if (write(fd, map, strlen(map)) == -1) {
    printf("  ❌ Failed to write gid_map: %s\n", strerror(errno));
    close(fd);
    return 1;
  }
  close(fd);
  printf("  ✅ Successfully wrote gid_map\n");

  printf("\nStep 6: Checking new identity...\n");
  printf("  UID: %d, GID: %d\n", getuid(), getgid());
  printf("  EUID: %d, EGID: %d\n", geteuid(), getegid());

  if (getuid() == 0) {
    printf("\n🎉 Success! We are root inside the namespace!\n");
  }

  return 0;
}
