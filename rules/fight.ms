import { Combatant, Mod } from "./stats";
import { BPS } from "./units";
import { Dice } from "./rng";

export const INCOMING_CAP: int32 = 3;
export const BITES_CAP: int32 = 1;
export const BITE_BPS: int32 = 1000;
export const BITE_CAP_BPS: int32 = 2000;
export const BITE_RATIO_MIN_BPS: int32 = 5000;
export const BITE_RATIO_MAX_BPS: int32 = 20000;
export const DEFEAT_BPS: int32 = 1000;
export const FIGHT_HP_BASE: int32 = 800;
export const FIGHT_HP_PER_GRIT: int32 = 7;
export const DAMAGE: int32 = 3;
export const ROLL_MIN: int32 = 10;
export const ROLL_MAX: int32 = 160;
export const DODGE_GRIT_DIVISOR: int32 = 8;
export const DODGE_ACCURACY_DIVISOR: int32 = 2;
export const DODGE_CAP: int32 = 30;
export const THICK_HIDE_DODGE: int32 = 10;
export const CRIT_BASE: int32 = 10;
export const CRIT_ACCURACY_DIVISOR: int32 = 9;
export const SCAVENGER_CRIT: int32 = 15;
export const CRIT_DAMAGE_PERCENT: int32 = 200;
export const ARMOR_PERCENT: int32 = 200;
export const MIN_DAMAGE_PERCENT: int32 = 20;
export const HASTE_DIVISOR: int32 = 3;
export const HASTE_CAP: int32 = 70;
export const LIFESTEAL_BPS_PER_POINT: int32 = 80;
export const BLEED_BPS_PER_POINT: int32 = 40;
export const BLEED_ROUNDS: int32 = 3;
export const MAX_ROUNDS: int32 = 6;
export const DRAWS_PER_STRIKE: int32 = 4;
export const DRAWS_PER_ROUND: int32 = 13;
export const ATTACK_MIGHT_DIVISOR: int32 = 100;
export const GRIT_LOOT_SCALE: int32 = 1000;
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
	Dead,
	TargetDead,
	NotANeighbor,
	Unsettled,
	Shielded,
	TargetShielded,
	AlreadyAttacked,
	TargetBusy,
	Broke,
}

export enum Side {
	Attacker,
	Defender,
}

export enum Initiative {
	Together,
	AttackerFirst,
	DefenderFirst,
}

export enum StrikeKind {
	Skipped,
	Dodged,
	Hit,
	Critical,
}

export struct Strike {
	kind: StrikeKind;
	damage: int32;
	blocked: int32;
	healed: int32;
	bleed: int32;
}

export struct Bleeding {
	damage: int32;
	rounds: int32;
}

export struct FightState {
	round: int32;
	attackerHpStart: int32;
	defenderHpStart: int32;
	attackerHp: int32;
	defenderHp: int32;
	attackerBleeding: Bleeding;
	defenderBleeding: Bleeding;
}

