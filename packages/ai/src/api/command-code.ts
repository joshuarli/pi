import type {
	AssistantMessage,
	Context,
	Model,
	ProviderHeaders,
	SimpleStreamOptions,
	StreamFunction,
	StreamOptions,
	ThinkingLevel,
	ToolCall,
	Usage,
} from "../types.ts";
import { AssistantMessageEventStream } from "../utils/event-stream.ts";
import { headersToRecord, providerHeadersToRecord } from "../utils/headers.ts";

export interface CommandCodeOptions extends StreamOptions {
	reasoning?: ThinkingLevel;
	permissionMode?: "standard" | "auto-accept" | "plan";
	threadId?: string;
	mode?: string;
}

type WireContent = Record<string, unknown>;
type WireMessage = { role: string; content: WireContent[] };
type CommandCodeEvent = Record<string, unknown>;

const API_ROUTE = "/alpha/generate";
const COMMAND_CODE_CLIENT_VERSION = "1.7.1";

function emptyUsage(): Usage {
	return {
		input: 0,
		output: 0,
		cacheRead: 0,
		cacheWrite: 0,
		totalTokens: 0,
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
	};
}

function textFromContent(
	content: string | Array<{ type: string; text?: string; data?: string; mimeType?: string }>,
): string {
	if (typeof content === "string") return content;
	return content
		.map((block) =>
			block.type === "text"
				? (block.text ?? "")
				: `[image:${block.mimeType ?? "unknown"}:${block.data?.length ?? 0}]`,
		)
		.join("\n");
}

function toWireMessages(context: Context): WireMessage[] {
	return context.messages.map((message): WireMessage => {
		if (message.role === "user") {
			const content =
				typeof message.content === "string"
					? [{ type: "text", text: message.content }]
					: message.content.map((block) =>
							block.type === "text"
								? { type: "text", text: block.text }
								: {
										type: "image",
										image: `data:${block.mimeType};base64,${block.data}`,
										mimeType: block.mimeType,
									},
						);
			return { role: "user", content };
		}
		if (message.role === "assistant") {
			return {
				role: "assistant",
				content: message.content.map((block) =>
					block.type === "text"
						? { type: "text", text: block.text }
						: block.type === "thinking"
							? { type: "reasoning", text: block.thinking }
							: { type: "tool-call", toolCallId: block.id, toolName: block.name, input: block.arguments },
				),
			};
		}
		return {
			role: "tool",
			content: [
				{
					type: "tool-result",
					toolCallId: message.toolCallId,
					toolName: message.toolName,
					output: { type: "text", value: textFromContent(message.content) },
					isError: message.isError,
				},
			],
		};
	});
}

function createPartial(model: Model<"command-code">): AssistantMessage {
	return {
		role: "assistant",
		content: [],
		api: model.api,
		provider: model.provider,
		model: model.id,
		usage: emptyUsage(),
		stopReason: "pending",
		timestamp: Date.now(),
	};
}

