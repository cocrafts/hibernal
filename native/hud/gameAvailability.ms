import {
	GameOwnerState,
	GameRead,
	GameReadError,
	GameReadState,
	GamePet,
	OwnerActionOutcome,
	PetLife,
	gameRead,
	noGamePet,
} from "../host/host";
import { levelForXp } from "../../rules/level";
import { EMISSION_START, pendingReward } from "../../rules/emission";
import { BlockSlot, Pet, stats } from "../../rules/layout";
import { born, settle } from "../../rules/life";
import { rewardWeight, Region } from "../../rules/stats";

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
	if (live.ok) { return "YOUR PET IS AWAKE."; }
	return match (live.error) {
		NotLive.NoPetRead => "LOOKING FOR YOUR PET...",
		NotLive.AwaitingDelegation => "YOUR PET IS CLAIMED. SUMMON IT TO WAKE IT.",
		NotLive.AwaitingPlacement => "YOUR PET IS WAITING FOR A BLOCK.",
		NotLive.WorldBehind => "THE WORLD IS CATCHING UP...",
		NotLive.ReadOld => "RECONNECTING...",
		NotLive.Dead => "YOUR PET HAS DIED.",
		NotLive.Inactive => "YOUR PET IS ASLEEP. CHECKING AGAIN SOON.",
		NotLive.Inconsistent => "SOMETHING LOOKS OFF. CHECKING AGAIN SOON.",
	};
}

export enum HudScreen {
	// The campfire alone: nothing read yet says whether the owner has a Pet.
	Waiting,
	Home,
	Onboarding,
}

// Onboarding only once a read or the owner state says there is no live Pet to show.
export function hudScreen(read: Result<GameRead, GameReadError>, owner: GameOwnerState, mourned: boolean): HudScreen {
	if (owner != GameOwnerState.Remembered || mourned) { return HudScreen.Onboarding; }
	if (!read.ok) { return HudScreen.Waiting; }
	if (read.value.state == GameReadState.NoPet) { return HudScreen.Onboarding; }
	const live = livePet(read.value);
	if (live.ok) { return HudScreen.Home; }
	return match (live.error) {
		NotLive.AwaitingDelegation | NotLive.AwaitingPlacement | NotLive.Dead | NotLive.Inactive => HudScreen.Onboarding,
		NotLive.NoPetRead | NotLive.WorldBehind | NotLive.ReadOld | NotLive.Inconsistent => HudScreen.Waiting,
	};
}

// The line under the campfire while waiting.
export function waitingStatus(read: Result<GameRead, GameReadError>): string {
	if (!read.ok) { return "LOOKING FOR YOUR PET..."; }
	if (read.value.state == GameReadState.Unavailable) { return "CONNECTING TO THE NETWORK..."; }
	return petReadStatus(read.value);
}

export function unavailablePetStatus(owner: GameOwnerState): string {
	return match (owner) {
		GameOwnerState.Unselected => "CONNECT YOUR WALLET TO FIND YOUR PET.",
		GameOwnerState.Remembered => "CONNECTING TO THE NETWORK...",
		GameOwnerState.Failed => "CONNECT YOUR WALLET AGAIN.",
	};
}

function noPetAdmissionStatus(snapshot: GameRead): string {
	if (snapshot.admissionHoldings == 0) {
		return "THIS WALLET HOLDS NO SEEKER GENESIS TOKEN.";
	}
	if (snapshot.unclaimedMembers > 0) {
		return "YOUR PET IS WAITING. SUMMON IT.";
	}
	if (snapshot.admissionMembers > 0) {
		return "YOUR TOKEN IS CLAIMED. LOOKING FOR ITS PET...";
	}
	return "NO PET FOR THIS WALLET YET.";
}

