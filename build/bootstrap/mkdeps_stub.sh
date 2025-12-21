#!/bin/sh
# Minimal mkdeps stub: accepts -o <file>, writes empty depend file, exits 0.
out=
while [ $# -gt 0 ]; do
	case "$1" in
		-o)
			shift
			[ $# -gt 0 ] && out="$1"
			shift
			;;
		*)
			shift
			;;
	esac
done
if [ -n "$out" ]; then
	: >"$out"
fi
exit 0
