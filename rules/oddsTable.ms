import * as arithmetic from "./arithmetic";
import { BPS } from "./units";
import { Combatant, Mod, modsFromMask } from "./stats";
import { splitmix } from "./rng";
import {
	DAMAGE,
	ROLL_MIN,
	ROLL_MAX,
	ARMOR_PERCENT,
	MIN_DAMAGE_PERCENT,
	CRIT_DAMAGE_PERCENT,
	LIFESTEAL_BPS_PER_POINT,
	BLEED_BPS_PER_POINT,
	fightHp,
	dodgePercent,
	critPercent,
	hastePercent,
} from "./fight";
import { winChanceAgainst } from "./winOdds";
import { LOG2_ONE, log2Times32 } from "./logarithm";
import { oddsTableColumn } from "./oddsTableColumns";

export const ODDS_RATIO_COLUMNS: int32 = 41;
export const ODDS_PACE_ROWS: int32 = 8;
export const ODDS_RATIO_STEP: int32 = LOG2_ONE / 8;
export const ODDS_RATIO_SPAN: int32 = (ODDS_RATIO_COLUMNS - 1) * ODDS_RATIO_STEP;
export const ODDS_PACE_STEP: int32 = LOG2_ONE / 2;
export const ODDS_PACE_FLOOR: int32 = 21 * ODDS_PACE_STEP;
export const ODDS_CELL_BPS: int32 = 50;

export struct OddsKey {
	ratio: int32;
	pace: int32;
}

export function expectedStrike(this striker: Combatant, target: Combatant): int32 {
	const rolled = striker.might * DAMAGE * (ROLL_MIN + ROLL_MAX) / 200;
	const raw = striker.mods.has(Mod.GlassCannon) ? rolled * 2 : rolled;
	const floor = raw * MIN_DAMAGE_PERCENT / 100;
	const armored = Math.max(raw - target.armor * ARMOR_PERCENT / 100, floor);
	const crit = striker.critPercent(target);
	const hit = (armored * (100 - crit) + raw * CRIT_DAMAGE_PERCENT / 100 * crit) / 100;
	const landed = hit * (100 - target.dodgePercent(striker)) / 100;
	const hasted = landed * (100 + striker.hastePercent(target)) / 100;
	return hasted * (BPS + striker.bleed * BLEED_BPS_PER_POINT) / BPS;
}

function healOf(this striker: Combatant, strike: int32): int32 {
	return strike * striker.lifesteal * LIFESTEAL_BPS_PER_POINT / BPS;
}

export function expectedHeal(this striker: Combatant, target: Combatant): int32 {
	return striker.healOf(striker.expectedStrike(target));
}

function netPressureBps(strike: int32, heal: int32, targetHp: int32): int32 {
	const net = Math.max(strike - heal, 1);
	return Math.max(net * BPS / targetHp, 1);
}

export function pressureBps(this striker: Combatant, target: Combatant): int32 {
	return netPressureBps(striker.expectedStrike(target), target.expectedHeal(striker), target.fightHp());
}

function clampInt32(value: int32, low: int32, high: int32): int32 {
	return Math.max(low, Math.min(value, high));
}

export function oddsKeyAgainst(this attacker: Combatant, defender: Combatant): OddsKey {
	const attackerStrike = attacker.expectedStrike(defender);
	const defenderStrike = defender.expectedStrike(attacker);
	return keyOf(
		netPressureBps(attackerStrike, defender.healOf(defenderStrike), defender.fightHp()),
		netPressureBps(defenderStrike, attacker.healOf(attackerStrike), attacker.fightHp()),
	);
}

function keyOf(attackerPressure: int32, defenderPressure: int32): OddsKey {
	const scaled = ((attackerPressure as uint64) << 16) / (defenderPressure as uint64);
	const ratio = log2Times32(scaled) - 16 * LOG2_ONE + ODDS_RATIO_SPAN / 2;
	const pace = log2Times32((attackerPressure + defenderPressure) as uint64) - ODDS_PACE_FLOOR;
	return {
		ratio: clampInt32(ratio, 0, ODDS_RATIO_SPAN),
		pace: clampInt32(pace, 0, ODDS_PACE_ROWS * ODDS_PACE_STEP - 1) / ODDS_PACE_STEP,
	};
}

