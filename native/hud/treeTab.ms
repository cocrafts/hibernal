import { Ui, pressable } from "@metascript/void/src/ui/ui";
import { Kit, frame, icon, say, INK, INK_MUTED, EMBER, EMBER_HOT } from "./kit";
import { FrameLook } from "./frame";
import { ChipKind, textLink, chip } from "./buttons";
import { sheet, sheetTop } from "./overlays";
import { NodeShape, NodeState, Rectangle, treeNodeScaled, treeLinkIn } from "./skillTree";
import { ScreenContext, closeOverlay } from "./screenChrome";

const CLIP: Rectangle = { x: 26.0, y: 156.0, width: 308.0, height: 528.0 };
// screen = SCREEN_ORIGIN + (world - WORLD_ORIGIN) * zoom + pan
const SCREEN_ORIGIN_X: float32 = 180.0;
const SCREEN_ORIGIN_Y: float32 = 420.0;
const WORLD_ORIGIN_X: float32 = 180.0;
const WORLD_ORIGIN_Y: float32 = 480.0;
const ZOOM_MIN: float32 = 0.7;
const ZOOM_MAX: float32 = 2.6;
const PAN_REACH: float32 = 220.0;
const DRAG_SLOP: float32 = 8.0;
const NODE_RADIUS: float32 = 13.0;
const RECENTER_EASE: float32 = 0.2;
const SHEET_HEIGHT: float32 = 220.0;
const SHEET_EASE: float32 = 0.25;
const NO_NODE: int32 = -1;

interface TreeNode {
	x: float32;
	y: float32;
	shape: NodeShape;
	state: NodeState;
	name: string;
	effect: string;
}

interface TreeLink {
	from: int32;
	to: int32;
}

// A gate, three paths with their notables, and keystones between the paths.
const NODES: TreeNode[] = [
	{ x: 180.0, y: 520.0, shape: NodeShape.Notable, state: NodeState.Allocated, name: "GATE", effect: "START" },
	{ x: 180.0, y: 460.0, shape: NodeShape.Small, state: NodeState.Allocated, name: "IRON HIDE", effect: "+6% GRIT" },
	{ x: 110.0, y: 560.0, shape: NodeShape.Small, state: NodeState.Allocated, name: "QUICK HANDS", effect: "+4% SPEED" },
	{ x: 250.0, y: 560.0, shape: NodeShape.Small, state: NodeState.Reachable, name: "DEEP POCKETS", effect: "+6% FORAGE" },
	{ x: 180.0, y: 400.0, shape: NodeShape.Small, state: NodeState.Allocated, name: "BRAWLER", effect: "+10% MIGHT" },
	{ x: 70.0, y: 600.0, shape: NodeShape.Small, state: NodeState.Reachable, name: "SCAVENGER", effect: "+5% LOOT" },
	{ x: 290.0, y: 600.0, shape: NodeShape.Small, state: NodeState.Locked, name: "FORAGER", effect: "+6% FORAGE" },
	{ x: 130.0, y: 640.0, shape: NodeShape.Small, state: NodeState.Locked, name: "LOOKOUT", effect: "+8% ACCURACY" },
	{ x: 230.0, y: 640.0, shape: NodeShape.Small, state: NodeState.Locked, name: "STOCKPILE", effect: "+10% STORE" },
	{ x: 180.0, y: 340.0, shape: NodeShape.Notable, state: NodeState.Reachable, name: "BERSERKER", effect: "+20% MIGHT" },
	{ x: 50.0, y: 650.0, shape: NodeShape.Notable, state: NodeState.Locked, name: "WARDEN", effect: "+15% ARMOR" },
	{ x: 310.0, y: 650.0, shape: NodeShape.Notable, state: NodeState.Locked, name: "HARVEST LORD", effect: "+25% FORAGE" },
	{ x: 110.0, y: 300.0, shape: NodeShape.Keystone, state: NodeState.Locked, name: "BLOOD OATH", effect: "WIN = HEAL 1 HEART" },
	{ x: 250.0, y: 300.0, shape: NodeShape.Keystone, state: NodeState.Locked, name: "LAST STAND", effect: "REVIVE AT 1 HEART" },
];

const LINKS: TreeLink[] = [
	{ from: 0, to: 1 }, { from: 0, to: 2 }, { from: 0, to: 3 }, { from: 1, to: 4 }, { from: 2, to: 5 }, { from: 3, to: 6 },
	{ from: 2, to: 7 }, { from: 3, to: 8 }, { from: 4, to: 9 }, { from: 5, to: 10 }, { from: 6, to: 11 }, { from: 9, to: 12 },
	{ from: 9, to: 13 },
];

// The pan and zoom, and the gesture in progress.
interface TreeView {
	zoom: float32;
	panX: float32;
	panY: float32;
	recentering: boolean;
	touching: boolean;
	pinching: boolean;
	moved: float32;
	startPanX: float32;
	startPanY: float32;
	startZoom: float32;
	startDistance: float32;
	// the world point under the pinch's midpoint
	anchorX: float32;
	anchorY: float32;
	lastX: float32;
	lastY: float32;
	selected: int32;
	sheetOpen: float32;
}

