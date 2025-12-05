#!/bin/bash
# Test quiet vs verbose modes

echo "🧪 Test 1: Quiet mode (default) - should have minimal output"
echo "=========================================================="
echo -e "pwd\nexit" | o//third_party/mexican_toaster/caboose.com toast

echo ""
echo ""
echo "🧪 Test 2: Verbose mode - should show all setup messages"
echo "=========================================================="
TOASTER_VERBOSE=1 o//third_party/mexican_toaster/caboose.com toast <<'EOF'
pwd
exit
EOF

echo ""
echo ""
echo "🧪 Test 3: Testing 'yes' and 'true' variants"
echo "=========================================================="
echo "Testing TOASTER_VERBOSE=yes:"
echo -e "pwd\nexit" | TOASTER_VERBOSE=yes o//third_party/mexican_toaster/caboose.com toast

echo ""
echo "Testing TOASTER_VERBOSE=true:"
echo -e "pwd\nexit" | TOASTER_VERBOSE=true o//third_party/mexican_toaster/caboose.com toast
