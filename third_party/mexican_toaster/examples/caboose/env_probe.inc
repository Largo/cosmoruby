static bool FileExists(const char *path) {
  struct stat st;
  return stat(path, &st) == 0;
}

static int ReadSmallFile(const char *path, char *buf, size_t n) {
  int fd = open(path, O_RDONLY);
  if (fd == -1) return -1;
  ssize_t rc = read(fd, buf, n - 1);
  if (rc >= 0) buf[rc] = '\0';
  close(fd);
  return rc;
}

static bool GrepFile(const char *path, const char *needle) {
  char buf[512];
  int fd = open(path, O_RDONLY);
  if (fd == -1) return false;
  ssize_t n;
  bool found = false;
  while ((n = read(fd, buf, sizeof(buf))) > 0) {
    if (memmem(buf, n, needle, strlen(needle))) {
      found = true;
      break;
    }
  }
  close(fd);
  return found;
}

static bool FindExec(const char *prog, char *out, size_t outlen) {
  if (!prog || !*prog) return false;
  if (strchr(prog, '/')) {
    if (!access(prog, X_OK) && realpath(prog, out)) return true;
    return false;
  }
  const char *path = getenv("PATH");
  if (!path || !*path) return false;
  char buf[4096];
  strncpy(buf, path, sizeof(buf) - 1);
  buf[sizeof(buf) - 1] = '\0';
  for (char *p = buf, *tok; p; p = tok ? tok + 1 : NULL) {
    tok = strchr(p, ':');
    if (tok) *tok = '\0';
    char candidate[PATH_MAX];
    if (snprintf(candidate, sizeof(candidate), "%s/%s", p, prog) <
        (int)sizeof(candidate)) {
      if (!access(candidate, X_OK) && realpath(candidate, out)) return true;
    }
    if (!tok) break;
  }
  return false;
}

static bool WriteMap(const char *path, const char *buf) {
  int fd = open(path, O_WRONLY);
  if (fd == -1) return false;
  bool ok = write(fd, buf, strlen(buf)) == (ssize_t)strlen(buf);
  close(fd);
  return ok;
}

static int UnshareLinux(int flags) {
  return unshare(flags);
}

struct OverlayProbe {
  bool userns_ok;
  char userns_msg[128];
  bool overlayfs_ok;
  char overlayfs_msg[128];
};

struct EnvReport {
  bool is_linux;
  bool is_wsl1;
  bool is_wsl2;
  bool has_dockerenv;
  bool has_containerenv;
  bool cgroup_container;
  char cgroup_hint[64];
  bool unpriv_userns_present;
  int unpriv_userns_clone;
  bool setgroups_exists;
  bool setgroups_writable;
  bool has_userns_status;
  bool userns_is_zero;
  bool can_chroot;
  bool can_pivot;
  bool fuse_dev;
  char fuse_overlayfs_path[PATH_MAX];
  bool fuse_dev_rw;
  char fuse_dev_msg[64];
  bool fuse_overlayfs_exec;
  char fuse_overlayfs_exec_msg[128];
  bool libfuse_present;
  bool libfuse_runtime;
  bool k_overlayfs;
  bool k_fusefs;
  bool cap_sys_admin;
  bool proc_mount_ok;
  char proc_mount_msg[64];

  bool kconfig_user_ns;
  bool kconfig_pid_ns;
  bool kconfig_net_ns;
  bool kconfig_ipc_ns;
  bool kconfig_uts_ns;
  bool kconfig_cgroup_ns;
  bool kconfig_overlay_fs;
  bool kconfig_fuse_fs;
  char kconfig_msg[128];

  char distro_name[64];
  char distro_version[64];
  char distro_id[32];
  char kernel_version[128];
};

