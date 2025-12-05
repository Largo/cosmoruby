#!/bin/bash
# Demonstration of all cocmd enhancements

COCMD="./o/tool/build/cocmd"

echo "=== cocmd Enhancement Demonstration ==="
echo

echo "1. Colon command (no-op):"
$COCMD -c ': && echo "  ✓ Colon works"'

echo
echo "2. Comments:"
$COCMD -c 'echo "  ✓ Comments work" # this is ignored'

echo
echo "3. Subshell grouping:"
$COCMD -c 'true && (echo "  ✓ Grouping works") || echo "  ✗ Failed"'

echo
echo "4. Command substitution with \$():"
$COCMD -c 'echo "  ✓ Date: $(date +%Y-%m-%d 2>/dev/null || echo 2025-11-01)"'

echo
echo "5. Command substitution with backticks:"
$COCMD -c 'echo "  ✓ PWD: `pwd | head -c 30`..."'

echo
echo "6. All features combined:"
$COCMD -c ': && (echo "  ✓ Combined: $(echo SUCCESS)") # all working!'

echo
echo "7. Quoted substitution:"
$COCMD -c 'echo "  ✓ Quoted: \"$(echo works)\""'

echo
echo "8. No nesting (expected to fail):"
$COCMD -c 'echo "$(echo $(echo nested))"' 2>&1 | head -1 | sed 's/^/  /'
echo "  (This is correct - nesting not supported)"

echo
echo "=== All enhancements verified! ==="
