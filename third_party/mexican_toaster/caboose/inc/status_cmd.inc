// status_cmd.inc - Show current toaster state and list persisted binaries

static int Status(const char *prog) {
  char sf_path[PATH_MAX];
  struct ToasterStateFile sf;

  if (DeriveStateFilePath(prog, sf_path, sizeof(sf_path)) == -1) {
    fprintf(stderr, "Failed to derive state file path\n");
    return EX_SOFTWARE;
  }

  if (LoadStateFile(sf_path, prog, &sf) == -1)
    return EX_IOERR;

  printf("State:       %s\n", ToasterStateName(sf.state));
  if (sf.state != kCold)
    printf("Backend:     %s\n", OverlayBackendName(sf.backend));
  printf("Binary:      %s\n", sf.binary_path);
  if (sf.orig_path[0])
    printf("Original:    %s\n", sf.orig_path);
  if (sf.upper_path[0])
    printf("Upper layer: %s\n", sf.upper_path);
  if (sf.lower_path[0])
    printf("Lower layer: %s\n", sf.lower_path);
  if (sf.mount_path[0])
    printf("Mount point: %s\n", sf.mount_path);
  printf("State file:  %s\n", sf_path);
  if (sf.persist_count > 0) {
    printf("Persists:    %d\n", sf.persist_count);
    for (int i = 0; i < sf.persist_count; i++)
      printf("  [%d] %s\n", i + 1, sf.persist_names[i]);
  }

  return EX_OK;
}

static int ListPersisted(const char *prog) {
  char sf_path[PATH_MAX];
  struct ToasterStateFile sf;
  struct stat st;

  if (DeriveStateFilePath(prog, sf_path, sizeof(sf_path)) == -1) {
    fprintf(stderr, "Failed to derive state file path\n");
    return EX_SOFTWARE;
  }

  if (LoadStateFile(sf_path, prog, &sf) == -1)
    return EX_IOERR;

  if (sf.persist_count == 0) {
    printf("No persisted binaries.\n");
    return EX_OK;
  }

  printf("Persisted binaries:\n");
  for (int i = 0; i < sf.persist_count; i++) {
    const char *path = sf.persist_names[i];
    if (stat(path, &st) == 0) {
      struct tm *tm = localtime(&st.st_mtim.tv_sec);
      char timebuf[64];
      strftime(timebuf, sizeof(timebuf), "%Y-%m-%d %H:%M:%S", tm);
      printf("  %s  %8ld bytes  %s\n", timebuf, (long)st.st_size, path);
    } else {
      printf("  (missing)  %s\n", path);
    }
  }

  // Check if binary_path is a symlink and show where it points
  char link_target[PATH_MAX];
  ssize_t link_len = readlink(sf.binary_path, link_target,
                              sizeof(link_target) - 1);
  if (link_len > 0) {
    link_target[link_len] = '\0';
    printf("\nCurrent symlink: %s -> %s\n", sf.binary_path, link_target);
  }

  return EX_OK;
}
