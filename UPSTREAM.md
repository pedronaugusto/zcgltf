# Vendored upstream

`libs/cgltf` is a pinned copy of upstream **cgltf**, unmodified.

| | |
|---|---|
| Source | <https://github.com/jkuhlmann/cgltf> |
| Version | 1.15 (`cgltf.h:4`) |
| Tag | `v1.15` |
| Commit | `360db1a95480fe102ae9c69b27c5d101167ff5ba` |
| Commit date | 2025-02-09 |
| License | MIT (`libs/cgltf/LICENSE`) |

## What was taken, and what was left behind

Taken: `cgltf.h`, `cgltf_write.h` and `LICENSE`, **verbatim** — upstream is
an implementation-in-header library, so those two files ARE the library.
The jsmn JSON tokenizer is inlined inside `cgltf.h` by upstream itself, with
its MIT notice carried in the header.

| Left out | Reason |
|---|---|
| `test/` | Upstream's test harness and its fetched sample-model corpora. |
| `fuzz/` | The libFuzzer driver and seed files. |
| `README.md` and repo glue | Documentation of the upstream repo, not part of the library. |

No file is vendored partially. `ci/verify-vendor.sh` diffs each vendored
file against upstream with **no exclusion list at all** — "unmodified" means
byte-identical, rather than identical-modulo-a-list that could itself fall
out of date.

What compiles is decided explicitly in `build.zig`: one translation unit,
`src/cgltf_impl.c`, which defines `CGLTF_IMPLEMENTATION` +
`CGLTF_WRITE_IMPLEMENTATION` and includes `cgltf_write.h` (which includes
`cgltf.h` itself). Exactly once, so the implementation exists exactly once.

## The header is the C ABI

cgltf's entire public surface is plain C declared in two headers. There is
no binding shim in this repository: the hand-written externs and structs in
`src/c/*.zig` mirror the headers directly, and `src/abi_check.zig`
`@cImport`s them (in the test module only) to prove the mirror, field by
field and function by function.

No configuration macro changes a type's layout. `CGLTF_MALLOC`/`CGLTF_FREE`
and friends (`cgltf.h:932`) swap implementation internals at compile time
and are left at their defaults; the runtime `MemoryOptions`/`FileOptions`
hooks are the supported customization points and are what the Zig adapters
use. So there is no config-id handshake here, because there is no
configuration a caller and the library could disagree about.

## Known upstream behaviour

Recorded so a future re-vendor can check whether any of it has changed, and
so the choices made here are not mistaken for omissions.

**The default file reader sizes files with `long`-returning `ftell` outside
MSVC** (`cgltf.h:1060`; the `_ftelli64` branch at `cgltf.h:1058` is
`#ifdef _MSC_VER` only, which a zig-compiled build is not). On Windows,
`long` is 32-bit, so a `.glb` over 2 GiB fails as `io_error`. The reader
also opens with `fopen(path, "rb")` (`cgltf.h:1045`), which on Windows
interprets a narrow path in the ANSI code page (Microsoft Learn, "fopen,
_wfopen", checked 2026-09-03), so a path outside it cannot be opened.
Upstream's escape hatch is the `FileOptions.read` hook, and `src/file.zig`'s
`fileOptions` is that hatch implemented over `std.Io` — 64-bit sizes and
WTF-8→UTF-16 paths on every toolchain. The vendored tree stays pristine; the workaround lives on
this side.

**The writer does not emit `EXT_meshopt_compression`.** `cgltf_write.h`
contains no handling for the extension at all (its extension-flag list,
`cgltf_write.h:72` onward, never mentions it), so a document parsed from a
meshopt-compressed asset writes back without the extension. Parsing support
is one-way; see README's "Pairing with zmeshopt".

**An IDE-only macro block changes what IntelliSense sees, not what
compiles.** Under `__INTELLISENSE__`/`__JETBRAINS_IDE__` (`cgltf.h:919`)
the header defines the implementation macros so IDEs index the whole file.
Real compilations never define those, so the block is inert here — noted
because it looks alarming in a vendored-verbatim tree.

**One function and two fields are deprecated upstream.**
`cgltf_copy_extras_json` is marked deprecated by upstream (comment above
its declaration, `cgltf.h:886`) in favour of reading `cgltf_extras::data`
directly. It is bound — completeness is the point — but the idiomatic layer
does not wrap it, with the reason on record in
`tools/zig_surface_exceptions.txt`. `cgltf_extras`'s `start_offset` and
`end_offset` are deprecated the same way (`cgltf.h:263`, `cgltf.h:264`) in
favour of its `data`; the mirror keeps both, as a mirror must, and its doc
comment says so.

## Re-vendoring procedure

`ci/verify-vendor.sh` fetches the pinned commit and diffs it against
`libs/`, so the claim that this copy is unmodified is checked rather than
asserted. It runs as its own CI job. Run it after any step below.

1. Clone upstream at the new tag; copy `cgltf.h`, `cgltf_write.h` and
   `LICENSE` over `libs/cgltf/`.
2. Update the table at the top of this file, the three constants at the
   top of `ci/verify-vendor.sh`, and the version the prose names in
   `README.md`, `src/zcgltf.zig` and `src/abi_check.zig`. The script refuses
   to run unless the tag and commit both appear in this file, so those two
   cannot drift; the other three are words, and this list is what holds
   them.
3. `zig build test`. `src/abi_check.zig` fails the build if any bound
   function's signature, any struct's layout, any enumerator's value or the
   union's shape has changed — its reverse sweep fails it if the new headers
   declare a function this binding does not — and its two hazard pins fail
   it if upstream introduces a signature shape the sibling package measured
   miscompiled (see README's ABI guard section).
4. Re-read the "known upstream behaviour" section above and check whether
   any of it has changed — the file:line citations make that mechanical. If
   it has, update the binding and the note together.
5. Run the full matrix: `ci/run.sh`, plus
   `ci/run.sh --drift-target=x86_64-windows-msvc` before a release.
