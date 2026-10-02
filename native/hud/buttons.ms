import { Color, rgba } from "@metascript/void/src/void2d/types";
import { Ui, box, pressable, held } from "../ui/ui";
import {
	Kit,
	TextSize,
	measure,
	frame,
	badgeFrame,
	icon,
	iconTinted,
	say,
	DIMMED,
	WHITE,
	INK,
	INK_MUTED,
	EMBER,
	EMBER_HOT,
	EMBER_PRESSED,
	ALERT_RED,
	GROWTH_GREEN,
	DISABLED_INK,
	ASH_DEEP,
} from "./kit";
import { FrameLook } from "./frame";
import { outline, dashedOutline } from "./shapes";

const CHIP_HEIGHT: float32 = 16.0;
const CHIP_PADDING: float32 = 5.0;
const CHIP_BACKGROUND: Color = rgba(0.06, 0.05, 0.05, 0.85);
const DASH: float32 = 3.0;
const DASH_STEP: float32 = 5.0;
const BADGE_SIZE: float32 = 40.0;
const SPINNER_DOTS: int32 = 8;
const RING_X: float32[] = [0.0, 0.707, 1.0, 0.707, 0.0, -0.707, -1.0, -0.707];
const RING_Y: float32[] = [-1.0, -0.707, 0.0, 0.707, 1.0, 0.707, 0.0, -0.707];

export enum ButtonStyle {
	Primary,
	Danger,
}

export enum SignState {
	Idle,
	Waiting,
	Done,
	Failed,
	Disabled,
}

export enum ChipKind {
	Outline,
	Filled,
	Dashed,
}

function buttonLook(style: ButtonStyle, enabled: boolean): FrameLook {
	return match (style) {
		_ when !enabled => FrameLook.Disabled,
		ButtonStyle.Danger => FrameLook.Alert,
		ButtonStyle.Primary => FrameLook.Normal,
	};
}

function buttonInk(style: ButtonStyle, enabled: boolean, down: boolean): Color {
	return match (style) {
		_ when !enabled => DISABLED_INK,
		_ when down => EMBER_PRESSED,
		ButtonStyle.Danger => ALERT_RED,
		ButtonStyle.Primary => EMBER_HOT,
	};
}

// Pressed, the label drops one unit and burns hotter.
export function button(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, height: float32, label: string,
	style: ButtonStyle, enabled: boolean, seed: int32): boolean {
	const clicked: boolean = pressable(ui, id, x, y, width, height) && enabled;
	const down: boolean = enabled && held(ui, id, x, y, width, height);
	frame(kit, id, x, y, width, height, seed, buttonLook(style, enabled));
	const size: TextSize = measure(kit, label, 8.0);
	say(ui, kit, id, label, x, y + (height - size.height) * 0.5 + (down ? 1.0 : 0.0), width, 8.0,
		buttonInk(style, enabled, down), 0.5);
	return clicked;
}

// The underline is even, with no hot spot at its ends.
export function textLink(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, label: string, enabled: boolean): boolean {
	const width: float32 = measure(kit, label, 8.0).width;
	const clicked: boolean = pressable(ui, id, x - 6.0, y - 14.0, width + 12.0, 36.0) && enabled;
	const down: boolean = enabled && held(ui, id, x - 6.0, y - 14.0, width + 12.0, 36.0);
	const ink: Color = !enabled ? DISABLED_INK : (down ? EMBER_PRESSED : EMBER_HOT);
	say(ui, kit, id, label, x, y + (down ? 1.0 : 0.0), width + 8.0, 8.0, ink, 0.0);
	box(ui, x, y + 11.0, width, 1.0, 0.0, !enabled ? DISABLED_INK : (down ? EMBER_PRESSED : EMBER));
	return clicked;
}

// The bright dot walks round the ring; `tick` counts frames.
export function spinner(ui: Ui, x: float32, y: float32, size: float32, tick: int32): void {
	const head: int32 = (tick / 3) % SPINNER_DOTS;
	const radius: float32 = size * 0.5 - 1.5;
	for (let dot: int32 = 0; dot < SPINNER_DOTS; dot += 1) {
		const age: int32 = (head - dot + SPINNER_DOTS) % SPINNER_DOTS;
		const color: Color = age == 0 ? EMBER_PRESSED : (age < 3 ? EMBER_HOT : EMBER);
		box(ui, x + size * 0.5 + RING_X[dot] * radius - 1.0, y + size * 0.5 + RING_Y[dot] * radius - 1.0, 2.0, 2.0, 0.0,
			rgba(color.r, color.g, color.b, age < 4 ? 1.0 : 0.45));
	}
}

