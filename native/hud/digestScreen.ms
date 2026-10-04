import { Color } from "@metascript/void/src/void2d/types";
import { Ui, box } from "../ui/ui";
import { Kit, frame, say, INK, INK_MUTED, EMBER, EMBER_HOT, ALERT_RED, GROWTH_GREEN } from "./kit";
import { FrameLook } from "./frame";
import { delta, signedAmount } from "./meters";
import { segmented } from "./controls";
import { RowKind, listRow, labelDivider } from "./rows";
import { Scroll, scrollState, scrollArea } from "./scroll";
import { lightFrame } from "./shapes";
import { selectNeighbourInSlot } from "./blockScreen";
import { Nav, ScreenContext, SCROLL_BOTTOM, scrollChrome, closeOverlay, screenTitle } from "./screenChrome";

const TOP: float32 = 104.0;
const ROW_HEIGHT: float32 = 48.0;
const NO_SLOT: int32 = 0;
const BAD_NIGHT: int32 = 2;
const DAYS: string[] = ["THIS MORNING", "YESTERDAY", "SEP 30"];
const UNREAD_TODAY: int32 = 3;

interface DaySummary {
	earned: int32;
	food: int32;
	robbed: int32;
	won: int32;
	hearts: string;
}

interface DigestEvent {
	day: int32;
	glyph: string;
	line: string;
	amount: int32;
	// the neighbour it involved, or NO_SLOT
	slot: int32;
}

const SUMMARIES: DaySummary[] = [
	{ earned: 1840, food: -630, robbed: -310, won: 280, hearts: "9 > 7" },
	{ earned: 1520, food: -420, robbed: 0, won: 0, hearts: "7 > 8" },
	{ earned: 1700, food: -500, robbed: -620, won: 0, hearts: "8 > 6" },
];

const EVENTS: DigestEvent[] = [
	{ day: 0, glyph: "worked", line: "WORKED", amount: 420, slot: NO_SLOT },
	{ day: 0, glyph: "fightLost", line: "ROBBED BY SLOT 4", amount: -310, slot: 4 },
	{ day: 0, glyph: "ate", line: "ATE A MEDIUM PORTION", amount: -315, slot: NO_SLOT },
	{ day: 0, glyph: "levelUp", line: "LEVELLED UP - LV 11 > 12", amount: 0, slot: NO_SLOT },
	{ day: 0, glyph: "fightWon", line: "ATTACKED SLOT 7 - WON", amount: 280, slot: 7 },
	{ day: 0, glyph: "gearBought", line: "MINTED RARE BOOTS", amount: -300, slot: NO_SLOT },
	{ day: 0, glyph: "gift", line: "GAVE YOU A GIFT", amount: 60, slot: NO_SLOT },
	{ day: 0, glyph: "worked", line: "WORKED THE NIGHT SHIFT", amount: 210, slot: NO_SLOT },
	{ day: 0, glyph: "skull", line: "SLOT 2 DIED - INHERITANCE", amount: 150, slot: 2 },
	{ day: 0, glyph: "fightWon", line: "ATTACKED SLOT 10 - WON", amount: 190, slot: 10 },
	{ day: 0, glyph: "ate", line: "ATE A SMALL PORTION", amount: -120, slot: NO_SLOT },
	{ day: 0, glyph: "gearSold", line: "SOLD COMMON GLOVES", amount: 90, slot: NO_SLOT },
	{ day: 1, glyph: "worked", line: "WORKED", amount: 380, slot: NO_SLOT },
	{ day: 1, glyph: "ate", line: "ATE A SMALL PORTION", amount: -120, slot: NO_SLOT },
	{ day: 1, glyph: "fightWon", line: "ATTACKED SLOT 10 - WON", amount: 150, slot: 10 },
	{ day: 1, glyph: "skull", line: "SLOT 2 DIED - INHERITANCE", amount: 150, slot: 2 },
	{ day: 1, glyph: "gearSold", line: "SOLD COMMON GLOVES", amount: 90, slot: NO_SLOT },
	{ day: 2, glyph: "worked", line: "WORKED", amount: 400, slot: NO_SLOT },
	{ day: 2, glyph: "fightLost", line: "ROBBED BY SLOT 4", amount: -320, slot: 4 },
	{ day: 2, glyph: "fightLost", line: "BITTEN BY SLOT 4 - -2 HEARTS", amount: 0, slot: 4 },
	{ day: 2, glyph: "ate", line: "ATE A LARGE PORTION", amount: -500, slot: NO_SLOT },
];

