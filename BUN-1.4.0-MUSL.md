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

## Static musl validation

Date: 2026-08-03

The Alpine edge distro LLVM22 build was proven natively on x86-64: it produced
a static Bun binary and passed startup, arithmetic, and live mimalloc
heap-stat/heap-dump checks. The corresponding ARM64 build compiled all sources
and reached the final ThinLTO link under QEMU, but QEMU ran out of memory after
about two hours before producing an artifact. Therefore LLVM22 has not yet
been proven with Pi.

As the fallback, the successful LLVM21 ARM64 static Bun artifact was tested in
an Alpine ARM64 container and used as the Bun compiler for this repository's
headless build path:

```text
Bun:          1.4.0, static ARM64 musl, 69,057,744 bytes
Bun SHA256:   7549825a56030606e63876677d946287963c500b4eb7cebdd1b97c3cd59897e7
Pi artifact:  packages/coding-agent/binaries/linux-aarch64/pi-headless
Pi size:      89,288,848 bytes
Pi SHA256:    731e56967e393e87a80ce1db2e56ad9a22517697c5cb7ede9fc9380a93b86f4f
```

The Pi artifact was built with the equivalent of `make headless` using the
static Bun, then validated with `make headless-test` in an Alpine ARM64
container:

```text
PASS: headless extracts and isolates a valid PI_PACKAGE_DIR
PASS: binary completed a fake-provider round-trip and printed the reply
```

The exact Pi artifact hash is recorded above. The build output itself is
intentionally ignored by this repository's git checkout.
