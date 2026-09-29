import * as arithmetic from "./arithmetic";
import { BPS } from "./units";
import { splitmix } from "./rng";

export const TALENT_LEVEL: int32 = 10;
export const COMMON_UNTIL_BPS: int32 = 6000;
export const RARE_UNTIL_BPS: int32 = 8800;
export const EPIC_UNTIL_BPS: int32 = 9800;
export const LEGENDARY_UNTIL_BPS: int32 = 9980;
export const GRADE_SPREAD_BPS: int32 = 1000;
export const LINEAGE_NUDGE_BPS: int32 = 500;
export const LINEAGE_NUDGE_CAP_BPS: int32 = 2500;

export enum TalentKind {
	None,
	Forage,
	Might,
	Grit,
}

export enum TalentGrade {
	Common,
	Rare,
	Epic,
	Legendary,
	Mythic,
}

export struct Talent {
	kind: TalentKind;
	multiplierBps: int32;
}

export function gradeOf(rollBps: int32): TalentGrade {
	if (rollBps < COMMON_UNTIL_BPS) { return TalentGrade.Common; }
	if (rollBps < RARE_UNTIL_BPS) { return TalentGrade.Rare; }
	if (rollBps < EPIC_UNTIL_BPS) { return TalentGrade.Epic; }
	if (rollBps < LEGENDARY_UNTIL_BPS) { return TalentGrade.Legendary; }
	return TalentGrade.Mythic;
}

export function multiplierOf(grade: TalentGrade, spreadBps: int32): int32 {
	return match (grade) {
		TalentGrade.Common => BPS + spreadBps,
		TalentGrade.Rare => 11000 + spreadBps,
		TalentGrade.Epic => 13000 + spreadBps,
		TalentGrade.Legendary => 16000,
		TalentGrade.Mythic => 20000,
	};
}

export function lineageNudgeBps(generation: int32): int32 {
	return Math.min(generation * LINEAGE_NUDGE_BPS, LINEAGE_NUDGE_CAP_BPS);
}

export function nudgedRoll(rollBps: int32, nudgeBps: int32): int32 {
	return BPS - (BPS - rollBps) * BPS / (BPS + nudgeBps);
}

export function rolled(this typeof Talent, randomness: uint64, nudgeBps: int32): Talent {
	const first = splitmix(randomness);
	const second = splitmix(first);
	const kind = (1 + (first % 3) as int32) as TalentKind;
	const roll = ((second >> 16) % (BPS as uint64)) as int32;
	const grade = gradeOf(nudgedRoll(roll, nudgeBps));
	const spread = ((second >> 40) % ((GRADE_SPREAD_BPS + 1) as uint64)) as int32;
	return { kind: kind, multiplierBps: multiplierOf(grade, spread) };
}

export function unrevealed(this typeof Talent): Talent {
	return { kind: TalentKind.None, multiplierBps: BPS };
}

test "grades follow the brief's odds" {
	assert gradeOf(0) == TalentGrade.Common;
	assert gradeOf(5999) == TalentGrade.Common;
	assert gradeOf(6000) == TalentGrade.Rare;
	assert gradeOf(9799) == TalentGrade.Epic;
	assert gradeOf(9800) == TalentGrade.Legendary;
	assert gradeOf(9980) == TalentGrade.Mythic;
	assert multiplierOf(TalentGrade.Common, 0) == BPS;
	assert multiplierOf(TalentGrade.Epic, GRADE_SPREAD_BPS) == 14000;
	assert multiplierOf(TalentGrade.Mythic, 7) == 20000;
}

test "rolled talents cover every kind and stay inside the grade ranges" {
	let seen = 0;
	let common = 0;
	for (let seed: uint64 = 1; seed <= 2000; seed++) {
		const talent = Talent.rolled(seed, 0);
		assert talent.kind != TalentKind.None;
		assert talent.multiplierBps >= BPS && talent.multiplierBps <= 20000;
		seen = seen | (1 << (talent.kind as int32));
		if (talent.multiplierBps <= 11000) { common += 1; }
	}
	assert seen == 14;
	assert common > 1000 && common < 1400;
}

test "a later generation rolls the rarer grades a little more often" {
	assert nudgedRoll(0, 0) == 0 && nudgedRoll(9999, 0) == 9999;
	assert nudgedRoll(5000, 2500) == 6000;
	assert lineageNudgeBps(1) == LINEAGE_NUDGE_BPS;
	assert lineageNudgeBps(9) == LINEAGE_NUDGE_CAP_BPS;
	let first = 0;
	let fifth = 0;
	for (let seed: uint64 = 1; seed <= 4000; seed++) {
		if (Talent.rolled(seed, 0).multiplierBps > 12000) { first += 1; }
		if (Talent.rolled(seed, lineageNudgeBps(5)).multiplierBps > 12000) { fifth += 1; }
	}
	assert fifth > first;
	assert fifth * 100 < first * 140;
}
