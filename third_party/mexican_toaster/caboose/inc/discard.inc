// discard.inc - Throw away overlay changes
//
// kThawed -> kCold : unmount overlay + remove directories + remove state file
// kFrozen -> kCold : remove upper layer + remove state file
// kPersisted: error (cannot undo a bake)

static int Discard(const char *prog) {
  char sf_path[PATH_MAX];
  struct ToasterStateFile sf;
  enum ToasterState next;

  if (DeriveStateFilePath(prog, sf_path, sizeof(sf_path)) == -1) {
    fprintf(stderr, "Failed to derive state file path\n");
    return EX_SOFTWARE;
  }

  if (LoadStateFile(sf_path, prog, &sf) == -1)
    return EX_IOERR;

  if (ToasterTransition(sf.state, kActionDiscard, &next) == -1) {
    if (sf.state == kPersisted) {
      fprintf(stderr, "Cannot discard after persist -- the binary has "
              "already been baked.\nRun 'thaw' to start a fresh cycle.\n");
    } else {
      fprintf(stderr, "Cannot discard from state '%s'\n",
              ToasterStateName(sf.state));
    }
    return EX_USAGE;
  }

  if (sf.backend == kOverlayUserland) {
    // Userland mode: upper is a real directory tree with files
    if (sf.upper_path[0]) {
      printf("Removing userland overlay: %s\n", sf.upper_path);
      RemoveDirectoryRecursive(sf.upper_path);
    }
  } else {
    // Kernel mode: unmount first, then remove empty dirs
    if (sf.state == kThawed && sf.mount_path[0]) {
      // EINVAL = not a mount point, EPERM = mount belonged to a dead
      // user namespace (re-entry model), ENOENT = path already gone.
      // All three are expected; only warn on genuinely unexpected errors.
      if (unmount(sf.mount_path, 0) == -1 &&
          errno != EINVAL && errno != EPERM && errno != ENOENT) {
        fprintf(stderr, "Warning: failed to unmount %s: %s\n",
                sf.mount_path, strerror(errno));
      }
    }

    // Remove overlay directories (best effort)
    if (sf.upper_path[0])  rmdir(sf.upper_path);
    if (sf.work_path[0])   rmdir(sf.work_path);
    if (sf.mount_path[0])  rmdir(sf.mount_path);
    if (sf.lower_path[0])  rmdir(sf.lower_path);

    // Remove parent directories if they're our temp dirs
    // e.g. /tmp/piz-overlay-<pid>/
    char parent[PATH_MAX];
    const char *slash;
    if (sf.upper_path[0]) {
      slash = strrchr(sf.upper_path, '/');
      if (slash && slash != sf.upper_path) {
        snprintf(parent, sizeof(parent), "%.*s",
                 (int)(slash - sf.upper_path), sf.upper_path);
        rmdir(parent);  // will fail if non-empty, which is fine
      }
    }
  }

  // Remove state file
  RemoveStateFile(sf_path);

  printf("Discarded. State reset to cold.\n");
  return EX_OK;
}
