static int Toast(const char *prog) {
  extern int mtsh_main(int, char **, char **);
  char upper[PATH_MAX];
  char lower[PATH_MAX];
  char work[PATH_MAX];
  char merged[PATH_MAX];
  uid_t host_uid;
  gid_t host_gid;

  // Save our real UID/GID before entering namespace
  host_uid = getuid();
  host_gid = getgid();

  if (CheckZip(true, false) != EX_OK) {
    return EX_NOINPUT;
  }

  printf("🍞 Getting toasted...\n");
  printf("Welcome to the Mexican Toaster!\n\n");

  // Derive paths for overlay filesystem
  if (DeriveLowerPath(lower) == -1) {
    fprintf(stderr, "Failed to derive lower path for overlay\n");
    return EX_SOFTWARE;
  }
  if (DeriveUpperPath(upper) == -1) {
    fprintf(stderr, "Failed to derive upper path for overlay\n");
    return EX_SOFTWARE;
  }

  // Derive parent directory for work and merged
  char parent[PATH_MAX];
  const char *last_slash = strrchr(upper, '/');
  if (!last_slash) {
    fprintf(stderr, "Invalid upper path (no parent directory)\n");
    return EX_SOFTWARE;
  }
  size_t parent_len = last_slash - upper;
  if (parent_len >= sizeof(parent)) {
    fprintf(stderr, "Parent path too long\n");
    return EX_SOFTWARE;
  }
  memcpy(parent, upper, parent_len);
  parent[parent_len] = '\0';

  // Create work and merged directories in same parent as upper
  if (snprintf(work, sizeof(work), "%s/work", parent) >= (int)sizeof(work)) {
    fprintf(stderr, "Path too long for work directory\n");
    return EX_SOFTWARE;
  }
  if (snprintf(merged, sizeof(merged), "%s/merged", parent) >= (int)sizeof(merged)) {
    fprintf(stderr, "Path too long for merged directory\n");
    return EX_SOFTWARE;
  }

  if (EnsureUpperLayout(upper) == -1) {
    fprintf(stderr, "Failed to prepare upper layout at %s\n", upper);
    return EX_CANTCREAT;
  }

  // Create work and merged directories
  if (mkdir(work, 0755) == -1 && errno != EEXIST) {
    fprintf(stderr, "Failed to create work directory: %s\n", strerror(errno));
    return EX_CANTCREAT;
  }
  if (mkdir(merged, 0755) == -1 && errno != EEXIST) {
    fprintf(stderr, "Failed to create merged directory: %s\n", strerror(errno));
    return EX_CANTCREAT;
  }

  printf("📦 Setting up namespaces...\n");

  // Setup user namespace (maps our UID to root inside namespace)
  if (SetupUserNamespace(host_uid, host_gid) == -1) {
    fprintf(stderr, "Failed to setup user namespace\n");
    return EX_OSERR;
  }
  printf("  ✅ User namespace (UID %d -> 0)\n", host_uid);

  // Setup mount namespace
  if (SetupMountNamespace() == -1) {
    fprintf(stderr, "Failed to setup mount namespace\n");
    return EX_OSERR;
  }
  printf("  ✅ Mount namespace\n");

  // Mount the overlay filesystem
  printf("📂 Mounting overlay filesystem...\n");
  printf("  Lower (read-only):  %s\n", lower);
  printf("  Upper (writable):   %s\n", upper);
  printf("  Merged (combined):  %s\n", merged);

  // Debug: check if paths exist
  struct stat st;
  if (stat(lower, &st) == -1) {
    fprintf(stderr, "⚠️  Lower path %s: %s\n", lower, strerror(errno));
  }
  if (stat(upper, &st) == -1) {
    fprintf(stderr, "⚠️  Upper path %s: %s\n", upper, strerror(errno));
  }
  if (stat(work, &st) == -1) {
    fprintf(stderr, "⚠️  Work path %s: %s\n", work, strerror(errno));
  }
  if (stat(merged, &st) == -1) {
    fprintf(stderr, "⚠️  Merged path %s: %s\n", merged, strerror(errno));
  }

  if (MountOverlay(lower, upper, work, merged) == -1) {
    fprintf(stderr, "Failed to mount overlay\n");
    return EX_OSERR;
  }
  printf("  ✅ Overlay mounted\n");

  // chroot into the merged overlay
  printf("🌐 Entering the toaster environment...\n");
  if (ChrootToOverlay(merged) == -1) {
    fprintf(stderr, "Failed to chroot to overlay\n");
    return EX_OSERR;
  }
  printf("  ✅ chroot complete\n\n");

  // Set environment variables
  setenv("TOASTER_LOWER", lower, 1);
  setenv("TOASTER_UPPER", upper, 1);
  setenv("PATH", "/bin:/usr/bin", 1);
  setenv("PWD", "/", 1);
  setenv("MTSH_MODE", "toast", 1);
  setenv("HOME", "/", 1);
  setenv("SHELL", "/bin/mtsh", 1);

  printf("🎉 You're now toasted!\n");
  printf("The /zip directory contains your embedded application.\n");
  printf("All writes go to: %s\n", upper);
  printf("Type 'exit' or ^D to leave the toaster.\n\n");

  char *mtsh_argv[] = {"mtsh", NULL};
  return mtsh_main(1, mtsh_argv, environ);
}
