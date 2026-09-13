import { Stats, Combatant } from "./stats";
import { Tree } from "./tree";
import { Outcome } from "./fight";
import { isShielded } from "./emission";

export const GRACE_EPOCHS: uint64 = 7;
export const BLOCK_SLOTS: int32 = 10;
export const FIGHT_RING: int32 = 32;

export enum Insurance {
	None,
	Armed,
	Used,
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
	tree: Tree;
	harvest: uint64;
	burrow: uint64;
	rewardSnapshot: uint64;
	bornEpoch: uint64;
	lastTickEpoch: uint64;
	fightsOutToday: uint8;
	fightsInToday: uint8;
	bitesInToday: uint8;
	fightDay: uint64;
	growthMultiplierBps: uint16;
	growthMultiplierExpiry: uint64;
	minHearts: uint8;
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
		...Stats.fromTree(pet.tree),
		forage: pet.forage as int32,
		might: pet.might as int32,
		grit: pet.grit as int32,
		maxHearts: pet.maxHearts as int32,
	};
}

export function combatant(this pet: Pet): Combatant {
	return pet.stats().asCombatant(pet.hearts as int32);
}

export function fightsOutOn(this pet: Pet, epoch: uint64): int32 {
	return pet.fightDay == epoch ? pet.fightsOutToday as int32 : 0;
}

export function fightsInOn(this pet: Pet, epoch: uint64): int32 {
	return pet.fightDay == epoch ? pet.fightsInToday as int32 : 0;
}

export function shieldedAt(this pet: Pet, epoch: uint64): boolean {
	return isShielded(epoch, pet.bornEpoch);
}
