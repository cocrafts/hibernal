// The Android shell, seen from the core: whether this frame draws in the app or as the live
// wallpaper, where the system wallpaper is set, and the request to open its picker (hostLink.c).

import { Pubkey } from "std/solana/pubkey";
import { TalentKind } from "../../rules/talent";
import { Combatant, Mod, Region, modsFromMask } from "../../rules/stats";
import { BlockSlot, GlobalConfig, Insurance } from "../../rules/layout";
import { OwnerItem } from "../../rules/owner";
import { Gear, Item } from "../../rules/items";
import { Outcome } from "../../rules/fight";

@include("./hostLink.h");
@compile("./hostLink.c");

extern function hostInApp(): int32;
extern function hostWallpaperPlaces(): int32;
extern function hostRequestWallpaperPicker(): void;
extern function hostPetNewsAllowed(): int32;
extern function hostRequestPetNews(): void;
extern function hostDeathNoticeSeen(): int32;
extern function hostMarkDeathNoticeSeen(generation: int32): void;
extern function hostRequestWalletConnect(): void;
extern function hostRequestWalletDisconnect(): void;
extern function hostWalletState(): int32;
extern function hostWalletRevision(): int32;
extern function hostWalletAddressByte(index: int32): int32;
extern function hostRequestOwnerAction(action: int32, item: int32): void;
extern function hostOwnerActionState(): int32;
extern function hostOwnerActionRevision(): int32;
extern function hostTakeOwnerActionRequest(): int32;
extern function hostSetOwnerAction(state: int32): void;
extern function hostGameOwnerState(): int32;
extern function hostGameOwnerRevision(): int32;
extern function hostGameOwnerKeyByte(index: int32): int32;
extern function hostGameReadState(): int32;
extern function hostGameReadRevision(): int32;
extern function hostGameReadBaseSlot(): uint64;
extern function hostGameReadEphemeralSlot(): uint64;
extern function hostGameReadAdmissionHoldings(): int32;
extern function hostGameReadAdmissionMembers(): int32;
extern function hostGameReadUnclaimedMembers(): int32;
extern function hostGameReadDetailByte(index: int32): int32;
extern function hostGameReadAgeSeconds(): int64;
extern function hostGameReadPetField(index: int32): int64;
extern function hostGameReadSeatCount(): int32;
extern function hostGameReadSeatField(seat: int32, field: int32): int64;
extern function hostGameReadFightCount(): int32;
extern function hostGameReadFightField(fight: int32, field: int32): int64;

export enum WallpaperPlace { Off, Home, Lock, HomeAndLock }

export function inApp(): boolean {
	return hostInApp() != 0;
}

// A match statement until ~/metascript/.inbox/compiler/2026-10-05-unreachable-arm-of-a-match-expression-fails-codegen.md
// lands: an `unreachable` arm of `return match` does not build.
export function wallpaperPlace(): WallpaperPlace {
	const places: int32 = hostWallpaperPlaces();
	match (places) {
		0 => { return WallpaperPlace.Off; },
		1 => { return WallpaperPlace.Home; },
		2 => { return WallpaperPlace.Lock; },
		3 => { return WallpaperPlace.HomeAndLock; },
		_ => {},
	};
	console.log("host: wallpaper places " + places.toString() + " is not two bits");
	unreachable;
}

export function requestWallpaperPicker(): void {
	hostRequestWallpaperPicker();
}

export function petNewsAllowed(): boolean {
	return hostPetNewsAllowed() != 0;
}

export function requestPetNews(): void {
	hostRequestPetNews();
}

// The highest lineage generation whose death notice this owner has seen for this Pet, -1 for none.
export function deathNoticeSeen(): int32 {
	return hostDeathNoticeSeen();
}

export function markDeathNoticeSeen(generation: int32): void {
	if (generation < 0) {
		console.log("host: death notice generation " + generation.toString() + " is negative");
		unreachable;
	}
	hostMarkDeathNoticeSeen(generation);
}

export enum WalletState {
	Disconnected,
	Connecting,
	Connected,
	NoWallet,
	Cancelled,
	Failed,
	Disconnecting,
}

let addressRevision: int32 = -1;
let connectedAddress: string = "";

export function walletState(): WalletState {
	const state: int32 = hostWalletState();
	match (state) {
		0 => { return WalletState.Disconnected; },
		1 => { return WalletState.Connecting; },
		2 => { return WalletState.Connected; },
		3 => { return WalletState.NoWallet; },
		4 => { return WalletState.Cancelled; },
		5 => { return WalletState.Failed; },
		6 => { return WalletState.Disconnecting; },
		_ => {},
	};
	console.log("host: unknown wallet state " + state.toString());
	unreachable;
}

export function walletAddress(): string {
	const revision: int32 = hostWalletRevision();
	if (revision == addressRevision) { return connectedAddress; }
	const bytes: uint8[] = [];
	for (let index: int32 = 0; index < 44; index += 1) {
		const value: int32 = hostWalletAddressByte(index);
		if (value == 0) { break; }
		bytes.push(value as uint8);
	}
	if (hostWalletRevision() != revision) { return ""; }
	connectedAddress = bytes.asString();
	addressRevision = revision;
	return connectedAddress;
}

export function requestWalletConnection(): void {
	hostRequestWalletConnect();
}

