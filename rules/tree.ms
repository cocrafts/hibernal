import { TREE_NODES, START_BONUS, BASE_STAT, BASE_MAX_HEARTS, Stats, Region } from "./layout";
import { MOD_OVERTIME, MOD_SCAVENGER, MOD_THICK_HIDE, MOD_PACIFIST, MOD_GLASS_CANNON, MOD_CANNIBAL } from "./layout";

export const KEYSTONE_PACIFIST: int32 = 21;
export const KEYSTONE_GLASS_CANNON: int32 = 22;
export const KEYSTONE_CANNIBAL: int32 = 23;

export enum NodeKind { Start = 0, Small = 1, Notable = 2, Keystone = 3 }

export function nodeKind(id: int32): int32 {
	if (id < 3) { return NodeKind.Start as int32; }
	if (id >= 21) { return NodeKind.Keystone as int32; }
	return (id - 3) % 6 == 5 ? (NodeKind.Notable as int32) : (NodeKind.Small as int32);
}

export function regionOf(id: int32): int32 {
	if (id < 3) { return id; }
	if (id >= 21) { return -1; }
	return (id - 3) / 6;
}

function offsetOf(id: int32): int32 {
	return (id - 3) % 6;
}

function regionNode(region: int32, offset: int32): int32 {
	return 3 + region * 6 + offset;
}

function bit(id: int32): uint32 {
	return (1 as uint32) << (id as uint32);
}

export function neighbors(id: int32): uint32 {
	if (id < 3) {
		return bit(regionNode(id, 0)) | bit(regionNode(id, 1));
	}
	if (id == KEYSTONE_PACIFIST) { return bit(regionNode(Region.Worker as int32, 4)) | bit(regionNode(Region.Survivor as int32, 4)); }
	if (id == KEYSTONE_GLASS_CANNON) { return bit(regionNode(Region.Fighter as int32, 4)) | bit(regionNode(Region.Worker as int32, 4)); }
	if (id == KEYSTONE_CANNIBAL) { return bit(regionNode(Region.Fighter as int32, 4)) | bit(regionNode(Region.Survivor as int32, 4)); }
	const r = regionOf(id);
	return match (offsetOf(id)) {
		0 => bit(r) | bit(regionNode(r, 2)),
		1 => bit(r) | bit(regionNode(r, 3)),
		2 => bit(regionNode(r, 0)) | bit(regionNode(r, 4)),
		3 => bit(regionNode(r, 1)) | bit(regionNode(r, 4)),
		4 => bit(regionNode(r, 2)) | bit(regionNode(r, 3)) | bit(regionNode(r, 5)) | keystonesTouching(r),
		_ => bit(regionNode(r, 4)),
	};
}

function keystonesTouching(region: int32): uint32 {
	return match (region) {
		0 => bit(KEYSTONE_PACIFIST) | bit(KEYSTONE_GLASS_CANNON),
		1 => bit(KEYSTONE_GLASS_CANNON) | bit(KEYSTONE_CANNIBAL),
		_ => bit(KEYSTONE_PACIFIST) | bit(KEYSTONE_CANNIBAL),
	};
}

export function adjacent(a: int32, b: int32): boolean {
	return (neighbors(a) & bit(b)) != 0;
}

export function isSet(bitmap: uint64, id: int32): boolean {
	return ((bitmap >> (id as uint64)) & 1) == 1;
}

export function withNode(bitmap: uint64, id: int32): uint64 {
	return bitmap | ((1 as uint64) << (id as uint64));
}

export function canAllocate(bitmap: uint64, id: int32, startRegion: int32): boolean {
	if (id < 0 || id >= TREE_NODES) { return false; }
	if (isSet(bitmap, id)) { return false; }
	if (id < 3) { return id == startRegion && bitmap == 0; }
	if (bitmap == 0) { return false; }
	return (neighbors(id) & (bitmap as uint32)) != 0;
}

