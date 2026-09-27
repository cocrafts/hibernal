import * as arithmetic from "./arithmetic";
import { BPS } from "./units";
import { START_BONUS, BASE_MAX_HEARTS, BASE_STAT, Stats, Region, Mod, grown, talented } from "./stats";
import { Talent } from "./talent";

export const TREE_NODES: int32 = 64;
export const KEYSTONE_COST: int32 = 3;
export const GATE: int32 = 3;
export const FIRST_DIRECTION_NODE: int32 = 4;
export const DIRECTION_NODES: int32 = 18;
export const CLUSTERS: int32 = 4;
export const CLUSTER_NODES: int32 = 4;
export const KEYSTONE_GLASS_CANNON: int32 = 58;
export const KEYSTONE_TYCOON: int32 = 59;
export const KEYSTONE_CANNIBAL: int32 = 60;
export const KEYSTONE_BERSERKER: int32 = 61;
export const KEYSTONE_PACIFIST: int32 = 62;
export const KEYSTONE_BULWARK: int32 = 63;
export const SMALL_NODE_BPS: int32 = 1000;
export const NOTABLE_NODE_BPS: int32 = 2500;
export const ATTACK_SMALL_MIGHT_BPS: int32 = 500;
export const TYCOON_FORAGE_BPS: int32 = 13000;
export const TYCOON_HEARTS_BPS: int32 = 7000;
export const BULWARK_HEARTS_BPS: int32 = 20000;
export const BULWARK_MIGHT_BPS: int32 = 7000;
export const BULWARK_FOOD_BPS: int32 = 10000;

export enum NodeKind {
	Start,
	Small,
	Notable,
	Keystone,
}

export enum NodeRole {
	Start,
	Gate,
	Entry,
	Fork,
	Cluster,
	Keystone,
}

