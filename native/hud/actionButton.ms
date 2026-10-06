// A tap button drawn as one piece, `look` and `look + "Held"` while pressed (art/hud/cutHud.py
// WALLPAPER_BUTTONS), its label centred on it.

import { Ui, pressable, held } from "../ui/ui";
import { Kit, PieceLayer, INK_BRIGHT, TOUCH_HEIGHT, piece, pieceWidth, pieceHeight, say, subId } from "./kit";

const LABEL_SIZE: float32 = 8.0;

// True in the frame the button is tapped; `right` is the piece's right edge, `y` the top of the
// tap area, which is TOUCH_HEIGHT tall with the piece centred in it.
export function actionButton(ui: Ui, kit: Kit, id: int32, look: string, right: float32, y: float32, label: string): boolean {
	const width: float32 = pieceWidth(kit, look);
	const height: float32 = pieceHeight(kit, look);
	const left: float32 = right - width;
	const tapped: boolean = pressable(ui, subId(id, 0), left, y, width, TOUCH_HEIGHT);
	const down: boolean = held(ui, subId(id, 0), left, y, width, TOUCH_HEIGHT);
	piece(kit, subId(id, 1), PieceLayer.Frames, down ? look + "Held" : look, left, y + (TOUCH_HEIGHT - height) * 0.5);
	say(ui, kit, subId(id, 2), label, left, y + TOUCH_HEIGHT * 0.5 - LABEL_SIZE * 0.625, width, LABEL_SIZE, INK_BRIGHT, 0.5);
	return tapped;
}