static void ProbeKernelConfig(struct EnvReport *e) {
  char boot_config[256];
  if (e->kernel_version[0]) {
    snprintf(boot_config, sizeof(boot_config), "/boot/config-%s", e->kernel_version);
    char *nl = strchr(boot_config, '\n');
    if (nl) *nl = '\0';
  }

  bool found_config = false;
  if (FileExists("/proc/config.gz")) {
    snprintf(e->kconfig_msg, sizeof(e->kconfig_msg),
             "/proc/config.gz exists but requires decompression");
    found_config = true;
  }

  if (!found_config && e->kernel_version[0] && FileExists(boot_config)) {
    e->kconfig_user_ns = GrepFile(boot_config, "CONFIG_USER_NS=y");
    e->kconfig_pid_ns = GrepFile(boot_config, "CONFIG_PID_NS=y");
    e->kconfig_net_ns = GrepFile(boot_config, "CONFIG_NET_NS=y");
    e->kconfig_ipc_ns = GrepFile(boot_config, "CONFIG_IPC_NS=y");
    e->kconfig_uts_ns = GrepFile(boot_config, "CONFIG_UTS_NS=y");
    e->kconfig_cgroup_ns = GrepFile(boot_config, "CONFIG_CGROUP_NS=y");
    e->kconfig_overlay_fs = GrepFile(boot_config, "CONFIG_OVERLAY_FS=y");
    e->kconfig_fuse_fs = GrepFile(boot_config, "CONFIG_FUSE_FS=y");
    snprintf(e->kconfig_msg, sizeof(e->kconfig_msg), "read from /boot/config");
    found_config = true;
  }

  if (!found_config) {
    e->kconfig_user_ns = FileExists("/proc/self/ns/user");
    e->kconfig_pid_ns = FileExists("/proc/self/ns/pid");
    e->kconfig_net_ns = FileExists("/proc/self/ns/net");
    e->kconfig_ipc_ns = FileExists("/proc/self/ns/ipc");
    e->kconfig_uts_ns = FileExists("/proc/self/ns/uts");
    e->kconfig_cgroup_ns = FileExists("/proc/self/ns/cgroup");
    e->kconfig_overlay_fs = e->k_overlayfs;
    e->kconfig_fuse_fs = e->k_fusefs;

    snprintf(e->kconfig_msg, sizeof(e->kconfig_msg),
             "inferred from /proc/self/ns/* (no config file found)");
    found_config = true;
  }

  if (!found_config) {
    snprintf(e->kconfig_msg, sizeof(e->kconfig_msg), "no kernel config available");
  }
}

static void ProbeDistroInfo(struct EnvReport *e) {
  char buf[512];

  if (ReadSmallFile("/proc/sys/kernel/osrelease", e->kernel_version,
                    sizeof(e->kernel_version)) >= 0) {
    char *nl = strchr(e->kernel_version, '\n');
    if (nl) *nl = '\0';
  }

  if (FileExists("/etc/os-release")) {
    FILE *f = fopen("/etc/os-release", "r");
    if (f) {
      while (fgets(buf, sizeof(buf), f)) {
        char *eq = strchr(buf, '=');
        if (!eq) continue;
        *eq = '\0';
        char *val = eq + 1;

        if (*val == '"') val++;
        char *end = strchr(val, '"');
        if (end) *end = '\0';
        end = strchr(val, '\n');
        if (end) *end = '\0';

        if (!strcmp(buf, "NAME")) {
          strncpy(e->distro_name, val, sizeof(e->distro_name) - 1);
        } else if (!strcmp(buf, "VERSION")) {
          strncpy(e->distro_version, val, sizeof(e->distro_version) - 1);
        } else if (!strcmp(buf, "ID")) {
          strncpy(e->distro_id, val, sizeof(e->distro_id) - 1);
        }
      }
      fclose(f);
      return;
    }
  }

  if (FileExists("/etc/lsb-release")) {
    FILE *f = fopen("/etc/lsb-release", "r");
    if (f) {
      while (fgets(buf, sizeof(buf), f)) {
        char *eq = strchr(buf, '=');
        if (!eq) continue;
        *eq = '\0';
        char *val = eq + 1;

        if (*val == '"') val++;
        char *end = strchr(val, '"');
        if (end) *end = '\0';
        end = strchr(val, '\n');
        if (end) *end = '\0';

        if (!strcmp(buf, "DISTRIB_ID")) {
          strncpy(e->distro_id, val, sizeof(e->distro_id) - 1);
        } else if (!strcmp(buf, "DISTRIB_DESCRIPTION")) {
          strncpy(e->distro_name, val, sizeof(e->distro_name) - 1);
        } else if (!strcmp(buf, "DISTRIB_RELEASE")) {
          strncpy(e->distro_version, val, sizeof(e->distro_version) - 1);
        }
      }
      fclose(f);
      return;
    }
  }

  if (FileExists("/etc/debian_version")) {
    strcpy(e->distro_id, "debian");
    if (ReadSmallFile("/etc/debian_version", buf, sizeof(buf)) >= 0) {
      char *nl = strchr(buf, '\n');
      if (nl) *nl = '\0';
      strncpy(e->distro_version, buf, sizeof(e->distro_version) - 1);
      e->distro_version[sizeof(e->distro_version) - 1] = '\0';
    }
  } else if (FileExists("/etc/redhat-release")) {
    strcpy(e->distro_id, "redhat");
    if (ReadSmallFile("/etc/redhat-release", buf, sizeof(buf)) >= 0) {
      char *nl = strchr(buf, '\n');
      if (nl) *nl = '\0';
      strncpy(e->distro_name, buf, sizeof(e->distro_name) - 1);
      e->distro_name[sizeof(e->distro_name) - 1] = '\0';
    }
  } else if (FileExists("/etc/arch-release")) {
    strcpy(e->distro_id, "arch");
    strcpy(e->distro_name, "Arch Linux");
  }
}

