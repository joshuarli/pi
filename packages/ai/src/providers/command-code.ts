import { stream, streamSimple } from "../api/command-code.ts";
import type { ApiKeyAuth } from "../auth/types.ts";
import { createProvider, type Provider } from "../models.ts";
import { COMMAND_CODE_MODELS } from "./command-code.catalog.ts";

async function localCommandCodeKey(
	readFile: ((path: string) => Promise<string | undefined>) | undefined,
): Promise<string | undefined> {
	if (!readFile) return undefined;
	try {
		const parsed: unknown = JSON.parse((await readFile("~/.commandcode/auth.json")) ?? "");
		if (parsed && typeof parsed === "object" && "apiKey" in parsed && typeof parsed.apiKey === "string")
			return parsed.apiKey;
	} catch {
		// The CLI may not have completed authentication, or its file may be absent.
	}
	return undefined;
}

const commandCodeAuth: ApiKeyAuth = {
	name: "Command Code API key",
	login: async (interaction) => ({
		type: "api_key",
		key: await interaction.prompt({ type: "secret", message: "Enter Command Code API key" }),
	}),
	resolve: async ({ ctx, credential }) => {
		if (credential?.key) return { auth: { apiKey: credential.key }, source: "stored credential" };
		const envKey = await ctx.env("COMMANDCODE_API_KEY");
		if (envKey) return { auth: { apiKey: envKey }, source: "COMMANDCODE_API_KEY" };
		const fileKey = await localCommandCodeKey(ctx.readFile);
		return fileKey ? { auth: { apiKey: fileKey }, source: "~/.commandcode/auth.json" } : undefined;
	},
};

export function commandCodeProvider(): Provider<"command-code"> {
	return createProvider({
		id: "command-code",
		name: "Command Code",
		baseUrl: "https://api.commandcode.ai",
		auth: { apiKey: commandCodeAuth },
		models: Object.values(COMMAND_CODE_MODELS),
		api: { stream, streamSimple },
	});
}
