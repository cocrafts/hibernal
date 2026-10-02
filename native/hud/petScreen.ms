import { Ui } from "@metascript/void/src/ui/ui";
import { Kit, frame, badgeFrame, icon, say, INK, INK_MUTED, EMBER, EMBER_HOT, ALERT_RED, GROWTH_GREEN } from "./kit";
import { FrameLook } from "./frame";
import { SignState, ChipKind, textLink, signButton, chip } from "./buttons";
import { bar, bondingBar } from "./meters";
import { Rarity, rarityColor, rarityName, rarityBorder } from "./rarity";
import { tabs, radioRow } from "./controls";
import { sectionHeader, emptyState } from "./rows";
import { LineageState, lineageEntry } from "./lineage";
import { Scroll, scrollState, scrollArea } from "./scroll";
import { CHAR_LIGHT, lightFrame } from "./shapes";
import { Signing, idleSigning, startSigning, advanceSigning } from "./signing";
import { treeTab } from "./treeTab";
import { ScreenContext, SCROLL_BOTTOM, openOverlay, scrollChrome, closeOverlay } from "./screenChrome";

const TOP: float32 = 100.0;
const SECTION_GAP: float32 = 30.0;
const HEADER_HEIGHT: float32 = 22.0;
const STAT_SCALE: float32 = 40.0;
const WORN_OUT: float32 = 0.4;

export enum PetTab {
	Pet,
	Tree,
}

interface Stat {
	name: string;
	value: int32;
}

interface Attribute {
	name: string;
	value: string;
}

interface GearPiece {
	slot: string;
	name: string;
	bonus: string;
	skill: string;
	wear: float32;
	rarity: Rarity;
}

interface Persona {
	name: string;
	line: string;
}

const STATS: Stat[] = [{ name: "FORAGE", value: 18 }, { name: "MIGHT", value: 26 }, { name: "GRIT", value: 21 }];
const ATTRIBUTES: Attribute[] = [
	{ name: "SPEED", value: "12" },
	{ name: "ARMOR", value: "8%" },
	{ name: "ACCURACY", value: "71%" },
	{ name: "LIFESTEAL", value: "4%" },
	{ name: "BLEED", value: "2%" },
];
// An empty slot has no name.
const GEAR: GearPiece[] = [
	{ slot: "HEAD", name: "IRON CAP", bonus: "GRIT +6%", skill: "NO SKILL", wear: 0.7, rarity: Rarity.Common },
	{ slot: "BODY", name: "", bonus: "", skill: "", wear: 0.0, rarity: Rarity.Common },
	{ slot: "HANDS", name: "EMBER GLOVES", bonus: "MIGHT +14%", skill: "SKILL - LOOT WARD", wear: 0.35, rarity: Rarity.Epic },
	{ slot: "FEET", name: "RARE BOOTS", bonus: "SPEED +8%", skill: "SKILL - REVIVE", wear: 0.9, rarity: Rarity.Rare },
];
const PERSONAS: Persona[] = [
	{ name: "CAUTIOUS", line: "AVOIDS FIGHTS IT MIGHT LOSE" },
	{ name: "GREEDY", line: "GOES FOR THE FATTEST HARVEST" },
	{ name: "VENGEFUL", line: "HITS BACK WHOEVER ROBBED IT" },
];

interface PetState {
	tab: PetTab;
	persona: int32;
	personaPicked: int32;
	personaSigning: Signing;
	contentHeight: float32;
	scroll: Scroll;
}

const pet: PetState = {
	tab: PetTab.Pet,
	persona: 1,
	personaPicked: 1,
	personaSigning: idleSigning(),
	contentHeight: 1600.0,
	scroll: scrollState(),
};

