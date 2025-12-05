#!/bin/bash
# Test mtsh builtin commands

echo "🧪 Test: Builtin Commands"
echo "=========================================="

o//third_party/mexican_toaster/caboose.com toast <<'EOF'
# Create /tmp first
mkdir /tmp

# Test 1: pwd
echo "Test 1: pwd"
pwd

# Test 2: cd and pwd
echo ""
echo "Test 2: cd to /tmp and check pwd"
cd /tmp
pwd

# Test 3: cd back to root
echo ""
echo "Test 3: cd back to /"
cd /
pwd

# Test 4: cd to non-existent directory (should fail gracefully)
echo ""
echo "Test 4: cd to non-existent directory (expect error)"
cd /this/does/not/exist
echo "Still alive after failed cd"

# Test 5: Environment variables
echo ""
echo "Test 5: Environment variables"
env

# Test 6: echo command
echo ""
echo "Test 6: echo command"
echo "Hello World"
echo "Multiple" "arguments"

# Test 7: Command substitution with builtin
echo ""
echo "Test 7: Command substitution"
CURRENT_DIR=$(pwd)
echo "Current directory via substitution: $CURRENT_DIR"

# Test 8: cat command
echo ""
echo "Test 8: cat command"
echo "Test content" > /tmp/cattest.txt
cat /tmp/cattest.txt

exit
EOF
