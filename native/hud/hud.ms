import { initHudHome, frameHudHome, frameHudOnboarding, frameHudWallpaper } from "./home";
import { currentLivePet } from "./gameAvailability";
import { mournedPet } from "./mourning";
import { PetHead, PetHeadHidden, drawUi } from "../ui/ui";
import { dropPointerEvents } from "../input/pointer";
import { inApp } from "../host/host";

export function initHud(): void {
	initHudHome();
}

// The wallpaper runs the same core with only the harvest and burrow over the scene.
export function frameHud(petHead: Result<PetHead, PetHeadHidden>, seconds: float32): void {
	if (!inApp()) {
		// Touches on the home screen would otherwise reach the app's next frame as presses.
		dropPointerEvents();
		frameHudWallpaper();
		return;
	}
	if (currentLivePet().ok && !mournedPet().ok) {
		frameHudHome(petHead, seconds);
		return;
	}
	frameHudOnboarding();
}

export function drawHud(): void {
	drawUi();
}
