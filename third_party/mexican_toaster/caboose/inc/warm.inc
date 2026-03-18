// warm.inc - Prepare isolated environment with namespaces and overlay
//
// This is the foundation for both 'thaw' and 'toast' on Linux.
// It sets up user namespace, mount namespace, and overlay filesystem.
//
// Usage:
//   Warm(prog, use_tmpfs) -> returns with namespaces active, overlay mounted
//   Caller then decides: thaw (disk upper), toast (chroot + mtsh), or stay in warm

#ifndef WARM_INC
#define WARM_INC

struct WarmConfig {
  bool use_tmpfs_upper;   // true for toast/ephemeral, false for thaw/persistent
  bool verbose;
  char merged_path[PATH_MAX];
  char upper_path[PATH_MAX];
  char work_path[PATH_MAX];
  char lower_path[PATH_MAX];
};

// Setup the warm environment.
// Returns EX_OK on success, with namespaces active and overlay mounted.
// On success, the caller is running inside user + mount namespaces.
//
// Parameters:
//   use_tmpfs_upper - true for tmpfs (ephemeral), false for disk (persistent)
static int Warm(const char *prog, bool use_tmpfs_upper, struct WarmConfig *config) {
  config->use_tmpfs_upper = use_tmpfs_upper;
  uid_t host_uid = getuid();
  gid_t host_gid = getgid();
  pid_t pid = getpid();

  if (config->verbose) {
    printf("🔥 Warming up...\n");
  }

  // Derive paths
  const char *parent = "/tmp";
  const char *prefix = config->use_tmpfs_upper ? "toast" : "warm";
  
  if (snprintf(config->lower_path, PATH_MAX, "%s/%s-lower-%d", 
               parent, prefix, pid) >= PATH_MAX) {
    fprintf(stderr, "Path too long for lower directory\n");
    return EX_SOFTWARE;
  }
  if (snprintf(config->upper_path, PATH_MAX, "%s/%s-overlay-%d/upper",
               parent, prefix, pid) >= PATH_MAX) {
    fprintf(stderr, "Path too long for upper directory\n");
    return EX_SOFTWARE;
  }
  if (snprintf(config->work_path, PATH_MAX, "%s/%s-overlay-%d/work",
               parent, prefix, pid) >= PATH_MAX) {
    fprintf(stderr, "Path too long for work directory\n");
    return EX_SOFTWARE;
  }
  if (snprintf(config->merged_path, PATH_MAX, "%s/%s-mount-%d",
               parent, prefix, pid) >= PATH_MAX) {
    fprintf(stderr, "Path too long for merged directory\n");
    return EX_SOFTWARE;
  }

  // Create directories
  if (mkdir(config->lower_path, 0755) == -1 && errno != EEXIST) {
    fprintf(stderr, "Failed to create %s: %s\n", config->lower_path, strerror(errno));
    return EX_CANTCREAT;
  }
  if (mkdir(config->merged_path, 0755) == -1 && errno != EEXIST) {
    fprintf(stderr, "Failed to create %s: %s\n", config->merged_path, strerror(errno));
    return EX_CANTCREAT;
  }

  // Create upper and work directories
  char overlay_parent[PATH_MAX];
  const char *last_slash = strrchr(config->upper_path, '/');
  if (!last_slash) {
    fprintf(stderr, "Invalid upper path\n");
    return EX_SOFTWARE;
  }
  size_t parent_len = last_slash - config->upper_path;
  memcpy(overlay_parent, config->upper_path, parent_len);
  overlay_parent[parent_len] = '\0';
  
  if (mkdir(overlay_parent, 0755) == -1 && errno != EEXIST) {
    fprintf(stderr, "Failed to create %s: %s\n", overlay_parent, strerror(errno));
    return EX_CANTCREAT;
  }
  
  // For tmpfs upper: mount tmpfs at upper_path
  // For disk upper: just create directory
  if (config->use_tmpfs_upper) {
    if (mkdir(config->upper_path, 0755) == -1 && errno != EEXIST) {
      fprintf(stderr, "Failed to create %s: %s\n", config->upper_path, strerror(errno));
      return EX_CANTCREAT;
    }
    if (mount("tmpfs", config->upper_path, "tmpfs", 0, "size=256m") == -1) {
      fprintf(stderr, "Failed to mount tmpfs at %s: %s\n", config->upper_path, strerror(errno));
      return EX_OSERR;
    }
  } else {
    if (mkdir(config->upper_path, 0755) == -1 && errno != EEXIST) {
      fprintf(stderr, "Failed to create %s: %s\n", config->upper_path, strerror(errno));
      return EX_CANTCREAT;
    }
  }
  
  if (mkdir(config->work_path, 0755) == -1 && errno != EEXIST) {
    fprintf(stderr, "Failed to create %s: %s\n", config->work_path, strerror(errno));
    return EX_CANTCREAT;
  }

  // Mount tmpfs for lower layer (holds copy of /zip)
  if (mount("tmpfs", config->lower_path, "tmpfs", 0, "size=512m") == -1) {
    fprintf(stderr, "Failed to mount tmpfs at %s: %s\n", config->lower_path, strerror(errno));
    return EX_OSERR;
  }

  // Copy /zip contents to lower layer
  if (CopyDirectoryRecursive("/zip", config->lower_path) == -1) {
    fprintf(stderr, "Failed to copy /zip to lower layer\n");
    unmount(config->lower_path, 0);
    return EX_OSERR;
  }

  // For tmpfs upper (toast), nothing more to do
  // For disk upper (thaw), we could optionally pre-populate from a saved upper
  // For now, upper starts empty

  // Setup user namespace
  if (SetupUserNamespace(host_uid, host_gid) == -1) {
    fprintf(stderr, "Failed to setup user namespace\n");
    unmount(config->lower_path, 0);
    return EX_OSERR;
  }
  if (config->verbose) {
    printf("  ✅ User namespace (UID %d -> 0)\n", host_uid);
  }

  // Setup mount namespace
  if (SetupMountNamespace() == -1) {
    fprintf(stderr, "Failed to setup mount namespace\n");
    unmount(config->lower_path, 0);
    return EX_OSERR;
  }
  if (config->verbose) {
    printf("  ✅ Mount namespace\n");
  }

  // Mount overlay
  char opts[PATH_MAX * 4];
  snprintf(opts, sizeof(opts), "lowerdir=%s,upperdir=%s,workdir=%s",
           config->lower_path, config->upper_path, config->work_path);
  
  if (mount("overlay", config->merged_path, "overlay", 0, opts) == -1) {
    fprintf(stderr, "Failed to mount overlay at %s: %s\n", config->merged_path, strerror(errno));
    unmount(config->lower_path, 0);
    return EX_OSERR;
  }
  if (config->verbose) {
    printf("  ✅ Overlay mounted at %s\n", config->merged_path);
    printf("     Lower: %s (read-only)\n", config->lower_path);
    printf("     Upper: %s (%s)\n", config->upper_path,
           config->use_tmpfs_upper ? "tmpfs" : "disk");
  }

  return EX_OK;
}