function header(ui: Ui, kit: Kit): void {
	badgeFrame(kit, 3000, 16.0, 26.0, 36.0, 61);
	icon(kit, 3000, "pet", 24.0, 34.0, 20.0);
	say(ui, kit, 3001, "EMBER", 62.0, 30.0, 140.0, 16.0, INK, 0.0);
	say(ui, kit, 3002, "LV 12 - DAY 34/90", 62.0, 50.0, 160.0, 8.0, INK_MUTED, 0.0);
	icon(kit, 3003, "heart", 286.0, 34.0, 12.0);
	say(ui, kit, 3003, "7/10", 300.0, 36.0, 44.0, 8.0, INK, 1.0);
	const picked: int32 = tabs(ui, kit, 3004, 16.0, 68.0, 328.0, ["PET", "TREE"], [0, 2], pet.tab as int32);
	pet.tab = picked == 0 ? PetTab.Pet : PetTab.Tree;
}

// Each section draws from `top` and returns its height.
function stats(ui: Ui, kit: Kit, top: float32): float32 {
	for (let row: int32 = 0; row < STATS.length; row += 1) {
		const stat: Stat = STATS[row];
		const y: float32 = top + 2.0 + (row as float32) * 40.0;
		say(ui, kit, 3100 + row, stat.name, 16.0, y, 100.0, 8.0, INK, 0.0);
		bar(ui, 110.0, y, 180.0, 8.0, (stat.value as float32) / STAT_SCALE, EMBER);
		say(ui, kit, 3110 + row, stat.value.toString(), 300.0, y, 44.0, 8.0, INK, 1.0);
	}
	for (let cell: int32 = 0; cell < ATTRIBUTES.length; cell += 1) {
		const attribute: Attribute = ATTRIBUTES[cell];
		const x: float32 = 16.0 + ((cell % 2) as float32) * 168.0;
		const y: float32 = top + 128.0 + ((cell / 2) as float32) * 34.0;
		lightFrame(ui, x, y, 160.0, 28.0, CHAR_LIGHT);
		say(ui, kit, 3120 + cell, attribute.name, x + 10.0, y + 10.0, 100.0, 8.0, INK_MUTED, 0.0);
		say(ui, kit, 3130 + cell, attribute.value, x + 90.0, y + 10.0, 60.0, 8.0, INK, 1.0);
	}
	say(ui, kit, 3140, "TREE: 18/30 POINTS - 2 UNSPENT", 16.0, top + 242.0, 260.0, 8.0, INK_MUTED, 0.0);
	if (textLink(ui, kit, 3141, 280.0, top + 242.0, "TREE", true)) {
		pet.tab = PetTab.Tree;
	}
	sectionHeader(ui, kit, 3150, 16.0, top + 274.0, 328.0, "TALENT", "");
	emptyState(ui, kit, 3151, 16.0, top + 294.0, 328.0, 70.0, "lock", "HIDDEN - REVEALED AT LEVEL 10 - 3 LEVELS TO GO");
	sectionHeader(ui, kit, 3160, 16.0, top + 382.0, 328.0, "VITALS", "");
	say(ui, kit, 3161, "HUNGER -2 HEARTS/DAY", 16.0, top + 404.0, 328.0, 8.0, INK, 0.0);
	say(ui, kit, 3162, "PANTRY S 1 - M 0 - L 2", 16.0, top + 422.0, 328.0, 8.0, INK, 0.0);
	say(ui, kit, 3163, "EATS BELOW 4 HEARTS - SET BY THE PET", 16.0, top + 440.0, 328.0, 8.0, INK_MUTED, 0.0);
	say(ui, kit, 3164, "AGE", 16.0, top + 462.0, 60.0, 8.0, INK_MUTED, 0.0);
	bar(ui, 60.0, top + 462.0, 230.0, 8.0, 34.0 / 90.0, GROWTH_GREEN);
	say(ui, kit, 3165, "D34", 300.0, top + 462.0, 44.0, 8.0, INK, 1.0);
	say(ui, kit, 3166, "STATS AT 100% - DECLINE AFTER DAY 50", 16.0, top + 482.0, 328.0, 8.0, INK_MUTED, 0.0);
	return 500.0;
}

