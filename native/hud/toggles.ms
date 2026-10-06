// A label and its checkbox to the right of it: the box's look from assets/hud/pieces/toggle*
// (art/hud/cutHud.py TOGGLE_*), held while pressed, dimmed when disabled. Rows with the same
// right edge share the boxes' column.

import { Ui, pressable, held } from "../ui/ui";
import { Kit, PieceLayer, TextSize, INK, DISABLED_INK, piece, pieceWidth, pieceHeight, say, measure, subId }
	from "./kit";

const LABEL_SIZE: float32 = 8.0;
const LABEL_GAP: float32 = 5.0;

function lookOf(on: boolean, down: boolean, enabled: boolean): string {
	if (!enabled) { return "toggleDisabled"; }
	if (on) { return "toggleOn"; }
	return down ? "toggleHeld" : "toggleOff";
}

// True in the frame the row is tapped; `right` is the box's right edge, `y` the top of the row,
// which is `height` tall (TOUCH_HEIGHT alone, STACKED_ROW_HEIGHT in a column) with the box and
// the label centred in it.
export function toggleRow(ui: Ui, kit: Kit, id: int32, right: float32, y: float32, height: float32, label: string, on: boolean,
	enabled: boolean): boolean {
	const text: TextSize = measure(kit, label, LABEL_SIZE);
	const boxWidth: float32 = pieceWidth(kit, "toggleOff");
	const boxHeight: float32 = pieceHeight(kit, "toggleOff");
	const boxLeft: float32 = right - boxWidth;
	const boxTop: float32 = y + (height - boxHeight) * 0.5;
	const left: float32 = boxLeft - LABEL_GAP - text.width;
	const width: float32 = right - left;
	const tapped: boolean = pressable(ui, subId(id, 0), left, y, width, height) && enabled;
	const down: boolean = held(ui, subId(id, 0), left, y, width, height);
	piece(kit, subId(id, 1), PieceLayer.Icons, lookOf(on, down, enabled), boxLeft, boxTop);
	say(ui, kit, subId(id, 2), label, left, y + height * 0.5 - LABEL_SIZE * 0.625, text.width + 2.0, LABEL_SIZE,
		enabled ? INK : DISABLED_INK, 0.0);
	return tapped;
}
