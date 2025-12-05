static int Toast(const char *prog) {
  extern int mtsh_main(int, char **, char **);
  uid_t host_uid;
  gid_t host_gid;
  bool verbose = false;

  // Check for verbose mode
  const char *verbose_env = getenv("TOASTER_VERBOSE");
  if (verbose_env && (strcmp(verbose_env, "1") == 0 ||
                      strcmp(verbose_env, "true") == 0 ||
                      strcmp(verbose_env, "yes") == 0)) {
    verbose = true;
  }

  // Save our real UID/GID before entering namespace
  host_uid = getuid();
  host_gid = getgid();

  if (CheckZip(true, false) != EX_OK) {
    return EX_NOINPUT;
  }

  if (verbose) {
    printf("🍞 Getting toasted...\n");
    printf("Welcome to the Mexican Toaster!\n\n");
    printf("📦 Setting up namespaces...\n");
  }

  // Setup user + mount namespaces (maps our UID to root inside namespace)
  if (SetupUserNamespace(host_uid, host_gid) == -1) {
    fprintf(stderr, "Failed to setup user namespace\n");
    return EX_OSERR;
  }
  if (verbose) {
    printf("  ✅ User + Mount namespaces (UID %d -> 0)\n", host_uid);
  }

  // Setup /piz with overlayfs
  if (SetupPiz(verbose) == -1) {
    fprintf(stderr, "Failed to setup /piz\n");
    return EX_OSERR;
  }

  // chroot into /piz
  const char *piz_mount = getenv("PIZ_MOUNT");
  if (!piz_mount) {
    fprintf(stderr, "❌ PIZ_MOUNT not set\n");
    return EX_SOFTWARE;
  }

  // Setup binfmt_misc for APE binary execution
  char binfmt_path[PATH_MAX];
  char proc_path[PATH_MAX];
  int fd;

  // Mount a new binfmt_misc instance for this namespace
  if (snprintf(binfmt_path, sizeof(binfmt_path), "%s/proc/sys/fs/binfmt_misc", piz_mount) >= (int)sizeof(binfmt_path)) {
    fprintf(stderr, "❌ Path too long for binfmt_misc\n");
    return EX_SOFTWARE;
  }

  // Create directory structure for binfmt_misc
  if (snprintf(proc_path, sizeof(proc_path), "%s/proc", piz_mount) >= (int)sizeof(proc_path)) {
    fprintf(stderr, "❌ Path too long for /proc\n");
    return EX_SOFTWARE;
  }

  if (mkdir(proc_path, 0755) == -1 && errno != EEXIST) {
    fprintf(stderr, "❌ Failed to create %s: %s\n", proc_path, strerror(errno));
    return EX_OSERR;
  }

  // Bind mount /proc
  if (mount("/proc", proc_path, NULL, MS_BIND | MS_REC, NULL) == -1) {
    fprintf(stderr, "❌ Failed to bind mount /proc at %s: %s\n", proc_path, strerror(errno));
    return EX_OSERR;
  }

  // Create binfmt_misc directory
  if (makedirs(binfmt_path, 0755) == -1 && errno != EEXIST) {
    fprintf(stderr, "❌ Failed to create %s: %s\n", binfmt_path, strerror(errno));
    return EX_OSERR;
  }

  // Mount our own binfmt_misc instance
  if (mount("binfmt_misc", binfmt_path, "binfmt_misc", 0, NULL) == -1) {
    fprintf(stderr, "❌ Failed to mount binfmt_misc at %s: %s\n", binfmt_path, strerror(errno));
    return EX_OSERR;
  }

  // Register APE format: :APE:M::MZqFpD::/usr/bin/ape:
  // This tells the kernel to use /usr/bin/ape as the interpreter for APE binaries
  char register_path[PATH_MAX];
  if (snprintf(register_path, sizeof(register_path), "%s/register", binfmt_path) >= (int)sizeof(register_path)) {
    fprintf(stderr, "❌ Path too long for register\n");
    return EX_SOFTWARE;
  }

  fd = open(register_path, O_WRONLY);
  if (fd == -1) {
    fprintf(stderr, "❌ Failed to open %s: %s\n", register_path, strerror(errno));
    return EX_OSERR;
  }

  const char *ape_registration = ":APE:M::MZqFpD::/usr/bin/ape:";
  if (write(fd, ape_registration, strlen(ape_registration)) == -1) {
    fprintf(stderr, "❌ Failed to register APE format: %s\n", strerror(errno));
    close(fd);
    return EX_OSERR;
  }
  close(fd);

  if (verbose) {
    printf("  ✅ APE format registered with /usr/bin/ape loader\n");
    printf("\n🌐 Entering the toaster environment...\n");
  }

  if (chroot(piz_mount) == -1) {
    fprintf(stderr, "❌ chroot to %s failed: %s\n", piz_mount, strerror(errno));
    return EX_OSERR;
  }

  if (chdir("/") == -1) {
    fprintf(stderr, "❌ chdir to / failed: %s\n", strerror(errno));
    return EX_OSERR;
  }
  if (verbose) {
    printf("  ✅ chroot complete\n\n");
  }

  // Set environment variables
  setenv("PATH", "/bin:/usr/bin", 1);
  setenv("PWD", "/", 1);
  setenv("MTSH_MODE", "toast", 1);
  setenv("TOASTER_MODE", "toast", 1);
  setenv("HOME", "/", 1);
  setenv("SHELL", "/bin/mtsh", 1);

  if (verbose) {
    printf("🎉 You're now toasted!\n");
    printf("You're in /piz - a real kernel mount with overlayfs!\n");
    printf("✨ Everything is writable (in-memory tmpfs)\n");
    printf("💾 Changes are ephemeral (lost on exit)\n");
    printf("Type 'exit' or ^D to leave the toaster.\n\n");
  }

  char *mtsh_argv[] = {"mtsh", NULL};
  return mtsh_main(1, mtsh_argv, environ);
}
