// The pet's character on Home: its three core stats from rules/ (Stats.built: tree, level, talent)
// with the talent, and the 64-node tree laid out as a ring from rules/tree.ms's topology, each node
// explained under a held finger. Read only: the pet allocates on its own.

import { Color, rgba } from "@metascript/void/src/void2d/types";
import { Ui, box, beginOverlay, endOverlay, DESIGN_W } from "../ui/ui";
import { Kit, TextSize, INK, INK_BRIGHT, HOLO_BLUE, HOLO_GREEN, say, measure, subId, beginKitOverlay, endKitOverlay } from "./kit";
import { SkillInfo, skillInfo } from "./skillInfo";
import { Stats } from "../../rules/stats";
import { Talent, TalentKind } from "../../rules/talent";
import {
	Tree,
	NodeKind,
	NodeRole,
	TREE_NODES,
	FIRST_DIRECTION_NODE,
	DIRECTION_NODES,
	CLUSTER_NODES,
	KEYSTONE_GLASS_CANNON,
	roleOf,
	nodeKind,
	clusterOf,
	neighbors,
	has,
	built,
} from "../../rules/tree";

export struct Character {
	level: int32;
	tree: Tree;
	talent: Talent;
}

const LABEL_SIZE: float32 = 8.0;
const VALUE_SIZE: float32 = 16.0;
const FACTOR_SIZE: float32 = 6.0;
const STAT_ROW: float32 = 20.0;
const LABEL_GAP: float32 = 5.0;
const FACTOR_GAP: float32 = 1.0;
const RING_UNIT: float32 = 36.0;
const RING_REACH: float32 = 4.75;
const RING_ALPHA: float32 = 0.95;
const HOLD_REACH: float32 = 16.0;
const HELD_GROWTH: float32 = 1.6;
const NO_NODE: int32 = -1;
const TIP_TEXT: float32 = 8.0;
const TIP_LINE: float32 = 11.0;
const TIP_PAD: float32 = 6.0;
const TIP_EDGE: float32 = 4.0;
const TIP_FINGER: float32 = 34.0;
const DOT_STEP: float32 = 1.5;
const LINE_WIDTH: float32 = 1.5;
const LIT_LINE_WIDTH: float32 = 2.0;
const TURN: float32 = 6.2831853;
const QUARTER: float32 = 1.5707963;

const LOCKED: Color = rgba(0.34, 0.4, 0.48, 1.0);
const REACHABLE: Color = rgba(0.3, 0.58, 0.82, 1.0);
const LINK: Color = rgba(0.45, 0.56, 0.7, 1.0);
const TIP_RIM: Color = rgba(0.25, 0.6, 0.95, 0.9);
const TIP_FILL: Color = rgba(0.01, 0.04, 0.10, 0.94);

struct Point {
	x: float32;
	y: float32;
}

function along(angle: float32, radius: float32, centre: Point): Point {
	return {
		x: centre.x + (Math.cos(angle as float64) as float32) * radius * RING_UNIT,
		y: centre.y + (Math.sin(angle as float64) as float32) * radius * RING_UNIT,
	};
}

function directionAngle(direction: int32): float32 {
	return (0.0 - QUARTER) + TURN * (direction as float32) / 3.0;
}

// Starts and the gate in the middle, each direction a spoke out to its four clusters, the
// keystones on the borders between two spokes.
function placed(id: int32, centre: Point): Point {
	return match (roleOf(id)) {
		NodeRole.Start => along(directionAngle(id) - 0.55, 0.75, centre),
		NodeRole.Gate => centre,
		NodeRole.Keystone => along(directionAngle((id - KEYSTONE_GLASS_CANNON) / 2) + TURN / 6.0
			+ ((id - KEYSTONE_GLASS_CANNON) % 2 == 0 ? (-0.17 as float32) : (0.17 as float32)), 4.35, centre),
		NodeRole.Entry => along(directionAngle((id - FIRST_DIRECTION_NODE) / DIRECTION_NODES), 1.15, centre),
		NodeRole.Fork => along(directionAngle((id - FIRST_DIRECTION_NODE) / DIRECTION_NODES), 1.8, centre),
		NodeRole.Cluster => along(directionAngle((id - FIRST_DIRECTION_NODE) / DIRECTION_NODES)
			+ ((clusterOf(id) as float32) - 1.5) * 0.3,
			2.4 + (((id - FIRST_DIRECTION_NODE) % DIRECTION_NODES - 2) % CLUSTER_NODES) as float32 * 0.55, centre),
	};
}