export function requestWalletDisconnect(): void {
	hostRequestWalletDisconnect();
}

// Ordinals are the host ABI shared with OwnerSigning.kt.
export enum OwnerAction {
	Claim,
	DelegatePet,
	Engage,
	Bank,
	Buy,
	Load,
	CommitPet,
	ClaimReward,
}

export enum OwnerActionOutcome {
	Idle,
	Requested,
	Cancelled,
	NoWallet,
	WalletFailed,
	SentPending,
	ConfirmedAwaitingRead,
	FailedOnChain,
	Expired,
	Unknown,
	Unavailable,
	NoSeekerGenesisToken,
	AdmissionFailed,
	// The game already committed this Pet today; the next gift reaches L1 tomorrow.
	GiftTooSoon,
}

// Only Buy reads item and tier; other actions pass 0.
// Claim carries a name id, Buy a packed cart (ownerGoods.ms packedCart): 3 goods of 4 bits.
export const OWNER_ACTION_ITEM_MAX: int32 = 0xffff;

export function requestOwnerAction(action: OwnerAction, item: int32): void {
	if (item < 0 || item > OWNER_ACTION_ITEM_MAX) {
		console.log("host: owner action item " + item.toString() + " does not fit 16 bits");
		unreachable;
	}
	hostRequestOwnerAction(action as int32, item);
}

export function ownerActionOutcome(): OwnerActionOutcome {
	const state: int32 = hostOwnerActionState();
	match (state) {
		0 => { return OwnerActionOutcome.Idle; },
		1 => { return OwnerActionOutcome.Requested; },
		2 => { return OwnerActionOutcome.Cancelled; },
		3 => { return OwnerActionOutcome.NoWallet; },
		4 => { return OwnerActionOutcome.WalletFailed; },
		5 => { return OwnerActionOutcome.SentPending; },
		6 => { return OwnerActionOutcome.ConfirmedAwaitingRead; },
		7 => { return OwnerActionOutcome.FailedOnChain; },
		8 => { return OwnerActionOutcome.Expired; },
		9 => { return OwnerActionOutcome.Unknown; },
		10 => { return OwnerActionOutcome.Unavailable; },
		11 => { return OwnerActionOutcome.NoSeekerGenesisToken; },
		12 => { return OwnerActionOutcome.AdmissionFailed; },
		13 => { return OwnerActionOutcome.GiftTooSoon; },
		_ => {},
	};
	console.log("host: unknown owner action outcome " + state.toString());
	unreachable;
}

export function ownerActionRevision(): int32 {
	return hostOwnerActionRevision();
}

test "one owner action is in flight until the shell publishes its outcome" {
	const before = ownerActionRevision();
	requestOwnerAction(OwnerAction.Buy, 0x713);
	assert ownerActionOutcome() == OwnerActionOutcome.Requested;
	assert ownerActionRevision() == before + 1;
	requestOwnerAction(OwnerAction.Bank, 0);
	assert hostTakeOwnerActionRequest() == (5 | (0x713 << 8));
	assert hostTakeOwnerActionRequest() == 0;
	hostSetOwnerAction(OwnerActionOutcome.SentPending as int32);
	requestOwnerAction(OwnerAction.Bank, 0);
	assert hostTakeOwnerActionRequest() == 0;
	hostSetOwnerAction(OwnerActionOutcome.ConfirmedAwaitingRead as int32);
	requestOwnerAction(OwnerAction.ClaimReward, 0);
	assert hostTakeOwnerActionRequest() == 8;
	hostSetOwnerAction(14);
	assert ownerActionOutcome() == OwnerActionOutcome.Unknown;
	hostSetOwnerAction(OwnerActionOutcome.AdmissionFailed as int32);
	assert ownerActionOutcome() == OwnerActionOutcome.AdmissionFailed;
	hostSetOwnerAction(OwnerActionOutcome.GiftTooSoon as int32);
	assert ownerActionOutcome() == OwnerActionOutcome.GiftTooSoon;
	hostSetOwnerAction(OwnerActionOutcome.Unavailable as int32);
	assert ownerActionOutcome() == OwnerActionOutcome.Unavailable;
	hostSetOwnerAction(OwnerActionOutcome.Idle as int32);
}

// Remembered identity is not a connected wallet or evidence of an existing Pet.
export enum GameOwnerState { Unselected, Remembered, Failed }

let gameOwnerAddressRevision: int32 = -1;
let rememberedOwnerAddress: string = "";

export function gameOwnerState(): GameOwnerState {
	return match (hostGameOwnerState()) {
		0 => GameOwnerState.Unselected,
		1 => GameOwnerState.Remembered,
		_ => GameOwnerState.Failed,
	};
}

export function gameOwnerAddress(): string {
	const revision: int32 = hostGameOwnerRevision();
	if (revision % 2 != 0) { return ""; }
	if (revision == gameOwnerAddressRevision) { return rememberedOwnerAddress; }
	let address: string = "";
	if (gameOwnerState() == GameOwnerState.Remembered) {
		let keyBytes = Pubkey.zero();
		for (let index: int32 = 0; index < 32; index += 1) {
			keyBytes.bytes[index] = hostGameOwnerKeyByte(index) as uint8;
		}
		if (hostGameOwnerRevision() != revision) { return ""; }
		const key = Pubkey.fromBytes(keyBytes.bytes);
		if (key.ok) { address = key.value.toBase58(); }
	}
	if (hostGameOwnerRevision() != revision) { return ""; }
	rememberedOwnerAddress = address;
	gameOwnerAddressRevision = revision;
	return rememberedOwnerAddress;
}

