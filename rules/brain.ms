import { Combatant } from "./stats";
import { BPS } from "./units";
import { Tree } from "./tree";
import { Pet } from "./layout";
import { Food, levelCost, foodCost, stakeSplit } from "./emission";
import { maxStake } from "./fight";
import { winChanceAgainst } from "./winOdds";

export const BRAIN_ODDS_RUNS: int32 = 400;

export enum PersonaKind {
	Cautious,
	Greedy,
	Vengeful,
}

export enum Skip {
	NotHungry,
	Broke,
	Shielded,
	CannotAttack,
	EmptyHarvest,
	NoStake,
	OddsTooLow,
}

export struct Persona {
	minWinChanceBps: int32;
	reserveBps: int32;
	stakeBps: int32;
	minHearts: int32;
}

export function of(this typeof Persona, kind: PersonaKind): Persona {
	return match (kind) {
		PersonaKind.Cautious => ({
			minWinChanceBps: 7000,
			reserveBps: 7000,
			stakeBps: 5000,
			minHearts: 3,
		}),
		PersonaKind.Greedy => ({
			minWinChanceBps: 5000,
			reserveBps: 3000,
			stakeBps: 10000,
			minHearts: 2,
		}),
		PersonaKind.Vengeful => ({
			minWinChanceBps: 4500,
			reserveBps: 5000,
			stakeBps: 10000,
			minHearts: 2,
		}),
	};
}

export function pickFood(
	this persona: Persona,
	hearts: int32,
	burrow: uint64,
	level: int32,
): Result<Food, Skip> {
	if (hearts > persona.minHearts + 1) { return Result.err(Skip.NotHungry); }
	for (let ordinal = Food.Large as int32; ordinal >= 0; ordinal--) {
		const food = ordinal as Food;
		if (burrow >= foodCost(food, level)) { return Result.ok(food); }
	}
	return Result.err(Skip.Broke);
}

export function shouldLevelUp(this persona: Persona, level: int32, burrow: uint64): boolean {
	const spendable = burrow * ((BPS - persona.reserveBps) as uint64) / (BPS as uint64);
	return levelCost(level) <= spendable;
}

export function chooseStake(
	this persona: Persona,
	defenderHarvest: uint64,
	attackerBurrow: uint64,
): uint64 {
	const cap = maxStake(defenderHarvest);
	const budget = attackerBurrow * (persona.stakeBps as uint64) / (BPS as uint64);
	return Math.min(cap, budget);
}

export function attackExpectedValue(
	this defender: Combatant,
	winChanceBps: int32,
	stake: uint64,
	harvest: uint64,
	fightsInToday: int32,
): int64 {
	const [winnings, _protocolFee] = stakeSplit(defender.lootFor(stake, harvest, fightsInToday));
	const weightedGain = (winnings as int64) * (winChanceBps as int64);
	const weightedLoss = (stake as int64) * ((BPS - winChanceBps) as int64);
	return (weightedGain - weightedLoss) / (BPS as int64);
}

export function scoreTarget(
	this persona: Persona,
	attacker: Pet,
	defender: Pet,
	epoch: uint64,
	seed: uint64,
): Result<int64, Skip> {
	if (defender.shieldedAt(epoch)) { return Result.err(Skip.Shielded); }
	const attackerCombatant = attacker.combatant();
	const defenderCombatant = defender.combatant();
	const remainingAttacks = attackerCombatant.attacksLeft(attacker.fightsOutOn(epoch));
	if (!remainingAttacks.ok) { return Result.err(Skip.CannotAttack); }
	if (defender.harvest == 0) { return Result.err(Skip.EmptyHarvest); }
	const stake = persona.chooseStake(defender.harvest, attacker.burrow);
	if (stake == 0) { return Result.err(Skip.NoStake); }
	const winChance = attackerCombatant.winChanceAgainst(defenderCombatant, seed, BRAIN_ODDS_RUNS);
	if (winChance < persona.minWinChanceBps) { return Result.err(Skip.OddsTooLow); }
	const expectedValue = defenderCombatant.attackExpectedValue(
		winChance,
		stake,
		defender.harvest,
		defender.fightsInOn(epoch),
	);
	return Result.ok(expectedValue);
}

