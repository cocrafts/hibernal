// The item card over the hotbar: what a hotbar slot or a shop cell holds. Laid out on
// itemCard.png (art/hud/cutItemShop.py) in that piece's pixels, scaled to CARD_WIDTH.

import { Color, rgba } from "@metascript/void/src/void2d/types";
import { BoxStyle, uniformRadii, uniformBorders } from "@metascript/void/src/void2d/boxStyle";
import { Ui, box, pressable } from "../ui/ui";
import {
	Kit, PieceLayer, INK, INK_BRIGHT, INK_MUTED, HOLO_BLUE, pieceSized, pieceWidth, pieceHeight, say, subId,
} from "./kit";
import { DESIGN_W } from "../ui/ui";
import { infoPanelSized } from "./shapes";
import { TalentKind, TalentGrade } from "../../rules/talent";
import { Item, ItemSkill, GearSlot, ITEM_WEAR_MAX } from "../../rules/items";
import { hbrnAmount } from "./gameNumbers";

export const CARD_WIDTH: float32 = 196.0;
const CARD_PIXELS_WIDE: float32 = 528.0;
const CARD_PIXELS_HIGH: float32 = 517.0;
const SCALE: float32 = CARD_WIDTH / CARD_PIXELS_WIDE;
export const CARD_HEIGHT: float32 = CARD_PIXELS_HIGH * SCALE;
const ICON_BOX_X: float32 = 57.0;
const ICON_BOX_Y: float32 = 75.0;
const ICON_BOX_SIZE: float32 = 158.0;
const ICON_SIZE: float32 = 44.0;
const NAME_X: float32 = 245.0;
const NAME_RIGHT: float32 = 464.0;
const NAME_Y: float32 = 84.0;
const NAME_HEIGHT: float32 = 36.0;
const ROW_TOPS: float32[] = [137.0, 188.0, 240.0, 292.0];
const ROW_LEFT: float32 = 232.0;
const ROW_RIGHT: float32 = 476.0;
const ROW_HEIGHT: float32 = 43.0;
const ROW_LABEL_X: float32 = 285.0;
const ROW_VALUE_RIGHT: float32 = 464.0;
const NOTE_X: float32 = 66.0;
const NOTE_Y: float32 = 364.0;
const NOTE_WIDTH: float32 = 400.0;
const NOTE_LINE: float32 = 30.0;
const TITLE_SIZE: float32 = 8.0;
const ROW_SIZE: float32 = 6.5;
const NOTE_SIZE: float32 = 6.0;
const CHOSEN_RIM: Color = rgba(0.92, 0.96, 1.0, 0.9);
export const CARD_ROWS: int32 = 4;
export const NO_ROW: int32 = -1;

export interface ItemRow {
	label: string;
	value: string;
}

export interface ItemCard {
	icon: string;
	title: string;
	tag: string;
	tagColour: Color;
	rows: ItemRow[];
	notes: string[];
	// Rows below this index can be tapped (the shop's tiers); NO_ROW for none.
	choosableRows: int32;
	chosenRow: int32;
}

function px(value: float32): float32 {
	return value * SCALE;
}

