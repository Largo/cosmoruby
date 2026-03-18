static int HealthCheck(const char *prog) {
  return CheckZip(false, false);
}

static int RunApp(const char *prog) {
  printf("🍞 Mexican Toaster - Minimal App\n");
  printf("This is where your app logic would go!\n");
  printf("Run '%s toast' to get toasted and enter the shell.\n",
         prog);
  return EX_OK;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    return RunApp(argv[0]);
  }

  if (!strcmp(argv[1], "check")) {
    return HealthCheck(argv[0]);
  }

  if (!strcmp(argv[1], "overlay")) {
    return Overlay();
  }

  if (!strcmp(argv[1], "toast")) {
    return Toast(argv[0]);
  }

  if (!strcmp(argv[1], "warm")) {
    return WarmCmd(argv[0]);
  }

  if (!strcmp(argv[1], "thaw")) {
    // --thaw toast: thaw then enter shell
    if (argc >= 3 && !strcmp(argv[2], "toast")) {
      int rc = Thaw(argv[0]);
      if (rc != EX_OK) return rc;
      return Toast(argv[0]);
    }
    return Thaw(argv[0]);
  }

  if (!strcmp(argv[1], "freeze")) {
    return Freeze(argv[0]);
  }

  if (!strcmp(argv[1], "persist")) {
    return Persist(argv[0]);
  }

  if (!strcmp(argv[1], "discard")) {
    return Discard(argv[0]);
  }

  if (!strcmp(argv[1], "status")) {
    return Status(argv[0]);
  }

  if (!strcmp(argv[1], "list")) {
    return ListPersisted(argv[0]);
  }

  if (!strcmp(argv[1], "ls")) {
    return ListZip(argv[0], argc >= 3 ? argv[2] : NULL);
  }

  if (!strcmp(argv[1], "cat")) {
    if (argc < 3) {
      fprintf(stderr, "Usage: %s cat FILE\n", argv[0]);
      return EX_USAGE;
    }
    return CatFile(argv[2]);
  }

  if (!strcmp(argv[1], "help") || !strcmp(argv[1], "--help") ||
      !strcmp(argv[1], "-h")) {
    ShowUsage(argv[0]);
    return EX_OK;
  }

  fprintf(stderr, "Unknown command: %s\n", argv[1]);
  ShowUsage(argv[0]);
  return EX_USAGE;
}
