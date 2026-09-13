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
		{ label: "equal low", attacker: contender(50, 50), defender: contender(50, 50) },
		{ label: "equal mid", attacker: contender(80, 80), defender: contender(80, 80) },
		{ label: "equal high", attacker: contender(200, 200), defender: contender(200, 200) },
		{ label: "double might", attacker: contender(160, 80), defender: contender(80, 80) },
		{ label: "half might", attacker: contender(40, 80), defender: contender(80, 80) },
		{ label: "double grit", attacker: contender(80, 160), defender: contender(80, 80) },
		{ label: "half grit", attacker: contender(80, 40), defender: contender(80, 80) },
		{ label: "Fighter vs Worker", attacker: contender(80, 50), defender: contender(50, 50) },
		{ label: "Worker vs Fighter", attacker: contender(50, 50), defender: contender(80, 50) },
		{ label: "Survivor vs Fighter", attacker: contender(50, 80), defender: contender(80, 50) },
		{ label: "Fighter vs Survivor", attacker: contender(80, 50), defender: contender(50, 80) },
	];
	for (const matchup of matchups) { console.log(row(matchup)); }
	return 0;
}
process.exit(main());
