# zcgltf

[![CI](https://github.com/pedronaugusto/zcgltf/actions/workflows/ci.yml/badge.svg)](https://github.com/pedronaugusto/zcgltf/actions/workflows/ci.yml)

Zig bindings for [cgltf](https://github.com/jkuhlmann/cgltf) — glTF 2.0
parsing, validation, accessor reading, and writing.

- Vendored, pinned upstream cgltf (v1.15). No fork, no patches. See
  [UPSTREAM.md](UPSTREAM.md).
- **Complete.** Every function the upstream headers declare is bound — the
  writer included — and completeness is a compile-time property, not a
  promise: the ABI cross-check's reverse sweep fails the build over an
  unbound header function.
- **The header is the ABI.** Upstream's public surface is plain C in two
  headers, so the hand-written Zig externs and the full document-model
  mirror — every struct of it — track them directly, and drift between them
  is a **build failure**, not a memory-corruption bug: every struct field,
  signature, enumerator and union member is cross-checked at comptime, with
  no hand-kept list of what to check (see [The ABI guard](#the-abi-guard)).
- An idiomatic layer over all of it — error unions where upstream returns a
  result code, slices where it returns pointer + count — plus two adapters
  the C defaults cannot offer: cgltf's allocations routed through a
  `std.mem.Allocator`, and its file I/O through `std.Io`, which also fixes
  two real portability holes in the fopen default (see
  [UPSTREAM.md](UPSTREAM.md)).

## Usage

The block below is not written here: it is a region of
[`examples/usage.zig`](examples/usage.zig), which `zig build examples` builds
and RUNS, extracted by `ci/readme_usage.sh` and compared by CI. A snippet in a
README is a claim about how the library is used, and this one is a claim
something executes.

<!-- BEGIN GENERATED ci/readme_usage.sh -->
```zig
const zcgltf = @import("zcgltf");

var options = std.mem.zeroes(zcgltf.Options);
options.memory = zcgltf.memoryOptions(&gpa);

const path = "tests/data/triangle.gltf";
const data = try zcgltf.parseFile(&options, path);
defer zcgltf.free(data);
try zcgltf.loadBuffers(&options, data, path);
try zcgltf.validate(data);

const prim = &data.meshes.?[0].primitives.?[0];
const positions = zcgltf.findAccessor(prim, .position, 0) orelse
    return error.MissingPositions;
const indices = prim.indices orelse return error.MissingIndices;

var corners: [9]f32 = undefined;
const floats = zcgltf.unpackFloats(positions, &corners);
var index_values: [3]u32 = undefined;
const idx = zcgltf.unpackIndices(indices, u32, &index_values);
```
<!-- END GENERATED -->

Add it as a dependency and link the module:

```zig
const zcgltf_dep = b.dependency("zcgltf", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("zcgltf", zcgltf_dep.module("zcgltf"));
```

A C or C++ host takes the library and upstream's own installed headers
instead:

```zig
exe.root_module.linkLibrary(zcgltf_dep.artifact("zcgltf"));  // then #include <cgltf.h>
```

Forward `optimize` as shown. zcgltf does not turn on Zig's C sanitizer for
you (see [Build hygiene](#build-hygiene)), so a mismatched build mode is a
size difference rather than an unresolved `__ubsan_handle_*` symbol — but a
Debug library inside a release executable is still not what you meant.

## Design

### The document model is mirrored whole

cgltf's value is its complete in-memory model of a glTF document — the
accessor/buffer-view/buffer chain, the material extension tree, cameras,
skins, animations. All of it is declared in `src/c/types.zig` as extern
structs under Zig names (`cgltf_buffer_view` is `BufferView`), field for
field, so a Zig host reads parsed documents through real typed pointers with
optionals where upstream documents null. Every enum keeps upstream's values —
the GL-valued sampler constants verbatim — and the one anonymous union in
the API (`Camera.data`) is a named `CameraData`.

The functions follow the same split as upstream's headers: document
lifecycle (`parse`, `parseFile`, `loadBuffers`, `validate`, `free`) returns
error unions built from `cgltf_result`; accessor reading
(`readFloat`, `unpackFloats`, `unpackIndices`, …) takes and returns slices,
deriving counts from `len`; object-to-index lookup is one
comptime-dispatched `indexOf`. The raw externs stay public under `zcgltf.c`
for a caller that wants the C contract verbatim.

### Two adapters where C defaults fall short

`memoryOptions(allocator)` fills cgltf's per-call `MemoryOptions` from a
`std.mem.Allocator`. cgltf frees with `free(ptr)` — no size — while a Zig
allocator requires the size back, so the adapter stores a size header ahead
of each block; see [BINDING.md](BINDING.md). Per-call, not process-global:
two documents can use two allocators.

`fileOptions(io)` replaces the fopen-based default reader with `std.Io`.
That is not a convenience: upstream's default cannot open paths beyond the
ANSI code page on Windows and, compiled by anything but MSVC, mis-sizes
Windows files over 2 GiB ([UPSTREAM.md](UPSTREAM.md) has the file:line for
both), and upstream's own documented escape hatch for that is exactly this
hook.

### The ABI guard

The Zig side hand-writes its declarations rather than running translate-c,
so the wrapper gets exactly the types it wants and the shipped module never
compiles C. Nothing in either compiler checks that those declarations still
agree with `cgltf.h`, and a `cgltf_size` narrowed to `c_int` links cleanly
and corrupts. `src/abi_check.zig` closes that: a comptime `@cImport` of the
vendored headers themselves — in the test module only — compared against
`src/c/*.zig` by reflection. Every struct field is paired **by name** with
its own offset; every scalar's size, alignment, signedness and
int-versus-float; every function's arity and full signature, the
callback fields signature-deep; every enumerator reconstructed by naming
convention and compared by value; the union member by member. A declaration
the check cannot classify is a compile error rather than a silent pass.

The same check sweeps the other direction: a function the headers export
that `src/c/` does not declare — or declares as anything but an extern fn —
fails the build. That sweep is the package's completeness gate; "binds all
of upstream" is enforced, not promised. See [BINDING.md](BINDING.md) for the
naming convention that makes the pairing work.

The guard is the one test here that cannot test itself: a refactor that
quietly makes it vacuous looks exactly like a passing build.
`ci/check-abi-drift.sh` is the answer — deliberate drifts applied one at a
time, each of which must be refused, including the struct-field swap that
leaves every offset unchanged and so defeats any positional comparison, and
two mutations against the coverage gate. It runs as two CI jobs, on the
x86_64-linux-gnu ABI and on MSVC's, because the headers are compared *as
preprocessed and laid out for a target*, so a refusal proved on one ABI is
not proved on the other.

One class of hazard lives below anything a declaration can express: Zig
0.16.0 was measured — by the sibling package
[zmeshopt](https://github.com/pedronaugusto/zmeshopt)'s CI, 2026-09-02 —
miscompiling two CALLER shapes (a float passed after many integer-class
parameters; a small all-float struct returned by value). cgltf's surface contains
**neither shape**, which is why this package ships with no forwarding shim —
and the oracle pins both counts at zero, so a re-vendor that introduces one
reopens the decision loudly instead of inheriting the hazard silently.

### Build hygiene

- Source lists are explicit, never globs — a re-vendor cannot silently change
  what compiles. Here that list is one translation unit: `src/cgltf_impl.c`
  instantiates the implementation-in-header parser and writer exactly once.
- UBSan is **not** blanket-disabled, and it is **not** on by default either.
  `-Dsanitize_c=true` turns it on and zcgltf's own CI runs Debug that way.
  It stays off by default because Zig's C sanitizer emits calls into a
  runtime linked only into a compilation that is itself sanitized: a consumer
  who forgets to forward `optimize` would get an `undefined symbol:
  __ubsan_handle_*` link failure naming nothing they can act on. A library
  does not get to decide that its consumers are running a sanitizer.
- Build options are declared once and mirrored into a Zig `options` module,
  so the wrapper cannot disagree with how the C was compiled.
- No configuration macro of cgltf's changes a type's layout, so there is no
  configuration handshake; see [UPSTREAM.md](UPSTREAM.md).

## Testing

```sh
zig build test
```

runs everything: the ABI cross-check compiles with the suite, the
behavioural tests parse the checked-in asset and pin values (vertex data
read back through accessors, node transforms, error mapping, a GLB write →
reparse round trip), both adapters run against `std.testing.allocator` — so
an unbalanced allocation seam is a leak-check failure — the C smoke test
(`zig build test-c`) proves the installed headers and library stand alone
with no Zig in the picture, and the examples build and RUN.

```sh
zig build --build-file tests/consumer/build.zig run
```

builds zcgltf the way a downstream package does — through `b.dependency`,
which resolves the artifact by scanning the dependency's install step and the
headers by their installed spelling. Neither is exercised by anything in
`src/`, so both can break while the whole suite stays green. The Zig module
and the C artifact are each driven by a real consumer there.

### By the numbers

<!-- BEGIN GENERATED ci/measurements.sh --markdown -->
| | |
|---:|---|
| **0.1.1** | version (one home: `build.zig.zon`) |
| **39** | upstream C entry points (declared in the vendored `cgltf.h` + `cgltf_write.h`) |
| **39** | Zig externs (`pub extern fn` in `src/c/*.zig`) |
| **49** | structs mirrored field-by-field (`src/c/types.zig`) |
| **17** | enums mirrored enumerator-by-enumerator |
| **13** | Zig tests `zig build test` executes |
| **2257** | Zig source lines (`src/`) |
| **19** | deliberate drifts `ci/check-abi-drift.sh` must refuse |
| **22** | steps `ci/run.sh` runs |
| **7** | further targets `ci/run.sh` cross-compiles |
<!-- END GENERATED -->

Not one of those is typed into this file. `ci/measurements.sh` recomputes them
from the tree, `ci/check-docs.sh` regenerates the block and fails the build if
what is committed differs, and the same gate refuses any other hand-written
number in these documents unless `tools/doc_numbers.txt` says why it cannot go
stale. Adding a claim means adding its measurement.

**What the numbers do not say.** A count is a count. Matching extern counts
prove presence, not correctness — the oracle and the behavioural tests hold
that, and `ci/check-coverage.sh` holds the idiomatic layer's reach one extern
at a time. Source lines measure volume, not surface. And the gate itself has
blind spots: a number spelled as a word, a single digit, a number joined to
its neighbour by `-`, `.` or `/` (a date, a byte width), a number inside
`code` — where it is an identifier or a citation rather than a claim — and a
sentence that is wrong without containing a number at all.

### Continuous integration

CI runs the whole suite on **Linux, macOS and Windows**, in every optimize
mode — Debug twice, with the C sanitizer on and off — plus the standalone C
test, the downstream-consumer build, and on Windows the MSVC ABI as well as
the gnu one. It also cross-compiles the further targets listed in
`ci/run.sh`, verifies the vendored files byte-for-byte against the pinned
upstream commit, and runs the ABI drift mutation proof on both ABIs. See
[`.github/workflows/ci.yml`](.github/workflows/ci.yml).

The same matrix runs locally, so a failure is reproducible on your machine
before it is a red mark on a pull request:

```sh
ci/run.sh            # the full matrix
ci/run.sh --quick    # native Debug only, for the inner loop
ci/install-hooks.sh  # run it automatically before every push
```

It reports every failure rather than stopping at the first. The drift proof
runs on this host's ABI; the second arm is opt-in
(`ci/run.sh --drift-target=x86_64-windows-msvc`) because it rebuilds once per
mutation — CI runs it on every push, and a release should run both arms here.

### Platform coverage

| | Suite executed by CI | Compile-checked by CI |
|---|---|---|
| Linux | x86_64 (glibc) | + aarch64, musl |
| macOS | aarch64 | + x86_64 |
| Windows | x86_64, both gnu and MSVC ABI | + aarch64 |

Compiling proves the sources and build graph are portable; only an executed
configuration proves behaviour, which is why the two are separate jobs.

That table describes the matrix, not a promise: **the badge at the top of
this file is the authority on whether those runs have actually happened and
passed.**

## Scope

Everything `cgltf.h` and `cgltf_write.h` declare: parsing glTF and GLB from
memory or file, buffer loading (bin chunks, base64 data URIs, external
files), validation, the full document model with every material extension
upstream models, accessor reading and unpacking (sparse accessors included),
node transforms, object-to-index lookup, string/URI decoding, and writing
documents back out as glTF or GLB.

**Static library only, by upstream design:** cgltf declares no export
macro, so a shared build would export nothing and a `.def` file would be
this repo editing upstream's contract. The limit is upstream's, documented
here rather than papered over.

### Pairing with zmeshopt

cgltf **parses** `EXT_meshopt_compression` but does not decode it — decoding
belongs to meshoptimizer, which is exactly the sibling package
[zmeshopt](https://github.com/pedronaugusto/zmeshopt) binds. The interop
contract between the two:

1. A compressed buffer view has `has_meshopt_compression` set, and
   `meshopt_compression` names the source buffer, region, element count and
   stride — cgltf parses that and stops there.
2. Decode the region with zmeshopt
   (`decodeVertexBuffer`/`decodeIndexBuffer`/`decodeIndexSequence` per its
   `mode`, then the filter per its `filter`).
3. Write the decoded pointer into `view.data`, which `bufferViewData` — and
   through it the whole accessor API — prefers over the underlying buffer,
   so the decoded bytes are read transparently from then on. Ownership
   transfers with the pointer: `free` releases every non-null `view.data`
   through `memory.free_func` (`cgltf.h:1875`), so allocate the decoded
   bytes through the document's own `MemoryOptions` and do not free them
   yourself. `tests/interop/` runs this contract end to end, in CI and in
   `ci/run.sh`, through every `mode` and the exponential filter, against a
   released zmeshopt pinned by URL and hash.

Neither package depends on the other — the pairing is a host-side loop, and
the packages meet only in `tests/interop/`, a package of its own that
depends on both.

Deliberately out of scope: rendering, scene graphs, image decoding, and
Draco (upstream parses its metadata but a Draco decoder is its own
library).

## Contributing

Issues and pull requests are welcome. Things to know before opening one:

- **`libs/cgltf` is vendored verbatim and must not be edited.** Changes
  there are lost at the next re-vendor. If upstream needs fixing, fix it
  upstream; if zcgltf needs to work around upstream, do it in `src/` and
  record it in [UPSTREAM.md](UPSTREAM.md) — `fileOptions` is the standing
  example.
- **Run `ci/run.sh` before pushing** — or `ci/install-hooks.sh` once, and it
  runs itself. It is the same matrix CI runs.
- **Comments state a contract, not a narrative.** `ci/check-comments.sh`
  enforces two things and will fail a pull request over either: block length
  caps, and the register — documentation, not conversation. The cap never
  justifies dropping a fact: units, ownership, sizing rules, error conditions
  and aliasing guarantees come first; if a block cannot hold them, shorten
  the prose around them.
- [BINDING.md](BINDING.md) is the contract for how surface is shaped.

## Licence

MIT, see [LICENSE](LICENSE). Vendored cgltf is MIT, copyright Johannes
Kuhlmann; its inlined jsmn JSON tokenizer is MIT, copyright Serge Zaitsev.
