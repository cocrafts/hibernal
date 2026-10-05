// Hibernal on Android: the campfire scene with the HUD over it.
// Build with scripts/buildAndroid.sh.

import { initLab, frameLab, setLabHud } from "./scene/campfireScene";
import { embedRegister } from "@metascript/void/src/sokol/gpu";
import { initHud, frameHud, drawHud } from "./hud/hud";

function register(): void {
	setLabHud(initHud, frameHud, drawHud);
	embedRegister(initLab, frameLab);
}

register();