export enum GameReadState {
	Unavailable,
	Checking,
	NoPet,
	PetFound,
	UnsupportedLayout,
	Failed,
}

export enum GameReadError {
	Updating,
	InvalidState,
}

// SourcePetLifecycle.Fact in the Kotlin shell, in that order.
export enum PetLife {
	ClaimedUnplaced,
	FirstLifeActive,
	HeirActive,
	InactiveWithoutDeathRecord,
	DeathRecorded,
}

export enum Persona {
	Cautious,
	Greedy,
	Vengeful,
}

// LivePetRead.Field in the Kotlin shell, in that order; HOST_GAME_PET_FIELDS counts them.
enum GamePetField {
	Life,
	Delegated,
	Member,
	BlockStarted,
	BlockEpoch,
	WorldDay,
	Level,
	Xp,
	Harvest,
	Burrow,
	Hearts,
	MaxHearts,
	Bonding,
	GrowthMultiplierBps,
	GrowthMultiplierExpiry,
	LastTickEpoch,
	Forage,
	Might,
	Grit,
	TalentKind,
	TalentBps,
	Tree,
	Persona,
	LineageGeneration,
	BornEpoch,
	ClaimedEpoch,
	DiedEpoch,
	GiftOwed,
	CommittedGiftOwed,
	PaidTotal,
	NameId,
	OwnerFirst,
	OwnerSecond,
	Insurance,
	Skin,
	SkrBalance,
	ItemsInTransit,
	WorldGenesisTimestamp,
	WorldRewardPerWorkPower,
	WorldRewardEpoch,
	WorldTotalWorkPower,
	WorldRecycledPending,
	WorldTreasury,
	WorldItemReserve,
	WorldEmitted,
	WorldLivingPets,
	WorldFloorSlots,
	HeadRarity,
	HeadStat,
	HeadWear,
	HeadSkill,
	HeadLevel,
	BodyRarity,
	BodyStat,
	BodyWear,
	BodySkill,
	BodyLevel,
	HandsRarity,
	HandsStat,
	HandsWear,
	HandsSkill,
	HandsLevel,
	FeetRarity,
	FeetStat,
	FeetWear,
	FeetSkill,
	FeetLevel,
}

// A validated canonical Pet as the shell read it; delegation, membership and the World day
// are facts for the live-game gate, not a verdict.
export struct GamePet {
	life: PetLife;
	delegated: boolean;
	member: boolean;
	blockStarted: boolean;
	blockEpoch: uint64;
	worldDay: uint64;
	level: int32;
	xp: uint32;
	harvest: uint64;
	burrow: uint64;
	hearts: int32;
	maxHearts: int32;
	bonding: int32;
	growthMultiplierBps: int32;
	growthMultiplierExpiry: uint64;
	lastTickEpoch: uint64;
	forage: int32;
	might: int32;
	grit: int32;
	talentKind: TalentKind;
	talentBps: int32;
	tree: uint64;
	persona: Persona;
	lineageGeneration: int32;
	bornEpoch: uint64;
	claimedEpoch: uint64;
	diedEpoch: uint64;
	giftOwed: uint64;
	committedGiftOwed: uint64;
	paidTotal: uint64;
	nameId: uint8;
	ownerFirst: OwnerItem;
	ownerSecond: OwnerItem;
	insurance: Insurance;
	skin: uint8;
	skrBalance: uint64;
	itemsInTransit: int32;
	// The ER World as of this read; all zero when the Pet is not placed on the ER.
	world: GlobalConfig;
	gear: Gear;
}

export const BLOCK_SEATS: int32 = 10;
export const FIGHT_RING: int32 = 32;
export const NO_SEAT: int32 = 255;

// LivePetRead.SeatKind in the Kotlin shell, in that order.
export enum SeatKind {
	Empty,
	Self,
	Living,
	Wild,
	Dead,
	Missing,
	Invalid,
}

// LivePetRead.SeatField in the Kotlin shell, in that order; HOST_GAME_SEAT_FIELDS counts them.
enum GameSeatField {
	Kind,
	Life,
	Level,
	Hearts,
	MaxHearts,
	Forage,
	Might,
	Grit,
	Mods,
	LootBps,
	BiteGuardBps,
	Harvest,
	Burrow,
	BornEpoch,
	LastTickEpoch,
	FightDay,
	FightsOutToday,
	FightsInToday,
	BitesInToday,
	SlotsAttackedToday,
	GrudgeSlot,
	Rage,
	RageEpoch,
	Region,
	Persona,
	LineageGeneration,
	TalentKind,
	TalentBps,
	BlockGrudgeRobber,
	BlockGrudgeEpoch,
	NameId,
	Tree,
	HeadRarity,
}

// LivePetRead.FightField in the Kotlin shell, in that order; HOST_GAME_FIGHT_FIELDS counts them.
enum GameFightField {
	Epoch,
	Seed,
	Stake,
	Loot,
	AttackerSeat,
	DefenderSeat,
	Rounds,
	AttackerWon,
	AttackerCombatant,
}

