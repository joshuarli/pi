#!/usr/bin/env bash
# Fake-provider round-trip smoke test for a compiled pi binary.
#
# Point a binary at a local fake OpenAI-compatible SSE server and assert it
# completes a one-shot `-p` prompt and prints the canned reply. This exercises
# the real compiled request path: config load -> auth -> fetch -> SSE parse ->
# print, with no network to a real provider and no API money spent.
#
# Usage: scripts/smoke-test-fake-provider.sh <binary>
set -euo pipefail

if [ "$#" -lt 1 ] || [ ! -x "$1" ]; then
	echo "usage: $0 <binary>" >&2
	exit 2
fi

BIN="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
REPLY="fake-provider-reply-OK"
ROOT="$(mktemp -d)"
FAKE_PORT=8787

cleanup() {
	[ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
	rm -rf "$ROOT"
}
trap cleanup EXIT

# Self-contained fake server config: temp agent dir with a models.json that
# overrides the openrouter baseUrl to the local fake server.
mkdir -p "$ROOT/agent"
cat > "$ROOT/agent/models.json" <<EOF
{
	"providers": {
		"openrouter": {
			"baseUrl": "http://127.0.0.1:${FAKE_PORT}/api/v1"
		}
	}
}
EOF

FAKE_PORT="$FAKE_PORT" node ./scripts/fake-provider-server.mjs "$REPLY" 2>"$ROOT/server.log" &
SERVER_PID=$!

# Wait for the server to be ready.
for _ in $(seq 1 50); do
	if curl -sf -X POST "http://127.0.0.1:${FAKE_PORT}/api/v1/chat/completions" -d '{}' >/dev/null 2>&1; then
		break
	fi
	sleep 0.1
done

WORK="$ROOT/work"
mkdir -p "$WORK"

echo "==> fake-provider test: $(basename "$BIN")"

OUT="$(cd "$WORK" && OPENROUTER_API_KEY=fake-key \
	PI_CODING_AGENT_DIR="$ROOT/agent" \
	PI_OFFLINE=1 \
	"$BIN" -p "Say hi" \
	--offline --approve \
	--no-extensions --no-skills --no-prompt-templates --no-themes --no-context-files \
	--provider openrouter --model "openrouter/deepseek/deepseek-v4-flash-latest" 2>&1)"

echo "--- output ---"
printf '%s\n' "$OUT"

if printf '%s' "$OUT" | grep -q "$REPLY"; then
	echo "==> PASS: binary completed a fake-provider round-trip and printed the reply"
else
	echo "FAIL: binary did not print the canned reply \"$REPLY\"" >&2
	echo "--- server log ---" >&2
	cat "$ROOT/server.log" >&2 || true
	exit 1
fi
