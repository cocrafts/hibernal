import { Color, rgba } from "@metascript/void/src/void2d/types";
import { Ui, box } from "../ui/ui";
import { Kit, TextSize, measure, say } from "./kit";
import { ChipKind, chip } from "./buttons";
import { outline, withAlpha } from "./shapes";

export const RARE_BLUE: Color = rgba(0.478, 0.675, 0.843, 1.0);
export const EPIC_PURPLE: Color = rgba(0.745, 0.439, 0.894, 1.0);
export const LEGENDARY_GOLD: Color = rgba(0.910, 0.678, 0.318, 1.0);
export const MYTHIC_CYAN: Color = rgba(0.439, 0.765, 0.788, 1.0);
export const COMMON_ASH: Color = rgba(0.576, 0.549, 0.522, 1.0);
// The warm bone of the reference's plate: grey would read as disabled.
export const COMMON_BONE: Color = rgba(0.851, 0.663, 0.510, 1.0);
const PLATE: Color = rgba(0.094, 0.071, 0.063, 1.0);
const PLATE_FACE: Color = rgba(0.094, 0.071, 0.063, 0.96);
const PLATE_SEAM: Color = rgba(0.055, 0.043, 0.039, 0.9);
const SMALLEST_ORNAMENTED: float32 = 30.0;

export enum Rarity {
	Common,
	Rare,
	Epic,
	Legendary,
	Mythic,
}

export function rarityColor(rarity: Rarity): Color {
	return match (rarity) {
		Rarity.Common => COMMON_BONE,
		Rarity.Rare => RARE_BLUE,
		Rarity.Epic => EPIC_PURPLE,
		Rarity.Legendary => LEGENDARY_GOLD,
		Rarity.Mythic => MYTHIC_CYAN,
	};
}

export function rarityName(rarity: Rarity): string {
	return match (rarity) {
		Rarity.Common => "COMMON",
		Rarity.Rare => "RARE",
		Rarity.Epic => "EPIC",
		Rarity.Legendary => "LEGENDARY",
		Rarity.Mythic => "MYTHIC",
	};
}

export function rarityChip(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, rarity: Rarity): float32 {
	return chip(ui, kit, id, x, y, rarityName(rarity), ChipKind.Outline, rarityColor(rarity));
}

interface Corner {
	x: float32;
	y: float32;
	// +1 or -1: which way the corner's arms run
	stepX: float32;
	stepY: float32;
}

function cornerDot(ui: Ui, corner: Corner, along: float32, down: float32, color: Color): void {
	const x: float32 = corner.stepX > 0.0 ? corner.x + along : corner.x - along - 1.0;
	const y: float32 = corner.stepY > 0.0 ? corner.y + down : corner.y - down - 1.0;
	box(ui, x, y, 1.0, 1.0, 0.0, color);
}

// A chamfered tip, a bright outer bracket over a dim inner one, a diamond with a light core
// where the bracket turns, and a bead past each bracket end.
function cornerOrnament(ui: Ui, corner: Corner, color: Color): void {
	const dim: Color = withAlpha(color, 0.5);
	const light: Color = rgba(color.r * 0.5 + 0.5, color.g * 0.5 + 0.5, color.b * 0.5 + 0.5, 1.0);
	cornerDot(ui, corner, 0.0, 0.0, PLATE);
	cornerDot(ui, corner, 1.0, 0.0, withAlpha(color, 0.45));
	cornerDot(ui, corner, 0.0, 1.0, withAlpha(color, 0.45));
	cornerDot(ui, corner, 1.0, 1.0, color);
	for (let step: int32 = 0; step < 6; step += 1) {
		const along: float32 = 3.0 + (step as float32);
		cornerDot(ui, corner, along, 3.0, color);
		cornerDot(ui, corner, 3.0, along, color);
	}
	for (let step: int32 = 0; step < 3; step += 1) {
		const along: float32 = 4.0 + (step as float32);
		cornerDot(ui, corner, along, 4.0, dim);
		cornerDot(ui, corner, 4.0, along, dim);
	}
	cornerDot(ui, corner, 6.0, 5.0, color);
	cornerDot(ui, corner, 5.0, 6.0, color);
	cornerDot(ui, corner, 7.0, 6.0, color);
	cornerDot(ui, corner, 6.0, 7.0, color);
	cornerDot(ui, corner, 6.0, 6.0, light);
	cornerDot(ui, corner, 10.0, 3.0, color);
	cornerDot(ui, corner, 3.0, 10.0, color);
	cornerDot(ui, corner, 12.0, 3.0, dim);
	cornerDot(ui, corner, 3.0, 12.0, dim);
}

// For plates, the talent card face and item reveals.
export function rarityBorder(ui: Ui, x: float32, y: float32, width: float32, height: float32, rarity: Rarity): void {
	const color: Color = rarityColor(rarity);
	outline(ui, x - 2.0, y - 2.0, width + 4.0, height + 4.0, 1.0, withAlpha(color, 0.12));
	outline(ui, x - 1.0, y - 1.0, width + 2.0, height + 2.0, 1.0, withAlpha(color, 0.25));
	box(ui, x, y, width, height, 0.0, PLATE_FACE);
	let seam: float32 = y + 6.0;
	while (seam < y + height - 3.0) {
		box(ui, x + 3.0, seam, width - 6.0, 1.0, 0.0, PLATE_SEAM);
		seam += 6.0;
	}
	outline(ui, x, y, width, height, 1.0, color);
	outline(ui, x + 1.0, y + 1.0, width - 2.0, height - 2.0, 1.0, withAlpha(color, 0.45));
	if (width < SMALLEST_ORNAMENTED || height < SMALLEST_ORNAMENTED) {
		return;
	}
	cornerOrnament(ui, { x: x, y: y, stepX: 1.0, stepY: 1.0 }, color);
	cornerOrnament(ui, { x: x + width, y: y, stepX: -1.0, stepY: 1.0 }, color);
	cornerOrnament(ui, { x: x, y: y + height, stepX: 1.0, stepY: -1.0 }, color);
	cornerOrnament(ui, { x: x + width, y: y + height, stepX: -1.0, stepY: -1.0 }, color);
}

// The moment an item is received: the border and its rarity's name, at 16 when it fits.
export function rarityPlate(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, height: float32,
	rarity: Rarity): void {
	rarityBorder(ui, x, y, width, height, rarity);
	const name: string = rarityName(rarity);
	const large: TextSize = measure(kit, name, 16.0);
	const fits: boolean = large.width <= width - 16.0;
	const textSize: float32 = fits ? 16.0 : 8.0;
	const size: TextSize = fits ? large : measure(kit, name, 8.0);
	say(ui, kit, id, name, x + (width - size.width) * 0.5, y + (height - size.height) * 0.5, size.width + 2.0, textSize,
		rarityColor(rarity), 0.0);
}
