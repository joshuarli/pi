# Bun 1.4.0 canary experiment

Date: 2026-08-02

## Result

The Bun 1.4.0 canary cannot be used with the current `Dockerfile.bun` as a
musl build. The canary is a dynamically linked glibc Linux aarch64 binary, and
Alpine 3.24's `gcompat` cannot load it:

```text
Error relocating /usr/local/bin/bun: __pthread_key_create: symbol not found
```

The Dockerfile was temporarily changed to copy the canary directly:

```dockerfile
COPY scripts/bun-canary-test/bun /usr/local/bin/bun
```

The direct Docker build was run with `EXPECTED_LINKAGE=glibc` because the
canary is not musl-compatible. It failed at the first `bun build --compile`
step, before either pi binary was produced. The existing
`bun-linux-arm64-musl` Makefile targets still request `EXPECTED_LINKAGE=musl`
and are therefore not valid for this canary.

## Glibc comparison

The canary runs successfully in a Debian glibc container and reports `1.4.0`.
Using the same source (`7805b9409`) and already-built pi entrypoint, both Bun
versions produced runnable binaries:

| Build | Bun 1.3.14 | Bun 1.4.0 canary | Difference |
| --- | ---: | ---: | ---: |
| Bun executable | 91,801,560 B | 74,498,272 B | 17,303,288 B smaller |
| Full `pi-bun` | 112,437,392 B | 95,071,264 B | 17,366,128 B smaller |
| Headless `pi-headless` | 112,044,176 B | 94,678,048 B | 17,366,128 B smaller |

The generated canary binaries passed `pi --version`:

```text
pi 0.83.0 (7805b9409) bun 1.4.0
```

These size results are glibc-container comparisons, not valid musl artifact
results. The canary is promising for size, but it needs a compatible glibc
builder image or a separate musl canary before it can replace the Bun binary
in the Alpine-based musl image.
