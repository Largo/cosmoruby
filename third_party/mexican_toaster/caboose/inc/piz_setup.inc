// Setup /piz - actual kernel mount from /zip contents
// This creates a real filesystem the kernel can see, unlike /zip which is userspace-only

static int CopyZipToPiz(const char *piz_lower, bool verbose) {
  if (verbose) {
    printf("  📦 Copying /zip contents to tmpfs...\n");
  }
  return CopyDirectoryRecursive("/zip", piz_lower);
}

static int CopyApeLoader(const char *piz_lower, bool verbose) {
  // Check if APE loader exists on host
  struct stat st;
  if (stat("/usr/bin/ape", &st) == -1) {
    fprintf(stderr, "⚠️  WARNING: /usr/bin/ape not found on host system.\n");
    fprintf(stderr, "   APE binaries (like lsdir, zipcopy) will not work inside the toaster.\n");
    fprintf(stderr, "   Install it with: sudo ape/apeinstall.sh (from cosmo repo)\n\n");
    return 0;  // Don't fail, just warn - user can still use mtsh
  }

  // Create usr/bin directory in piz_lower
  char ape_dir[PATH_MAX];
  if (snprintf(ape_dir, sizeof(ape_dir), "%s/usr/bin", piz_lower) >= (int)sizeof(ape_dir)) {
    fprintf(stderr, "❌ Path too long for ape directory\n");
    return -1;
  }

  if (mkdir(ape_dir, 0755) == -1 && errno != EEXIST) {
    fprintf(stderr, "❌ Failed to create %s: %s\n", ape_dir, strerror(errno));
    return -1;
  }

  // Copy the ape loader
  char ape_dest[PATH_MAX];
  if (snprintf(ape_dest, sizeof(ape_dest), "%s/usr/bin/ape", piz_lower) >= (int)sizeof(ape_dest)) {
    fprintf(stderr, "❌ Path too long for ape destination\n");
    return -1;
  }

  if (verbose) {
    printf("  📦 Copying APE loader (/usr/bin/ape)...\n");
  }

  if (CopyFile("/usr/bin/ape", ape_dest) == -1) {
    fprintf(stderr, "❌ Failed to copy /usr/bin/ape to %s: %s\n", ape_dest, strerror(errno));
    return -1;
  }

  // Make it executable
  if (chmod(ape_dest, 0755) == -1) {
    fprintf(stderr, "❌ Failed to chmod %s: %s\n", ape_dest, strerror(errno));
    return -1;
  }

  if (verbose) {
    printf("  ✅ APE loader copied to /usr/bin/ape\n");
  }

  return 0;
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

  // 3b. Copy APE loader so binaries can execute inside chroot
  if (CopyApeLoader(piz_lower, verbose) == -1) {
    fprintf(stderr, "❌ Failed to copy APE loader\n");
    unmount(piz_lower, 0);
    return -1;
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

  // Verify the overlay actually works (not just that mount returned 0)
  if (verbose) {
    struct stat vst;
    DIR *vdir;
    struct dirent *vent;
    int vfd;
    char vprobe[PATH_MAX];

    // A. Can we stat the mount point?
    if (stat(piz_mount, &vst) == -1) {
      printf("  🔍 VERIFY: stat(%s) FAILED: %s\n", piz_mount, strerror(errno));
    } else {
      printf("  🔍 VERIFY: stat(%s) OK, mode=%04o uid=%d gid=%d\n",
             piz_mount, vst.st_mode & 07777, vst.st_uid, vst.st_gid);
    }

    // B. Can we opendir + readdir the mount point?
    vdir = opendir(piz_mount);
    if (!vdir) {
      printf("  🔍 VERIFY: opendir(%s) FAILED: %s\n", piz_mount, strerror(errno));
    } else {
      int count = 0;
      while ((vent = readdir(vdir)) != NULL) count++;
      closedir(vdir);
      printf("  🔍 VERIFY: opendir(%s) OK, %d entries\n", piz_mount, count);
    }

    // C. Can we create a file on the overlay?
    if (snprintf(vprobe, sizeof(vprobe), "%s/.piz_probe", piz_mount) >= (int)sizeof(vprobe)) {
      printf("  🔍 VERIFY: path too long for probe file\n");
    } else {
      vfd = open(vprobe, O_WRONLY | O_CREAT | O_TRUNC, 0644);
      if (vfd == -1) {
        printf("  🔍 VERIFY: create(%s) FAILED: %s\n", vprobe, strerror(errno));
      } else {
        close(vfd);
        unlink(vprobe);
        printf("  🔍 VERIFY: create(%s) OK (write works)\n", vprobe);
      }
    }

    // D. Can we stat the lower layer contents through the overlay?
    if (snprintf(vprobe, sizeof(vprobe), "%s/bin", piz_mount) >= (int)sizeof(vprobe)) {
      printf("  🔍 VERIFY: path too long for bin stat\n");
    } else if (stat(vprobe, &vst) == -1) {
      printf("  🔍 VERIFY: stat(%s/bin) FAILED: %s\n", piz_mount, strerror(errno));
    } else {
      printf("  🔍 VERIFY: stat(%s/bin) OK, is_dir=%d\n",
             piz_mount, S_ISDIR(vst.st_mode));
    }

    // E. Can we readdir the bin directory through the overlay?
    if (snprintf(vprobe, sizeof(vprobe), "%s/bin", piz_mount) >= (int)sizeof(vprobe)) {
      printf("  🔍 VERIFY: path too long for bin readdir\n");
    } else {
      vdir = opendir(vprobe);
      if (!vdir) {
        printf("  🔍 VERIFY: opendir(%s/bin) FAILED: %s\n", piz_mount, strerror(errno));
      } else {
        printf("  🔍 VERIFY: opendir(%s/bin) OK:", piz_mount);
        while ((vent = readdir(vdir)) != NULL) {
          if (strcmp(vent->d_name, ".") && strcmp(vent->d_name, ".."))
            printf(" %s", vent->d_name);
        }
        printf("\n");
        closedir(vdir);
      }
    }
  }

  return 0;
}
