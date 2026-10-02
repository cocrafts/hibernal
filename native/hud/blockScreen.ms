import { Color, rgba } from "@metascript/void/src/void2d/types";
import { Ui, box, pressable } from "@metascript/void/src/ui/ui";
import { Kit, say, INK, INK_MUTED, ALERT_RED, GROWTH_GREEN, DISABLED_INK } from "./kit";
import { ChipKind, chip } from "./buttons";
import { heartPips, balance } from "./meters";
import { segmented } from "./controls";
import { RowKind, listRow, sectionHeader, emptyState } from "./rows";
import { pager } from "./navigation";
import { OddsState, Odds, oddsBlock } from "./odds";
import { CHAR_LIGHT, lightFrame } from "./shapes";
import { ScreenContext, screenTitle } from "./screenChrome";

const CELL_WIDTH: float32 = 104.0;
const CELL_HEIGHT: float32 = 44.0;
const SELECTED_CELL: Color = rgba(0.733, 0.682, 0.675, 1.0);
const SELECTED_INK: Color = rgba(0.09, 0.07, 0.06, 1.0);
const FADING_DAY: int32 = 50;
const SORTS: string[] = ["THREAT", "LOOT", "WEAK"];
const ROUND_SHARES: float32[] = [0.08, 0.12, 0.28, 0.40, 0.33, 0.18];
const ROBBER_SLOT: int32 = 4;

export enum NeighbourKind {
	Player,
	Wild,
	Shielded,
	Dead,
}

export interface Neighbour {
	slot: int32;
	name: string;
	kind: NeighbourKind;
	level: int32;
	hearts: int32;
	harvest: int32;
	burrow: int32;
	winPercent: int32;
	day: int32;
	rage: int32;
}

// Our pet is slot 5; these are the other nine of the block.
const NEIGHBOURS: Neighbour[] = [
	{ slot: 4, name: "ASHEN", kind: NeighbourKind.Player, level: 15, hearts: 3, harvest: 2100, burrow: 8400, winPercent: 62, day: 52, rage: 2 },
	{ slot: 7, name: "MOSS", kind: NeighbourKind.Player, level: 12, hearts: 8, harvest: 1300, burrow: 3100, winPercent: 48, day: 30, rage: 1 },
	{ slot: 10, name: "CINDER", kind: NeighbourKind.Player, level: 14, hearts: 2, harvest: 1650, burrow: 5200, winPercent: 76, day: 61, rage: 0 },
	{ slot: 2, name: "-", kind: NeighbourKind.Dead, level: 9, hearts: 0, harvest: 0, burrow: 0, winPercent: 0, day: 0, rage: 0 },
	{ slot: 9, name: "WILD 9", kind: NeighbourKind.Wild, level: 11, hearts: 6, harvest: 880, burrow: 2600, winPercent: 55, day: 18, rage: 0 },
	{ slot: 1, name: "FLINT", kind: NeighbourKind.Player, level: 13, hearts: 7, harvest: 940, burrow: 4400, winPercent: 41, day: 44, rage: 0 },
	{ slot: 6, name: "SORREL", kind: NeighbourKind.Player, level: 10, hearts: 5, harvest: 1120, burrow: 3900, winPercent: 58, day: 37, rage: 0 },
	{ slot: 3, name: "PIP", kind: NeighbourKind.Shielded, level: 8, hearts: 9, harvest: 300, burrow: 900, winPercent: 0, day: 2, rage: 0 },
	{ slot: 8, name: "BRAMBLE", kind: NeighbourKind.Player, level: 12, hearts: 4, harvest: 1410, burrow: 5100, winPercent: 51, day: 25, rage: 0 },
];

interface BlockState {
	sort: int32;
	selected: int32;
}

const block: BlockState = { sort: 0, selected: 0 };

// Opens the Block on the neighbour in `slot`, for a tap on a Digest line.
export function selectNeighbourInSlot(slot: int32): void {
	for (let position: int32 = 0; position < NEIGHBOURS.length; position += 1) {
		if (NEIGHBOURS[position].slot == slot) {
			block.selected = position;
		}
	}
}

function attackable(neighbour: Neighbour): boolean {
	return neighbour.kind == NeighbourKind.Player || neighbour.kind == NeighbourKind.Wild;
}

function winColor(neighbour: Neighbour): Color {
	return match (neighbour.winPercent) {
		_ when !attackable(neighbour) => INK_MUTED,
		_ when neighbour.winPercent >= 50 => GROWTH_GREEN,
		_ => ALERT_RED,
	};
}

function summary(neighbour: Neighbour): string {
	const wild: string = neighbour.kind == NeighbourKind.Wild ? " W" : "";
	const raging: string = neighbour.rage > 0 ? " !" : "";
	return "LV" + neighbour.level.toString() + " " + neighbour.hearts.toString() + "/10" + wild + raging;
}

