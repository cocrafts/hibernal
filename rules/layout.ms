import { Region, Stats, Combatant } from "./stats";
import { Tree, built } from "./tree";
import { Outcome } from "./fight";
import { isShielded } from "./emission";
import { Pantry } from "./pantry";
import { Talent, TalentKind } from "./talent";

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
	return {
		...Stats.built(pet.tree, pet.level as int32, pet.talent()),
		forage: pet.forage as int32,
		might: pet.might as int32,
		grit: pet.grit as int32,
		maxHearts: pet.maxHearts as int32,
	};
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