const ITEM_FIELDS: int32 = 5;
const GAME_PET_FIELDS: int32 = (GamePetField.FeetLevel as int32) + 1;
const INT32_LOW: int64 = -2147483648;
const INT32_HIGH: int64 = 2147483647;
const COMBATANT_FIELDS: int32 = 9;

// grudgeSlot and rage are the Pet's own; blockGrudge* is Block.grudges[seat], the program's
// record of who last robbed this seat, with epoch 0 for none (program/day.ms robberOf).
export struct GameNeighbour {
	seat: int32;
	kind: SeatKind;
	life: PetLife;
	level: int32;
	hearts: int32;
	maxHearts: int32;
	forage: int32;
	might: int32;
	grit: int32;
	mods: BitSet<Mod>;
	lootBps: int32;
	biteGuardBps: int32;
	harvest: uint64;
	burrow: uint64;
	bornEpoch: uint64;
	lastTickEpoch: uint64;
	fightDay: uint64;
	fightsOutToday: int32;
	fightsInToday: int32;
	bitesInToday: int32;
	slotsAttackedToday: BitSet<BlockSlot>;
	grudgeSlot: int32;
	rage: int32;
	rageEpoch: uint64;
	region: Region;
	persona: Persona;
	lineageGeneration: int32;
	talentKind: TalentKind;
	talentBps: int32;
	blockGrudgeRobber: int32;
	blockGrudgeEpoch: uint64;
	nameId: uint8;
	tree: uint64;
	gear: Gear;
}

export struct GameFight {
	epoch: uint64;
	seed: uint64;
	stake: uint64;
	loot: uint64;
	attackerSeat: int32;
	defenderSeat: int32;
	rounds: int32;
	outcome: Outcome;
	attacker: Combatant;
	defender: Combatant;
}

export struct GameRead {
	ownerRevision: int32;
	state: GameReadState;
	baseSlot: uint64;
	ephemeralSlot: uint64;
	admissionHoldings: int32;
	admissionMembers: int32;
	unclaimedMembers: int32;
	detail: string;
	ageSeconds: int64;
	pet: GamePet;
	seats: GameNeighbour[];
	fights: GameFight[];
}

export function noGamePet(): GamePet {
	return {
		life: PetLife.ClaimedUnplaced,
		delegated: false,
		member: false,
		blockStarted: false,
		blockEpoch: 0,
		worldDay: 0,
		level: 0,
		xp: 0,
		harvest: 0,
		burrow: 0,
		hearts: 0,
		maxHearts: 0,
		bonding: 0,
		growthMultiplierBps: 0,
		growthMultiplierExpiry: 0,
		lastTickEpoch: 0,
		forage: 0,
		might: 0,
		grit: 0,
		talentKind: TalentKind.None,
		talentBps: 0,
		tree: 0,
		persona: Persona.Cautious,
		lineageGeneration: 0,
		bornEpoch: 0,
		claimedEpoch: 0,
		diedEpoch: 0,
		giftOwed: 0,
		committedGiftOwed: 0,
		paidTotal: 0,
		nameId: 0,
		ownerFirst: OwnerItem.None,
		ownerSecond: OwnerItem.None,
		insurance: Insurance.None,
		skin: 0,
		skrBalance: 0,
		itemsInTransit: 0,
		world: {
			genesisTimestamp: 0,
			rewardPerWorkPower: 0,
			rewardEpoch: 0,
			totalWorkPower: 0,
			recycledPending: 0,
			treasury: 0,
			itemReserve: 0,
			emitted: 0,
			livingPets: 0,
			floorSlots: 0,
		},
		gear: Gear.bare(),
	};
}

function petField(field: GamePetField): int64 {
	return hostGameReadPetField(field as int32);
}

function petUnsigned(field: GamePetField): uint64 {
	return petField(field) as uint64;
}

function petBounded(field: GamePetField, low: int64, high: int64): Result<int32, GameReadError> {
	const value = petField(field);
	if (value < low || value > high) { return Result.err(GameReadError.InvalidState); }
	return Result.ok(value as int32);
}

function petFlag(field: GamePetField): Result<boolean, GameReadError> {
	const value = try petBounded(field, 0, 1);
	return Result.ok(value == 1);
}

// Head, body, hands, feet from GamePetField.HeadRarity on, ITEM_FIELDS each, as a seat publishes them.
// A worn item always carries the stat it raises; one without is a corrupt read.
function wornItem(item: Item): Result<Item, GameReadError> {
	if (item.rarity != 0 && item.stat == (TalentKind.None as uint8)) { return Result.err(GameReadError.InvalidState); }
	return Result.ok(item);
}

function petItem(slot: int32): Result<Item, GameReadError> {
	const first = (GamePetField.HeadRarity as int32) + slot * ITEM_FIELDS;
	return wornItem({
		rarity: (try petBounded((first as GamePetField), 0, 5)) as uint8,
		stat: (try petBounded(((first + 1) as GamePetField), 0, 3)) as uint8,
		wear: (try petBounded(((first + 2) as GamePetField), 0, 255)) as uint8,
		skill: (try petBounded(((first + 3) as GamePetField), 0, 3)) as uint8,
		level: (try petBounded(((first + 4) as GamePetField), 0, 255)) as uint8,
	});
}

