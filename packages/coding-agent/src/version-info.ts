import { APP_NAME, VERSION } from "./config.ts";
import { SOURCE_SHA } from "./version.generated.ts";

function runtimeLabel(): string {
	if (process.versions.bun) return `bun ${process.versions.bun}`;
	if (process.versions.deno) return `deno ${process.versions.deno}`;
	return `node ${process.versions.node ?? "unknown"}`;
}

export function formatVersion(): string {
	return `${APP_NAME} ${VERSION} (${SOURCE_SHA}) ${runtimeLabel()}`;
}