// Cleanup function to unmount and remove warm directories
// Called on exit or error
static void WarmCleanup(struct WarmConfig *config) {
  if (config->merged_path[0]) {
    unmount(config->merged_path, 0);
  }
  if (config->lower_path[0]) {
    unmount(config->lower_path, 0);
  }
  if (config->use_tmpfs_upper && config->upper_path[0]) {
    unmount(config->upper_path, 0);
  }
  // Directories will be cleaned up by /tmp cleaner or on reboot
}

// Command handler for "warm" CLI command
static int WarmCmd(const char *prog) {
  struct WarmConfig config = {0};
  config.verbose = true;
  
  int rc = Warm(prog, true, &config);  // tmpfs upper for warm command
  if (rc != EX_OK) {
    WarmCleanup(&config);
    return rc;
  }
  
  // Note: After Warm(), we're still in the parent process,
  // but namespaces have been set up via unshare() so we're
  // already inside them. We haven't chrooted yet.
  
  printf("\n🔥 Warmed up! Environment ready at: %s\n", config.merged_path);
  printf("   You are inside user + mount namespaces.\n");
  printf("   Upper layer (tmpfs): %s\n", config.upper_path);
  printf("\n   Next steps:\n");
  printf("     - 'thaw' to switch to persistent disk upper\n");
  printf("     - 'toast' to enter isolated chroot + mtsh\n");
  printf("     - Or use the merged overlay directly\n");
  printf("\n   NOTE: This process must stay running to keep namespaces alive.\n");
  printf("   Exit (Ctrl+C) to cleanup.\n\n");
  
  // Save state as kWarm
  char sf_path[PATH_MAX];
  struct ToasterStateFile sf = {0};
  if (DeriveStateFilePath(prog, sf_path, sizeof(sf_path)) == 0 &&
      LoadStateFile(sf_path, prog, &sf) == 0) {
    sf.state = kWarm;
    sf.backend = kOverlayKernel;
    snprintf(sf.mount_path, sizeof(sf.mount_path), "%s", config.merged_path);
    snprintf(sf.upper_path, sizeof(sf.upper_path), "%s", config.upper_path);
    snprintf(sf.work_path, sizeof(sf.work_path), "%s", config.work_path);
    snprintf(sf.lower_path, sizeof(sf.lower_path), "%s", config.lower_path);
    SaveStateFile(sf_path, &sf);
  }
  
  // Stay alive - namespaces die when we exit
  // In future, this could daemonize or wait for commands
  printf("Press Enter to exit and cleanup...\n");
  getchar();
  
  WarmCleanup(&config);
  return EX_OK;
}

#endif // WARM_INC
