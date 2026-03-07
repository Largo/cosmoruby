// persist.inc - Bake overlay changes into the binary
//
// kThawed/kFrozen -> kPersisted
//
// 1. Copies the running binary to binary_path.tmp
// 2. Reads /zip/.bare_size to find pre-ZIP executable size
// 3. Truncates .tmp to bare size (strips existing ZIP)
// 4. Merges /zip/ content + overlay into a single staging directory
// 5. Single fasterzip pass to embed everything into .tmp
// 6. Atomic rename(.tmp, binary_path) to swap in the new binary
//
// The running process keeps the old inode.  New execs get the new binary.
//
// Why merge-then-append: fasterzip cannot cleanly append to a binary that
// already has fasterzip-appended ZIP content — a second append writes a
// new central directory covering only the new entries, orphaning the
// original central directory and corrupting the ZIP.  Truncating back to
// bare and doing a single pass avoids this.

// CopyFile and CopyDirectoryRecursive are defined in recursive_copy.inc.

// Extract a tool from /zip/bin/ to a temp file on disk so it can be exec'd.
// After fork+exec, the child process doesn't have the parent's /zip/
// filesystem, so we must copy the tool to a real file first.
static const char *ExtractZipTool(const char *name) {
  static char tmp[PATH_MAX];
  char zip_path[PATH_MAX];
  snprintf(zip_path, sizeof(zip_path), "/zip/bin/%s", name);
  int src = open(zip_path, O_RDONLY);
  if (src == -1)
    return NULL;
  snprintf(tmp, sizeof(tmp), "/tmp/toaster-%s-XXXXXX", name);
  int fd = mkstemp(tmp);
  if (fd == -1) {
    close(src);
    return NULL;
  }
  char iobuf[65536];
  ssize_t n;
  while ((n = read(src, iobuf, sizeof(iobuf))) > 0) {
    if (write(fd, iobuf, n) != n) {
      close(src);
      close(fd);
      unlink(tmp);
      return NULL;
    }
  }
  close(src);
  fchmod(fd, 0755);
  close(fd);
  return tmp;
}

// Find a tool binary.  /zip/bin/ first, then cosmocc toolchain, then PATH.
static const char *FindTool(const char *name) {
  static char buf[PATH_MAX];
  struct stat st;
  const char *extracted = ExtractZipTool(name);
  if (extracted)
    return extracted;
  snprintf(buf, sizeof(buf), ".cosmocc/current/bin/%s", name);
  if (stat(buf, &st) == 0 && S_ISREG(st.st_mode))
    return buf;
  return name;
}

// Run a command via fork/exec.  Returns exit status or -1.
static int RunCommand(const char *const argv[]) {
  pid_t pid = fork();
  if (pid == -1) {
    fprintf(stderr, "fork failed: %s\n", strerror(errno));
    return -1;
  }
  if (pid == 0) {
    execvp(argv[0], (char *const *)argv);
    fprintf(stderr, "exec %s failed: %s\n", argv[0], strerror(errno));
    _Exit(127);
  }
  int status;
  if (waitpid(pid, &status, 0) == -1) {
    fprintf(stderr, "waitpid failed: %s\n", strerror(errno));
    return -1;
  }
  if (WIFEXITED(status))
    return WEXITSTATUS(status);
  return -1;
}

// Read /zip/.bare_size to find the pre-ZIP binary size.
// package_caboose.sh writes this marker during packaging.
static off_t ReadBareSize(void) {
  int fd = open("/zip/.bare_size", O_RDONLY);
  if (fd == -1)
    return -1;
  char buf[32];
  ssize_t n = read(fd, buf, sizeof(buf) - 1);
  close(fd);
  if (n <= 0)
    return -1;
  buf[n] = '\0';
  while (n > 0 && (buf[n-1] == '\n' || buf[n-1] == '\r' || buf[n-1] == ' '))
    buf[--n] = '\0';
  return strtoll(buf, NULL, 10);
}

static void CleanupTempDir(const char *path) {
  const char *argv[] = {"rm", "-rf", path, NULL};
  RunCommand(argv);
}

