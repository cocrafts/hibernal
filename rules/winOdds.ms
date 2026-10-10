import * as arithmetic from "std/solana/arithmetic";
import { Combatant } from "./stats";
import { BPS } from "./units";
import { Outcome, fight } from "./fight";
import { splitmix } from "./rng";

export const ODDS_DEFAULT_RUNS: int32 = 2000;

export struct Odds {
	winChanceBps: int32;
	averageRoundsTimes100: int32;
	runs: int32;
}

export function oddsAgainst(
	this attacker: Combatant,
	defender: Combatant,
	firstSeed: uint64,
	runs: int32,
): Odds {
	let wins = 0;
	let totalRounds = 0;
	for (let run = 0; run < runs; run++) {
		const result = attacker.fight(defender, splitmix(firstSeed + (run as uint64)));
		if (result.outcome == Outcome.AttackerWins) { wins += 1; }
		totalRounds += result.rounds;
	}
	return {
		winChanceBps: runs == 0 ? 0 : wins * BPS / runs,
		averageRoundsTimes100: runs == 0 ? 0 : totalRounds * 100 / runs,
		runs: runs,
	};
}

export function winChanceAgainst(
	this attacker: Combatant,
	defender: Combatant,
	firstSeed: uint64,
	runs: int32,
): int32 {
	return attacker.oddsAgainst(defender, firstSeed, runs).winChanceBps;
}

test "win chance grows with might" {
	const defender = Combatant.plain(80, 50, 5);
	const weaker = Combatant.plain(40, 50, 5).winChanceAgainst(defender, 1, 500);
	const equal = Combatant.plain(80, 50, 5).winChanceAgainst(defender, 1, 500);
	const stronger = Combatant.plain(160, 50, 5).winChanceAgainst(defender, 1, 500);
	assert weaker < equal;
	assert equal < stronger;
}