function nodeSize(id: int32): float32 {
	return match (nodeKind(id)) {
		NodeKind.Start => 9.0,
		NodeKind.Small => 7.0,
		NodeKind.Notable => 11.0,
		NodeKind.Keystone => 12.0,
	};
}

function linked(a: int32, b: int32): boolean {
	return ((neighbors(a) >> (b as uint64)) & 1) == 1 || ((neighbors(b) >> (a as uint64)) & 1) == 1;
}

function dots(ui: Ui, from: Point, to: Point, colour: Color, width: float32): void {
	const acrossX: float32 = to.x - from.x;
	const acrossY: float32 = to.y - from.y;
	const length: float32 = Math.sqrt((acrossX * acrossX + acrossY * acrossY) as float64) as float32;
	const steps: int32 = (length / DOT_STEP) as int32;
	for (let step: int32 = 1; step < steps; step += 1) {
		const share: float32 = (step as float32) / (steps as float32);
		box(ui, from.x + acrossX * share - width * 0.5, from.y + acrossY * share - width * 0.5, width, width, 0.0, faint(colour));
	}
}

function faint(colour: Color): Color {
	return { ...colour, a: colour.a * RING_ALPHA };
}

// Centred on (x, y).
// Centred on (x, y). Holding a finger on a node shows what it does just above the finger.
export function skillRing(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, character: Character): void {
	const centre: Point = { x: x, y: y };
	const disc: float32 = RING_REACH * RING_UNIT;
	for (let a: int32 = 0; a < TREE_NODES; a += 1) {
		for (let b: int32 = a + 1; b < TREE_NODES; b += 1) {
			if (!linked(a, b)) { continue; }
			const lit: boolean = character.tree.has(a) && character.tree.has(b);
			dots(ui, placed(a, centre), placed(b, centre), lit ? HOLO_BLUE : LINK, lit ? LIT_LINE_WIDTH : LINE_WIDTH);
		}
	}
	const held: int32 = heldNode(ui, centre, disc);
	for (let node: int32 = 0; node < TREE_NODES; node += 1) {
		const at: Point = placed(node, centre);
		const size: float32 = nodeSize(node) * (node == held ? HELD_GROWTH : (1.0 as float32));
		const corner: float32 = nodeKind(node) == NodeKind.Keystone ? 1.0 : size * 0.5;
		box(ui, at.x - size * 0.5, at.y - size * 0.5, size, size, corner, faint(stateColour(character.tree, node)));
		if (character.tree.has(node) && nodeKind(node) == NodeKind.Notable) {
			box(ui, at.x - 2.0, at.y - 2.0, 4.0, 4.0, 2.0, faint(INK_BRIGHT));
		}
	}
	if (held != NO_NODE) {
		tooltip(ui, kit, id, held, character.tree);
	}
}

function stateColour(tree: Tree, node: int32): Color {
	if (tree.has(node)) { return HOLO_BLUE; }
	return (neighbors(node) & tree.bits) != 0 ? REACHABLE : LOCKED;
}

function stateLine(tree: Tree, node: int32): string {
	if (tree.has(node)) { return "TAKEN"; }
	return (neighbors(node) & tree.bits) != 0 ? "CAN BE TAKEN NEXT" : "NOT REACHED YET";
}

// The node nearest the finger, if the press began on the ring and the finger is still close to one.
function heldNode(ui: Ui, centre: Point, disc: float32): int32 {
	if (!ui.down || distance(ui.pressX, ui.pressY, centre.x, centre.y) > disc) { return NO_NODE; }
	let nearest: int32 = NO_NODE;
	let best: float32 = HOLD_REACH;
	for (let node: int32 = 0; node < TREE_NODES; node += 1) {
		const at: Point = placed(node, centre);
		const away: float32 = distance(ui.x, ui.y, at.x, at.y);
		if (away < best) {
			best = away;
			nearest = node;
		}
	}
	return nearest;
}

function distance(ax: float32, ay: float32, bx: float32, by: float32): float32 {
	return Math.sqrt(((ax - bx) * (ax - bx) + (ay - by) * (ay - by)) as float64) as float32;
}

