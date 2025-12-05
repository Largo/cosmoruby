#!/bin/bash
# Package caboose with embedded mtsh and content
#
# Usage: cd o && bash ../third_party/mexican_toaster/package_caboose.sh
# This script must be run from the 'o' directory

# Ensure we're in the o directory
cd "$(dirname "$0")/../../o" 2>/dev/null || true

# Exit if current working directory is not o (does not end in /o)
if [[ ! "$PWD" =~ /o$ ]]; then
  echo "Error: Script must be run from the 'o' directory."
  exit 1
fi

# Clean up any existing caboose directory and caboose.zip file
rm -rf caboose
rm -f caboose.zip

mkdir -p caboose/bin
mkdir -p caboose/usr/bin

# Copy APE loader for binfmt_misc support inside chroot
cp ../.cosmocc/3.9.2/bin/ape-x86_64.elf caboose/usr/bin/ape
chmod +x caboose/usr/bin/ape

# Copy mtsh into the ZIP at /zip/bin/mtsh
cp third_party/mexican_toaster/mtsh.com caboose/bin/mtsh
chmod +x caboose/bin/mtsh

# Copy lsdir and create ls/dir symlinks
cp third_party/mexican_toaster/lsdir.com caboose/bin/lsdir
chmod +x caboose/bin/lsdir
ln -sf lsdir caboose/bin/ls
ln -sf lsdir caboose/bin/dir

# Create a sample application structure
mkdir -p caboose/app
cat > caboose/app/hello.txt <<'EOF'
🍞 Hello from inside the Mexican Toaster!

You are now inside the embedded ZIP filesystem.
This is where your application files live.

Try these commands:
  ls           - List files
  pwd          - Show current directory
  cat app/hello.txt - Read this file again
  help         - Show mtsh built-in commands
  exit or ^D   - Leave the toaster
EOF

# Create a README
cat > caboose/README.txt <<'EOF'
🍞 Mexican Toaster - Caboose

This is a proof-of-concept for "getting toasted" - entering an interactive
shell inside an Actually Portable Executable's embedded ZIP filesystem.

All files you see here are embedded inside the caboose.com binary!

The shell you're using (mtsh - Mexican Toaster Shell) is also embedded
in this ZIP at /zip/bin/mtsh

This demonstrates that a single APE binary can contain:
- The application code
- An interactive shell
- Application files and data
- All dependencies

Perfect for portable, self-contained development environments!
EOF

# Create a .cosmo marker file (convention)
touch caboose/.cosmo

cd caboose

# Create the ZIP file
zip -q -r -dd ../caboose.zip *
echo "📦 ZIP creation complete"

cd ..

# Prepare the caboose binary for packaging
cp third_party/mexican_toaster/caboose third_party/mexican_toaster/caboose.com

# Use zipcopy to embed the ZIP into the caboose binary
../.cosmocc/current/bin/zipcopy caboose.zip third_party/mexican_toaster/caboose.com

echo "🍞 caboose.com is ready! Try: o//third_party/mexican_toaster/caboose.com toast"
