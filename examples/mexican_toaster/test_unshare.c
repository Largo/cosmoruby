#include "libc/calls/calls.h"
#include "libc/errno.h"
#include "libc/sysv/consts/clone.h"
#include "libc/stdio/stdio.h"
#include "libc/str/str.h"

int main(void) {
  printf("Testing unshare() syscall\n");
  printf("=========================\n\n");

  // Test 1: No-op
  printf("Test 1: unshare(0)...\n");
  int rc = unshare(0);
  printf("  Result: %d\n", rc);

  // Test 2: Create user namespace
  printf("\nTest 2: unshare(CLONE_NEWUSER)...\n");
  rc = unshare(CLONE_NEWUSER);
  printf("  Result: %d\n", rc);
  if (rc == -1) {
    printf("  Error: %s\n", strerror(errno));
  } else {
    printf("  Success!\n");
  }

  printf("\nDone!\n");
  return 0;
}
