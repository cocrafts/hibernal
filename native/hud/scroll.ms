// Draw the content shifted up by scrollArea's offset. A drag never taps a widget, and presses
// outside the area are not taken by base-layer widgets; what spills over the area's edges is
// the caller's to cover (screens.ms scrollChrome).

import { rgba } from "@metascript/void/src/void2d/types";
import { Ui, box, cancelPress } from "@metascript/void/src/ui/ui";

const DRAG_SLOP: float32 = 8.0;
const FRICTION: float32 = 0.92;
const RESTING_VELOCITY: float32 = 0.2;
const DRAGGED_GIVE: float32 = 0.5;
const RELEASED_GIVE: float32 = 0.7;
const SCROLLBAR_X: float32 = 352.0;

export interface Scroll {
	offset: float32;
	velocity: float32;
	dragging: boolean;
	startOffset: float32;
	lastY: float32;
	moved: float32;
}

export function scrollState(): Scroll {
	return { offset: 0.0, velocity: 0.0, dragging: false, startOffset: 0.0, lastY: 0.0, moved: 0.0 };
}

function follow(ui: Ui, scroll: Scroll): void {
	const step: float32 = ui.y - scroll.lastY;
	scroll.moved += step < 0.0 ? -step : step;
	scroll.velocity = -step;
	scroll.lastY = ui.y;
	if (scroll.moved > DRAG_SLOP) {
		scroll.offset = scroll.startOffset - (ui.y - ui.pressY);
		cancelPress(ui);
	}
}

function glide(scroll: Scroll): void {
	scroll.offset += scroll.velocity;
	scroll.velocity = scroll.velocity * FRICTION;
	if (scroll.velocity < RESTING_VELOCITY && scroll.velocity > -RESTING_VELOCITY) {
		scroll.velocity = 0.0;
	}
}

// A little give past either end while dragging, pulled back once released.
function clampToContent(scroll: Scroll, maxOffset: float32): void {
	const give: float32 = scroll.dragging ? DRAGGED_GIVE : RELEASED_GIVE;
	if (scroll.offset < 0.0) {
		scroll.offset = scroll.offset * give;
		scroll.velocity = 0.0;
	}
	if (scroll.offset > maxOffset) {
		scroll.offset = maxOffset + (scroll.offset - maxOffset) * give;
		scroll.velocity = 0.0;
	}
	if (!scroll.dragging && scroll.offset > -0.5 && scroll.offset < 0.0) {
		scroll.offset = 0.0;
	}
}

function scrollbar(ui: Ui, scroll: Scroll, top: float32, visible: float32, contentHeight: float32, maxOffset: float32): void {
	const length: float32 = visible * visible / contentHeight;
	const progress: float32 = scroll.offset < 0.0 ? 0.0 : (scroll.offset > maxOffset ? 1.0 : scroll.offset / maxOffset);
	box(ui, SCROLLBAR_X, top + (visible - length) * progress, 2.0, length, 0.0, rgba(0.404, 0.247, 0.188, 0.9));
}

export function scrollArea(ui: Ui, scroll: Scroll, top: float32, bottom: float32, contentHeight: float32): float32 {
	ui.clipTop = top;
	ui.clipBottom = bottom;
	const visible: float32 = bottom - top;
	const maxOffset: float32 = contentHeight > visible ? contentHeight - visible : 0.0;
	if (ui.pressed && ui.pressY >= top && ui.pressY < bottom) {
		scroll.dragging = true;
		scroll.startOffset = scroll.offset;
		scroll.lastY = ui.pressY;
		scroll.moved = 0.0;
		scroll.velocity = 0.0;
	}
	if (scroll.dragging && ui.down && !ui.down2) {
		follow(ui, scroll);
	} else if (scroll.dragging) {
		scroll.dragging = false;
		if (scroll.moved <= DRAG_SLOP) {
			scroll.velocity = 0.0;
		}
	} else {
		glide(scroll);
	}
	clampToContent(scroll, maxOffset);
	if (maxOffset > 0.0) {
		scrollbar(ui, scroll, top, visible, contentHeight, maxOffset);
	}
	return scroll.offset;
}
