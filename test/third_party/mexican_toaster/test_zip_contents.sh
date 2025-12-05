#!/bin/bash
# Test access to ZIP filesystem contents

echo "🧪 Test: ZIP Filesystem Contents"
echo "=========================================="

o//third_party/mexican_toaster/caboose.com toast <<'EOF'
# Test 1: List root directory (should show copied /zip contents)
echo "Test 1: Root directory contents"
ls /

# Test 2: Check README.txt from ZIP
echo ""
echo "Test 2: README.txt from embedded ZIP"
test -f /README.txt && echo "README.txt exists" || echo "README.txt not found"
cat /README.txt

# Test 3: Check for directories from ZIP
echo ""
echo "Test 3: Check standard directories"
test -d /usr && echo "✅ /usr exists" || echo "❌ /usr not found"
test -d /bin && echo "✅ /bin exists" || echo "❌ /bin not found"
test -d /app && echo "✅ /app exists" || echo "❌ /app not found"

# Test 4: List /bin contents
echo ""
echo "Test 4: Contents of /bin"
ls /bin

# Test 5: List /usr contents
echo ""
echo "Test 5: Contents of /usr"
ls /usr

# Test 6: Verify lsdir exists
echo ""
echo "Test 6: Check for lsdir binary"
test -f /bin/lsdir && echo "✅ /bin/lsdir exists" || echo "❌ /bin/lsdir not found"

# Test 7: Verify APE loader
echo ""
echo "Test 7: APE loader in /usr/bin"
test -f /usr/bin/ape && echo "✅ /usr/bin/ape exists" || echo "❌ /usr/bin/ape not found"

exit
EOF
