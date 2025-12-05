#!/bin/bash
# Basic test: Does piping to toast work at all?

echo "🧪 Test 1: Simple echo pipe"
echo -e "pwd\nexit" | o//third_party/mexican_toaster/caboose.com toast

echo ""
echo "🧪 Test 2: Printf pipe"
printf "ls\nexit\n" | o//third_party/mexican_toaster/caboose.com toast

echo ""
echo "🧪 Test 3: Here-document"
o//third_party/mexican_toaster/caboose.com toast <<'EOF'
pwd
ls
exit
EOF
