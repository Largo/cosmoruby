#!/bin/bash
# Test overlay filesystem behavior (ephemeral changes)

echo "🧪 Test: Overlay Persistence (Ephemeral)"
echo "=========================================="

echo "Part 1: Create files in toaster"
o//third_party/mexican_toaster/caboose.com toast <<'EOF'
mkdir /tmp
echo "Creating test files..."
echo "Ephemeral data 1" > /tmp/ephemeral1.txt
echo "Ephemeral data 2" > /ephemeral_root.txt
mkdir -p /tmp/test_dir
echo "data" > /tmp/test_dir/file.txt
ls /tmp
ls /ephemeral_root.txt
exit
EOF

echo ""
echo "Part 2: Start new toaster - files should NOT persist"
o//third_party/mexican_toaster/caboose.com toast <<'EOF'
echo "Checking if files from previous session exist..."

test -f /tmp/ephemeral1.txt && echo "❌ FAIL: /tmp/ephemeral1.txt persisted" || echo "✅ PASS: /tmp/ephemeral1.txt does not exist"

test -f /ephemeral_root.txt && echo "❌ FAIL: /ephemeral_root.txt persisted" || echo "✅ PASS: /ephemeral_root.txt does not exist"

test -d /tmp/test_dir && echo "❌ FAIL: /tmp/test_dir persisted" || echo "✅ PASS: /tmp/test_dir does not exist"

echo ""
echo "But original ZIP contents should still exist:"
test -f /README.txt && echo "✅ README.txt from ZIP still exists" || echo "❌ README.txt missing"

exit
EOF
