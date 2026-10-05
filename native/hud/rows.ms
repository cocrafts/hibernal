import { Color, rgba } from "@metascript/void/src/void2d/types";
import { Ui, box, pressable, held } from "../ui/ui";
import {
	Kit,
	TextSize,
	subId,
	measure,
	iconTinted,
	say,
	INK,
	INK_MUTED,
	EMBER_HOT,
	ALERT_RED,
	DISABLED_INK,
	ASH_DEEP,
	DIMMED,
	WHITE,
} from "./kit";
import { CHAR_MID, CHAR_LIGHT, dashedOutline, centredY } from "./shapes";

const SELECTED_FILL: Color = rgba(0.733, 0.682, 0.675, 1.0);
const PRESSED_FILL: Color = rgba(1.0, 0.6, 0.3, 0.08);
const SKELETON_BAR: Color = rgba(0.16, 0.12, 0.11, 0.9);
const SKELETON_LIGHT: Color = rgba(0.30, 0.22, 0.19, 0.9);
const SKELETON_SWEEP_FRAMES: int32 = 60;
const EMPTY_FILL: Color = rgba(0.06, 0.05, 0.05, 0.7);

export enum RowKind {
	Plain,
	Selected,
	Destructive,
	Locked,
}

function rowInk(kind: RowKind): Color {
	return match (kind) {
		RowKind.Plain => INK,
		RowKind.Selected => ASH_DEEP,
		RowKind.Destructive => ALERT_RED,
		RowKind.Locked => DISABLED_INK,
	};
}

// Frameless, with a thin divider under it; a selected row is inverted. Settings rows are tall
// (56), the rest 48. True on a tap.
export function listRow(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, glyph: string, label: string,
	value: string, valueColor: Color, kind: RowKind, chevron: boolean, tall: boolean): boolean {
	const height: float32 = tall ? 56.0 : 48.0;
	const locked: boolean = kind == RowKind.Locked;
	const selected: boolean = kind == RowKind.Selected;
	const tapped: boolean = pressable(ui, id, x, y, width, height) && !locked;
	const down: boolean = !locked && held(ui, id, x, y, width, height);
	if (selected) {
		box(ui, x, y, width, height - 1.0, 0.0, SELECTED_FILL);
	} else if (down) {
		box(ui, x, y, width, height - 1.0, 0.0, PRESSED_FILL);
	}
	if (glyph != "") {
		iconTinted(kit, id, glyph, x + 8.0, y + (height - 16.0) * 0.5, 16.0, locked ? DIMMED : WHITE);
	}
	const textX: float32 = glyph != "" ? x + 32.0 : x + 8.0;
	const textY: float32 = centredY(kit, label, 8.0, y, height);
	say(ui, kit, id, label, textX, textY, width * 0.6, 8.0, rowInk(kind), 0.0);
	const right: float32 = x + width - (chevron || locked ? (22.0 as float32) : (8.0 as float32));
	if (value != "") {
		say(ui, kit, subId(id, 0), value, x + width * 0.4, textY, right - x - width * 0.4, 8.0, selected ? ASH_DEEP : valueColor, 1.0);
	}
	if (locked) {
		iconTinted(kit, subId(id, 1), "lock", x + width - 18.0, y + (height - 12.0) * 0.5, 12.0, DIMMED);
	} else if (chevron) {
		say(ui, kit, subId(id, 2), ">", x + width - 16.0, textY, 12.0, 8.0, selected ? ASH_DEEP : INK_MUTED, 0.0);
	}
	box(ui, x, y + height - 1.0, width, 1.0, 0.0, CHAR_MID);
	return tapped;
}

export function sectionHeader(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, title: string, right: string): void {
	say(ui, kit, id, title, x, y, width * 0.6, 8.0, EMBER_HOT, 0.0);
	if (right != "") {
		say(ui, kit, subId(id, 0), right, x + width * 0.4, y, width * 0.6, 8.0, INK_MUTED, 1.0);
	}
	box(ui, x, y + 14.0, width, 1.0, 0.0, CHAR_MID);
}

// "NEW SINCE 23:10", "SEEN": the label sits in the middle of the line.
export function labelDivider(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, label: string, color: Color): void {
	const size: TextSize = measure(kit, label, 8.0);
	const labelX: float32 = x + (width - size.width) * 0.5;
	box(ui, x, y + 4.0, labelX - x - 6.0, 1.0, 0.0, color);
	box(ui, labelX + size.width + 6.0, y + 4.0, x + width - labelX - size.width - 6.0, 1.0, 0.0, color);
	say(ui, kit, id, label, labelX, y, size.width + 2.0, 8.0, color, 0.0);
}

// A dim bar whose light sweeps left to right.
export function skeleton(ui: Ui, x: float32, y: float32, width: float32, height: float32, tick: int32): void {
	box(ui, x, y, width, height, 0.0, SKELETON_BAR);
	const sweep: float32 = ((tick % SKELETON_SWEEP_FRAMES) as float32) / (SKELETON_SWEEP_FRAMES as float32);
	const lightWidth: float32 = width * 0.3;
	const lightStart: float32 = x - lightWidth + (width + lightWidth) * sweep;
	const start: float32 = lightStart < x ? x : lightStart;
	const end: float32 = lightStart + lightWidth > x + width ? x + width : lightStart + lightWidth;
	if (end > start) {
		box(ui, start, y, end - start, height, 0.0, SKELETON_LIGHT);
	}
}

// Nothing yet, hidden, not attackable, a dead slot.
export function emptyState(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, height: float32, glyph: string,
	line: string): void {
	box(ui, x, y, width, height, 0.0, EMPTY_FILL);
	dashedOutline(ui, x, y, width, height, 4.0, 7.0, CHAR_LIGHT);
	if (glyph == "") {
		say(ui, kit, id, line, x + 8.0, centredY(kit, line, 8.0, y, height), width - 16.0, 8.0, INK_MUTED, 0.5);
		return;
	}
	iconTinted(kit, id, glyph, x + (width - 20.0) * 0.5, y + height * 0.5 - 18.0, 20.0, DIMMED);
	say(ui, kit, id, line, x + 8.0, y + height * 0.5 + 8.0, width - 16.0, 8.0, INK_MUTED, 0.5);
}
