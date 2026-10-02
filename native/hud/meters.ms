import { Color, rgba } from "@metascript/void/src/void2d/types";
import { Ui, box } from "../ui/ui";
import { Kit, subId, icon, say, INK, INK_MUTED, ALERT_RED, GROWTH_GREEN } from "./kit";
import { RARE_BLUE } from "./rarity";

const HEART_ID_BASE: int32 = 2000000;
const TRACK: Color = rgba(0.11, 0.09, 0.09, 1.0);
const TRACK_RIM: Color = rgba(0.275, 0.251, 0.243, 1.0);
const HATCH: Color = rgba(0.20, 0.15, 0.14, 1.0);
const HEARTS_PER_ROW: int32 = 10;
const MOST_HEART_PIPS: int32 = 20;
const BONDING_MAX: float32 = 127.0;
const BONDING_ZONE_SHARE: float32 = 0.18;

// Two rows of ten at most; past twenty, one heart and "n/max".
export function heartPips(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, hearts: int32, max: int32, size: float32): void {
	if (max > MOST_HEART_PIPS) {
		icon(kit, id, "heart", x, y, size);
		say(ui, kit, id, hearts.toString() + "/" + max.toString(), x + size + 4.0, y + (size - 8.0) * 0.5, 80.0, 8.0, INK, 0.0);
		return;
	}
	const step: float32 = size + 2.0;
	for (let pip: int32 = 0; pip < max; pip += 1) {
		const column: float32 = (pip % HEARTS_PER_ROW) as float32;
		const row: float32 = (pip / HEARTS_PER_ROW) as float32;
		icon(kit, HEART_ID_BASE + id * 32 + pip, pip < hearts ? "heart" : "crackedHeart", x + column * step, y + row * step, size);
	}
}

// `value` is 0..1; no spark at the end of the fill.
export function bar(ui: Ui, x: float32, y: float32, width: float32, height: float32, value: float32, fill: Color): void {
	const clamped: float32 = value < 0.0 ? 0.0 : (value > 1.0 ? 1.0 : value);
	box(ui, x, y, width, height, 0.0, TRACK_RIM);
	box(ui, x + 1.0, y + 1.0, width - 2.0, height - 2.0, 0.0, TRACK);
	if (clamped > 0.0) {
		box(ui, x + 1.0, y + 1.0, (width - 2.0) * clamped, height - 2.0, 0.0, fill);
	}
}

// Bonding runs -127..127 and fills from the centre; the hatched ends are where the pet refuses
// food and where it gives gifts.
export function bondingBar(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, value: int32): void {
	const height: float32 = 8.0;
	bar(ui, x, y, width, height, 0.0, TRACK);
	const zone: float32 = width * BONDING_ZONE_SHARE;
	let hatch: float32 = 2.0;
	while (hatch < zone - 2.0) {
		box(ui, x + hatch, y + 2.0, 1.0, height - 4.0, 0.0, HATCH);
		box(ui, x + width - hatch - 1.0, y + 2.0, 1.0, height - 4.0, 0.0, HATCH);
		hatch += 3.0;
	}
	const middle: float32 = x + width * 0.5;
	const marker: float32 = middle + (width * 0.5 - 2.0) * ((value as float32) / BONDING_MAX);
	const fill: Color = value >= 0 ? RARE_BLUE : ALERT_RED;
	const fillStart: float32 = marker > middle ? middle : marker;
	const fillLength: float32 = marker > middle ? marker - middle : middle - marker;
	box(ui, fillStart, y + 2.0, fillLength, height - 4.0, 0.0, fill);
	box(ui, middle - 0.5, y - 2.0, 1.0, height + 4.0, 0.0, INK_MUTED);
	box(ui, marker - 1.0, y - 3.0, 2.0, height + 6.0, 0.0, INK);
	say(ui, kit, subId(id, 0), "REFUSES", x, y + height + 4.0, width * 0.5, 8.0, INK_MUTED, 0.0);
	say(ui, kit, subId(id, 1), "GIFTS", x + width * 0.5, y + height + 4.0, width * 0.5, 8.0, INK_MUTED, 1.0);
}

// `badge` (e.g. "warning" on the harvest bag) sits small on the icon's corner.
export function balance(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, glyph: string, badge: string,
	amount: string): void {
	icon(kit, id, glyph, x, y, 14.0);
	if (badge != "") {
		icon(kit, id, badge, x + 7.0, y + 6.0, 9.0);
	}
	say(ui, kit, id, amount, x + 20.0, y + 3.0, width - 20.0, 8.0, INK, 1.0);
}

export function signedAmount(value: int32): string {
	return value > 0 ? "+" + value.toString() : value.toString();
}

// "+280" green, "-310" red.
export function delta(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, value: int32, align: float32): void {
	const color: Color = value > 0 ? GROWTH_GREEN : (value < 0 ? ALERT_RED : INK_MUTED);
	say(ui, kit, id, signedAmount(value), x, y, width, 8.0, color, align);
}