interface DigestState {
	day: int32;
	contentHeight: float32;
	scroll: Scroll;
}

const digest: DigestState = { day: 0, contentHeight: 600.0, scroll: scrollState() };

function summaryCard(ui: Ui, kit: Kit, y: float32): void {
	const bad: boolean = digest.day == BAD_NIGHT;
	const summary: DaySummary = SUMMARIES[digest.day];
	frame(kit, 1010, 16.0, y, 328.0, 96.0, 42 + digest.day, bad ? FrameLook.Alert : FrameLook.Normal);
	const labels: string[] = ["EARNED", "FOOD", "ROBBED", "WON", "HEARTS"];
	const amounts: int32[] = [summary.earned, summary.food, summary.robbed, summary.won];
	for (let cell: int32 = 0; cell < labels.length; cell += 1) {
		const cellX: float32 = 30.0 + ((cell % 3) as float32) * 104.0;
		const cellY: float32 = y + 14.0 + ((cell / 3) as float32) * 36.0;
		say(ui, kit, 1011 + cell, labels[cell], cellX, cellY, 96.0, 8.0, INK_MUTED, 0.0);
		if (cell < amounts.length) {
			delta(ui, kit, 1020 + cell, cellX, cellY + 12.0, 96.0, amounts[cell], 0.0);
		} else {
			say(ui, kit, 1024, summary.hearts, cellX, cellY + 12.0, 96.0, 8.0, bad ? ALERT_RED : INK, 0.0);
		}
	}
}

function amountColor(amount: int32): Color {
	return amount >= 0 ? GROWTH_GREEN : ALERT_RED;
}

// Returns where the list ends.
function eventList(context: ScreenContext, top: float32): float32 {
	const ui: Ui = context.ui;
	const kit: Kit = context.kit;
	const today: boolean = digest.day == 0;
	let y: float32 = top;
	let shown: int32 = 0;
	for (let position: int32 = 0; position < EVENTS.length; position += 1) {
		const event: DigestEvent = EVENTS[position];
		if (event.day != digest.day) {
			continue;
		}
		if (today && shown == 0) {
			labelDivider(ui, kit, 1030, 16.0, y, 328.0, "NEW SINCE 23:10", EMBER);
			y += 14.0;
		}
		if (today && shown == UNREAD_TODAY) {
			labelDivider(ui, kit, 1031, 16.0, y, 328.0, "SEEN", INK_MUTED);
			y += 14.0;
		}
		const value: string = event.amount == 0 ? "" : signedAmount(event.amount);
		const linked: boolean = event.slot != NO_SLOT;
		const tapped: boolean = listRow(ui, kit, 1040 + position, 16.0, y, 328.0, event.glyph, event.line, value, amountColor(event.amount),
			RowKind.Plain, linked, false);
		if (today && shown < UNREAD_TODAY) {
			box(ui, 18.0, y + 22.0, 4.0, 4.0, 0.0, EMBER_HOT);
		}
		if (tapped && linked) {
			selectNeighbourInSlot(event.slot);
			context.navigate = Nav.Block;
		}
		y += ROW_HEIGHT;
		shown += 1;
	}
	return y;
}

export function digestScreen(context: ScreenContext): void {
	const offset: float32 = scrollArea(context.ui, digest.scroll, TOP, SCROLL_BOTTOM, digest.contentHeight);
	const contentTop: float32 = TOP + 6.0 - offset;
	summaryCard(context.ui, context.kit, contentTop);
	let y: float32 = contentTop + 106.0;
	if (digest.day == BAD_NIGHT) {
		lightFrame(context.ui, 16.0, y, 200.0, 20.0, ALERT_RED);
		say(context.ui, context.kit, 1025, "HEARTS 6 - ROBBED TWICE", 24.0, y + 6.0, 190.0, 8.0, ALERT_RED, 0.0);
		y += 28.0;
	}
	y = eventList(context, y);
	say(context.ui, context.kit, 1099, "TAP A SLOT TO SEE IT IN YOUR BLOCK", 16.0, y + 12.0, 328.0, 8.0, INK_MUTED, 0.5);
	digest.contentHeight = y + 46.0 - contentTop;

	scrollChrome(context, TOP);
	screenTitle(context, 1000, "DIGEST", "WHILE YOU WERE AWAY");
	const day: int32 = segmented(context.ui, context.kit, 1002, 16.0, 62.0, 328.0, DAYS, digest.day, 41);
	if (day != digest.day) {
		digest.day = day;
		digest.scroll = scrollState();
	}
	closeOverlay(context.ui, context.kit);
}
