import {
	Combatant,
	splitmix,
	modsFromMask,
	winChanceAgainst,
	oddsKeyAgainst,
	nearestColumn,
	oddsCellBps,
	winChanceBps,
} from "../rules/index";

const PAIRS: int32 = 4000;
const RUNS: int32 = 2000;

function reachable(seed: uint64, withMods: boolean): Combatant {
	const mask = withMods ? (((seed >> 32) % 64) & ((seed >> 40) % 64)) as int32 : 0;
	return {
		...Combatant.plain(
			50 + (((seed >> 8) % 8) as int32) * 10,
			50 + (((seed >> 16) % 9) as int32) * 10,
			1 + ((seed >> 24) % 5) as int32,
		),
		mods: modsFromMask(mask),
	};
}

function insert(sorted: int32[], value: int32): void {
	let position = sorted.length;
	sorted.push(value);
	while (position > 0 && sorted[position - 1] > value) {
		sorted[position] = sorted[position - 1];
		position -= 1;
	}
	sorted[position] = value;
}

function report(label: string, errors: int32[]): void {
	let total = 0;
	for (const error of errors) { total += error; }
	const count = errors.length;
	const p90 = errors[count * 9 / 10];
	console.log(`${label} mean ${total / count} p90 ${p90} max ${errors[count - 1]} bps`);
}

function measure(label: string, withMods: boolean): void {
	const nearest: int32[] = [];
	const interpolated: int32[] = [];
	for (let index = 0; index < PAIRS; index++) {
		const seed = splitmix((index as uint64) + 991);
		const attacker = reachable(seed, withMods);
		const defender = reachable(splitmix(seed), withMods);
		const simulated = attacker.winChanceAgainst(defender, seed, RUNS);
		const key = attacker.oddsKeyAgainst(defender);
		const cell = oddsCellBps(key.nearestColumn(), key.pace);
		const blended = key.winChanceBps();
		insert(nearest, Math.max(cell - simulated, simulated - cell));
		insert(interpolated, Math.max(blended - simulated, simulated - blended));
	}
	report(`${label} nearest     `, nearest);
	report(`${label} interpolated`, interpolated);
}

function main(): int32 {
	measure("no mods  ", false);
	measure("with mods", true);
	return 0;
}
process.exit(main());