interface SignFace {
	look: FrameLook;
	caption: string;
	ink: Color;
	glyph: string;
}

function signFace(state: SignState, label: string, down: boolean): SignFace {
	const ready: Color = down ? EMBER_PRESSED : EMBER_HOT;
	return match (state) {
		SignState.Idle => ({ look: FrameLook.Normal, caption: label, ink: ready, glyph: "wallet" }),
		SignState.Waiting => ({ look: FrameLook.Disabled, caption: "WALLET...", ink: INK_MUTED, glyph: "" }),
		SignState.Done => ({ look: FrameLook.Normal, caption: "DONE", ink: GROWTH_GREEN, glyph: "" }),
		SignState.Failed => ({ look: FrameLook.Alert, caption: "RETRY", ink: ALERT_RED, glyph: "warning" }),
		SignState.Disabled => ({ look: FrameLook.Disabled, caption: label, ink: DISABLED_INK, glyph: "wallet" }),
	};
}

// Hands off to the wallet; clickable while Idle or Failed.
export function signButton(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, height: float32, label: string,
	state: SignState, seed: int32, tick: int32): boolean {
	const live: boolean = state == SignState.Idle || state == SignState.Failed;
	const clicked: boolean = pressable(ui, id, x, y, width, height) && live;
	const down: boolean = live && held(ui, id, x, y, width, height);
	const face: SignFace = signFace(state, label, down);
	frame(kit, id, x, y, width, height, seed, face.look);
	const size: TextSize = measure(kit, face.caption, 8.0);
	const lead: float32 = face.glyph != "" || state == SignState.Waiting ? 22.0 : 0.0;
	const left: float32 = x + (width - size.width - lead) * 0.5;
	const sink: float32 = down ? 1.0 : 0.0;
	const iconY: float32 = y + (height - 16.0) * 0.5 + sink;
	if (state == SignState.Waiting) {
		spinner(ui, left, iconY, 16.0, tick);
	} else if (face.glyph != "") {
		iconTinted(kit, id, face.glyph, left, iconY, 16.0, state == SignState.Disabled ? DIMMED : WHITE);
	}
	say(ui, kit, id, face.caption, left + lead, y + (height - size.height) * 0.5 + sink, size.width + 8.0, 8.0, face.ink, 0.0);
	return clicked;
}

// Returns its width so chips can be laid in a row.
export function chip(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, label: string, kind: ChipKind, color: Color): float32 {
	const size: TextSize = measure(kit, label, 8.0);
	const width: float32 = size.width + 2.0 * CHIP_PADDING;
	match (kind) {
		ChipKind.Filled => box(ui, x, y, width, CHIP_HEIGHT, 0.0, color),
		ChipKind.Outline => {
			box(ui, x, y, width, CHIP_HEIGHT, 0.0, CHIP_BACKGROUND);
			outline(ui, x, y, width, CHIP_HEIGHT, 1.0, color);
		},
		ChipKind.Dashed => {
			box(ui, x, y, width, CHIP_HEIGHT, 0.0, CHIP_BACKGROUND);
			dashedOutline(ui, x, y, width, CHIP_HEIGHT, DASH, DASH_STEP, color);
		},
	};
	say(ui, kit, id, label, x + CHIP_PADDING, y + (CHIP_HEIGHT - size.height) * 0.5, size.width + 2.0, 8.0,
		kind == ChipKind.Filled ? ASH_DEEP : color, 0.0);
	return width;
}

// An icon, and a short number under it when given; true when tapped.
export function badge(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, glyph: string, number: string, seed: int32): boolean {
	const tapped: boolean = pressable(ui, id, x - 4.0, y - 4.0, BADGE_SIZE + 8.0, BADGE_SIZE + 8.0);
	badgeFrame(kit, id, x, y, BADGE_SIZE, seed);
	if (number == "") {
		icon(kit, id, glyph, x + 10.0, y + 10.0, 20.0);
		return tapped;
	}
	const size: TextSize = measure(kit, number, 8.0);
	const top: float32 = y + (BADGE_SIZE - (14.0 + 2.0 + size.height)) * 0.5;
	icon(kit, id, glyph, x + 13.0, top, 14.0);
	say(ui, kit, id, number, x, top + 16.0, BADGE_SIZE, 8.0, INK, 0.5);
	return tapped;
}
