import { START_BONUS, NODE_BONUS, BASE_MAX_HEARTS, Stats, Region, Mod } from "./stats";

export const TREE_NODES: int32 = 24;
export const KEYSTONE_COST: int32 = 3;
export const KEYSTONE_PACIFIST: int32 = 21;
export const KEYSTONE_GLASS_CANNON: int32 = 22;
export const KEYSTONE_CANNIBAL: int32 = 23;

export enum NodeKind {
	Start,
	Small,
	Notable,
	Keystone,
}

export enum AllocationError {
	OutOfRange,
	Taken,
	WrongStart,
	AlreadyStarted,
	NotAdjacent,
	Dead,
	Unsettled,
	NoPoints,
}

export struct Tree {
	bits: uint64;
}

export function empty(this typeof Tree): Tree {
	return { bits: 0 };
}

export function nodeKind(id: int32): NodeKind {
	return match (id) {
		_ when id < 3 => NodeKind.Start,
		_ when id >= 21 => NodeKind.Keystone,
		_ when (id - 3) % 6 == 5 => NodeKind.Notable,
		_ => NodeKind.Small,
	};
}

export function nodeCost(id: int32): int32 {
	return nodeKind(id) == NodeKind.Keystone ? KEYSTONE_COST : 1;
}

export function regionOf(id: int32): Region {
	if (id >= 21) { unreachable; }
	return id < 3 ? id as Region : ((id - 3) / 6) as Region;
}

function offsetOf(id: int32): int32 {
	return (id - 3) % 6;
}

function regionNode(region: Region, offset: int32): int32 {
	return 3 + (region as int32) * 6 + offset;
}

function nodeBit(id: int32): uint32 {
	return (1 as uint32) << (id as uint32);
}

function keystonesTouching(region: Region): uint32 {
	return match (region) {
		Region.Worker => nodeBit(KEYSTONE_PACIFIST) | nodeBit(KEYSTONE_GLASS_CANNON),
		Region.Fighter => nodeBit(KEYSTONE_GLASS_CANNON) | nodeBit(KEYSTONE_CANNIBAL),
		Region.Survivor => nodeBit(KEYSTONE_PACIFIST) | nodeBit(KEYSTONE_CANNIBAL),
	};
}

function regionNeighbors(id: int32): uint32 {
	const region = regionOf(id);
	return match (offsetOf(id)) {
		0 => nodeBit(region as int32) | nodeBit(regionNode(region, 2)),
		1 => nodeBit(region as int32) | nodeBit(regionNode(region, 3)),
		2 => nodeBit(regionNode(region, 0)) | nodeBit(regionNode(region, 4)),
		3 => nodeBit(regionNode(region, 1)) | nodeBit(regionNode(region, 4)),
		4 => nodeBit(regionNode(region, 2)) |
			nodeBit(regionNode(region, 3)) |
			nodeBit(regionNode(region, 5)) |
			keystonesTouching(region),
		_ => nodeBit(regionNode(region, 4)),
	};
}

export function neighbors(id: int32): uint32 {
	return match (id) {
		_ when id < 3 => nodeBit(regionNode(id as Region, 0)) |
			nodeBit(regionNode(id as Region, 1)),
		KEYSTONE_PACIFIST => nodeBit(regionNode(Region.Worker, 4)) |
			nodeBit(regionNode(Region.Survivor, 4)),
		KEYSTONE_GLASS_CANNON => nodeBit(regionNode(Region.Fighter, 4)) |
			nodeBit(regionNode(Region.Worker, 4)),
		KEYSTONE_CANNIBAL => nodeBit(regionNode(Region.Fighter, 4)) |
			nodeBit(regionNode(Region.Survivor, 4)),
		_ => regionNeighbors(id),
	};
}

export function adjacent(first: int32, second: int32): boolean {
	return (neighbors(first) & nodeBit(second)) != 0;
}