export struct Round {
	initiative: Initiative;
	attackerStrike: Strike;
	defenderStrike: Strike;
	hasteSide: Side;
	haste: Strike;
	attackerBleedTaken: int32;
	defenderBleedTaken: int32;
	after: FightState;
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

export function dodgePercent(this target: Combatant, striker: Combatant): int32 {
	const thickHide = target.mods.has(Mod.ThickHide) ? THICK_HIDE_DODGE : 0;
	const evasion = Math.min(target.grit / DODGE_GRIT_DIVISOR + thickHide, DODGE_CAP);
	return Math.max(evasion - striker.accuracy / DODGE_ACCURACY_DIVISOR, 0);
}

export function critPercent(this striker: Combatant, target: Combatant): int32 {
	const scavenger = striker.mods.has(Mod.Scavenger) && target.hearts < striker.hearts;
	return CRIT_BASE + striker.accuracy / CRIT_ACCURACY_DIVISOR + (scavenger ? SCAVENGER_CRIT : 0);
}

export function hastePercent(this fast: Combatant, slow: Combatant): int32 {
	if (fast.speed <= slow.speed) { return 0; }
	const lead = (fast.speed - slow.speed) * 100 / (Math.max(slow.speed, 1) * HASTE_DIVISOR);
	return Math.min(lead, HASTE_CAP);
}

function noStrike(): Strike {
	return { kind: StrikeKind.Skipped, damage: 0, blocked: 0, healed: 0, bleed: 0 };
}

function strike(this striker: Combatant, target: Combatant, dice: Dice): Strike {
	if (dice.percent(0) < target.dodgePercent(striker)) {
		return { ...noStrike(), kind: StrikeKind.Dodged };
	}
	const rolled = striker.might * DAMAGE * dice.roll(1, ROLL_MIN, ROLL_MAX) / 100;
	const raw = striker.mods.has(Mod.GlassCannon) ? rolled * 2 : rolled;
	const critical = dice.percent(2) < striker.critPercent(target);
	const floor = raw * MIN_DAMAGE_PERCENT / 100;
	const armored = Math.max(raw - target.armor * ARMOR_PERCENT / 100, floor);
	const damage = critical ? raw * CRIT_DAMAGE_PERCENT / 100 : armored;
	return {
		kind: critical ? StrikeKind.Critical : StrikeKind.Hit,
		damage: damage,
		blocked: critical ? 0 : raw - armored,
		healed: damage * striker.lifesteal * LIFESTEAL_BPS_PER_POINT / BPS,
		bleed: damage * striker.bleed * BLEED_BPS_PER_POINT / BPS,
	};
}

function noBleeding(): Bleeding {
	return { damage: 0, rounds: 0 };
}

function worsen(this bleeding: Bleeding, damage: int32): Bleeding {
	if (damage <= 0) { return bleeding; }
	return { damage: Math.max(bleeding.damage, damage), rounds: BLEED_ROUNDS };
}

function pending(this bleeding: Bleeding): int32 {
	return bleeding.rounds > 0 ? bleeding.damage : 0;
}

function tick(this bleeding: Bleeding): Bleeding {
	if (bleeding.rounds <= 1) { return noBleeding(); }
	return { ...bleeding, rounds: bleeding.rounds - 1 };
}

export function start(
	this typeof FightState,
	attacker: Combatant,
	defender: Combatant,
): FightState {
	return {
		round: 0,
		attackerHpStart: attacker.fightHp(),
		defenderHpStart: defender.fightHp(),
		attackerHp: attacker.fightHp(),
		defenderHp: defender.fightHp(),
		attackerBleeding: noBleeding(),
		defenderBleeding: noBleeding(),
	};
}

export function isOver(this state: FightState): boolean {
	return state.round >= MAX_ROUNDS || state.attackerHp <= 0 || state.defenderHp <= 0;
}

function landOnDefender(this state: FightState, landed: Strike): FightState {
	return {
		...state,
		defenderHp: state.defenderHp - landed.damage,
		attackerHp: Math.min(state.attackerHp + landed.healed, state.attackerHpStart),
		defenderBleeding: state.defenderBleeding.worsen(landed.bleed),
	};
}

function landOnAttacker(this state: FightState, landed: Strike): FightState {
	return {
		...state,
		attackerHp: state.attackerHp - landed.damage,
		defenderHp: Math.min(state.defenderHp + landed.healed, state.defenderHpStart),
		attackerBleeding: state.attackerBleeding.worsen(landed.bleed),
	};
}

function initiativeOf(attacker: Combatant, defender: Combatant): Initiative {
	if (attacker.speed > defender.speed) { return Initiative.AttackerFirst; }
	if (attacker.speed < defender.speed) { return Initiative.DefenderFirst; }
	return Initiative.Together;
}

export function nextRound(
	this attacker: Combatant,
	defender: Combatant,
	seed: uint64,
	before: FightState,
): Round {
	const dice: Dice = { seed: seed, draw: before.round * DRAWS_PER_ROUND };
	const initiative = initiativeOf(attacker, defender);
	const attackerFirst = initiative == Initiative.AttackerFirst;
	const defenderFirst = initiative == Initiative.DefenderFirst;
	const attackerSwing = attacker.strike(defender, dice);
	const defenderSwing = defender.strike(attacker, dice.advance(DRAWS_PER_STRIKE));
	const opened: FightState = { ...before, round: before.round + 1 };
	const defenderOpened = defenderFirst ? opened.landOnAttacker(defenderSwing) : opened;
	const attackerDown = defenderFirst && defenderOpened.attackerHp <= 0;
	const attackerStrike = attackerDown ? noStrike() : attackerSwing;
	const attackerLanded = defenderOpened.landOnDefender(attackerStrike);
	const defenderDown = attackerFirst && attackerLanded.defenderHp <= 0;
	const defenderStrike = defenderDown ? noStrike() : defenderSwing;
	const exchanged = defenderFirst
		? attackerLanded
		: attackerLanded.landOnAttacker(defenderStrike);
	const bothStanding = exchanged.attackerHp > 0 && exchanged.defenderHp > 0;
	const hasteRoll = dice.percent(2 * DRAWS_PER_STRIKE);
	const attackerHastes = bothStanding && hasteRoll < attacker.hastePercent(defender);
	const defenderHastes = bothStanding && hasteRoll < defender.hastePercent(attacker);
	const hasteDice = dice.advance(2 * DRAWS_PER_STRIKE + 1);
	const attackerHaste = attackerHastes ? attacker.strike(defender, hasteDice) : noStrike();
	const haste = defenderHastes ? defender.strike(attacker, hasteDice) : attackerHaste;
	const hasted = attackerHastes ? exchanged.landOnDefender(haste) : exchanged.landOnAttacker(haste);
	const attackerBleedTaken = hasted.attackerBleeding.pending();
	const defenderBleedTaken = hasted.defenderBleeding.pending();
	return {
		initiative: initiative,
		attackerStrike: attackerStrike,
		defenderStrike: defenderStrike,
		hasteSide: defenderHastes ? Side.Defender : Side.Attacker,
		haste: haste,
		attackerBleedTaken: attackerBleedTaken,
		defenderBleedTaken: defenderBleedTaken,
		after: {
			...hasted,
			attackerHp: hasted.attackerHp - attackerBleedTaken,
			defenderHp: hasted.defenderHp - defenderBleedTaken,
			attackerBleeding: hasted.attackerBleeding.tick(),
			defenderBleeding: hasted.defenderBleeding.tick(),
		},
	};
}

export function finish(this state: FightState): FightResult {
	const attackerShare = state.attackerHp * state.defenderHpStart;
	const defenderShare = state.defenderHp * state.attackerHpStart;
	return {
		outcome: attackerShare > defenderShare ? Outcome.AttackerWins : Outcome.DefenderWins,
		rounds: state.round,
		attackerHp: Math.max(state.attackerHp, 0),
		defenderHp: Math.max(state.defenderHp, 0),
	};
}

export function fight(this attacker: Combatant, defender: Combatant, seed: uint64): FightResult {
	let state = FightState.start(attacker, defender);
	while (!state.isOver()) {
		state = attacker.nextRound(defender, seed, state).after;
	}
	return state.finish();
}

export function attacksPerEpoch(this attacker: Combatant): int32 {
	return 1 + attacker.might / ATTACK_MIGHT_DIVISOR;
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
	const kept = Math.max(GRIT_LOOT_SCALE - defender.grit, 0);
	const afterGrit = reachable * (kept as uint64) / (GRIT_LOOT_SCALE as uint64);
	const pacifist = defender.mods.has(Mod.Pacifist);
	const afterPacifist = pacifist ? applyCut(afterGrit, PACIFIST_LOOT_CUT_BPS) : afterGrit;
	const thickHide = defender.mods.has(Mod.ThickHide) && fightsInToday < THICK_HIDE_FIGHTS;
	return thickHide ? applyCut(afterPacifist, THICK_HIDE_LOOT_CUT_BPS) : afterPacifist;
}

export function shareOfHearts(maxHearts: int32, shareBps: int64): int32 {
	const scale = BPS as int64;
	return Math.max((((maxHearts as int64) * shareBps + scale - 1) / scale) as int32, 1);
}

export function biteHearts(
	stake: uint64,
	loot: uint64,
	attackerPower: int32,
	defenderPower: int32,
	defenderMaxHearts: int32,
	defenderBitesToday: int32,
): int32 {
	if (loot >= stake || defenderBitesToday >= BITES_CAP) { return 0; }
	const divisor: int32 = Math.max(defenderPower, 1);
	const ratioBps = (attackerPower as int64) * (BPS as int64) / (divisor as int64);
	const clamped = Math.max(
		Math.min(ratioBps, BITE_RATIO_MAX_BPS as int64),
		BITE_RATIO_MIN_BPS as int64,
	);
	const bite = shareOfHearts(defenderMaxHearts, (BITE_BPS as int64) * clamped / (BPS as int64));
	return Math.min(bite, shareOfHearts(defenderMaxHearts, BITE_CAP_BPS as int64));
}

export function defeatHearts(maxHearts: int32): int32 {
	return shareOfHearts(maxHearts, DEFEAT_BPS as int64);
}

test "fight is deterministic per seed" {
	const attacker = Combatant.plain(80, 50, 5);
	const defender = Combatant.plain(80, 50, 5);
	const first = attacker.fight(defender, 42);
	const second = attacker.fight(defender, 42);
	assert first == second;
	assert first.rounds >= 1 && first.rounds <= MAX_ROUNDS;
}

test "zero might attacker never wins" {
	const attacker = Combatant.plain(0, 50, 5);
	const defender = Combatant.plain(80, 50, 5);
	for (let seed: uint64 = 0; seed < 200; seed++) {
		assert attacker.fight(defender, seed).outcome == Outcome.DefenderWins;
	}
}

test "loot caps at the stake multiple and at harvest" {
	const defender = Combatant.plain(50, 100, 5);
	assert defender.lootFor(100, 1000000, 0) == 135;
	assert defender.lootFor(100, 120, 0) == 108;
	const bare = Combatant.plain(50, 0, 5);
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
	assert Combatant.plain(50, 0, 5).attacksPerEpoch() == 1;
	assert Combatant.plain(250, 0, 5).attacksPerEpoch() == 3;
	const strong = Combatant.plain(500, 0, 5);
	const pacifist: Combatant = { ...strong, mods: Mod.Pacifist | Mod.Pacifist };
	const refusal = pacifist.attacksLeft(0);
	assert !refusal.ok;
	if (!refusal.ok) { assert refusal.error == AttackError.Pacifist; }
	const fighter = Combatant.plain(120, 0, 5);
	const oneLeft = fighter.attacksLeft(1);
	assert oneLeft.ok;
	if (oneLeft.ok) { assert oneLeft.value == 1; }
	const noneLeft = fighter.attacksLeft(2);
	assert !noneLeft.ok;
	if (!noneLeft.ok) { assert noneLeft.error == AttackError.OutOfAttacks; }
}

test "a robber that takes back its stake leaves the hearts alone, one that does not bites" {
	assert biteHearts(100, 100, 30, 10, 10, 0) == 0;
	assert biteHearts(100, 99, 10, 10, 10, 0) == 1;
	assert biteHearts(100, 0, 10, 10, 40, 0) == 4;
	assert biteHearts(100, 0, 15, 10, 40, 0) == 6;
	assert biteHearts(100, 0, 40, 10, 40, 0) == 8;
	assert biteHearts(100, 0, 1, 10, 40, 0) == 2;
	assert biteHearts(100, 0, 20, 10, 40, BITES_CAP) == 0;
	assert defeatHearts(10) == 1;
	assert defeatHearts(35) == 4;
}

function firstHitSeed(attacker: Combatant, defender: Combatant): uint64 {
	for (let seed: uint64 = 0; seed < 1000; seed++) {
		const round = attacker.nextRound(defender, seed, FightState.start(attacker, defender));
		if (round.attackerStrike.kind == StrikeKind.Hit) { return seed; }
	}
	return 0;
}

test "the faster side strikes first and a knockout skips the reply" {
	const quick: Combatant = { ...Combatant.plain(3000, 0, 5), speed: 200 };
	const slow = Combatant.plain(50, 0, 5);
	const round = quick.nextRound(slow, 1, FightState.start(quick, slow));
	assert round.initiative == Initiative.AttackerFirst;
	assert round.after.defenderHp <= 0;
	assert round.defenderStrike.kind == StrikeKind.Skipped;
	const even = slow.nextRound(slow, 1, FightState.start(slow, slow));
	assert even.initiative == Initiative.Together;
}

test "armor blocks part of a normal hit" {
	const attacker = Combatant.plain(200, 0, 5);
	const bare = Combatant.plain(50, 0, 5);
	const plated: Combatant = { ...bare, armor: 60 };
	const seed = firstHitSeed(attacker, bare);
	const open = attacker.nextRound(bare, seed, FightState.start(attacker, bare)).attackerStrike;
	const plating = FightState.start(attacker, plated);
	const blocked = attacker.nextRound(plated, seed, plating).attackerStrike;
	assert open.kind == StrikeKind.Hit && blocked.kind == StrikeKind.Hit;
	assert blocked.damage < open.damage;
	assert blocked.blocked == open.damage - blocked.damage;
	assert blocked.damage >= open.damage * MIN_DAMAGE_PERCENT / 100;
}

test "accuracy cancels dodge and raises crit" {
	const evasive = Combatant.plain(50, 400, 5);
	const plain = Combatant.plain(50, 0, 5);
	const sharp: Combatant = { ...plain, accuracy: 60 };
	assert evasive.dodgePercent(plain) == DODGE_CAP;
	assert evasive.dodgePercent(sharp) == 0;
	assert sharp.critPercent(plain) == CRIT_BASE + 60 / CRIT_ACCURACY_DIVISOR;
}

test "lifesteal heals the striker and bleed ticks on the target" {
	const leech: Combatant = { ...Combatant.plain(200, 0, 5), lifesteal: 100, bleed: 100 };
	const target = Combatant.plain(200, 0, 5);
	const wounded: FightState = { ...FightState.start(leech, target), attackerHp: 500 };
	const seed = firstHitSeed(leech, target);
	const round = leech.nextRound(target, seed, wounded);
	assert round.attackerStrike.healed > 0;
	assert round.defenderBleedTaken == round.attackerStrike.bleed;
	assert round.after.defenderBleeding.rounds == BLEED_ROUNDS - 1;
}

test "haste only favours the faster side" {
	const quick: Combatant = { ...Combatant.plain(50, 0, 5), speed: 150 };
	const slow = Combatant.plain(50, 0, 5);
	assert quick.hastePercent(slow) == Math.min(100 * 100 / (50 * HASTE_DIVISOR), HASTE_CAP);
	assert slow.hastePercent(quick) == 0;
}

test "fight is the rounds played until one side is over" {
	const attacker: Combatant = { ...Combatant.plain(120, 90, 5), speed: 70, armor: 20, bleed: 30 };
	const defender: Combatant = { ...Combatant.plain(110, 120, 4), accuracy: 40, lifesteal: 30 };
	for (let seed: uint64 = 0; seed < 50; seed++) {
		let state = FightState.start(attacker, defender);
		let rounds = 0;
		while (!state.isOver()) {
			state = attacker.nextRound(defender, seed, state).after;
			rounds += 1;
		}
		assert state.finish() == attacker.fight(defender, seed);
		assert rounds <= MAX_ROUNDS;
	}
}
