# Exit-status propagation check for a packaged CosmoRuby APE.
#
#   <ruby.com> cosmo_tests/ci_exit7.rb   # must exit 7
#
# The caller checks the status.  Note that PowerShell reports a cosmo APE's
# status shifted left by 8 ($LASTEXITCODE == 1792 for exit 7); the CI accepts
# 7 or 7 << 8 on Windows and reports which one it saw.
puts "EXIT7-BEFORE"
require "json"
$stdout.flush
exit 7