export enum Family {
	Forage,
	Food,
	Experience,
	Might,
	Loot,
	Attacks,
	Grit,
	Hearts,
	BiteGuard,
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

export enum HomeError {
	Shared,
	Border,
}

export struct Tree {
	bits: uint64;
}

export function empty(this typeof Tree): Tree {
	return { bits: 0 };
}

export function roleOf(id: int32): NodeRole {
	if (id < GATE) { return NodeRole.Start; }
	if (id == GATE) { return NodeRole.Gate; }
	if (id >= KEYSTONE_GLASS_CANNON) { return NodeRole.Keystone; }
	return match ((id - FIRST_DIRECTION_NODE) % DIRECTION_NODES) {
		0 => NodeRole.Entry,
		1 => NodeRole.Fork,
		_ => NodeRole.Cluster,
	};
}

function directionBase(region: Region): int32 {
	return FIRST_DIRECTION_NODE + (region as int32) * DIRECTION_NODES;
}

export function clusterOf(id: int32): int32 {
	return ((id - FIRST_DIRECTION_NODE) % DIRECTION_NODES - 2) / CLUSTER_NODES;
}

function stepOf(id: int32): int32 {
	return ((id - FIRST_DIRECTION_NODE) % DIRECTION_NODES - 2) % CLUSTER_NODES;
}

export function clusterNode(region: Region, cluster: int32, step: int32): int32 {
	return directionBase(region) + 2 + cluster * CLUSTER_NODES + step;
}

export function notableOf(region: Region, cluster: int32): int32 {
	return clusterNode(region, cluster, CLUSTER_NODES - 1);
}

export function nodeKind(id: int32): NodeKind {
	return match (roleOf(id)) {
		NodeRole.Start => NodeKind.Start,
		NodeRole.Keystone => NodeKind.Keystone,
		NodeRole.Cluster => stepOf(id) == CLUSTER_NODES - 1 ? NodeKind.Notable : NodeKind.Small,
		_ => NodeKind.Small,
	};
}

export function nodeCost(id: int32): int32 {
	return nodeKind(id) == NodeKind.Keystone ? KEYSTONE_COST : 1;
}

function nextRegion(region: Region): Region {
	return (((region as int32) + 1) % 3) as Region;
}

function previousRegion(region: Region): Region {
	return (((region as int32) + 2) % 3) as Region;
}

function borderKeystone(region: Region, second: int32): int32 {
	return KEYSTONE_GLASS_CANNON + (region as int32) * 2 + second;
}

export function keystoneBorder(id: int32): [Region, Region] {
	const first = ((id - KEYSTONE_GLASS_CANNON) / 2) as Region;
	return [first, nextRegion(first)];
}

export function keystoneTouches(id: int32, region: Region): boolean {
	const [first, second] = keystoneBorder(id);
	return first == region || second == region;
}

export function regionOf(id: int32): Result<Region, HomeError> {
	return match (roleOf(id)) {
		NodeRole.Start => Result.ok(id as Region),
		NodeRole.Gate => Result.err(HomeError.Shared),
		NodeRole.Keystone => Result.err(HomeError.Border),
		_ => Result.ok(((id - FIRST_DIRECTION_NODE) / DIRECTION_NODES) as Region),
	};
}

function directionOf(id: int32): Region {
	return ((id - FIRST_DIRECTION_NODE) / DIRECTION_NODES) as Region;
}

function nodeBit(id: int32): uint64 {
	return (1 as uint64) << (id as uint64);
}

export function keystoneMask(): uint64 {
	return (~(0 as uint64)) << (KEYSTONE_GLASS_CANNON as uint64);
}

function lowestNode(bits: uint64): int32 {
	let id = 0;
	let rest = bits;
	for (let width = 32; width > 0; width = width >> 1) {
		const low = ((1 as uint64) << (width as uint64)) - 1;
		if ((rest & low) == 0) {
			rest = rest >> (width as uint64);
			id += width;
		}
	}
	return id;
}

function pairBits(region: Region): uint64 {
	return nodeBit(borderKeystone(region, 0)) | nodeBit(borderKeystone(region, 1));
}

function clusterNeighbors(id: int32): uint64 {
	const region = directionOf(id);
	const cluster = clusterOf(id);
	const step = stepOf(id);
	const inward = step == 0 ? directionBase(region) + 1 : id - 1;
	if (step < CLUSTER_NODES - 1) { return nodeBit(inward) | nodeBit(id + 1); }
	const border = match (cluster) {
		2 => pairBits(previousRegion(region)),
		3 => pairBits(region),
		_ => 0 as uint64,
	};
	return nodeBit(inward) | border;
}

export function neighbors(id: int32): uint64 {
	return match (roleOf(id)) {
		NodeRole.Start => nodeBit(directionBase(id as Region)),
		NodeRole.Gate => nodeBit(directionBase(Region.Worker)) |
			nodeBit(directionBase(Region.Fighter)) |
			nodeBit(directionBase(Region.Survivor)),
		NodeRole.Entry => nodeBit((directionOf(id) as int32)) | nodeBit(GATE) | nodeBit(id + 1),
		NodeRole.Fork => nodeBit(id - 1) |
			nodeBit(clusterNode(directionOf(id), 0, 0)) |
			nodeBit(clusterNode(directionOf(id), 1, 0)) |
			nodeBit(clusterNode(directionOf(id), 2, 0)) |
			nodeBit(clusterNode(directionOf(id), 3, 0)),
		NodeRole.Cluster => clusterNeighbors(id),
		NodeRole.Keystone => keystoneNeighbors(id),
	};
}

function keystoneNeighbors(id: int32): uint64 {
	const [first, second] = keystoneBorder(id);
	return nodeBit(notableOf(first, 3)) | nodeBit(notableOf(second, 2));
}

export function adjacent(first: int32, second: int32): boolean {
	return (neighbors(first) & nodeBit(second)) != 0;
}

export function has(this tree: Tree, id: int32): boolean {
	return ((tree.bits >> (id as uint64)) & 1) == 1;
}

export function withNode(this tree: Tree, id: int32): Tree {
	return { bits: tree.bits | nodeBit(id) };
}

export function isEmpty(this tree: Tree): boolean {
	return tree.bits == 0;
}

export function touches(this tree: Tree, id: int32): boolean {
	return (neighbors(id) & tree.bits & ~keystoneMask()) != 0;
}

export function allocate(
	this tree: Tree,
	id: int32,
	start: Region,
): Result<Tree, AllocationError> {
	if (id < 0 || id >= TREE_NODES) { return Result.err(AllocationError.OutOfRange); }
	if (tree.has(id)) { return Result.err(AllocationError.Taken); }
	if (id < GATE) {
		if (id != (start as int32)) { return Result.err(AllocationError.WrongStart); }
		if (!tree.isEmpty()) { return Result.err(AllocationError.AlreadyStarted); }
		return Result.ok(tree.withNode(id));
	}
	if (tree.isEmpty() || !tree.touches(id)) { return Result.err(AllocationError.NotAdjacent); }
	return Result.ok(tree.withNode(id));
}

export function allocatable(this tree: Tree, start: Region): uint64 {
	if (tree.isEmpty()) { return nodeBit(start as int32); }
	let touched: uint64 = 0;
	let remaining = tree.bits & ~keystoneMask();
	while (remaining != 0) {
		touched = touched | neighbors(lowestNode(remaining));
		remaining = remaining & (remaining - 1);
	}
	return touched & ~tree.bits & ~(nodeBit(GATE) - 1);
}

export function opensWith(this tree: Tree, id: int32): int32 {
	let opened = 0;
	let candidates = neighbors(id) & ~tree.bits;
	while (candidates != 0) {
		const other = lowestNode(candidates);
		candidates = candidates & (candidates - 1);
		if (!tree.touches(other)) { opened += 1; }
	}
	return opened;
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

function workerFamily(cluster: int32): Family {
	return match (cluster) {
		2 => Family.Food,
		3 => Family.Experience,
		_ => Family.Forage,
	};
}

function fighterFamily(cluster: int32): Family {
	return match (cluster) {
		2 => Family.Loot,
		3 => Family.Attacks,
		_ => Family.Might,
	};
}

function survivorFamily(cluster: int32): Family {
	return match (cluster) {
		0 => Family.Grit,
		3 => Family.BiteGuard,
		_ => Family.Hearts,
	};
}

export function familyOf(region: Region, cluster: int32): Family {
	return match (region) {
		Region.Worker => workerFamily(cluster),
		Region.Fighter => fighterFamily(cluster),
		Region.Survivor => survivorFamily(cluster),
	};
}

export function nodeFamily(id: int32): Family {
	return match (roleOf(id)) {
		NodeRole.Gate => Family.Hearts,
		NodeRole.Cluster => familyOf(directionOf(id), clusterOf(id)),
		_ => familyOf(directionOf(id), 0),
	};
}

export function nodeBonusBps(id: int32): int32 {
	const kind = nodeKind(id);
	if (kind == NodeKind.Notable) { return NOTABLE_NODE_BPS; }
	if (nodeFamily(id) == Family.Attacks) { return ATTACK_SMALL_MIGHT_BPS; }
	return SMALL_NODE_BPS;
}

function fighterNotableMod(cluster: int32): Result<Mod, HomeError> {
	return match (cluster) {
		1 => Result.ok(Mod.Scavenger),
		3 => Result.ok(Mod.Relentless),
		_ => Result.err(HomeError.Shared),
	};
}

function notableMod(id: int32): Result<Mod, HomeError> {
	const cluster = clusterOf(id);
	return match (directionOf(id)) {
		Region.Worker => cluster == 1 ? Result.ok(Mod.Overtime) : Result.err(HomeError.Shared),
		Region.Fighter => fighterNotableMod(cluster),
		Region.Survivor => cluster == 3 ? Result.ok(Mod.ThickHide) : Result.err(HomeError.Shared),
	};
}

function keystoneMod(id: int32): Result<Mod, HomeError> {
	return match (id) {
		KEYSTONE_GLASS_CANNON => Result.ok(Mod.GlassCannon),
		KEYSTONE_CANNIBAL => Result.ok(Mod.Cannibal),
		KEYSTONE_BERSERKER => Result.ok(Mod.Berserker),
		KEYSTONE_PACIFIST => Result.ok(Mod.Pacifist),
		_ => Result.err(HomeError.Border),
	};
}

function percentOf(value: int32, bps: int32): int32 {
	return ((value as int64) * ((BPS + bps) as int64) / (BPS as int64)) as int32;
}

function scaledBy(value: int32, bps: int32): int32 {
	return ((value as int64) * (bps as int64) / (BPS as int64)) as int32;
}

export function built(this typeof Stats, tree: Tree, level: int32, talent: Talent): Stats {
	let flat = Stats.base();
	for (let region = 0; region < 3; region++) {
		if (!tree.has(region)) { continue; }
		flat = match (region as Region) {
			Region.Worker => ({ ...flat, forage: flat.forage + START_BONUS }),
			Region.Fighter => ({ ...flat, might: flat.might + START_BONUS }),
			Region.Survivor => ({ ...flat, grit: flat.grit + START_BONUS }),
		};
	}
	flat = flat.grown(level);
	let forageBps = 0;
	let mightBps = 0;
	let gritBps = 0;
	let heartsBps = 0;
	let foodBps = 0;
	let experienceBps = 0;
	let lootBps = 0;
	let biteGuardBps = 0;
	let mods = flat.mods;
	let remaining = tree.bits & ~keystoneMask() & ~((nodeBit(GATE) - 1));
	while (remaining != 0) {
		const id = lowestNode(remaining);
		remaining = remaining & (remaining - 1);
		const bonus = nodeBonusBps(id);
		match (nodeFamily(id)) {
			Family.Forage => { forageBps += bonus; },
			Family.Food => { foodBps += bonus; },
			Family.Experience => { experienceBps += bonus; },
			Family.Might => { mightBps += bonus; },
			Family.Loot => { lootBps += bonus; },
			Family.Attacks => { mightBps += bonus; },
			Family.Grit => { gritBps += bonus; },
			Family.Hearts => { heartsBps += bonus; },
			Family.BiteGuard => { biteGuardBps += bonus; },
		}
		if (nodeKind(id) != NodeKind.Notable) { continue; }
		const granted = notableMod(id);
		if (granted.ok) { mods = mods.incl(granted.value); }
	}
	let stats: Stats = {
		...flat,
		forage: percentOf(flat.forage, forageBps),
		might: percentOf(flat.might, mightBps),
		grit: percentOf(flat.grit, gritBps),
		maxHearts: percentOf(flat.maxHearts, heartsBps),
		foodBps: foodBps,
		experienceBps: experienceBps,
		lootBps: lootBps,
		biteGuardBps: biteGuardBps,
		mods: mods,
	};
	for (let id = KEYSTONE_GLASS_CANNON; id < TREE_NODES; id++) {
		if (!tree.has(id)) { continue; }
		const granted = keystoneMod(id);
		if (granted.ok) { stats = { ...stats, mods: stats.mods.incl(granted.value) }; }
		if (id == KEYSTONE_TYCOON) {
			stats = {
				...stats,
				forage: scaledBy(stats.forage, TYCOON_FORAGE_BPS),
				maxHearts: scaledBy(stats.maxHearts, TYCOON_HEARTS_BPS),
			};
		}
		if (id == KEYSTONE_BULWARK) {
			stats = {
				...stats,
				maxHearts: scaledBy(stats.maxHearts, BULWARK_HEARTS_BPS),
				might: scaledBy(stats.might, BULWARK_MIGHT_BPS),
				foodBps: stats.foodBps + BULWARK_FOOD_BPS,
			};
		}
	}
	return stats.talented(talent);
}

export function fromTree(this typeof Stats, tree: Tree): Stats {
	return Stats.built(tree, 1, Talent.unrevealed());
}

function refused(result: Result<Tree, AllocationError>, expected: AllocationError): boolean {
	if (result.ok) { return false; }
	return result.error == expected;
}

function path(ids: int32[]): Tree {
	let tree = Tree.empty();
	for (const id of ids) { tree = tree.withNode(id); }
	return tree;
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

test "the allocatable set is every node allocate accepts" {
	for (let start = 0; start < 3; start++) {
		let tree = Tree.empty();
		let grew = true;
		while (grew) {
			for (let id = 0; id < TREE_NODES; id++) {
				const accepted = tree.allocate(id, start as Region).ok;
				assert ((tree.allocatable(start as Region) & nodeBit(id)) != 0) == accepted;
			}
			grew = false;
			for (let id = TREE_NODES - 1; id >= 0; id--) {
				if (!grew && tree.allocate(id, start as Region).ok) { tree = tree.withNode(id); grew = true; }
			}
		}
		assert tree.allocatable(start as Region) == 0;
	}
}

test "a node opens exactly the neighbours no allocated node touches yet" {
	let tree = Tree.empty().withNode(1);
	let grew = true;
	while (grew) {
		for (let id = 0; id < TREE_NODES; id++) {
			let opened = 0;
			for (let other = 0; other < TREE_NODES; other++) {
				if (adjacent(id, other) && !tree.has(other) && !tree.touches(other)) { opened += 1; }
			}
			assert tree.opensWith(id) == opened;
		}
		grew = false;
		for (let id = 0; id < TREE_NODES; id++) {
			if (!grew && !tree.has(id) && tree.touches(id)) { tree = tree.withNode(id); grew = true; }
		}
	}
	assert tree.nodeCount() == TREE_NODES;
}

test "a direction is an entry, a fork and four clusters of three small nodes and a notable" {
	for (let region = 0; region < 3; region++) {
		let notables = 0;
		for (let offset = 0; offset < DIRECTION_NODES; offset++) {
			const id = FIRST_DIRECTION_NODE + region * DIRECTION_NODES + offset;
			if (nodeKind(id) == NodeKind.Notable) { notables += 1; }
			const home = regionOf(id);
			assert home.ok;
			if (home.ok) { assert home.value == (region as Region); }
		}
		assert notables == CLUSTERS;
	}
	assert !regionOf(GATE).ok;
	assert nodeKind(KEYSTONE_BULWARK) == NodeKind.Keystone;
	assert nodeCost(KEYSTONE_PACIFIST) == KEYSTONE_COST;
	assert nodeCost(GATE) == 1;
}

test "allocation starts at the own start and grows along edges" {
	const none = Tree.empty();
	const started = none.allocate(1, Region.Fighter);
	assert started.ok;
	if (started.ok) { assert started.value == none.withNode(1); }
	assert refused(none.allocate(0, Region.Fighter), AllocationError.WrongStart);
	assert refused(none.allocate(GATE, Region.Fighter), AllocationError.NotAdjacent);
	assert refused(none.allocate(TREE_NODES, Region.Fighter), AllocationError.OutOfRange);
	const fighter = none.withNode(1);
	const entry = directionBase(Region.Fighter);
	assert fighter.allocate(entry, Region.Fighter).ok;
	assert refused(fighter.allocate(entry + 1, Region.Fighter), AllocationError.NotAdjacent);
	assert refused(fighter.allocate(0, Region.Worker), AllocationError.AlreadyStarted);
	const entered = fighter.withNode(entry);
	assert entered.allocate(GATE, Region.Fighter).ok;
	assert entered.allocate(entry + 1, Region.Fighter).ok;
}

test "a keystone is a dead end nine points out and never opens the other direction" {
	const fighter = directionBase(Region.Fighter);
	const beforeNotable = path([
		1,
		fighter,
		fighter + 1,
		clusterNode(Region.Fighter, 2, 0),
		clusterNode(Region.Fighter, 2, 1),
		clusterNode(Region.Fighter, 2, 2),
	]);
	const early = beforeNotable.allocate(KEYSTONE_GLASS_CANNON, Region.Fighter);
	assert refused(early, AllocationError.NotAdjacent);
	const atNotable = beforeNotable.withNode(notableOf(Region.Fighter, 2));
	assert atNotable.allocate(KEYSTONE_GLASS_CANNON, Region.Fighter).ok;
	assert atNotable.allocate(KEYSTONE_TYCOON, Region.Fighter).ok;
	assert refused(atNotable.allocate(KEYSTONE_CANNIBAL, Region.Fighter), AllocationError.NotAdjacent);
	const withKeystone = atNotable.withNode(KEYSTONE_GLASS_CANNON);
	const worker = notableOf(Region.Worker, 3);
	assert refused(withKeystone.allocate(worker, Region.Fighter), AllocationError.NotAdjacent);
	assert keystoneTouches(KEYSTONE_GLASS_CANNON, Region.Worker);
	assert keystoneTouches(KEYSTONE_GLASS_CANNON, Region.Fighter);
	assert !keystoneTouches(KEYSTONE_GLASS_CANNON, Region.Survivor);
}

test "small nodes add ten percent, notables a quarter and a rule, keystones multiply" {
	const fighter = directionBase(Region.Fighter);
	const bare = Stats.fromTree(path([1]));
	assert bare.might == BASE_STAT + START_BONUS;
	const mighty = Stats.fromTree(path([
		1,
		fighter,
		fighter + 1,
		clusterNode(Region.Fighter, 1, 0),
		clusterNode(Region.Fighter, 1, 1),
		clusterNode(Region.Fighter, 1, 2),
		notableOf(Region.Fighter, 1),
	]));
	const mightBps = BPS + 5 * SMALL_NODE_BPS + NOTABLE_NODE_BPS;
	assert mighty.might == (BASE_STAT + START_BONUS) * mightBps / BPS;
	assert mighty.mods.has(Mod.Scavenger);
	const survivor = directionBase(Region.Survivor);
	const hearty = Stats.fromTree(path([
		2,
		survivor,
		survivor + 1,
		clusterNode(Region.Survivor, 1, 0),
		KEYSTONE_BULWARK,
	]));
	assert hearty.maxHearts == BASE_MAX_HEARTS * (BPS + SMALL_NODE_BPS) / BPS * 2;
	assert hearty.might == BASE_STAT * BULWARK_MIGHT_BPS / BPS;
	assert hearty.grit == (BASE_STAT + START_BONUS) * (BPS + 2 * SMALL_NODE_BPS) / BPS;
	assert hearty.foodBps == BULWARK_FOOD_BPS;
}