export function petReadStatus(snapshot: GameRead): string {
	return match (snapshot.state) {
		GameReadState.Unavailable => "CONNECT YOUR WALLET TO FIND YOUR PET.",
		GameReadState.Checking => "LOOKING FOR YOUR PET...",
		GameReadState.NoPet => noPetAdmissionStatus(snapshot),
		GameReadState.PetFound => petFoundStatus(snapshot),
		GameReadState.UnsupportedLayout => "THE GAME IS UPDATING. TRY AGAIN SOON.",
		GameReadState.Failed => "NETWORK HICCUP. RETRYING...",
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
		OwnerActionOutcome.SentPending => "SUMMON SENT. CONFIRMING...",
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

export enum IncomeUnknown {
	NotPlaced,
}

// What one full day pays this Pet at today's World, by the rules' own settle and reward share.
export function dailyIncome(pet: GamePet): Result<uint64, IncomeUnknown> {
	if (pet.world.genesisTimestamp == 0) { return Result.err(IncomeUnknown.NotPlaced); }
	const day: uint64 = Math.max(pet.worldDay, pet.world.rewardEpoch);
	const today = pet.world.settle(day);
	const tomorrow = pet.world.settle(day + 1);
	const worker: Pet = {
		...Pet.born(0, BlockSlot.First, Region.Worker, day, pet.world).pet,
		level: pet.level as uint16,
		forage: pet.forage as uint16,
		might: pet.might as uint16,
		grit: pet.grit as uint16,
		maxHearts: pet.maxHearts as uint8,
		talentKind: (pet.talentKind as int32) as uint8,
		talentBps: pet.talentBps as uint16,
		growthMultiplierBps: pet.growthMultiplierBps as uint16,
		growthMultiplierExpiry: pet.growthMultiplierExpiry,
		lastTickEpoch: pet.lastTickEpoch,
		gear: pet.gear,
	};
	return Result.ok(pendingReward(worker.stats().rewardWeight(), tomorrow.rewardPerWorkPower, today.rewardPerWorkPower));
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
	assert petReadStatus(snapshot) == "YOUR PET IS CLAIMED. SUMMON IT TO WAKE IT.";
	snapshot.state = GameReadState.UnsupportedLayout;
	assert petReadStatus(snapshot) == "THE GAME IS UPDATING. TRY AGAIN SOON.";
	snapshot.state = GameReadState.NoPet;
	snapshot.admissionHoldings = 0;
	assert petReadStatus(snapshot) == "THIS WALLET HOLDS NO SEEKER GENESIS TOKEN.";
	snapshot.admissionHoldings = 1;
	snapshot.admissionMembers = 0;
	snapshot.unclaimedMembers = 0;
	assert petReadStatus(snapshot) == "NO PET FOR THIS WALLET YET.";
	snapshot.admissionMembers = 1;
	snapshot.unclaimedMembers = 1;
	assert petReadStatus(snapshot) == "YOUR PET IS WAITING. SUMMON IT.";
	snapshot.unclaimedMembers = 0;
	assert petReadStatus(snapshot) == "YOUR TOKEN IS CLAIMED. LOOKING FOR ITS PET...";
	snapshot.state = GameReadState.Failed;
	assert petReadStatus(snapshot) == "NETWORK HICCUP. RETRYING...";
}

test "unselected owner is not proof of no Pet" {
	assert unavailablePetStatus(GameOwnerState.Unselected) ==
		"CONNECT YOUR WALLET TO FIND YOUR PET.";
}

test "remembered owner is not verified Pet or wallet authorization" {
	assert unavailablePetStatus(GameOwnerState.Remembered) ==
		"CONNECTING TO THE NETWORK...";
}

test "cache failure is not absence of Pet" {
	assert unavailablePetStatus(GameOwnerState.Failed) ==
		"CONNECT YOUR WALLET AGAIN.";
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
	assert petReadStatus(snapshot) == "YOUR PET IS AWAKE.";
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
	assert petReadStatus(snapshot) == "YOUR PET IS WAITING FOR A BLOCK.";
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
	assert petReadStatus(behind) == "THE WORLD IS CATCHING UP...";
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
	assert petReadStatus(dead) == "YOUR PET HAS DIED.";
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

test "a Pet alone in the World earns the whole day's emission; an unplaced one has no income yet" {
	assert !dailyIncome(noGamePet()).ok;
	// Forage 100: work power 10 + 30, reward weight (40 + 50)^2.
	const alone: GamePet = {
		...noGamePet(),
		level: 1,
		forage: 100,
		maxHearts: 10,
		world: { ...noGamePet().world, genesisTimestamp: 1, totalWorkPower: 8100, livingPets: 1, floorSlots: 1 },
	};
	const income = dailyIncome(alone);
	assert income.ok && income.value <= EMISSION_START && income.value + 1 >= EMISSION_START;
}

test "the campfire waits until a read says whether there is a live Pet" {
	const live = livePetRead();
	const remembered = GameOwnerState.Remembered;
	assert hudScreen(Result.ok(live), remembered, false) == HudScreen.Home;
	assert hudScreen(Result.ok(live), remembered, true) == HudScreen.Onboarding;
	assert hudScreen(Result.ok(live), GameOwnerState.Unselected, false) == HudScreen.Onboarding;
	assert hudScreen(Result.ok(live), GameOwnerState.Failed, false) == HudScreen.Onboarding;
	assert hudScreen(Result.err(GameReadError.Updating), remembered, false) == HudScreen.Waiting;
	for (const state of [GameReadState.Unavailable, GameReadState.Checking, GameReadState.UnsupportedLayout,
		GameReadState.Failed]) {
		assert hudScreen(Result.ok({ ...live, state: state }), remembered, false) == HudScreen.Waiting;
	}
	assert hudScreen(Result.ok({ ...live, state: GameReadState.NoPet }), remembered, false) == HudScreen.Onboarding;
	assert hudScreen(Result.ok({ ...live, ageSeconds: LIVE_READ_MAX_AGE_SECONDS + 1 }), remembered, false)
		== HudScreen.Waiting;
	const unplaced: GameRead = { ...live, pet: { ...live.pet, member: false } };
	assert hudScreen(Result.ok(unplaced), remembered, false) == HudScreen.Onboarding;
	const dead: GameRead = { ...live, pet: { ...live.pet, life: PetLife.DeathRecorded } };
	assert hudScreen(Result.ok(dead), remembered, false) == HudScreen.Onboarding;
	assert waitingStatus(Result.ok({ ...live, state: GameReadState.Failed })) == "NETWORK HICCUP. RETRYING...";
}
