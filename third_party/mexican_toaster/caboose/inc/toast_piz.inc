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

  // Save TERM before we clear the environment later
  const char *host_term = getenv("TERM");
  char saved_term[64] = "";
  if (host_term)
    snprintf(saved_term, sizeof(saved_term), "%s", host_term);

  // Save our real UID/GID before entering namespace
  host_uid = getuid();
  host_gid = getgid();

  if (CheckZip(true, false) != EX_OK) {
    return EX_NOINPUT;
  }

  // Read lifecycle state before chroot (state file is on host fs)
  char sf_path[PATH_MAX];
  struct ToasterStateFile sf;
  const char *state_name = "cold";
  if (DeriveStateFilePath(prog, sf_path, sizeof(sf_path)) == 0 &&
      LoadStateFile(sf_path, prog, &sf) == 0) {
    state_name = ToasterStateName(sf.state);
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

  // Bind mount /dev for device access (urandom, null, zero, etc.)
  char dev_path[PATH_MAX];
  if (snprintf(dev_path, sizeof(dev_path), "%s/dev", piz_mount) < (int)sizeof(dev_path)) {
    if (mkdir(dev_path, 0755) == -1 && errno != EEXIST) {
      fprintf(stderr, "⚠️  Failed to create %s: %s\n", dev_path, strerror(errno));
    } else {
      if (mount("/dev", dev_path, NULL, MS_BIND | MS_REC, NULL) == -1) {
        fprintf(stderr, "⚠️  Failed to bind mount /dev: %s\n", strerror(errno));
      } else if (verbose) {
        printf("  ✅ /dev available (urandom, null, zero, etc.)\n");
      }
    }
  }

  // Bind mount /sys for system info (optional but useful)
  char sys_path[PATH_MAX];
  if (snprintf(sys_path, sizeof(sys_path), "%s/sys", piz_mount) < (int)sizeof(sys_path)) {
    if (mkdir(sys_path, 0755) == -1 && errno != EEXIST) {
      fprintf(stderr, "⚠️  Failed to create %s: %s\n", sys_path, strerror(errno));
    } else {
      if (mount("/sys", sys_path, NULL, MS_BIND | MS_REC, NULL) == -1) {
        // Non-fatal: many programs work fine without /sys
        if (verbose) {
          printf("  ⚠️  /sys not available (optional)\n");
        }
      } else if (verbose) {
        printf("  ✅ /sys available\n");
      }
    }
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

    // Verify filesystem operations work INSIDE the chroot
    struct stat vst;
    DIR *vdir;
    struct dirent *vent;
    int vfd;

    // F. stat("/") inside chroot
    if (stat("/", &vst) == -1) {
      printf("  🔍 POST-CHROOT: stat(/) FAILED: %s\n", strerror(errno));
    } else {
      printf("  🔍 POST-CHROOT: stat(/) OK, mode=%04o uid=%d gid=%d\n",
             vst.st_mode & 07777, vst.st_uid, vst.st_gid);
    }

    // G. opendir("/") inside chroot
    vdir = opendir("/");
    if (!vdir) {
      printf("  🔍 POST-CHROOT: opendir(/) FAILED: %s\n", strerror(errno));
    } else {
      printf("  🔍 POST-CHROOT: opendir(/) OK:");
      while ((vent = readdir(vdir)) != NULL) {
        printf(" %s", vent->d_name);
      }
      printf("\n");
      closedir(vdir);
    }

    // H. create file at "/" inside chroot
    vfd = open("/.piz_probe", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (vfd == -1) {
      printf("  🔍 POST-CHROOT: create(/.piz_probe) FAILED: %s\n", strerror(errno));
    } else {
      close(vfd);
      unlink("/.piz_probe");
      printf("  🔍 POST-CHROOT: create(/.piz_probe) OK\n");
    }

    // I. stat("/bin") inside chroot
    if (stat("/bin", &vst) == -1) {
      printf("  🔍 POST-CHROOT: stat(/bin) FAILED: %s\n", strerror(errno));
    } else {
      printf("  🔍 POST-CHROOT: stat(/bin) OK, is_dir=%d\n", S_ISDIR(vst.st_mode));
    }

    // J. opendir("/bin") inside chroot
    vdir = opendir("/bin");
    if (!vdir) {
      printf("  🔍 POST-CHROOT: opendir(/bin) FAILED: %s\n", strerror(errno));
    } else {
      printf("  🔍 POST-CHROOT: opendir(/bin) OK:");
      while ((vent = readdir(vdir)) != NULL) {
        if (strcmp(vent->d_name, ".") && strcmp(vent->d_name, ".."))
          printf(" %s", vent->d_name);
      }
      printf("\n");
      closedir(vdir);
    }

    // K. stat("/bin/lsdir") inside chroot
    if (stat("/bin/lsdir", &vst) == -1) {
      printf("  🔍 POST-CHROOT: stat(/bin/lsdir) FAILED: %s\n", strerror(errno));
    } else {
      printf("  🔍 POST-CHROOT: stat(/bin/lsdir) OK, size=%ld\n", (long)vst.st_size);
    }

    // L. CRITICAL: Check APE loader exists inside chroot
    if (stat("/usr/bin/ape", &vst) == -1) {
      printf("  ⚠️  POST-CHROOT: /usr/bin/ape MISSING - APE binaries will fail to execute!\n");
      printf("      Error: %s\n", strerror(errno));
      printf("      (You'll see 'No such file or directory' when running /bin/lsdir etc.)\n");
    } else {
      printf("  ✅ POST-CHROOT: /usr/bin/ape exists (APE binaries should work)\n");
    }
  }

  // Clean environment: start fresh, only set what's needed inside the chroot
  clearenv();
  setenv("PATH", "/bin:/usr/bin", 1);
  setenv("PWD", "/", 1);
  setenv("HOME", "/", 1);
  setenv("SHELL", "/bin/mtsh", 1);
  setenv("MTSH_MODE", "toast", 1);
  setenv("TOASTER_STATE", state_name, 1);
  if (saved_term[0])
    setenv("TERM", saved_term, 1);

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
