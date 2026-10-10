import { Color } from "@metascript/void/src/void2d/types";
import { Ui, box, pressable } from "../ui/ui";
import { Kit, subId, measure, say, INK, INK_BRIGHT, HOLO_BLUE, ALERT_RED, GROWTH_GREEN } from "./kit";
import { hbrnAmount } from "./gameNumbers";
import { Scroll, scrollState, scrollArea } from "./scroll";
import { centredY, infoPanelSized, withAlpha, INFO_PANEL_HEIGHT } from "./shapes";
import { PetActivity } from "./activity";

const PANEL_PAD: float32 = 8.0;
const SHOWN_ROWS: float32 = 5.0;
const LOG_HEIGHT: float32 = INFO_PANEL_HEIGHT - PANEL_PAD * 2.0;
const ROW_HEIGHT: float32 = LOG_HEIGHT / SHOWN_ROWS;
const COMPACT_HEIGHT: float32 = ROW_HEIGHT + PANEL_PAD * 2.0;
const TEXT_SIZE: float32 = 8.0;
const AMOUNT_GAP: float32 = 8.0;
const FOLLOW_SLACK: float32 = 0.5;
const RIM_CLEARANCE: float32 = 2.0;
// The expand / collapse arrow at the panel's right, and the corner a tap on it may land in.
const ARROW_WIDTH: float32 = 7.0;
const ARROW_SPACE: float32 = ARROW_WIDTH + AMOUNT_GAP;
const ARROW_REACH: float32 = 30.0;
// A row that just arrived glows for this long, fading out.
const FRESH_SECONDS: float32 = 1.0;
const FRESH_GLOW: Color = HOLO_BLUE;
const FRESH_GLOW_ALPHA: float32 = 0.35;

export interface ActivityLog {
	scroll: Scroll;
	following: boolean;
	// One line, the newest, until the owner opens it; every launch starts compact.
	expanded: boolean;
	// The newest row last drawn, so a new one can glow; `seen` false takes the next newest without a glow.
	seen: boolean;
	newest: string;
	freshSince: float32;
}

export function activityLogState(): ActivityLog {
	return { scroll: scrollState(), following: true, expanded: false, seen: false, newest: "", freshSince: -FRESH_SECONDS };
}

function amountColor(amount: int64): Color {
	return amount >= 0 ? GROWTH_GREEN : ALERT_RED;
}

function signedHbrn(amount: int64): string {
	return (amount < 0 ? "-" : "+") + hbrnAmount((amount < 0 ? -amount : amount) as uint64);
}

function activityRow(ui: Ui, kit: Kit, id: int32, activity: PetActivity, x: float32, textY: float32, width: float32,
	ink: Color): void {
	let lineWidth: float32 = width;
	if (activity.amount != 0) {
		const amount: string = signedHbrn(activity.amount);
		say(ui, kit, subId(id, 0), amount, x, textY, width, TEXT_SIZE, amountColor(activity.amount), 1.0);
		lineWidth = width - measure(kit, amount, TEXT_SIZE).width - AMOUNT_GAP;
	}
	say(ui, kit, id, activity.line, x, textY, lineWidth, TEXT_SIZE, ink, 0.0);
}

// A pixel triangle ARROW_WIDTH wide, pointing up (opens upwards) or down (closes).
function arrow(ui: Ui, x: float32, middle: float32, up: boolean): void {
	const rows: int32 = 4;
	for (let row: int32 = 0; row < rows; row += 1) {
		const inset: float32 = (up ? rows - 1 - row : row) as float32;
		box(ui, x + inset, middle - 2.0 + (row as float32), ARROW_WIDTH - inset * 2.0, 1.0, 0.0, HOLO_BLUE);
	}
}

function noteNewest(log: ActivityLog, newestFirst: PetActivity[], seconds: float32): float32 {
	const newest: string = (newestFirst.length as int32) > 0 ? newestFirst[0].line : "";
	if (log.seen && newest != log.newest) { log.freshSince = seconds; }
	log.seen = true;
	log.newest = newest;
	const age: float32 = seconds - log.freshSince;
	return age >= 0.0 && age < FRESH_SECONDS ? 1.0 - age / FRESH_SECONDS : 0.0;
}