export function nearestColumn(this key: OddsKey): int32 {
	return (key.ratio + ODDS_RATIO_STEP / 2) / ODDS_RATIO_STEP;
}

export function oddsCellBps(column: int32, pace: int32): int32 {
	const cell = (oddsTableColumn(column) >> ((pace * 8) as uint64)) & 0xff;
	return (cell as int32) * ODDS_CELL_BPS;
}

export function winChanceBps(this key: OddsKey): int32 {
	const column = key.ratio / ODDS_RATIO_STEP;
	const along = key.ratio % ODDS_RATIO_STEP;
	const here = oddsCellBps(column, key.pace);
	if (along == 0) { return here; }
	const next = oddsCellBps(column + 1, key.pace);
	return (here * (ODDS_RATIO_STEP - along) + next * along) / ODDS_RATIO_STEP;
}

export function winChanceFromTable(this attacker: Combatant, defender: Combatant): int32 {
	return attacker.oddsKeyAgainst(defender).winChanceBps();
}

function reachable(seed: uint64): Combatant {
	return {
		...Combatant.plain(
			50 + (((seed >> 8) % 8) as int32) * 10,
			50 + (((seed >> 16) % 9) as int32) * 10,
			1 + ((seed >> 24) % 5) as int32,
		),
		mods: modsFromMask((((seed >> 32) % 64) & ((seed >> 40) % 64)) as int32),
	};
}

test "pressure follows might, grit and glass cannon" {
	const plain = Combatant.plain(80, 60, 5);
	const strong = Combatant.plain(120, 60, 5);
	const tough = Combatant.plain(80, 120, 5);
	const glass: Combatant = { ...plain, mods: (0 as BitSet<Mod>).incl(Mod.GlassCannon) };
	assert strong.pressureBps(plain) > plain.pressureBps(plain);
	assert plain.pressureBps(tough) < plain.pressureBps(plain);
	assert glass.pressureBps(plain) > plain.pressureBps(plain);
	assert plain.pressureBps(glass) > plain.pressureBps(plain);
}

test "the key is centred on even pressure and clamps at the edges" {
	const plain = Combatant.plain(80, 60, 5);
	const even = plain.oddsKeyAgainst(plain);
	assert even.ratio == ODDS_RATIO_SPAN / 2;
	assert even.pace >= 0 && even.pace < ODDS_PACE_ROWS;
	const crushed = Combatant.plain(1, 50, 5).oddsKeyAgainst(Combatant.plain(200, 200, 5));
	assert crushed.ratio == 0;
	const crushing = Combatant.plain(200, 200, 5).oddsKeyAgainst(Combatant.plain(1, 50, 5));
	assert crushing.ratio == ODDS_RATIO_SPAN;
	assert crushing.nearestColumn() == ODDS_RATIO_COLUMNS - 1;
}

test "the key reads each side's pressure, lifesteal and bleed included" {
	for (let index = 0; index < 200; index++) {
		const seed = splitmix((index as uint64) + 77);
		const attacker: Combatant = { ...reachable(seed), lifesteal: ((seed >> 48) % 4) as int32 };
		const target: Combatant = {
			...reachable(splitmix(seed)),
			lifesteal: ((seed >> 52) % 4) as int32,
			bleed: ((seed >> 56) % 3) as int32,
		};
		const expected = keyOf(attacker.pressureBps(target), target.pressureBps(attacker));
		assert attacker.oddsKeyAgainst(target) == expected;
	}
}

test "the table rises with the pressure ratio and stays close to simulated odds" {
	const defender = Combatant.plain(80, 60, 5);
	const weaker = Combatant.plain(50, 60, 5).winChanceFromTable(defender);
	const equal = Combatant.plain(80, 60, 5).winChanceFromTable(defender);
	const stronger = Combatant.plain(120, 60, 5).winChanceFromTable(defender);
	assert weaker < equal;
	assert equal < stronger;
	let totalError = 0;
	const pairs = 60;
	for (let index = 0; index < pairs; index++) {
		const seed = splitmix((index as uint64) + 4242);
		const attacker = reachable(seed);
		const target = reachable(splitmix(seed));
		const simulated = attacker.winChanceAgainst(target, seed, 1000);
		const tabled = attacker.winChanceFromTable(target);
		totalError += Math.max(tabled - simulated, simulated - tabled);
	}
	assert totalError / pairs < 300;
}
