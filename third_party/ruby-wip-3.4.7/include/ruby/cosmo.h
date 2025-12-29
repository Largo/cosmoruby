/**********************************************************************

  ruby/cosmo.h - Cosmopolitan-specific Ruby extensions

  Copyright (C) 2025 Cosmopolitan Ruby Port

**********************************************************************/
#ifndef RUBY_COSMO_H
#define RUBY_COSMO_H 1

#include "ruby/ruby.h"
#include "ruby/config.h"

/**
 * cosmo_provide - Mark extension initialization point (NO-OP)
 *
 * This function is intentionally a no-op in ALL build modes because Ruby's require
 * mechanism automatically calls rb_provide_feature() after successfully loading any
 * extension (see load.c:1421 in CosmoRuby, load.c:1354 in pristine Ruby 3.4.7).
 *
 * Historical context:
 * - We initially called rb_provide() here in static bare mode, causing duplicate
 *   $LOADED_FEATURES entries (each extension appeared twice).
 * - Investigation revealed pristine Ruby extensions do NOT call rb_provide() in
 *   their Init functions - they rely on require to handle registration.
 * - Only built-in features initialized during Ruby startup (not via require) call
 *   rb_provide() manually: thread.rb, fiber.so, enumerator.so, complex.so, etc.
 *
 * Why this function still exists:
 * - Provides a single code site for future registration logic if needed
 * - Documents the initialization point for each extension
 * - Maintains consistency across extension Init functions
 * - Makes it easy to add Cosmopolitan-specific initialization later if needed
 *
 * Behavior across build modes:
 * - Static bare mode (EXTSTATIC=1, SLIM_STATIC=0): NO-OP, require handles it
 * - Slim static mode (EXTSTATIC=1, SLIM_STATIC=1): NO-OP, require handles it
 * - Dynamic mode (EXTSTATIC=0): NO-OP, require handles it
 *
 * Usage:
 *   void Init_myext(void) {
 *       // ... extension initialization ...
 *       cosmo_provide("myext" DLEXT);
 *   }
 */
static inline void
cosmo_provide(const char *feature)
{
    // NO-OP: require mechanism handles registration automatically
    // after Init function completes successfully (load.c:1421)
    (void)feature;
}

#endif /* RUBY_COSMO_H */
