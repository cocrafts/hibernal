import { BPS } from "./units";
import { Talent, TalentKind } from "./talent";

export const BASE_STAT: int32 = 50;
export const BASE_SPEED: int32 = 50;
export const START_BONUS: int32 = 30;
export const BASE_MAX_HEARTS: int32 = 10;
export const LEVEL_STAT_GROWTH: int32 = 5;
export const LEVELS_PER_HEART: int32 = 2;
export const REWARD_WEIGHT_OFFSET: uint64 = 40;

export enum Region {
	Worker,
	Fighter,
	Survivor,
}

export enum Mod {
	Overtime,
	Scavenger,
	ThickHide,
	Pacifist,
	GlassCannon,
	Cannibal,
	Relentless,
	Berserker,
}

export struct Stats {
	forage: int32;
	might: int32;
	grit: int32;
	speed: int32;
	armor: int32;
	accuracy: int32;
	lifesteal: int32;
	bleed: int32;
	maxHearts: int32;
	foodBps: int32;
	experienceBps: int32;
	lootBps: int32;
	biteGuardBps: int32;
	mods: BitSet<Mod>;
}

export struct Combatant {
	might: int32;
	grit: int32;
	speed: int32;
	armor: int32;
	accuracy: int32;
	lifesteal: int32;
	bleed: int32;
	hearts: int32;
	mods: BitSet<Mod>;
}

export function noMods(): BitSet<Mod> {
	let empty: BitSet<Mod>;
	return empty;
}

export function modsFromMask(mask: int32): BitSet<Mod> {
	return (mask as uint8) as BitSet<Mod>;
}

export function base(this typeof Stats): Stats {
	return {
		forage: BASE_STAT,
		might: BASE_STAT,
		grit: BASE_STAT,
		speed: BASE_SPEED,
		armor: 0,
		accuracy: 0,
		lifesteal: 0,
		bleed: 0,
		maxHearts: BASE_MAX_HEARTS,
		foodBps: 0,
		experienceBps: 0,
		lootBps: 0,
		biteGuardBps: 0,
		mods: noMods(),
	};
}

export function workPower(this stats: Stats): uint64 {
	return (10 + stats.forage * 3 / 10) as uint64;
}

export function rewardWeight(this stats: Stats): uint64 {
	const shifted = stats.workPower() + REWARD_WEIGHT_OFFSET;
	return shifted * shifted;
}

function faded(value: int32, vigorBps: int32): int32 {
	return BASE_STAT + (value - BASE_STAT) * vigorBps / BPS;
}

function talentScaled(value: int32, talent: Talent, kind: TalentKind): int32 {
	if (talent.kind != kind) { return value; }
	return ((value as int64) * (talent.multiplierBps as int64) / (BPS as int64)) as int32;
}

export function talented(this stats: Stats, talent: Talent): Stats {
	return {
		...stats,
		forage: talentScaled(stats.forage, talent, TalentKind.Forage),
		might: talentScaled(stats.might, talent, TalentKind.Might),
		grit: talentScaled(stats.grit, talent, TalentKind.Grit),
	};
}

export function grown(this stats: Stats, level: int32): Stats {
	const growth = Math.max(level - 1, 0) * LEVEL_STAT_GROWTH;
	return {
		...stats,
		forage: stats.forage + growth,
		might: stats.might + growth,
		grit: stats.grit + growth,
		maxHearts: stats.maxHearts + level / LEVELS_PER_HEART,
	};
}

export function aged(this stats: Stats, vigorBps: int32): Stats {
	return {
		...stats,
		forage: faded(stats.forage, vigorBps),
		might: faded(stats.might, vigorBps),
		grit: faded(stats.grit, vigorBps),
	};
}

export function power(this stats: Stats): int32 {
	return stats.forage + stats.might + stats.grit;
}

export function berserkBps(this stats: Stats, hearts: int32): int32 {
	if (!stats.mods.has(Mod.Berserker) || stats.maxHearts <= 0) { return 0; }
	return Math.max(stats.maxHearts - hearts, 0) * BPS / stats.maxHearts;
}

export function asCombatant(this stats: Stats, hearts: int32): Combatant {
	return {
		might: stats.might * (BPS + stats.berserkBps(hearts)) / BPS,
		grit: stats.grit,
		speed: stats.speed,
		armor: stats.armor,
		accuracy: stats.accuracy,
		lifesteal: stats.lifesteal,
		bleed: stats.bleed,
		hearts: hearts,
		mods: stats.mods,
	};
}

export function plain(this typeof Combatant, might: int32, grit: int32, hearts: int32): Combatant {
	return { ...Stats.base().asCombatant(hearts), might: might, grit: grit };
}

test "workPower base is 25 at forage 50" {
	const base = Stats.base();
	const worker: Stats = { ...base, forage: base.forage + START_BONUS };
	assert base.workPower() == 25;
	assert worker.workPower() == 34;
	assert worker.rewardWeight() == (34 + REWARD_WEIGHT_OFFSET) * (34 + REWARD_WEIGHT_OFFSET);
	assert Stats.base().asCombatant(3).hearts == 3;
	assert Combatant.plain(80, 60, 5).speed == BASE_SPEED;
}

test "age fades what the tree gave and keeps the base" {
	const grown: Stats = { ...Stats.base(), forage: 150, might: 90, grit: 51 };
	const old = grown.aged(5000);
	assert old.forage == 100;
	assert old.might == 70;
	assert old.grit == 50;
	assert grown.aged(BPS).forage == 150 && grown.aged(BPS).might == 90;
}

test "a berserker hits harder the fewer hearts it has left" {
	const berserker: Stats = { ...Stats.base(), maxHearts: 20, mods: noMods().incl(Mod.Berserker) };
	assert berserker.asCombatant(20).might == BASE_STAT;
	assert berserker.asCombatant(10).might == BASE_STAT * 3 / 2;
	assert berserker.asCombatant(0).might == BASE_STAT * 2;
	assert Stats.base().asCombatant(1).might == BASE_STAT;
}

test "mods round-trip through a mask" {
	const mods = modsFromMask(2 | 16);
	assert mods.has(Mod.Scavenger);
	assert mods.has(Mod.GlassCannon);
	assert !mods.has(Mod.Overtime);
	assert (mods as uint32) == 18;
	assert noMods().isEmpty();
	assert Stats.base().power() == 150;
}
