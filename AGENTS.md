# pi Build Contract

This repository produces standalone ARM64 pi variants:

- `pi-bun`, built by `Dockerfile.bun` with a static Bun musl compiler;
- Linux `pi-deno`, built by `Dockerfile.deno` with a static QuickJS Deno
  compiler and matching `denort`;
- macOS 26+ arm64 `pi-deno`, built natively with a dynamic QuickJS Deno pair.

The root `Makefile` is the canonical local build interface. The historical
`BUN-1.4.0-MUSL.md` and `DENO-MUSL-STATIC.md` notes are intentionally removed;
update this file and the Makefile when the build contract changes.

## Makefile workflows

Workspace preparation and cleanup:

- `make workspace-build` installs dependencies and builds all packages.
- `make build` is an alias for `workspace-build`.
- `make workspace-clean` runs each workspace package's clean script.
- `make clean` runs `workspace-clean` and removes staged standalone binaries.

Bun:

- `make bun` builds current-platform `pi-bun` and runs local smoke tests.
- `make bun-linux-arm64-musl` builds pi-bun in the static Alpine container.
- `make bun-test` runs the local binary smoke tests.
- `make bun-real-test` requires `OPENROUTER_API_KEY` and contacts a real
  provider; do not run it unless explicitly requested.

Deno:

- `make deno-linux-arm64-musl` builds pi-deno with the pinned static QuickJS
  Deno compiler/runtime pair, downloading it into `.artifacts/` when no paths
  are supplied. Override `DENO_BIN` and `DENO_RT_BIN` to use another matching
  pair.
- `make deno-linux-x86_64-musl` (or `make deno-linux-amd64-musl`) builds the
  matching Linux AMD64 artifact through Docker's `linux/amd64` platform.
- `make deno-macos-aarch64` builds pi-deno natively on macOS 26+ arm64 using
  the pinned prebuilt macOS QuickJS compiler/runtime pair by default.
- Deno build metadata derives `RUNTIME_SHA` from the compiler's `deno --version`
  output; the compiler obtains the commit identity from its adjacent matching
  `denort`, rather than copying the Makefile's release pin.
- `make deno-test` runs the embedded-assets/cache smoke for staged pi-deno.
- `deno desktop` validation is out of scope.

The Deno Docker build uses Deno to install dependencies, build the workspace,
hydrate model data, bundle the Deno-specific coding-agent entrypoint with
esbuild, prepare a CommonJS bundle for QuickJS Deno compilation, and verify
that the resulting ELF has no interpreter or dynamic dependencies. Linux
builders run as `linux/arm64` and `linux/amd64` Docker containers (including
QEMU emulation where needed); do not substitute a glibc binary or a cross-libc
compatibility layer. The macOS target uses the native system libraries instead.

## Release workflows

The single `.github/workflows/build-pi.yml` workflow is manual-only and uses
first-party artifact actions plus shell, Docker, and `gh`. It downloads the
Deno prerelease selected by the full `deno_sha` input, builds Linux in Docker
on `ubuntu-24.04-arm` and macOS natively on `macos-26`, then publishes one
prerelease containing all active pi archives. Bun inputs and commented matrix
entries remain documented there for later re-enablement, but Bun builds are
currently disabled while its LLVM issue is investigated.

The old `.github/workflows/build.yml` is intentionally absent. The pinned Deno
prerelease `prerelease-5ea581da3280cd5321c4a2ee6c761466a37d3bc6` publishes these
compiler/runtime archives:

```text
deno-quickjs-aarch64-unknown-linux-musl.zip
denort-quickjs-aarch64-unknown-linux-musl.zip
deno-quickjs-x86_64-unknown-linux-musl.zip
denort-quickjs-x86_64-unknown-linux-musl.zip
deno-quickjs-aarch64-apple-darwin.zip
denort-quickjs-aarch64-apple-darwin.zip
```

## Validation rules

- Preserve static ELF checks: no `INTERP` segment and no `DT_NEEDED` entries.
- Keep embedded assets self-contained; standalone binaries must work without
  sidecar package files.
- Use `npm run check` after source changes. Prefer focused package tests for
  behavior changes; do not run provider/e2e tests without request.
- Avoid third-party workflow actions; use shell, Docker, `gh`, and only the
  first-party artifact actions needed to pass archives between matrix jobs.
- Do not add dependencies without review, run pre-commit hooks, or push
  unrelated work.
