// Both open the overlay layer (ui and kit) and leave it open so the caller's content lands on
// top; the caller ends it with endOverlay and endKitOverlay.

import { rgba } from "@metascript/void/src/void2d/types";
import { Ui, box, pressable, beginOverlay } from "../ui/ui";
import { Kit, TextSize, subId, beginKitOverlay, measure, measureWrapped, frame, say, INK, INK_MUTED, SCREEN_WIDTH,
	SCREEN_HEIGHT } from "./kit";
import { FrameLook } from "./frame";
import { ButtonStyle, button, textLink } from "./buttons";
import { CHAR_LIGHT } from "./shapes";

const HALF: float32 = 0.5;
const MODAL_WIDTH: float32 = 296.0;
const FULLY_OPEN: float32 = 0.95;

export enum ModalAnswer {
	None,
	Cancel,
	Confirm,
}

export function sheetTop(height: float32, open: float32): float32 {
	return SCREEN_HEIGHT - height * open;
}

// `open` slides it from 0 (hidden) to 1 (up); the scene behind is dimmed and the bottom rim sits
// off-screen. True when the dimmed scene is tapped, which closes it.
export function sheet(ui: Ui, kit: Kit, id: int32, height: float32, open: float32, seed: int32): boolean {
	beginOverlay(ui);
	beginKitOverlay(kit);
	if (open <= 0.0) {
		return false;
	}
	const top: float32 = sheetTop(height, open);
	box(ui, 0.0, 0.0, SCREEN_WIDTH, top, 0.0, rgba(0.02, 0.02, 0.04, 0.55 * open));
	// While it slides, the dimmed area is under the finger that opened it.
	const closed: boolean = open > FULLY_OPEN && pressable(ui, id, 0.0, 0.0, SCREEN_WIDTH, top - 4.0);
	frame(kit, id, 4.0, top, SCREEN_WIDTH - 8.0, height + 24.0, seed, FrameLook.Normal);
	box(ui, 162.0, top + 10.0, 36.0, 3.0, 0.0, CHAR_LIGHT);
	box(ui, 162.0, top + 10.0, 36.0, 1.0, 0.0, rgba(0.55, 0.36, 0.27, 1.0));
	return closed;
}

// Centred over a dimmed screen that swallows taps; the body wraps. A destructive confirm is red.
export function modal(ui: Ui, kit: Kit, id: int32, title: string, body: string, confirm: string, destructive: boolean,
	seed: int32): ModalAnswer {
	beginOverlay(ui);
	beginKitOverlay(kit);
	box(ui, 0.0, 0.0, SCREEN_WIDTH, SCREEN_HEIGHT, 0.0, rgba(0.02, 0.02, 0.04, 0.6));
	pressable(ui, subId(id, 0), 0.0, 0.0, SCREEN_WIDTH, SCREEN_HEIGHT);
	const x: float32 = (SCREEN_WIDTH - MODAL_WIDTH) * HALF;
	const bodySize: TextSize = measureWrapped(kit, body, 8.0, MODAL_WIDTH - 40.0);
	const height: float32 = 40.0 + 20.0 + bodySize.height + 24.0 + 44.0 + 16.0;
	const y: float32 = (SCREEN_HEIGHT - height) * HALF - 20.0;
	frame(kit, id, x, y, MODAL_WIDTH, height, seed, FrameLook.Normal);
	say(ui, kit, subId(id, 1), title, x + 20.0, y + 26.0, MODAL_WIDTH - 40.0, 16.0, INK, 0.5);
	say(ui, kit, subId(id, 2), body, x + 20.0, y + 60.0, MODAL_WIDTH - 40.0, 8.0, INK_MUTED, 0.5);
	const buttonsY: float32 = y + height - 64.0;
	const cancelWidth: float32 = measure(kit, "CANCEL", 8.0).width;
	const cancelled: boolean = textLink(ui, kit, subId(id, 3), x + 30.0 + (100.0 - cancelWidth) * HALF, buttonsY + 18.0, "CANCEL",
		true);
	const style: ButtonStyle = destructive ? ButtonStyle.Danger : ButtonStyle.Primary;
	const confirmed: boolean = button(ui, kit, subId(id, 4), x + MODAL_WIDTH - 156.0, buttonsY, 136.0, 44.0, confirm, style, true,
		seed + 1);
	return confirmed ? ModalAnswer.Confirm : (cancelled ? ModalAnswer.Cancel : ModalAnswer.None);
}
