// Fake OpenAI-compatible SSE server used to smoke-test a compiled pi binary
// (headless) end-to-end without touching a real model provider or spending
// money. The binary is pointed at it via a temporary models.json baseUrl
// override; this server answers POST /api/v1/chat/completions with a canned
// text-delta SSE stream terminated by finish_reason=stop + [DONE].
//
// Usage: FAKE_PORT=<port> node scripts/fake-provider-server.mjs <reply-text>

import { createServer } from "node:http";

const PORT = Number(process.env.FAKE_PORT ?? 0);
const BODY = process.argv[2] ?? "Hello from fake provider";

const server = createServer((req, res) => {
	let body = "";
	req.on("data", (chunk) => (body += chunk));
	req.on("end", () => {
		if (req.method === "POST" && req.url === "/api/v1/chat/completions") {
			console.error(`REQ POST ${req.url}`);
			res.writeHead(200, {
				"content-type": "text/event-stream",
				"cache-control": "no-cache",
				connection: "keep-alive",
			});
			const chunk = (delta) =>
				res.write(
					`data: ${JSON.stringify({
						id: "chatcmpl-fake",
						object: "chat.completion.chunk",
						created: 1700000000,
						model: "headless-fake",
						choices: [{ index: 0, delta, finish_reason: null }],
					})}\n\n`,
				);
			chunk({ role: "assistant", content: BODY });
			chunk({});
			res.write(
				`data: ${JSON.stringify({
					id: "chatcmpl-fake",
					object: "chat.completion.chunk",
					created: 1700000000,
					model: "headless-fake",
					choices: [{ index: 0, delta: {}, finish_reason: "stop" }],
				})}\n\n`,
			);
			res.write("data: [DONE]\n\n");
			res.end();
			return;
		}
		res.writeHead(404, { "content-type": "application/json" });
		res.end(JSON.stringify({ error: { message: `no route ${req.method} ${req.url}` } }));
	});
});

server.listen(PORT, "127.0.0.1", () => {
	console.log(`LISTENING ${PORT}`);
});
