import { Color, rgba } from "@metascript/void/src/void2d/types";
import { Ui, box } from "../ui/ui";
import { Kit, measure } from "./kit";

export const CHAR_DEEP: Color = rgba(0.161, 0.110, 0.102, 1.0);
export const CHAR_MID: Color = rgba(0.243, 0.149, 0.125, 1.0);
export const CHAR_LIGHT: Color = rgba(0.404, 0.247, 0.188, 1.0);
export const PLANK_DARK: Color = rgba(0.094, 0.071, 0.063, 0.96);

export function outline(ui: Ui, x: float32, y: float32, width: float32, height: float32, thickness: float32, color: Color): void {
	box(ui, x, y, width, thickness, 0.0, color);
	box(ui, x, y + height - thickness, width, thickness, 0.0, color);
	box(ui, x, y + thickness, thickness, height - 2.0 * thickness, 0.0, color);
	box(ui, x + width - thickness, y + thickness, thickness, height - 2.0 * thickness, 0.0, color);
}

export function horizontalDashes(ui: Ui, x: float32, y: float32, width: float32, dash: float32, step: float32, color: Color): void {
	let along: float32 = 0.0;
	while (along < width) {
		box(ui, x + along, y, along + dash < width ? dash : width - along, 1.0, 0.0, color);
		along += step;
	}
}

export function verticalDashes(ui: Ui, x: float32, y: float32, height: float32, dash: float32, step: float32, color: Color): void {
	let along: float32 = 0.0;
	while (along < height) {
		box(ui, x, y + along, 1.0, along + dash < height ? dash : height - along, 0.0, color);
		along += step;
	}
}

export function dashedOutline(ui: Ui, x: float32, y: float32, width: float32, height: float32, dash: float32, step: float32,
	color: Color): void {
	horizontalDashes(ui, x, y, width, dash, step, color);
	horizontalDashes(ui, x, y + height - 1.0, width, dash, step, color);
	verticalDashes(ui, x, y, height, dash, step, color);
	verticalDashes(ui, x + width - 1.0, y, height, dash, step, color);
}

// The light frame weight: plank fill and a two-unit rim, dark outside and `rim` inside, its
// corners cut.
export function lightFrame(ui: Ui, x: float32, y: float32, width: float32, height: float32, rim: Color): void {
	box(ui, x + 1.0, y + 1.0, width - 2.0, height - 2.0, 0.0, PLANK_DARK);
	box(ui, x + 1.0, y, width - 2.0, 1.0, 0.0, CHAR_DEEP);
	box(ui, x + 1.0, y + height - 1.0, width - 2.0, 1.0, 0.0, CHAR_DEEP);
	box(ui, x, y + 1.0, 1.0, height - 2.0, 0.0, CHAR_DEEP);
	box(ui, x + width - 1.0, y + 1.0, 1.0, height - 2.0, 0.0, CHAR_DEEP);
	outline(ui, x + 1.0, y + 1.0, width - 2.0, height - 2.0, 1.0, rim);
}

export function centredY(kit: Kit, line: string, size: float32, y: float32, height: float32): float32 {
	const half: float32 = 0.5;
	return y + (height - measure(kit, line, size).height) * half;
}

export function withAlpha(color: Color, alpha: float32): Color {
	return rgba(color.r, color.g, color.b, alpha);
}
