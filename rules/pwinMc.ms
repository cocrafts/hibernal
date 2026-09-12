import { Combatant, FightResult, Outcome, BPS } from "./layout";
import { fight } from "./fight";
import { splitmix } from "./rng";

export const MC_DEFAULT_RUNS: int32 = 2000;

export struct Odds {
	pwinBps: int32;
	avgRoundsX100: int32;
	runs: int32;
}

export function estimateOdds(a: Combatant, d: Combatant, seed0: uint64, runs: int32, out odds: Odds): void {
	let wins = 0;
	let rounds = 0;
	let i = 0;
	let r: FightResult = { outcome: 0, rounds: 0, hpA: 0, hpD: 0 };
	while (i < runs) {
		const seed = splitmix(seed0 + (i as uint64));
		if (fight(seed, a, d, out r) == (Outcome.AttackerWins as int32)) { wins += 1; }
		rounds += r.rounds;
		i += 1;
	}
	const built: Odds = { pwinBps: runs == 0 ? 0 : wins * BPS / runs, avgRoundsX100: runs == 0 ? 0 : rounds * 100 / runs, runs: runs };
	odds = built;
}

export function pwinBps(a: Combatant, d: Combatant, seed0: uint64, runs: int32): int32 {
	let o: Odds = { pwinBps: 0, avgRoundsX100: 0, runs: 0 };
	estimateOdds(a, d, seed0, runs, out o);
	return o.pwinBps;
}

test "odds are monotone in might" {
	const d: Combatant = { might: 8, grit: 5, hearts: 5, mods: 0 };
	const weak: Combatant = { might: 4, grit: 5, hearts: 5, mods: 0 };
	const equal: Combatant = { might: 8, grit: 5, hearts: 5, mods: 0 };
	const strong: Combatant = { might: 16, grit: 5, hearts: 5, mods: 0 };
	const pw = pwinBps(weak, d, 1, 500);
	const pe = pwinBps(equal, d, 1, 500);
	const ps = pwinBps(strong, d, 1, 500);
	assert pw < pe;
	assert pe < ps;
}
