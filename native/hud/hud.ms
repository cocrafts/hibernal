// The HUD over the campfire scene: the Home screen and the screens it opens, or the kit's
// gallery, each asking for the other.

import { initHudHome, frameHudHome, takeGalleryRequest } from "./home";
import { initGallery, frameGallery, takeHomeRequest } from "./gallery";

let showingGallery: boolean = false;

export function initHud(): void {
	initHudHome();
	initGallery();
}

export function frameHud(): void {
	if (showingGallery) {
		frameGallery();
		if (takeHomeRequest()) { showingGallery = false; }
	} else {
		frameHudHome();
		if (takeGalleryRequest()) { showingGallery = true; }
	}
}
