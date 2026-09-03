# Adding surface to zcgltf

How a declaration gets bound, written down so every one of them comes out
the same shape. This is the contract a change has to satisfy. Today the
surface is complete — the reverse sweep in `src/abi_check.zig` proves it —
so "adding surface" means a re-vendor brought new declarations, and this is
what they must look like.

## The header is the ABI

cgltf's entire public surface is plain C in two headers, so unlike zozz and
zjolt there is no `ffi/` layer here: nothing to write in C++, no
static_assert axis, no config-id handshake (no macro changes a type's
layout — see [UPSTREAM.md](UPSTREAM.md)). And unlike the sibling zmeshopt
there is no ABI shim either: the two caller shapes Zig 0.16.0 was measured
miscompiling (zmeshopt's hosted CI, 2026-09-02 — a float after more than 6
integer-class parameters, and a small all-float struct returned by value)
do not occur anywhere in cgltf's surface, and `src/abi_check.zig` pins both
hazard counts at 0 so a re-vendor that introduces one is a refused build,
not an inherited hazard. A new declaration is:

1. A mirror in `src/c/types.zig` (types, in header order) or an extern in
   the matching function module (`document`, `access`, `index`, `write`),
   matching the header exactly, with a doc comment that states the
   ownership and lifetime contract.
2. An idiomatic wrapper in the matching `src/*.zig` area file.
3. A flat re-export from `src/zcgltf.zig` — types under their Zig names,
   functions under the prefix-stripped camelCase name.
4. A behavioural test that pins a value, not merely "it ran".

`zig build test` then holds the whole chain: the ABI cross-check, the two
hazard pins, and `ci/check-coverage.sh` fails if the extern has no
idiomatic caller.

## Naming, which is load-bearing

`src/abi_check.zig` pairs the two sides by name with almost no
hand-maintained list, so a name that breaks convention is a build failure,
not a style nit:

| Zig side | C side |
|---|---|
| extern fn `cgltf_parse` | `cgltf_parse` (the C name itself) |
| type `BufferView` | `cgltf_buffer_view` (PascalCase snaked onto the prefix) |
| enum `Result`'s field `data_too_short` | `cgltf_result_data_too_short` |
| typedef `Size` | `cgltf_size` (via the verified `scalar_typedefs` table) |

Each enum carries an `upstream_prefix` decl; the oracle appends the field
name directly — cgltf's enumerators are already snake case — to
reconstruct the C constant and compare its value. The 6 scalar typedefs are
the one place a table exists, because their Zig names cannot be derived
(`Bool32` is `cgltf_bool`); every row of it is itself verified against the
real typedef, and a scalar alias missing from it refuses the build. The
API's one union (`CameraData`) is anonymous upstream, so it pairs
structurally: at every struct field embedding it, member by member.

The idiomatic layer re-exports functions under the prefix-stripped
camelCase name (`parseFile` for `cgltf_parse_file`), so upstream's
documentation stays searchable while the Zig surface reads as Zig.

## The idiomatic layer's rules

- **Results become error unions.** `Result` is folded through one `check`
  function into the `Error` set — every failure enumerator, one error —
  and wrappers return `Error!T`. Values that are answers (a count, an
  index) stay plain values.
- **Slices in, slices out.** `readFloat` takes `[]f32` and passes its
  length; `unpackFloats`/`unpackIndices` return the written prefix;
  `bufferViewData` sizes its slice from the view. No wrapper takes a count
  a slice already knows.
- **Nullability mirrors the document.** Fields upstream documents as
  omittable are optionals in the mirror, so reading a parsed document is
  `orelse`, not a null check remembered or forgotten.
- **The per-type object-to-index helpers are one entry point.**
  `indexOf(data, ptr)` dispatches on the pointee type at comptime; a type
  without an upstream helper is a compile error.
- **Adapters own their contracts.** `memoryOptions` captures a
  `*const std.mem.Allocator` that must outlive every use, including the
  final `free`; `fileOptions` captures a `*const std.Io` the same way.
  Both are per-call state in `Options`, never process-global.

## The allocator adapter, and its one trick

cgltf's `free_func` receives only the pointer, while a `std.mem.Allocator`
needs the allocation's length back. `src/memory.zig` stores a size-prefix
header ahead of each block (16-byte aligned, so any alignment assumption
upstream's structs make still holds). The cost is one header per
allocation; the payoff is correctness with no reliance on any upstream
allocation discipline. The suite runs the adapter against
`std.testing.allocator`, so an unbalanced seam is a leak-check failure.

## The version has one home

`build.zig.zon` `.version` — and nowhere else. zozz mirrors its version
into `ffi/zozz_core.h` because a C consumer needs a version macro; zcgltf
owns no C header (upstream's carries upstream's version), so the zon field
is the single source. `build.zig` reads it into the options module and
`version()` re-exports it; a test checks that what arrives is three dotted
integers, which is all there is to check when nothing else holds a copy.
README's version cell is generated by `ci/measurements.sh` from the same
field.

## Before you call it done

`zig build test` is the bar — it runs the oracle, the behavioural suite,
the C smoke test and the examples. `ci/run.sh` before pushing;
`ci/check-abi-drift.sh` if you touched the oracle or the declarations, and
on both ABIs (`-Dtarget=x86_64-windows-msvc`) for a release. A change that
touches the pairing surface (`BufferView.data`, `MeshoptCompression`, the
buffer loaders) also runs the interop step, which `ci/run.sh` includes;
on its own it is `zig build --build-file tests/interop/build.zig run`.
