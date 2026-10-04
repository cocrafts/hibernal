import { rgba } from "@metascript/void/src/void2d/types";
import { Ui, box, pressable } from "../ui/ui";
import { Kit, icon, EMBER_HOT, SCREEN_WIDTH, SCREEN_HEIGHT } from "./kit";

const HALF: float32 = 0.5;
const NODE_TARGET: float32 = 48.0;

export enum NodeShape {
	Small,
	Notable,
	Keystone,
}

export enum NodeState {
	Allocated,
	Reachable,
	Locked,
}

export interface Rectangle {
	x: float32;
	y: float32;
	width: float32;
	height: float32;
}

// The style reference's sheet 6 draws them 40, 56 and 72 px wide at 2.84 px per unit.
function nodeSize(shape: NodeShape): float32 {
	return match (shape) {
		NodeShape.Small => 15.0,
		NodeShape.Notable => 21.0,
		NodeShape.Keystone => 26.0,
	};
}

function nodeIcon(shape: NodeShape, state: NodeState): string {
	const shapeName: string = match (shape) {
		NodeShape.Small => "Small",
		NodeShape.Notable => "Notable",
		NodeShape.Keystone => "Keystone",
	};
	const stateName: string = match (state) {
		NodeState.Allocated => "Allocated",
		NodeState.Reachable => "Reachable",
		NodeState.Locked => "Locked",
	};
	return "node" + shapeName + stateName;
}

export function treeNode(ui: Ui, kit: Kit, id: int32, centreX: float32, centreY: float32, shape: NodeShape, state: NodeState): boolean {
	return treeNodeScaled(ui, kit, id, centreX, centreY, shape, state, 1.0);
}

// At the tree's zoom: the sprite and its touch target grow with it.
export function treeNodeScaled(ui: Ui, kit: Kit, id: int32, centreX: float32, centreY: float32, shape: NodeShape, state: NodeState,
	scale: float32): boolean {
	const target: float32 = NODE_TARGET * (scale > 1.0 ? scale : 1.0);
	const tapped: boolean = pressable(ui, id, centreX - target * HALF, centreY - target * HALF, target, target);
	const size: float32 = nodeSize(shape) * scale;
	icon(kit, id, nodeIcon(shape, state), centreX - size * HALF, centreY - size * HALF, size);
	return tapped;
}

export function treeLink(ui: Ui, fromX: float32, fromY: float32, toX: float32, toY: float32, allocated: boolean): void {
	treeLinkIn(ui, fromX, fromY, toX, toY, allocated, { x: 0.0, y: 0.0, width: SCREEN_WIDTH, height: SCREEN_HEIGHT });
}

// Thin ash, or thick ember when both ends are allocated; only the part inside `clip` is drawn.
export function treeLinkIn(ui: Ui, fromX: float32, fromY: float32, toX: float32, toY: float32, allocated: boolean,
	clip: Rectangle): void {
	const acrossX: float32 = toX - fromX;
	const acrossY: float32 = toY - fromY;
	const lengthX: float32 = acrossX < 0.0 ? -acrossX : acrossX;
	const lengthY: float32 = acrossY < 0.0 ? -acrossY : acrossY;
	const longest: float32 = lengthX > lengthY ? lengthX : lengthY;
	const steps: int32 = longest as int32;
	for (let step: int32 = 0; step <= steps; step += 1) {
		const along: float32 = steps == 0 ? 0.0 : (step as float32) / (steps as float32);
		const x: float32 = fromX + acrossX * along;
		const y: float32 = fromY + acrossY * along;
		if (x < clip.x + 2.0 || y < clip.y + 2.0 || x > clip.x + clip.width - 2.0 || y > clip.y + clip.height - 2.0) {
			continue;
		}
		if (allocated) {
			box(ui, x - 2.0, y - 2.0, 4.0, 4.0, 0.0, rgba(0.969, 0.549, 0.227, 0.18));
			box(ui, x - 1.0, y - 1.0, 2.0, 2.0, 0.0, EMBER_HOT);
		} else {
			box(ui, x - 1.0, y - 1.0, 2.0, 2.0, 0.0, rgba(0.42, 0.40, 0.39, 0.85));
		}
	}
}
