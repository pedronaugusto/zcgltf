# Changelog

Each entry says what the old shape could not express, so a port has the reason
and not only the diff. Versions follow [semantic versioning](https://semver.org);
before 1.0 the minor is the breaking one.

## 0.1.1

Documentation and gates only. The library, its ABI and its behaviour are
unchanged from 0.1.0, so an upgrade is a re-pin and nothing else.

- The zmeshopt pairing was described as part of the test suite while
  nothing ran it: `ci/run.sh` hid it behind `--interop`, no CI job existed,
  and it needed a sibling checkout on disk. It is now a default step and a
  job of its own, `tests/interop` pins a released zmeshopt by URL and hash
  so a lone clone can run it, and it covers every
  `EXT_meshopt_compression` mode and the exponential filter rather than
  two of them.
- The C smoke test was compiled with `libs/cgltf` on its include path as
  well as the installed header, so "proves the installed headers" was not
  what it proved. The extra path is gone; `linkLibrary` propagates what
  `installHeader` publishes.
- The version test was said to compare two copies of the version. There is
  no second copy — it checks the shape of the one in `build.zig.zon` — and
  the three places that said "compares" say what it does.
- The MSVC drift arm was justified by an enum underlying-type difference
  the oracle deliberately ignores. It is justified now by what it actually
  proves: the header preprocessed for a second target, laid out by the
  other compiler's rules.
- Smaller: a deprecation citation one line off, the pin's date labelled as
  the commit date, the `fopen` claim sourced, the deprecated `Extras`
  offsets noted, the re-vendor procedure naming every home of the upstream
  version string, the number gate's blind spots written down, a sibling
  vestige dropped from `ci/check-coverage.sh`, and `.gitignore` covering
  the `.bak` the drift script leaves when interrupted.

## 0.1.0

First release. Complete bindings for cgltf v1.15 — every function both
headers declare, the writer included — with:

- Hand-written externs and a full document-model mirror (`src/c/*.zig`,
  every struct, enum and the one union) proved against the vendored headers
  by a comptime reflective cross-check (`src/abi_check.zig`) whose reverse
  sweep makes completeness a build property, and whose own vigilance is
  proved by `ci/check-abi-drift.sh` on both the linux-gnu and MSVC ABIs.
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
  a default step of `ci/run.sh` and its own CI job): zmeshopt encodes,
  cgltf parses the `EXT_meshopt_compression` metadata, zmeshopt decodes
  into `view.data`, and the accessor API reads the decoded bytes, for all
  three modes and the exponential filter. Running it is what
  measured the ownership rule — `free` releases every non-null
  `view.data` through `memory.free_func` — now stated in README and on
  the `BufferView` mirror.
