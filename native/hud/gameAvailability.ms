import {
	GameOwnerState,
	GameRead,
	GameReadState,
	GamePet,
	OwnerActionOutcome,
	PetLife,
	gameRead,
	noGamePet,
} from "../host/host";
import { levelForXp } from "../../rules/level";

// GameSync refreshes every 30 s; four missed refreshes is no longer a live read.
export const LIVE_READ_MAX_AGE_SECONDS: int64 = 120;
// A Block runs its day's turns after the clock's day starts; a full day behind has stalled.
export const BLOCK_DAYS_BEHIND_ALLOWED: uint64 = 1;

export enum NotLive {
	NoPetRead,
	AwaitingDelegation,
	AwaitingPlacement,
	WorldBehind,
	ReadOld,
	Dead,
	Inactive,
	Inconsistent,
}

// The only way into the live Home: a validated Pet, alive, delegated, seated in a started
// Block, the Block within a day of the clock, and a recent read.
export function livePet(snapshot: GameRead): Result<GamePet, NotLive> {
	if (snapshot.state != GameReadState.PetFound) { return Result.err(NotLive.NoPetRead); }
	const pet = snapshot.pet;
	match (pet.life) {
		PetLife.ClaimedUnplaced => {
			const waiting = pet.delegated ? NotLive.AwaitingPlacement : NotLive.AwaitingDelegation;
			return Result.err(waiting);
		},
		PetLife.DeathRecorded => { return Result.err(NotLive.Dead); },
		PetLife.InactiveWithoutDeathRecord => { return Result.err(NotLive.Inactive); },
		PetLife.FirstLifeActive | PetLife.HeirActive => {},
	};
	if (!pet.delegated) { return Result.err(NotLive.AwaitingDelegation); }
	if (!pet.member || !pet.blockStarted) { return Result.err(NotLive.AwaitingPlacement); }
	if (pet.blockEpoch + BLOCK_DAYS_BEHIND_ALLOWED < pet.worldDay) {
		return Result.err(NotLive.WorldBehind);
	}
	if (snapshot.ageSeconds < 0 || snapshot.ageSeconds > LIVE_READ_MAX_AGE_SECONDS) {
		return Result.err(NotLive.ReadOld);
	}
	if (levelForXp(pet.xp) != pet.level || pet.maxHearts <= 0 || pet.hearts > pet.maxHearts) {
		return Result.err(NotLive.Inconsistent);
	}
	return Result.ok(pet);
}

export function currentLivePet(): Result<GamePet, NotLive> {
	const read = gameRead();
	if (!read.ok) { return Result.err(NotLive.NoPetRead); }
	return livePet(read.value);
}

function petFoundStatus(snapshot: GameRead): string {
	const live = livePet(snapshot);
	if (live.ok) { return "PET IS LIVE."; }
	return match (live.error) {
		NotLive.NoPetRead => "PET STATE IS UNKNOWN.",
		NotLive.AwaitingDelegation => "PET CLAIMED. WAITING FOR ER DELEGATION.",
		NotLive.AwaitingPlacement => "PET DELEGATED. WAITING FOR BLOCK PLACEMENT.",
		NotLive.WorldBehind => "ER WORLD IS BEHIND. PET STATE IS STALE.",
		NotLive.ReadOld => "NO FRESH CHAIN READ. PET STATE IS STALE.",
		NotLive.Dead => "YOUR PET IS LOST FOR GOOD.",
		NotLive.Inactive => "PET INACTIVE, NO DEATH RECORD. UNKNOWN.",
		NotLive.Inconsistent => "PET READ INCONSISTENT. NOT GAME READY.",
	};
}

export function unavailablePetStatus(owner: GameOwnerState): string {
	return match (owner) {
		GameOwnerState.Unselected => "SELECT AN OWNER. PET STATE IS UNKNOWN.",
		GameOwnerState.Remembered => "CHAIN CLIENT UNAVAILABLE. PET STATE UNKNOWN.",
		GameOwnerState.Failed => "OWNER CACHE UNREADABLE. SELECT WALLET AGAIN.",
	};
}

function noPetAdmissionStatus(snapshot: GameRead): string {
	if (snapshot.admissionHoldings == 0) {
		return "NO PET FOUND. NO TOKEN-2022 ADMISSION HELD.";
	}
	if (snapshot.unclaimedMembers > 0) {
		return "ADMISSION FOUND. SUMMON TO CLAIM YOUR PET.";
	}
	if (snapshot.admissionMembers > 0) {
		return "ADMISSION CLAIMED. RESUME NEEDS VERIFICATION.";
	}
	return "NO PET FOUND. NO ADMISSION MEMBER MATCH.";
}

