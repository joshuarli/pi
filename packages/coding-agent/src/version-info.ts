import { APP_NAME, VERSION } from "./config.ts";
import { RUNTIME_SHA, RUNTIME_VERSION, SOURCE_SHA } from "./version.generated.ts";

function runtimeLabel(): string {
	if (process.versions.bun || process.versions.deno) return `${RUNTIME_VERSION} (${RUNTIME_SHA})`;
	return `node ${process.versions.node ?? "unknown"}`;
}

export function formatVersion(): string {
	return `${APP_NAME} ${VERSION} (${SOURCE_SHA}) ${runtimeLabel()}`;
}
