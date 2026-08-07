import { describe, expect, test, vi } from "vitest";
import { type ClipboardModule, loadClipboardNative, supportsNativeNodeAddons } from "../src/utils/clipboard-native.ts";

type ClipboardRequire = (id: string) => unknown;

const fakeClipboard: ClipboardModule = {
	getText: async () => "",
	setText: async () => {},
	hasImage: () => true,
	getImageBinary: async () => [1, 2, 3],
};

describe("loadClipboardNative", () => {
	test("does not load native addons in QuickJS Deno", () => {
		expect(supportsNativeNodeAddons({ deno: "2.9.5", typescript: "n/a" })).toBe(false);
	});

	test("loads native addons in Deno V8", () => {
		expect(supportsNativeNodeAddons({ deno: "2.9.5", typescript: "6.0.3" })).toBe(true);
	});

	test("falls back to the next require root", () => {
		const primary = vi.fn<ClipboardRequire>(() => {
			throw new Error("missing from bundled root");
		});
		const fallback = vi.fn<ClipboardRequire>(() => fakeClipboard);

		expect(loadClipboardNative([primary, fallback])).toBe(fakeClipboard);
		expect(primary).toHaveBeenCalledWith("@mariozechner/clipboard");
		expect(fallback).toHaveBeenCalledWith("@mariozechner/clipboard");
	});

	test("returns null when no require root can load clipboard", () => {
		const missing = vi.fn<ClipboardRequire>(() => {
			throw new Error("missing");
		});

		expect(loadClipboardNative([missing])).toBeNull();
	});
});