export function petReadStatus(snapshot: GameRead): string {
	return match (snapshot.state) {
		GameReadState.Unavailable => "SELECT AN OWNER. PET STATE IS UNKNOWN.",
		GameReadState.Checking => "CHECKING L1 / ER FOR YOUR PET.",
		GameReadState.NoPet => noPetAdmissionStatus(snapshot),
		GameReadState.PetFound => petFoundStatus(snapshot),
		GameReadState.UnsupportedLayout => "DEPLOYED CONTRACT UNVERIFIED. NOT GAME READY.",
		GameReadState.Failed => "CHAIN READ FAILED. PET STATE IS UNKNOWN.",
	};
}

// Summon claims and delegates, or only delegates a claimed Pet; the shell picks which from L1.
export function summonAllowed(snapshot: GameRead): boolean {
	if (snapshot.state == GameReadState.NoPet) { return true; }
	const live = livePet(snapshot);
	return !live.ok && live.error == NotLive.AwaitingDelegation;
}

export function summonInFlight(outcome: OwnerActionOutcome): boolean {
	return outcome == OwnerActionOutcome.Requested || outcome == OwnerActionOutcome.SentPending;
}

export function summonStatus(outcome: OwnerActionOutcome): string {
	return match (outcome) {
		OwnerActionOutcome.Idle => "",
		OwnerActionOutcome.Requested => "PREPARING SUMMON. APPROVE IT IN YOUR WALLET.",
		OwnerActionOutcome.Cancelled => "SUMMON CANCELLED. NOTHING SENT.",
		OwnerActionOutcome.NoWallet => "NO WALLET APP FOUND. NOTHING SENT.",
		OwnerActionOutcome.WalletFailed => "WALLET DID NOT SIGN. CONNECT AND RETRY.",
		OwnerActionOutcome.SentPending => "SUMMON SENT. CONFIRMING ON DEVNET.",
		OwnerActionOutcome.ConfirmedAwaitingRead => "SUMMON CONFIRMED. READING YOUR PET.",
		OwnerActionOutcome.FailedOnChain => "SUMMON FAILED ON CHAIN.",
		OwnerActionOutcome.Expired => "SUMMON EXPIRED BEFORE LANDING. RETRY.",
		OwnerActionOutcome.Unknown => "SUMMON OUTCOME UNKNOWN. WAIT FOR THE NEXT READ.",
		OwnerActionOutcome.Unavailable => "SUMMON PREFLIGHT FAILED. NOTHING SENT.",
		OwnerActionOutcome.NoSeekerGenesisToken => "THIS WALLET HOLDS NO SEEKER GENESIS TOKEN.",
		OwnerActionOutcome.AdmissionFailed => "ADMISSION SERVICE FAILED. NOTHING SENT.",
	};
}

export function buyStatus(outcome: OwnerActionOutcome): string {
	return match (outcome) {
		OwnerActionOutcome.Idle => "",
		OwnerActionOutcome.Requested => "PREPARING PURCHASE. APPROVE IT IN YOUR WALLET.",
		OwnerActionOutcome.Cancelled => "PURCHASE CANCELLED. NOTHING PAID.",
		OwnerActionOutcome.NoWallet => "NO WALLET OR PET READ. NOTHING PAID.",
		OwnerActionOutcome.WalletFailed => "WALLET DID NOT SIGN. CONNECT AND RETRY.",
		OwnerActionOutcome.SentPending => "PURCHASE SENT. CONFIRMING ON DEVNET.",
		OwnerActionOutcome.ConfirmedAwaitingRead => "PAID. ITEMS REACH SLOTS 5 AND 6 WITHIN A MINUTE.",
		OwnerActionOutcome.FailedOnChain => "PURCHASE REFUSED BY THE PROGRAM. NOTHING PAID.",
		OwnerActionOutcome.Expired => "EXPIRED BEFORE LANDING. RETRY.",
		OwnerActionOutcome.Unknown => "OUTCOME UNKNOWN. WAIT FOR THE NEXT READ.",
		OwnerActionOutcome.Unavailable => "PURCHASE PREFLIGHT FAILED. NOTHING PAID.",
		OwnerActionOutcome.NoSeekerGenesisToken => "THIS WALLET HOLDS NO SEEKER GENESIS TOKEN.",
		OwnerActionOutcome.AdmissionFailed => "ADMISSION SERVICE FAILED. NOTHING PAID.",
	};
}

// The owner's gift is Pet.giftOwed less what Paid already minted. ClaimReward pays from the
// L1 copy, so a gift the ER has but L1 lacks needs CommitPet first (the shell picks the step).
export enum GiftStep {
	Nothing,
	Commit,
	Claim,
}

export function giftOwedToOwner(pet: GamePet): uint64 {
	return pet.giftOwed > pet.paidTotal ? pet.giftOwed - pet.paidTotal : 0;
}

