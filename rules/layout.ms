import { BPS } from "./units";
import { Region, Stats, Combatant } from "./stats";
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
	blockId: uint32;
	slot: uint8;
	alive: boolean;
	region: uint8;
	hearts: uint8;
	maxHearts: uint8;
	forage: uint16;
	might: uint16;
	grit: uint16;
	level: uint16;
	pointsUnspent: uint8;
	xp: uint32;
	tree: Tree;
	harvest: uint64;
	burrow: uint64;
	rewardSnapshot: uint64;
	bornEpoch: uint64;
	lastTickEpoch: uint64;
	fightsOutToday: uint8;
	fightsInToday: uint8;
	bitesInToday: uint8;
	slotsAttackedToday: BitSet<BlockSlot>;
	fightDay: uint64;
	growthMultiplierBps: uint16;
	growthMultiplierExpiry: uint64;
	minHearts: uint8;
	pantry: Pantry;
	foodBoughtToday: uint8;
	talentKind: uint8;
	talentBps: uint16;
	insurance: uint8;
	scars: uint8;
	lineageGeneration: uint16;
	bonding: int8;
	talksToday: uint8;
	ownerFedToday: uint8;
	giftOwed: uint64;
	gear: Gear;
	grudgeSlot: uint8;
	rage: uint8;
	rageEpoch: uint64;
}

export struct GlobalConfig {
	genesisTimestamp: uint64;
	rewardPerWorkPower: uint64;
	rewardEpoch: uint64;
	totalWorkPower: uint64;
	recycledPending: uint64;
	protocolPending: uint64;
	burned: uint64;
}

export struct FightRecord {
	epoch: uint64;
	seed: uint64;
	attackerSlot: int32;
	defenderSlot: int32;
	attacker: Combatant;
	defender: Combatant;
	stake: uint64;
	loot: uint64;
	outcome: Outcome;
	rounds: int32;
}

export function stats(this pet: Pet): Stats {
	const gear = pet.gear;
	return {
		...Stats.built(pet.tree, pet.level as int32, pet.talent()),
		forage: geared(pet.forage, gear.statBonusBps(TalentKind.Forage)),
		might: geared(pet.might, gear.statBonusBps(TalentKind.Might)),
		grit: geared(pet.grit, gear.statBonusBps(TalentKind.Grit)),
		maxHearts: pet.maxHearts as int32,
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
	const base = pet.combatant();
	if (pet.rage == 0 || pet.grudgeSlot != opponent.slot) { return base; }
	const bps = BPS + (pet.rage as int32) * RAGE_STEP_BPS;
	return { ...base, might: base.might * bps / BPS, grit: base.grit * bps / BPS };
}

export function robbedBy(this pet: Pet, robber: Pet, epoch: uint64): Pet {
	if (pet.rage > 0 && pet.grudgeSlot == robber.slot) {
		return { ...pet, rage: Math.min((pet.rage as int32) + 1, RAGE_MAX) as uint8, rageEpoch: epoch };
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
