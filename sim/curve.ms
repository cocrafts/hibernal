import { Combatant, Odds, estimateOdds } from "../rules/index";

function odds(am: int32, ag: int32, dm: int32, dg: int32, runs: int32): Odds {
	const a: Combatant = { might: am, grit: ag, hearts: 5, mods: 0 };
	const d: Combatant = { might: dm, grit: dg, hearts: 5, mods: 0 };
	let o: Odds = { pwinBps: 0, avgRoundsX100: 0, runs: 0 };
	estimateOdds(a, d, 7, runs, out o);
	return o;
}

function row(label: string, am: int32, ag: int32, dm: int32, dg: int32): void {
	const o = odds(am, ag, dm, dg, 4000);
	console.log(label + "\tA(" + String(am) + "," + String(ag) + ") vs D(" + String(dm) + "," + String(dg) + ")\tpwin=" + String(o.pwinBps) + "bps\trounds=" + String(o.avgRoundsX100));
}

function main(): int32 {
	row("equal low ", 5, 5, 5, 5);
	row("equal mid ", 8, 8, 8, 8);
	row("equal high", 20, 20, 20, 20);
	row("2x might  ", 16, 8, 8, 8);
	row("0.5x might", 4, 8, 8, 8);
	row("2x grit   ", 8, 16, 8, 8);
	row("0.5x grit ", 8, 4, 8, 8);
	row("start F v W", 8, 5, 5, 5);
	row("start W v F", 5, 5, 8, 5);
	row("start S v F", 5, 8, 8, 5);
	row("start F v S", 8, 5, 5, 8);
	return 0;
}
process.exit(main());
