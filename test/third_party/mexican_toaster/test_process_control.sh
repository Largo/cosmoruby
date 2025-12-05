#!/bin/bash
# Test process control features

echo "🧪 Test: Process Control"
echo "=========================================="

o//third_party/mexican_toaster/caboose.com toast <<'EOF'
# Create /tmp
mkdir /tmp

# Test 1: Sequential commands with ;
echo "Test 1: Sequential commands with semicolon"
pwd ; echo "After pwd" ; echo "Still here"

# Test 2: Command chaining with &&
echo ""
echo "Test 2: Command chaining with &&"
echo "First" && echo "Second" && echo "Third"

# Test 3: || operator (should execute second if first fails)
echo ""
echo "Test 3: || operator"
cd /nonexistent || echo "First command failed, so I ran"

# Test 4: Combining && and ||
echo ""
echo "Test 4: Combining && and ||"
cd /tmp && echo "cd succeeded" || echo "cd failed"
cd /nonexistent && echo "cd succeeded" || echo "cd failed as expected"

# Test 5: Exit status with true/false
echo ""
echo "Test 5: Exit status"
true && echo "true succeeded"
false || echo "false failed as expected"

# Test 6: Command grouping with subshell
echo ""
echo "Test 6: Subshell grouping"
(cd /tmp; pwd; echo "Inside subshell")
pwd
echo "Back in parent shell"

exit
EOF