static void DetectEnv(struct EnvReport *e) {
  memset(e, 0, sizeof(*e));
  e->is_linux = IsLinux();

  char osrel[256];
  if (ReadSmallFile("/proc/sys/kernel/osrelease", osrel, sizeof(osrel)) >= 0) {
    if (strstr(osrel, "Microsoft")) e->is_wsl1 = true;
    if (strstr(osrel, "microsoft-standard")) {
      e->is_wsl2 = true;
      e->is_wsl1 = false;
    }
  }
  const char *wsl_env = getenv("WSL_DISTRO_NAME");
  if (wsl_env && *wsl_env) {
    if (strstr(wsl_env, "WSL2")) {
      e->is_wsl2 = true;
      e->is_wsl1 = false;
    } else if (!e->is_wsl2) {
      e->is_wsl1 = true;
    }
  }

  e->has_dockerenv = FileExists("/.dockerenv");
  e->has_containerenv = FileExists("/run/.containerenv");

  char cgroup[512];
  if (ReadSmallFile("/proc/1/cgroup", cgroup, sizeof(cgroup)) >= 0) {
    if (strstr(cgroup, "docker")) {
      e->cgroup_container = true;
      strcpy(e->cgroup_hint, "docker");
    } else if (strstr(cgroup, "kubepods") || strstr(cgroup, "containerd")) {
      e->cgroup_container = true;
      strcpy(e->cgroup_hint, "k8s/containerd");
    } else if (strstr(cgroup, "podman")) {
      e->cgroup_container = true;
      strcpy(e->cgroup_hint, "podman");
    } else if (strstr(cgroup, "lxc")) {
      e->cgroup_container = true;
      strcpy(e->cgroup_hint, "lxc");
    }
  }

  char buf[32];
  if (ReadSmallFile("/proc/sys/kernel/unprivileged_userns_clone", buf,
                    sizeof(buf)) >= 0) {
    e->unpriv_userns_present = true;
    e->unpriv_userns_clone = atoi(buf);
  }

  char status[256];
  if (ReadSmallFile("/proc/self/status", status, sizeof(status)) >= 0) {
    const char *userns = strstr(status, "UserNS:");
    if (userns) {
      e->has_userns_status = true;
      if (strstr(userns, "0\n")) e->userns_is_zero = true;
    }
    const char *cap = strstr(status, "CapEff:");
    if (cap) {
      unsigned long long val = 0;
      if (sscanf(cap, "CapEff:\t%llx", &val) == 1) {
        if (val & (1ull << 21)) e->cap_sys_admin = true;
      }
    }
  }

  int fd = open("/proc/self/setgroups", O_WRONLY);
  if (fd != -1) {
    e->setgroups_exists = true;
    e->setgroups_writable = true;
    close(fd);
  } else if (errno == EACCES) {
    e->setgroups_exists = true;
    e->setgroups_writable = false;
  }

  e->fuse_dev = FileExists("/dev/fuse");
  int fdfuse = open("/dev/fuse", O_RDWR);
  if (fdfuse != -1) {
    e->fuse_dev_rw = true;
    close(fdfuse);
  } else if (errno) {
    snprintf(e->fuse_dev_msg, sizeof(e->fuse_dev_msg), "%s", strerror(errno));
  }
  if (FindExec("fuse-overlayfs", e->fuse_overlayfs_path,
               sizeof(e->fuse_overlayfs_path))) {
  } else if (FindExec("/zip/bin/fuse-overlayfs", e->fuse_overlayfs_path,
                      sizeof(e->fuse_overlayfs_path))) {
  } else {
    e->fuse_overlayfs_path[0] = '\0';
  }
  if (FindExec("pkg-config", buf, sizeof(buf))) {
    pid_t p = fork();
    if (p == 0) {
      const char *argvv[] = {buf, "--exists", "fuse", NULL};
      execv(buf, (char *const *)argvv);
      _exit(127);
    } else if (p > 0) {
      int st = 0;
      if (waitpid(p, &st, 0) == p && st == 0) {
        e->libfuse_present = true;
      }
    }
  }
  void *h = dlopen("libfuse3.so.3", RTLD_LAZY | RTLD_LOCAL);
  if (h) {
    e->libfuse_runtime = true;
    dlclose(h);
  } else {
    h = dlopen("libfuse.so.2", RTLD_LAZY | RTLD_LOCAL);
    if (h) {
      e->libfuse_runtime = true;
      dlclose(h);
    }
  }
  if (e->fuse_overlayfs_path[0]) {
    pid_t p = fork();
    if (p == 0) {
      const char *argvv[] = {e->fuse_overlayfs_path, "--version", NULL};
      execv(e->fuse_overlayfs_path, (char *const *)argvv);
      _exit(127);
    } else if (p > 0) {
      int st = 0;
      if (waitpid(p, &st, 0) == p && st == 0) {
        e->fuse_overlayfs_exec = true;
      } else {
        snprintf(e->fuse_overlayfs_exec_msg,
                 sizeof(e->fuse_overlayfs_exec_msg), "exit status %d", st);
      }
    } else {
      snprintf(e->fuse_overlayfs_exec_msg, sizeof(e->fuse_overlayfs_exec_msg),
               "fork: %s", strerror(errno));
    }
  }

  e->k_overlayfs = GrepFile("/proc/filesystems", "overlay");
  e->k_fusefs = GrepFile("/proc/filesystems", "fuse");

  ProbeDistroInfo(e);
  ProbeKernelConfig(e);
}

