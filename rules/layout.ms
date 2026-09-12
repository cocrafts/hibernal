export const EPOCH_SECONDS: uint64 = 86400;
export const HBRN_UNIT: uint64 = 1000000;
export const NEWBORN_EPOCHS: uint64 = 3;
export const GRACE_EPOCHS: uint64 = 7;
export const BLOCK_SLOTS: int32 = 10;
export const FIGHT_RING: int32 = 32;
export const TREE_NODES: int32 = 24;

export const BASE_STAT: int32 = 5;
export const START_BONUS: int32 = 3;
export const BASE_MAX_HEARTS: int32 = 5;
export const GROWTH_CAP_BPS: int32 = 12000;
export const BPS: int32 = 10000;

export const INCOMING_CAP: int32 = 3;
export const BITES_CAP: int32 = 1;

export enum Region { Worker = 0, Fighter = 1, Survivor = 2 }
export enum Insurance { None = 0, Armed = 1, Used = 2 }
export enum Outcome { DefenderWins = 0, AttackerWins = 1 }

export const MOD_OVERTIME: int32 = 1;
export const MOD_SCAVENGER: int32 = 2;
export const MOD_THICK_HIDE: int32 = 4;
export const MOD_PACIFIST: int32 = 8;
export const MOD_GLASS_CANNON: int32 = 16;
export const MOD_CANNIBAL: int32 = 32;

export struct Stats {
	yield_: int32;
	might: int32;
	grit: int32;
	maxHearts: int32;
	mods: int32;
}

export struct Combatant {
	might: int32;
	grit: int32;
	hearts: int32;
	mods: int32;
}

export struct FightResult {
	outcome: int32;
	rounds: int32;
	hpA: int32;
	hpD: int32;
}

export struct FightRecord {
	epoch: uint64;
	seed: uint64;
	attackerSlot: int32;
	defenderSlot: int32;
	a: Combatant;
	d: Combatant;
	stake: uint64;
	loot: uint64;
	outcome: int32;
	rounds: int32;
}

export struct Pet {
	blockId: uint32;
	slot: uint8;
	alive: boolean;
	region: uint8;
	hearts: uint8;
	maxHearts: uint8;
	yield_: uint16;
	might: uint16;
	grit: uint16;
	level: uint16;
	pointsUnspent: uint8;
	treeBitmap: uint64;
	harvest: uint64;
	burrow: uint64;
	accSnapshot: uint64;
	bornEpoch: uint64;
	lastTickEpoch: uint64;
	fightsOutToday: uint8;
	fightsInToday: uint8;
	bitesInToday: uint8;
	fightDay: uint64;
	growthMultBps: uint16;
	growthMultExpiry: uint64;
	minHearts: uint8;
	insurance: uint8;
	scars: uint8;
	lineageGen: uint16;
}

export struct GlobalConfig {
	genesisTs: uint64;
	accRewardPerWp: uint64;
	accEpoch: uint64;
	totalWorkPower: uint64;
	recycledPending: uint64;
	protocolPending: uint64;
	burned: uint64;
}

export function workPower(yield_: int32): uint64 {
	return (10 + yield_ * 3) as uint64;
}

export function power(s: Stats): int32 {
	return s.yield_ + s.might + s.grit;
}

export function combatantOf(s: Stats, hearts: int32): Combatant {
	const c: Combatant = { might: s.might, grit: s.grit, hearts: hearts, mods: s.mods };
	return c;
}

test "workPower base is 25 at yield 5" {
	assert workPower(BASE_STAT) == 25;
	assert workPower(BASE_STAT + START_BONUS) == 34;
}
