// The pet's stats in the top-right corner, one bar each: badge and plug on the right, the fill
// growing leftwards out of the badge. Pieces assets/hud/pieces/stat*; the sheet-pixel positions
// below are cutHud.py's STAT_* layout, scaled by STAT_WIDTH / STAT_CANVAS width.

import { Kit, PieceLayer, piece, pieceSized, pieceWidth, pieceHeight, subId } from "./kit";

export enum StatColour {
	Red,
	Blue,
	Green,
	Orange,
}

export struct Stat {
	colour: StatColour;
	icon: string;
	share: float32;
}

export const STAT_BAR_WIDTH: float32 = 70.0;
const SCALE: float32 = STAT_BAR_WIDTH / 612.0;
const ROW_STEP: float32 = 173.0 * SCALE;
const BADGE_X: float32 = 342.0 * SCALE;
const ICON_CENTRE_X: float32 = 429.0 * SCALE;
const ICON_CENTRE_Y: float32 = 84.0 * SCALE;
const FILL_X: float32 = 52.0 * SCALE;
const FILL_Y: float32 = 63.0 * SCALE;
const FILL_ANCHOR: float32 = 352.0 * SCALE;

function fillName(colour: StatColour): string {
	return match (colour) {
		StatColour.Red => "statFillRed",
		StatColour.Blue => "statFillBlue",
		StatColour.Green => "statFillGreen",
		StatColour.Orange => "statFillOrange",
	};
}

function statBar(kit: Kit, id: int32, x: float32, y: float32, stat: Stat): void {
	if (stat.share < 0.0 || stat.share > 1.0) {
		console.log("statBars: " + stat.icon + " share " + stat.share.toString() + " is outside 0..1");
		unreachable;
	}
	piece(kit, subId(id, 0), PieceLayer.Frames, "statFrame", x, y);
	const end: string = fillName(stat.colour) + "End";
	const body: string = fillName(stat.colour) + "Body";
	const width: float32 = (FILL_ANCHOR - FILL_X) * stat.share;
	const left: float32 = x + FILL_ANCHOR - width;
	const endWidth: float32 = Math.min(pieceWidth(kit, end), width) as float32;
	const height: float32 = pieceHeight(kit, end);
	pieceSized(kit, subId(id, 1), PieceLayer.Icons, end, left, y + FILL_Y, endWidth, height);
	pieceSized(kit, subId(id, 2), PieceLayer.Icons, body, left + endWidth, y + FILL_Y, width - endWidth, height);
	piece(kit, subId(id, 3), PieceLayer.Icons, "statBadge", x + BADGE_X, y);
	piece(kit, subId(id, 4), PieceLayer.Icons, stat.icon, x + ICON_CENTRE_X - pieceWidth(kit, stat.icon) * 0.5,
		y + ICON_CENTRE_Y - pieceHeight(kit, stat.icon) * 0.5);
}

export function statBarsHeight(rows: int32): float32 {
	return ROW_STEP * (rows as float32);
}

// `right` and `top` place the stack's top-right corner; one id per row from `id` on.
export function statBars(kit: Kit, id: int32, right: float32, top: float32, stats: Stat[]): void {
	for (let row: int32 = 0; row < stats.length; row += 1) {
		statBar(kit, id + row, right - STAT_BAR_WIDTH, top + ROW_STEP * (row as float32), stats[row]);
	}
}
