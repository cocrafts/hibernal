// Hibernal on Android: the campfire scene with the HUD over it.
// Build with scripts/buildAndroid.sh.

import {
	initLab, frameLab, setLabHud, setPetLevel, setPetPreview, setPetPreviewGrey, petHead, sceneSeconds,
} from "./scene/campfireScene";
import { embedRegister } from "@metascript/void/src/sokol/gpu";
import { initHud, frameHud, drawHud, currentHudScreen } from "./hud/hud";
import { STAND_IN_LEVEL } from "./hud/home";
import { inApp } from "./host/host";
import { HudScreen } from "./hud/gameAvailability";
import { PET_PREVIEW_X, PET_PREVIEW_Y } from "./hud/onboarding";
import { mournedPet } from "./hud/mourning";

function frameAndroid(): void {
	const screen: HudScreen = inApp() ? currentHudScreen() : HudScreen.Home;
	const mourned: boolean = mournedPet().ok;
	// On the wallpaper a dead Pet stands grey where the death screen shows it, instead of walking.
	const wallpaperMourning: boolean = !inApp() && mourned;
	setPetPreview(screen == HudScreen.Onboarding || wallpaperMourning, PET_PREVIEW_X, PET_PREVIEW_Y);
	setPetPreviewGrey(mourned);
	frameLab(true, screen != HudScreen.Waiting && !wallpaperMourning);
}

// After the scene placed the Pet, so the HUD draws over its head this frame.
function prepareHud(): void {
	frameHud(petHead(), sceneSeconds());
}

function register(): void {
	setLabHud(initHud, prepareHud, drawHud);
	setPetLevel(STAND_IN_LEVEL);
	embedRegister(initLab, frameAndroid);
}

register();
