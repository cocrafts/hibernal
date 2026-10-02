import { Color, rgba } from "@metascript/void/src/void2d/types";
import { Ui, box } from "../ui/ui";
import { Kit, TextSize, subId, measure, measureWrapped, badgeFrame, icon, say, INK, INK_MUTED, EMBER } from "./kit";
import { ButtonStyle, button } from "./buttons";
import { CHAR_LIGHT, lightFrame, centredY } from "./shapes";

const OWNER_FILL: Color = rgba(0.200, 0.090, 0.060, 0.96);
const PET_FILL: Color = rgba(0.094, 0.071, 0.063, 0.96);
const INPUT_HEIGHT: float32 = 44.0;
const SEND_WIDTH: float32 = 84.0;

// The owner speaks on the right in ember with whether the line counted; the pet on the left in
// the dark, beside its avatar. Returns the height used, to stack messages.
export function chatBubble(ui: Ui, kit: Kit, id: int32, left: float32, right: float32, y: float32, line: string, owner: boolean,
	counted: boolean, avatarSeed: int32): float32 {
	const maxWidth: float32 = (right - left) - 70.0;
	const size: TextSize = measureWrapped(kit, line, 8.0, maxWidth);
	const width: float32 = size.width + 20.0;
	const height: float32 = size.height + 16.0;
	const x: float32 = owner ? right - width : left + 46.0;
	const rim: Color = owner ? EMBER : CHAR_LIGHT;
	box(ui, x, y, width, height, 0.0, owner ? OWNER_FILL : PET_FILL);
	lightFrame(ui, x, y, width, height, rim);
	for (let step: int32 = 0; step < 3; step += 1) {
		const offset: float32 = (step as float32) * 2.0;
		box(ui, owner ? x + width - 6.0 + offset : x + 4.0 - offset, y + height + (step as float32), 2.0, 1.0, 0.0, rim);
	}
	say(ui, kit, id, line, x + 10.0, y + 8.0, maxWidth + 2.0, 8.0, INK, 0.0);
	if (!owner) {
		badgeFrame(kit, subId(id, 0), left, y + height - 36.0, 36.0, avatarSeed);
		icon(kit, subId(id, 0), "pet", left + 8.0, y + height - 28.0, 20.0);
		const used: float32 = height + 4.0;
		return used;
	}
	const tag: string = counted ? "COUNTED" : "DOESN'T COUNT";
	const tagWidth: float32 = measure(kit, tag, 8.0).width;
	say(ui, kit, subId(id, 1), tag, right - tagWidth - 2.0, y + height + 6.0, tagWidth + 4.0, 8.0, counted ? EMBER : INK_MUTED, 0.0);
	const used: float32 = height + 20.0;
	return used;
}

// SEND is enabled only with text. Typing itself is a native overlay placed with ui.ms
// designToSurfaceX/Y.
export function chatInput(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, typed: string, seed: int32): boolean {
	const fieldWidth: float32 = width - SEND_WIDTH - 8.0;
	lightFrame(ui, x, y, fieldWidth, INPUT_HEIGHT, CHAR_LIGHT);
	const empty: boolean = typed == "";
	const shown: string = empty ? "SAY SOMETHING..." : typed;
	say(ui, kit, id, shown, x + 12.0, centredY(kit, shown, 8.0, y, INPUT_HEIGHT), fieldWidth - 24.0, 8.0, empty ? INK_MUTED : INK, 0.0);
	return button(ui, kit, subId(id, 0), x + width - SEND_WIDTH, y, SEND_WIDTH, INPUT_HEIGHT, "SEND", ButtonStyle.Primary, !empty, seed);
}
