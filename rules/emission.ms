import { EPOCH_SECONDS, HBRN_UNIT, NEWBORN_EPOCHS, BPS, GROWTH_CAP_BPS } from "./layout";

export const ACC_SCALE: uint64 = 100000;
export const E0: uint64 = 100000 * HBRN_UNIT;
export const E_FLOOR: uint64 = E0 / 20;
export const DECAY_EPOCHS: uint64 = 90;

export const LEVEL_COST_BASE: uint64 = 100 * HBRN_UNIT;
export const LEVEL_CAP: int32 = 60;
export const RESERVE_RATIO_BPS: int32 = 5000;

export function epochOf(now: uint64, genesis: uint64): uint64 {
	if (now < genesis) { return 0; }
	return (now - genesis) / EPOCH_SECONDS;
}

export function emissionFor(epoch: uint64): uint64 {
	let e = E0;
	let k = epoch / DECAY_EPOCHS;
	while (k > 0 && e > E_FLOOR) { e = e * 3 / 4; k -= 1; }
	return e < E_FLOOR ? E_FLOOR : e;
}

export function accAdvance(acc: uint64, totalWp: uint64, amount: uint64): uint64 {
	if (totalWp == 0) { return acc; }
	return acc + amount * ACC_SCALE / totalWp;
}

export function settleGlobal(acc: uint64, accEpoch: uint64, current: uint64, totalWp: uint64, recycled: uint64): uint64 {
	let a = acc;
	let e = accEpoch;
	let extra = recycled;
	while (e < current) {
		e += 1;
		a = accAdvance(a, totalWp, emissionFor(e) + extra);
		extra = 0;
	}
	return a;
}

export function pendingReward(wp: uint64, acc: uint64, accSnapshot: uint64): uint64 {
	if (acc <= accSnapshot) { return 0; }
	return wp * (acc - accSnapshot) / ACC_SCALE;
}

export function growthBonus(pending: uint64, multBps: int32): uint64 {
	const m = multBps > GROWTH_CAP_BPS ? GROWTH_CAP_BPS : (multBps < BPS ? BPS : multBps);
	return pending * ((m - BPS) as uint64) / (BPS as uint64);
}

export function levelCost(level: int32): uint64 {
	let c = LEVEL_COST_BASE;
	let l = 0;
	const cap = level > LEVEL_CAP ? LEVEL_CAP : level;
	while (l < cap) { c = c * 112 / 100; l += 1; }
	return c;
}

export function foodCost(tier: int32, level: int32): uint64 {
	const base: uint64 = match (tier) {
		1 => 8,
		2 => 15,
		_ => 21,
	};
	return base * HBRN_UNIT * ((20 + level) as uint64) / 20;
}

export function foodHearts(tier: int32): int32 {
	return tier < 1 ? 1 : (tier > 3 ? 3 : tier);
}

export function hungerStepsBetween(lastTick: uint64, current: uint64, bornEpoch: uint64): int32 {
	let steps = 0;
	let e = lastTick;
	while (e < current) {
		e += 1;
		const newborn = e < bornEpoch + NEWBORN_EPOCHS;
		if (!newborn || (e - bornEpoch) % 2 == 1) { steps += 1; }
	}
	return steps;
}

export function isShielded(epoch: uint64, bornEpoch: uint64): boolean {
	return epoch < bornEpoch + NEWBORN_EPOCHS;
}

export struct Split {
	recycled: uint64;
	burned: uint64;
	protocol: uint64;
}

export function spendSplit(amount: uint64, out s: Split): void {
	const protocol = amount / 10;
	const burned = amount * 3 / 10;
	s = { recycled: amount - protocol - burned, burned: burned, protocol: protocol };
}

export function stakeSplit(amount: uint64, out winner: uint64, out protocol: uint64): void {
	protocol = amount / 20;
	winner = amount - protocol;
}

export function deathSplit(wallet: uint64, livingMates: int32, out perMate: uint64, out burned: uint64): void {
	const pot = wallet / 2;
	if (livingMates <= 0) { perMate = 0; burned = wallet; return; }
	perMate = pot / (livingMates as uint64);
	burned = wallet - perMate * (livingMates as uint64);
}

test "emission decays by quarter every 90 epochs and floors" {
	assert emissionFor(0) == E0;
	assert emissionFor(89) == E0;
	assert emissionFor(90) == E0 * 3 / 4;
	assert emissionFor(180) == E0 * 9 / 16;
	assert emissionFor(100000) == E_FLOOR;
}

test "accumulator pays each pet its share exactly once" {
	const wpA: uint64 = 25;
	const wpB: uint64 = 75;
	const acc1 = settleGlobal(0, 0, 1, wpA + wpB, 0);
	const payA = pendingReward(wpA, acc1, 0);
	const payB = pendingReward(wpB, acc1, 0);
	assert payA + payB <= E0;
	assert E0 - (payA + payB) < 100;
	assert payB == payA * 3;
	assert pendingReward(wpA, acc1, acc1) == 0;
}

test "recycled pot lands in the next settled epoch only" {
	const plain = settleGlobal(0, 0, 3, 100, 0);
	const boosted = settleGlobal(0, 0, 3, 100, 1000 * HBRN_UNIT);
	assert boosted - plain == 1000 * HBRN_UNIT * ACC_SCALE / 100;
}

test "growth bonus is capped at 20 percent" {
	assert growthBonus(1000, 11000) == 100;
	assert growthBonus(1000, 15000) == 200;
	assert growthBonus(1000, 9000) == 0;
}

test "level and food cost curves" {
	assert levelCost(0) == 100 * HBRN_UNIT;
	assert levelCost(1) == 112 * HBRN_UNIT;
	assert levelCost(10) > levelCost(9);
	assert levelCost(LEVEL_CAP + 5) == levelCost(LEVEL_CAP);
	assert foodCost(1, 0) == 8 * HBRN_UNIT;
	assert foodCost(3, 20) == 42 * HBRN_UNIT;
}

test "newborn hunger is halved" {
	assert hungerStepsBetween(0, 6, 0) == 5;
	assert hungerStepsBetween(0, 3, 0) == 2;
	assert hungerStepsBetween(10, 16, 0) == 6;
}

test "splits conserve value" {
	let s: Split = { recycled: 0, burned: 0, protocol: 0 };
	spendSplit(1001, out s);
	assert s.recycled + s.burned + s.protocol == 1001;
	assert s.protocol == 100;
	assert s.burned == 300;
	let w: uint64 = 0;
	let p: uint64 = 0;
	stakeSplit(999, out w, out p);
	assert w + p == 999;
	let per: uint64 = 0;
	let burn: uint64 = 0;
	deathSplit(1000, 3, out per, out burn);
	assert per == 166;
	assert per * 3 + burn == 1000;
	deathSplit(1000, 0, out per, out burn);
	assert per == 0 && burn == 1000;
}