export function has(this tree: Tree, id: int32): boolean {
	return ((tree.bits >> (id as uint64)) & 1) == 1;
}

export function withNode(this tree: Tree, id: int32): Tree {
	return { bits: tree.bits | ((1 as uint64) << (id as uint64)) };
}

export function isEmpty(this tree: Tree): boolean {
	return tree.bits == 0;
}

export function touches(this tree: Tree, id: int32): boolean {
	return (neighbors(id) & (tree.bits as uint32)) != 0;
}

export function allocate(
	this tree: Tree,
	id: int32,
	start: Region,
): Result<Tree, AllocationError> {
	if (id < 0 || id >= TREE_NODES) { return Result.err(AllocationError.OutOfRange); }
	if (tree.has(id)) { return Result.err(AllocationError.Taken); }
	if (id < 3) {
		if (id != (start as int32)) { return Result.err(AllocationError.WrongStart); }
		if (!tree.isEmpty()) { return Result.err(AllocationError.AlreadyStarted); }
		return Result.ok(tree.withNode(id));
	}
	if (tree.isEmpty() || !tree.touches(id)) { return Result.err(AllocationError.NotAdjacent); }
	return Result.ok(tree.withNode(id));
}

export function nodeCount(this tree: Tree): int32 {
	let count = 0;
	let remaining = tree.bits;
	while (remaining != 0) {
		remaining = remaining & (remaining - 1);
		count += 1;
	}
	return count;
}

function withStart(this stats: Stats, id: int32): Stats {
	return match (id as Region) {
		Region.Worker => ({ ...stats, forage: stats.forage + START_BONUS }),
		Region.Fighter => ({ ...stats, might: stats.might + START_BONUS }),
		Region.Survivor => ({ ...stats, grit: stats.grit + START_BONUS }),
	};
}

function withSmall(this stats: Stats, id: int32): Stats {
	const region = regionOf(id);
	const primaryStat: Stats = match (region) {
		Region.Worker => ({ ...stats, forage: stats.forage + NODE_BONUS }),
		Region.Fighter => ({ ...stats, might: stats.might + NODE_BONUS }),
		Region.Survivor => ({ ...stats, grit: stats.grit + NODE_BONUS }),
	};
	const secondaryStat: Stats = match (region) {
		Region.Survivor => ({ ...stats, might: stats.might + NODE_BONUS }),
		_ => ({ ...stats, grit: stats.grit + NODE_BONUS }),
	};
	const extraHeart: Stats = { ...stats, maxHearts: stats.maxHearts + 1 };
	return match (offsetOf(id)) {
		2 => extraHeart,
		4 => secondaryStat,
		_ => primaryStat,
	};
}

function withMod(this stats: Stats, granted: Mod): Stats {
	return { ...stats, mods: stats.mods.incl(granted) };
}

function withNotable(this stats: Stats, id: int32): Stats {
	return match (regionOf(id)) {
		Region.Worker => stats.withMod(Mod.Overtime),
		Region.Fighter => stats.withMod(Mod.Scavenger),
		Region.Survivor => stats.withMod(Mod.ThickHide),
	};
}

function withKeystone(this stats: Stats, id: int32): Stats {
	return match (id) {
		KEYSTONE_PACIFIST => stats.withMod(Mod.Pacifist),
		KEYSTONE_CANNIBAL => stats.withMod(Mod.Cannibal),
		_ => stats.withMod(Mod.GlassCannon),
	};
}

function applyNode(this stats: Stats, id: int32): Stats {
	return match (nodeKind(id)) {
		NodeKind.Start => stats.withStart(id),
		NodeKind.Small => stats.withSmall(id),
		NodeKind.Notable => stats.withNotable(id),
		NodeKind.Keystone => stats.withKeystone(id),
	};
}

export function fromTree(this typeof Stats, tree: Tree): Stats {
	let stats = Stats.base();
	for (let id = 0; id < TREE_NODES; id++) {
		if (tree.has(id)) { stats = stats.applyNode(id); }
	}
	return stats;
}

