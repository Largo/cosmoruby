/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Tests for the Mexican Toaster state machine and state file persistence.    │
╚─────────────────────────────────────────────────────────────────────────────*/
#include "libc/calls/calls.h"
#include "libc/calls/struct/stat.h"
#include "libc/errno.h"
#include "libc/limits.h"
#include "libc/nexgen32e/crc32.h"
#include "libc/runtime/runtime.h"
#include "libc/stdio/stdio.h"
#include "libc/fmt/conv.h"
#include <stdbool.h>
#include <stdlib.h>
#include "libc/str/str.h"
#include "libc/sysv/consts/ex.h"
#include "libc/sysv/consts/o.h"
#include "libc/temp.h"
#include "libc/time.h"
#include "third_party/tomlc99/toml.h"

// Include the units under test
#include "third_party/mexican_toaster/examples/caboose/state.inc"
#include "third_party/mexican_toaster/examples/caboose/state_file.inc"

static int tests_run;
static int tests_passed;
static int tests_failed;

#define TEST(name) \
  static void test_##name(void); \
  static void run_##name(void) { \
    tests_run++; \
    printf("  %-50s ", #name); \
    test_##name(); \
  } \
  static void test_##name(void)

#define ASSERT(cond) do { \
  if (!(cond)) { \
    printf("FAIL\n    %s:%d: %s\n", __FILE__, __LINE__, #cond); \
    tests_failed++; \
    return; \
  } \
} while (0)

#define ASSERT_EQ_INT(a, b) do { \
  int _a = (a), _b = (b); \
  if (_a != _b) { \
    printf("FAIL\n    %s:%d: %d != %d\n", __FILE__, __LINE__, _a, _b); \
    tests_failed++; \
    return; \
  } \
} while (0)

#define ASSERT_EQ_STR(a, b) do { \
  const char *_a = (a), *_b = (b); \
  if (strcmp(_a, _b) != 0) { \
    printf("FAIL\n    %s:%d: \"%s\" != \"%s\"\n", __FILE__, __LINE__, _a, _b); \
    tests_failed++; \
    return; \
  } \
} while (0)

#define PASS() do { printf("ok\n"); tests_passed++; } while (0)

// ============================================================
// State transition tests
// ============================================================

TEST(cold_thaw_gives_thawed) {
  enum ToasterState to;
  ASSERT_EQ_INT(0, ToasterTransition(kCold, kActionThaw, &to));
  ASSERT_EQ_INT(kThawed, to);
  PASS();
}

TEST(cold_freeze_invalid) {
  enum ToasterState to;
  ASSERT_EQ_INT(-1, ToasterTransition(kCold, kActionFreeze, &to));
  PASS();
}

TEST(cold_persist_invalid) {
  enum ToasterState to;
  ASSERT_EQ_INT(-1, ToasterTransition(kCold, kActionPersist, &to));
  PASS();
}

TEST(cold_discard_invalid) {
  enum ToasterState to;
  ASSERT_EQ_INT(-1, ToasterTransition(kCold, kActionDiscard, &to));
  PASS();
}

TEST(thawed_freeze_gives_frozen) {
  enum ToasterState to;
  ASSERT_EQ_INT(0, ToasterTransition(kThawed, kActionFreeze, &to));
  ASSERT_EQ_INT(kFrozen, to);
  PASS();
}

TEST(thawed_persist_gives_persisted) {
  enum ToasterState to;
  ASSERT_EQ_INT(0, ToasterTransition(kThawed, kActionPersist, &to));
  ASSERT_EQ_INT(kPersisted, to);
  PASS();
}

TEST(thawed_discard_gives_cold) {
  enum ToasterState to;
  ASSERT_EQ_INT(0, ToasterTransition(kThawed, kActionDiscard, &to));
  ASSERT_EQ_INT(kCold, to);
  PASS();
}

TEST(thawed_thaw_invalid) {
  enum ToasterState to;
  ASSERT_EQ_INT(-1, ToasterTransition(kThawed, kActionThaw, &to));
  PASS();
}

TEST(frozen_thaw_gives_thawed) {
  enum ToasterState to;
  ASSERT_EQ_INT(0, ToasterTransition(kFrozen, kActionThaw, &to));
  ASSERT_EQ_INT(kThawed, to);
  PASS();
}

TEST(frozen_persist_gives_persisted) {
  enum ToasterState to;
  ASSERT_EQ_INT(0, ToasterTransition(kFrozen, kActionPersist, &to));
  ASSERT_EQ_INT(kPersisted, to);
  PASS();
}

