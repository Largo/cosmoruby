#!/bin/bash
# Test shell redirection operators

echo "🧪 Test: Shell Redirection"
echo "=========================================="

o//third_party/mexican_toaster/caboose.com toast <<'EOF'
# Create /tmp first
mkdir /tmp

# Test 1: Stdout redirection
echo "Test 1: Stdout redirection"
echo "Hello stdout" > /tmp/stdout.txt
cat /tmp/stdout.txt

# Test 2: Stdout append
echo ""
echo "Test 2: Stdout append"
echo "Line 1" > /tmp/append.txt
echo "Line 2" >> /tmp/append.txt
echo "Line 3" >> /tmp/append.txt
cat /tmp/append.txt

# Test 3: Stderr redirection
echo ""
echo "Test 3: Stderr redirection (error should be captured)"
mkdir /tmp 2> /tmp/stderr.txt
echo "Stderr content (should show 'File exists'):"
cat /tmp/stderr.txt

# Test 4: Input redirection
echo ""
echo "Test 4: Input redirection"
echo "line1" > /tmp/input.txt
echo "line2" >> /tmp/input.txt
cat < /tmp/input.txt

# Test 5: Pipe to cat
echo ""
echo "Test 5: Pipe to cat"
echo "piped content" | cat

exit
EOF
