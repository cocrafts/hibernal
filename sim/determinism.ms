import { Combatant, FightResult, Stats, splitmix, fight, derivedStats, withNode, settleGlobal, pendingReward, levelCost, foodCost, estimateOdds, Odds } from "../rules/index";

function digestFights(n: int32): uint64 {
	let h: uint64 = 0x9e3779b97f4a7c15;
	let r: FightResult = { outcome: 0, rounds: 0, hpA: 0, hpD: 0 };
	let i = 0;
	while (i < n) {
		const seed = splitmix(i as uint64);
		const a: Combatant = { might: 1 + ((seed >> 8) % 40) as int32, grit: ((seed >> 16) % 40) as int32, hearts: 1 + ((seed >> 24) % 5) as int32, mods: ((seed >> 32) % 64) as int32 };
		const d: Combatant = { might: 1 + ((seed >> 40) % 40) as int32, grit: ((seed >> 48) % 40) as int32, hearts: 1 + ((seed >> 56) % 5) as int32, mods: ((seed >> 4) % 64) as int32 };
		fight(seed, a, d, out r);
		h = splitmix(h ^ (r.outcome as uint64) ^ ((r.rounds as uint64) << 8) ^ ((r.hpA as uint64) << 16) ^ ((r.hpD as uint64) << 32));
		i += 1;
	}
	return h;
}

function digestTree(): uint64 {
	let h: uint64 = 1;
	let bitmap: uint64 = 0;
	let s: Stats = { yield_: 0, might: 0, grit: 0, maxHearts: 0, mods: 0 };
	let i = 0;
	while (i < 24) {
		bitmap = withNode(bitmap, i);
		derivedStats(bitmap, out s);
		h = splitmix(h ^ (s.yield_ as uint64) ^ ((s.might as uint64) << 8) ^ ((s.grit as uint64) << 16) ^ ((s.maxHearts as uint64) << 24) ^ ((s.mods as uint64) << 32));
		i += 1;
	}
	return h;
}

function digestEconomy(): uint64 {
	let h: uint64 = 2;
	let e: uint64 = 0;
	while (e < 400) {
		const acc = settleGlobal(0, 0, e, 1234, e * 7);
		h = splitmix(h ^ acc ^ pendingReward(34, acc, acc / 3) ^ levelCost((e % 70) as int32) ^ foodCost(((e % 3) + 1) as int32, (e % 50) as int32));
		e += 1;
	}
	return h;
}

function digestOdds(): uint64 {
	const a: Combatant = { might: 9, grit: 6, hearts: 5, mods: 2 };
	const d: Combatant = { might: 7, grit: 9, hearts: 3, mods: 4 };
	let o: Odds = { pwinBps: 0, avgRoundsX100: 0, runs: 0 };
	estimateOdds(a, d, 99, 2000, out o);
	return splitmix((o.pwinBps as uint64) ^ ((o.avgRoundsX100 as uint64) << 20));
}

function main(): int32 {
	console.log("fights   " + String(digestFights(20000)));
	console.log("tree     " + String(digestTree()));
	console.log("economy  " + String(digestEconomy()));
	console.log("odds     " + String(digestOdds()));
	return 0;
}
process.exit(main());