// Above the finger, clamped to the screen; under it when there is no room above.
function tooltip(ui: Ui, kit: Kit, id: int32, node: int32, tree: Tree): void {
	const info: SkillInfo = skillInfo(node);
	const lines: string[] = [];
	for (const line of info.lines) { lines.push(line); }
	lines.push(stateLine(tree, node));
	let width: float32 = measure(kit, info.name, TIP_TEXT).width;
	for (const line of lines) {
		width = Math.max(width, measure(kit, line, TIP_TEXT).width);
	}
	width += TIP_PAD * 2.0;
	const height: float32 = TIP_PAD * 2.0 + TIP_LINE * ((lines.length as int32) + 1) as float32;
	const left: float32 = Math.min(Math.max(TIP_EDGE, ui.x - width * 0.5), DESIGN_W - TIP_EDGE - width);
	const above: float32 = ui.y - TIP_FINGER - height;
	const top: float32 = above >= TIP_EDGE ? above : ui.y + TIP_FINGER;
	beginOverlay(ui);
	beginKitOverlay(kit);
	box(ui, left, top, width, height, 3.0, TIP_RIM);
	box(ui, left + 1.0, top + 1.0, width - 2.0, height - 2.0, 2.5, TIP_FILL);
	say(ui, kit, subId(id, 0), info.name, left + TIP_PAD, top + TIP_PAD, width, TIP_TEXT, INK_BRIGHT, 0.0);
	for (let index: int32 = 0; index < (lines.length as int32); index += 1) {
		const last: boolean = index == (lines.length as int32) - 1;
		say(ui, kit, subId(id, 1 + index), lines[index], left + TIP_PAD, top + TIP_PAD + TIP_LINE * ((index + 1) as float32), width,
			TIP_TEXT, last ? HOLO_BLUE : INK, 0.0);
	}
	endKitOverlay(kit);
	endOverlay(ui);
}

function talentFactor(talent: Talent): string {
	const hundredths: int32 = talent.multiplierBps / 100;
	const cents: int32 = hundredths % 100;
	return "X" + (hundredths / 100).toString() + "." + (cents < 10 ? "0" : "") + cents.toString();
}

// Numbers right-aligned on `right`; the talent's factor sits over its stat's name.
function statRow(ui: Ui, kit: Kit, id: int32, right: float32, y: float32, name: string, value: int32, factor: string): void {
	const number: string = value.toString();
	const numberSize: TextSize = measure(kit, number, VALUE_SIZE);
	const x: float32 = right - numberSize.width;
	say(ui, kit, subId(id, 1), number, x, y, numberSize.width + 2.0, VALUE_SIZE, INK_BRIGHT, 0.0);
	const label: TextSize = measure(kit, name, LABEL_SIZE);
	const labelRight: float32 = x - LABEL_GAP;
	const labelY: float32 = y + VALUE_SIZE - LABEL_SIZE - 1.0;
	say(ui, kit, subId(id, 0), name, labelRight - label.width, labelY, label.width + 2.0, LABEL_SIZE, HOLO_BLUE, 0.0);
	if (factor != "") {
		const factorSize: TextSize = measure(kit, factor, FACTOR_SIZE);
		say(ui, kit, subId(id, 2), factor, labelRight - factorSize.width, labelY - FACTOR_SIZE - FACTOR_GAP, factorSize.width + 2.0,
			FACTOR_SIZE, HOLO_GREEN, 0.0);
	}
}

// Right-aligned on `right`, the first row's top at `top`; the talent's factor shows once revealed.
export function characterStats(ui: Ui, kit: Kit, id: int32, right: float32, top: float32, character: Character): void {
	const stats: Stats = Stats.built(character.tree, character.level, character.talent);
	const kind: TalentKind = character.talent.kind;
	const factor: string = kind == TalentKind.None ? "" : talentFactor(character.talent);
	statRow(ui, kit, subId(id, 0), right, top, "FORAGE", stats.forage, kind == TalentKind.Forage ? factor : "");
	statRow(ui, kit, subId(id, 1), right, top + STAT_ROW, "MIGHT", stats.might, kind == TalentKind.Might ? factor : "");
	statRow(ui, kit, subId(id, 2), right, top + STAT_ROW * 2.0, "GRIT", stats.grit, kind == TalentKind.Grit ? factor : "");
}
