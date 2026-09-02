#!/usr/bin/env bash
#
# zcgltf — mutation test for the ABI cross-check.
#
# `src/abi_check.zig` compares every declaration in `src/c/` against the real
# vendored `cgltf.h` + `cgltf_write.h` by reflection. It is the one test in
# this repo that cannot test itself: a refactor that quietly makes it vacuous
# — a name filter that matches nothing, a sweep that silently skips a
# category — looks exactly like a passing build. The coverage floors in
# `abi_check.zig` catch the crude version of that. Only mutation catches the
# subtle one.
#
# So this applies one deliberate drift at a time, asserts the build is
# REFUSED with the guard's own message, and reverts. Each mutation is a
# distinct kind of skew, chosen because it is the kind a human review would
# miss. Four of them mutate the VENDORED header — always restored, and a
# leftover would be caught by both the trap sweep here and ci/verify-vendor.sh.
#
# Out of `ci/run.sh --quick` — it rebuilds once per mutation and takes
# minutes. The full `ci/run.sh` does run it, as does CI.
#
# Usage:
#   ci/check-abi-drift.sh                     # the host's default ABI
#   ci/check-abi-drift.sh -Dtarget=<triple>   # that ABI instead
#
# Any argument given is appended to every `zig build test` below. The one
# that matters is `-Dtarget`: the oracle compares src/c/ against @cImport of
# the headers AS PREPROCESSED FOR A TARGET, so a guard proved to fire on one
# ABI is not proved to fire on another — a C enum is `int` under MSVC and
# `unsigned int` under the Itanium ABI, and cgltf's signatures and structs
# carry enums throughout.

set -uo pipefail
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
cd "$(dirname "$0")/.."

pass=0

ZIG=${ZIG:-zig}

# The arm every build in this run is proved on, carried in one place so the
# clean-tree precheck, each mutation and the final summary cannot disagree
# about which ABI the count belongs to.
ARM="$*"
ZIG_TEST="$ZIG build test${ARM:+ $ARM}"
BUILD="$ZIG_TEST"
fail=0
backups=()

restore() {
  local f
  for f in "${backups[@]:-}"; do
    [ -n "$f" ] && [ -f "$f.bak" ] && mv "$f.bak" "$f"
  done
  backups=()
}
# A killed run must not leave a mutated source behind. EXIT covers the paths
# a signal handler does not — an error exit, the shell dying with its parent;
# INT/TERM keep the exit status. SIGKILL cannot be trapped at all, so the
# stale-backup sweep below is the other half.
trap restore EXIT
trap 'restore; exit 130' INT TERM HUP QUIT

# A previous run that was killed outright left its .bak beside the file it
# had mutated, and this run would then measure a mutated tree and save the
# mutation as its own backup. Recover first, and say so.
stale=$(find . -name '*.bak' -not -path './.zig-cache/*' -not -path './.git/*')
if [ -n "$stale" ]; then
  printf 'recovering from a killed run:\n' >&2
  while read -r bak; do
    [ -n "$bak" ] || continue
    printf '  restoring %s\n' "${bak%.bak}" >&2
    mv "$bak" "${bak%.bak}"
  done <<< "$stale"
fi

# try <description> <file> <from> <to>
#
# Asserts the ABI cross-check refuses the mutation, by its own message.
try() {
  expect 'zcgltf ABI drift: [^"]*' "$@"
}

# expect <signal> <description> <file> <from> <to>
#
# `signal` is a grep pattern the output must contain. Requiring a specific
# signal rather than merely a non-zero exit is the whole point: a mutation
# that fails for an unrelated reason — a typo in the replacement, a stale
# anchor landing somewhere odd — would otherwise count as a guard doing its
# job.
expect() {
  local signal="$1" what="$2" file="$3" from="$4" to="$5"

  cp "$file" "$file.bak"
  backups=("$file")

  # A stale anchor and a helper that could not run mean opposite things: the
  # first is a mutation to rewrite, the second says nothing about the guard
  # at all. newline= on both ends keeps the mutated file byte-faithful. The
  # three inputs travel in the ENVIRONMENT, not argv: given `python3 - <path>`
  # the Windows `py` launcher reads the shebang of the PATH argument instead
  # of passing it through.
  local applied
  applied=$(MUT_FILE="$file" MUT_FROM="$from" MUT_TO="$to" python3 <<'PY'
import os, pathlib
p = pathlib.Path(os.environ["MUT_FILE"])
before, after = os.environ["MUT_FROM"], os.environ["MUT_TO"]
with open(p, encoding="utf-8", newline="") as f:
    s = f.read()
if before not in s:
    print("ANCHOR_MISSING")
    raise SystemExit(0)
with open(p, "w", encoding="utf-8", newline="") as f:
    f.write(s.replace(before, after, 1))
print("APPLIED")
PY
  )
  case "$applied" in
    APPLIED) ;;
    ANCHOR_MISSING)
      printf '  ANCHOR STALE  %s\n' "$what"
      fail=$((fail + 1))
      restore
      return
      ;;
    *)
      printf '  TOOL FAILED   %s\n' "$what"
      printf '                the mutation never applied; nothing learned\n'
      fail=$((fail + 1))
      restore
      return
      ;;
  esac

  local out status
  out=$(eval "$BUILD" 2>&1)
  status=$?
  restore

  if [ $status -eq 0 ]; then
    printf '  NOT CAUGHT    %s\n' "$what"
    fail=$((fail + 1))
    return
  fi

  local msg
  msg=$(printf '%s' "$out" | grep -m1 -oE "$signal")
  if [ -z "$msg" ]; then
    printf '  WRONG FAILURE %s\n' "$what"
    printf '                expected to see: %s\n' "$signal"
    printf '%s\n' "$out" | tail -5 | sed 's/^/      | /'
    fail=$((fail + 1))
    return
  fi

  printf '  caught        %s\n' "$what"
  printf '                -> %s\n' "$msg"
  pass=$((pass + 1))
}

