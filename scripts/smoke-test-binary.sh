#!/usr/bin/env bash
# Smoke test for standalone pi binaries (pi-bun, pi-deno).
#
# Asserts that a single-file binary:
#   - extracts its embedded assets into an isolated TMPDIR cache directory
#   - points PI_PACKAGE_DIR at that directory (proven by --version matching the
#     version in the extracted package.json, since no package.json ships next to
#     the executable)
#   - reuses the cache across runs (exactly one pi-embedded-* directory)
#   - does not leak extraction artifacts into the working directory
#
# Usage: scripts/smoke-test-binary.sh <binary> <name>
set -euo pipefail

if [ "$#" -lt 2 ]; then
	echo "usage: $0 <binary> <name>" >&2
	exit 2
fi

BIN="$1"
NAME="$2"

if [ ! -x "$BIN" ]; then
	echo "FAIL: binary not found or not executable: $BIN (run 'make $NAME' first)" >&2
	exit 1
fi

# The binary caches extraction under $TMPDIR; use a fresh one and ignore any
# externally set package-dir overrides so the test is deterministic.
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export TMPDIR="$ROOT/tmp"
mkdir -p "$TMPDIR"
unset PI_PACKAGE_DIR PI_STANDALONE_BINARY

WORK="$ROOT/work"
mkdir -p "$WORK"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

echo "==> smoke-test: $NAME ($(basename "$BIN"))"

VERSION_OUT="$(cd "$WORK" && "$BIN" --version)" || fail "--version exited non-zero"
# --version reports "pi <semver> (<source sha>) <runtime>"; extract the semver.
VERSION="$(printf '%s' "$VERSION_OUT" | sed -E 's/^pi ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "--version output '$VERSION_OUT' is not a semver"

# Second run exercises the cache-reuse path (same TMPDIR).
( cd "$WORK" && "$BIN" --help >/dev/null 2>&1 ) || fail "--help exited non-zero"

mapfile -t CACHE_DIRS < <(find "$TMPDIR" -maxdepth 1 -type d -name 'pi-embedded-*' | sort)
if [ "${#CACHE_DIRS[@]}" -ne 1 ]; then
	echo "FAIL: expected exactly one extracted cache dir under TMPDIR; found:" >&2
	printf '  %s\n' "${CACHE_DIRS[@]}" >&2
	exit 1
fi
CACHE_DIR="${CACHE_DIRS[0]}"

test -f "$CACHE_DIR/.complete" || fail "missing $CACHE_DIR/.complete marker"

for f in package.json README.md CHANGELOG.md; do
	test -f "$CACHE_DIR/$f" || fail "missing $CACHE_DIR/$f"
done
for d in theme export-html docs examples; do
	test -d "$CACHE_DIR/$d" || fail "missing $CACHE_DIR/$d/"
done

PKG_VERSION="$(PI_SMOKE_PACKAGE_JSON="$CACHE_DIR/package.json" \
	node -e 'const p = require(process.env.PI_SMOKE_PACKAGE_JSON); process.stdout.write(p.version)')"
[ "$PKG_VERSION" = "$VERSION" ] || fail "binary version '$VERSION' != extracted package.json version '$PKG_VERSION'"

# Isolation: extraction must not leak into the working directory.
if [ -n "$(find "$WORK" -name 'pi-embedded-*' -print -quit)" ]; then
	fail "extraction leaked a pi-embedded-* path into the working directory"
fi

echo "    version: $VERSION"
echo "    package dir: $CACHE_DIR"
echo "==> PASS: $NAME extracts and isolates a valid PI_PACKAGE_DIR"
