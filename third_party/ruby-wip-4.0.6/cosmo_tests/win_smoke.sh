#!/bin/sh
# Copy a packaged ruby.com (+ win_smoke.rb) to a Windows machine over ssh and
# run the smoke script there.
#
#   sh third_party/ruby/cosmo_tests/win_smoke.sh <ruby.com> [tag]
#
# Defaults target a local Vagrant Windows box (127.0.0.1:2222, user "vagrant",
# insecure vagrant key).  Override with environment variables:
#
#   WIN_HOST   default 127.0.0.1
#   WIN_USER   default vagrant
#   WIN_PORT   default 2222
#   WIN_KEY    default ~/.vagrant.d/insecure_private_keys/vagrant.key.rsa
#
# Expected output: the RUBY_DESCRIPTION banner, JSON, Gem.default_dir, a file
# round-trip, ARGV, a digest, "stdlib-ok", "42", and RC=1792.
#
# RC=1792 is 7 << 8 -- Windows reports a cosmopolitan APE's exit status shifted
# left by 8 bits.  That is pre-existing cosmopolitan behaviour (identical for
# Ruby 4.0.0), not a bug in the smoke script.  Divide by 256.
#
# Why this exists: an APE that passes every Linux check can still segfault
# during VM init on Windows (see PORTING-NOTES.md, "Windows verification").
# Linux green is only half the acceptance criteria.
set -eu
RUBY="$1"; TAG="${2:-wintest}"
WIN_HOST="${WIN_HOST:-127.0.0.1}"
WIN_USER="${WIN_USER:-vagrant}"
WIN_PORT="${WIN_PORT:-2222}"
WIN_KEY="${WIN_KEY:-$HOME/.vagrant.d/insecure_private_keys/vagrant.key.rsa}"

SSH="ssh -o StrictHostKeyChecking=no -p $WIN_PORT -i $WIN_KEY $WIN_USER@$WIN_HOST"
SCP="scp -o StrictHostKeyChecking=no -P $WIN_PORT -i $WIN_KEY"
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

$SCP "$RUBY" "$WIN_USER@$WIN_HOST:C:/$TAG.com"
$SCP "$DIR/win_smoke.rb" "$WIN_USER@$WIN_HOST:C:/win_smoke.rb"
# Redirect inside cmd and read the file back: PowerShell mangles interleaved
# native stderr, which is exactly where the [BUG] crash block goes.
$SSH "cmd /c \"cd C:\\ && C:\\$TAG.com C:\\win_smoke.rb argA argB > C:\\$TAG.out 2>&1\"; echo RC=\$LASTEXITCODE; Get-Content C:\\$TAG.out | Out-String -Width 200"
