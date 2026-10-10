// Hibernal on Android: the campfire scene with the HUD over it.
// Build with scripts/buildAndroid.sh.

import {
	initLab, frameLab, setLabHud, setPetLevel, setPetPreview, setPetPreviewGrey, petHead, sceneSeconds,
} from "./scene/campfireScene";
import { embedRegister } from "@metascript/void/src/sokol/gpu";
import { initHud, frameHud, drawHud } from "./hud/hud";
import { STAND_IN_LEVEL } from "./hud/home";
import { inApp } from "./host/host";
import { currentLivePet } from "./hud/gameAvailability";
import { PET_PREVIEW_X, PET_PREVIEW_Y } from "./hud/onboarding";
import { mournedPet } from "./hud/mourning";

function frameAndroid(): void {
	const live = currentLivePet();
	const mourned: boolean = mournedPet().ok;
	setPetPreview(inApp() && (!live.ok || mourned), PET_PREVIEW_X, PET_PREVIEW_Y);
	setPetPreviewGrey(mourned);
	frameLab();
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