const view: TreeView = {
	zoom: 1.0,
	panX: 0.0,
	panY: 0.0,
	recentering: false,
	touching: false,
	pinching: false,
	moved: 0.0,
	startPanX: 0.0,
	startPanY: 0.0,
	startZoom: 1.0,
	startDistance: 1.0,
	anchorX: 0.0,
	anchorY: 0.0,
	lastX: 0.0,
	lastY: 0.0,
	selected: NO_NODE,
	sheetOpen: 0.0,
};

function absolute(value: float32): float32 {
	return value < 0.0 ? -value : value;
}

function clamped(value: float32, low: float32, high: float32): float32 {
	return value < low ? low : (value > high ? high : value);
}

function squareRoot(value: float32): float32 {
	if (value <= 0.0) {
		return 0.0;
	}
	let root: float32 = value > 1.0 ? value : 1.0;
	for (let step: int32 = 0; step < 12; step += 1) {
		root = (root + value / root) * 0.5;
	}
	return root;
}

function insideClip(x: float32, y: float32): boolean {
	return x >= CLIP.x && x < CLIP.x + CLIP.width && y >= CLIP.y && y < CLIP.y + CLIP.height;
}

function screenX(worldX: float32): float32 {
	return SCREEN_ORIGIN_X + (worldX - WORLD_ORIGIN_X) * view.zoom + view.panX;
}

function screenY(worldY: float32): float32 {
	return SCREEN_ORIGIN_Y + (worldY - WORLD_ORIGIN_Y) * view.zoom + view.panY;
}

function pinch(ui: Ui): void {
	const acrossX: float32 = ui.x2 - ui.x;
	const acrossY: float32 = ui.y2 - ui.y;
	const distance: float32 = squareRoot(acrossX * acrossX + acrossY * acrossY);
	const middleX: float32 = (ui.x + ui.x2) * 0.5;
	const middleY: float32 = (ui.y + ui.y2) * 0.5;
	if (!view.pinching) {
		view.pinching = true;
		view.startDistance = distance < 1.0 ? 1.0 : distance;
		view.startZoom = view.zoom;
		view.anchorX = (middleX - SCREEN_ORIGIN_X - view.panX) / view.zoom + WORLD_ORIGIN_X;
		view.anchorY = (middleY - SCREEN_ORIGIN_Y - view.panY) / view.zoom + WORLD_ORIGIN_Y;
		view.moved = DRAG_SLOP + 1.0;
	}
	view.zoom = clamped(view.startZoom * distance / view.startDistance, ZOOM_MIN, ZOOM_MAX);
	view.panX = middleX - SCREEN_ORIGIN_X - (view.anchorX - WORLD_ORIGIN_X) * view.zoom;
	view.panY = middleY - SCREEN_ORIGIN_Y - (view.anchorY - WORLD_ORIGIN_Y) * view.zoom;
}

function pan(ui: Ui): void {
	if (view.pinching) {
		// Back to one finger: carry on panning from here.
		view.pinching = false;
		view.startPanX = view.panX - (ui.x - ui.pressX);
		view.startPanY = view.panY - (ui.y - ui.pressY);
	}
	view.panX = view.startPanX + (ui.x - ui.pressX);
	view.panY = view.startPanY + (ui.y - ui.pressY);
	view.moved += absolute(ui.x - view.lastX) + absolute(ui.y - view.lastY);
	view.lastX = ui.x;
	view.lastY = ui.y;
}

// One finger pans, two pinch about the point between them. A gesture that moves past the slop is
// a drag, and its release is not a tap on a node.
function gesture(ui: Ui): void {
	if (ui.pressed && insideClip(ui.pressX, ui.pressY)) {
		view.touching = true;
		view.pinching = false;
		view.moved = 0.0;
		view.startPanX = view.panX;
		view.startPanY = view.panY;
		view.lastX = ui.pressX;
		view.lastY = ui.pressY;
		view.recentering = false;
	}
	if (!view.touching) {
		return;
	}
	if (ui.down && ui.down2) {
		pinch(ui);
	} else if (ui.down) {
		pan(ui);
	}
	const reach: float32 = PAN_REACH * view.zoom;
	view.panX = clamped(view.panX, -reach, reach);
	view.panY = clamped(view.panY, -reach, reach);
}

function easeHome(): void {
	view.zoom = view.zoom + (1.0 - view.zoom) * RECENTER_EASE;
	view.panX = view.panX * (1.0 - RECENTER_EASE);
	view.panY = view.panY * (1.0 - RECENTER_EASE);
	const away: float32 = absolute(view.panX) + absolute(view.panY) + absolute(view.zoom - 1.0) * 100.0;
	if (away < 0.5) {
		view.recentering = false;
		view.zoom = 1.0;
		view.panX = 0.0;
		view.panY = 0.0;
	}
}

