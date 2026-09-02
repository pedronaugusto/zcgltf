#!/usr/bin/env bash
#
# zcgltf — prove libs/cgltf is really unmodified upstream.
#
# UPSTREAM.md says the vendored tree is a pristine copy of a specific commit.
# On its own that is a claim in a markdown file: nothing stops an edit to
# libs/ from landing while the documentation still says otherwise. This script
# turns the claim into a check by fetching that exact commit and diffing.
#
# It is the reason a git submodule is not needed here. A submodule would have
# git record the upstream commit, which is genuinely useful — but Zig's package
# manager fetches a source archive and never resolves submodules, so consumers
# would receive an empty libs/ and a build that cannot work. This gets the
# guarantee without the breakage.
#
# The diff takes no exclusions: the three vendored files are compared byte for
# byte. What is left out is left out at the repository level (test/, fuzz/,
# the README) and never appears under libs/ at all.
#
# Needs network, so it is a separate CI job rather than part of ci/run.sh.
#
# Usage: ci/verify-vendor.sh

set -euo pipefail
cd "$(dirname "$0")/.."

# Kept in step with UPSTREAM.md by the check below, so the two cannot drift.
UPSTREAM_URL="https://github.com/jkuhlmann/cgltf.git"
UPSTREAM_TAG="v1.15"
UPSTREAM_COMMIT="360db1a95480fe102ae9c69b27c5d101167ff5ba"

# Paths copied verbatim from upstream.
VENDORED=(cgltf.h cgltf_write.h LICENSE)

if [ -t 1 ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; DIM=$'\033[2m'; OFF=$'\033[0m'
else
  RED=; GREEN=; DIM=; OFF=
fi

fail() { printf '%s%s%s\n' "$RED" "$1" "$OFF" >&2; exit 1; }

# The pin must appear in UPSTREAM.md verbatim. If someone bumps one and not the
# other, that is exactly the drift this script exists to catch.
grep -q "$UPSTREAM_COMMIT" UPSTREAM.md ||
  fail "UPSTREAM.md does not mention $UPSTREAM_COMMIT — the pin has drifted."
grep -q "$UPSTREAM_TAG" UPSTREAM.md ||
  fail "UPSTREAM.md does not mention $UPSTREAM_TAG — the pin has drifted."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

printf '%sfetching %s at %s%s\n' "$DIM" "$UPSTREAM_URL" "$UPSTREAM_TAG" "$OFF"
# Line endings off on both sides of the comparison. "Unmodified" means the
# bytes git stores, and a checkout that translates them -- the default on
# Windows -- makes every line of every file differ. `.gitattributes` holds
# the local half of that; this holds the reference half.
git -c core.autocrlf=false -c core.eol=lf \
  clone --quiet --depth 1 --branch "$UPSTREAM_TAG" "$UPSTREAM_URL" \
  "$work/upstream" 2>/dev/null || fail "clone failed"

# A tag can be moved; the commit cannot. Check the SHA, not the label.
actual=$(git -C "$work/upstream" rev-parse HEAD)
[ "$actual" = "$UPSTREAM_COMMIT" ] ||
  fail "tag $UPSTREAM_TAG is $actual, expected $UPSTREAM_COMMIT"
printf '%scommit %s confirmed%s\n' "$DIM" "$UPSTREAM_COMMIT" "$OFF"

status=0
for path in "${VENDORED[@]}"; do
  if [ ! -e "libs/cgltf/$path" ]; then
    printf '  %-24s %sMISSING locally%s\n' "$path" "$RED" "$OFF"
    status=1
    continue
  fi
  if diff "$work/upstream/$path" "libs/cgltf/$path" > "$work/diff" 2>&1; then
    printf '  %-24s %sidentical%s\n' "$path" "$GREEN" "$OFF"
  else
    printf '  %-24s %sDIFFERS%s\n' "$path" "$RED" "$OFF"
    sed 's/^/      /' "$work/diff" | head -30
    status=1
  fi
done

if [ $status -ne 0 ]; then
  printf '\n%slibs/cgltf is not a pristine copy of %s.%s\n' \
    "$RED" "$UPSTREAM_COMMIT" "$OFF" >&2
  printf 'Either revert the local change, or — if the divergence is intended —\n' >&2
  printf 'record it in UPSTREAM.md and teach this script about it.\n' >&2
  exit 1
fi

printf '\n%slibs/cgltf matches upstream %s exactly%s\n' \
  "$GREEN" "$UPSTREAM_COMMIT" "$OFF"