function cell(ui: Ui, kit: Kit, position: int32, x: float32, y: float32): void {
	const neighbour: Neighbour = NEIGHBOURS[position];
	const selected: boolean = position == block.selected;
	const dead: boolean = neighbour.kind == NeighbourKind.Dead;
	if (selected) {
		box(ui, x, y, CELL_WIDTH, CELL_HEIGHT, 0.0, SELECTED_CELL);
	} else {
		lightFrame(ui, x, y, CELL_WIDTH, CELL_HEIGHT, dead ? DISABLED_INK : CHAR_LIGHT);
	}
	const ink: Color = selected ? SELECTED_INK : INK;
	const quiet: Color = selected ? SELECTED_INK : INK_MUTED;
	say(ui, kit, 2010 + position, "#" + neighbour.slot.toString(), x + 8.0, y + 8.0, 40.0, 8.0, ink, 0.0);
	if (dead) {
		say(ui, kit, 2020 + position, "HEIR IN 5D", x + 8.0, y + 26.0, 90.0, 8.0, quiet, 0.0);
	} else {
		say(ui, kit, 2020 + position, attackable(neighbour) ? neighbour.winPercent.toString() + "%" : "-", x + 52.0, y + 8.0, 44.0, 8.0,
			selected ? ink : winColor(neighbour), 1.0);
		say(ui, kit, 2030 + position, summary(neighbour), x + 8.0, y + 26.0, 90.0, 8.0, quiet, 0.0);
	}
	if (pressable(ui, 2040 + position, x, y, CELL_WIDTH, CELL_HEIGHT)) {
		block.selected = position;
	}
}

function statusChips(ui: Ui, kit: Kit, neighbour: Neighbour): void {
	let chipX: float32 = 16.0;
	if (neighbour.kind == NeighbourKind.Wild) {
		chipX += chip(ui, kit, 2063, chipX, 334.0, "WILD", ChipKind.Outline, INK) + 4.0;
	}
	if (neighbour.kind == NeighbourKind.Shielded) {
		chipX += chip(ui, kit, 2064, chipX, 334.0, "SHIELD 2D", ChipKind.Outline, INK) + 4.0;
	}
	if (neighbour.day >= FADING_DAY) {
		chipX += chip(ui, kit, 2065, chipX, 334.0, "FADING", ChipKind.Dashed, INK_MUTED) + 4.0;
	}
	if (neighbour.rage > 0) {
		chip(ui, kit, 2066, chipX, 334.0, "RAGE " + neighbour.rage.toString(), ChipKind.Filled, ALERT_RED);
	}
}

function fightLog(ui: Ui, kit: Kit, neighbour: Neighbour): void {
	sectionHeader(ui, kit, 2080, 16.0, 594.0, 328.0, "FIGHT LOG - 24H", "");
	if (neighbour.slot != ROBBER_SLOT) {
		say(ui, kit, 2083, "NO FIGHTS WITH YOU IN THE LAST 24H", 16.0, 620.0, 328.0, 8.0, INK_MUTED, 0.0);
		return;
	}
	listRow(ui, kit, 2081, 16.0, 612.0, 328.0, "fightLost", "03:10 SLOT 4 > YOU - LOST", "-310", ALERT_RED, RowKind.Plain, false, false);
	listRow(ui, kit, 2082, 16.0, 660.0, 328.0, "fightWon", "21:40 YOU > SLOT 4 - WON", "+220", GROWTH_GREEN, RowKind.Plain, false, false);
}

function detail(context: ScreenContext, neighbour: Neighbour): void {
	const ui: Ui = context.ui;
	const kit: Kit = context.kit;
	if (neighbour.kind == NeighbourKind.Dead) {
		emptyState(ui, kit, 2060, 16.0, 310.0, 328.0, 120.0, "skull", "WAITING FOR HEIR - 5 DAYS LEFT");
		return;
	}
	say(ui, kit, 2061, neighbour.name, 16.0, 310.0, 160.0, 16.0, INK, 0.0);
	say(ui, kit, 2062, "LV " + neighbour.level.toString() + " - DAY " + neighbour.day.toString() + "/90", 160.0, 314.0, 184.0, 8.0,
		INK_MUTED, 1.0);
	statusChips(ui, kit, neighbour);
	heartPips(ui, kit, 2067, 16.0, 358.0, neighbour.hearts, 10, 12.0);
	balance(ui, kit, 2068, 16.0, 380.0, 156.0, "bag", "warning", neighbour.harvest.toString());
	balance(ui, kit, 2069, 188.0, 380.0, 156.0, "lock", "", neighbour.burrow.toString());
	const odds: Odds = {
		winPercent: neighbour.winPercent,
		expectedLoot: (neighbour.harvest * neighbour.winPercent) / 400,
		maxLoot: neighbour.harvest / 4,
		rounds: ROUND_SHARES,
	};
	const state: OddsState = neighbour.kind == NeighbourKind.Shielded ? OddsState.NotAttackable : OddsState.Ready;
	oddsBlock(ui, kit, 2070, 16.0, 410.0, state, odds, "NEWBORN SHIELD - 2 DAYS LEFT", 52, context.tick);
	fightLog(ui, kit, neighbour);
}

export function blockScreen(context: ScreenContext): void {
	screenTitle(context, 2000, "YOUR BLOCK", "9 NEIGHBOURS - YOU: #5");
	block.sort = segmented(context.ui, context.kit, 2002, 16.0, 62.0, 328.0, SORTS, block.sort, 51);
	for (let position: int32 = 0; position < NEIGHBOURS.length; position += 1) {
		cell(context.ui, context.kit, position, 16.0 + ((position % 3) as float32) * 112.0, 108.0 + ((position / 3) as float32) * 50.0);
	}
	const neighbour: Neighbour = NEIGHBOURS[block.selected];
	const count: int32 = NEIGHBOURS.length as int32;
	const label: string = "SLOT " + neighbour.slot.toString() + " - " + (block.selected + 1).toString() + " OF " + count.toString()
		+ " (" + SORTS[block.sort] + ")";
	block.selected = pager(context.ui, context.kit, 2050, 16.0, 266.0, 328.0, label, block.selected, count);
	detail(context, NEIGHBOURS[block.selected]);
}