// Returns the panel's top, which the cards above the log stand on.
export function activityLog(ui: Ui, kit: Kit, id: int32, log: ActivityLog, newestFirst: PetActivity[], panelX: float32,
	panelBottom: float32, panelWidth: float32, seconds: float32): float32 {
	const glow: float32 = noteNewest(log, newestFirst, seconds);
	const panelHeight: float32 = log.expanded ? INFO_PANEL_HEIGHT : COMPACT_HEIGHT;
	const panelTop: float32 = panelBottom - panelHeight;
	// Before the scroll area, which limits the presses after it to the rows.
	const toggled: boolean = log.expanded
		? pressable(ui, subId(id, 15), panelX + panelWidth - ARROW_REACH, panelTop, ARROW_REACH, ARROW_REACH)
		: pressable(ui, subId(id, 15), panelX, panelTop, panelWidth, panelHeight);
	if (toggled) {
		log.expanded = !log.expanded;
		log.following = true;
	}
	infoPanelSized(ui, panelX, panelTop, panelWidth, panelHeight);
	const x: float32 = panelX + PANEL_PAD;
	const width: float32 = panelWidth - PANEL_PAD * 2.0 - ARROW_SPACE;
	const arrowX: float32 = panelX + panelWidth - PANEL_PAD - ARROW_WIDTH;
	const count: int32 = newestFirst.length as int32;
	if (!log.expanded) {
		arrow(ui, arrowX, panelTop + panelHeight * 0.5, true);
		if (count == 0) { return panelTop; }
		const rowTop: float32 = panelTop + PANEL_PAD;
		if (glow > 0.0) { box(ui, panelX + 1.0, rowTop, panelWidth - 2.0, ROW_HEIGHT, 0.0, withAlpha(FRESH_GLOW, FRESH_GLOW_ALPHA * glow)); }
		activityRow(ui, kit, id, newestFirst[0], x, centredY(kit, newestFirst[0].line, TEXT_SIZE, rowTop, ROW_HEIGHT), width,
			glow > 0.0 ? INK_BRIGHT : INK);
		return panelTop;
	}
	arrow(ui, arrowX, panelTop + PANEL_PAD + ROW_HEIGHT * 0.5, false);
	const bottom: float32 = panelBottom - PANEL_PAD;
	const top: float32 = bottom - LOG_HEIGHT;
	const contentHeight: float32 = (count as float32) * ROW_HEIGHT;
	const end: float32 = contentHeight > LOG_HEIGHT ? contentHeight - LOG_HEIGHT : 0.0;
	const below: float32 = contentHeight < LOG_HEIGHT ? LOG_HEIGHT - contentHeight : 0.0;
	if (log.following && !log.scroll.dragging) {
		log.scroll.offset = end;
	}
	const offset: float32 = scrollArea(ui, log.scroll, top, bottom, contentHeight);
	log.following = offset >= end - FOLLOW_SLACK;
	for (let row: int32 = 0; row < count; row += 1) {
		const activity: PetActivity = newestFirst[count - 1 - row];
		const y: float32 = top + below + (row as float32) * ROW_HEIGHT - offset;
		const textY: float32 = centredY(kit, activity.line, TEXT_SIZE, y, ROW_HEIGHT);
		if (textY < panelTop + RIM_CLEARANCE
			|| textY + measure(kit, activity.line, TEXT_SIZE).height > panelBottom - RIM_CLEARANCE) {
			continue;
		}
		const newest: boolean = row == count - 1 && glow > 0.0;
		if (newest) { box(ui, panelX + 1.0, y, panelWidth - 2.0, ROW_HEIGHT, 0.0, withAlpha(FRESH_GLOW, FRESH_GLOW_ALPHA * glow)); }
		activityRow(ui, kit, id + row, activity, x, textY, width, newest ? INK_BRIGHT : INK);
	}
	return panelTop;
}
