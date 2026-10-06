import * as arithmetic from "./arithmetic";
import { BPS } from "./units";
import { Mod, Region, Stats, Combatant } from "./stats";
import { Tree, built } from "./tree";
import { Outcome, RAGE_STEP_BPS, RAGE_MAX, RAGE_DAYS } from "./fight";
import { isShielded } from "./emission";
import { Pantry } from "./pantry";
import { Talent, TalentKind } from "./talent";
import { Gear, statBonusBps } from "./items";

export const GRACE_EPOCHS: uint64 = 7;
export const BLOCK_SLOTS: int32 = 10;
export const FIGHT_RING: int32 = 32;

export enum Insurance {
	None,
	Armed,
	Used,
}

export enum BlockSlot {
	First,
	Second,
	Third,
	Fourth,
	Fifth,
	Sixth,
	Seventh,
	Eighth,
	Ninth,
	Tenth,
}

export struct Pet {
	tree: Tree;
	harvest: uint64;
	burrow: uint64;
	rewardSnapshot: uint64;
	bornEpoch: uint64;
	lastTickEpoch: uint64;
	fightDay: uint64;
	growthMultiplierExpiry: uint64;
	giftOwed: uint64;
	ownerBankedAt: uint64;
	rageEpoch: uint64;
	blockId: uint32;
	xp: uint32;
	foodBps: int32;
	experienceBps: int32;
	lootBps: int32;
	biteGuardBps: int32;
	forage: uint16;
	might: uint16;
	grit: uint16;
	level: uint16;
	slotsAttackedToday: BitSet<BlockSlot>;
	growthMultiplierBps: uint16;
	talentBps: uint16;
	lineageGeneration: uint16;
	slot: uint8;
	alive: boolean;
	region: uint8;
	hearts: uint8;
	maxHearts: uint8;
	pointsUnspent: uint8;
	mods: BitSet<Mod>;
	fightsOutToday: uint8;
	fightsInToday: uint8;
	bitesInToday: uint8;
	minHearts: uint8;
	pantry: Pantry;
	foodBoughtToday: uint8;
	talentKind: uint8;
	insurance: uint8;
	scars: uint8;
	bonding: int8;
	engagedToday: uint8;
	ownerFedToday: uint8;
	gear: Gear;
	grudgeSlot: uint8;
	rage: uint8;
	ownerFirst: uint8;
	ownerSecond: uint8;
	skin: uint8;
	wild: boolean;
	engagedRound: uint8;
}

export struct GlobalConfig {
	genesisTimestamp: uint64;
	rewardPerWorkPower: uint64;
	rewardEpoch: uint64;
	totalWorkPower: uint64;
	recycledPending: uint64;
	treasury: uint64;
	itemReserve: uint64;
	emitted: uint64;
	livingPets: uint32;
	floorSlots: uint32;
}

export struct FightRecord {
	epoch: uint64;
	seed: uint64;
	stake: uint64;
	loot: uint64;
	attackerSlot: int32;
	defenderSlot: int32;
	rounds: int32;
	attacker: Combatant;
	defender: Combatant;
	outcome: uint8;
	pad: uint8;
	pad2: uint16;
}

export function ownStats(this pet: Pet): Stats {
	return {
		...Stats.base(),
		forage: pet.forage as int32,
		might: pet.might as int32,
		grit: pet.grit as int32,
		maxHearts: pet.maxHearts as int32,
		foodBps: pet.foodBps,
		experienceBps: pet.experienceBps,
		lootBps: pet.lootBps,
		biteGuardBps: pet.biteGuardBps,
		mods: pet.mods,
	};
}

export function withTreeBonuses(this pet: Pet, built: Stats): Pet {
	return {
		...pet,
		foodBps: built.foodBps,
		experienceBps: built.experienceBps,
		lootBps: built.lootBps,
		biteGuardBps: built.biteGuardBps,
		mods: built.mods,
	};
}

export function withTree(this pet: Pet, tree: Tree): Pet {
	const planted: Pet = { ...pet, tree: tree };
	return planted.withTreeBonuses(Stats.built(tree, pet.level as int32, pet.talent()));
}

