// The HUD over the campfire scene: the Home screen and the screens it opens, or the kit's
// gallery, each asking for the other.

import { initHudHome, frameHudHome, takeGalleryRequest } from "./home";
import { initGallery, frameGallery, takeHomeRequest } from "./gallery";
import { drawUi } from "../ui/ui";
import { dropPointerEvents } from "../input/pointer";
import { inApp } from "../host/host";

let showingGallery: boolean = false;

export function initHud(): void {
	initHudHome();
	initGallery();
}

// The wallpaper draws the scene alone: it runs the same core with the HUD off (BRIEF §5.6).
export function frameHud(): void {
	if (!inApp()) {
		// Touches on the home screen would otherwise reach the app's next frame as presses.
		dropPointerEvents();
		return;
	}
	if (showingGallery) {
		frameGallery();
		if (takeHomeRequest()) { showingGallery = false; }
	} else {
		frameHudHome();
		if (takeGalleryRequest()) { showingGallery = true; }
	}
}

export function drawHud(): void {
	drawUi();
}
