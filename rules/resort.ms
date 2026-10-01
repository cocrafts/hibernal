import { BlockSlot, GlobalConfig, Pet, stats } from "./layout";
import { Region } from "./stats";
import { born, genesis } from "./life";

export const RESORT_EPOCHS: uint64 = 7;
export const LEVEL_WEIGHT: uint64 = 10_000;

export enum StrengthMeasure {
	Level,
	Power,
	Combat,
}

export function strengthOf(this pet: Pet, measure: StrengthMeasure): uint64 {
	const geared = pet.stats();
	const power = (geared.forage + geared.might + geared.grit) as uint64;
	return match (measure) {
		StrengthMeasure.Level => (pet.level as uint64) * LEVEL_WEIGHT + power,
		StrengthMeasure.Power => power,
		StrengthMeasure.Combat => (geared.might + geared.grit) as uint64,
	};
}

export function resortsAt(epoch: uint64, every: uint64): boolean {
	return every > 0 && epoch > 0 && epoch % every == 0;
}

export function outranks(this pet: Pet, other: Pet, measure: StrengthMeasure): boolean {
	const own = pet.strengthOf(measure);
	const theirs = other.strengthOf(measure);
	if (own != theirs) { return own > theirs; }
	if (pet.blockId != other.blockId) { return pet.blockId < other.blockId; }
	return pet.slot < other.slot;
}

export function movedTo(this pet: Pet, blockId: uint32, slot: BlockSlot): Pet {
	return {
		...pet,
		blockId: blockId,
		slot: slot as uint8,
		grudgeSlot: 0,
		rage: 0,
		rageEpoch: 0,
		slotsAttackedToday: 0 as BitSet<BlockSlot>,
	};
}

function sample(level: uint16, might: uint16, forage: uint16, blockId: uint32, slot: uint8): Pet {
	const hatched = Pet.born(blockId, slot as BlockSlot, Region.Worker, 0, GlobalConfig.genesis(0));
	return { ...hatched.pet, level: level, might: might, forage: forage, grit: 50, grudgeSlot: 3, rage: 2, rageEpoch: 9 };
}

test "a stronger fighter outranks a richer forager in combat, not in power" {
	const fighter = sample(5, 200, 50, 0, 1);
	const forager = sample(5, 50, 300, 0, 2);
	assert fighter.outranks(forager, StrengthMeasure.Combat);
	assert forager.outranks(fighter, StrengthMeasure.Power);
}

test "level ranks before power" {
	const veteran = sample(12, 50, 50, 1, 0);
	const brute = sample(4, 400, 400, 0, 0);
	assert veteran.outranks(brute, StrengthMeasure.Level);
	assert !veteran.outranks(brute, StrengthMeasure.Power);
}

test "equal strength falls back to the position, so the order is total" {
	const first = sample(5, 100, 100, 2, 4);
	const second = sample(5, 100, 100, 2, 7);
	assert first.outranks(second, StrengthMeasure.Combat);
	assert !second.outranks(first, StrengthMeasure.Combat);
}

test "a move takes the new place and forgets every grudge" {
	const pet = sample(5, 100, 100, 2, 4);
	const moved = pet.movedTo(7, BlockSlot.Ninth);
	assert moved.blockId == 7 && moved.slot == 8;
	assert moved.rage == 0 && moved.rageEpoch == 0 && moved.grudgeSlot == 0;
	assert moved.harvest == pet.harvest && moved.level == pet.level;
}

test "the re-sort falls on every multiple of its period and never at zero" {
	assert resortsAt(7, 7) && resortsAt(14, 7);
	assert !resortsAt(0, 7) && !resortsAt(8, 7) && !resortsAt(7, 0);
}
