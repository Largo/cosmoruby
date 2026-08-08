#!/bin/bash
# Handy functions and aliases for Cosmopolitan/CosmoRuby development
# Source this file: source handy_functions_and_aliases

################################################################################
# Ruby Build Helpers
################################################################################

# Clean build artifacts without triggering dependency generation
clean_ruby() {
    echo "Cleaning Ruby build artifacts (using mkdeps_stub)..."
    make MKDEPS=build/bootstrap/mkdeps_stub.sh clean
}

# Build Ruby binary
build_ruby() {
    local mode="${1:-}"
    if [[ -n "$mode" ]]; then
        echo "Building Ruby (MODE=$mode)..."
        make -j1 MODE="$mode" o/"$mode"/third_party/ruby/ruby
    else
        echo "Building Ruby (default mode)..."
        make -j1 o//third_party/ruby/ruby
    fi
}

# Build IRB
build_irb() {
    local mode="${1:-}"
    if [[ -n "$mode" ]]; then
        echo "Building IRB (MODE=$mode)..."
        make -j1 MODE="$mode" o/"$mode"/third_party/ruby/irb
    else
        echo "Building IRB (default mode)..."
        make -j1 o//third_party/ruby/irb
    fi
}

# Build automate_mkdeps
build_automate_mkdeps() {
    local mode="${1:-}"
    if [[ -n "$mode" ]]; then
        echo "Building automate_mkdeps (MODE=$mode)..."
        make MKDEPS=build/bootstrap/mkdeps_stub.sh -j1 MODE="$mode" o/"$mode"/third_party/build/mtdeps/automate_mkdeps
    else
        echo "Building automate_mkdeps (default mode)..."
        make MKDEPS=build/bootstrap/mkdeps_stub.sh -j1 o//third_party/build/mtdeps/automate_mkdeps
    fi
}

# Run automate_mkdeps to fix dependency errors
fix_ruby_deps() {
    echo "Running automate_mkdeps for Ruby..."
    o//third_party/build/mtdeps/automate_mkdeps --module=ruby
}

# Truncate Ruby dependency blocks (start fresh)
truncate_ruby_deps() {
    echo "Truncating Ruby dependency blocks..."
    o//third_party/build/mtdeps/automate_mkdeps --module=ruby --truncate
}

# Show Ruby dependency info
ruby_deps_info() {
    o//third_party/build/mtdeps/automate_mkdeps --module=ruby --info
}

# Show Ruby dependency counts
ruby_deps_count() {
    o//third_party/build/mtdeps/automate_mkdeps --module=ruby --count
}

# Package Ruby with embedded stdlib
package_ruby() {
    echo "Packaging Ruby with embedded stdlib..."
    if [[ ! -f o//third_party/ruby/ruby ]]; then
        echo "Error: Ruby binary not found. Build it first with: build_ruby"
        return 1
    fi
    (cd third_party/ruby && bash package_ruby.sh)
    echo "Done! Ruby packaged in releases/"
}

# Run Ruby with RUBYLIB set correctly
run_ruby() {
    RUBYLIB="$PWD/third_party/ruby-wip-4.0.6/lib" o//third_party/ruby/ruby "$@"
}

# Run IRB with RUBYLIB set correctly
run_irb() {
    RUBYLIB="$PWD/third_party/ruby-wip-4.0.6/lib" o//third_party/ruby/irb "$@"
}

# Full Ruby build workflow
build_ruby_full() {
    echo "=== Full Ruby Build Workflow ==="
    echo "1. Building automate_mkdeps..."
    build_automate_mkdeps || return 1
    echo
    echo "2. Building Ruby binary..."
    build_ruby || return 1
    echo
    echo "3. Building IRB..."
    build_irb || return 1
    echo
    echo "=== Build Complete ==="
    echo "Run with: run_ruby or run_irb"
}

# Check Ruby version requirement
check_ruby_version() {
    local required_version="4.0.0"
    local current_version=$(ruby --disable-gems -e 'puts RUBY_VERSION' 2>/dev/null)

    if [[ -z "$current_version" ]]; then
        echo "Ruby not found in PATH"
        echo "Install Ruby 4.0.0 with: rbenv install 4.0.0"
        return 1
    fi

    if [[ "$current_version" != "$required_version" ]]; then
        echo "Ruby version mismatch"
        echo "   Current: $current_version"
        echo "   Required: $required_version"
        echo "   Fix with: rbenv local 4.0.0"
        return 1
    fi

    echo "Ruby $current_version (correct version)"
    return 0
}

################################################################################
# General Build Helpers
################################################################################

# Clean everything with mkdeps_stub
clean_all() {
    echo "Cleaning all build artifacts (using mkdeps_stub)..."
    make MKDEPS=build/bootstrap/mkdeps_stub.sh clean
}

# Build mtdeps
build_mtdeps() {
    echo "Building mtdeps..."
    make -j1 MKDEPS=build/bootstrap/mkdeps_stub.sh o//third_party/build/mtdeps/mtdeps
}

# Build mtsh
build_mtsh() {
    echo "Building mtsh..."
    make -j1 MKDEPS=build/bootstrap/mkdeps_stub.sh o//third_party/mexican_toaster/mtsh.com
}

function_names() {
    set | grep -E '^[^ ]+ \(\)' | awk '{print $1}'
}

################################################################################
# Help
################################################################################

handy_help() {
    cat <<'EOF'
Handy Functions and Aliases
===========================

Ruby Build:
  build_ruby [mode]           - Build Ruby binary (default or dbg/opt/rel)
  build_irb [mode]            - Build IRB
  build_ruby_full             - Full build workflow (automate_mkdeps + ruby + irb)
  package_ruby                - Package Ruby with embedded stdlib

Ruby Execution:
  run_ruby [args]             - Run Ruby with RUBYLIB set
  run_irb [args]              - Run IRB with RUBYLIB set

Ruby Dependencies:
  build_automate_mkdeps [mode] - Build the automate_mkdeps tool
  fix_ruby_deps               - Fix dependency errors automatically
  truncate_ruby_deps          - Truncate dependency blocks (start fresh)
  ruby_deps_info              - Show dependency information
  ruby_deps_count             - Show dependency counts

Cleaning:
  clean_ruby                  - Clean Ruby (using mkdeps_stub)
  clean_all                   - Clean everything (using mkdeps_stub)

Mexican Toaster:
  build_mtdeps                - Build mtdeps
  build_mtsh                  - Build mtsh

Utilities:
  check_ruby_version          - Verify Ruby 4.0.0 is active
  function_names              - List defined helper functions
  handy_help                  - Show this help

Examples:
  build_ruby                  # Build in default mode
  build_ruby dbg              # Build in debug mode
  fix_ruby_deps               # Fix missing dependencies
  run_ruby -e 'puts "Hello"'  # Run Ruby script
EOF
}

################################################################################
# Initialisation
################################################################################

echo "Build helpers loaded! Type 'handy_help' for available commands."

# Optional: Check Ruby version on load
# Uncomment to enable automatic version check when sourcing:
# check_ruby_version