static void ProbeOverlayUserns(struct OverlayProbe *r) {
  int fd;
  pid_t pid;
  int status;
  int pipefd[2];
  struct OverlayProbe child = {0};

  if (pipe(pipefd) == -1) {
    snprintf(r->userns_msg, sizeof(r->userns_msg), "pipe: %s",
             strerror(errno));
    return;
  }

  pid = fork();
  if (pid == -1) {
    snprintf(r->userns_msg, sizeof(r->userns_msg), "fork: %s",
             strerror(errno));
    close(pipefd[0]);
    close(pipefd[1]);
    return;
  }

  if (pid == 0) {
    close(pipefd[0]);

    if (UnshareLinux(CLONE_NEWUSER | CLONE_NEWNS) == -1) {
      snprintf(child.userns_msg, sizeof(child.userns_msg),
               "unshare(CLONE_NEWUSER|CLONE_NEWNS): %s", strerror(errno));
      write(pipefd[1], &child, sizeof(child));
      _exit(0);
    }

    fd = open("/proc/self/setgroups", O_WRONLY);
    if (fd != -1) {
      if (write(fd, "deny\n", 5) != 5) {
        snprintf(child.userns_msg, sizeof(child.userns_msg),
                 "write setgroups: %s", strerror(errno));
        close(fd);
        write(pipefd[1], &child, sizeof(child));
        _exit(0);
      }
      close(fd);
    }

    uid_t uid = getuid();
    gid_t gid = getgid();
    char map[64];

    snprintf(map, sizeof(map), "0 %u 1\n", (unsigned)uid);
    if (!WriteMap("/proc/self/uid_map", map)) {
      snprintf(child.userns_msg, sizeof(child.userns_msg),
               "write uid_map: %s", strerror(errno));
      write(pipefd[1], &child, sizeof(child));
      _exit(0);
    }

    snprintf(map, sizeof(map), "0 %u 1\n", (unsigned)gid);
    if (!WriteMap("/proc/self/gid_map", map)) {
      snprintf(child.userns_msg, sizeof(child.userns_msg),
               "write gid_map: %s", strerror(errno));
      write(pipefd[1], &child, sizeof(child));
      _exit(0);
    }

    child.userns_ok = true;

    mount(0, "/", 0, MS_REC | MS_PRIVATE, 0);

    char base[PATH_MAX];
    char lower[PATH_MAX];
    char upper[PATH_MAX];
    char work[PATH_MAX];
    char merged[PATH_MAX];

    strcpy(base, "/tmp/toast_overlay_probeXXXXXX");
    if (!mkdtemp(base)) {
      snprintf(child.overlayfs_msg, sizeof(child.overlayfs_msg),
               "mkdtemp: %s", strerror(errno));
      write(pipefd[1], &child, sizeof(child));
      _exit(0);
    }

    snprintf(lower, sizeof(lower), "%s/lower", base);
    snprintf(upper, sizeof(upper), "%s/upper", base);
    snprintf(work, sizeof(work), "%s/work", base);
    snprintf(merged, sizeof(merged), "%s/merged", base);
    mkdir(lower, 0700);
    mkdir(upper, 0700);
    mkdir(work, 0700);
    mkdir(merged, 0700);

    int lfd = open(lower, O_DIRECTORY | O_RDONLY);
    if (lfd != -1) close(lfd);
    char probe_path[PATH_MAX];
    if (snprintf(probe_path, sizeof(probe_path), "%s/file", lower) >=
        (int)sizeof(probe_path)) {
      snprintf(child.overlayfs_msg, sizeof(child.overlayfs_msg),
               "probe path too long");
      write(pipefd[1], &child, sizeof(child));
      _exit(0);
    }
    int f = open(probe_path, O_CREAT | O_WRONLY, 0600);
    if (f != -1) {
      write(f, "probe", 5);
      close(f);
    }

    char opts[PATH_MAX * 2];
    if (snprintf(opts, sizeof(opts), "lowerdir=%s,upperdir=%s,workdir=%s",
                 lower, upper, work) >= (int)sizeof(opts)) {
      snprintf(child.overlayfs_msg, sizeof(child.overlayfs_msg),
               "overlay opts too long");
      write(pipefd[1], &child, sizeof(child));
      _exit(0);
    }

    if (mount("overlay", merged, "overlay", MS_NODEV | MS_NOSUID, opts) == -1) {
      snprintf(child.overlayfs_msg, sizeof(child.overlayfs_msg),
               "mount overlay: %s", strerror(errno));
    } else {
      child.overlayfs_ok = true;
    }

    write(pipefd[1], &child, sizeof(child));
    _exit(0);
  }

  close(pipefd[1]);
  ssize_t got = read(pipefd[0], &child, sizeof(child));
  close(pipefd[0]);
  waitpid(pid, &status, 0);
  (void)status;

  if (got == sizeof(child)) {
    *r = child;
    if (!r->userns_ok && !r->userns_msg[0]) {
      snprintf(r->userns_msg, sizeof(r->userns_msg), "unknown failure");
    }
    if (!r->overlayfs_ok && !r->overlayfs_msg[0]) {
      snprintf(r->overlayfs_msg, sizeof(r->overlayfs_msg), "not attempted");
    }
  } else {
    snprintf(r->userns_msg, sizeof(r->userns_msg), "probe read failed");
  }
}

