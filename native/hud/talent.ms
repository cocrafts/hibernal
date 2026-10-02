import { Color } from "@metascript/void/src/void2d/types";
import { Ui, box } from "@metascript/void/src/ui/ui";
import { Kit, subId, frameSqueezed, icon, say, INK, INK_MUTED, EMBER_HOT, DISABLED_INK } from "./kit";
import { FrameLook } from "./frame";
import { ChipKind, chip } from "./buttons";
import { Rarity, rarityColor, rarityName, rarityBorder } from "./rarity";
import { withAlpha } from "./shapes";

const HALF: float32 = 0.5;
const CARD_WIDTH: float32 = 120.0;
const CARD_HEIGHT: float32 = 160.0;
const THINNEST_SQUEEZE: float32 = 0.04;
const READABLE_OPEN: float32 = 0.6;
const GRADES: Rarity[] = [Rarity.Common, Rarity.Rare, Rarity.Epic, Rarity.Legendary, Rarity.Mythic];

// `flip` 0 shows the back ("?") and 1 the face; between, the card squeezes shut on its back and
// opens on its face.
export function talentCard(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, flip: float32, kind: string, rarity: Rarity,
	multiplier: string, seed: int32): void {
	const turned: float32 = flip < 0.0 ? 0.0 : (flip > 1.0 ? 1.0 : flip);
	const faceUp: boolean = turned >= HALF;
	const open: float32 = faceUp ? (turned - HALF) * 2.0 : 1.0 - turned * 2.0;
	const squeeze: float32 = open < THINNEST_SQUEEZE ? THINNEST_SQUEEZE : open;
	if (!faceUp) {
		frameSqueezed(kit, id, x, y, CARD_WIDTH, CARD_HEIGHT, seed, FrameLook.Normal, squeeze);
		if (open >= READABLE_OPEN) {
			say(ui, kit, id, "?", x, y + CARD_HEIGHT * HALF - 16.0, CARD_WIDTH, 32.0, EMBER_HOT, 0.5);
		}
		return;
	}
	const faceWidth: float32 = CARD_WIDTH * squeeze;
	rarityBorder(ui, x + (CARD_WIDTH - faceWidth) * HALF, y, faceWidth, CARD_HEIGHT, rarity);
	if (open < READABLE_OPEN) {
		return;
	}
	const color: Color = rarityColor(rarity);
	say(ui, kit, id, kind, x, y + 26.0, CARD_WIDTH, 8.0, INK_MUTED, 0.5);
	icon(kit, id, "fightWon", x + CARD_WIDTH * HALF - 14.0, y + 42.0, 28.0);
	say(ui, kit, subId(id, 0), rarityName(rarity), x, y + 82.0, CARD_WIDTH, 16.0, color, 0.5);
	box(ui, x + 24.0, y + 104.0, CARD_WIDTH - 48.0, 1.0, 0.0, withAlpha(color, 0.5));
	say(ui, kit, subId(id, 1), multiplier, x, y + 112.0, CARD_WIDTH, 16.0, INK, 0.5);
	say(ui, kit, subId(id, 2), "TO FIGHT STATS", x, y + 134.0, CARD_WIDTH, 8.0, INK_MUTED, 0.5);
}

// Every grade as a chip, lit up to `reached`, dashed above it.
export function gradeLadder(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, reached: Rarity): void {
	let chipX: float32 = x;
	for (let position: int32 = 0; position < GRADES.length; position += 1) {
		const grade: Rarity = GRADES[position];
		const lit: boolean = (grade as int32) <= (reached as int32);
		chipX += chip(ui, kit, subId(id, position), chipX, y, rarityName(grade), lit ? ChipKind.Outline : ChipKind.Dashed,
			lit ? rarityColor(grade) : DISABLED_INK) + 4.0;
	}
}
