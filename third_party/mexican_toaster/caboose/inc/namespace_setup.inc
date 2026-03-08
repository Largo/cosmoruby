// Namespace setup functions for Mexican Toaster caboose

static int SetupUserNamespace(uid_t target_uid, gid_t target_gid) {
  int fd;
  char map[64];
  ssize_t n;

  // Step 1: Create user namespace AND mount namespace together
  // This is critical - doing them together gives us proper capabilities
  if (unshare(CLONE_NEWUSER | CLONE_NEWNS) == -1) {
    fprintf(stderr, "❌ unshare(CLONE_NEWUSER | CLONE_NEWNS) failed: %s\n", strerror(errno));
    return -1;
  }

  // Step 2: Write 'deny' to setgroups
  fd = open("/proc/self/setgroups", O_WRONLY);
  if (fd == -1) {
    fprintf(stderr, "❌ Cannot open /proc/self/setgroups: %s\n", strerror(errno));
    return -1;
  }
  if (write(fd, "deny\n", 5) != 5) {
    fprintf(stderr, "❌ Failed to write to setgroups: %s\n", strerror(errno));
    close(fd);
    return -1;
  }
  close(fd);

  // Step 3: Map UID (namespace UID 0 -> host UID)
  fd = open("/proc/self/uid_map", O_WRONLY);
  if (fd == -1) {
    fprintf(stderr, "❌ Cannot open /proc/self/uid_map: %s\n", strerror(errno));
    return -1;
  }
  snprintf(map, sizeof(map), "0 %d 1\n", target_uid);
  n = write(fd, map, strlen(map));
  if (n == -1) {
    fprintf(stderr, "❌ Failed to write uid_map: %s\n", strerror(errno));
    close(fd);
    return -1;
  }
  close(fd);

  // Step 4: Map GID (namespace GID 0 -> host GID)
  fd = open("/proc/self/gid_map", O_WRONLY);
  if (fd == -1) {
    fprintf(stderr, "❌ Cannot open /proc/self/gid_map: %s\n", strerror(errno));
    return -1;
  }
  snprintf(map, sizeof(map), "0 %d 1\n", target_gid);
  n = write(fd, map, strlen(map));
  if (n == -1) {
    fprintf(stderr, "❌ Failed to write gid_map: %s\n", strerror(errno));
    close(fd);
    return -1;
  }
  close(fd);

  return 0;
}

static int SetupMountNamespace(void) {
  // Create mount namespace
  if (unshare(CLONE_NEWNS) == -1) {
    fprintf(stderr, "❌ unshare(CLONE_NEWNS) failed: %s\n", strerror(errno));
    return -1;
  }

  // Make mount namespace private (don't propagate mounts)
  // NOTE: This can break access to /zip in some cases, so we skip it for now
  // if (mount("none", "/", NULL, MS_REC | MS_PRIVATE, NULL) == -1) {
  //   fprintf(stderr, "❌ Failed to make / private: %s\n", strerror(errno));
  //   return -1;
  // }

  return 0;
}

static int MountOverlay(const char *lower, const char *upper, const char *work, const char *merged) {
  char opts[PATH_MAX * 3];
  int n;

  // Build overlay options string
  n = snprintf(opts, sizeof(opts), "lowerdir=%s,upperdir=%s,workdir=%s", lower, upper, work);
  if (n >= (int)sizeof(opts)) {
    fprintf(stderr, "❌ Overlay options string too long\n");
    return -1;
  }

  // Mount the overlay
  if (mount("overlay", merged, "overlay", 0, opts) == -1) {
    fprintf(stderr, "❌ mount overlay failed: %s\n", strerror(errno));
    fprintf(stderr, "   Options: %s\n", opts);
    return -1;
  }

  return 0;
}

static int ChrootToOverlay(const char *merged) {
  // chroot to the overlay merged directory
  if (chroot(merged) == -1) {
    fprintf(stderr, "❌ chroot to %s failed: %s\n", merged, strerror(errno));
    return -1;
  }

  // Change to root directory inside the chroot
  if (chdir("/") == -1) {
    fprintf(stderr, "❌ chdir to / failed: %s\n", strerror(errno));
    return -1;
  }

  return 0;
}
