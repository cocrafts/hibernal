export const BASE_STAT: int32 = 5;
export const START_BONUS: int32 = 3;
export const BASE_MAX_HEARTS: int32 = 5;

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
}

export struct Stats {
	forage: int32;
	might: int32;
	grit: int32;
	maxHearts: int32;
	mods: BitSet<Mod>;
}

export struct Combatant {
	might: int32;
	grit: int32;
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
		maxHearts: BASE_MAX_HEARTS,
		mods: noMods(),
	};
}

export function workPower(this stats: Stats): uint64 {
	return (10 + stats.forage * 3) as uint64;
}

export function power(this stats: Stats): int32 {
	return stats.forage + stats.might + stats.grit;
}

export function asCombatant(this stats: Stats, hearts: int32): Combatant {
	return { might: stats.might, grit: stats.grit, hearts: hearts, mods: stats.mods };
}

export function plain(this typeof Combatant, might: int32, grit: int32, hearts: int32): Combatant {
	return { might: might, grit: grit, hearts: hearts, mods: noMods() };
}

test "workPower base is 25 at forage 5" {
	const base = Stats.base();
	const worker: Stats = { ...base, forage: base.forage + START_BONUS };
	assert base.workPower() == 25;
	assert worker.workPower() == 34;
	assert Stats.base().asCombatant(3).hearts == 3;
}

test "mods round-trip through a mask" {
	const mods = modsFromMask(2 | 16);
	assert mods.has(Mod.Scavenger);
	assert mods.has(Mod.GlassCannon);
	assert !mods.has(Mod.Overtime);
	assert (mods as uint32) == 18;
	assert noMods().isEmpty();
	assert Stats.base().power() == 15;
}