TEST(frozen_discard_gives_cold) {
  enum ToasterState to;
  ASSERT_EQ_INT(0, ToasterTransition(kFrozen, kActionDiscard, &to));
  ASSERT_EQ_INT(kCold, to);
  PASS();
}

TEST(frozen_freeze_invalid) {
  enum ToasterState to;
  ASSERT_EQ_INT(-1, ToasterTransition(kFrozen, kActionFreeze, &to));
  PASS();
}

TEST(persisted_thaw_gives_thawed) {
  enum ToasterState to;
  ASSERT_EQ_INT(0, ToasterTransition(kPersisted, kActionThaw, &to));
  ASSERT_EQ_INT(kThawed, to);
  PASS();
}

TEST(persisted_freeze_invalid) {
  enum ToasterState to;
  ASSERT_EQ_INT(-1, ToasterTransition(kPersisted, kActionFreeze, &to));
  PASS();
}

TEST(persisted_persist_invalid) {
  enum ToasterState to;
  ASSERT_EQ_INT(-1, ToasterTransition(kPersisted, kActionPersist, &to));
  PASS();
}

TEST(persisted_discard_invalid) {
  enum ToasterState to;
  ASSERT_EQ_INT(-1, ToasterTransition(kPersisted, kActionDiscard, &to));
  PASS();
}

// ============================================================
// State name tests
// ============================================================

TEST(state_names) {
  ASSERT_EQ_STR("cold", ToasterStateName(kCold));
  ASSERT_EQ_STR("thawed", ToasterStateName(kThawed));
  ASSERT_EQ_STR("frozen", ToasterStateName(kFrozen));
  ASSERT_EQ_STR("persisted", ToasterStateName(kPersisted));
  PASS();
}

TEST(action_names) {
  ASSERT_EQ_STR("thaw", ToasterActionName(kActionThaw));
  ASSERT_EQ_STR("freeze", ToasterActionName(kActionFreeze));
  ASSERT_EQ_STR("persist", ToasterActionName(kActionPersist));
  ASSERT_EQ_STR("discard", ToasterActionName(kActionDiscard));
  PASS();
}

TEST(parse_state_names) {
  enum ToasterState s;
  ASSERT_EQ_INT(0, ParseStateName("cold", &s));
  ASSERT_EQ_INT(kCold, s);
  ASSERT_EQ_INT(0, ParseStateName("thawed", &s));
  ASSERT_EQ_INT(kThawed, s);
  ASSERT_EQ_INT(0, ParseStateName("frozen", &s));
  ASSERT_EQ_INT(kFrozen, s);
  ASSERT_EQ_INT(0, ParseStateName("persisted", &s));
  ASSERT_EQ_INT(kPersisted, s);
  ASSERT_EQ_INT(-1, ParseStateName("bogus", &s));
  PASS();
}

// ============================================================
// State file path derivation
// ============================================================

TEST(derive_state_file_path) {
  char path[PATH_MAX];
  ASSERT_EQ_INT(0, DeriveStateFilePath("/usr/bin/myapp.com", path, sizeof(path)));
  // Should start with /tmp/toaster- and end with .toml
  ASSERT(strstr(path, "/tmp/toaster-") == path);
  ASSERT(strstr(path, ".toml") != NULL);
  PASS();
}

TEST(derive_state_file_path_deterministic) {
  char path1[PATH_MAX], path2[PATH_MAX];
  ASSERT_EQ_INT(0, DeriveStateFilePath("/foo/bar.com", path1, sizeof(path1)));
  ASSERT_EQ_INT(0, DeriveStateFilePath("/foo/bar.com", path2, sizeof(path2)));
  ASSERT_EQ_STR(path1, path2);
  PASS();
}

TEST(derive_state_file_path_different_binaries) {
  char path1[PATH_MAX], path2[PATH_MAX];
  ASSERT_EQ_INT(0, DeriveStateFilePath("/foo/bar.com", path1, sizeof(path1)));
  ASSERT_EQ_INT(0, DeriveStateFilePath("/foo/baz.com", path2, sizeof(path2)));
  ASSERT(strcmp(path1, path2) != 0);
  PASS();
}

// ============================================================
// State file round-trip (save then load)
// ============================================================

