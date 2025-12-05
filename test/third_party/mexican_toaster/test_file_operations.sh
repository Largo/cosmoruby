#!/bin/bash
# Test file operations in the toaster

echo "🧪 Test: File Operations"
echo "=========================================="

o//third_party/mexican_toaster/caboose.com toast <<'EOF'
# Test 1: Create /tmp directory first
mkdir /tmp

# Test 2: Create a file
echo "Hello from toaster" > /tmp/test.txt
cat /tmp/test.txt

# Test 3: Append to file
echo "Second line" >> /tmp/test.txt
cat /tmp/test.txt

# Test 4: Create directory structure
mkdir -p /tmp/foo/bar/baz
ls /tmp/foo/bar

# Test 5: Touch creates empty file
touch /tmp/empty.txt
ls /tmp/empty.txt

# Test 6: Remove files
rm /tmp/empty.txt
echo "Removed empty.txt"

# Test 7: Remove directory
rmdir /tmp/foo/bar/baz
echo "Removed /tmp/foo/bar/baz"

exit
EOF
