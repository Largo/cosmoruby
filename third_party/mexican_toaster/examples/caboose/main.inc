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

  if (!strcmp(argv[1], "ls")) {
    return ListZip(argv[0]);
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
