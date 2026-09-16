import {
	Combatant,
	FightState,
	Round,
	Odds,
	Food,
	modsFromMask,
	splitmix,
	oddsAgainst,
	nextRound,
	fightHp,
	dodgePercent,
	critPercent,
	hastePercent,
	attacksPerEpoch,
	isOver,
	emissionFor,
	foodCost,
	xpToReach,
	nodeCost,
} from "../../rules/index";

export function makeCombatant(
	might: int32,
	grit: int32,
	speed: int32,
	armor: int32,
	accuracy: int32,
	lifesteal: int32,
	bleed: int32,
	hearts: int32,
	modsMask: int32,
): Combatant {
	return {
		might: might,
		grit: grit,
		speed: speed,
		armor: armor,
		accuracy: accuracy,
		lifesteal: lifesteal,
		bleed: bleed,
		hearts: hearts,
		mods: modsFromMask(modsMask),
	};
}

export function odds(
	this attacker: Combatant,
	defender: Combatant,
	firstSeed: int32,
	runs: int32,
): Odds {
	return attacker.oddsAgainst(defender, firstSeed as uint64, runs);
}

export function firstFightSeed(firstSeed: int32): uint64 {
	return splitmix(firstSeed as uint64);
}

export function startState(this attacker: Combatant, defender: Combatant): FightState {
	return FightState.start(attacker, defender);
}

export function replay(this attacker: Combatant, defender: Combatant, seed: uint64): Round[] {
	const rounds: Round[] = [];
	let state = FightState.start(attacker, defender);
	while (!state.isOver()) {
		const round = attacker.nextRound(defender, seed, state);
		rounds.push(round);
		state = round.after;
	}
	return rounds;
}

export function derivedFor(this self: Combatant, other: Combatant): int32[] {
	return [
		self.fightHp(),
		self.dodgePercent(other),
		self.critPercent(other),
		self.hastePercent(other),
		self.attacksPerEpoch(),
	];
}

export function emissionAt(epoch: int32): int32 {
	return (emissionFor(epoch as uint64) / 1000000) as int32;
}

export function foodCostAt(food: int32, level: int32): int32 {
	return (foodCost(food as Food, level) / 10000) as int32;
}

export function xpToReachAt(level: int32): int32 {
	return xpToReach(level) as int32;
}

export function nodeCostAt(id: int32): int32 {
	return nodeCost(id);
}
