import {
	GamePet,
	GameRead,
	GameReadState,
	PetLife,
	SeatKind,
	deathNoticeSeen,
	gameRead,
	noGamePet,
} from "../host/host";
import { Outcome } from "../../rules/fight";
import { NotLive, livePet } from "./gameAvailability";
import { petDisplayName } from "./petNames";
import { blockRead } from "./neighbours";

// Every death hatches the next generation in the same Pet account at dusk (program/day.ms dusked).
export enum Mourning {
	// Dead today, or hatched and waiting for a Block.
	HeirWaiting,
	HeirArrived,
}

// Read while the chain still holds the dead Pet, before dusk; after it only the heir is left.
export enum DeathCause {
	OldAge,
	Starved,
	Beaten,
	Unknown,
}

export enum NotMourning {
	NoRead,
	NotDead,
	NoticeSeen,
}

// `pet` is the heir, as it is or as it will hatch.
export struct MournedPet {
	pet: GamePet;
	mourning: Mourning;
	cause: DeathCause;
	// Beaten: the slot (seat + 1) of the Pet that won the fight; 0 otherwise.
	slayerSlot: int32;
}

// Onboarding mourns a Pet from its death until the owner continues with its heir.
export function mournedPet(): Result<MournedPet, NotMourning> {
	const read = gameRead();
	if (!read.ok) { return Result.err(NotMourning.NoRead); }
	return mourning(read.value, deathNoticeSeen());
}

// `seen`: the highest lineage generation whose death notice the owner continued past, -1 for none.
export function mourning(snapshot: GameRead, seen: int32): Result<MournedPet, NotMourning> {
	const live = livePet(snapshot);
	if (!live.ok) {
		if (live.error == NotLive.Dead || live.error == NotLive.Inactive) { return dying(snapshot, seen); }
		const unplaced: boolean = live.error == NotLive.AwaitingPlacement || live.error == NotLive.AwaitingDelegation;
		const heir: GamePet = snapshot.pet;
		if (!unplaced || heir.lineageGeneration == 0) { return Result.err(NotMourning.NotDead); }
		if (heir.lineageGeneration <= seen) { return Result.err(NotMourning.NoticeSeen); }
		return Result.ok({ pet: heir, mourning: Mourning.HeirWaiting, cause: DeathCause.Unknown, slayerSlot: 0 });
	}
	const heir = live.value;
	if (heir.life != PetLife.HeirActive || heir.lineageGeneration <= seen) {
		return Result.err(NotMourning.NoticeSeen);
	}
	return Result.ok({ pet: heir, mourning: Mourning.HeirArrived, cause: DeathCause.Unknown, slayerSlot: 0 });
}

// The mourned Pet's own name, one generation before its heir.
export function mournedName(mourned: MournedPet): string {
	return petDisplayName(mourned.pet.nameId, (mourned.pet.lineageGeneration - 1) as uint16);
}

export function mournedLine(mourned: MournedPet): string {
	return match (mourned.cause) {
		DeathCause.OldAge => "DIED OF OLD AGE / THE HEIR KEEPS 70% AND TWO ITEMS",
		DeathCause.Starved => "STARVED / THE HEIR STARTS WITH NOTHING",
		DeathCause.Beaten => "FELL TO SLOT " + mourned.slayerSlot.toString() + " / THE HEIR STARTS WITH NOTHING",
		DeathCause.Unknown => "ITS HEIR CARRIES ON",
	};
}

// rules/life.ms agedOut: dead with hearts left is old age. Out of hearts, a fight it lost on the day it
// died beat it; with none, it starved.
function dying(snapshot: GameRead, seen: int32): Result<MournedPet, NotMourning> {
	const pet: GamePet = snapshot.pet;
	const heir: GamePet = { ...pet, lineageGeneration: pet.lineageGeneration + 1 };
	if (heir.lineageGeneration <= seen) { return Result.err(NotMourning.NoticeSeen); }
	if (pet.hearts > 0) {
		return Result.ok({ pet: heir, mourning: Mourning.HeirWaiting, cause: DeathCause.OldAge, slayerSlot: 0 });
	}
	const slayer: int32 = slayerSlot(snapshot);
	return Result.ok({ pet: heir, mourning: Mourning.HeirWaiting, cause: slayer > 0 ? DeathCause.Beaten : DeathCause.Starved,
		slayerSlot: slayer });
}

function slayerSlot(snapshot: GameRead): int32 {
	let me: int32 = -1;
	for (const seat of snapshot.seats) {
		if (seat.kind == SeatKind.Self) { me = seat.seat; }
	}
	let slayer: int32 = 0;
	for (const fight of snapshot.fights) {
		if (fight.epoch != snapshot.pet.blockEpoch) { continue; }
		const attackerWon: boolean = fight.outcome == Outcome.AttackerWins;
		if (fight.attackerSeat == me && !attackerWon) { slayer = fight.defenderSeat + 1; }
		if (fight.defenderSeat == me && attackerWon) { slayer = fight.attackerSeat + 1; }
	}
	return slayer;
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

test "a Pet is mourned from its death until the owner continues with its heir" {
	const waiting = mourning(unplacedHeirOf(1), -1);
	assert waiting.ok && waiting.value.mourning == Mourning.HeirWaiting;
	const waitingSeen = mourning(unplacedHeirOf(1), 1);
	assert !waitingSeen.ok && waitingSeen.error == NotMourning.NoticeSeen;
	const arrived = mourning(readOf(PetLife.HeirActive, 1), -1);
	assert arrived.ok && arrived.value.mourning == Mourning.HeirArrived;
	const continued = mourning(readOf(PetLife.HeirActive, 1), 1);
	assert !continued.ok && continued.error == NotMourning.NoticeSeen;
	const firstLife = mourning(readOf(PetLife.FirstLifeActive, 0), -1);
	assert !firstLife.ok && firstLife.error == NotMourning.NoticeSeen;
	const claimed = mourning(unplacedHeirOf(0), -1);
	assert !claimed.ok && claimed.error == NotMourning.NotDead;
}

test "a Pet that died today says how, before dusk hatches its heir" {
	const read = readOf(PetLife.InactiveWithoutDeathRecord, 0);
	const old = mourning(read, -1);
	assert old.ok && old.value.cause == DeathCause.OldAge && old.value.pet.lineageGeneration == 1;
	assert mournedName(old.value) == petDisplayName(read.pet.nameId, 0);
	const starved = mourning({ ...read, pet: { ...read.pet, hearts: 0 } }, -1);
	assert starved.ok && starved.value.cause == DeathCause.Starved;
	assert mournedLine(starved.value) == "STARVED / THE HEIR STARTS WITH NOTHING";
	const seen = mourning(read, 1);
	assert !seen.ok && seen.error == NotMourning.NoticeSeen;
	const block = blockRead();
	const beaten = mourning({ ...block, pet: { ...block.pet, life: PetLife.InactiveWithoutDeathRecord, hearts: 0 } }, -1);
	assert beaten.ok && beaten.value.cause == DeathCause.Beaten && beaten.value.slayerSlot == 10;
	assert mournedLine(beaten.value) == "FELL TO SLOT 10 / THE HEIR STARTS WITH NOTHING";
	const recorded = mourning(readOf(PetLife.DeathRecorded, 0), -1);
	assert recorded.ok && recorded.value.mourning == Mourning.HeirWaiting;
}
