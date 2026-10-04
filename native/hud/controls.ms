import { Color, rgba } from "@metascript/void/src/void2d/types";
import { Ui, box, pressable } from "../ui/ui";
import { Kit, TextSize, subId, measure, frame, say, INK, INK_MUTED, EMBER, EMBER_HOT, ASH_DEEP } from "./kit";
import { FrameLook } from "./frame";
import { spinner } from "./buttons";
import { CHAR_MID, CHAR_LIGHT, outline, dashedOutline, lightFrame, centredY } from "./shapes";

const TOGGLE_TARGET: float32 = 48.0;
const SLOT_WIDTH: float32 = 40.0;
const SLOT_HEIGHT: float32 = 20.0;
const KNOB_WIDTH: float32 = 15.0;
const KNOB_HEIGHT: float32 = 14.0;
const SEGMENTED_HEIGHT: float32 = 36.0;
const SEGMENTED_PADDING: float32 = 7.0;
const RADIO_ROW_HEIGHT: float32 = 48.0;

export enum ToggleState {
	Off,
	On,
	Pending,
	Disabled,
}

// The off shape faded: a sunken slot, a dashed ash rim and a dark knob, so it does not read as
// plain Off.
function disabledToggle(ui: Ui, slotX: float32, slotY: float32): void {
	box(ui, slotX, slotY, SLOT_WIDTH, SLOT_HEIGHT, 0.0, rgba(0.035, 0.031, 0.031, 0.95));
	dashedOutline(ui, slotX, slotY, SLOT_WIDTH, SLOT_HEIGHT, 2.0, 4.0, rgba(0.30, 0.28, 0.27, 1.0));
	box(ui, slotX + 3.0, slotY + 3.0, KNOB_WIDTH, KNOB_HEIGHT, 0.0, rgba(0.24, 0.22, 0.21, 1.0));
}

// True on a tap; the caller flips the state, or makes it Pending while a signature is out.
export function toggle(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, state: ToggleState, tick: int32): boolean {
	const live: boolean = state == ToggleState.Off || state == ToggleState.On;
	const tapped: boolean = pressable(ui, id, x, y, TOGGLE_TARGET, TOGGLE_TARGET) && live;
	const slotX: float32 = x + 4.0;
	const slotY: float32 = y + 14.0;
	const on: boolean = state == ToggleState.On;
	const knobX: float32 = on ? slotX + 22.0 : slotX + 3.0;
	match (state) {
		ToggleState.Disabled => disabledToggle(ui, slotX, slotY),
		ToggleState.Pending => {
			lightFrame(ui, slotX, slotY, SLOT_WIDTH, SLOT_HEIGHT, CHAR_LIGHT);
			spinner(ui, slotX + 12.0, slotY + 2.0, 16.0, tick);
		},
		ToggleState.Off => {
			lightFrame(ui, slotX, slotY, SLOT_WIDTH, SLOT_HEIGHT, CHAR_LIGHT);
			box(ui, knobX, slotY + 3.0, KNOB_WIDTH, KNOB_HEIGHT, 0.0, INK_MUTED);
			box(ui, knobX + 1.0, slotY + 4.0, 13.0, 2.0, 0.0, rgba(1.0, 1.0, 1.0, 0.15));
		},
		ToggleState.On => {
			lightFrame(ui, slotX, slotY, SLOT_WIDTH, SLOT_HEIGHT, EMBER);
			box(ui, knobX, slotY + 3.0, KNOB_WIDTH, KNOB_HEIGHT, 0.0, EMBER_HOT);
			box(ui, knobX + 1.0, slotY + 4.0, 13.0, 2.0, 0.0, rgba(1.0, 1.0, 1.0, 0.35));
			outline(ui, knobX - 1.0, slotY + 2.0, 17.0, 16.0, 1.0, rgba(0.969, 0.549, 0.227, 0.35));
		},
	};
	return tapped;
}

// Returns the active index, new when a segment was tapped.
export function segmented(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, labels: string[], active: int32,
	seed: int32): int32 {
	frame(kit, id, x, y, width, SEGMENTED_HEIGHT, seed, FrameLook.Normal);
	const count: int32 = labels.length as int32;
	const segmentWidth: float32 = (width - 2.0 * SEGMENTED_PADDING) / (count as float32);
	let picked: int32 = active;
	for (let segment: int32 = 0; segment < count; segment += 1) {
		const segmentX: float32 = x + SEGMENTED_PADDING + segmentWidth * (segment as float32);
		if (pressable(ui, subId(id, segment), segmentX, y, segmentWidth, SEGMENTED_HEIGHT)) {
			picked = segment;
		}
		if (segment == active) {
			box(ui, segmentX + 1.0, y + 7.0, segmentWidth - 2.0, SEGMENTED_HEIGHT - 14.0, 0.0, EMBER);
			box(ui, segmentX + 1.0, y + 7.0, segmentWidth - 2.0, 1.0, 0.0, EMBER_HOT);
		} else if (segment > 0 && segment - 1 != active) {
			box(ui, segmentX, y + 10.0, 1.0, SEGMENTED_HEIGHT - 20.0, 0.0, CHAR_MID);
		}
		say(ui, kit, subId(id, segment), labels[segment], segmentX, centredY(kit, labels[segment], 8.0, y, SEGMENTED_HEIGHT),
			segmentWidth, 8.0, segment == active ? ASH_DEEP : INK, 0.5);
	}
	return picked;
}

