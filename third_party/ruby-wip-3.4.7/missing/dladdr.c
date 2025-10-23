/* Stub implementation of dladdr for Cosmopolitan */
/* dladdr is used for enhanced backtraces but is not essential */

#include "dladdr.h"

int dladdr(const void *addr, Dl_info *info) {
    /* Return 0 to indicate failure - backtrace will fall back to other methods */
    (void)addr;
    (void)info;
    return 0;
}
