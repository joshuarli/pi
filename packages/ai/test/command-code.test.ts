import { describe, expect, it } from "vitest";
import type { AuthContext } from "../src/auth/types.ts";
import { createModels } from "../src/models.ts";
import { commandCodeProvider } from "../src/providers/command-code.ts";
import type { Context, Model } from "../src/types.ts";

function authContext(env: Record<string, string>): AuthContext {
	return { env: async (name) => env[name], fileExists: async () => false };
}

describe("Command Code provider", () => {
	it("resolves the CLI-compatible API key environment", async () => {
		const models = createModels({ authContext: authContext({ COMMANDCODE_API_KEY: "test-key" }) });
		models.setProvider(commandCodeProvider());

		expect(await models.getAuth("command-code")).toEqual({
			auth: { apiKey: "test-key" },
			source: "COMMANDCODE_API_KEY",
		});
		expect(models.getModels("command-code").length).toBe(52);
		expect(models.getModel("command-code", "deepseek/deepseek-v4-pro")).toMatchObject({ contextWindow: 1_000_000 });
		expect(models.getModel("command-code", "deepseek/deepseek-v4-flash")).toBeDefined();
		expect(models.getModel("command-code", "poolside/laguna-s-2.1-free")).toMatchObject({ maxTokens: 32_768 });
	});

	it("resolves the CLI's local auth file through the auth context", async () => {
		const models = createModels({
			authContext: {
				env: async () => undefined,
				fileExists: async () => true,
				readFile: async (path) =>
					path === "~/.commandcode/auth.json" ? JSON.stringify({ apiKey: "file-key" }) : undefined,
			},
		});
		models.setProvider(commandCodeProvider());

		expect(await models.getAuth("command-code")).toEqual({
			auth: { apiKey: "file-key" },
			source: "~/.commandcode/auth.json",
		});
	});

	it("translates the gateway NDJSON stream into Pi events", async () => {
		const provider = commandCodeProvider();
		const model = provider.getModels()[0] as Model<"command-code">;
		const context: Context = {
			systemPrompt: "Be concise",
			messages: [{ role: "user", content: "hello", timestamp: Date.now() }],
			tools: [{ name: "weather", description: "Get weather", parameters: { type: "object", properties: {} } }],
		};
		let request: Request | undefined;
		const response = new Response(
			[
				JSON.stringify({ type: "text-delta", text: "hi" }),
				JSON.stringify({ type: "tool-call", toolCallId: "call-1", toolName: "weather", input: { city: "Paris" } }),
				JSON.stringify({
					type: "finish",
					finishReason: "tool-calls",
					rawFinishReason: "tool_use",
					totalUsage: { inputTokens: 12, outputTokens: 4 },
				}),
			].join("\n"),
		);

		const stream = provider.stream(model, context, {
			apiKey: "test-key",
			fetch: async (input, init) => {
				request = new Request(input, init);
				return response;
			},
		});
		const events = [];
		for await (const event of stream) events.push(event);
		const result = await stream.result();

		expect(request?.url).toBe("https://api.commandcode.ai/alpha/generate");
		expect(request?.headers.get("authorization")).toBe("Bearer test-key");
		expect(request?.headers.get("x-command-code-version")).toBe("1.7.1");
		expect(request?.headers.get("x-cli-environment")).toBe("cli");
		expect(request?.headers.get("user-agent")).toBe("cli");
		const payload = JSON.parse(await request!.text()) as {
			config: { workingDir: string; date: string; structure: unknown[] };
			taste: unknown;
			mode: string;
			params: { model: string; stream: boolean; tools: unknown[] };
		};
		expect(payload).toMatchObject({ taste: null, mode: "agent" });
		expect(payload.config).toMatchObject({
			workingDir: expect.any(String),
			date: expect.stringMatching(/^\d{4}-\d{2}-\d{2}$/),
			structure: [],
		});
		expect(payload.params).toMatchObject({ model: model.id, stream: true });
		expect(payload.params.tools).toHaveLength(1);
		expect(events.map((event) => event.type)).toContain("toolcall_end");
		expect(result.stopReason).toBe("toolUse");
		expect(result.usage.input).toBe(12);
	});
});