// A count above zero shows as a small filled pill after the label (points unspent on Tree).
// Returns the active index.
export function tabs(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, labels: string[], counts: int32[],
	active: int32): int32 {
	const count: int32 = labels.length as int32;
	const tabWidth: float32 = width / (count as float32);
	let picked: int32 = active;
	box(ui, x, y + 30.0, width, 1.0, 0.0, CHAR_MID);
	for (let tab: int32 = 0; tab < count; tab += 1) {
		const tabX: float32 = x + tabWidth * (tab as float32);
		if (pressable(ui, subId(id, tab), tabX, y - 8.0, tabWidth, 48.0)) {
			picked = tab;
		}
		const size: TextSize = measure(kit, labels[tab], 8.0);
		const pill: string = counts[tab] > 0 ? counts[tab].toString() : "";
		const pillWidth: float32 = pill == "" ? 0.0 : measure(kit, pill, 8.0).width + 8.0;
		const left: float32 = tabX + (tabWidth - size.width - (pillWidth > 0.0 ? pillWidth + 4.0 : 0.0)) * 0.5;
		say(ui, kit, subId(id, tab), labels[tab], left, y + 10.0, size.width + 2.0, 8.0, tab == active ? EMBER_HOT : INK_MUTED, 0.0);
		if (pillWidth > 0.0) {
			box(ui, left + size.width + 4.0, y + 8.0, pillWidth, 12.0, 0.0, EMBER);
			say(ui, kit, subId(id, tab + 8), pill, left + size.width + 4.0, y + 10.0, pillWidth, 8.0, ASH_DEEP, 0.5);
		}
		if (tab == active) {
			box(ui, tabX + 8.0, y + 28.0, tabWidth - 16.0, 2.0, 0.0, EMBER);
			box(ui, tabX + 8.0, y + 28.0, tabWidth - 16.0, 1.0, 0.0, EMBER_HOT);
		}
	}
	return picked;
}

function radioRing(ui: Ui, x: float32, y: float32, selected: boolean): void {
	const ring: Color = selected ? EMBER_HOT : INK_MUTED;
	box(ui, x + 3.0, y, 6.0, 1.0, 0.0, ring);
	box(ui, x + 3.0, y + 11.0, 6.0, 1.0, 0.0, ring);
	box(ui, x, y + 3.0, 1.0, 6.0, 0.0, ring);
	box(ui, x + 11.0, y + 3.0, 1.0, 6.0, 0.0, ring);
	box(ui, x + 1.0, y + 1.0, 2.0, 2.0, 0.0, ring);
	box(ui, x + 9.0, y + 1.0, 2.0, 2.0, 0.0, ring);
	box(ui, x + 1.0, y + 9.0, 2.0, 2.0, 0.0, ring);
	box(ui, x + 9.0, y + 9.0, 2.0, 2.0, 0.0, ring);
	if (selected) {
		box(ui, x + 3.0, y + 3.0, 6.0, 6.0, 0.0, EMBER_HOT);
	}
}

// A title and a one-line description; the current choice carries a CURRENT tag.
export function radioRow(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, title: string, detail: string,
	selected: boolean, current: boolean): boolean {
	const tapped: boolean = pressable(ui, id, x, y, width, RADIO_ROW_HEIGHT);
	radioRing(ui, x + 4.0, y + 16.0, selected);
	say(ui, kit, id, title, x + 26.0, y + 10.0, width - 100.0, 8.0, selected ? INK : INK_MUTED, 0.0);
	say(ui, kit, subId(id, 0), detail, x + 26.0, y + 26.0, width - 30.0, 8.0, INK_MUTED, 0.0);
	if (current) {
		const size: TextSize = measure(kit, "CURRENT", 8.0);
		box(ui, x + width - size.width - 12.0, y + 8.0, size.width + 10.0, 14.0, 0.0, EMBER);
		say(ui, kit, subId(id, 1), "CURRENT", x + width - size.width - 12.0, y + 11.0, size.width + 10.0, 8.0, ASH_DEEP, 0.5);
	}
	box(ui, x, y + RADIO_ROW_HEIGHT - 1.0, width, 1.0, 0.0, CHAR_MID);
	return tapped;
}