# A clean tree first: a mutation is only evidence if the unmutated build
# passes.
if ! eval "$ZIG_TEST" >/dev/null 2>&1; then
  echo "the unmutated build already fails; fix that before reading this script's output"
  exit 1
fi

echo "drift the ABI cross-check must refuse${ARM:+, on $ARM}:"

# Two same-sized fields exchanged. offset and size are both cgltf_size, so
# the offset SEQUENCE of the struct is unchanged and every positional check
# and every offsets-only digest passes this — while each compressed region is
# read starting at its length.
try "same-sized fields swapped" src/c/types.zig \
"$(printf '    buffer: ?*Buffer,\n    offset: Size,\n    size: Size,')" \
"$(printf '    buffer: ?*Buffer,\n    size: Size,\n    offset: Size,')"

# A callback parameter retyped. Allocation hooks cross as bare function
# pointers with no upstream typedef; only a comparison that recurses INTO
# pointed-to function types can see this one.
try "a callback parameter narrowed (Size -> u32)" src/c/types.zig \
'    alloc_func: ?*const fn (user: ?*anyopaque, size: Size) callconv(.c) ?*anyopaque,' \
'    alloc_func: ?*const fn (user: ?*anyopaque, size: u32) callconv(.c) ?*anyopaque,'

try "a parameter dropped from a function" src/c/access.zig \
'pub extern fn cgltf_accessor_read_float(accessor: *const t.Accessor, index: t.Size, out: [*]t.Float, element_size: t.Size) t.Bool32;' \
'pub extern fn cgltf_accessor_read_float(accessor: *const t.Accessor, index: t.Size, out: [*]t.Float) t.Bool32;'

# Same width, same alignment — only signedness distinguishes them, on a
# parameter that indexes TEXCOORD_n and legitimately carries small values.
try "a parameter's signedness flipped (Int -> Uint)" src/c/access.zig \
'index: t.Int) ?*const t.Accessor;' \
'index: t.Uint) ?*const t.Accessor;'

# cgltf's GL-valued enums carry their constants verbatim; an off-by-one here
# is a sampler that silently stops matching real glTF files.
try "an enumerator renumbered" src/c/types.zig \
'    nearest = 9728,' \
'    nearest = 9727,'

try "an enum tag narrowed (c_uint -> u8)" src/c/types.zig \
'pub const Result = enum(c_uint) {' \
'pub const Result = enum(u8) {'

# The API's one union, anonymous upstream. Its members exchanged leaves the
# union's own size unchanged (it is the max either way); only recursing into
# the members by name can see a perspective camera read as an orthographic.
try "the union's members exchanged" src/c/types.zig \
"$(printf '    perspective: CameraPerspective,\n    orthographic: CameraOrthographic,')" \
"$(printf '    perspective: CameraOrthographic,\n    orthographic: CameraPerspective,')"

# The reverse direction: the header declares something src/c/ does not.
try "an extern deleted" src/c/access.zig \
'pub extern fn cgltf_buffer_view_data(view: *const t.BufferView) ?[*]const u8;' \
''

# A Zig helper wearing an exported symbol's name. The forward sweep skips
# non-extern functions and the reverse sweep asks whether the name exists;
# reserving the prefix and demanding EXTERN declarations closes the gap
# between them.
try "an extern replaced by a Zig helper of the same name" src/c/access.zig \
'pub extern fn cgltf_num_components(type: t.Type) t.Size;' \
'pub fn cgltf_num_components(kind: t.Type) t.Size {
    _ = kind;
    return 4;
}'

# An enum whose pairing convention itself drifts: every enumerator of Result
# stops resolving in the header, which is what a renamed upstream prefix
# looks like from here.
try "an enum's upstream_prefix misspelled" src/c/types.zig \
'    pub const upstream_prefix = "cgltf_result_";' \
'    pub const upstream_prefix = "cgltf_results_";'

