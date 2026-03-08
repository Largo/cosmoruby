// thaw.inc - Make /zip writable via overlayfs or userland copy
//
// kCold/kPersisted -> kThawed : fresh thaw (new namespace + overlay, or userland copy)
// kFrozen -> kThawed          : resume (reuse upper layer from state file)

static enum OverlayBackend SelectBackend(void) {
  const char *env = getenv("TOASTER_BACKEND");
  enum OverlayBackend requested = ParseOverlayBackend(env);

  if (requested == kOverlayUserland)
    return kOverlayUserland;

  if (requested == kOverlayKernel) {
    if (!IsLinux()) {
      fprintf(stderr, "Warning: kernel overlay requested but not on Linux, "
                       "using userland\n");
      return kOverlayUserland;
    }
    return kOverlayKernel;
  }

  // Auto-detect
  if (!IsLinux())
    return kOverlayUserland;

  // On Linux: probe for user namespace + overlayfs support
  struct OverlayProbe probe = {0};
  ProbeOverlayUserns(&probe);
  if (probe.userns_ok && probe.overlayfs_ok)
    return kOverlayKernel;

  return kOverlayUserland;
}

static int Thaw(const char *prog) {
  char sf_path[PATH_MAX];
  struct ToasterStateFile sf;
  enum ToasterState next;
  enum OverlayBackend backend;
  bool verbose = false;
  const char *verbose_env;

  verbose_env = getenv("TOASTER_VERBOSE");
  if (verbose_env && (!strcmp(verbose_env, "1") ||
                      !strcmp(verbose_env, "true") ||
                      !strcmp(verbose_env, "yes")))
    verbose = true;

  if (DeriveStateFilePath(prog, sf_path, sizeof(sf_path)) == -1) {
    fprintf(stderr, "Failed to derive state file path\n");
    return EX_SOFTWARE;
  }

  if (LoadStateFile(sf_path, prog, &sf) == -1)
    return EX_IOERR;

  if (ToasterTransition(sf.state, kActionThaw, &next) == -1) {
    fprintf(stderr, "Cannot thaw from state '%s'\n",
            ToasterStateName(sf.state));
    return EX_USAGE;
  }

  if (CheckZip(true, false) != EX_OK)
    return EX_NOINPUT;

  backend = SelectBackend();
  if (verbose)
    printf("Using backend: %s\n", OverlayBackendName(backend));

  if (backend == kOverlayKernel) {
    // Existing kernel overlay path
    uid_t host_uid = getuid();
    gid_t host_gid = getgid();

    if (verbose)
      printf("Thawing (from %s) using kernel overlay...\n",
             ToasterStateName(sf.state));

    if (SetupUserNamespace(host_uid, host_gid) == -1) {
      fprintf(stderr, "Failed to setup user namespace\n");
      return EX_OSERR;
    }

    if (SetupPiz(verbose) == -1) {
      fprintf(stderr, "Failed to setup /piz\n");
      return EX_OSERR;
    }

    const char *piz_mount = getenv("PIZ_MOUNT");
    if (!piz_mount) {
      fprintf(stderr, "PIZ_MOUNT not set after SetupPiz\n");
      return EX_SOFTWARE;
    }

    sf.state = next;
    sf.backend = kOverlayKernel;
    snprintf(sf.mount_path, sizeof(sf.mount_path), "%s", piz_mount);
    pid_t pid = getpid();
    snprintf(sf.lower_path, sizeof(sf.lower_path), "/tmp/piz-lower-%d", pid);
    snprintf(sf.upper_path, sizeof(sf.upper_path),
             "/tmp/piz-overlay-%d/upper", pid);
    snprintf(sf.work_path, sizeof(sf.work_path),
             "/tmp/piz-overlay-%d/work", pid);

    if (SaveStateFile(sf_path, &sf) == -1)
      fprintf(stderr, "Warning: failed to save state file\n");

    printf("Thawed. /piz is writable at %s\n", piz_mount);
  } else {
    // Userland overlay path
    if (verbose)
      printf("Thawing (from %s) using userland overlay...\n",
             ToasterStateName(sf.state));

    if (ThawUserland(prog, &sf, verbose) == -1) {
      fprintf(stderr, "Failed to setup userland overlay\n");
      return EX_OSERR;
    }

    sf.state = next;
    sf.backend = kOverlayUserland;

    if (SaveStateFile(sf_path, &sf) == -1)
      fprintf(stderr, "Warning: failed to save state file\n");

    printf("Thawed. Writable layer at %s\n", sf.upper_path);
  }

  return EX_OK;
}
