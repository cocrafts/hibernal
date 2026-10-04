import { Color, rgba } from "@metascript/void/src/void2d/types";
import { Ui, box } from "../ui/ui";
import { Kit, iconTinted, say, INK, INK_MUTED, EMBER_HOT } from "./kit";
import { CHAR_MID } from "./shapes";

const ASH: Color = rgba(0.30, 0.28, 0.27, 1.0);
const SKULL_TINT: Color = rgba(0.6, 0.58, 0.56, 1.0);
const NOW_GLOW: Color = rgba(0.969, 0.549, 0.227, 0.35);

export enum LineageState {
	Lived,
	Died,
	Now,
}

function diamond(ui: Ui, centreX: float32, y: float32, color: Color): void {
	for (let row: int32 = 0; row < 6; row += 1) {
		const half: float32 = (row < 3 ? row + 1 : 6 - row) as float32;
		box(ui, centreX - half, y + 2.0 + (row as float32) * 1.5, half * 2.0, 1.5, 0.0, color);
	}
}

// One generation on a vertical timeline, joined to the next by a line unless it is the last: an
// ember diamond for the living pet, an ash skull for one that died, a dim diamond for one that
// lived its span.
export function lineageEntry(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, line: string,
	state: LineageState, last: boolean): void {
	const centreX: float32 = x + 8.0;
	if (!last) {
		box(ui, centreX - 1.0, y + 14.0, 2.0, 30.0, 0.0, CHAR_MID);
	}
	match (state) {
		LineageState.Died => iconTinted(kit, id, "skull", centreX - 7.0, y - 1.0, 14.0, SKULL_TINT),
		LineageState.Lived => diamond(ui, centreX, y, ASH),
		LineageState.Now => {
			diamond(ui, centreX, y, EMBER_HOT);
			box(ui, centreX - 6.0, y - 1.0, 12.0, 1.0, 0.0, NOW_GLOW);
			box(ui, centreX - 6.0, y + 12.0, 12.0, 1.0, 0.0, NOW_GLOW);
		},
	};
	say(ui, kit, id, line, x + 24.0, y + 2.0, width - 24.0, 8.0, state == LineageState.Now ? INK : INK_MUTED, 0.0);
}