static void ReportOverlayCapabilities(void) {
  struct OverlayProbe r = {0};
  struct EnvReport env;
  DetectEnv(&env);

  printf("🔎 Overlay environment probe:\n");
  printf("\n📋 System Information:\n");
  if (env.distro_name[0] || env.distro_id[0]) {
    printf("  OS: %s%s%s%s\n",
           env.distro_name[0] ? env.distro_name : env.distro_id,
           env.distro_version[0] ? " " : "",
           env.distro_version[0] ? env.distro_version : "",
           env.distro_id[0] && env.distro_name[0] ? "" : " (detected)");
  }
  if (env.kernel_version[0]) {
    printf("  Kernel: %s\n", env.kernel_version);
  }
  printf("  %s Platform: %s # overlayfs userns only on Linux; others need fuse/userland\n",
         env.is_linux ? "✅" : "❌",
         env.is_linux ? "Linux" : "Non-Linux");
  if (env.is_wsl2) {
    printf("  ℹ️  Detected WSL2 # Linux kernel under Hyper-V\n");
  } else if (env.is_wsl1) {
    printf("  ℹ️  Detected WSL1 (no Linux syscalls) # userns/overlayfs not available\n");
  }
  if (env.has_dockerenv || env.has_containerenv || env.cgroup_container) {
    printf("  ℹ️  Container hints: %s%s%s%s%s # may have seccomp/cgroup mount limits\n",
           env.has_dockerenv ? "/.dockerenv " : "",
           env.has_containerenv ? "/run/.containerenv " : "",
           env.cgroup_container ? "cgroup:" : "",
           env.cgroup_container ? env.cgroup_hint : "",
           env.cgroup_container ? "" : "");
  } else {
    printf("  ℹ️  Container hints: none observed # likely on host\n");
  }
  if (env.unpriv_userns_present) {
    printf("  ℹ️  /proc/sys/kernel/unprivileged_userns_clone = %d # 1 permits unpriv userns (if CONFIG_USER_NS)\n",
           env.unpriv_userns_clone);
  } else {
    printf("  ℹ️  /proc/sys/kernel/unprivileged_userns_clone missing # kernel may lack CONFIG_USER_NS or sysctl\n");
  }
  if (env.has_userns_status) {
    printf("  ℹ️  /proc/self/status UserNS observed%s # UserNS id=0 may indicate no userns support\n",
           env.userns_is_zero ? " (id=0, likely init/userns disabled)" : "");
  } else {
    printf("  ℹ️  /proc/self/status does not expose UserNS # cannot infer userns id\n");
  }
  printf("  ℹ️  CAP_SYS_ADMIN effective: %s # required for host mounts/chroot/pivot_root\n",
         env.cap_sys_admin ? "yes" : "no");
  if (env.setgroups_exists) {
    printf("  ℹ️  /proc/self/setgroups writable: %s # must be writable to map gids in userns\n",
           env.setgroups_writable ? "yes" : "no (may block userns mappings)");
  } else {
    printf("  ℹ️  /proc/self/setgroups not present # legacy kernel or restricted proc\n");
  }
  printf("  ℹ️  /dev/fuse: %s # needed for fuse-overlayfs\n",
         env.fuse_dev ? "present" : "missing");
  if (env.fuse_dev && !env.fuse_dev_rw) {
    printf("  ℹ️  /dev/fuse access: %s # need R/W for FUSE mounts\n",
           env.fuse_dev_msg[0] ? env.fuse_dev_msg : "open failed");
  } else if (env.fuse_dev) {
    printf("  ℹ️  /dev/fuse access: ok (read/write) # FUSE backend viable if binary exists\n");
  }
  if (env.fuse_overlayfs_path[0]) {
    printf("  ℹ️  fuse-overlayfs binary: %s # userspace overlay mount helper\n", env.fuse_overlayfs_path);
    printf("  ℹ️  fuse-overlayfs probe: %s # ran --version to confirm it executes\n",
           env.fuse_overlayfs_exec ? "ok"
                                   : env.fuse_overlayfs_exec_msg[0]
                                         ? env.fuse_overlayfs_exec_msg
                                         : "probe failed");
  } else {
    printf("  ℹ️  fuse-overlayfs binary: not found in PATH or /zip/bin # add static binary to use fuse backend\n");
  }
  printf("  ℹ️  libfuse (pkg-config fuse): %s # only relevant for dynamic fuse-overlayfs\n",
         env.libfuse_present ? "present (dev files)" : env.libfuse_runtime
                                                      ? "runtime only (no pkg-config files)"
                                                      : "not found");
  printf("  ℹ️  Kernel filesystems: overlayfs=%s fuse=%s # from /proc/filesystems\n",
         env.k_overlayfs ? "yes" : "no",
         env.k_fusefs ? "yes" : "no");

  printf("\n⚙️  Kernel Configuration (%s):\n", env.kconfig_msg);
  printf("  CONFIG_USER_NS: %s # user namespaces for unprivileged containers\n",
         env.kconfig_user_ns ? "✅ enabled" : "❌ disabled/unknown");
  printf("  CONFIG_PID_NS: %s # PID namespaces\n",
         env.kconfig_pid_ns ? "✅ enabled" : "❌ disabled/unknown");
  printf("  CONFIG_NET_NS: %s # network namespaces\n",
         env.kconfig_net_ns ? "✅ enabled" : "❌ disabled/unknown");
  printf("  CONFIG_IPC_NS: %s # IPC namespaces\n",
         env.kconfig_ipc_ns ? "✅ enabled" : "❌ disabled/unknown");
  printf("  CONFIG_UTS_NS: %s # UTS namespaces (hostname/domain)\n",
         env.kconfig_uts_ns ? "✅ enabled" : "❌ disabled/unknown");
  printf("  CONFIG_CGROUP_NS: %s # cgroup namespaces\n",
         env.kconfig_cgroup_ns ? "✅ enabled" : "❌ disabled/unknown");
  printf("  CONFIG_OVERLAY_FS: %s # kernel overlay filesystem\n",
         env.kconfig_overlay_fs ? "✅ enabled" : "❌ disabled/unknown");
  printf("  CONFIG_FUSE_FS: %s # FUSE filesystem support\n",
         env.kconfig_fuse_fs ? "✅ enabled" : "❌ disabled/unknown");

  if (!env.is_linux) return;

  printf("\n🔬 Runtime Capability Probes:\n");
  {
    if (chroot("/")) {
      printf("  ❌ chroot(2) in current namespace: %s\n", strerror(errno));
    } else {
      printf("  ✅ chroot(2) in current namespace: permitted (noop)\n");
      env.can_chroot = true;
    }
  }
  {
    if (pivot_root(".", ".")) {
      printf("  ❌ pivot_root(2) in current namespace: %s\n", strerror(errno));
    } else {
      printf("  ✅ pivot_root(2) in current namespace: permitted (noop)\n");
      env.can_pivot = true;
    }
  }
  {
    char tmpdir[] = "/tmp/toast_proc_probeXXXXXX";
    if (mkdtemp(tmpdir)) {
      if (mount("proc", tmpdir, "proc", MS_RDONLY | MS_NODEV | MS_NOSUID, 0) ==
          0) {
        env.proc_mount_ok = true;
        unmount(tmpdir, 0);
      } else {
        snprintf(env.proc_mount_msg, sizeof(env.proc_mount_msg), "%s",
                 strerror(errno));
      }
      rmdir(tmpdir);
    }
    printf("  ℹ️  proc mount in current ns: %s%s\n",
           env.proc_mount_ok ? "ok" : "failed",
           env.proc_mount_ok ? "" : env.proc_mount_msg[0] ? env.proc_mount_msg : "");
  }

  ProbeOverlayUserns(&r);
  printf("  %s user namespace + mount namespace: %s\n",
         r.userns_ok ? "✅" : "❌",
         r.userns_ok ? "supported" : r.userns_msg[0] ? r.userns_msg : "no");
  printf("  %s overlayfs mount inside userns: %s\n",
         r.overlayfs_ok ? "✅" : "❌",
         r.overlayfs_ok ? "supported"
                        : r.overlayfs_msg[0] ? r.overlayfs_msg : "no");
  if (!r.overlayfs_ok) {
    printf("  ℹ️  Fallbacks: fuse-overlayfs or userland copy-up will be needed.\n");
  }
}
