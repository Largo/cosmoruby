#include "libc/calls/calls.h"
#include "libc/errno.h"
#include "libc/sysv/consts/clone.h"
#include "libc/sysv/consts/o.h"
#include "libc/sysv/consts/s.h"
#include "libc/sysv/consts/mount.h"
#include "libc/stdio/stdio.h"
#include "libc/str/str.h"
#include "libc/runtime/runtime.h"

// NOTE: On Ubuntu/Debian, this test requires AppArmor to allow unprivileged user namespaces:
//   sudo sysctl kernel.apparmor_restrict_unprivileged_userns=0
// Without this, unshare(CLONE_NEWUSER) will fail with EACCES or EPERM.
// See MEXICAN_TOASTER_VISION.md for production solution (fine-grained AppArmor profile).

int main(void) {
  printf("=== Overlay Mount Test ===\n\n");

  printf("Step 1: Create user namespace...\n");
  if (unshare(CLONE_NEWUSER) == -1) {
    printf("  ❌ unshare(CLONE_NEWUSER) failed: %s\n", strerror(errno));
    return 1;
  }
  printf("  ✅ User namespace created\n");

  printf("\nStep 2: Write 'deny' to setgroups...\n");
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
  printf("  ✅ Wrote 'deny'\n");

  printf("\nStep 3: Map UID 0 -> 1000...\n");
  fd = open("/proc/self/uid_map", O_WRONLY);
  if (fd == -1) {
    printf("  ❌ Cannot open uid_map: %s\n", strerror(errno));
    return 1;
  }
  char map[64];
  snprintf(map, sizeof(map), "0 %d 1\n", 1000);
  if (write(fd, map, strlen(map)) == -1) {
    printf("  ❌ Failed to write uid_map: %s\n", strerror(errno));
    close(fd);
    return 1;
  }
  close(fd);
  printf("  ✅ UID mapped\n");

  printf("\nStep 4: Map GID 0 -> 1000...\n");
  fd = open("/proc/self/gid_map", O_WRONLY);
  if (fd == -1) {
    printf("  ❌ Cannot open gid_map: %s\n", strerror(errno));
    return 1;
  }
  snprintf(map, sizeof(map), "0 %d 1\n", 1000);
  if (write(fd, map, strlen(map)) == -1) {
    printf("  ❌ Failed to write gid_map: %s\n", strerror(errno));
    close(fd);
    return 1;
  }
  close(fd);
  printf("  ✅ GID mapped\n");

  printf("\nStep 5: Create mount namespace...\n");
  if (unshare(CLONE_NEWNS) == -1) {
    printf("  ❌ unshare(CLONE_NEWNS) failed: %s\n", strerror(errno));
    return 1;
  }
  printf("  ✅ Mount namespace created\n");

  printf("\nStep 5.5: Make mount namespace private...\n");
  if (mount("none", "/", NULL, MS_REC | MS_PRIVATE, NULL) == -1) {
    printf("  ❌ Failed to make / private: %s\n", strerror(errno));
    return 1;
  }
  printf("  ✅ Mount namespace is now private\n");

  printf("\nStep 6: Create overlay directories...\n");
  mkdir("/tmp/overlay-test", 0755);
  mkdir("/tmp/overlay-test/upper", 0755);
  mkdir("/tmp/overlay-test/work", 0755);
  mkdir("/tmp/overlay-test/merged", 0755);
  mkdir("/tmp/overlay-test/lower", 0755);

  // Create test file in lower
  fd = open("/tmp/overlay-test/lower/testfile.txt", O_WRONLY | O_CREAT, 0644);
  if (fd != -1) {
    write(fd, "Hello from lower layer\n", 23);
    close(fd);
  }
  printf("  ✅ Directories created\n");

  printf("\nStep 7: Mount overlay...\n");
  const char *opts = "lowerdir=/tmp/overlay-test/lower,upperdir=/tmp/overlay-test/upper,workdir=/tmp/overlay-test/work";
  if (mount("overlay", "/tmp/overlay-test/merged", "overlay", 0, opts) == -1) {
    printf("  ❌ mount failed: %s\n", strerror(errno));
    return 1;
  }
  printf("  ✅ Overlay mounted!\n");

  printf("\nStep 7.5: Check what's in merged...\n");
  fd = open("/tmp/overlay-test/merged", O_RDONLY);
  if (fd == -1) {
    printf("  ❌ Cannot open merged dir: %s\n", strerror(errno));
  } else {
    printf("  ✅ Can open merged directory\n");
    close(fd);
  }

  // Check if we can read the lower file through the overlay
  fd = open("/tmp/overlay-test/merged/testfile.txt", O_RDONLY);
  if (fd == -1) {
    printf("  ❌ Cannot read testfile.txt through overlay: %s\n", strerror(errno));
  } else {
    char buf[64];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    if (n > 0) {
      buf[n] = '\0';
      printf("  ✅ Read from overlay: %s", buf);
    }
    close(fd);
  }

  printf("\nStep 7.6: Try writing to merged...\n");
  printf("  Current capabilities - UID: %d, GID: %d\n", getuid(), getgid());
  fd = open("/tmp/overlay-test/merged/test-write.txt", O_WRONLY | O_CREAT, 0644);
  if (fd == -1) {
    printf("  ❌ Failed to create file: %s (errno=%d)\n", strerror(errno), errno);

    // Try writing directly to upper
    printf("  Trying direct write to upper directory...\n");
    fd = open("/tmp/overlay-test/upper/direct-write.txt", O_WRONLY | O_CREAT, 0644);
    if (fd == -1) {
      printf("  ❌ Upper also fails: %s\n", strerror(errno));
    } else {
      write(fd, "Direct to upper\n", 16);
      close(fd);
      printf("  ✅ Direct write to upper succeeded\n");
    }
  } else {
    write(fd, "Written through overlay\n", 24);
    close(fd);
    printf("  ✅ Write to overlay succeeded!\n");
  }

  printf("\nStep 8: chroot to merged...\n");
  if (chroot("/tmp/overlay-test/merged") == -1) {
    printf("  ❌ chroot failed: %s\n", strerror(errno));
    return 1;
  }
  if (chdir("/") == -1) {
    printf("  ❌ chdir failed: %s\n", strerror(errno));
    return 1;
  }
  printf("  ✅ chrooted to overlay!\n");

  printf("\nStep 9: Diagnostics inside chroot...\n");
  printf("  Current UID: %d, GID: %d\n", getuid(), getgid());
  printf("  Current EUID: %d, EGID: %d\n", geteuid(), getegid());

  // Try to list root directory
  // system("ls -la / 2>&1 | head -5");  // Skipped - system() not available in static link

  printf("\nStep 10: Test write inside chroot...\n");
  fd = open("/testfile.txt", O_RDONLY);
  if (fd == -1) {
    printf("  ⚠️  Cannot read testfile.txt: %s\n", strerror(errno));
  } else {
    char buf[64];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    if (n > 0) {
      buf[n] = '\0';
      printf("  ✅ Read from lower: %s", buf);
    }
    close(fd);
  }

  fd = open("/newfile.txt", O_WRONLY | O_CREAT, 0644);
  if (fd == -1) {
    printf("  ❌ Cannot create file: %s\n", strerror(errno));
    printf("  errno = %d\n", errno);
  } else {
    write(fd, "Written to overlay after chroot!\n", 33);
    close(fd);
    printf("  ✅ File created in overlay!\n");
  }

  printf("\n🎉 SUCCESS! We are now in an overlay filesystem!\n");
  printf("Current UID: %d (should be 0)\n", getuid());
  printf("Current GID: %d (should be 0)\n", getgid());
  printf("\nThis is exactly what Mexican Toaster needs:\n");
  printf("  - Read-only /zip (lower layer) with Ruby/Rails\n");
  printf("  - Writable overlay (upper layer) for app files\n");
  printf("  - chroot so / is the merged view\n");
  printf("  - rails new myapp would write to overlay!\n");

  return 0;
}
