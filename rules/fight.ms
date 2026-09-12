import { Combatant, FightResult, Outcome, BPS } from "./layout";
import { MOD_SCAVENGER, MOD_THICK_HIDE, MOD_PACIFIST, MOD_GLASS_CANNON } from "./layout";
import { pct, rangeRoll } from "./rng";

export const FIGHT_HP_BASE: int32 = 100;
export const FIGHT_HP_PER_GRIT: int32 = 4;
export const DMG: int32 = 3;
export const ROLL_LO: int32 = 20;
export const ROLL_HI: int32 = 180;
export const COUNTER_NUM: int32 = 1;
export const COUNTER_DEN: int32 = 1;
export const DODGE_CAP: int32 = 30;
export const DODGE_DIV: int32 = 2;
export const THICK_HIDE_DODGE: int32 = 10;
export const CRIT_BASE: int32 = 5;
export const CRIT_DIV: int32 = 4;
export const SCAVENGER_CRIT: int32 = 15;
export const CRIT_NUM: int32 = 200;
export const MAX_ROUNDS: int32 = 8;

export const K_BPS: int32 = 15000;
export const MIN_BITE_STAKE: uint64 = 5000000;
export const PACIFIST_LOOT_CUT_BPS: int32 = 7000;
export const THICK_HIDE_LOOT_CUT_BPS: int32 = 5000;
export const THICK_HIDE_FIGHTS: int32 = 3;

export function fightHp(c: Combatant): int32 {
	const base = FIGHT_HP_BASE + FIGHT_HP_PER_GRIT * c.grit;
	return (c.mods & MOD_GLASS_CANNON) != 0 ? base / 2 : base;
}

export function dodgePct(c: Combatant): int32 {
	let d = c.grit / DODGE_DIV;
	if ((c.mods & MOD_THICK_HIDE) != 0) { d += THICK_HIDE_DODGE; }
	return d > DODGE_CAP ? DODGE_CAP : d;
}

export function critPct(attacker: Combatant, target: Combatant): int32 {
	let c = CRIT_BASE + attacker.might / CRIT_DIV;
	if ((attacker.mods & MOD_SCAVENGER) != 0 && target.hearts < attacker.hearts) { c += SCAVENGER_CRIT; }
	return c;
}

function strike(seed: uint64, draw: int32, striker: Combatant, target: Combatant, num: int32, den: int32): int32 {
	if (pct(seed, draw) < dodgePct(target)) { return 0; }
	let dmg = striker.might * DMG * rangeRoll(seed, draw + 1, ROLL_LO, ROLL_HI) / 100;
	if ((striker.mods & MOD_GLASS_CANNON) != 0) { dmg *= 2; }
	if (pct(seed, draw + 2) < critPct(striker, target)) { dmg = dmg * CRIT_NUM / 100; }
	return dmg * num / den;
}

export function fight(seed: uint64, a: Combatant, d: Combatant, out res: FightResult): int32 {
	const hpA0 = fightHp(a);
	const hpD0 = fightHp(d);
	let hpA = hpA0;
	let hpD = hpD0;
	let round = 0;
	let draw = 0;
	while (round < MAX_ROUNDS && hpA > 0 && hpD > 0) {
		round += 1;
		hpD -= strike(seed, draw, a, d, 1, 1);
		hpA -= strike(seed, draw + 3, d, a, COUNTER_NUM, COUNTER_DEN);
		draw += 6;
	}
	const outcome = hpA * hpD0 > hpD * hpA0 ? (Outcome.AttackerWins as int32) : (Outcome.DefenderWins as int32);
	const built: FightResult = { outcome: outcome, rounds: round, hpA: hpA < 0 ? 0 : hpA, hpD: hpD < 0 ? 0 : hpD };
	res = built;
	return outcome;
}

export function canAttack(a: Combatant, fightsOutToday: int32): boolean {
	if ((a.mods & MOD_PACIFIST) != 0) { return false; }
	return fightsOutToday < attacksPerEpoch(a.might);
}

export function attacksPerEpoch(might: int32): int32 {
	return 1 + might / 10;
}