TEST(save_load_cold) {
  char path[PATH_MAX];
  snprintf(path, sizeof(path), "/tmp/toaster-test-%d.toml", getpid());

  struct ToasterStateFile sf_out;
  memset(&sf_out, 0, sizeof(sf_out));
  sf_out.state = kCold;
  snprintf(sf_out.binary_path, sizeof(sf_out.binary_path), "/usr/bin/test.com");

  ASSERT_EQ_INT(0, SaveStateFile(path, &sf_out));

  struct ToasterStateFile sf_in;
  ASSERT_EQ_INT(0, LoadStateFile(path, "/usr/bin/test.com", &sf_in));
  ASSERT_EQ_INT(kCold, sf_in.state);
  ASSERT_EQ_STR("/usr/bin/test.com", sf_in.binary_path);

  unlink(path);
  PASS();
}

TEST(save_load_thawed_with_paths) {
  char path[PATH_MAX];
  snprintf(path, sizeof(path), "/tmp/toaster-test-%d.toml", getpid());

  struct ToasterStateFile sf_out;
  memset(&sf_out, 0, sizeof(sf_out));
  sf_out.state = kThawed;
  snprintf(sf_out.binary_path, sizeof(sf_out.binary_path), "/app/myapp.com");
  snprintf(sf_out.upper_path, sizeof(sf_out.upper_path), "/tmp/piz-overlay-123/upper");
  snprintf(sf_out.lower_path, sizeof(sf_out.lower_path), "/tmp/piz-lower-123");
  snprintf(sf_out.work_path, sizeof(sf_out.work_path), "/tmp/piz-overlay-123/work");
  snprintf(sf_out.mount_path, sizeof(sf_out.mount_path), "/tmp/piz-mount-123");

  ASSERT_EQ_INT(0, SaveStateFile(path, &sf_out));

  struct ToasterStateFile sf_in;
  ASSERT_EQ_INT(0, LoadStateFile(path, "/app/myapp.com", &sf_in));
  ASSERT_EQ_INT(kThawed, sf_in.state);
  ASSERT_EQ_STR("/app/myapp.com", sf_in.binary_path);
  ASSERT_EQ_STR("/tmp/piz-overlay-123/upper", sf_in.upper_path);
  ASSERT_EQ_STR("/tmp/piz-lower-123", sf_in.lower_path);
  ASSERT_EQ_STR("/tmp/piz-overlay-123/work", sf_in.work_path);
  ASSERT_EQ_STR("/tmp/piz-mount-123", sf_in.mount_path);

  unlink(path);
  PASS();
}

TEST(save_load_persisted_with_history) {
  char path[PATH_MAX];
  snprintf(path, sizeof(path), "/tmp/toaster-test-%d.toml", getpid());

  struct ToasterStateFile sf_out;
  memset(&sf_out, 0, sizeof(sf_out));
  sf_out.state = kPersisted;
  snprintf(sf_out.binary_path, sizeof(sf_out.binary_path), "/app/myapp.com");
  snprintf(sf_out.orig_path, sizeof(sf_out.orig_path), "/app/myapp-orig.com");
  sf_out.persist_count = 3;
  snprintf(sf_out.persist_names[0], PATH_MAX, "/app/myapp-20260305T170000.com");
  snprintf(sf_out.persist_names[1], PATH_MAX, "/app/myapp-20260305T171000.com");
  snprintf(sf_out.persist_names[2], PATH_MAX, "/app/myapp-20260305T172300.com");

  ASSERT_EQ_INT(0, SaveStateFile(path, &sf_out));

  struct ToasterStateFile sf_in;
  ASSERT_EQ_INT(0, LoadStateFile(path, "/app/myapp.com", &sf_in));
  ASSERT_EQ_INT(kPersisted, sf_in.state);
  ASSERT_EQ_STR("/app/myapp-orig.com", sf_in.orig_path);
  ASSERT_EQ_INT(3, sf_in.persist_count);
  ASSERT_EQ_STR("/app/myapp-20260305T170000.com", sf_in.persist_names[0]);
  ASSERT_EQ_STR("/app/myapp-20260305T171000.com", sf_in.persist_names[1]);
  ASSERT_EQ_STR("/app/myapp-20260305T172300.com", sf_in.persist_names[2]);

  unlink(path);
  PASS();
}

TEST(load_nonexistent_gives_cold) {
  struct ToasterStateFile sf;
  ASSERT_EQ_INT(0, LoadStateFile("/tmp/toaster-nonexistent-99999.toml",
                                  "/bin/test.com", &sf));
  ASSERT_EQ_INT(kCold, sf.state);
  ASSERT_EQ_STR("/bin/test.com", sf.binary_path);
  PASS();
}

