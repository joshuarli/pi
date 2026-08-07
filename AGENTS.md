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

- `make deno-linux-arm64-musl DENO_BIN=/path/to/deno DENO_RT_BIN=/path/to/denort`
  builds pi-deno with a matching static QuickJS Deno compiler/runtime pair.
- `make deno-macos-aarch64` builds pi-deno natively on macOS 26+ arm64 using
  the sibling `deno-musl-static` checkout's optimized `release-quickjs`
  compiler/runtime pair by default.
- `make deno-test` runs the embedded-assets/cache smoke for staged pi-deno.
- `deno desktop` validation is out of scope.

The Deno Docker build bundles the Deno-specific coding-agent entrypoint with
esbuild, prepares a CommonJS bundle for QuickJS Deno compilation, and verifies
that the resulting ELF has no interpreter or dynamic dependencies. Linux
builders run natively as `linux/arm64` Docker containers; do not substitute a
glibc binary or a cross-libc compatibility layer. The macOS target uses the
native system libraries instead.

## Release workflows

The single `.github/workflows/build-pi.yml` workflow is manual-only and uses
first-party artifact actions plus shell, Docker, and `gh`. It downloads the
Deno prerelease selected by the full `deno_sha` input, builds Linux in Docker
on `ubuntu-24.04-arm` and macOS natively on `macos-26`, then publishes one
prerelease containing all active pi archives. Bun inputs and commented matrix
entries remain documented there for later re-enablement, but Bun builds are
currently disabled while its LLVM issue is investigated.

The old `.github/workflows/build.yml` is intentionally absent. Deno's own
workflow publishes these compiler/runtime archives:

```text
deno-quickjs-aarch64-unknown-linux-musl.zip
denort-quickjs-aarch64-unknown-linux-musl.zip
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
