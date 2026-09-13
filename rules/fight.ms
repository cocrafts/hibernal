import { Combatant, Mod } from "./stats";
import { BPS } from "./units";
import { Dice } from "./rng";

export const INCOMING_CAP: int32 = 3;
export const BITES_CAP: int32 = 1;

export const FIGHT_HP_BASE: int32 = 100;
export const FIGHT_HP_PER_GRIT: int32 = 4;
export const DAMAGE: int32 = 3;
export const ROLL_MIN: int32 = 20;
export const ROLL_MAX: int32 = 180;
export const COUNTER_NUMERATOR: int32 = 1;
export const COUNTER_DENOMINATOR: int32 = 1;
export const DODGE_CAP: int32 = 30;
export const DODGE_GRIT_DIVISOR: int32 = 2;
export const THICK_HIDE_DODGE: int32 = 10;
export const CRIT_BASE: int32 = 5;
export const CRIT_MIGHT_DIVISOR: int32 = 4;
export const SCAVENGER_CRIT: int32 = 15;
export const CRIT_DAMAGE_PERCENT: int32 = 200;
export const MAX_ROUNDS: int32 = 8;

export const LOOT_PER_STAKE_BPS: int32 = 15000;
export const MIN_BITE_STAKE: uint64 = 5000000;
export const PACIFIST_LOOT_CUT_BPS: int32 = 7000;
export const THICK_HIDE_LOOT_CUT_BPS: int32 = 5000;
export const THICK_HIDE_FIGHTS: int32 = 3;

export enum Outcome {
	DefenderWins,
	AttackerWins,
}

export enum AttackError {
	Pacifist,
	OutOfAttacks,
}

export struct FightResult {
	outcome: Outcome;
	rounds: int32;
	attackerHp: int32;
	defenderHp: int32;
}

export function fightHp(this combatant: Combatant): int32 {
	const base = FIGHT_HP_BASE + FIGHT_HP_PER_GRIT * combatant.grit;
	return combatant.mods.has(Mod.GlassCannon) ? base / 2 : base;
}

export function dodgePercent(this combatant: Combatant): int32 {
	const thickHide = combatant.mods.has(Mod.ThickHide) ? THICK_HIDE_DODGE : 0;
	const raw = combatant.grit / DODGE_GRIT_DIVISOR + thickHide;
	return Math.min(raw, DODGE_CAP);
}

export function critPercent(this attacker: Combatant, target: Combatant): int32 {
	const scavenger = attacker.mods.has(Mod.Scavenger) && target.hearts < attacker.hearts;
	return CRIT_BASE + attacker.might / CRIT_MIGHT_DIVISOR + (scavenger ? SCAVENGER_CRIT : 0);
}

function strike(
	this striker: Combatant,
	target: Combatant,
	dice: Dice,
	damageNumerator: int32,
	damageDenominator: int32,
): int32 {
	if (dice.percent(0) < target.dodgePercent()) { return 0; }
	const hit = striker.might * DAMAGE * dice.roll(1, ROLL_MIN, ROLL_MAX) / 100;
	const heavy = striker.mods.has(Mod.GlassCannon) ? hit * 2 : hit;
	const critical = dice.percent(2) < striker.critPercent(target);
	const landed = critical ? heavy * CRIT_DAMAGE_PERCENT / 100 : heavy;
	return landed * damageNumerator / damageDenominator;
}

export function fight(this attacker: Combatant, defender: Combatant, seed: uint64): FightResult {
	const attackerHpStart = attacker.fightHp();
	const defenderHpStart = defender.fightHp();
	let attackerHp = attackerHpStart;
	let defenderHp = defenderHpStart;
	let round = 0;
	let dice: Dice = { seed: seed, draw: 0 };
	while (round < MAX_ROUNDS && attackerHp > 0 && defenderHp > 0) {
		round += 1;
		defenderHp -= attacker.strike(defender, dice, 1, 1);
		const counter = dice.advance(3);
		attackerHp -= defender.strike(attacker, counter, COUNTER_NUMERATOR, COUNTER_DENOMINATOR);
		dice = dice.advance(6);
	}
	const attackerAhead = attackerHp * defenderHpStart > defenderHp * attackerHpStart;
	return {
		outcome: attackerAhead ? Outcome.AttackerWins : Outcome.DefenderWins,
		rounds: round,
		attackerHp: attackerHp < 0 ? 0 : attackerHp,
		defenderHp: defenderHp < 0 ? 0 : defenderHp,
	};
}

export function attacksPerEpoch(this attacker: Combatant): int32 {
	return 1 + attacker.might / 10;
}