TEST(remove_state_file) {
  char path[PATH_MAX];
  snprintf(path, sizeof(path), "/tmp/toaster-test-rm-%d.toml", getpid());

  // Create a file
  FILE *fp = fopen(path, "w");
  ASSERT(fp != NULL);
  fprintf(fp, "# test\n");
  fclose(fp);

  struct stat st;
  ASSERT_EQ_INT(0, stat(path, &st));
  ASSERT_EQ_INT(0, RemoveStateFile(path));
  ASSERT_EQ_INT(-1, stat(path, &st));

  // Removing again should succeed (ENOENT is OK)
  ASSERT_EQ_INT(0, RemoveStateFile(path));
  PASS();
}

TEST(save_is_atomic) {
  char path[PATH_MAX];
  snprintf(path, sizeof(path), "/tmp/toaster-test-atomic-%d.toml", getpid());

  struct ToasterStateFile sf;
  memset(&sf, 0, sizeof(sf));
  sf.state = kFrozen;
  snprintf(sf.binary_path, sizeof(sf.binary_path), "/test.com");

  ASSERT_EQ_INT(0, SaveStateFile(path, &sf));

  // The .tmp file should not exist after a successful save
  char tmp[PATH_MAX + 8];
  snprintf(tmp, sizeof(tmp), "%s.tmp", path);
  struct stat st;
  ASSERT_EQ_INT(-1, stat(tmp, &st));

  unlink(path);
  PASS();
}

// ============================================================
// Full lifecycle: kCold -> kThawed -> kFrozen -> kThawed -> kPersisted
// ============================================================

TEST(full_lifecycle_transitions) {
  enum ToasterState s = kCold;
  enum ToasterState next;

  // cold -> thaw -> thawed
  ASSERT_EQ_INT(0, ToasterTransition(s, kActionThaw, &next));
  s = next;
  ASSERT_EQ_INT(kThawed, s);

  // thawed -> freeze -> frozen
  ASSERT_EQ_INT(0, ToasterTransition(s, kActionFreeze, &next));
  s = next;
  ASSERT_EQ_INT(kFrozen, s);

  // frozen -> thaw -> thawed (resume)
  ASSERT_EQ_INT(0, ToasterTransition(s, kActionThaw, &next));
  s = next;
  ASSERT_EQ_INT(kThawed, s);

  // thawed -> persist -> persisted
  ASSERT_EQ_INT(0, ToasterTransition(s, kActionPersist, &next));
  s = next;
  ASSERT_EQ_INT(kPersisted, s);

  // persisted -> thaw -> thawed (new cycle)
  ASSERT_EQ_INT(0, ToasterTransition(s, kActionThaw, &next));
  s = next;
  ASSERT_EQ_INT(kThawed, s);

  // thawed -> discard -> cold
  ASSERT_EQ_INT(0, ToasterTransition(s, kActionDiscard, &next));
  s = next;
  ASSERT_EQ_INT(kCold, s);

  PASS();
}

// ============================================================
// Main
// ============================================================

int main(int argc, char **argv) {
  (void)argc;
  (void)argv;

  printf("State machine tests:\n");
  run_cold_thaw_gives_thawed();
  run_cold_freeze_invalid();
  run_cold_persist_invalid();
  run_cold_discard_invalid();
  run_thawed_freeze_gives_frozen();
  run_thawed_persist_gives_persisted();
  run_thawed_discard_gives_cold();
  run_thawed_thaw_invalid();
  run_frozen_thaw_gives_thawed();
  run_frozen_persist_gives_persisted();
  run_frozen_discard_gives_cold();
  run_frozen_freeze_invalid();
  run_persisted_thaw_gives_thawed();
  run_persisted_freeze_invalid();
  run_persisted_persist_invalid();
  run_persisted_discard_invalid();

  printf("\nName conversion tests:\n");
  run_state_names();
  run_action_names();
  run_parse_state_names();

  printf("\nState file path tests:\n");
  run_derive_state_file_path();
  run_derive_state_file_path_deterministic();
  run_derive_state_file_path_different_binaries();

  printf("\nState file round-trip tests:\n");
  run_save_load_cold();
  run_save_load_thawed_with_paths();
  run_save_load_persisted_with_history();
  run_load_nonexistent_gives_cold();
  run_remove_state_file();
  run_save_is_atomic();

  printf("\nLifecycle tests:\n");
  run_full_lifecycle_transitions();

  printf("\n%d tests run, %d passed, %d failed\n",
         tests_run, tests_passed, tests_failed);

  return tests_failed ? 1 : 0;
}
