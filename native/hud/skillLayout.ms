import {
	TREE_NODES, GATE, FIRST_DIRECTION_NODE, DIRECTION_NODES,
	CLUSTERS, CLUSTER_NODES, KEYSTONE_GLASS_CANNON,
	NodeRole, NodeKind, roleOf, nodeKind, clusterOf,
} from "../../rules/tree";

export const SKILL_LAYOUT_SCALE: float32 = 0.45;
const TURN: float32 = 6.2831853;
const QUARTER: float32 = 1.5707963;
const HIT_RADIUS: float32 = 14.0;

export struct SkillPoint {
	x: float32;
	y: float32;
}

export enum SkillHitError {
	Outside,
}

function polar(radius: float32, angle: float32): SkillPoint {
	return {
		x: (Math.cos(angle as float64) as float32) * radius * SKILL_LAYOUT_SCALE,
		y: (Math.sin(angle as float64) as float32) * radius * SKILL_LAYOUT_SCALE,
	};
}

function directionAngle(direction: int32): float32 {
	return -QUARTER + TURN * (direction as float32) / 3.0;
}

export function branchLabelPoint(direction: int32): SkillPoint {
	return polar(368.0, directionAngle(direction));
}

export function skillPoint(id: int32): SkillPoint {
	if (id < 0 || id >= TREE_NODES) {
		console.log("skill layout: node outside rules tree: " + id.toString());
		unreachable;
	}
	const direction: int32 = (id - FIRST_DIRECTION_NODE) / DIRECTION_NODES;
	return match (roleOf(id)) {
		NodeRole.Start => polar(62.0, directionAngle(id) - TURN / 15.0),
		NodeRole.Gate => ({ x: 0.0, y: 0.0 }),
		NodeRole.Entry => polar(95.0, directionAngle(direction)),
		NodeRole.Fork => polar(150.0, directionAngle(direction)),
		NodeRole.Cluster => {
			const step: int32 = ((id - FIRST_DIRECTION_NODE) % DIRECTION_NODES - 2)
				% CLUSTER_NODES;
			const radius: float32 = 205.0
				+ (step as float32) * 113.0 / ((CLUSTER_NODES - 1) as float32);
			const angle: float32 = directionAngle(direction) - TURN / 6.0
				+ ((clusterOf(id) as float32) + 0.5) * TURN / (3.0 * (CLUSTERS as float32));
			return polar(radius, angle);
		},
		NodeRole.Keystone => {
			const offset: int32 = id - KEYSTONE_GLASS_CANNON;
			const spread: float32 = offset % 2 == 0 ? -TURN / 60.0 : TURN / 60.0;
			return polar(326.0, directionAngle(offset / 2) + TURN / 6.0 + spread);
		},
	};
}

export function nearestSkill(point: SkillPoint): Result<int32, SkillHitError> {
	let nearest: Result<int32, SkillHitError> = Result.err(SkillHitError.Outside);
	let best: float32 = HIT_RADIUS * HIT_RADIUS;
	for (let id: int32 = 0; id < TREE_NODES; id += 1) {
		const at = skillPoint(id);
		const dx: float32 = point.x - at.x;
		const dy: float32 = point.y - at.y;
		const squared: float32 = dx * dx + dy * dy;
		if (squared < best) {
			best = squared;
			nearest = Result.ok(id);
		}
	}
	return nearest;
}

export function selectSkill(selected: int32, press: SkillPoint, release: SkillPoint): int32 {
	const began = nearestSkill(press);
	const ended = nearestSkill(release);
	if (began.ok && ended.ok) {
		if (began.value == ended.value) { return ended.value; }
	}
	return selected;
}

test "all 64 canonical nodes occupy distinct selectable positions" {
	assert TREE_NODES == 64;
	for (let id: int32 = 0; id < TREE_NODES; id += 1) {
		const point = skillPoint(id);
		const hit = nearestSkill(point);
		assert hit.ok;
		if (hit.ok) { assert hit.value == id; }
		assert Math.abs(point.x) < 160.0 && Math.abs(point.y) < 160.0;
		if (nodeKind(id) == NodeKind.Notable) {
			const radius: float32 = 318.0 * SKILL_LAYOUT_SCALE;
			assert Math.abs(point.x * point.x + point.y * point.y - radius * radius) < 0.05;
		}
		for (let other: int32 = id + 1; other < TREE_NODES; other += 1) {
			const next = skillPoint(other);
			const dx: float32 = point.x - next.x;
			const dy: float32 = point.y - next.y;
			assert dx * dx + dy * dy > 200.0;
		}
	}
}

test "tap persists selection but drag and empty space leave it unchanged" {
	const gate = skillPoint(GATE);
	const first = skillPoint(FIRST_DIRECTION_NODE);
	assert selectSkill(-1, gate, gate) == GATE;
	assert selectSkill(GATE, first, first) == FIRST_DIRECTION_NODE;
	assert selectSkill(GATE, gate, first) == GATE;
	assert selectSkill(GATE, { x: 170.0, y: 170.0 }, gate) == GATE;
	assert selectSkill(GATE, gate, { x: 170.0, y: 170.0 }) == GATE;
	assert selectSkill(GATE, { x: 170.0, y: 170.0 }, { x: 170.0, y: 170.0 }) == GATE;
}
