import type { Model } from "../types.ts";

const BASE_URL = "https://api.commandcode.ai";

type ModelDefinition = {
	id: string;
	name: string;
	contextWindow: number;
	input?: ("text" | "image")[];
	reasoning?: boolean;
	maxTokens?: number;
};

// Sourced from Command Code's bundled model registry. Keep gateway slugs intact:
// these are not Pi aliases and are sent verbatim to /alpha/generate.
const MODEL_DEFINITIONS: ModelDefinition[] = [
	{ id: "claude-sonnet-5", name: "Claude Sonnet 5", contextWindow: 1_000_000, reasoning: true },
	{ id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", contextWindow: 1_000_000 },
	{ id: "claude-fable-5", name: "Claude Fable 5", contextWindow: 1_000_000, reasoning: true },
	{ id: "claude-opus-5", name: "Claude Opus 5", contextWindow: 1_000_000, reasoning: true },
	{ id: "claude-opus-4-8", name: "Claude Opus 4.8", contextWindow: 1_000_000, reasoning: true },
	{ id: "claude-opus-4-7", name: "Claude Opus 4.7", contextWindow: 1_000_000, reasoning: true },
	{ id: "claude-haiku-4-5-20251001", name: "Claude Haiku 4.5", contextWindow: 200_000 },
	{ id: "gpt-5.6-sol", name: "GPT-5.6 Sol", contextWindow: 1_050_000, reasoning: true },
	{ id: "gpt-5.6-terra", name: "GPT-5.6 Terra", contextWindow: 1_050_000, reasoning: true },
	{ id: "gpt-5.6-luna", name: "GPT-5.6 Luna", contextWindow: 1_050_000, reasoning: true },
	{ id: "gpt-5.5", name: "GPT-5.5", contextWindow: 400_000, reasoning: true },
	{ id: "gpt-5.4", name: "GPT-5.4", contextWindow: 400_000, reasoning: true },
	{ id: "gpt-5.3-codex", name: "GPT-5.3 Codex", contextWindow: 400_000, reasoning: true },
	{ id: "gpt-5.4-mini", name: "GPT-5.4 Mini", contextWindow: 400_000, reasoning: true },
	{ id: "MiniMaxAI/MiniMax-M3-Free", name: "MiniMax M3", contextWindow: 1_000_000, input: ["text", "image"], reasoning: true },
	{ id: "deepseek/deepseek-v4-pro", name: "DeepSeek V4 Pro", contextWindow: 1_000_000, reasoning: true },
	{ id: "deepseek/deepseek-v4-flash", name: "DeepSeek V4 Flash", contextWindow: 1_000_000, reasoning: true },
	{ id: "moonshotai/Kimi-K3", name: "Kimi K3", contextWindow: 1_000_000, input: ["text", "image"], reasoning: true },
	{ id: "moonshotai/Kimi-K2.7-Code", name: "Kimi K2.7 Code", contextWindow: 256_000, input: ["text", "image"], reasoning: true },
	{ id: "moonshotai/Kimi-K2.7-Code-Highspeed", name: "Kimi K2.7 Code HighSpeed", contextWindow: 262_000, input: ["text", "image"], reasoning: true },
	{ id: "moonshotai/Kimi-K2.6", name: "Kimi K2.6", contextWindow: 256_000, input: ["text", "image"] },
	{ id: "moonshotai/Kimi-K2.5", name: "Kimi K2.5", contextWindow: 256_000, input: ["text", "image"] },
	{ id: "zai-org/GLM-5.2", name: "GLM-5.2", contextWindow: 1_000_000, reasoning: true },
	{ id: "zai-org/GLM-5.2-Fast", name: "GLM-5.2 Fast", contextWindow: 1_000_000 },
	{ id: "zai-org/GLM-5.1", name: "GLM-5.1", contextWindow: 200_000 },
	{ id: "zai-org/GLM-5", name: "GLM-5", contextWindow: 200_000 },
	{ id: "MiniMaxAI/MiniMax-M3", name: "MiniMax M3", contextWindow: 1_000_000, input: ["text", "image"], reasoning: true },
	{ id: "MiniMaxAI/MiniMax-M2.7", name: "MiniMax M2.7", contextWindow: 200_000 },
	{ id: "MiniMaxAI/MiniMax-M2.5", name: "MiniMax M2.5", contextWindow: 200_000 },
	{ id: "xiaomi/mimo-v2.5-pro", name: "MiMo V2.5 Pro", contextWindow: 1_000_000 },
	{ id: "xiaomi/mimo-v2.5", name: "MiMo V2.5", contextWindow: 1_000_000, input: ["text", "image"] },
	{ id: "Qwen/Qwen3.6-Max-Preview", name: "Qwen 3.6 Max Preview", contextWindow: 200_000, reasoning: true },
	{ id: "Qwen/Qwen3.6-Plus", name: "Qwen 3.6 Plus", contextWindow: 200_000, input: ["text", "image"], reasoning: true },
	{ id: "Qwen/Qwen3.7-Max", name: "Qwen 3.7 Max", contextWindow: 1_000_000, reasoning: true },
	{ id: "Qwen/Qwen3.7-Plus", name: "Qwen 3.7 Plus", contextWindow: 1_000_000, input: ["text", "image"], reasoning: true },
	{ id: "Qwen/Qwen3.7-Flash", name: "Qwen 3.7 Flash", contextWindow: 1_000_000, input: ["text", "image"], reasoning: true },
	{ id: "stepfun/Step-3.7-Flash", name: "Step 3.7 Flash", contextWindow: 256_000, input: ["text", "image"], reasoning: true },
	{ id: "stepfun/Step-3.5-Flash", name: "Step 3.5 Flash", contextWindow: 1_000_000, reasoning: true },
	{ id: "tencent/Hy3", name: "Tencent Hy3 (Free)", contextWindow: 262_144, reasoning: true },
	{ id: "tencent/hy3-paid", name: "Tencent Hy3", contextWindow: 262_144, reasoning: true },
	{ id: "google/gemini-3.6-flash", name: "Gemini 3.6 Flash", contextWindow: 1_000_000, input: ["text", "image"], reasoning: true },
	{ id: "google/gemini-3.5-flash", name: "Gemini 3.5 Flash", contextWindow: 1_000_000, input: ["text", "image"], reasoning: true },
	{ id: "google/gemini-3.5-flash-lite", name: "Gemini 3.5 Flash Lite", contextWindow: 1_000_000, input: ["text", "image"], reasoning: true },
	{ id: "google/gemini-3.1-flash-lite", name: "Gemini 3.1 Flash Lite", contextWindow: 1_000_000, input: ["text", "image"], reasoning: true },
	{ id: "sakana/fugu-ultra", name: "Fugu Ultra", contextWindow: 1_000_000, input: ["text", "image"], reasoning: true },
	{ id: "nvidia/nemotron-3-ultra-550b-a55b", name: "Nemotron 3 Ultra", contextWindow: 1_000_000, reasoning: true },
	{ id: "thinkingmachines/inkling", name: "Inkling", contextWindow: 256_000, input: ["text", "image"], reasoning: true },
	{ id: "thinkingmachines/inkling-small", name: "Inkling Small", contextWindow: 1_000_000, input: ["text", "image"], reasoning: true },
	{ id: "poolside/laguna-s-2.1-free", name: "Laguna S 2.1", contextWindow: 256_000, maxTokens: 32_768, reasoning: true },
	{ id: "inclusionai/ling-3.0-flash-free", name: "Ling 3.0 Flash", contextWindow: 256_000, maxTokens: 32_768, reasoning: true },
	{ id: "meta/muse-spark-1.1", name: "Muse Spark 1.1", contextWindow: 1_048_576, input: ["text", "image"], reasoning: true },
	{ id: "xai/grok-4.5", name: "Grok 4.5", contextWindow: 500_000, input: ["text", "image"], reasoning: true },
];

export const COMMAND_CODE_MODELS: Record<string, Model<"command-code">> = Object.fromEntries(
	MODEL_DEFINITIONS.map((definition) => [
		definition.id,
		{
			...definition,
			api: "command-code" as const,
			provider: "command-code" as const,
			baseUrl: BASE_URL,
			reasoning: definition.reasoning ?? false,
			input: definition.input ?? ["text"],
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
			maxTokens: definition.maxTokens ?? 64_000,
		},
	]),
) as Record<string, Model<"command-code">>;
