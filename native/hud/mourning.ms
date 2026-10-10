import {
	GamePet,
	GameRead,
	GameReadState,
	PetLife,
	deathNoticeSeen,
	gameRead,
	noGamePet,
} from "../host/host";
import { NotLive, livePet } from "./gameAvailability";
import { petDisplayName } from "./petNames";

export enum Mourning {
	// Starved or beaten: the Pet is gone and no heir will hatch.
	Lost,
	// Died of old age: its heir is on chain, waiting for a Block.
	HeirWaiting,
	HeirArrived,
}

export enum NotMourning {
	NoRead,
	NotDead,
	NoticeSeen,
}

// `pet` is the Pet on chain: the lost one, or the heir.
export struct MournedPet {
	pet: GamePet;
	mourning: Mourning;
}

// Onboarding mourns a lost Pet for good, and an old one from its heir's hatching until the owner continues.
export function mournedPet(): Result<MournedPet, NotMourning> {
	const read = gameRead();
	if (!read.ok) { return Result.err(NotMourning.NoRead); }
	return mourning(read.value, deathNoticeSeen());
}

// `seen`: the highest lineage generation whose death notice the owner continued past, -1 for none.
export function mourning(snapshot: GameRead, seen: int32): Result<MournedPet, NotMourning> {
	const live = livePet(snapshot);
	if (!live.ok) {
		if (live.error == NotLive.Dead) { return Result.ok({ pet: snapshot.pet, mourning: Mourning.Lost }); }
		// Died during the day: the chain records it at dusk (program/day.ms dusked), and rules/life.ms
		// agedOut already says how it ends: out of hearts is lost, old with hearts left leaves an heir.
		if (live.error == NotLive.Inactive) { return dying(snapshot.pet, seen); }
		const unplaced: boolean = live.error == NotLive.AwaitingPlacement || live.error == NotLive.AwaitingDelegation;
		const heir: GamePet = snapshot.pet;
		if (!unplaced || heir.lineageGeneration == 0) { return Result.err(NotMourning.NotDead); }
		if (heir.lineageGeneration <= seen) { return Result.err(NotMourning.NoticeSeen); }
		return Result.ok({ pet: heir, mourning: Mourning.HeirWaiting });
	}
	const heir = live.value;
	if (heir.life != PetLife.HeirActive || heir.lineageGeneration <= seen) {
		return Result.err(NotMourning.NoticeSeen);
	}
	return Result.ok({ pet: heir, mourning: Mourning.HeirArrived });
}

// The mourned Pet's own name, generation included: `pet` is the heir unless the Pet was lost.
export function mournedName(mourned: MournedPet): string {
	const generation: int32 = mourned.pet.lineageGeneration - (mourned.mourning == Mourning.Lost ? 0 : 1);
	return petDisplayName(mourned.pet.nameId, generation as uint16);
}

export function mournedLine(mourning: Mourning): string {
	return match (mourning) {
		Mourning.Lost => "LOST FOR GOOD",
		Mourning.HeirWaiting => "DIED OF OLD AGE / ITS HEIR IS ON ITS WAY",
		Mourning.HeirArrived => "DIED OF OLD AGE / ITS HEIR HAS HATCHED",
	};
}

function dying(pet: GamePet, seen: int32): Result<MournedPet, NotMourning> {
	if (pet.hearts == 0) { return Result.ok({ pet: pet, mourning: Mourning.Lost }); }
	const heir: GamePet = { ...pet, lineageGeneration: pet.lineageGeneration + 1 };
	if (heir.lineageGeneration <= seen) { return Result.err(NotMourning.NoticeSeen); }
	return Result.ok({ pet: heir, mourning: Mourning.HeirWaiting });
}

function readOf(life: PetLife, lineageGeneration: int32): GameRead {
	return {
		ownerRevision: 2,
		state: GameReadState.PetFound,
		baseSlot: 10,
		ephemeralSlot: 20,
		admissionHoldings: 1,
		admissionMembers: 1,
		unclaimedMembers: 0,
		detail: "",
		ageSeconds: 30,
		pet: {
			...noGamePet(),
			life: life,
			lineageGeneration: lineageGeneration,
			delegated: true,
			member: true,
			blockStarted: true,
			blockEpoch: 40,
			worldDay: 41,
			level: 2,
			xp: 191,
			hearts: 8,
			maxHearts: 18,
		},
		seats: [],
		fights: [],
	};
}

function unplacedHeirOf(lineageGeneration: int32): GameRead {
	const read = readOf(PetLife.ClaimedUnplaced, lineageGeneration);
	return { ...read, pet: { ...read.pet, member: false, blockStarted: false } };
}

test "a lost Pet is mourned for good; an old one from its heir's hatching until the owner continues" {
	const lost = mourning(readOf(PetLife.DeathRecorded, 0), 3);
	assert lost.ok && lost.value.mourning == Mourning.Lost;
	const waiting = mourning(unplacedHeirOf(1), -1);
	assert waiting.ok && waiting.value.mourning == Mourning.HeirWaiting;
	const waitingSeen = mourning(unplacedHeirOf(1), 1);
	assert !waitingSeen.ok && waitingSeen.error == NotMourning.NoticeSeen;
	const arrived = mourning(readOf(PetLife.HeirActive, 1), -1);
	assert arrived.ok && arrived.value.mourning == Mourning.HeirArrived;
	const continued = mourning(readOf(PetLife.HeirActive, 1), 1);
	assert !continued.ok && continued.error == NotMourning.NoticeSeen;
	const nextDeath = mourning(readOf(PetLife.HeirActive, 2), 1);
	assert nextDeath.ok && nextDeath.value.mourning == Mourning.HeirArrived;
	const firstLife = mourning(readOf(PetLife.FirstLifeActive, 0), -1);
	assert !firstLife.ok && firstLife.error == NotMourning.NoticeSeen;
	const claimed = mourning(unplacedHeirOf(0), -1);
	assert !claimed.ok && claimed.error == NotMourning.NotDead;
}

test "a Pet that died today is mourned before dusk records it" {
	const read = readOf(PetLife.InactiveWithoutDeathRecord, 0);
	const starved = mourning({ ...read, pet: { ...read.pet, hearts: 0 } }, -1);
	assert starved.ok && starved.value.mourning == Mourning.Lost;
	const old = mourning(read, -1);
	assert old.ok && old.value.mourning == Mourning.HeirWaiting && old.value.pet.lineageGeneration == 1;
	const oldSeen = mourning(read, 1);
	assert !oldSeen.ok && oldSeen.error == NotMourning.NoticeSeen;
}

test "a mourned Pet is named as it lived, not as its heir" {
	const read = readOf(PetLife.InactiveWithoutDeathRecord, 1);
	const lost = mourning({ ...read, pet: { ...read.pet, hearts: 0 } }, -1);
	assert lost.ok && mournedName(lost.value) == petDisplayName(read.pet.nameId, 1) && mournedLine(lost.value.mourning) == "LOST FOR GOOD";
	const old = mourning(read, -1);
	assert old.ok && mournedName(old.value) == petDisplayName(read.pet.nameId, 1);
}
