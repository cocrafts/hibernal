import { Color } from "@metascript/void/src/void2d/types";
import { Ui } from "../ui/ui";
import { Kit, subId, measure, say, INK, ALERT_RED, GROWTH_GREEN } from "./kit";
import { signedAmount } from "./meters";
import { Scroll, scrollState, scrollArea } from "./scroll";
import { centredY, withAlpha } from "./shapes";
import { PetActivity } from "./activity";

const ROW_HEIGHT: float32 = 20.0;
const SHOWN_ROWS: float32 = 8.0;
const CLEAR_ROWS: float32 = 4.0;
const LOG_HEIGHT: float32 = ROW_HEIGHT * SHOWN_ROWS;
const FADE_HEIGHT: float32 = ROW_HEIGHT * (SHOWN_ROWS - CLEAR_ROWS + 1.0);
const TEXT_SIZE: float32 = 8.0;
const AMOUNT_GAP: float32 = 8.0;
const FOLLOW_SLACK: float32 = 0.5;

export interface ActivityLog {
	scroll: Scroll;
	following: boolean;
}

export function activityLogState(): ActivityLog {
	return { scroll: scrollState(), following: true };
}

function amountColor(amount: int32): Color {
	return amount >= 0 ? GROWTH_GREEN : ALERT_RED;
}

function activityRow(ui: Ui, kit: Kit, id: int32, activity: PetActivity, x: float32, y: float32, width: float32,
	alpha: float32): void {
	const textY: float32 = centredY(kit, activity.line, TEXT_SIZE, y, ROW_HEIGHT);
	let lineWidth: float32 = width;
	if (activity.amount != 0) {
		const amount: string = signedAmount(activity.amount);
		say(ui, kit, subId(id, 0), amount, x, textY, width, TEXT_SIZE, withAlpha(amountColor(activity.amount), alpha), 1.0);
		lineWidth = width - measure(kit, amount, TEXT_SIZE).width - AMOUNT_GAP;
	}
	say(ui, kit, id, activity.line, x, textY, lineWidth, TEXT_SIZE, withAlpha(INK, alpha), 1.0);
}

export function activityLog(ui: Ui, kit: Kit, id: int32, log: ActivityLog, newestFirst: PetActivity[], x: float32,
	bottom: float32, width: float32): void {
	const count: int32 = newestFirst.length as int32;
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
		const y: float32 = top + below + (row as float32) * ROW_HEIGHT - offset;
		if (y < top || y + ROW_HEIGHT > bottom) {
			continue;
		}
		const alpha: float32 = Math.min((y - top + ROW_HEIGHT) / FADE_HEIGHT, 1.0) as float32;
		activityRow(ui, kit, id + row, newestFirst[count - 1 - row], x, y, width, alpha);
	}
}
