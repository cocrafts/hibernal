// The Home screen's one bar: the pet's level, its XP towards the next level, and its six-slot
// inventory, numbered; an empty slot shows a plus. Pieces from assets/hud/pieces/ (art/hud/cutHud.py); positions in
// design units from the bar's top-left, after art/hud/hotbarMockup.png.

import { Ui, box, pressable } from "../ui/ui";
import { Kit, PieceLayer, piece, pieceWidth, pieceHeight, say, subId } from "./kit";
import { Color, rgba } from "@metascript/void/src/void2d/types";

export const HOTBAR_HEIGHT: float32 = 102.0;
export const NO_SLOT: int32 = -1;

export enum HotbarTapKind {
	Nothing,
	Menu,
	Slot,
}

// `slot` is the tapped slot (0 to 5) for Slot, NO_SLOT otherwise.
export struct HotbarTap {
	kind: HotbarTapKind;
	slot: int32;
}

const INK_BRIGHT: Color = rgba(0.92, 0.96, 1.0, 1.0);
const TRACK: Color = rgba(0.055, 0.204, 0.376, 1.0);
const FILL: Color = rgba(0.314, 0.706, 0.941, 1.0);

const PLATE_X: float32 = 12.3;
const PLATE_Y: float32 = 10.7;
const PANEL_X: float32 = 64.7;
const PANEL_Y: float32 = 23.1;
const PLATE_CENTRE_X: float32 = 39.6;
const XP_FRAME_X: float32 = 67.1;
const XP_FRAME_Y: float32 = 26.6;
const TRACK_X: float32 = 74.2;
const TRACK_Y: float32 = 30.2;
const TRACK_WIDTH: float32 = 76.8;
const TRACK_HEIGHT: float32 = 6.7;
const XP_TEXT_CENTRE_X: float32 = 196.0;
const XP_TEXT_CENTRE_Y: float32 = 33.1;
const XP_TEXT_SIZE: float32 = 8.0;
const HATCH_X: float32 = 242.6;
const HATCH_Y: float32 = 29.2;
const DOTS_X: float32 = 310.3;
const DOTS_Y: float32 = 31.4;
const DOT_STEP: float32 = 4.6;
const SLOT_X: float32 = 70.2;
const SLOT_Y: float32 = 44.5;
const SLOT_STEP: float32 = 43.0;
const TAB_Y: float32 = 87.5;
const END_CAP_X: float32 = 331.1;
const END_CAP_Y: float32 = 17.8;
export const HOTBAR_SLOTS: int32 = 6;
// A slot's entry in hotbar()'s `slots` when it holds nothing.
export const EMPTY_SLOT: string = "";

// The bar's outline from its top-left: the level plate on the left and top, the end cap on the right.
export function hotbarLeft(): float32 {
	return PLATE_X;
}

export function hotbarTopEdge(): float32 {
	return PLATE_Y;
}

// The XP frame's left edge and width, and the top of the panel behind the XP frame and slots.
export function hotbarXpLeft(): float32 {
	return XP_FRAME_X;
}

export function hotbarXpWidth(kit: Kit): float32 {
	return pieceWidth(kit, "xpFrame");
}

export function hotbarPanelTop(): float32 {
	return PANEL_Y;
}

export function hotbarRight(kit: Kit): float32 {
	return END_CAP_X + pieceWidth(kit, "endCap");
}

function centredText(ui: Ui, kit: Kit, id: int32, line: string, centreX: float32, centreY: float32, width: float32,
	size: float32): void {
	say(ui, kit, id, line, centreX - width * 0.5, centreY - size * 0.625, width, size, INK_BRIGHT, 0.5);
}