function publishedPet(): Result<GamePet, GameReadError> {
	const life = try petBounded(GamePetField.Life, 0, 4);
	const talentKind = try petBounded(GamePetField.TalentKind, 0, 3);
	const persona = try petBounded(GamePetField.Persona, 0, 2);
	const xp = petField(GamePetField.Xp);
	const xpMaximum: int64 = 4294967295;
	if (xp < 0 || xp > xpMaximum) { return Result.err(GameReadError.InvalidState); }
	return Result.ok({
		life: life as PetLife,
		delegated: try petFlag(GamePetField.Delegated),
		member: try petFlag(GamePetField.Member),
		blockStarted: try petFlag(GamePetField.BlockStarted),
		blockEpoch: petUnsigned(GamePetField.BlockEpoch),
		worldDay: petUnsigned(GamePetField.WorldDay),
		level: try petBounded(GamePetField.Level, 0, 65535),
		xp: xp as uint32,
		harvest: petUnsigned(GamePetField.Harvest),
		burrow: petUnsigned(GamePetField.Burrow),
		hearts: try petBounded(GamePetField.Hearts, 0, 255),
		maxHearts: try petBounded(GamePetField.MaxHearts, 0, 255),
		bonding: try petBounded(GamePetField.Bonding, -128, 127),
		growthMultiplierBps: try petBounded(GamePetField.GrowthMultiplierBps, 0, 65535),
		growthMultiplierExpiry: petUnsigned(GamePetField.GrowthMultiplierExpiry),
		lastTickEpoch: petUnsigned(GamePetField.LastTickEpoch),
		forage: try petBounded(GamePetField.Forage, 0, 65535),
		might: try petBounded(GamePetField.Might, 0, 65535),
		grit: try petBounded(GamePetField.Grit, 0, 65535),
		talentKind: talentKind as TalentKind,
		talentBps: try petBounded(GamePetField.TalentBps, 0, 65535),
		tree: petUnsigned(GamePetField.Tree),
		persona: persona as Persona,
		lineageGeneration: try petBounded(GamePetField.LineageGeneration, 0, 65535),
		bornEpoch: petUnsigned(GamePetField.BornEpoch),
		claimedEpoch: petUnsigned(GamePetField.ClaimedEpoch),
		diedEpoch: petUnsigned(GamePetField.DiedEpoch),
		giftOwed: petUnsigned(GamePetField.GiftOwed),
		committedGiftOwed: petUnsigned(GamePetField.CommittedGiftOwed),
		paidTotal: petUnsigned(GamePetField.PaidTotal),
		nameId: (try petBounded(GamePetField.NameId, 0, 255)) as uint8,
		ownerFirst: (try petBounded(GamePetField.OwnerFirst, 0, 7)) as OwnerItem,
		ownerSecond: (try petBounded(GamePetField.OwnerSecond, 0, 7)) as OwnerItem,
		insurance: (try petBounded(GamePetField.Insurance, 0, 2)) as Insurance,
		skin: (try petBounded(GamePetField.Skin, 0, 255)) as uint8,
		skrBalance: petUnsigned(GamePetField.SkrBalance),
		itemsInTransit: try petBounded(GamePetField.ItemsInTransit, 0, 2147483647),
		world: {
			genesisTimestamp: petUnsigned(GamePetField.WorldGenesisTimestamp),
			rewardPerWorkPower: petUnsigned(GamePetField.WorldRewardPerWorkPower),
			rewardEpoch: petUnsigned(GamePetField.WorldRewardEpoch),
			totalWorkPower: petUnsigned(GamePetField.WorldTotalWorkPower),
			recycledPending: petUnsigned(GamePetField.WorldRecycledPending),
			treasury: petUnsigned(GamePetField.WorldTreasury),
			itemReserve: petUnsigned(GamePetField.WorldItemReserve),
			emitted: petUnsigned(GamePetField.WorldEmitted),
			livingPets: (try petBounded(GamePetField.WorldLivingPets, 0, 2147483647)) as uint32,
			floorSlots: (try petBounded(GamePetField.WorldFloorSlots, 0, 2147483647)) as uint32,
		},
		gear: { head: try petItem(0), body: try petItem(1), hands: try petItem(2), feet: try petItem(3) },
	});
}

function seatField(seat: int32, field: int32): int64 {
	return hostGameReadSeatField(seat, field);
}

function seatBounded(
	seat: int32,
	field: int32,
	low: int64,
	high: int64,
): Result<int32, GameReadError> {
	const value = seatField(seat, field);
	if (value < low || value > high) { return Result.err(GameReadError.InvalidState); }
	return Result.ok(value as int32);
}

function seatSmall(seat: int32, field: GameSeatField, high: int64): Result<int32, GameReadError> {
	return seatBounded(seat, field as int32, 0, high);
}

function seatInt32(seat: int32, field: GameSeatField): Result<int32, GameReadError> {
	return seatBounded(seat, field as int32, INT32_LOW, INT32_HIGH);
}

function seatUnsigned(seat: int32, field: GameSeatField): uint64 {
	return seatField(seat, field as int32) as uint64;
}

