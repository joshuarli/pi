import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { processFileArguments } from "../src/cli/file-processor.ts";
import { createReadTool } from "../src/core/tools/read.ts";
import { detectSupportedImageMimeType } from "../src/utils/mime.ts";

const TINY_PNG_BASE64 =
	"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==";

function createTinyBmp1x1Red24bpp(): Buffer {
	const buffer = Buffer.alloc(58);
	buffer.write("BM", 0, "ascii");
	buffer.writeUInt32LE(buffer.length, 2);
	buffer.writeUInt32LE(54, 10);
	buffer.writeUInt32LE(40, 14);
	buffer.writeInt32LE(1, 18);
	buffer.writeInt32LE(1, 22);
	buffer.writeUInt16LE(1, 26);
	buffer.writeUInt16LE(24, 28);
	buffer.writeUInt32LE(0, 30);
	buffer.writeUInt32LE(4, 34);
	buffer[56] = 0xff;
	return buffer;
}

describe("image attachment refusal", () => {
	let testDir: string;

	beforeEach(() => {
		testDir = join(tmpdir(), `image-attachment-callers-${Date.now()}`);
		mkdirSync(testDir, { recursive: true });
	});

	afterEach(() => {
		rmSync(testDir, { recursive: true, force: true });
	});

	it("detects supported image mime types from magic bytes", () => {
		expect(detectSupportedImageMimeType(Buffer.from(TINY_PNG_BASE64, "base64"))).toBe("image/png");
		expect(detectSupportedImageMimeType(createTinyBmp1x1Red24bpp())).toBe("image/bmp");
	});

	it("read tool omits image attachments", async () => {
		const imagePath = join(testDir, "test.png");
		writeFileSync(imagePath, Buffer.from(TINY_PNG_BASE64, "base64"));

		const tool = createReadTool(testDir);
		const result = await tool.execute("test-read-image", { path: imagePath });

		expect(result.content.some((c) => c.type === "image")).toBe(false);
		const first = result.content[0] as { type: string; text?: string };
		expect(first.type).toBe("text");
		expect(first.text).toContain("Image omitted");
	});

	it("file processor omits image attachments", async () => {
		const imagePath = join(testDir, "test.bmp");
		writeFileSync(imagePath, createTinyBmp1x1Red24bpp());

		const result = await processFileArguments([imagePath]);

		expect(result.text).toContain("Image omitted");
	});

	it("file processor reads text files normally", async () => {
		const textPath = join(testDir, "test.txt");
		writeFileSync(textPath, "Hello, world!");

		const result = await processFileArguments([textPath]);

		expect(result.text).toContain("Hello, world!");
	});
});