export function maxStake(harvestD: uint64): uint64 {
	const cap = harvestD * (BPS as uint64) / (K_BPS as uint64);
	return cap < MIN_BITE_STAKE ? MIN_BITE_STAKE : cap;
}

export function lootFor(stake: uint64, harvestD: uint64, d: Combatant, fightsInTodayD: int32): uint64 {
	const kS = stake * (K_BPS as uint64) / (BPS as uint64);
	let loot = kS < harvestD ? kS : harvestD;
	loot = loot * ((100 - d.grit) as uint64) / 100;
	if ((d.mods & MOD_PACIFIST) != 0) { loot = loot * ((BPS - PACIFIST_LOOT_CUT_BPS) as uint64) / (BPS as uint64); }
	if ((d.mods & MOD_THICK_HIDE) != 0 && fightsInTodayD < THICK_HIDE_FIGHTS) { loot = loot * ((BPS - THICK_HIDE_LOOT_CUT_BPS) as uint64) / (BPS as uint64); }
	return loot;
}

export function biteAllowed(harvestDBefore: uint64, powerA: int32, powerD: int32, bitesInTodayD: int32): boolean {
	return harvestDBefore == 0 && powerD * 2 >= powerA && bitesInTodayD < 1;
}

test "fight is deterministic per seed" {
	const a: Combatant = { might: 8, grit: 5, hearts: 5, mods: 0 };
	const d: Combatant = { might: 8, grit: 5, hearts: 5, mods: 0 };
	let r1: FightResult = { outcome: 0, rounds: 0, hpA: 0, hpD: 0 };
	let r2: FightResult = { outcome: 0, rounds: 0, hpA: 0, hpD: 0 };
	fight(42, a, d, out r1);
	fight(42, a, d, out r2);
	assert r1.outcome == r2.outcome && r1.rounds == r2.rounds && r1.hpA == r2.hpA && r1.hpD == r2.hpD;
	assert r1.rounds >= 1 && r1.rounds <= MAX_ROUNDS;
}

test "zero might attacker never wins" {
	const a: Combatant = { might: 0, grit: 5, hearts: 5, mods: 0 };
	const d: Combatant = { might: 8, grit: 5, hearts: 5, mods: 0 };
	let r: FightResult = { outcome: 0, rounds: 0, hpA: 0, hpD: 0 };
	let seed: uint64 = 0;
	while (seed < 200) {
		assert fight(seed, a, d, out r) == (Outcome.DefenderWins as int32);
		seed += 1;
	}
}

test "loot caps at k times stake and at harvest" {
	const d: Combatant = { might: 5, grit: 10, hearts: 5, mods: 0 };
	assert lootFor(100, 1000000, d, 0) == 135;
	assert lootFor(100, 120, d, 0) == 108;
	const p: Combatant = { might: 5, grit: 0, hearts: 5, mods: MOD_PACIFIST };
	assert lootFor(100, 1000000, p, 0) == 45;
	const t: Combatant = { might: 5, grit: 0, hearts: 5, mods: MOD_THICK_HIDE };
	assert lootFor(100, 1000000, t, 0) == 75;
	assert lootFor(100, 1000000, t, 3) == 150;
}

test "stake bounds and attack budget" {
	assert maxStake(0) == MIN_BITE_STAKE;
	assert maxStake(1500) == MIN_BITE_STAKE;
	assert maxStake(15000000) == 10000000;
	assert attacksPerEpoch(5) == 1;
	assert attacksPerEpoch(25) == 3;
	const p: Combatant = { might: 50, grit: 0, hearts: 5, mods: MOD_PACIFIST };
	assert !canAttack(p, 0);
	const f: Combatant = { might: 12, grit: 0, hearts: 5, mods: 0 };
	assert canAttack(f, 1);
	assert !canAttack(f, 2);
}

test "bite needs empty harvest, comparable power and no bite yet" {
	assert biteAllowed(0, 20, 10, 0);
	assert !biteAllowed(0, 21, 10, 0);
	assert !biteAllowed(1, 20, 10, 0);
	assert !biteAllowed(0, 20, 10, 1);
}
