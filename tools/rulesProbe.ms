import { Combatant, FightResult, Stats, Outcome, fight, derivedStats, withNode, emissionFor, E0, canAllocate, KEYSTONE_GLASS_CANNON } from "../rules/index";

function check(): boolean {
	const weak: Combatant = { might: 0, grit: 5, hearts: 5, mods: 0 };
	const d: Combatant = { might: 8, grit: 5, hearts: 5, mods: 0 };
	let r: FightResult = { outcome: 0, rounds: 0, hpA: 0, hpD: 0 };
	if (fight(42, weak, d, out r) != (Outcome.DefenderWins as int32)) { return false; }
	if (r.rounds < 1) { return false; }
	let b: uint64 = withNode(0, 1);
	b = withNode(b, 9);
	b = withNode(b, 11);
	b = withNode(b, 13);
	if (!canAllocate(b, KEYSTONE_GLASS_CANNON, 1)) { return false; }
	let s: Stats = { yield_: 0, might: 0, grit: 0, maxHearts: 0, mods: 0 };
	derivedStats(withNode(b, KEYSTONE_GLASS_CANNON), out s);
	if (s.might != 9 || s.maxHearts != 2) { return false; }
	if (emissionFor(90) != E0 * 3 / 4) { return false; }
	return true;
}

function main(): int32 {
	if (check()) { console.log("rules ok"); } else { console.log("rules BAD"); }
	return 0;
}
main();
