// Setup /piz - actual kernel mount from /zip contents
// This creates a real filesystem the kernel can see, unlike /zip which is userspace-only

static int CopyZipToPiz(const char *piz_lower, bool verbose) {
  if (verbose) {
    printf("  📦 Copying /zip contents to tmpfs...\n");
  }
  return CopyDirectoryRecursive("/zip", piz_lower);
}

static int SetupPiz(bool verbose) {
  char piz_lower[PATH_MAX];
  char piz_overlay[PATH_MAX];
  char piz_upper[PATH_MAX];
  char piz_work[PATH_MAX];
  char opts[PATH_MAX * 3];
  int n;

  // Use process-specific temp directories
  pid_t pid = getpid();

  if (snprintf(piz_lower, sizeof(piz_lower), "/tmp/piz-lower-%d", pid) >= (int)sizeof(piz_lower)) {
    fprintf(stderr, "❌ Path too long\n");
    return -1;
  }
  if (snprintf(piz_overlay, sizeof(piz_overlay), "/tmp/piz-overlay-%d", pid) >= (int)sizeof(piz_overlay)) {
    fprintf(stderr, "❌ Path too long\n");
    return -1;
  }
  if (snprintf(piz_upper, sizeof(piz_upper), "%s/upper", piz_overlay) >= (int)sizeof(piz_upper)) {
    fprintf(stderr, "❌ Path too long\n");
    return -1;
  }
  if (snprintf(piz_work, sizeof(piz_work), "%s/work", piz_overlay) >= (int)sizeof(piz_work)) {
    fprintf(stderr, "❌ Path too long\n");
    return -1;
  }

  char piz_mount[PATH_MAX];
  if (snprintf(piz_mount, sizeof(piz_mount), "/tmp/piz-mount-%d", pid) >= (int)sizeof(piz_mount)) {
    fprintf(stderr, "❌ Path too long\n");
    return -1;
  }

  if (verbose) {
    printf("📂 Setting up /piz (actual kernel mount)...\n");
  }

  // 1. Create mount point
  if (mkdir(piz_mount, 0755) == -1 && errno != EEXIST) {
    fprintf(stderr, "❌ Failed to create %s: %s\n", piz_mount, strerror(errno));
    return -1;
  }

  // 2. Mount tmpfs for lower layer
  if (mkdir(piz_lower, 0755) == -1 && errno != EEXIST) {
    fprintf(stderr, "❌ Failed to create %s: %s\n", piz_lower, strerror(errno));
    return -1;
  }

  if (mount("tmpfs", piz_lower, "tmpfs", 0, "size=512m") == -1) {
    fprintf(stderr, "❌ Failed to mount tmpfs at %s: %s\n", piz_lower, strerror(errno));
    return -1;
  }
  if (verbose) {
    printf("  ✅ tmpfs mounted at %s\n", piz_lower);
  }

  // 3. Copy /zip contents to tmpfs
  if (CopyZipToPiz(piz_lower, verbose) == -1) {
    fprintf(stderr, "❌ Failed to copy /zip to tmpfs\n");
    unmount(piz_lower, 0);
    return -1;
  }
  if (verbose) {
    printf("  ✅ /zip contents copied\n");
  }

  // 4. Create overlay directories
  if (mkdir(piz_overlay, 0755) == -1 && errno != EEXIST) {
    fprintf(stderr, "❌ Failed to create %s: %s\n", piz_overlay, strerror(errno));
    unmount(piz_lower, 0);
    return -1;
  }

  if (mkdir(piz_upper, 0755) == -1 && errno != EEXIST) {
    fprintf(stderr, "❌ Failed to create %s: %s\n", piz_upper, strerror(errno));
    unmount(piz_lower, 0);
    return -1;
  }

  if (mkdir(piz_work, 0755) == -1 && errno != EEXIST) {
    fprintf(stderr, "❌ Failed to create %s: %s\n", piz_work, strerror(errno));
    unmount(piz_lower, 0);
    return -1;
  }
  if (verbose) {
    printf("  ✅ Overlay directories created\n");
  }

  // 5. Mount overlay at /piz
  n = snprintf(opts, sizeof(opts), "lowerdir=%s,upperdir=%s,workdir=%s",
               piz_lower, piz_upper, piz_work);
  if (n >= (int)sizeof(opts)) {
    fprintf(stderr, "❌ Overlay options too long\n");
    unmount(piz_lower, 0);
    return -1;
  }

  if (mount("overlay", piz_mount, "overlay", 0, opts) == -1) {
    fprintf(stderr, "❌ Failed to mount overlay at %s: %s\n", piz_mount, strerror(errno));
    fprintf(stderr, "   Options: %s\n", opts);
    unmount(piz_lower, 0);
    return -1;
  }
  if (verbose) {
    printf("  ✅ Overlay mounted at %s\n", piz_mount);
  }

  // Store piz_mount path in environment for toast_piz.inc
  setenv("PIZ_MOUNT", piz_mount, 1);

  return 0;
}
