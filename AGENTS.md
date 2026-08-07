# pi Build Contract

This repository produces two standalone ARM64 musl variants of pi:

- `pi-bun`, built by `Dockerfile.bun` with a static Bun musl compiler;
- `pi-deno`, built by `Dockerfile.deno` with a static QuickJS Deno compiler and
  matching `denort`.

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
- `make deno-test` runs the embedded-assets/cache smoke for staged pi-deno.
- `deno desktop` validation is out of scope.

The Deno Docker build bundles the Deno-specific coding-agent entrypoint with
esbuild, prepares a CommonJS bundle for QuickJS Deno compilation, and verifies
that the resulting ELF has no interpreter or dynamic dependencies. Both
builders run natively as `linux/arm64` Docker containers; do not substitute a
glibc binary or a cross-libc compatibility layer.

## Release workflows

Both workflows are manual-only, use Docker on `ubuntu-24.04-arm`, and use no
third-party GitHub Actions:

- `.github/workflows/build-pi-deno.yml` downloads the Deno prerelease selected
  by the full `deno_sha` input, builds pi-deno, and publishes
  `pi-<pi-sha>-deno-<deno-sha>-linux-arm64-musl-static.zip`.
- `.github/workflows/build-pi-bun.yml` downloads the Bun prerelease selected
  by the full `bun_sha` input, builds pi-bun, and publishes
  `pi-<pi-sha>-bun-<bun-sha>-linux-arm64-musl-static.zip`.

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
- Keep workflow builds action-free and use shell, Docker, and `gh` directly.
- Do not add dependencies without review, run pre-commit hooks, or push
  unrelated work.
