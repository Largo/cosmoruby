#!/bin/bash
# Test external APE binaries execution

echo "🧪 Test: External APE Binaries"
echo "=========================================="

o//third_party/mexican_toaster/caboose.com toast <<'EOF'
# Test 0: Create /tmp
mkdir /tmp

# Test 1: lsdir command
echo "Test 1: lsdir"
lsdir

# Test 2: ls command (symlink to lsdir)
echo ""
echo "Test 2: ls (should work via symlink)"
ls

# Test 3: dir command (symlink to lsdir)
echo ""
echo "Test 3: dir (should work via symlink)"
dir

# Test 4: Multiple invocations (test that shell doesn't exit)
echo ""
echo "Test 4: Multiple external commands in sequence"
ls > /tmp/ls_output.txt
echo "First ls done"
dir > /tmp/dir_output.txt
echo "First dir done"
lsdir > /tmp/lsdir_output.txt
echo "First lsdir done"
echo "All commands completed successfully!"

# Test 5: External command in subshell
echo ""
echo "Test 5: Command in subshell"
OUTPUT=$(ls)
echo "Captured output from ls:"
echo "$OUTPUT"

exit
EOF