function publishedItem(seat: int32, slot: int32): Result<Item, GameReadError> {
	const first = (GameSeatField.HeadRarity as int32) + slot * ITEM_FIELDS;
	return wornItem({
		rarity: (try seatBounded(seat, first, 0, 5)) as uint8,
		stat: (try seatBounded(seat, first + 1, 0, 3)) as uint8,
		wear: (try seatBounded(seat, first + 2, 0, 255)) as uint8,
		skill: (try seatBounded(seat, first + 3, 0, 3)) as uint8,
		level: (try seatBounded(seat, first + 4, 0, 255)) as uint8,
	});
}

function publishedSeat(seat: int32): Result<GameNeighbour, GameReadError> {
	const grudgeSlot = try seatSmall(seat, GameSeatField.GrudgeSlot, 255);
	if (grudgeSlot >= BLOCK_SEATS && grudgeSlot != NO_SEAT) {
		return Result.err(GameReadError.InvalidState);
	}
	const slotsAttacked = try seatSmall(seat, GameSeatField.SlotsAttackedToday, 1023);
	return Result.ok({
		seat: seat,
		kind: (try seatSmall(seat, GameSeatField.Kind, 6)) as SeatKind,
		life: (try seatSmall(seat, GameSeatField.Life, 4)) as PetLife,
		level: try seatSmall(seat, GameSeatField.Level, 65535),
		hearts: try seatSmall(seat, GameSeatField.Hearts, 255),
		maxHearts: try seatSmall(seat, GameSeatField.MaxHearts, 255),
		forage: try seatSmall(seat, GameSeatField.Forage, 65535),
		might: try seatSmall(seat, GameSeatField.Might, 65535),
		grit: try seatSmall(seat, GameSeatField.Grit, 65535),
		mods: modsFromMask(try seatSmall(seat, GameSeatField.Mods, 255)),
		lootBps: try seatInt32(seat, GameSeatField.LootBps),
		biteGuardBps: try seatInt32(seat, GameSeatField.BiteGuardBps),
		harvest: seatUnsigned(seat, GameSeatField.Harvest),
		burrow: seatUnsigned(seat, GameSeatField.Burrow),
		bornEpoch: seatUnsigned(seat, GameSeatField.BornEpoch),
		lastTickEpoch: seatUnsigned(seat, GameSeatField.LastTickEpoch),
		fightDay: seatUnsigned(seat, GameSeatField.FightDay),
		fightsOutToday: try seatSmall(seat, GameSeatField.FightsOutToday, 255),
		fightsInToday: try seatSmall(seat, GameSeatField.FightsInToday, 255),
		bitesInToday: try seatSmall(seat, GameSeatField.BitesInToday, 255),
		slotsAttackedToday: (slotsAttacked as uint16) as BitSet<BlockSlot>,
		grudgeSlot: grudgeSlot,
		rage: try seatSmall(seat, GameSeatField.Rage, 255),
		rageEpoch: seatUnsigned(seat, GameSeatField.RageEpoch),
		region: (try seatSmall(seat, GameSeatField.Region, 2)) as Region,
		persona: (try seatSmall(seat, GameSeatField.Persona, 2)) as Persona,
		lineageGeneration: try seatSmall(seat, GameSeatField.LineageGeneration, 65535),
		talentKind: (try seatSmall(seat, GameSeatField.TalentKind, 3)) as TalentKind,
		talentBps: try seatSmall(seat, GameSeatField.TalentBps, 65535),
		blockGrudgeRobber: try seatSmall(seat, GameSeatField.BlockGrudgeRobber, 9),
		blockGrudgeEpoch: seatUnsigned(seat, GameSeatField.BlockGrudgeEpoch),
		nameId: (try seatSmall(seat, GameSeatField.NameId, 255)) as uint8,
		tree: seatUnsigned(seat, GameSeatField.Tree),
		gear: {
			head: try publishedItem(seat, 0),
			body: try publishedItem(seat, 1),
			hands: try publishedItem(seat, 2),
			feet: try publishedItem(seat, 3),
		},
	});
}

function publishedSeats(): Result<GameNeighbour[], GameReadError> {
	const count = hostGameReadSeatCount();
	if (count != 0 && count != BLOCK_SEATS) { return Result.err(GameReadError.InvalidState); }
	const seats: GameNeighbour[] = [];
	let selves = 0;
	for (let seat: int32 = 0; seat < count; seat += 1) {
		const published = try publishedSeat(seat);
		if (published.kind == SeatKind.Self) { selves += 1; }
		seats.push(published);
	}
	if (count != 0 && selves != 1) { return Result.err(GameReadError.InvalidState); }
	return Result.ok(seats);
}

function fightInt32(fight: int32, field: int32): Result<int32, GameReadError> {
	const value = hostGameReadFightField(fight, field);
	if (value < INT32_LOW || value > INT32_HIGH) { return Result.err(GameReadError.InvalidState); }
	return Result.ok(value as int32);
}

function fightSeat(fight: int32, field: GameFightField): Result<int32, GameReadError> {
	const seat = try fightInt32(fight, field as int32);
	if (seat < 0 || seat >= BLOCK_SEATS) { return Result.err(GameReadError.InvalidState); }
	return Result.ok(seat);
}

