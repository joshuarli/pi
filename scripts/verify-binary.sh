#!/bin/sh
#
# Verify the ELF linkage of a built pi binary with elfutils before it ships.
#
# `bun build --compile` output follows the libc of the Bun flavor used to
# build it: glibc by default, musl with BUN_FLAVOR=musl. gcompat only makes
# the glibc Bun tool run inside the Alpine builder; it does not change the
# output binary's linkage. Alpine-based environments (e.g. the xsh gym) need
# a musl or fully static binary, so the build must refuse to stage a glibc
# binary when musl is requested.
#
# bun 1.3.14 cannot produce a fully static compile output (no static-linking
# option; the musl flavor still links ld-musl, libstdc++, libgcc_s), so
# "musl" accepts either a static or a musl-linked binary and rejects glibc.
#
# Usage: verify-binary.sh <binary> <glibc|musl|static>
#
# Exit status: 0 when linkage matches the expectation, 1 when it does not,
# 2 on usage errors.
set -eu

binary=${1:?usage: verify-binary.sh <binary> <glibc|musl|static>}
expected=${2:?usage: verify-binary.sh <binary> <glibc|musl|static>}
readelf=${READELF:-eu-readelf}

test -f "$binary" || {
  echo "verify-binary: binary not found: $binary" >&2
  exit 2
}

case "$expected" in
  glibc | musl | static) ;;
  *)
    echo "verify-binary: expected must be glibc, musl, or static" >&2
    exit 2
    ;;
esac

# Program interpreter and NEEDED shared libraries, if any. A static binary
# has neither. eu-readelf emits "[Requesting program interpreter: /lib/...]"
# and "Shared library: [libc.so.6]" style lines.
interpreter=$($readelf -l "$binary" 2>/dev/null | awk '/interpreter/{print $NF; exit}' | tr -d '[]')
needed=$($readelf -d "$binary" 2>/dev/null | awk '/NEEDED/{print $NF}' | tr -d '[]' | tr '\n' ' ')

report() {
  echo "verify-binary: $binary: interpreter=${interpreter:-static} needed=$needed"
}

case "$expected" in
  static)
    if test -n "$interpreter" || test -n "$needed"; then
      report
      echo "verify-binary: error: expected static, got a dynamically linked binary" >&2
      exit 1
    fi
    report
    ;;
  musl)
    case "$interpreter" in
      *ld-linux*)
        report
        echo "verify-binary: error: expected musl or static, got a glibc-linked binary" >&2
        exit 1
        ;;
    esac
    report
    ;;
  glibc)
    case "$interpreter" in
      *ld-linux*) report ;;
      *)
        report
        echo "verify-binary: error: expected glibc, got interpreter=${interpreter:-none}" >&2
        exit 1
        ;;
    esac
    ;;
esac
