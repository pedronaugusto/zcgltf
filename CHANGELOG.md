# Changelog

Each entry says what the old shape could not express, so a port has the reason
and not only the diff. Versions follow [semantic versioning](https://semver.org);
before 1.0 the minor is the breaking one.

## 0.1.0

First release. Complete bindings for cgltf v1.15 — every function both
headers declare, the writer included — with:

- Hand-written externs and a full document-model mirror (`src/c/*.zig`,
  every struct, enum and the one union) proved against the vendored headers
  by a comptime reflective cross-check (`src/abi_check.zig`) whose reverse
  sweep makes completeness a build property, and whose own vigilance is
  proved by `ci/check-abi-drift.sh` on both the Itanium and MSVC ABIs.
- An idiomatic layer over all of it: `cgltf_result` folded into an error
  set, slice-based accessor reading and unpacking, comptime-dispatched
  object-to-index lookup, and error-union parse/load/validate/write.
- Two adapters upstream's C defaults cannot offer: allocations through a
  `std.mem.Allocator` (size-prefix header, since `free_func` gets no size
  back), and file I/O through `std.Io` — which also closes the default
  reader's two Windows holes, ANSI-only paths and 32-bit `ftell` sizing
  (UPSTREAM.md has the file:line for both).
- No ABI shim, stated rather than assumed: the two caller shapes the
  sibling package zmeshopt measured Zig 0.16.0 miscompiling occur nowhere
  in cgltf's surface, and the oracle pins both hazard counts at 0 so a
  re-vendor that introduces one is refused instead of inherited.
- A consumer package (`tests/consumer/`) driving the module and the C
  artifact the way a downstream `b.dependency` does, examples that are
  built AND run, generated README numbers, and the family CI matrix.
- The pairing with the sibling zmeshopt run end to end (`tests/interop/`,
  `ci/run.sh --interop`): zmeshopt encodes, cgltf parses the
  `EXT_meshopt_compression` metadata, zmeshopt decodes into `view.data`,
  and the accessor API reads the decoded bytes. Running it is what
  measured the ownership rule — `free` releases every non-null
  `view.data` through `memory.free_func` — now stated in README and on
  the `BufferView` mirror.