export function growthBoosted(this pet: Pet): boolean {
	return pet.lastTickEpoch + 1 == pet.growthMultiplierExpiry;
}

export function growthBonusBps(this pet: Pet): int32 {
	return pet.growthBoosted() ? (pet.growthMultiplierBps as int32) - BPS : 0;
}

export function stats(this pet: Pet): Stats {
	const gear = pet.gear;
	return {
		...pet.ownStats(),
		forage: geared(pet.forage, gear.statBonusBps(TalentKind.Forage) + pet.growthBonusBps()),
		might: geared(pet.might, gear.statBonusBps(TalentKind.Might)),
		grit: geared(pet.grit, gear.statBonusBps(TalentKind.Grit)),
	};
}

function geared(value: uint16, bonusBps: int32): int32 {
	return (value as int32) * (BPS + bonusBps) / BPS;
}

export function talent(this pet: Pet): Talent {
	return {
		kind: (pet.talentKind as int32) as TalentKind,
		multiplierBps: pet.talentBps as int32,
	};
}

export function combatant(this pet: Pet): Combatant {
	return pet.stats().asCombatant(pet.hearts as int32);
}

export function combatantFacing(this pet: Pet, opponent: Pet): Combatant {
	return pet.enragedAgainst(pet.combatant(), opponent);
}

export function enragedAgainst(this pet: Pet, own: Combatant, opponent: Pet): Combatant {
	if (pet.rage == 0 || pet.grudgeSlot != opponent.slot) { return own; }
	const bps = BPS + (pet.rage as int32) * RAGE_STEP_BPS;
	return { ...own, might: own.might * bps / BPS, grit: own.grit * bps / BPS };
}

export function robbedBy(this pet: Pet, robber: Pet, epoch: uint64): Pet {
	if (pet.rage > 0 && pet.grudgeSlot == robber.slot) {
		const rage = Math.min((pet.rage as int32) + 1, RAGE_MAX);
		return { ...pet, rage: rage as uint8, rageEpoch: epoch };
	}
	return { ...pet, grudgeSlot: robber.slot, rage: 1, rageEpoch: epoch };
}

export function rageAt(this pet: Pet, epoch: uint64): uint8 {
	return epoch >= pet.rageEpoch + RAGE_DAYS ? 0 : pet.rage;
}

export function calmedAgainst(this pet: Pet, foe: Pet): Pet {
	if (pet.grudgeSlot != foe.slot) { return pet; }
	return { ...pet, rage: 0 };
}

export function wallet(this pet: Pet): uint64 {
	return pet.harvest + pet.burrow;
}

export function charged(this pet: Pet, amount: uint64): Pet {
	const fromHarvest = Math.min(pet.harvest, amount);
	return { ...pet, harvest: pet.harvest - fromHarvest, burrow: pet.burrow - (amount - fromHarvest) };
}

export function fightOutcome(this record: FightRecord): Outcome {
	return (record.outcome as int32) as Outcome;
}

export function startRegion(this pet: Pet): Region {
	return (pet.region as int32) as Region;
}

export function blockSlot(this pet: Pet): BlockSlot {
	return (pet.slot as int32) as BlockSlot;
}

export function fightsOutOn(this pet: Pet, epoch: uint64): int32 {
	return pet.fightDay == epoch ? pet.fightsOutToday as int32 : 0;
}

export function fightsInOn(this pet: Pet, epoch: uint64): int32 {
	return pet.fightDay == epoch ? pet.fightsInToday as int32 : 0;
}

export function attackedOn(this pet: Pet, target: BlockSlot, epoch: uint64): boolean {
	return pet.fightDay == epoch && pet.slotsAttackedToday.has(target);
}

export function onFightDay(this pet: Pet, epoch: uint64): Pet {
	if (pet.fightDay == epoch) { return pet; }
	return {
		...pet,
		fightDay: epoch,
		fightsOutToday: 0,
		fightsInToday: 0,
		bitesInToday: 0,
		slotsAttackedToday: 0 as BitSet<BlockSlot>,
	};
}

export function shieldedAt(this pet: Pet, epoch: uint64): boolean {
	return isShielded(epoch, pet.bornEpoch);
}
