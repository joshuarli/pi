# pi-deno linux-arm64: musl / static findings

Goal: a `pi-deno-2.9.4-linux-arm64-musl` standalone binary, the Deno analog of the
Bun musl build (`pi-<sha>-bun-1.3.14-linux-arm64-musl`, see `Dockerfile.bun` and the
`bun-linux-arm64-musl` Makefile target). That build works because Bun ships a musl
flavor of its own tool binary and `bun build --compile` output follows the tool's
libc. Deno does not.

## Findings (verified in linux/arm64 containers, Deno 2.9.4)

- **Deno 2.9.4 ships no musl Linux binaries.** The release (also the latest as of
  this writing) only has `deno-aarch64-unknown-linux-gnu.zip` and
  `deno-x86_64-unknown-linux-gnu.zip`, plus darwin/windows assets. There is no
  `deno compile --target` for musl either; the available targets are the four
  official builds.
- **`deno compile` output is glibc-dynamic, same linkage as the tool.** Compiling
  with the official `aarch64-unknown-linux-gnu` binary downloads a matching
  `denort-aarch64-unknown-linux-gnu.zip` runtime and emits an executable whose
  interpreter is `/lib/ld-linux-aarch64.so.1` with NEEDED
  `libdl.so.2 libgcc_s.so.1 libpthread.so.0 libm.so.6 libc.so.6
  ld-linux-aarch64.so.1`. A pi-deno built this way is not musl and not static.
- **The glibc Deno binary cannot run on Alpine at all**, so the Bun "run the glibc
  tool inside Alpine via `gcompat`" approach does not transfer. Deno aborts with
  `Error relocating ...: __res_init: symbol not found` under both `gcompat` and
  `libc6-compat` (Alpine's glibc compatibility libraries are missing that resolver
  symbol). Consequently a glibc-linked pi-deno would also abort in Alpine
  containers, which is exactly the environment the musl variant exists for.

## The realistic route to a real musl pi-deno

Build Deno from source for the musl target. Alpine already does this:

- https://gitlab.alpinelinux.org/alpine/aports/community/deno
- `APKBUILD` is `pkgver=2.7.4` (outdated vs 2.9.4) and builds natively for the
  musl libc with `cargo fetch --target=...`. It carries a patch set that is
  largely musl/V8/stacker-specific: `musl-malloc_trim.patch`,
  `tests-musl-compat.patch`, `stacker-detect-stack-overflow.patch`,
  `stacker-disable-guess_os_stack_limit.patch`, `v8-build.patch`,
  `v8-compiler.patch`, `v8-no-execinfo.patch`, `v8-use-system-icu.patch`,
  `use-system-libs.patch`, `unbundle-ca-certs.patch`, and
  `cargo.lock.patch`, among others.

Porting that patch set to 2.9.4 is the only path to a genuine
`pi-deno-2.9.4-linux-arm64-musl`. It is a heavy, fragile toolchain build
(clang/llvm, rust musl target, V8), not a Dockerfile tweak on top of an official
binary.

## Status

No container build infrastructure was added for a Deno linux-arm64 binary.
Options if a musl/static pi-deno becomes a hard requirement:

1. Port the Alpine aports Deno patches to 2.9.4 and build from source for
   `aarch64-unknown-linux-musl` (heavy).
2. Ship a glibc `pi-deno-2.9.4-linux-arm64` built in a Debian container; it runs
   on glibc Linux arm64 but not on Alpine.
3. Skip Deno for Alpine environments and keep the host-only `make deno` path.
