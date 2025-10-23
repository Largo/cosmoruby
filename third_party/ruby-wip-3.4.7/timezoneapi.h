#ifndef RUBY_COSMOPOLITAN_TIMEZONEAPI_H_
#define RUBY_COSMOPOLITAN_TIMEZONEAPI_H_

/*
 * Cosmopolitan compatibility wrapper for Windows timezoneapi.h
 *
 * This header maps Windows timezone API types to their Cosmopolitan
 * equivalents, allowing Ruby code to work with Windows timezone
 * functionality in a portable way across all platforms.
 */

#include "libc/nt/struct/dynamictimezoneinformation.h"
#include "libc/nt/struct/timezoneinformation.h"

/* Map Windows API types to Cosmopolitan equivalents */
#define DYNAMIC_TIME_ZONE_INFORMATION struct NtDynamicTimeZoneInformation
#define TIME_ZONE_INFORMATION struct NtTimeZoneInformation

#endif /* RUBY_COSMOPOLITAN_TIMEZONEAPI_H_ */
