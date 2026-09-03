#!/usr/bin/env bash
#
# zcgltf — the Zig surface covers the C surface, in both directions.
#
# Whether src/c/ binds everything the headers export is not this script's
# question: src/abi_check.zig's reverse sweep refuses the build over it. What
# nothing else checks is the layer above — an extern with no idiomatic caller
# is unreachable for a Zig host that stays out of `c`, and an exception that
# outlives its reason is a rule about code that no longer exists.
#
#   ci/check-coverage.sh

set -uo pipefail
cd "$(dirname "$0")/.."

if [ -t 1 ]; then RED=$'\033[31m'; GREEN=$'\033[32m'; BOLD=$'\033[1m'; OFF=$'\033[0m'
else RED=; GREEN=; BOLD=; OFF=; fi

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
fails=0
fail() { printf '%s%s%s\n' "$RED" "$1" "$OFF" >&2; fails=$((fails + 1)); }

#-----------------------------------------------------------------------------
# The Zig surface: every extern reachable from the idiomatic layer.
#-----------------------------------------------------------------------------
grep -h 'pub extern fn cgltf_' src/c/*.zig |
  grep -oE 'cgltf_[A-Za-z0-9_]+' | sort -u > "$work/entrypoints"

# Comments are stripped first: a doc comment NAMING an entry point must not
# count as calling it. src/c/ and c.zig are declarations, abi_check.zig is
# the oracle, and neither is use.
find src -name '*.zig' ! -path 'src/c/*' ! -name 'c.zig' ! -name 'abi_check.zig' \
     -print0 |
  xargs -0 sed -E 's://.*::' |
  grep -oE 'cgltf_[A-Za-z0-9_]+' | sort -u > "$work/wrapped"

awk -F'\t' '/^#/ || !NF { next }
  NF != 2 { printf "  %s: not NAME<TAB>reason\n", $1 > "/dev/stderr"; next }
  length($2) < 10 { printf "  %s: no reason given\n", $1 > "/dev/stderr"; next }
  { print $1 }' tools/zig_surface_exceptions.txt 2>"$work/exc_shape" | sort -u > "$work/excused"
if [ -s "$work/exc_shape" ]; then
  cat "$work/exc_shape" >&2
  fail "$(grep -c . "$work/exc_shape") malformed exception line(s)"
fi

comm -23 "$work/entrypoints" "$work/wrapped" > "$work/unwrapped"
comm -23 "$work/unwrapped" "$work/excused" > "$work/stranded"
if [ -s "$work/stranded" ]; then
  sed 's/^/  /' "$work/stranded" >&2
  fail "$(grep -c . "$work/stranded") entry point(s) with no idiomatic caller"
fi
comm -13 "$work/unwrapped" "$work/excused" > "$work/excess"
if [ -s "$work/excess" ]; then
  sed 's/^/  /' "$work/excess" >&2
  fail "$(grep -c . "$work/excess") excused entry point(s) the idiomatic layer does call, or that no longer exist"
fi

#-----------------------------------------------------------------------------
# Summary.
#-----------------------------------------------------------------------------
printf '%szcgltf coverage%s\n' "$BOLD" "$OFF"
printf '  %-40s %5d\n' 'entry points declared in src/c/' "$(grep -c . "$work/entrypoints")"
printf '  %-40s %5d\n' '  called by the idiomatic layer' \
  "$(comm -12 "$work/entrypoints" "$work/wrapped" | grep -c .)"
printf '  %-40s %5d\n' '  excused, with a reason' "$(grep -c . "$work/excused")"

if [ "$fails" -ne 0 ]; then
  printf '\n%sFAIL%s  %d problem(s)\n' "$RED" "$OFF" "$fails" >&2
  exit 1
fi
printf '\n%sOK%s  every entry point is reachable in Zig or excused\n' "$GREEN" "$OFF"