// Returns the tapped row, NO_ROW when none.
export function itemCard(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, card: ItemCard): int32 {
	if (card.rows.length != CARD_ROWS) {
		console.log("itemCard: " + (card.rows.length as int32).toString() + " rows, not " + CARD_ROWS.toString());
		unreachable;
	}
	pieceSized(kit, subId(id, 0), PieceLayer.Frames, "itemCard", x, y, CARD_WIDTH, CARD_HEIGHT);
	const iconWidth: float32 = pieceWidth(kit, card.icon);
	const iconHeight: float32 = pieceHeight(kit, card.icon);
	const fit: float32 = ICON_SIZE / Math.max(iconWidth, iconHeight);
	const centreX: float32 = x + px(ICON_BOX_X + ICON_BOX_SIZE * 0.5);
	const centreY: float32 = y + px(ICON_BOX_Y + ICON_BOX_SIZE * 0.5);
	pieceSized(kit, subId(id, 1), PieceLayer.Icons, card.icon, centreX - iconWidth * fit * 0.5,
		centreY - iconHeight * fit * 0.5, iconWidth * fit, iconHeight * fit);
	const nameTextY: float32 = y + px(NAME_Y + NAME_HEIGHT * 0.5) - TITLE_SIZE * 0.6;
	say(ui, kit, subId(id, 2), card.title, x + px(NAME_X), nameTextY, px(NAME_RIGHT - NAME_X), TITLE_SIZE, INK_BRIGHT, 0.0);
	say(ui, kit, subId(id, 3), card.tag, x + px(NAME_X), nameTextY, px(NAME_RIGHT - NAME_X), ROW_SIZE, card.tagColour, 1.0);
	let tapped: int32 = NO_ROW;
	for (let row: int32 = 0; row < CARD_ROWS; row += 1) {
		const top: float32 = y + px(ROW_TOPS[row]);
		const textY: float32 = top + px(ROW_HEIGHT) * 0.5 - ROW_SIZE * 0.6;
		const line: ItemRow = card.rows[row];
		const chosen: boolean = row == card.chosenRow;
		say(ui, kit, subId(id, 4 + row), line.label, x + px(ROW_LABEL_X), textY, px(ROW_VALUE_RIGHT - ROW_LABEL_X),
			ROW_SIZE, chosen ? INK_BRIGHT : INK, 0.0);
		say(ui, kit, subId(id, 8 + row), line.value, x + px(ROW_LABEL_X), textY, px(ROW_VALUE_RIGHT - ROW_LABEL_X),
			ROW_SIZE, chosen ? INK_BRIGHT : HOLO_BLUE, 1.0);
		if (chosen) {
			const rim = BoxStyle.create(uniformRadii(px(8.0)), uniformBorders(1.0), CHOSEN_RIM);
			box(ui, x + px(ROW_LEFT), top, px(ROW_RIGHT - ROW_LEFT), px(ROW_HEIGHT), px(8.0), rgba(0.0, 0.0, 0.0, 0.0), rim);
		}
		if (row < card.choosableRows
			&& pressable(ui, subId(id, 12 + row), x + px(ROW_LEFT), top, px(ROW_RIGHT - ROW_LEFT), px(ROW_HEIGHT))) {
			tapped = row;
		}
	}
	for (let line: int32 = 0; line < (card.notes.length as int32); line += 1) {
		say(ui, kit, subId(id + 1, line), card.notes[line], x + px(NOTE_X), y + px(NOTE_Y + NOTE_LINE * (line as float32)),
			px(NOTE_WIDTH), NOTE_SIZE, INK, 0.0);
	}
	return tapped;
}

// The light look of a held slot, the activity log's panel: icon and title, then rows, then notes.
const PEEK_WIDTH: float32 = 200.0;
const PEEK_PAD: float32 = 8.0;
const PEEK_EDGE: float32 = 6.0;
const PEEK_ICON: float32 = 24.0;
const PEEK_TITLE_SIZE: float32 = 8.0;
const PEEK_ROW_SIZE: float32 = 7.0;
const PEEK_ROW: float32 = 12.0;
const PEEK_NOTE: float32 = 10.0;
const PEEK_GAP: float32 = 6.0;
const PEEK_RULE: Color = rgba(0.25, 0.6, 0.95, 0.35);

function peekRows(card: ItemCard): int32 {
	let shown: int32 = 0;
	for (const row of card.rows) {
		if (row.label != "") { shown += 1; }
	}
	return shown;
}

export function itemPeekHeight(card: ItemCard): float32 {
	return PEEK_PAD * 2.0 + PEEK_ICON + PEEK_GAP * 2.0 + (peekRows(card) as float32) * PEEK_ROW
		+ (card.notes.length as float32) * PEEK_NOTE;
}

// Centred over `centreX` and kept on screen, its bottom at `bottom`.
export function itemPeek(ui: Ui, kit: Kit, id: int32, centreX: float32, bottom: float32, card: ItemCard): void {
	const height: float32 = itemPeekHeight(card);
	const x: float32 = Math.min(Math.max(centreX - PEEK_WIDTH * 0.5, PEEK_EDGE), DESIGN_W - PEEK_EDGE - PEEK_WIDTH);
	const y: float32 = bottom - height;
	infoPanelSized(ui, x, y, PEEK_WIDTH, height);
	const inner: float32 = PEEK_WIDTH - PEEK_PAD * 2.0;
	const iconWidth: float32 = pieceWidth(kit, card.icon);
	const iconHeight: float32 = pieceHeight(kit, card.icon);
	const fit: float32 = PEEK_ICON / Math.max(iconWidth, iconHeight);
	pieceSized(kit, subId(id, 1), PieceLayer.Icons, card.icon, x + PEEK_PAD + (PEEK_ICON - iconWidth * fit) * 0.5,
		y + PEEK_PAD + (PEEK_ICON - iconHeight * fit) * 0.5, iconWidth * fit, iconHeight * fit);
	const titleX: float32 = x + PEEK_PAD + PEEK_ICON + PEEK_GAP;
	const titleY: float32 = y + PEEK_PAD + PEEK_ICON * 0.5 - PEEK_TITLE_SIZE * 0.6;
	const titleWidth: float32 = x + PEEK_WIDTH - PEEK_PAD - titleX;
	say(ui, kit, subId(id, 2), card.title, titleX, titleY, titleWidth, PEEK_TITLE_SIZE, INK_BRIGHT, 0.0);
	say(ui, kit, subId(id, 3), card.tag, titleX, titleY, titleWidth, PEEK_ROW_SIZE, card.tagColour, 1.0);
	let lineY: float32 = y + PEEK_PAD + PEEK_ICON + PEEK_GAP;
	for (let row: int32 = 0; row < (card.rows.length as int32); row += 1) {
		const line: ItemRow = card.rows[row];
		if (line.label == "") { continue; }
		const chosen: boolean = row == card.chosenRow;
		say(ui, kit, subId(id, 4 + row), line.label, x + PEEK_PAD, lineY, inner, PEEK_ROW_SIZE, chosen ? INK_BRIGHT : INK, 0.0);
		say(ui, kit, subId(id, 8 + row), line.value, x + PEEK_PAD, lineY, inner, PEEK_ROW_SIZE,
			chosen ? INK_BRIGHT : HOLO_BLUE, 1.0);
		lineY += PEEK_ROW;
	}
	box(ui, x + PEEK_PAD, lineY + PEEK_GAP * 0.5 - 1.0, inner, 1.0, 0.0, PEEK_RULE);
	lineY += PEEK_GAP;
	for (let note: int32 = 0; note < (card.notes.length as int32); note += 1) {
		say(ui, kit, subId(id + 1, note), card.notes[note], x + PEEK_PAD, lineY, inner, NOTE_SIZE, INK_MUTED, 0.0);
		lineY += PEEK_NOTE;
	}
}