function publishedCombatant(fight: int32, at: int32): Result<Combatant, GameReadError> {
	const mods = try fightInt32(fight, at + 8);
	if (mods < 0 || mods > 255) { return Result.err(GameReadError.InvalidState); }
	return Result.ok({
		might: try fightInt32(fight, at),
		grit: try fightInt32(fight, at + 1),
		speed: try fightInt32(fight, at + 2),
		armor: try fightInt32(fight, at + 3),
		accuracy: try fightInt32(fight, at + 4),
		lifesteal: try fightInt32(fight, at + 5),
		bleed: try fightInt32(fight, at + 6),
		hearts: try fightInt32(fight, at + 7),
		mods: modsFromMask(mods),
	});
}

function publishedFight(fight: int32): Result<GameFight, GameReadError> {
	const attackerSeat = try fightSeat(fight, GameFightField.AttackerSeat);
	const defenderSeat = try fightSeat(fight, GameFightField.DefenderSeat);
	const won = try fightInt32(fight, GameFightField.AttackerWon as int32);
	if (attackerSeat == defenderSeat || won < 0 || won > 1) {
		return Result.err(GameReadError.InvalidState);
	}
	const attackerFirst = GameFightField.AttackerCombatant as int32;
	return Result.ok({
		epoch: hostGameReadFightField(fight, GameFightField.Epoch as int32) as uint64,
		seed: hostGameReadFightField(fight, GameFightField.Seed as int32) as uint64,
		stake: hostGameReadFightField(fight, GameFightField.Stake as int32) as uint64,
		loot: hostGameReadFightField(fight, GameFightField.Loot as int32) as uint64,
		attackerSeat: attackerSeat,
		defenderSeat: defenderSeat,
		rounds: try fightInt32(fight, GameFightField.Rounds as int32),
		outcome: won == 1 ? Outcome.AttackerWins : Outcome.DefenderWins,
		attacker: try publishedCombatant(fight, attackerFirst),
		defender: try publishedCombatant(fight, attackerFirst + COMBATANT_FIELDS),
	});
}

function publishedFights(): Result<GameFight[], GameReadError> {
	const count = hostGameReadFightCount();
	if (count < 0 || count > FIGHT_RING) { return Result.err(GameReadError.InvalidState); }
	const fights: GameFight[] = [];
	for (let fight: int32 = 0; fight < count; fight += 1) {
		fights.push(try publishedFight(fight));
	}
	return Result.ok(fights);
}

export function gameRead(): Result<GameRead, GameReadError> {
	const ownerRevision = hostGameOwnerRevision();
	const revision = hostGameReadRevision();
	if (ownerRevision % 2 != 0 || revision % 2 != 0) {
		return Result.err(GameReadError.Updating);
	}
	const state = hostGameReadState();
	if (state < 0 || state > 5) { return Result.err(GameReadError.InvalidState); }
	const bytes: uint8[] = [];
	for (let index: int32 = 0; index < 128; index += 1) {
		const value = hostGameReadDetailByte(index);
		if (value == 0) { break; }
		bytes.push(value as uint8);
	}
	let snapshot: GameRead = {
		ownerRevision: ownerRevision,
		state: state as GameReadState,
		baseSlot: hostGameReadBaseSlot(),
		ephemeralSlot: hostGameReadEphemeralSlot(),
		admissionHoldings: hostGameReadAdmissionHoldings(),
		admissionMembers: hostGameReadAdmissionMembers(),
		unclaimedMembers: hostGameReadUnclaimedMembers(),
		detail: bytes.asString(),
		ageSeconds: hostGameReadAgeSeconds(),
		pet: noGamePet(),
		seats: [],
		fights: [],
	};
	if (snapshot.state == GameReadState.PetFound) {
		snapshot.pet = try publishedPet();
		snapshot.seats = try publishedSeats();
		snapshot.fights = try publishedFights();
		if (snapshot.pet.member != (snapshot.seats.length != 0)) {
			return Result.err(GameReadError.InvalidState);
		}
	}
	if (hostGameOwnerRevision() != ownerRevision || hostGameReadRevision() != revision) {
		return Result.err(GameReadError.Updating);
	}
	return Result.ok(snapshot);
}

extern function hostSetGameOwner(state: int32, publicKey: Borrow<uint8>, length: int32): void;
extern function hostSetGameRead(
	ownerRevision: int32,
	state: int32,
	baseSlot: uint64,
	ephemeralSlot: uint64,
	admissionHoldings: int32,
	admissionMembers: int32,
	unclaimedMembers: int32,
	detail: Borrow<uint8>,
	pet: Borrow<int64>,
	petFields: int32,
	seats: Borrow<int64>,
	seatValues: int32,
	fights: Borrow<int64>,
	fightValues: int32,
): int32;

const SEAT_FIELDS: int32 = (GameSeatField.HeadRarity as int32) + 4 * ITEM_FIELDS;
const FIGHT_FIELDS: int32 = 26;

function publishedRead(
	seats: int64[],
	seatValues: int32,
	fights: int64[],
	fightValues: int32,
): int32 {
	const detail: uint8[] = [79, 75, 0];
	let pet: int64[] = [];
	for (let field = 0; field < GAME_PET_FIELDS; field++) { pet.push(0); }
	pet[GamePetField.Member as int32] = seatValues == 0 ? 0 : 1;
	return hostSetGameRead(
		hostGameOwnerRevision(),
		3,
		10,
		20,
		1,
		1,
		0,
		detail[0],
		pet[0],
		GAME_PET_FIELDS,
		seats[0],
		seatValues,
		fights[0],
		fightValues,
	);
}