export function attacksLeft(
	this attacker: Combatant,
	fightsOutToday: int32,
): Result<int32, AttackError> {
	if (attacker.mods.has(Mod.Pacifist)) { return Result.err(AttackError.Pacifist); }
	const left = attacker.attacksPerEpoch() - fightsOutToday;
	return left > 0 ? Result.ok(left) : Result.err(AttackError.OutOfAttacks);
}

export function maxStake(defenderHarvest: uint64): uint64 {
	const cap = defenderHarvest * (BPS as uint64) / (LOOT_PER_STAKE_BPS as uint64);
	return Math.max(cap, MIN_BITE_STAKE);
}

function applyCut(loot: uint64, cutBps: int32): uint64 {
	return loot * ((BPS - cutBps) as uint64) / (BPS as uint64);
}

export function lootFor(
	this defender: Combatant,
	stake: uint64,
	harvest: uint64,
	fightsInToday: int32,
): uint64 {
	const stakeLoot = stake * (LOOT_PER_STAKE_BPS as uint64) / (BPS as uint64);
	const reachable = Math.min(stakeLoot, harvest);
	const afterGrit = reachable * ((100 - defender.grit) as uint64) / 100;
	const pacifist = defender.mods.has(Mod.Pacifist);
	const afterPacifist = pacifist ? applyCut(afterGrit, PACIFIST_LOOT_CUT_BPS) : afterGrit;
	const thickHide = defender.mods.has(Mod.ThickHide) && fightsInToday < THICK_HIDE_FIGHTS;
	return thickHide ? applyCut(afterPacifist, THICK_HIDE_LOOT_CUT_BPS) : afterPacifist;
}

export function biteAllowed(
	defenderHarvestBefore: uint64,
	attackerPower: int32,
	defenderPower: int32,
	defenderBitesToday: int32,
): boolean {
	const comparable = defenderPower * 2 >= attackerPower;
	return defenderHarvestBefore == 0 && comparable && defenderBitesToday < BITES_CAP;
}

test "fight is deterministic per seed" {
	const attacker = Combatant.plain(8, 5, 5);
	const defender = Combatant.plain(8, 5, 5);
	const first = attacker.fight(defender, 42);
	const second = attacker.fight(defender, 42);
	assert first == second;
	assert first.rounds >= 1 && first.rounds <= MAX_ROUNDS;
}

test "zero might attacker never wins" {
	const attacker = Combatant.plain(0, 5, 5);
	const defender = Combatant.plain(8, 5, 5);
	for (let seed: uint64 = 0; seed < 200; seed++) {
		assert attacker.fight(defender, seed).outcome == Outcome.DefenderWins;
	}
}

test "loot caps at the stake multiple and at harvest" {
	const defender = Combatant.plain(5, 10, 5);
	assert defender.lootFor(100, 1000000, 0) == 135;
	assert defender.lootFor(100, 120, 0) == 108;
	const bare = Combatant.plain(5, 0, 5);
	const pacifist: Combatant = { ...bare, mods: Mod.Pacifist | Mod.Pacifist };
	assert pacifist.lootFor(100, 1000000, 0) == 45;
	const thickHide: Combatant = { ...bare, mods: Mod.ThickHide | Mod.ThickHide };
	assert thickHide.lootFor(100, 1000000, 0) == 75;
	assert thickHide.lootFor(100, 1000000, 3) == 150;
}

test "stake bounds and attack budget" {
	assert maxStake(0) == MIN_BITE_STAKE;
	assert maxStake(1500) == MIN_BITE_STAKE;
	assert maxStake(15000000) == 10000000;
	assert Combatant.plain(5, 0, 5).attacksPerEpoch() == 1;
	assert Combatant.plain(25, 0, 5).attacksPerEpoch() == 3;
	const strong = Combatant.plain(50, 0, 5);
	const pacifist: Combatant = { ...strong, mods: Mod.Pacifist | Mod.Pacifist };
	const refusal = pacifist.attacksLeft(0);
	assert !refusal.ok;
	if (!refusal.ok) { assert refusal.error == AttackError.Pacifist; }
	const fighter = Combatant.plain(12, 0, 5);
	const oneLeft = fighter.attacksLeft(1);
	assert oneLeft.ok;
	if (oneLeft.ok) { assert oneLeft.value == 1; }
	const noneLeft = fighter.attacksLeft(2);
	assert !noneLeft.ok;
	if (!noneLeft.ok) { assert noneLeft.error == AttackError.OutOfAttacks; }
}

test "bite needs empty harvest, comparable power and no bite yet" {
	assert biteAllowed(0, 20, 10, 0);
	assert !biteAllowed(0, 21, 10, 0);
	assert !biteAllowed(1, 20, 10, 0);
	assert !biteAllowed(0, 20, 10, 1);
}
