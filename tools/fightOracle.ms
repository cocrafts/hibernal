import { Combatant, Outcome, fight } from "../rules/index";

function describe(attacker: Combatant, defender: Combatant, seed: uint64): string {
	const result = attacker.fight(defender, seed);
	const winner = result.outcome == Outcome.AttackerWins ? 1 : 0;
	return `seed=${seed} outcome=${winner} rounds=${result.rounds} attackerHp=${Math.max(result.attackerHp, 0)} defenderHp=${Math.max(result.defenderHp, 0)}`;
}

function main(): int32 {
	console.log(describe(Combatant.plain(80, 50, 5), Combatant.plain(50, 80, 5), 42));
	console.log(describe(Combatant.plain(50, 50, 5), Combatant.plain(50, 50, 5), 7));
	console.log(describe(Combatant.plain(200, 200, 5), Combatant.plain(160, 80, 5), 123456789));
	return 0;
}

process.exit(main());