function numberValue(value: unknown): number {
	return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function updateUsage(partial: AssistantMessage, value: unknown): void {
	if (!value || typeof value !== "object") return;
	const usage = value as Record<string, unknown>;
	const input = numberValue(usage.inputTokens);
	const output = numberValue(usage.outputTokens);
	const details = usage.inputTokenDetails;
	const cacheRead =
		details && typeof details === "object" ? numberValue((details as Record<string, unknown>).cacheReadTokens) : 0;
	const cacheWrite =
		details && typeof details === "object" ? numberValue((details as Record<string, unknown>).cacheWriteTokens) : 0;
	partial.usage = {
		input,
		output,
		cacheRead,
		cacheWrite,
		totalTokens: input + output + cacheRead + cacheWrite,
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
	};
}

function eventText(event: CommandCodeEvent): string {
	return typeof event.text === "string" ? event.text : "";
}

function readEvent(raw: string): CommandCodeEvent | undefined {
	if (!raw.trim()) return undefined;
	const value: unknown = JSON.parse(raw);
	return value && typeof value === "object" && !Array.isArray(value) ? (value as CommandCodeEvent) : undefined;
}

function errorMessage(error: unknown): string {
	if (error instanceof Error) return error.message;
	if (error && typeof error === "object" && "message" in error && typeof error.message === "string")
		return error.message;
	return String(error);
}

function providerHeaders(headers: ProviderHeaders | undefined): Record<string, string> {
	return providerHeadersToRecord(headers) ?? {};
}

function commandCodeConfig(): Record<string, unknown> {
	const runtime = (globalThis as { process?: { cwd?: () => string; platform?: string } }).process;
	return {
		workingDir: runtime?.cwd?.() ?? ".",
		date: new Date().toISOString().slice(0, 10),
		environment: runtime?.platform ?? "unknown",
		structure: [],
		isGitRepo: false,
		currentBranch: "",
		mainBranch: "",
		gitStatus: "Working tree clean",
		recentCommits: [],
	};
}

export const stream: StreamFunction<"command-code", CommandCodeOptions> = (model, context, options) => {
	const output = new AssistantMessageEventStream();
	const partial = createPartial(model);

	void (async () => {
		try {
			if (!options?.apiKey) throw new Error(`No API key provided for provider "${model.provider}"`);
			const custom = options as CommandCodeOptions;
			const params = {
				model: model.id,
				messages: toWireMessages(context),
				tools:
					context.tools?.map((tool) => ({
						name: tool.name,
						description: tool.description,
						input_schema: tool.parameters,
					})) ?? [],
				system: context.systemPrompt,
				max_tokens: options.maxTokens ?? model.maxTokens,
				stream: true,
				...(options.temperature === undefined ? {} : { temperature: options.temperature }),
				...(custom.reasoning ? { reasoning_effort: custom.reasoning } : {}),
			};
			let payload: unknown = {
				config: commandCodeConfig(),
				memory: null,
				taste: null,
				skills: null,
				permissionMode: custom.permissionMode ?? "standard",
				threadId: custom.threadId,
				mode: custom.mode ?? "agent",
				params,
			};
			const nextPayload = await options.onPayload?.(payload, model);
			if (nextPayload !== undefined) payload = nextPayload;
			const headers: Record<string, string> = {
				authorization: `Bearer ${options.apiKey}`,
				accept: "application/x-ndjson",
				"content-type": "application/json",
				"x-cli-environment": "cli",
				"x-command-code-version": COMMAND_CODE_CLIENT_VERSION,
				"user-agent": "cli",
				...providerHeaders(options.headers),
			};
			if ((options.env?.COMMANDCODE_ZDR ?? process.env.COMMANDCODE_ZDR) === "1") headers["x-cmd-zdr"] = "1";
			const url = new URL(`${model.baseUrl.replace(/\/+$/u, "")}${API_ROUTE}`);
			const response = await (options.fetch ?? globalThis.fetch)(url, {
				method: "POST",
				headers,
				body: JSON.stringify(payload),
				signal: options.signal,
			});
			await options.onResponse?.({ status: response.status, headers: headersToRecord(response.headers) }, model);
			if (!response.ok) throw new Error(`${response.status} ${response.statusText}: ${await response.text()}`);
			if (!response.body) throw new Error(`${model.provider} response has no body`);
			output.push({ type: "start", partial });
			const reader = response.body.getReader();
			const decoder = new TextDecoder();
			let buffer = "";
			let textIndex = -1;
			let thinkingIndex = -1;
			try {
				while (true) {
					const chunk = await reader.read();
					buffer += decoder.decode(chunk.value, { stream: !chunk.done });
					const lines = buffer.split(/\r?\n/u);
					buffer = lines.pop() ?? "";
					for (const line of lines) {
						const event = readEvent(line);
						if (!event) continue;
						switch (event.type) {
							case "text-delta": {
								if (textIndex < 0) {
									textIndex = partial.content.length;
									partial.content.push({ type: "text", text: "" });
									output.push({ type: "text_start", contentIndex: textIndex, partial });
								}
								const delta = eventText(event);
								(partial.content[textIndex] as { type: "text"; text: string }).text += delta;
								output.push({ type: "text_delta", contentIndex: textIndex, delta, partial });
								break;
							}
							case "reasoning-start":
								thinkingIndex = partial.content.length;
								partial.content.push({ type: "thinking", thinking: "" });
								output.push({ type: "thinking_start", contentIndex: thinkingIndex, partial });
								break;
							case "reasoning-delta": {
								const delta = eventText(event);
								if (thinkingIndex < 0) {
									thinkingIndex = partial.content.length;
									partial.content.push({ type: "thinking", thinking: "" });
									output.push({ type: "thinking_start", contentIndex: thinkingIndex, partial });
								}
								(partial.content[thinkingIndex] as { type: "thinking"; thinking: string }).thinking += delta;
								output.push({ type: "thinking_delta", contentIndex: thinkingIndex, delta, partial });
								break;
							}
							case "tool-call": {
								const id =
									typeof event.toolCallId === "string" ? event.toolCallId : `tool-${partial.content.length}`;
								const name = typeof event.toolName === "string" ? event.toolName : "tool";
								const args = event.input ?? event.args;
								const toolCall: ToolCall = {
									type: "toolCall",
									id,
									name,
									arguments:
										args && typeof args === "object" && !Array.isArray(args)
											? (args as Record<string, never>)
											: {},
								};
								const index = partial.content.length;
								partial.content.push(toolCall);
								output.push({ type: "toolcall_start", contentIndex: index, partial });
								output.push({ type: "toolcall_end", contentIndex: index, toolCall, partial });
								break;
							}
							case "finish": {
								const raw = typeof event.rawFinishReason === "string" ? event.rawFinishReason : undefined;
								const reason =
									event.finishReason === "tool-calls"
										? "toolUse"
										: event.finishReason === "length"
											? "length"
											: "stop";
								partial.rawStopReason = raw;
								partial.stopReason = reason;
								updateUsage(partial, event.totalUsage);
								output.push({ type: "done", reason, message: partial });
								return;
							}
							case "error":
								throw new Error(errorMessage(event.error));
							case "abort":
								partial.stopReason = "aborted";
								partial.errorMessage = "Command Code stream aborted";
								output.push({ type: "error", reason: "aborted", error: partial });
								return;
						}
					}
					if (chunk.done) break;
				}
				if (buffer.trim()) {
					const event = readEvent(buffer);
					if (event?.type === "finish") {
						partial.stopReason =
							event.finishReason === "tool-calls"
								? "toolUse"
								: event.finishReason === "length"
									? "length"
									: "stop";
						updateUsage(partial, event.totalUsage);
						output.push({ type: "done", reason: partial.stopReason, message: partial });
						return;
					}
				}
			} finally {
				reader.releaseLock();
			}
			throw new Error("Command Code stream ended without a terminal event");
		} catch (error) {
			const reason = options?.signal?.aborted ? "aborted" : "error";
			partial.stopReason = reason;
			partial.errorMessage = errorMessage(error);
			output.push({ type: "error", reason, error: partial });
		}
	})();
	return output;
};

export const streamSimple: StreamFunction<"command-code", SimpleStreamOptions> = (model, context, options) =>
	stream(model, context, options as CommandCodeOptions | undefined);