function gearCard(ui: Ui, kit: Kit, position: int32, x: float32, y: float32): void {
	const piece: GearPiece = GEAR[position];
	if (piece.name == "") {
		emptyState(ui, kit, 3200 + position, x, y, 160.0, 120.0, "", piece.slot + " - EMPTY");
		return;
	}
	rarityBorder(ui, x, y, 160.0, 120.0, piece.rarity);
	say(ui, kit, 3200 + position, piece.slot, x + 14.0, y + 14.0, 132.0, 8.0, INK_MUTED, 0.0);
	say(ui, kit, 3210 + position, piece.name, x + 14.0, y + 32.0, 132.0, 8.0, INK, 0.0);
	chip(ui, kit, 3220 + position, x + 14.0, y + 48.0, rarityName(piece.rarity), ChipKind.Outline, rarityColor(piece.rarity));
	say(ui, kit, 3230 + position, piece.bonus, x + 14.0, y + 72.0, 132.0, 8.0, EMBER_HOT, 0.0);
	say(ui, kit, 3240 + position, piece.skill, x + 14.0, y + 86.0, 132.0, 8.0, INK_MUTED, 0.0);
	bar(ui, x + 14.0, y + 102.0, 132.0, 5.0, piece.wear, piece.wear < WORN_OUT ? ALERT_RED : INK_MUTED);
}

function equipment(ui: Ui, kit: Kit, top: float32): float32 {
	for (let position: int32 = 0; position < GEAR.length; position += 1) {
		gearCard(ui, kit, position, 16.0 + ((position % 2) as float32) * 168.0, top + ((position / 2) as float32) * 132.0);
	}
	sectionHeader(ui, kit, 3250, 16.0, top + 272.0, 328.0, "HEIRLOOMS", "KEPT FOR THE NEXT GENERATION");
	emptyState(ui, kit, 3251, 16.0, top + 294.0, 160.0, 80.0, "", "EMPTY");
	rarityBorder(ui, 184.0, top + 294.0, 160.0, 80.0, Rarity.Legendary);
	say(ui, kit, 3252, "GRANDSIRE'S FANG", 198.0, top + 310.0, 132.0, 8.0, INK, 0.0);
	say(ui, kit, 3253, "MIGHT +5%", 198.0, top + 328.0, 132.0, 8.0, EMBER_HOT, 0.0);
	say(ui, kit, 3254, "YOUR PET BUYS AND SELLS ITS OWN GEAR.", 16.0, top + 398.0, 328.0, 8.0, INK_MUTED, 0.5);
	return 420.0;
}

function personaButtonState(changed: boolean): SignState {
	return match (pet.personaSigning.state) {
		SignState.Idle => changed ? SignState.Idle : SignState.Disabled,
		_ => pet.personaSigning.state,
	};
}

function bonding(context: ScreenContext, top: float32): float32 {
	const ui: Ui = context.ui;
	const kit: Kit = context.kit;
	say(ui, kit, 3300, "BONDING +40", 16.0, top + 2.0, 200.0, 8.0, INK, 0.0);
	bondingBar(ui, kit, 3301, 16.0, top + 20.0, 328.0, 40);
	say(ui, kit, 3302, "GIFTS RECEIVED: 1,240", 16.0, top + 52.0, 328.0, 8.0, INK, 0.0);
	say(ui, kit, 3303, "TALKS THAT COUNT TODAY: 3/5", 16.0, top + 68.0, 328.0, 8.0, INK, 0.0);
	sectionHeader(ui, kit, 3310, 16.0, top + 98.0, 328.0, "BRAIN - PERSONA", "");
	const waiting: boolean = pet.personaSigning.state == SignState.Waiting;
	for (let position: int32 = 0; position < PERSONAS.length; position += 1) {
		const persona: Persona = PERSONAS[position];
		if (radioRow(ui, kit, 3311 + position, 16.0, top + 116.0 + (position as float32) * 48.0, 328.0, persona.name, persona.line,
			pet.personaPicked == position, pet.persona == position) && !waiting) {
			pet.personaPicked = position;
		}
	}
	if (advanceSigning(pet.personaSigning, context.tick)) {
		pet.persona = pet.personaPicked;
	}
	const changed: boolean = pet.personaPicked != pet.persona;
	if (signButton(ui, kit, 3320, 16.0, top + 270.0, 328.0, 44.0, "CHANGE", personaButtonState(changed), 62, context.tick)) {
		startSigning(pet.personaSigning, context.tick);
	}
	const signing: boolean = pet.personaSigning.state != SignState.Idle;
	say(ui, kit, 3321, changed || signing ? "NEEDS A SIGNATURE" : "PICK ANOTHER PERSONA TO CHANGE IT", 16.0, top + 322.0, 328.0, 8.0,
		INK_MUTED, 0.0);
	say(ui, kit, 3322, "YOUR PET DECIDES; THIS ONLY NUDGES IT.", 16.0, top + 342.0, 328.0, 8.0, INK_MUTED, 0.0);
	return 360.0;
}

