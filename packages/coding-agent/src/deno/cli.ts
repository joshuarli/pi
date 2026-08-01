#!/usr/bin/env node
import "../standalone-assets.ts";
import { registerBunOAuthFlows } from "@earendil-works/pi-ai/bun-oauth";
import { APP_NAME } from "../config.ts";

process.title = APP_NAME;
process.emitWarning = (() => {}) as typeof process.emitWarning;

registerBunOAuthFlows();

import { restoreSandboxEnv } from "../bun/restore-sandbox-env.ts";

restoreSandboxEnv();

await import("../bun/register-bedrock.ts");
await import("../cli.ts");
