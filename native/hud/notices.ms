import { Color, rgba } from "@metascript/void/src/void2d/types";
import { Ui, box, beginOverlay, endOverlay, DESIGN_W, DESIGN_H } from "../ui/ui";
import { Kit, TextSize, subId, measure, measureWrapped, frame, fill, beginKitOverlay, endKitOverlay, iconTinted, say, INK, INK_MUTED, EMBER_HOT, ALERT_RED, DISABLED_INK, DIMMED,
	WHITE } from "./kit";
import { FrameLook } from "./frame";
import { spinner } from "./buttons";
import { CHAR_LIGHT, PLANK_DARK, horizontalDashes, lightFrame, centredY, withAlpha } from "./shapes";

const TOAST_FRAMES: int32 = 120;
const TOAST_FADE_IN_FRAMES: int32 = 8;
const TOAST_FADE_OUT_FRAMES: int32 = 12;
const TOAST_HEIGHT: float32 = 36.0;
// The skill tree's shade: the whole screen steps back behind the line.
const TOAST_SHADE: Color = rgba(0.0, 0.01, 0.03, 0.7);
// One size for every toast; a long line wraps instead of shrinking.
const TOAST_SIZE: float32 = 11.2;
const PILL_HEIGHT: float32 = 20.0;

export interface Toast {
	line: string;
	alert: boolean;
}

// One toast shows at a time; the rest wait in line.
export interface Toasts {
	queue: Toast[];
	framesLeft: int32;
}

export function emptyToasts(): Toasts {
	return { queue: [], framesLeft: 0 };
}

export function pushToast(toasts: Toasts, line: string, alert: boolean): void {
	toasts.queue.push({ line: line, alert: alert });
	if ((toasts.queue.length as int32) == 1) {
		toasts.framesLeft = TOAST_FRAMES;
	}
}

function toastAlpha(toasts: Toasts): float32 {
	const age: int32 = TOAST_FRAMES - toasts.framesLeft;
	return match (age) {
		_ when toasts.framesLeft < TOAST_FADE_OUT_FRAMES => (toasts.framesLeft as float32) / (TOAST_FADE_OUT_FRAMES as float32),
		_ when age < TOAST_FADE_IN_FRAMES => (age as float32) / (TOAST_FADE_IN_FRAMES as float32),
		_ => 1.0,
	};
}

function dropShownToast(toasts: Toasts): void {
	const rest: Toast[] = [];
	for (let position: int32 = 1; position < toasts.queue.length; position += 1) {
		rest.push(toasts.queue[position]);
	}
	toasts.queue = rest;
	toasts.framesLeft = (rest.length as int32) > 0 ? TOAST_FRAMES : 0;
}

// The line alone in the middle, over the whole HUD shaded back; both fade in and out. The shade takes no touches.
export function drawToasts(ui: Ui, kit: Kit, id: int32, toasts: Toasts, x: float32, y: float32, width: float32): void {
	if ((toasts.queue.length as int32) == 0) {
		return;
	}
	const shown: Toast = toasts.queue[0];
	const alpha: float32 = toastAlpha(toasts);
	beginOverlay(ui);
	beginKitOverlay(kit);
	fill(kit, subId(id, 1), 0.0, 0.0, DESIGN_W, DESIGN_H, withAlpha(TOAST_SHADE, TOAST_SHADE.a * alpha));
	const ink: Color = shown.alert ? ALERT_RED : INK;
	const height: float32 = measureWrapped(kit, shown.line, TOAST_SIZE, width).height;
	say(ui, kit, id, shown.line, x, y + (TOAST_HEIGHT - height) * 0.5, width, TOAST_SIZE, withAlpha(ink, alpha), 0.5);
	endKitOverlay(kit);
	endOverlay(ui);
	toasts.framesLeft -= 1;
	if (toasts.framesLeft <= 0) {
		dropShownToast(toasts);
	}
}

// To the left of the anchor (its vertical middle at anchorY), with a small tail pointing at it.
export function tooltip(ui: Ui, kit: Kit, id: int32, anchorX: float32, anchorY: float32, line: string): void {
	const size: TextSize = measure(kit, line, 8.0);
	const width: float32 = size.width + 16.0;
	const height: float32 = 24.0;
	const x: float32 = anchorX - width - 6.0;
	const y: float32 = anchorY - height * 0.5;
	lightFrame(ui, x, y, width, height, CHAR_LIGHT);
	for (let step: int32 = 0; step < 4; step += 1) {
		const offset: float32 = step as float32;
		box(ui, x + width + offset, anchorY - 3.0 + offset, 1.0, 6.0 - 2.0 * offset, 0.0, CHAR_LIGHT);
	}
	say(ui, kit, id, line, x + 8.0, centredY(kit, line, 8.0, y, height), size.width + 2.0, 8.0, INK, 0.0);
}

// The one-line reason under a card. Returns its width.
export function reasonPill(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, line: string, alert: boolean): float32 {
	const size: TextSize = measure(kit, line, 8.0);
	const width: float32 = size.width + 30.0;
	lightFrame(ui, x, y, width, PILL_HEIGHT, alert ? ALERT_RED : CHAR_LIGHT);
	iconTinted(kit, id, "warning", x + 6.0, y + 4.0, 12.0, alert ? WHITE : DIMMED);
	say(ui, kit, id, line, x + 22.0, centredY(kit, line, 8.0, y, PILL_HEIGHT), size.width + 2.0, 8.0, alert ? ALERT_RED : INK, 0.0);
	return width;
}

// While a signature is out: what is being signed, under "confirm in your wallet".
export function walletBanner(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, detail: string, seed: int32,
	tick: int32): void {
	frame(kit, id, x, y, width, 52.0, seed, FrameLook.Normal);
	spinner(ui, x + 14.0, y + 18.0, 16.0, tick);
	say(ui, kit, id, "CONFIRM IN YOUR WALLET", x + 40.0, y + 15.0, width - 50.0, 8.0, EMBER_HOT, 0.0);
	say(ui, kit, subId(id, 0), detail, x + 40.0, y + 29.0, width - 50.0, 8.0, INK_MUTED, 0.0);
}

// "SYNCING..." with a spinner, or "OFFLINE - 3 MIN AGO" with a dim dot. Returns its width.
export function syncChip(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, line: string, syncing: boolean, tick: int32): float32 {
	const size: TextSize = measure(kit, line, 8.0);
	const width: float32 = size.width + 30.0;
	box(ui, x, y, width, PILL_HEIGHT, 0.0, PLANK_DARK);
	horizontalDashes(ui, x, y, width, 3.0, 5.0, CHAR_LIGHT);
	horizontalDashes(ui, x, y + PILL_HEIGHT - 1.0, width, 3.0, 5.0, CHAR_LIGHT);
	box(ui, x, y, 1.0, PILL_HEIGHT, 0.0, CHAR_LIGHT);
	box(ui, x + width - 1.0, y, 1.0, PILL_HEIGHT, 0.0, CHAR_LIGHT);
	if (syncing) {
		spinner(ui, x + 5.0, y + 2.0, 16.0, tick);
	} else {
		box(ui, x + 10.0, y + 8.0, 4.0, 4.0, 0.0, DISABLED_INK);
	}
	say(ui, kit, id, line, x + 24.0, centredY(kit, line, 8.0, y, PILL_HEIGHT), size.width + 2.0, 8.0, syncing ? INK : INK_MUTED, 0.0);
	return width;
}