export function giftStep(pet: GamePet): GiftStep {
	if (pet.committedGiftOwed > pet.paidTotal) { return GiftStep.Claim; }
	if (pet.giftOwed > pet.paidTotal) { return GiftStep.Commit; }
	return GiftStep.Nothing;
}

export function giftStatus(outcome: OwnerActionOutcome): string {
	return match (outcome) {
		OwnerActionOutcome.Idle => "",
		OwnerActionOutcome.Requested => "PREPARING CLAIM. APPROVE IT IN YOUR WALLET.",
		OwnerActionOutcome.Cancelled => "CLAIM CANCELLED. NOTHING SENT.",
		OwnerActionOutcome.NoWallet => "NO WALLET OR PET READ. NOTHING SENT.",
		OwnerActionOutcome.WalletFailed => "WALLET DID NOT SIGN. CONNECT AND RETRY.",
		OwnerActionOutcome.SentPending => "SENT. CONFIRMING ON DEVNET.",
		OwnerActionOutcome.ConfirmedAwaitingRead => "CONFIRMED. WAITING FOR THE NEXT READ.",
		OwnerActionOutcome.FailedOnChain => "CLAIM REFUSED BY THE PROGRAM. NOTHING PAID.",
		OwnerActionOutcome.Expired => "EXPIRED BEFORE LANDING. RETRY.",
		OwnerActionOutcome.Unknown => "OUTCOME UNKNOWN. WAIT FOR THE NEXT READ.",
		OwnerActionOutcome.Unavailable => "CLAIM PREFLIGHT FAILED. NOTHING SENT.",
		OwnerActionOutcome.NoSeekerGenesisToken => "THIS WALLET HOLDS NO SEEKER GENESIS TOKEN.",
		OwnerActionOutcome.AdmissionFailed => "ADMISSION SERVICE FAILED. NOTHING SENT.",
	};
}

test "the gift claims what L1 holds, commits what only the ER holds, and never repays" {
	let pet: GamePet = noGamePet();
	assert giftStep(pet) == GiftStep.Nothing;
	pet.giftOwed = 500;
	assert giftStep(pet) == GiftStep.Commit;
	assert giftOwedToOwner(pet) == 500;
	pet.committedGiftOwed = 500;
	assert giftStep(pet) == GiftStep.Claim;
	pet.paidTotal = 500;
	assert giftStep(pet) == GiftStep.Nothing;
	assert giftOwedToOwner(pet) == 0;
	pet.giftOwed = 800;
	assert giftStep(pet) == GiftStep.Commit;
	assert giftOwedToOwner(pet) == 300;
}

test "summon asks the wallet only with no Pet or a claimed Pet awaiting delegation" {
	let snapshot: GameRead = {
		ownerRevision: 2,
		state: GameReadState.NoPet,
		baseSlot: 1,
		ephemeralSlot: 2,
		admissionHoldings: 0,
		admissionMembers: 0,
		unclaimedMembers: 0,
		detail: "",
		ageSeconds: 0,
		pet: noGamePet(),
		seats: [],
		fights: [],
	};
	assert summonAllowed(snapshot);
	snapshot.state = GameReadState.PetFound;
	assert summonAllowed(snapshot);
	snapshot.pet.delegated = true;
	assert !summonAllowed(snapshot);
	snapshot.state = GameReadState.Checking;
	assert !summonAllowed(snapshot);
	snapshot.state = GameReadState.Failed;
	assert !summonAllowed(snapshot);
	assert summonInFlight(OwnerActionOutcome.SentPending);
	assert !summonInFlight(OwnerActionOutcome.Unknown);
}

test "read results never turn a found or unsupported Pet into game ready" {
	let snapshot: GameRead = {
		ownerRevision: 2,
		state: GameReadState.PetFound,
		baseSlot: 1,
		ephemeralSlot: 2,
		admissionHoldings: -1,
		admissionMembers: -1,
		unclaimedMembers: -1,
		detail: "",
		ageSeconds: 0,
		pet: noGamePet(),
		seats: [],
		fights: [],
	};
	assert petReadStatus(snapshot) == "PET CLAIMED. WAITING FOR ER DELEGATION.";
	snapshot.state = GameReadState.UnsupportedLayout;
	assert petReadStatus(snapshot) == "DEPLOYED CONTRACT UNVERIFIED. NOT GAME READY.";
	snapshot.state = GameReadState.NoPet;
	snapshot.admissionHoldings = 0;
	assert petReadStatus(snapshot) == "NO PET FOUND. NO TOKEN-2022 ADMISSION HELD.";
	snapshot.admissionHoldings = 1;
	snapshot.admissionMembers = 0;
	snapshot.unclaimedMembers = 0;
	assert petReadStatus(snapshot) == "NO PET FOUND. NO ADMISSION MEMBER MATCH.";
	snapshot.admissionMembers = 1;
	snapshot.unclaimedMembers = 1;
	assert petReadStatus(snapshot) == "ADMISSION FOUND. SUMMON TO CLAIM YOUR PET.";
	snapshot.unclaimedMembers = 0;
	assert petReadStatus(snapshot) == "ADMISSION CLAIMED. RESUME NEEDS VERIFICATION.";
	snapshot.state = GameReadState.Failed;
	assert petReadStatus(snapshot) == "CHAIN READ FAILED. PET STATE IS UNKNOWN.";
}

