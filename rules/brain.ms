import { Combatant, BPS } from "./layout";
import { levelCost, foodCost } from "./emission";
import { lootFor, maxStake, canAttack } from "./fight";
import { pwinBps } from "./pwinMc";

export const P_MIN_BPS: int32 = 5500;
export const EV_RUNS: int32 = 400;

export struct Persona {
	pMinBps: int32;
	reserveBps: int32;
	stakeBps: int32;
	minHearts: int32;
}

export function cautious(): Persona {
	const p: Persona = { pMinBps: 7000, reserveBps: 7000, stakeBps: 5000, minHearts: 3 };
	return p;
}

export function greedy(): Persona {
	const p: Persona = { pMinBps: 5000, reserveBps: 3000, stakeBps: 10000, minHearts: 2 };
	return p;
}

export function vengeful(): Persona {
	const p: Persona = { pMinBps: 4500, reserveBps: 5000, stakeBps: 10000, minHearts: 2 };
	return p;
}

export function shouldEat(hearts: int32, minHearts: int32, burrow: uint64, level: int32): int32 {
	if (hearts > minHearts + 1) { return 0; }
	let tier = 3;
	while (tier >= 1) {
		if (burrow >= foodCost(tier, level)) { return tier; }
		tier -= 1;
	}
	return 0;
}

export function shouldLevelUp(level: int32, burrow: uint64, reserveBps: int32): boolean {
	const cost = levelCost(level);
	return cost <= burrow * ((BPS - reserveBps) as uint64) / (BPS as uint64);
}

export function chooseStake(harvestD: uint64, burrowA: uint64, stakeBps: int32): uint64 {
	const cap = maxStake(harvestD);
	const budget = burrowA * (stakeBps as uint64) / (BPS as uint64);
	return cap < budget ? cap : budget;
}

export function attackEv(pwin: int32, stake: uint64, harvestD: uint64, d: Combatant, fightsInTodayD: int32): int64 {
	const loot = lootFor(stake, harvestD, d, fightsInTodayD) as int64;
	const gain = loot * 95 / 100;
	const loss = stake as int64;
	return (gain * (pwin as int64) - loss * ((BPS - pwin) as int64)) / (BPS as int64);
}

export function scoreTarget(a: Combatant, d: Combatant, harvestD: uint64, burrowA: uint64, fightsOutA: int32, fightsInTodayD: int32, shieldedD: boolean, p: Persona, seed: uint64): int64 {
	if (shieldedD || !canAttack(a, fightsOutA)) { return -1; }
	if (harvestD == 0) { return -1; }
	const stake = chooseStake(harvestD, burrowA, p.stakeBps);
	if (stake == 0) { return -1; }
	const pw = pwinBps(a, d, seed, EV_RUNS);
	if (pw < p.pMinBps) { return -1; }
	return attackEv(pw, stake, harvestD, d, fightsInTodayD);
}

test "eat picks the best affordable tier only when low" {
	assert shouldEat(5, 2, 1000000000, 0) == 0;
	assert shouldEat(3, 2, 1000000000, 0) == 3;
	assert shouldEat(3, 2, 9000000, 0) == 1;
	assert shouldEat(1, 2, 0, 0) == 0;
}

test "level up respects reserve" {
	assert shouldLevelUp(0, 200000000, 5000);
	assert !shouldLevelUp(0, 199000000, 5000);
}

test "attack ev sign follows odds" {
	const d: Combatant = { might: 5, grit: 0, hearts: 5, mods: 0 };
	assert attackEv(9000, 100, 1000000, d, 0) > 0;
	assert attackEv(3000, 100, 1000000, d, 0) < 0;
	assert attackEv(9000, 100, 0, d, 0) < 0;
}

test "empty harvest target is never worth attacking" {
	const a: Combatant = { might: 50, grit: 5, hearts: 5, mods: 0 };
	const d: Combatant = { might: 5, grit: 5, hearts: 5, mods: 0 };
	assert scoreTarget(a, d, 0, 1000000000, 0, 0, false, greedy(), 1) < 0;
	assert scoreTarget(a, d, 1000000000, 1000000000, 0, 0, true, greedy(), 1) < 0;
	assert scoreTarget(a, d, 1000000000, 1000000000, 0, 0, false, greedy(), 1) > 0;
}