function gradeName(grade: TalentGrade): string {
	return match (grade) {
		TalentGrade.Common => "COMMON",
		TalentGrade.Rare => "RARE",
		TalentGrade.Epic => "EPIC",
		TalentGrade.Legendary => "LEGENDARY",
		TalentGrade.Mythic => "MYTHIC",
	};
}

function gradeColour(grade: TalentGrade): Color {
	return match (grade) {
		TalentGrade.Common => rgba(0.75, 0.78, 0.8, 1.0),
		TalentGrade.Rare => rgba(0.45, 0.78, 1.0, 1.0),
		TalentGrade.Epic => rgba(0.72, 0.55, 0.95, 1.0),
		TalentGrade.Legendary => rgba(1.0, 0.66, 0.25, 1.0),
		TalentGrade.Mythic => rgba(1.0, 0.36, 0.36, 1.0),
	};
}

function statName(stat: TalentKind): string {
	return match (stat) {
		TalentKind.None => "NO STAT",
		TalentKind.Forage => "FORAGE",
		TalentKind.Might => "MIGHT",
		TalentKind.Grit => "GRIT",
	};
}

function skillName(skill: ItemSkill): string {
	return match (skill) {
		ItemSkill.None => "NO SKILL",
		ItemSkill.Revive => "REVIVE",
		ItemSkill.AntiRobbery => "ANTI-ROBBERY",
		ItemSkill.DamageGuard => "DAMAGE GUARD",
	};
}

export function slotName(slot: GearSlot): string {
	return match (slot) {
		GearSlot.Head => "HEAD",
		GearSlot.Body => "BODY",
		GearSlot.Hands => "HANDS",
		GearSlot.Feet => "FEET",
	};
}

export function gearSummary(item: Item): string {
	return gradeName(((item.rarity as int32) - 1) as TalentGrade) + " " + statName(item.stat as TalentKind) + " LV"
		+ (item.level as int32).toString();
}

export function percentOfBps(bps: int32): string {
	const tenths: int32 = (bps + 5) / 10;
	const fraction: int32 = tenths % 10;
	return (tenths / 10).toString() + (fraction == 0 ? "" : "." + fraction.toString()) + "%";
}

// Hotbar slots 1 to 4: the Pet's gear, which only the Pet changes.
export function gearCard(icon: string, slot: GearSlot, item: Item, live: boolean): ItemCard {
	const grade: TalentGrade = ((item.rarity as int32) - 1) as TalentGrade;
	return {
		icon: icon,
		title: slotName(slot),
		tag: gradeName(grade),
		tagColour: gradeColour(grade),
		rows: [
			{ label: statName(item.stat as TalentKind), value: "+" + percentOfBps(item.bonusBps()) },
			{ label: "LEVEL", value: (item.level as int32).toString() },
			{ label: "WEAR", value: (item.wear as int32).toString() + "/" + ITEM_WEAR_MAX.toString() },
			{ label: skillName(item.skill as ItemSkill), value: "" },
		],
		notes: [live ? "GEAR THE PET WEARS." : "PREVIEW GEAR, NOT FROM CHAIN.", "THE PET EQUIPS AND SELLS ITS GEAR.",
			"SELLS BACK FOR " + hbrnAmount(item.sellPrice()) + " HBRN."],
		choosableRows: NO_ROW,
		chosenRow: NO_ROW,
	};
}
