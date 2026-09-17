import {
	ODDS_RATIO_COLUMNS,
	ODDS_PACE_ROWS,
	ODDS_CELL_BPS,
	Combatant,
	splitmix,
	modsFromMask,
	winChanceAgainst,
	oddsKeyAgainst,
	nearestColumn,
} from "../rules/index";

const SAMPLES: int32 = 400000;
const RUNS_PER_SAMPLE: int32 = 200;
const MIGHT_STEPS: uint64 = 16;
const GRIT_STEPS: uint64 = 16;

function sampled(seed: uint64): Combatant {
	return {
		...Combatant.plain(
			50 + (((seed >> 8) % MIGHT_STEPS) as int32) * 10,
			50 + (((seed >> 16) % GRIT_STEPS) as int32) * 10,
			1 + ((seed >> 24) % 8) as int32,
		),
		mods: modsFromMask((((seed >> 32) % 64) & ((seed >> 40) % 64)) as int32),
	};
}

function hexByte(value: int32): string {
	const digits = "0123456789abcdef";
	const high = value / 16;
	const low = value % 16;
	return digits.slice(high, high + 1) + digits.slice(low, low + 1);
}

function nearestFilled(counts: int32[], column: int32, pace: int32): int32 {
	for (let distance = 0; distance < ODDS_RATIO_COLUMNS + ODDS_PACE_ROWS; distance++) {
		for (let paceShift = 0; paceShift <= distance; paceShift++) {
			const columnShift = distance - paceShift;
			for (let sign = 0; sign < 4; sign++) {
				const otherColumn = column + (sign % 2 == 0 ? columnShift : -columnShift);
				const otherPace = pace + (sign < 2 ? paceShift : -paceShift);
				if (otherColumn < 0 || otherColumn >= ODDS_RATIO_COLUMNS) { continue; }
				if (otherPace < 0 || otherPace >= ODDS_PACE_ROWS) { continue; }
				if (counts[otherColumn * ODDS_PACE_ROWS + otherPace] > 0) {
					return otherColumn * ODDS_PACE_ROWS + otherPace;
				}
			}
		}
	}
	return column * ODDS_PACE_ROWS + pace;
}

function main(): int32 {
	const totals: uint64[] = [];
	const counts: int32[] = [];
	for (let cell = 0; cell < ODDS_RATIO_COLUMNS * ODDS_PACE_ROWS; cell++) {
		totals.push(0);
		counts.push(0);
	}
	for (let sample = 0; sample < SAMPLES; sample++) {
		const seed = splitmix((sample as uint64) + 0x0dd5);
		const attacker = sampled(seed);
		const defender = sampled(splitmix(seed));
		const key = attacker.oddsKeyAgainst(defender);
		const cell = key.nearestColumn() * ODDS_PACE_ROWS + key.pace;
		totals[cell] += attacker.winChanceAgainst(defender, seed, RUNS_PER_SAMPLE) as uint64;
		counts[cell] += 1;
	}
	console.log("export function oddsTableColumn(column: int32): uint64 {");
	console.log("\treturn match (column) {");
	for (let column = 0; column < ODDS_RATIO_COLUMNS; column++) {
		let word = "";
		for (let pace = ODDS_PACE_ROWS - 1; pace >= 0; pace--) {
			const source = nearestFilled(counts, column, pace);
			const mean = (totals[source] / (counts[source] as uint64)) as int32;
			word += hexByte((mean + ODDS_CELL_BPS / 2) / ODDS_CELL_BPS);
		}
		console.log(`\t\t${column} => 0x${word},`);
	}
	console.log("\t\t_ => 0,");
	console.log("\t};");
	console.log("}");
	return 0;
}
process.exit(main());
