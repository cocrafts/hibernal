import { Combatant, Odds, oddsAgainst } from "../rules/index";

struct Matchup {
	label: string;
	attacker: Combatant;
	defender: Combatant;
}

const RUNS_PER_MATCHUP: int32 = 4000;

function contender(might: int32, grit: int32): Combatant {
	return Combatant.plain(might, grit, 5);
}

function toString(this combatant: Combatant): string {
	return `(${combatant.might},${combatant.grit})`;
}

function toString(this odds: Odds): string {
	return `winChance=${odds.winChanceBps}bps\taverageRoundsTimes100=${odds.averageRoundsTimes100}`;
}

function row(matchup: Matchup): string {
	const odds = matchup.attacker.oddsAgainst(matchup.defender, 7, RUNS_PER_MATCHUP);
	return `${matchup.label}\tA${matchup.attacker} vs D${matchup.defender}\t${odds}`;
}

function main(): int32 {
	const matchups: Matchup[] = [
		{ label: "equal low", attacker: contender(5, 5), defender: contender(5, 5) },
		{ label: "equal mid", attacker: contender(8, 8), defender: contender(8, 8) },
		{ label: "equal high", attacker: contender(20, 20), defender: contender(20, 20) },
		{ label: "double might", attacker: contender(16, 8), defender: contender(8, 8) },
		{ label: "half might", attacker: contender(4, 8), defender: contender(8, 8) },
		{ label: "double grit", attacker: contender(8, 16), defender: contender(8, 8) },
		{ label: "half grit", attacker: contender(8, 4), defender: contender(8, 8) },
		{ label: "Fighter vs Worker", attacker: contender(8, 5), defender: contender(5, 5) },
		{ label: "Worker vs Fighter", attacker: contender(5, 5), defender: contender(8, 5) },
		{ label: "Survivor vs Fighter", attacker: contender(5, 8), defender: contender(8, 5) },
		{ label: "Fighter vs Survivor", attacker: contender(8, 5), defender: contender(5, 8) },
	];
	for (const matchup of matchups) { console.log(row(matchup)); }
	return 0;
}
process.exit(main());
