import { Color, rgba } from "@metascript/void/src/void2d/types";
import { Ui, box, beginOverlay, endOverlay } from "@metascript/void/src/ui/ui";
import { Kit, beginKitOverlay, endKitOverlay, fill, say, INK, INK_MUTED, SCREEN_WIDTH, SCREEN_HEIGHT } from "./kit";
import { Toasts } from "./notices";
import { CHAR_MID } from "./shapes";

export const SCROLL_BOTTOM: float32 = 720.0;
const BACKDROP: Color = rgba(0.035, 0.031, 0.031, 0.93);
const COVER: Color = rgba(0.035, 0.031, 0.031, 1.0);

export enum Nav {
	Stay,
	Home,
	Pet,
	Block,
	Shop,
	Digest,
	Settings,
	Gallery,
}

// What every screen draws with, and what it hands back to home.ms: where to go next and
// whether a sheet or modal of its own is taking the touches.
export interface ScreenContext {
	ui: Ui;
	kit: Kit;
	toasts: Toasts;
	tick: int32;
	navigate: Nav;
	overlayOpen: boolean;
}

export function backdrop(kit: Kit): void {
	fill(kit, 1, 0.0, 0.0, SCREEN_WIDTH, SCREEN_HEIGHT, BACKDROP);
}

export function openOverlay(ui: Ui, kit: Kit): void {
	beginOverlay(ui);
	beginKitOverlay(kit);
}

export function closeOverlay(ui: Ui, kit: Kit): void {
	endOverlay(ui);
	endKitOverlay(kit);
}

// For a scrolling screen: covers what scrolled above `top` and below the dock line on the
// overlay, which it leaves open for the fixed header; close it with closeOverlay.
export function scrollChrome(context: ScreenContext, top: float32): void {
	openOverlay(context.ui, context.kit);
	fill(context.kit, 2, 0.0, 0.0, SCREEN_WIDTH, top, COVER);
	fill(context.kit, 3, 0.0, SCROLL_BOTTOM, SCREEN_WIDTH, SCREEN_HEIGHT - SCROLL_BOTTOM, COVER);
}

export function screenTitle(context: ScreenContext, id: int32, line: string, right: string): void {
	say(context.ui, context.kit, id, line, 16.0, 30.0, 220.0, 16.0, INK, 0.0);
	if (right != "") {
		say(context.ui, context.kit, id + 1, right, 140.0, 34.0, 204.0, 8.0, INK_MUTED, 1.0);
	}
	box(context.ui, 16.0, 52.0, 328.0, 1.0, 0.0, CHAR_MID);
}
