// freeze.inc - Pause writes, keep changes in memory
//
// kThawed -> kFrozen : unmount overlay but keep upper layer intact

static int Freeze(const char *prog) {
  char sf_path[PATH_MAX];
  struct ToasterStateFile sf;
  enum ToasterState next;

  if (DeriveStateFilePath(prog, sf_path, sizeof(sf_path)) == -1) {
    fprintf(stderr, "Failed to derive state file path\n");
    return EX_SOFTWARE;
  }

  if (LoadStateFile(sf_path, prog, &sf) == -1)
    return EX_IOERR;

  if (ToasterTransition(sf.state, kActionFreeze, &next) == -1) {
    fprintf(stderr, "Cannot freeze from state '%s'\n",
            ToasterStateName(sf.state));
    return EX_USAGE;
  }

  // Unmount the overlay but keep the upper layer
  // (Userland mode has no mount, so this is a no-op)
  if (sf.mount_path[0] && sf.backend != kOverlayUserland) {
    // EINVAL = not a mount point, EPERM = mount belonged to a dead
    // user namespace (re-entry model), ENOENT = path already gone.
    // All three are expected; only warn on genuinely unexpected errors.
    if (unmount(sf.mount_path, 0) == -1 &&
        errno != EINVAL && errno != EPERM && errno != ENOENT) {
      fprintf(stderr, "Warning: failed to unmount %s: %s\n",
              sf.mount_path, strerror(errno));
    }
  }

  sf.state = next;
  if (SaveStateFile(sf_path, &sf) == -1)
    return EX_IOERR;

  printf("Frozen. Upper layer preserved at %s\n", sf.upper_path);
  return EX_OK;
}
