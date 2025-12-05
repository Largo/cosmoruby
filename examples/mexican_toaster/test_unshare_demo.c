#include "libc/calls/calls.h"
#include "libc/errno.h"
#include "libc/sysv/consts/clone.h"
#include "libc/stdio/stdio.h"
#include "libc/str/str.h"
#include "libc/runtime/runtime.h"

int main(void) {
  printf("=== unshare() Capabilities Demo ===\n\n");

  // Test 1: What happens if we unshare WITHOUT uid mapping?
  printf("Test 1: Creating isolated namespaces (no UID mapping)...\n");
  printf("  Current PID: %d\n", getpid());
  printf("  Current UID: %d\n", getuid());

  int rc = unshare(CLONE_NEWUTS | CLONE_NEWIPC);
  if (rc == -1) {
    printf("  ❌ Failed: %s\n", strerror(errno));
    return 1;
  }
  printf("  ✅ Created UTS + IPC namespaces\n");

  // What can we do now?
  printf("\nTest 2: We're in isolated UTS namespace\n");
  char oldhostname[256];
  gethostname(oldhostname, sizeof(oldhostname));
  printf("  Hostname: %s\n", oldhostname);
  printf("  (Changes here wouldn't affect host, but we need privileges)\n");

  printf("\nTest 3: Can we create a user namespace?\n");
  rc = unshare(CLONE_NEWUSER);
  if (rc == -1) {
    printf("  ❌ Failed: %s\n", strerror(errno));
  } else {
    printf("  ✅ User namespace created!\n");
    printf("  Current UID in namespace: %d\n", getuid());
    printf("  (Without UID mapping, we're still our original UID)\n");
  }

  printf("\n=== Summary ===\n");
  printf("unshare() lets us:\n");
  printf("  ✅ Create isolated namespaces\n");
  printf("  ❌ But without UID mapping, we lack privileges for mounts\n");
  printf("  💡 For Mexican Toaster: Use userland overlay instead!\n");

  return 0;
}
