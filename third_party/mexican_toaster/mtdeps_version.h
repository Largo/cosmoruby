#ifndef COSMOPOLITAN_THIRD_PARTY_MEXICAN_TOASTER_MTDEPS_VERSION_H_
#define COSMOPOLITAN_THIRD_PARTY_MEXICAN_TOASTER_MTDEPS_VERSION_H_

/**
 * @fileoverview Mexican Toaster Dependency Analyzer Version Information
 *
 * mtdeps follows Semantic Versioning (semver.org):
 *   MAJOR.MINOR.PATCH
 *
 * MAJOR: Incompatible changes (output format, command-line interface)
 * MINOR: New features, backward-compatible
 * PATCH: Bug fixes, backward-compatible
 */

#define MTDEPS_VERSION_MAJOR 1
#define MTDEPS_VERSION_MINOR 0
#define MTDEPS_VERSION_PATCH 0

#define MTDEPS_VERSION_STRING "1.0.0"

/* Version history:
 * 1.0.0 (e1401d183c) - Initial release
 *   - Based on mkdeps with context-key shim support
 *   - Sanitized shim path generation for complex includes
 *   - Context-aware header resolution
 *   - Enables automation of Ruby's header dependencies
 *   - Shim path format: shims/<sanitized-include>@<sanitized-source>
 */

#endif /* COSMOPOLITAN_THIRD_PARTY_MEXICAN_TOASTER_MTDEPS_VERSION_H_ */