function lineage(ui: Ui, kit: Kit, top: float32): float32 {
	frame(kit, 3400, 16.0, top, 328.0, 160.0, 63, FrameLook.Normal);
	lineageEntry(ui, kit, 3401, 32.0, top + 22.0, 300.0, "GEN 1 - FIGHTER - LIVED 90 DAYS", LineageState.Lived, false);
	lineageEntry(ui, kit, 3402, 32.0, top + 54.0, 300.0, "GEN 2 - WORKER - DIED DAY 61", LineageState.Died, false);
	lineageEntry(ui, kit, 3403, 32.0, top + 86.0, 300.0, "GEN 3 - FIGHTER - NOW - DAY 34", LineageState.Now, true);
	say(ui, kit, 3404, "HEIR BONUS: +2 STARTING POINTS", 32.0, top + 128.0, 300.0, 8.0, EMBER_HOT, 0.0);
	say(ui, kit, 3405, "START PATH: FIGHTER - FIXED AT BIRTH", 16.0, top + 178.0, 328.0, 8.0, INK_MUTED, 0.0);
	say(ui, kit, 3406, "GEN 3 - SCARS 1", 16.0, top + 196.0, 328.0, 8.0, INK_MUTED, 0.0);
	return 212.0;
}

function petPage(context: ScreenContext): void {
	const ui: Ui = context.ui;
	const kit: Kit = context.kit;
	const offset: float32 = scrollArea(ui, pet.scroll, TOP, SCROLL_BOTTOM, pet.contentHeight);
	let y: float32 = TOP + 8.0 - offset;
	sectionHeader(ui, kit, 3011, 16.0, y, 328.0, "STATS", "TAP FOR BREAKDOWN");
	y += stats(ui, kit, y + HEADER_HEIGHT) + SECTION_GAP;
	sectionHeader(ui, kit, 3012, 16.0, y, 328.0, "EQUIPMENT", "TAP TO INSPECT");
	y += equipment(ui, kit, y + HEADER_HEIGHT) + SECTION_GAP;
	sectionHeader(ui, kit, 3013, 16.0, y, 328.0, "BONDING", "");
	y += bonding(context, y + HEADER_HEIGHT) + SECTION_GAP;
	sectionHeader(ui, kit, 3014, 16.0, y, 328.0, "LINEAGE", "");
	y += lineage(ui, kit, y + HEADER_HEIGHT) + SECTION_GAP;
	pet.contentHeight = y + offset - TOP + 8.0;
	scrollChrome(context, TOP);
	header(ui, kit);
	closeOverlay(ui, kit);
}

export function petScreen(context: ScreenContext): void {
	match (pet.tab) {
		PetTab.Pet => petPage(context),
		PetTab.Tree => {
			treeTab(context);
			openOverlay(context.ui, context.kit);
			header(context.ui, context.kit);
			closeOverlay(context.ui, context.kit);
		},
	};
}