# The scalar typedef table is hand-kept (the one irregular pairing), so each
# row must be verified: cgltf_bool is a signed int, and an unsigned mirror
# reinterprets every negative sentinel.
try "a scalar typedef's signedness flipped" src/c/types.zig \
'pub const Bool32 = i32;' \
'pub const Bool32 = u32;'

# Header-side mutations: the vendored header is what @cImport reads, so a
# drift IN UPSTREAM at the next re-vendor looks exactly like this.
try "a struct field added in the header only" libs/cgltf/cgltf.h \
"$(printf 'typedef struct cgltf_buffer_view\n{\n\tchar *name;')" \
"$(printf 'typedef struct cgltf_buffer_view\n{\n\tcgltf_int intruder;\n\tchar *name;')"

# Signedness, which size and alignment cannot see: same width, same offset,
# and a stride above 2^63 is nonsense either way — but the check is about the
# class of drift, not this field's plausible values.
try "a field's signedness flipped in the header" libs/cgltf/cgltf.h \
"$(printf '\tcgltf_size stride; /* 0 == automatically determined by accessor */')" \
"$(printf '\tcgltf_ssize stride; /* 0 == automatically determined by accessor */')"

# The other half of scalar identity: a 32-bit integer and a 32-bit float are
# the same width, the same alignment, the same offset — and every bit
# pattern that crosses means something else entirely.
try "a field retyped int -> float in the header" libs/cgltf/cgltf.h \
"$(printf '\tcgltf_bool is_sparse;')" \
"$(printf '\tcgltf_float is_sparse;')"

# A new export appearing upstream. The reverse sweep is the completeness
# gate: a re-vendor that brings a new function must fail until src/c/ binds
# it, or "binds all of it" quietly stops being true.
try "a new function declared in the header only" libs/cgltf/cgltf.h \
'cgltf_size cgltf_num_components(cgltf_type type);' \
"$(printf 'cgltf_size cgltf_num_components(cgltf_type type);\ncgltf_size cgltf_future_thing(cgltf_type type);')"

# The two hazard pins. Both caller shapes were measured miscompiled in the
# sibling package zmeshopt; cgltf has neither, and THAT is why this package
# ships without a forwarding shim. If a pin can drift without a refusal, a
# re-vendor could introduce an affected signature with nothing watching it.
expect 'expected 1, found 0' \
  "the late-float signature pin drifted" src/abi_check.zig \
'try std.testing.expectEqual(@as(usize, 0), ours.late_float_fns);' \
'try std.testing.expectEqual(@as(usize, 1), ours.late_float_fns);'

expect 'expected 1, found 0' \
  "the aggregate-return pin drifted" src/abi_check.zig \
'try std.testing.expectEqual(@as(usize, 0), ours.aggregate_return_fns);' \
'try std.testing.expectEqual(@as(usize, 1), ours.aggregate_return_fns);'

#-----------------------------------------------------------------------------
# The coverage guard.
#
# `ci/check-coverage.sh` answers "is every entry point reachable in Zig, and
# is the exception list honest". If it goes vacuous it reports full coverage
# and nobody notices.
#-----------------------------------------------------------------------------
BUILD='bash ci/check-coverage.sh'

if ! bash ci/check-coverage.sh >/dev/null 2>&1; then
  echo
  echo "  SKIPPED       the coverage mutations"
  echo "                ci/check-coverage.sh already fails, so they would all"
  echo "                report a catch without catching anything."
  fail=$((fail + 1))
else

expect 'entry point\(s\) with no idiomatic caller' \
  "an idiomatic caller removed" src/access.zig \
'    return c.access.cgltf_num_components(kind);' \
'    return 1;'

expect 'the idiomatic layer does call' \
  "an excuse written for an entry point that needs none" tools/zig_surface_exceptions.txt \
'cgltf_copy_extras_json	deprecated upstream; Extras.data carries the same span' \
"$(printf 'cgltf_copy_extras_json\tdeprecated upstream; Extras.data carries the same span\ncgltf_validate\tstructural checks belong to the caller')"

fi

BUILD="$ZIG_TEST"

printf '\ncaught: %d   missed: %d   on %s\n' "$pass" "$fail" "${ARM:-the host default ABI}"

# ci/measurements.sh publishes how many mutations this file holds by counting
# its `try` and `expect` lines. A declaration inside a branch that did not
# run would make that number overstate the proof; this makes it mean "ran".
declared=$(grep -cE '^(try|expect) ' "$SELF")
if [ $fail -eq 0 ] && [ $((pass + fail)) -ne "$declared" ]; then
  printf 'ran %d of %d declared mutations; the published count would overstate it\n' \
    "$((pass + fail))" "$declared"
  exit 1
fi

[ $fail -eq 0 ]