function blockSeats(selfSeat: int32): int64[] {
	let seats: int64[] = [];
	for (let value = 0; value < BLOCK_SEATS * SEAT_FIELDS; value++) { seats.push(0); }
	for (let seat = 0; seat < BLOCK_SEATS; seat++) {
		const other = seat == 2 ? SeatKind.Empty : SeatKind.Living;
		const kind = seat == selfSeat ? SeatKind.Self : other;
		seats[seat * SEAT_FIELDS] = kind as int64;
		seats[seat * SEAT_FIELDS + (GameSeatField.Might as int32)] = (60 + seat) as int64;
		seats[seat * SEAT_FIELDS + (GameSeatField.GrudgeSlot as int32)] = NO_SEAT as int64;
	}
	seats[7 * SEAT_FIELDS + (GameSeatField.BlockGrudgeRobber as int32)] = 4;
	seats[7 * SEAT_FIELDS + (GameSeatField.BlockGrudgeEpoch as int32)] = 41;
	seats[7 * SEAT_FIELDS + (GameSeatField.HeadRarity as int32) + 5] = 3;
	seats[7 * SEAT_FIELDS + (GameSeatField.HeadRarity as int32) + 6] = TalentKind.Grit as int64;
	return seats;
}

function ringFight(): int64[] {
	let fight: int64[] = [];
	for (let field = 0; field < FIGHT_FIELDS + 1; field++) { fight.push(0); }
	fight[GameFightField.Epoch as int32] = 41;
	fight[GameFightField.Loot as int32] = 900;
	fight[GameFightField.AttackerSeat as int32] = 4;
	fight[GameFightField.DefenderSeat as int32] = 7;
	fight[GameFightField.AttackerWon as int32] = 1;
	fight[(GameFightField.AttackerCombatant as int32) + COMBATANT_FIELDS] = 66;
	return fight;
}

test "the shell's Block seats and fight ring reach the core only whole" {
	const key: uint8[] = [];
	for (let index = 0; index < 32; index++) { key.push(7); }
	hostSetGameOwner(1, key[0], 32);
	const fight = ringFight();
	assert publishedRead(blockSeats(4), BLOCK_SEATS * SEAT_FIELDS, fight, FIGHT_FIELDS) == 1;
	assert hostGameReadState() == 3;
	const read = gameRead();
	assert read.ok;
	if (read.ok) {
		assert read.value.seats.length == BLOCK_SEATS && read.value.fights.length == 1;
		assert read.value.seats[4].kind == SeatKind.Self;
		assert read.value.seats[2].kind == SeatKind.Empty;
		assert read.value.seats[9].might == 69 && read.value.seats[7].blockGrudgeRobber == 4;
		assert read.value.seats[7].gear.body.rarity == 3;
		assert read.value.seats[7].gear.body.stat == (TalentKind.Grit as uint8);
		assert read.value.fights[0].defenderSeat == 7 && read.value.fights[0].loot == 900;
		assert read.value.fights[0].outcome == Outcome.AttackerWins;
		assert read.value.fights[0].defender.might == 66;
	}
	const statless = blockSeats(4);
	statless[7 * SEAT_FIELDS + (GameSeatField.HeadRarity as int32) + 6] = TalentKind.None as int64;
	assert publishedRead(statless, BLOCK_SEATS * SEAT_FIELDS, fight, FIGHT_FIELDS) == 1;
	const refused = gameRead();
	assert !refused.ok && refused.error == GameReadError.InvalidState;
	const wholeSeats = BLOCK_SEATS * SEAT_FIELDS;
	for (const seatValues of [wholeSeats - 1, wholeSeats + 1, SEAT_FIELDS]) {
		assert publishedRead(blockSeats(4), seatValues, fight, FIGHT_FIELDS) == 1;
		assert hostGameReadState() == 5 && hostGameReadSeatCount() == 0;
	}
	const overRing = (FIGHT_RING + 1) * FIGHT_FIELDS;
	for (const fightValues of [FIGHT_FIELDS - 1, FIGHT_FIELDS + 1, overRing]) {
		assert publishedRead(blockSeats(4), BLOCK_SEATS * SEAT_FIELDS, fight, fightValues) == 1;
		assert hostGameReadState() == 5 && hostGameReadFightCount() == 0;
	}
	assert publishedRead(blockSeats(4), 0, fight, FIGHT_FIELDS) == 1;
	assert hostGameReadState() == 5;
	assert publishedRead(blockSeats(4), 0, fight, 0) == 1;
	assert hostGameReadState() == 3;
	const unseated = gameRead();
	assert unseated.ok;
	if (unseated.ok) { assert unseated.value.seats.length == 0 && !unseated.value.pet.member; }
	assert publishedRead(blockSeats(10), BLOCK_SEATS * SEAT_FIELDS, fight, 0) == 1;
	assert hostGameReadState() == 3;
	const selfless = gameRead();
	assert !selfless.ok;
	hostSetGameOwner(0, key[0], 0);
}