function nodes(ui: Ui, kit: Kit): void {
	for (const link of LINKS) {
		const from: TreeNode = NODES[link.from];
		const to: TreeNode = NODES[link.to];
		treeLinkIn(ui, screenX(from.x), screenY(from.y), screenX(to.x), screenY(to.y),
			from.state == NodeState.Allocated && to.state == NodeState.Allocated, CLIP);
	}
	const dragged: boolean = view.moved > DRAG_SLOP;
	const radius: float32 = NODE_RADIUS * view.zoom;
	for (let position: int32 = 0; position < NODES.length; position += 1) {
		const node: TreeNode = NODES[position];
		const x: float32 = screenX(node.x);
		const y: float32 = screenY(node.y);
		if (x - radius < CLIP.x || y - radius < CLIP.y || x + radius > CLIP.x + CLIP.width || y + radius > CLIP.y + CLIP.height) {
			continue;
		}
		if (treeNodeScaled(ui, kit, 3510 + position, x, y, node.shape, node.state, view.zoom) && !dragged) {
			view.selected = position;
		}
	}
}

function stateName(state: NodeState): string {
	return match (state) {
		NodeState.Allocated => "TAKEN",
		NodeState.Reachable => "REACHABLE",
		NodeState.Locked => "LOCKED",
	};
}

function shapeName(shape: NodeShape): string {
	return match (shape) {
		NodeShape.Small => "SMALL NODE",
		NodeShape.Notable => "NOTABLE",
		NodeShape.Keystone => "KEYSTONE",
	};
}

function nodeSheet(context: ScreenContext): void {
	const ui: Ui = context.ui;
	const kit: Kit = context.kit;
	const chosen: boolean = view.selected != NO_NODE;
	view.sheetOpen = view.sheetOpen + ((chosen ? 1.0 : 0.0) - view.sheetOpen) * SHEET_EASE;
	if (view.sheetOpen < 0.01 && !chosen) {
		return;
	}
	context.overlayOpen = chosen;
	if (sheet(ui, kit, 3600, SHEET_HEIGHT, view.sheetOpen, 65)) {
		view.selected = NO_NODE;
	}
	const top: float32 = sheetTop(SHEET_HEIGHT, view.sheetOpen);
	// While it slides away the sheet still shows a node: the first.
	const node: TreeNode = NODES[chosen ? view.selected : 0];
	say(ui, kit, 3601, node.name, 32.0, top + 28.0, 220.0, 16.0, INK, 0.0);
	chip(ui, kit, 3602, 32.0, top + 52.0, stateName(node.state), node.state == NodeState.Allocated ? ChipKind.Filled : ChipKind.Outline,
		node.state == NodeState.Locked ? INK_MUTED : EMBER);
	say(ui, kit, 3603, "FIGHTER - " + shapeName(node.shape), 32.0, top + 80.0, 296.0, 8.0, INK_MUTED, 0.0);
	say(ui, kit, 3604, node.effect, 32.0, top + 98.0, 296.0, 8.0, EMBER_HOT, 0.0);
	say(ui, kit, 3605, node.shape == NodeShape.Keystone ? "COST 3 POINTS" : "COST 1 POINT", 32.0, top + 116.0, 296.0, 8.0, INK, 0.0);
	say(ui, kit, 3606, "YOUR PET SPENDS ITS OWN POINTS.", 32.0, top + 140.0, 296.0, 8.0, INK_MUTED, 0.0);
	if (textLink(ui, kit, 3607, 284.0, top + 32.0, "CLOSE", true)) {
		view.selected = NO_NODE;
	}
	closeOverlay(ui, kit);
}

export function treeTab(context: ScreenContext): void {
	const ui: Ui = context.ui;
	const kit: Kit = context.kit;
	say(ui, kit, 3500, "POINTS: 2 UNSPENT - 18/30 USED", 16.0, 112.0, 328.0, 8.0, INK, 0.0);
	say(ui, kit, 3501, "WINTER REFUND: 3 AVAILABLE", 16.0, 128.0, 328.0, 8.0, INK_MUTED, 0.0);
	frame(kit, 3502, 16.0, 146.0, 328.0, 548.0, 64, FrameLook.Normal);
	if (view.selected == NO_NODE) {
		gesture(ui);
	}
	if (view.recentering) {
		easeHome();
	}
	const pathX: float32 = screenX(180.0);
	const pathY: float32 = screenY(270.0);
	if (insideClip(pathX, pathY)) {
		say(ui, kit, 3503, "FIGHTER", pathX - 40.0, pathY, 80.0, 8.0, INK_MUTED, 0.5);
	}
	nodes(ui, kit);
	icon(kit, 3530, "recenter", 306.0, 656.0, 26.0);
	if (pressable(ui, 3531, 296.0, 646.0, 48.0, 48.0)) {
		view.recentering = true;
	}
	if (!ui.down) {
		view.touching = false;
	}
	say(ui, kit, 3532, "DRAG TO PAN - PINCH TO ZOOM", 16.0, 706.0, 328.0, 8.0, INK_MUTED, 0.5);
	nodeSheet(context);
}
