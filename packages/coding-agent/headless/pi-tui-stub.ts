/**
 * Headless stub for `@earendil-works/pi-tui`.
 *
 * Only used by the headless build (`scripts/build-headless.mts` + Makefile
 * `headless` target). A `bun` plugin swaps the import for this module so the
 * binary carries none of the interactive UI code.
 *
 * The bundle never runs the TUI (headless is print/rpc/json only), so these
 * TUI primitives are dead paths at runtime. They must still resolve as modules
 * so the bundler can link the tool/CLI graph. The stub only needs the value
 * exports that the compiled `dist` imports at runtime; type-only imports are
 * erased by `tsgo`.
 *
 * The exact candidate list is derived from:
 *   grep -rhoE 'import \{[^}]*\} from "@earendil-works/pi-tui"' dist/
 */

export type Component<Props = Record<string, unknown>> = object;
export type Focusable = object;
export type TUI = object;
export type KeyId = string;
export type Keybinding = { id: string };
export type KeybindingsConfig = Record<string, unknown>;
export type MarkdownTheme = Record<string, unknown>;
export type RgbColor = { r: number; g: number; b: number };
export type ScrollViewScrollbar = unknown;
export type SelectListTheme = Record<string, unknown>;
export type SettingsListTheme = Record<string, unknown>;
export type EditorOptions = Record<string, unknown>;
export type EditorTheme = Record<string, unknown>;

export const TUI_KEYBINDINGS = {};

class KeybindingsManager {
	constructor(..._args: unknown[]) {}
}
export { KeybindingsManager };

export class ProcessTerminal {
	constructor(..._args: unknown[]) {}
}
export class TuiAltScreen {
	constructor(..._args: unknown[]) {}
}
export class TuiMainScreen {
	constructor(..._args: unknown[]) {}
}

export class Box {
	constructor(..._args: unknown[]) {}
}
export class Container {
	constructor(..._args: unknown[]) {}
}
export class Spacer {
	constructor(..._args: unknown[]) {}
}
export class Text {
	constructor(..._args: unknown[]) {}
}
export class TruncatedText {
	constructor(..._args: unknown[]) {}
}
export class Input {
	constructor(..._args: unknown[]) {}
}
export class Editor {
	constructor(..._args: unknown[]) {}
}
export class Image {
	constructor(..._args: unknown[]) {}
}
export class Markdown {
	constructor(..._args: unknown[]) {}
}
export class Loader {
	constructor(..._args: unknown[]) {}
}
export class CancellableLoader {
	constructor(..._args: unknown[]) {}
}
export class SelectList<T = unknown> {
	constructor(..._args: unknown[]) {}
	public getSelectedItem(): { label: string; value: T } | undefined {
		return undefined;
	}
}
export class SettingsList {
	constructor(..._args: unknown[]) {}
}
export class CombinedAutocompleteProvider {
	constructor(..._args: unknown[]) {}
}
export class Key {
	constructor(..._args: unknown[]) {}
}

export function getCapabilities(): Record<string, unknown> {
	return {};
}
export function getCellDimensions(): Record<string, unknown> {
	return {};
}
export function getImageDimensions(): undefined {
	return undefined;
}
export function getKeybindings(..._args: unknown[]): Array<{ id: string }> {
	return [];
}
export function setKeybindings(..._args: unknown[]): void {}
export function truncateToWidth(..._args: unknown[]): string {
	return "";
}
export function visibleWidth(..._args: unknown[]): number {
	return 0;
}
export function hyperlink(text: string): string {
	return text;
}
export function imageFallback(..._args: unknown[]): string {
	return "";
}
export function fuzzyMatch(_query: string, _candidate: string): boolean {
	return false;
}
export function fuzzyFilter<T>(_query: string, _items: readonly T[]): T[] {
	return [..._items];
}
export function matchesKey(_key: unknown, _pattern: string): boolean {
	return false;
}
export function sliceByColumn(..._args: unknown[]): string {
	return "";
}
export function wrapTextWithAnsi(..._args: unknown[]): string {
	return "";
}

/** Namespace import target used by `core/extensions/loader.ts`. */
export default {};