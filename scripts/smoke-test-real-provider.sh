#!/usr/bin/env bash
# Real OpenRouter smoke test for a compiled pi binary.
#
# Usage: scripts/smoke-test-real-provider.sh <binary>
set -euo pipefail

if [ "$#" -lt 1 ] || [ ! -x "$1" ]; then
	echo "usage: $0 <executable binary>" >&2
	exit 2
fi

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
	echo "OPENROUTER_API_KEY must be set" >&2
	exit 1
fi

BIN="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
PI_CODING_AGENT_DIR="$(mktemp -d)"
trap 'rm -rf "$PI_CODING_AGENT_DIR"' EXIT

echo "==> real-provider test: $(basename "$BIN")"
PI_CODING_AGENT_DIR="$PI_CODING_AGENT_DIR" \
	OPENROUTER_API_KEY="$OPENROUTER_API_KEY" \
	"$BIN" \
	--offline --no-tools --no-extensions --no-skills --no-themes \
	--no-session --no-context-files --approve --thinking low \
	--provider openrouter --model "poolside/laguna-xs-2.1:free" \
	-p "just say hi"

echo "==> PASS: real-provider request completed"