function petWith(fighter: Combatant, harvest: uint64, burrow: uint64, bornEpoch: uint64): Pet {
	return {
		blockId: 0,
		slot: 0,
		alive: true,
		region: 0,
		hearts: fighter.hearts as uint8,
		maxHearts: 5,
		forage: 50,
		might: fighter.might as uint16,
		grit: fighter.grit as uint16,
		level: 0,
		pointsUnspent: 0,
		tree: Tree.empty(),
		harvest: harvest,
		burrow: burrow,
		rewardSnapshot: 0,
		bornEpoch: bornEpoch,
		lastTickEpoch: bornEpoch,
		fightsOutToday: 0,
		fightsInToday: 0,
		bitesInToday: 0,
		fightDay: 0,
		growthMultiplierBps: 0,
		growthMultiplierExpiry: 0,
		minHearts: 0,
		insurance: 0,
		scars: 0,
		lineageGeneration: 0,
	};
}

test "eat picks the best affordable food only when low" {
	const greedy = Persona.of(PersonaKind.Greedy);
	const full = greedy.pickFood(5, 1000000000, 0);
	assert !full.ok;
	if (!full.ok) { assert full.error == Skip.NotHungry; }
	const rich = greedy.pickFood(3, 1000000000, 0);
	assert rich.ok;
	if (rich.ok) { assert rich.value == Food.Large; }
	const tight = greedy.pickFood(3, 9000000, 0);
	assert tight.ok;
	if (tight.ok) { assert tight.value == Food.Small; }
	const broke = greedy.pickFood(1, 0, 0);
	assert !broke.ok;
	if (!broke.ok) { assert broke.error == Skip.Broke; }
}

test "level up respects reserve" {
	const half: Persona = {
		minWinChanceBps: 5000,
		reserveBps: 5000,
		stakeBps: 5000,
		minHearts: 2,
	};
	assert half.shouldLevelUp(0, 200000000);
	assert !half.shouldLevelUp(0, 199000000);
}

test "attack expected value follows odds" {
	const defender = Combatant.plain(50, 0, 5);
	assert defender.attackExpectedValue(9000, 100, 1000000, 0) > 0;
	assert defender.attackExpectedValue(3000, 100, 1000000, 0) < 0;
	assert defender.attackExpectedValue(9000, 100, 0, 0) < 0;
}

test "empty harvest target is never worth attacking" {
	const greedy = Persona.of(PersonaKind.Greedy);
	const attacker = petWith(Combatant.plain(500, 50, 5), 0, 1000000000, 0);
	const defender = petWith(Combatant.plain(50, 50, 5), 1000000000, 0, 0);
	const empty = greedy.scoreTarget(attacker, { ...defender, harvest: 0 }, 10, 1);
	assert !empty.ok;
	if (!empty.ok) { assert empty.error == Skip.EmptyHarvest; }
	const shielded = greedy.scoreTarget(attacker, { ...defender, bornEpoch: 9 }, 10, 1);
	assert !shielded.ok;
	if (!shielded.ok) { assert shielded.error == Skip.Shielded; }
	const juicy = greedy.scoreTarget(attacker, defender, 10, 1);
	assert juicy.ok;
	if (juicy.ok) { assert juicy.value > 0; }
}

test "daily attack counters reset with the fight day" {
	const greedy = Persona.of(PersonaKind.Greedy);
	const attacker = petWith(Combatant.plain(500, 50, 5), 0, 1000000000, 0);
	const defender = petWith(Combatant.plain(50, 50, 5), 1000000000, 0, 0);
	const spentToday: Pet = { ...attacker, fightDay: 10, fightsOutToday: 6 };
	const spent = greedy.scoreTarget(spentToday, defender, 10, 1);
	assert !spent.ok;
	if (!spent.ok) { assert spent.error == Skip.CannotAttack; }
	const spentYesterday: Pet = { ...attacker, fightDay: 9, fightsOutToday: 6 };
	assert greedy.scoreTarget(spentYesterday, defender, 10, 1).ok;
}

test "personas order by caution" {
	const cautious = Persona.of(PersonaKind.Cautious);
	const greedy = Persona.of(PersonaKind.Greedy);
	const vengeful = Persona.of(PersonaKind.Vengeful);
	assert cautious.minWinChanceBps > greedy.minWinChanceBps;
	assert greedy.minWinChanceBps > vengeful.minWinChanceBps;
}
