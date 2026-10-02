// Hibernal on Android: void's campfire scene with the HUD over it.
// Build with scripts/buildAndroid.sh.

import { initLab, frameLab, setLabHud } from "@metascript/void/src/examples/grassLabScene";
import { embedRegister } from "@metascript/void/src/sokol/gpu";
import { initHud, frameHud } from "./hud/hud";

function register(): void {
	setLabHud(initHud, frameHud);
	embedRegister(initLab, frameLab);
}

register();
