static void ShowUsage(const char *prog) {
  fprintf(stderr, "Usage: %s [command]\n\n", prog);
  fprintf(stderr, "Commands:\n");
  fprintf(stderr, "  check    Health check: verify ZIP and writable overlay\n");
  fprintf(stderr, "  overlay  Health check + prepare writable overlay (portable stub)\n");
  fprintf(stderr, "  toast    Get toasted! Enter interactive shell inside the app\n");
  fprintf(stderr, "  ls       List contents of embedded filesystem\n");
  fprintf(stderr, "  cat FILE Read a file from embedded filesystem\n");
  fprintf(stderr, "  help     Show this help message\n");
  fprintf(stderr, "\nWith no command, runs the app normally.\n");
}
