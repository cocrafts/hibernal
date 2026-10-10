import { Color, rgba } from "@metascript/void/src/void2d/types";
import {
	BoxStyle, uniformRadii, uniformBorders, dashed,
} from "@metascript/void/src/void2d/boxStyle";
import { Ui, box, pressable, DESIGN_W } from "../ui/ui";
import {
	Kit, TextSize, INK, INK_BRIGHT, HOLO_BLUE, HOLO_GREEN, say, measure, subId,
} from "./kit";
import { SkillInfo, skillInfo } from "./skillInfo";
import { infoPanel } from "./shapes";
import {
	SkillPoint, skillPoint, branchLabelPoint, selectSkill, SKILL_LAYOUT_SCALE,
} from "./skillLayout";
import { Stats, Region } from "../../rules/stats";
import { Talent, TalentKind } from "../../rules/talent";
import { BPS } from "../../rules/units";
import {
	Tree, NodeKind, NodeRole, TREE_NODES, CLUSTER_NODES, GATE,
	roleOf, nodeKind, regionOf, nodeCost, neighbors, has, built,
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
export const STAT_COLUMN_HEIGHT: float32 = STAT_ROW * 3.0;
const LABEL_GAP: float32 = 5.0;
const FACTOR_GAP: float32 = 1.0;
const DOT_STEP: float32 = 1.0;
const NO_NODE: int32 = -1;
const TREE_REACH: float32 = 163.0;
const TIP_TEXT: float32 = 7.0;
const TIP_LINE: float32 = 10.0;
const TIP_PAD: float32 = 8.0;
const NODE_FILL: Color = rgba(0.05, 0.08, 0.095, 1.0);
const LINK: Color = rgba(0.23, 0.30, 0.34, 1.0);
const ACTIVE_LINK: Color = rgba(1.0, 0.56, 0.30, 1.0);
const KEYSTONE: Color = rgba(0.68, 0.54, 0.86, 1.0);
// Void draws a dash twice the border's width with a gap of one width, so the width sets the dash length.
const GUIDE_WIDTH: float32 = 1.4;
const GUIDE: Color = rgba(0.78, 0.86, 0.92, 0.55);

export function regionColour(region: Region): Color {
	return match (region) {
		Region.Worker => rgba(0.93, 0.70, 0.27, 1.0),
		Region.Fighter => rgba(0.95, 0.40, 0.33, 1.0),
		Region.Survivor => rgba(0.26, 0.75, 0.65, 1.0),
	};
}

export function regionName(region: Region): string {
	return match (region) {
		Region.Worker => "WORKER",
		Region.Fighter => "FIGHTER",
		Region.Survivor => "SURVIVOR",
	};
}

function placed(node: int32, centre: SkillPoint): SkillPoint {
	const point = skillPoint(node);
	return { x: centre.x + point.x, y: centre.y + point.y };
}

function nodeSize(node: int32): float32 {
	return match (nodeKind(node)) {
		NodeKind.Start => 18.0,
		NodeKind.Small => 12.0,
		NodeKind.Notable => 16.0,
		NodeKind.Keystone => 18.0,
	};
}

function nodeColour(node: int32): Color {
	if (roleOf(node) == NodeRole.Keystone) { return KEYSTONE; }
	const region = regionOf(node);
	if (region.ok) { return regionColour(region.value); }
	return rgba(0.58, 0.68, 0.73, 1.0);
}

function nodeLabel(node: int32): string {
	return match (roleOf(node)) {
		NodeRole.Start => "S" + node.toString(),
		NodeRole.Gate => "C",
		_ => node.toString(),
	};
}

function dots(ui: Ui, from: SkillPoint, to: SkillPoint, colour: Color,
	width: float32, dashed: boolean): void {
	const acrossX: float32 = to.x - from.x;
	const acrossY: float32 = to.y - from.y;
	const length: float32 = Math.sqrt(
		((acrossX * acrossX) + (acrossY * acrossY)) as float64) as float32;
	const steps: int32 = Math.max(1, (length / DOT_STEP) as int32);
	for (let step: int32 = 0; step <= steps; step += 1) {
		if (dashed && step % 8 >= 4) { continue; }
		const share: float32 = (step as float32) / (steps as float32);
		box(ui, from.x + acrossX * share - width * 0.5,
			from.y + acrossY * share - width * 0.5, width, width, 0.0, colour);
	}
}

function linked(a: int32, b: int32): boolean {
	return (neighbors(a) & ((1 as uint64) << (b as uint64))) != 0;
}

export function skillRing(ui: Ui, kit: Kit, id: int32, x: float32, y: float32,
	character: Character, selected: int32): int32 {
	const centre: SkillPoint = { x: x, y: y };
	let selectedNode: int32 = selected;
	if (pressable(ui, id, x - TREE_REACH, y - TREE_REACH,
		TREE_REACH * 2.0, TREE_REACH * 2.0)) {
		selectedNode = selectSkill(selected,
			{ x: ui.pressX - x, y: ui.pressY - y },
			{ x: ui.releaseX - x, y: ui.releaseY - y });
	}
	for (let ring: int32 = 0; ring < CLUSTER_NODES + 2; ring += 1) {
		const baseRadius: float32 = match (ring) {
			0 => 95.0,
			1 => 150.0,
			_ => 205.0 + ((ring - 2) as float32) * 113.0 / ((CLUSTER_NODES - 1) as float32),
		};
		const radius: float32 = baseRadius * SKILL_LAYOUT_SCALE;
		const guide = BoxStyle.create(uniformRadii(radius), uniformBorders(GUIDE_WIDTH), GUIDE).dashed();
		box(ui, x - radius, y - radius, radius * 2.0, radius * 2.0,
			radius, rgba(0.0, 0.0, 0.0, 0.0), guide);
	}
	for (let a: int32 = 0; a < TREE_NODES; a += 1) {
		for (let b: int32 = a + 1; b < TREE_NODES; b += 1) {
			if (!linked(a, b)) { continue; }
			const owned: boolean = character.tree.has(a) && character.tree.has(b);
			dots(ui, placed(a, centre), placed(b, centre),
				owned ? ACTIVE_LINK : LINK, owned ? 1.8 : 1.0,
				(a == GATE || b == GATE) && !owned);
		}
	}
	for (let node: int32 = 0; node < TREE_NODES; node += 1) {
		const point = placed(node, centre);
		const size: float32 = nodeSize(node);
		const owned: boolean = character.tree.has(node);
		const connected: boolean = (neighbors(node) & character.tree.bits) != 0;
		const colour: Color = nodeColour(node);
		const border: Color = owned || connected ? colour
			: rgba(colour.r * 0.72, colour.g * 0.72, colour.b * 0.72, 1.0);
		if (node == selectedNode) {
			box(ui, point.x - size * 0.5 - 2.0, point.y - size * 0.5 - 2.0,
				size + 4.0, size + 4.0, (size + 4.0) * 0.5, INK_BRIGHT);
		}
		box(ui, point.x - size * 0.5, point.y - size * 0.5,
			size, size, size * 0.5, border);
		if (!owned) {
			const inner: float32 = size - 2.4;
			box(ui, point.x - inner * 0.5, point.y - inner * 0.5,
				inner, inner, inner * 0.5, NODE_FILL);
		}
		say(ui, kit, subId(id, 100 + node), nodeLabel(node),
			point.x - size * 0.5, point.y - 3.0, size, 5.5,
			owned ? NODE_FILL : INK_BRIGHT, 0.5);
	}
	for (const region of [Region.Worker, Region.Fighter, Region.Survivor]) {
		const point = branchLabelPoint(region as int32);
		say(ui, kit, subId(id, 180 + (region as int32)), regionName(region),
			x + point.x - 25.0, y + point.y - 4.0, 50.0, 7.0,
			regionColour(region), 0.5);
	}
	return selectedNode;
}

export function skillPreview(ui: Ui, kit: Kit, id: int32, top: float32,
	selected: int32, tree: Tree, live: boolean): void {
	const width: float32 = DESIGN_W - 24.0;
	infoPanel(ui, 12.0, top, width);
	const left: float32 = 12.0 + TIP_PAD;
	const contentWidth: float32 = width - TIP_PAD * 2.0;
	if (selected == NO_NODE) {
		say(ui, kit, subId(id, 0), live ? "TAP A NODE TO VIEW" : "TAP A NODE TO PREVIEW", left, top + TIP_PAD,
			contentWidth, 9.0, INK_BRIGHT, 0.0);
		say(ui, kit, subId(id, 1), "FILLED: OWNED / RING: NOT OWNED", left, top + 27.0,
			contentWidth, TIP_TEXT, INK, 0.0);
	} else {
		const info: SkillInfo = skillInfo(selected);
		say(ui, kit, subId(id, 0), nodeLabel(selected) + " / " + info.name,
			left, top + TIP_PAD, contentWidth, 9.0, nodeColour(selected), 0.0);
		let displayedLine: int32 = 0;
		for (let line: int32 = 0; line < (info.lines.length as int32); line += 1) {
			if (info.lines[line].startsWith("COSTS ")) { continue; }
			say(ui, kit, subId(id, 1 + line), info.lines[line], left,
				top + 23.0 + (displayedLine as float32) * TIP_LINE, contentWidth,
				TIP_TEXT, INK_BRIGHT, 0.0);
			displayedLine += 1;
		}
		const cost: string = roleOf(selected) == NodeRole.Start ? "START AT CREATION"
			: "COST " + nodeCost(selected).toString() + " POINTS";
		say(ui, kit, subId(id, 10), cost, left, top + 76.0,
			contentWidth * 0.5, TIP_TEXT, INK, 0.0);
		const status: string = tree.has(selected) ? (live ? "OWNED" : "OWNED IN PREVIEW")
			: (neighbors(selected) & tree.bits) != 0 ? "CONNECTED TO OWNED" : "NOT CONNECTED";
		say(ui, kit, subId(id, 11), status, left + contentWidth * 0.5, top + 76.0,
			contentWidth * 0.5, TIP_TEXT, INK_BRIGHT, 0.0);
	}
	// A live Pet's brain spends its points on chain; only the preview has upgrades still to wire.
	if (live) { return; }
	say(ui, kit, subId(id, 12), "UI PREVIEW / SKILL UPGRADES NOT CONNECTED",
		left, top + 93.0, contentWidth, 6.0, HOLO_BLUE, 0.0);
}

function talentFactor(talent: Talent): string {
	let fraction: string = (BPS + talent.multiplierBps % BPS).toString().substring(1, 5);
	while (fraction.length > 2 && fraction.endsWith("0")) {
		fraction = fraction.substring(0, fraction.length - 1);
	}
	return "X" + (talent.multiplierBps / BPS).toString() + "." + fraction;
}

function statRow(ui: Ui, kit: Kit, id: int32, right: float32, y: float32,
	name: string, value: int32, factor: string): void {
	const number: string = value.toString();
	const numberSize: TextSize = measure(kit, number, VALUE_SIZE);
	const x: float32 = right - numberSize.width;
	say(ui, kit, subId(id, 1), number, x, y, numberSize.width + 2.0,
		VALUE_SIZE, INK_BRIGHT, 0.0);
	const label: TextSize = measure(kit, name, LABEL_SIZE);
	const labelRight: float32 = x - LABEL_GAP;
	const labelY: float32 = y + VALUE_SIZE - LABEL_SIZE - 1.0;
	say(ui, kit, subId(id, 0), name, labelRight - label.width, labelY,
		label.width + 2.0, LABEL_SIZE, HOLO_BLUE, 0.0);
	if (factor != "") {
		const factorSize: TextSize = measure(kit, factor, FACTOR_SIZE);
		say(ui, kit, subId(id, 2), factor, labelRight - factorSize.width,
			labelY - FACTOR_SIZE - FACTOR_GAP, factorSize.width + 2.0,
			FACTOR_SIZE, HOLO_GREEN, 0.0);
	}
}

export enum NoLeaning {
	Tied,
}

// The region of the Pet's highest stat; a tie for the top leans nowhere.
export function leaning(forage: int32, might: int32, grit: int32): Result<Region, NoLeaning> {
	if (forage > might && forage > grit) { return Result.ok(Region.Worker); }
	if (might > forage && might > grit) { return Result.ok(Region.Fighter); }
	if (grit > forage && grit > might) { return Result.ok(Region.Survivor); }
	return Result.err(NoLeaning.Tied);
}

export function characterLeaning(character: Character): Result<Region, NoLeaning> {
	const stats: Stats = Stats.built(character.tree, character.level, character.talent);
	return leaning(stats.forage, stats.might, stats.grit);
}

export function characterStats(ui: Ui, kit: Kit, id: int32, right: float32,
	top: float32, character: Character): void {
	const stats: Stats = Stats.built(character.tree, character.level, character.talent);
	statColumn(ui, kit, id, right, top, stats.forage, stats.might, stats.grit, character.talent);
}

// A neighbour's stats come from its Pet account, which has no tree to build them from.
export function statColumn(ui: Ui, kit: Kit, id: int32, right: float32, top: float32, forage: int32, might: int32,
	grit: int32, talent: Talent): void {
	const kind: TalentKind = talent.kind;
	const factor: string = kind == TalentKind.None ? "" : talentFactor(talent);
	statRow(ui, kit, subId(id, 0), right, top, "FORAGE", forage,
		kind == TalentKind.Forage ? factor : "");
	statRow(ui, kit, subId(id, 1), right, top + STAT_ROW, "MIGHT", might,
		kind == TalentKind.Might ? factor : "");
	statRow(ui, kit, subId(id, 2), right, top + STAT_ROW * 2.0, "GRIT", grit,
		kind == TalentKind.Grit ? factor : "");
}