function applyNode(id: int32, s: Stats, out next: Stats): void {
	let y = s.yield_;
	let m = s.might;
	let g = s.grit;
	let h = s.maxHearts;
	let mods = s.mods;
	const kind = nodeKind(id);
	if (kind == (NodeKind.Start as int32)) {
		if (id == (Region.Worker as int32)) { y += START_BONUS; }
		if (id == (Region.Fighter as int32)) { m += START_BONUS; }
		if (id == (Region.Survivor as int32)) { g += START_BONUS; }
	} else if (kind == (NodeKind.Small as int32)) {
		const r = regionOf(id);
		const o = offsetOf(id);
		if (o == 2) {
			h += 1;
		} else if (o == 4) {
			if (r == (Region.Survivor as int32)) { m += 1; } else { g += 1; }
		} else {
			if (r == (Region.Worker as int32)) { y += 1; }
			if (r == (Region.Fighter as int32)) { m += 1; }
			if (r == (Region.Survivor as int32)) { g += 1; }
		}
	} else if (kind == (NodeKind.Notable as int32)) {
		const r = regionOf(id);
		if (r == (Region.Worker as int32)) { mods = mods | MOD_OVERTIME; }
		if (r == (Region.Fighter as int32)) { mods = mods | MOD_SCAVENGER; }
		if (r == (Region.Survivor as int32)) { mods = mods | MOD_THICK_HIDE; }
	} else {
		if (id == KEYSTONE_PACIFIST) { mods = mods | MOD_PACIFIST; }
		if (id == KEYSTONE_GLASS_CANNON) { mods = mods | MOD_GLASS_CANNON; h = 2; }
		if (id == KEYSTONE_CANNIBAL) { mods = mods | MOD_CANNIBAL; }
	}
	const built: Stats = { yield_: y, might: m, grit: g, maxHearts: h, mods: mods };
	next = built;
}

export function derivedStats(bitmap: uint64, out stats: Stats): void {
	let s: Stats = { yield_: BASE_STAT, might: BASE_STAT, grit: BASE_STAT, maxHearts: BASE_MAX_HEARTS, mods: 0 };
	let id = 0;
	while (id < TREE_NODES) {
		if (isSet(bitmap, id)) {
			let next: Stats = s;
			applyNode(id, s, out next);
			s = next;
		}
		id += 1;
	}
	stats = s;
}

export function popcount(bitmap: uint64): int32 {
	let n = 0;
	let b = bitmap;
	while (b != 0) { b = b & (b - 1); n += 1; }
	return n;
}

test "adjacency is symmetric over all pairs" {
	let a = 0;
	while (a < TREE_NODES) {
		let b = 0;
		while (b < TREE_NODES) {
			assert adjacent(a, b) == adjacent(b, a);
			assert !(a == b && adjacent(a, b));
			b += 1;
		}
		a += 1;
	}
}

test "every node is reachable from every start" {
	let start = 0;
	while (start < 3) {
		let seen: uint64 = withNode(0, start);
		let grew = true;
		while (grew) {
			grew = false;
			let id = 0;
			while (id < TREE_NODES) {
				if (!isSet(seen, id) && (neighbors(id) & (seen as uint32)) != 0) { seen = withNode(seen, id); grew = true; }
				id += 1;
			}
		}
		assert popcount(seen) == TREE_NODES;
		start += 1;
	}
}

test "allocation rules" {
	assert canAllocate(0, 1, 1);
	assert !canAllocate(0, 0, 1);
	assert !canAllocate(0, 9, 1);
	const b1 = withNode(0, 1);
	assert canAllocate(b1, 9, 1);
	assert canAllocate(b1, 10, 1);
	assert !canAllocate(b1, 11, 1);
	assert !canAllocate(b1, 1, 1);
	assert !canAllocate(b1, 0, 1);
}

test "keystone is four points from its own start" {
	let b: uint64 = withNode(0, 1);
	b = withNode(b, 9);
	b = withNode(b, 11);
	assert !canAllocate(b, KEYSTONE_GLASS_CANNON, 1);
	b = withNode(b, 13);
	assert canAllocate(b, KEYSTONE_GLASS_CANNON, 1);
	assert canAllocate(b, KEYSTONE_CANNIBAL, 1);
	assert !canAllocate(b, KEYSTONE_PACIFIST, 1);
}

test "derived stats for a fighter path" {
	let b: uint64 = withNode(0, 1);
	b = withNode(b, 9);
	b = withNode(b, 11);
	b = withNode(b, 13);
	b = withNode(b, 14);
	b = withNode(b, KEYSTONE_GLASS_CANNON);
	let s: Stats = { yield_: 0, might: 0, grit: 0, maxHearts: 0, mods: 0 };
	derivedStats(b, out s);
	assert s.might == BASE_STAT + START_BONUS + 1;
	assert s.grit == BASE_STAT + 1;
	assert s.yield_ == BASE_STAT;
	assert s.maxHearts == 2;
	assert (s.mods & MOD_SCAVENGER) != 0;
	assert (s.mods & MOD_GLASS_CANNON) != 0;
	assert (s.mods & MOD_THICK_HIDE) == 0;
}