function refused(result: Result<Tree, AllocationError>, expected: AllocationError): boolean {
	if (result.ok) { return false; }
	return result.error == expected;
}

test "adjacency is symmetric over all pairs" {
	for (let first = 0; first < TREE_NODES; first++) {
		for (let second = 0; second < TREE_NODES; second++) {
			assert adjacent(first, second) == adjacent(second, first);
			assert !(first == second && adjacent(first, second));
		}
	}
}

test "every node is reachable from every start" {
	for (let start = 0; start < 3; start++) {
		let seen = Tree.empty().withNode(start);
		let grew = true;
		while (grew) {
			grew = false;
			for (let id = 0; id < TREE_NODES; id++) {
				if (!seen.has(id) && seen.touches(id)) { seen = seen.withNode(id); grew = true; }
			}
		}
		assert seen.nodeCount() == TREE_NODES;
	}
}

test "allocation rules" {
	const none = Tree.empty();
	const started = none.allocate(1, Region.Fighter);
	assert started.ok;
	if (started.ok) { assert started.value == none.withNode(1); }
	assert refused(none.allocate(0, Region.Fighter), AllocationError.WrongStart);
	assert refused(none.allocate(9, Region.Fighter), AllocationError.NotAdjacent);
	assert refused(none.allocate(TREE_NODES, Region.Fighter), AllocationError.OutOfRange);
	const fighterStart = none.withNode(1);
	assert fighterStart.allocate(9, Region.Fighter).ok;
	assert fighterStart.allocate(10, Region.Fighter).ok;
	assert refused(fighterStart.allocate(11, Region.Fighter), AllocationError.NotAdjacent);
	assert refused(fighterStart.allocate(1, Region.Fighter), AllocationError.Taken);
	assert refused(fighterStart.allocate(0, Region.Fighter), AllocationError.WrongStart);
	assert refused(fighterStart.allocate(0, Region.Worker), AllocationError.AlreadyStarted);
}

test "keystone is four points from its own start" {
	const threePoints = Tree.empty().withNode(1).withNode(9).withNode(11);
	const tooEarly = threePoints.allocate(KEYSTONE_GLASS_CANNON, Region.Fighter);
	assert refused(tooEarly, AllocationError.NotAdjacent);
	const fourPoints = threePoints.withNode(13);
	assert fourPoints.allocate(KEYSTONE_GLASS_CANNON, Region.Fighter).ok;
	assert fourPoints.allocate(KEYSTONE_CANNIBAL, Region.Fighter).ok;
	const otherBorder = fourPoints.allocate(KEYSTONE_PACIFIST, Region.Fighter);
	assert refused(otherBorder, AllocationError.NotAdjacent);
}

test "derived stats for a fighter path" {
	const tree = Tree.empty()
		.withNode(1)
		.withNode(9)
		.withNode(11)
		.withNode(13)
		.withNode(14)
		.withNode(KEYSTONE_GLASS_CANNON);
	const stats = Stats.fromTree(tree);
	assert stats.might == 90;
	assert stats.grit == 60;
	assert stats.forage == 50;
	assert stats.maxHearts == BASE_MAX_HEARTS + 1;
	assert stats.mods.has(Mod.Scavenger);
	assert stats.mods.has(Mod.GlassCannon);
	assert !stats.mods.has(Mod.ThickHide);
}

test "node kinds and regions" {
	assert nodeCost(KEYSTONE_PACIFIST) == KEYSTONE_COST;
	assert nodeCost(9) == 1;
	assert nodeKind(0) == NodeKind.Start;
	assert nodeKind(8) == NodeKind.Notable;
	assert nodeKind(9) == NodeKind.Small;
	assert nodeKind(23) == NodeKind.Keystone;
	assert regionOf(2) == Region.Survivor;
	assert regionOf(14) == Region.Fighter;
	assert regionOf(20) == Region.Survivor;
}
