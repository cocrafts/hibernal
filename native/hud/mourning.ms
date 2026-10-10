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
