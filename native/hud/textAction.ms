// A label and a glyph piece to the right of it, tapped as one; the label brightens while pressed.

import { Ui, pressable, held } from "../ui/ui";
import { Kit, PieceLayer, TextSize, INK, INK_BRIGHT, piece, pieceWidth, pieceHeight, say, measure, subId }
	from "./kit";

const LABEL_SIZE: float32 = 8.0;
const GLYPH_GAP: float32 = 5.0;

// True in the frame the row is tapped; `right` is the glyph's right edge, `y` the top of the row,
// which is `height` tall (TOUCH_HEIGHT alone, STACKED_ROW_HEIGHT in a column) with the glyph and
// the label centred in it.
export function textAction(ui: Ui, kit: Kit, id: int32, right: float32, y: float32, height: float32, label: string,
	glyph: string): boolean {
	const text: TextSize = measure(kit, label, LABEL_SIZE);
	const glyphLeft: float32 = right - pieceWidth(kit, glyph);
	const left: float32 = glyphLeft - GLYPH_GAP - text.width;
	const width: float32 = right - left;
	const tapped: boolean = pressable(ui, subId(id, 0), left, y, width, height);
	const down: boolean = held(ui, subId(id, 0), left, y, width, height);
	piece(kit, subId(id, 1), PieceLayer.Icons, glyph, glyphLeft, y + (height - pieceHeight(kit, glyph)) * 0.5);
	say(ui, kit, subId(id, 2), label, left, y + height * 0.5 - LABEL_SIZE * 0.625, text.width + 2.0, LABEL_SIZE,
		down ? INK_BRIGHT : INK, 0.0);
	return tapped;
}