static int Persist(const char *prog) {
  char sf_path[PATH_MAX];
  struct ToasterStateFile sf;
  enum ToasterState next;
  char tmp_path[PATH_MAX];
  char staging[PATH_MAX];
  struct stat st;

  // Prime /zip/ VFS — Cosmopolitan may lazily initialise /zip/ access,
  // and a prior open() ensures the VFS index is populated.
  { int _fd = open("/zip/.cosmo", O_RDONLY); if (_fd >= 0) close(_fd); }

  if (DeriveStateFilePath(prog, sf_path, sizeof(sf_path)) == -1) {
    fprintf(stderr, "Failed to derive state file path\n");
    return EX_SOFTWARE;
  }

  if (LoadStateFile(sf_path, prog, &sf) == -1)
    return EX_IOERR;

  if (ToasterTransition(sf.state, kActionPersist, &next) == -1) {
    fprintf(stderr, "Cannot persist from state '%s'\n",
            ToasterStateName(sf.state));
    return EX_USAGE;
  }

  if (!sf.upper_path[0]) {
    fprintf(stderr, "No upper layer path recorded -- nothing to persist\n");
    return EX_NOINPUT;
  }
  if (stat(sf.upper_path, &st) == -1) {
    fprintf(stderr, "Upper layer %s not found: %s\n",
            sf.upper_path, strerror(errno));
    return EX_NOINPUT;
  }

  off_t bare_size = ReadBareSize();
  if (bare_size <= 0) {
    fprintf(stderr,
            "No .bare_size marker found in /zip/\n"
            "Re-package with the updated package_caboose.sh first.\n");
    return EX_NOINPUT;
  }

  // Temp file in same directory as binary (same filesystem for rename)
  if (snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", sf.binary_path)
      >= (int)sizeof(tmp_path)) {
    fprintf(stderr, "Path too long\n");
    return EX_SOFTWARE;
  }

  printf("Copying %s -> %s\n", sf.binary_path, tmp_path);
  if (CopyFile(sf.binary_path, tmp_path) == -1)
    return EX_IOERR;

  printf("Stripping ZIP (truncating to %lld bytes)...\n",
         (long long)bare_size);
  if (truncate(tmp_path, bare_size) == -1) {
    fprintf(stderr, "Failed to truncate %s: %s\n",
            tmp_path, strerror(errno));
    unlink(tmp_path);
    return EX_IOERR;
  }

  // Merge /zip/ content + overlay into a single staging directory
  snprintf(staging, sizeof(staging), "/tmp/toaster-merge-XXXXXX");
  if (!mkdtemp(staging)) {
    fprintf(stderr, "Failed to create staging dir: %s\n", strerror(errno));
    unlink(tmp_path);
    return EX_CANTCREAT;
  }

  printf("Merging /zip/ + overlay into staging...\n");
  if (CopyDirectoryRecursive("/zip", staging) == -1) {
    fprintf(stderr, "Failed to copy /zip/ content\n");
    CleanupTempDir(staging);
    unlink(tmp_path);
    return EX_IOERR;
  }
  if (CopyDirectoryRecursive(sf.upper_path, staging) == -1) {
    fprintf(stderr, "Failed to copy overlay content\n");
    CleanupTempDir(staging);
    unlink(tmp_path);
    return EX_IOERR;
  }

  printf("Embedding merged content into %s...\n", tmp_path);
  {
    const char *fz_tool = FindTool("fasterzip");
    const char *fz_argv[] = {fz_tool, "-r", tmp_path, ".", NULL};
    if (chdir(staging) == -1) {
      fprintf(stderr, "Failed to chdir to %s: %s\n",
              staging, strerror(errno));
      CleanupTempDir(staging);
      unlink(tmp_path);
      return EX_IOERR;
    }
    int rc = RunCommand(fz_argv);
    if (strncmp(fz_tool, "/tmp/toaster-", 13) == 0)
      unlink(fz_tool);
    CleanupTempDir(staging);
    if (rc != 0) {
      fprintf(stderr, "fasterzip failed (exit %d)\n", rc);
      unlink(tmp_path);
      return EX_UNAVAILABLE;
    }
  }

  // Atomic swap — the running process keeps its old inode
  if (rename(tmp_path, sf.binary_path) == -1) {
    fprintf(stderr, "Failed to rename %s -> %s: %s\n",
            tmp_path, sf.binary_path, strerror(errno));
    unlink(tmp_path);
    return EX_IOERR;
  }

  sf.state = next;
  if (SaveStateFile(sf_path, &sf) == -1)
    fprintf(stderr, "Warning: failed to save state file\n");

  printf("Persisted as %s\n", sf.binary_path);
  return EX_OK;
}