test "unselected owner is not proof of no Pet" {
	assert unavailablePetStatus(GameOwnerState.Unselected) ==
		"SELECT AN OWNER. PET STATE IS UNKNOWN.";
}

test "remembered owner is not verified Pet or wallet authorization" {
	assert unavailablePetStatus(GameOwnerState.Remembered) ==
		"CHAIN CLIENT UNAVAILABLE. PET STATE UNKNOWN.";
}

test "cache failure is not absence of Pet" {
	assert unavailablePetStatus(GameOwnerState.Failed) ==
		"OWNER CACHE UNREADABLE. SELECT WALLET AGAIN.";
}

function livePetRead(): GameRead {
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
			life: PetLife.FirstLifeActive,
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

function refusedAs(snapshot: GameRead, reason: NotLive): boolean {
	const live = livePet(snapshot);
	if (live.ok) { return false; }
	return live.error == reason;
}

test "a placed, delegated, fresh and consistent Pet is live" {
	const snapshot = livePetRead();
	const live = livePet(snapshot);
	assert live.ok;
	if (live.ok) { assert live.value.xp == 191; }
	assert petReadStatus(snapshot) == "PET IS LIVE.";
	let heir = livePetRead();
	heir.pet.life = PetLife.HeirActive;
	assert livePet(heir).ok;
}

test "only a read Pet can be live" {
	let snapshot = livePetRead();
	for (const state of [GameReadState.Unavailable, GameReadState.Checking, GameReadState.NoPet,
		GameReadState.UnsupportedLayout, GameReadState.Failed]) {
		snapshot.state = state;
		assert refusedAs(snapshot, NotLive.NoPetRead);
	}
}

test "a confirmed Claim is pending, never ready or dead" {
	let snapshot = livePetRead();
	snapshot.pet.life = PetLife.ClaimedUnplaced;
	snapshot.pet.delegated = false;
	assert refusedAs(snapshot, NotLive.AwaitingDelegation);
	snapshot.pet.delegated = true;
	assert refusedAs(snapshot, NotLive.AwaitingPlacement);
	assert petReadStatus(snapshot) == "PET DELEGATED. WAITING FOR BLOCK PLACEMENT.";
}

test "an alive Pet without delegation, membership or a started Block waits" {
	let undelegated = livePetRead();
	undelegated.pet.delegated = false;
	assert refusedAs(undelegated, NotLive.AwaitingDelegation);
	let stranger = livePetRead();
	stranger.pet.member = false;
	assert refusedAs(stranger, NotLive.AwaitingPlacement);
	let idle = livePetRead();
	idle.pet.blockStarted = false;
	assert refusedAs(idle, NotLive.AwaitingPlacement);
}

test "a Block more than a day behind the clock or an old read is stale" {
	let behind = livePetRead();
	behind.pet.worldDay = 42;
	assert refusedAs(behind, NotLive.WorldBehind);
	assert petReadStatus(behind) == "ER WORLD IS BEHIND. PET STATE IS STALE.";
	let old = livePetRead();
	old.ageSeconds = LIVE_READ_MAX_AGE_SECONDS + 1;
	assert refusedAs(old, NotLive.ReadOld);
	old.ageSeconds = LIVE_READ_MAX_AGE_SECONDS;
	assert livePet(old).ok;
	old.ageSeconds = -1;
	assert refusedAs(old, NotLive.ReadOld);
}

test "death and inactivity are separate and never live" {
	let dead = livePetRead();
	dead.pet.life = PetLife.DeathRecorded;
	assert refusedAs(dead, NotLive.Dead);
	assert petReadStatus(dead) == "YOUR PET IS LOST FOR GOOD.";
	dead.pet.life = PetLife.InactiveWithoutDeathRecord;
	assert refusedAs(dead, NotLive.Inactive);
}

test "level, XP and hearts that disagree with the rules are not live" {
	let level = livePetRead();
	level.pet.xp = 190;
	assert refusedAs(level, NotLive.Inconsistent);
	let hearts = livePetRead();
	hearts.pet.hearts = 19;
	assert refusedAs(hearts, NotLive.Inconsistent);
	hearts.pet.hearts = 0;
	hearts.pet.maxHearts = 0;
	assert refusedAs(hearts, NotLive.Inconsistent);
}
