// thaw.inc - Make /zip writable via overlayfs
//
// kCold/kPersisted -> kThawed : fresh thaw (new namespace + overlay)
// kFrozen -> kThawed          : resume (reuse upper layer from state file)

static int Thaw(const char *prog) {
  char sf_path[PATH_MAX];
  struct ToasterStateFile sf;
  enum ToasterState next;
  uid_t host_uid;
  gid_t host_gid;
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

  host_uid = getuid();
  host_gid = getgid();

  if (CheckZip(true, false) != EX_OK)
    return EX_NOINPUT;

  if (verbose)
    printf("Thawing (from %s)...\n", ToasterStateName(sf.state));

  // Setup user + mount namespaces
  if (SetupUserNamespace(host_uid, host_gid) == -1) {
    fprintf(stderr, "Failed to setup user namespace\n");
    return EX_OSERR;
  }

  // Setup /piz with overlayfs
  if (SetupPiz(verbose) == -1) {
    fprintf(stderr, "Failed to setup /piz\n");
    return EX_OSERR;
  }

  // Record overlay paths from environment (set by SetupPiz)
  const char *piz_mount = getenv("PIZ_MOUNT");
  if (!piz_mount) {
    fprintf(stderr, "PIZ_MOUNT not set after SetupPiz\n");
    return EX_SOFTWARE;
  }

  // Save state
  sf.state = next;
  snprintf(sf.mount_path, sizeof(sf.mount_path), "%s", piz_mount);
  // Derive upper/lower/work from piz_mount's sibling directories
  pid_t pid = getpid();
  snprintf(sf.lower_path, sizeof(sf.lower_path), "/tmp/piz-lower-%d", pid);
  snprintf(sf.upper_path, sizeof(sf.upper_path),
           "/tmp/piz-overlay-%d/upper", pid);
  snprintf(sf.work_path, sizeof(sf.work_path),
           "/tmp/piz-overlay-%d/work", pid);

  if (SaveStateFile(sf_path, &sf) == -1) {
    fprintf(stderr, "Warning: failed to save state file\n");
    // non-fatal -- the overlay is still up
  }

  if (verbose)
    printf("State: %s -> %s\n", ToasterStateName(sf.state == next ? kCold : sf.state),
           ToasterStateName(next));

  printf("Thawed. /piz is writable at %s\n", piz_mount);
  return EX_OK;
}
