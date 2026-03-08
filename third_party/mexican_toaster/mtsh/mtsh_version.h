#ifndef COSMOPOLITAN_THIRD_PARTY_MEXICAN_TOASTER_MTSH_VERSION_H_
#define COSMOPOLITAN_THIRD_PARTY_MEXICAN_TOASTER_MTSH_VERSION_H_

/**
 * @fileoverview Mexican Toaster Shell Version Information
 *
 * mtsh follows Semantic Versioning (semver.org):
 *   MAJOR.MINOR.PATCH
 *
 * MAJOR: Incompatible changes (breaking changes to command-line interface or shell syntax)
 * MINOR: New features, backward-compatible (e.g., new builtins, new flags)
 * PATCH: Bug fixes, backward-compatible
 */

#define MTSH_VERSION_MAJOR 0
#define MTSH_VERSION_MINOR 2
#define MTSH_VERSION_PATCH 0

#define MTSH_VERSION_STRING "0.2.0"

/* Version history:
 * 0.1.0 (e1401d183c) - Initial release
 *   - Enhanced command interpreter based on cocmd
 *   - Subshell execution with ( )
 *   - Command substitution with $( ) and backticks
 *   - 'command -v' builtin for PATH lookups
 *   - ':' null command builtin
 *   - Toast mode for containerized environments
 *   - Fixed redirection handling (proper fd management for >, <, >>)
 *   - Raw character-by-character input in interactive mode
 *
 * 0.2.0 - Line editing support
 *   - Integrated linenoise for professional line editing in interactive mode
 *   - Arrow keys (left/right navigation, up/down history)
 *   - Backspace/Delete support
 *   - Home/End keys
 *   - Command history
 *   - Proper escape sequence handling (fixes Alt-key crashes)
 *   - Non-interactive mode unchanged (still uses raw command parsing)
 */

#endif /* COSMOPOLITAN_THIRD_PARTY_MEXICAN_TOASTER_MTSH_VERSION_H_ */