// `slots` holds HOTBAR_SLOTS item piece names, EMPTY_SLOT for an empty one.
export function hotbar(ui: Ui, kit: Kit, id: int32, y: float32, level: int32, xp: int32, xpToNext: int32, slots: string[]): HotbarTap {
	if (slots.length != HOTBAR_SLOTS) {
		console.log("hotbar: " + (slots.length as int32).toString() + " slots, not " + HOTBAR_SLOTS.toString());
		unreachable;
	}
	let result: HotbarTap = { kind: HotbarTapKind.Nothing, slot: NO_SLOT };
	piece(kit, subId(id, 0), PieceLayer.Frames, "panel", PANEL_X, y + PANEL_Y);
	piece(kit, subId(id, 1), PieceLayer.Frames, "xpFrame", XP_FRAME_X, y + XP_FRAME_Y);
	const share: float32 = xpToNext > 0 ? Math.min(1.0, (xp as float32) / (xpToNext as float32)) as float32 : (0.0 as float32);
	box(ui, TRACK_X, y + TRACK_Y, TRACK_WIDTH, TRACK_HEIGHT, 0.0, TRACK);
	box(ui, TRACK_X, y + TRACK_Y, TRACK_WIDTH * share, TRACK_HEIGHT, 0.0, FILL);
	centredText(ui, kit, subId(id, 2), xp.toString() + "/" + xpToNext.toString(), XP_TEXT_CENTRE_X, y + XP_TEXT_CENTRE_Y,
		120.0, XP_TEXT_SIZE);
	piece(kit, subId(id, 3), PieceLayer.Icons, "hatch", HATCH_X, y + HATCH_Y);
	for (let dot: int32 = 0; dot < 3; dot += 1) {
		piece(kit, subId(id + 1, dot), PieceLayer.Icons, "dot", DOTS_X + DOT_STEP * (dot as float32), y + DOTS_Y);
	}
	const slotWidth: float32 = pieceWidth(kit, "slot");
	const slotHeight: float32 = pieceHeight(kit, "slot");
	const tabWidth: float32 = pieceWidth(kit, "tab");
	const tabHeight: float32 = pieceHeight(kit, "tab");
	for (let slot: int32 = 0; slot < HOTBAR_SLOTS; slot += 1) {
		const slotX: float32 = SLOT_X + SLOT_STEP * (slot as float32);
		const plus: boolean = slots[slot] == EMPTY_SLOT;
		piece(kit, subId(id + 2, slot), PieceLayer.Frames, plus ? "plusSlot" : "slot", slotX, y + SLOT_Y);
		if (pressable(ui, subId(id + 6, slot), slotX, y + SLOT_Y, slotWidth, slotHeight)) {
			result = { kind: HotbarTapKind.Slot, slot: slot };
		}
		if (!plus) {
			const item: string = slots[slot];
			piece(kit, subId(id + 3, slot), PieceLayer.Icons, item, slotX + (slotWidth - pieceWidth(kit, item)) * 0.5,
				y + SLOT_Y + (slotHeight - pieceHeight(kit, item)) * 0.5);
		}
		piece(kit, subId(id + 4, slot), PieceLayer.Frames, "tab", slotX + (slotWidth - tabWidth) * 0.5, y + TAB_Y);
		centredText(ui, kit, subId(id + 5, slot), (slot + 1).toString(), slotX + slotWidth * 0.5, y + TAB_Y + tabHeight * 0.5,
			tabWidth, 12.0);
	}
	piece(kit, subId(id, 4), PieceLayer.Frames, "levelPlate", PLATE_X, y + PLATE_Y);
	centredText(ui, kit, subId(id, 5), level.toString(), PLATE_CENTRE_X, y + 33.5, 50.0, 16.0);
	centredText(ui, kit, subId(id, 6), "LVL", PLATE_CENTRE_X, y + 45.5, 50.0, 8.0);
	piece(kit, subId(id, 7), PieceLayer.Frames, "endCap", END_CAP_X, y + END_CAP_Y);
	if (pressable(ui, subId(id, 8), END_CAP_X, y + END_CAP_Y, pieceWidth(kit, "endCap"), pieceHeight(kit, "endCap"))) {
		result = { kind: HotbarTapKind.Menu, slot: NO_SLOT };
	}
	return result;
}
