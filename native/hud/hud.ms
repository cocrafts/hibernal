import { initHudHome, frameHudHome, frameHudOnboarding, frameHudWaiting, frameHudWallpaper } from "./home";
import { HudScreen, hudScreen, waitingStatus } from "./gameAvailability";
import { mournedPet } from "./mourning";
import { gameOwnerState, gameRead } from "../host/host";
import { PetHead, PetHeadHidden, drawUi } from "../ui/ui";
import { dropPointerEvents } from "../input/pointer";
import { inApp } from "../host/host";

export function currentHudScreen(): HudScreen {
	return hudScreen(gameRead(), gameOwnerState(), mournedPet().ok);
}

export function initHud(): void {
	initHudHome();
}

// The wallpaper runs the same core with only the harvest and burrow over the scene.
export function frameHud(petHead: Result<PetHead, PetHeadHidden>, seconds: float32): void {
	if (!inApp()) {
		// Touches on the home screen would otherwise reach the app's next frame as presses.
		dropPointerEvents();
		frameHudWallpaper(petHead, seconds);
		return;
	}
	match (currentHudScreen()) {
		HudScreen.Home => { frameHudHome(petHead, seconds); },
		HudScreen.Onboarding => { frameHudOnboarding(); },
		HudScreen.Waiting => { frameHudWaiting(waitingStatus(gameRead())); },
	};
}

export function drawHud(): void {
	drawUi();
}
