import { Discriminator, ProgramError, Pubkey, Seeds, accountDiscriminator } from "std/solana";
import { EPOCH_SECONDS, FightRecord, GlobalConfig, Listing, Pet } from "../rules/index";

export const SEATS: int32 = 10;
export const FIGHTS: int32 = 32;
export const LISTINGS: int32 = 10;
export const RELATIONSHIPS: int32 = 45;
export const POLICY_BYTES: int32 = 4763;
export const MAX_PETS: int32 = 80_000;
export const RESORT_BITMAP_BYTES: int32 = 10_000;
export const NO_SEAT: uint8 = 255;
export const NO_BLOCK: uint32 = 0xffffffff;
export const NEVER_DAWNED: uint64 = 0xffffffffffffffff;

export enum Op {
	Initialize,
	WritePolicy,
	CreateBlock,
	Claim,
	DelegatePet,
	DelegateBlock,
	DelegateWorld,
	ProcessUndelegation,
	Place,
	Seeded,
	Talk,
	Bank,
	Buy,
	Load,
	ResortBegin,
	ResortClear,
	ResortAssign,
	ResortFinish,
	DelegateResort,
	DelegateVrfPayer,
	CommitPet,
	ClaimReward,
	StartBlock,
	RoundStart,
	Turn,
	Sweep,
	WithdrawRevenue,
}

export enum Phase {
	Idle,
	Seeding,
	Acting,
}

export struct Config {
	authority: Pubkey;
	admissionGroup: Pubkey;
	hbrnMint: Pubkey;
	engine: uint64;
	genesisTimestamp: uint64;
	claimCapPerDay: uint64;
	blocks: uint32;
	pets: uint32;
	bump: uint8;
	mintBump: uint8;
	policyBump: uint8;
	worldBump: uint8;
	pad: uint32;
	validator: Pubkey;
	skrMint: Pubkey;
	treasury: Pubkey;
	vrfQueue: Pubkey;
	secondsPerDay: uint64;
	staggerSeconds: uint64;
	slotMillis: uint64;
	turnGapSlots: uint64;
}

export function discriminator(this typeof Config): Discriminator {
	return @comptime { return accountDiscriminator("Config"); };
}

export struct Policy {
	engine: uint64;
	written: uint32;
	sealed: uint8;
	bump: uint8;
	pad: uint16;
	bytes: uint8[4763];
}

export function discriminator(this typeof Policy): Discriminator {
	return @comptime { return accountDiscriminator("Policy"); };
}

export struct World {
	global: GlobalConfig;
	epoch: uint64;
	resortEvery: uint64;
	rotation: uint64;
	resortedEpoch: uint64;
	bump: uint8;
	resorting: uint8;
	pad: uint16;
	unplaced: uint32;
	placed: uint32;
	pad2: uint32;
	secondsPerDay: uint64;
}

export function discriminator(this typeof World): Discriminator {
	return @comptime { return accountDiscriminator("World"); };
}

export struct Grudge {
	robber: uint8;
	pad: uint8[7];
	epoch: uint64;
}

export struct Block {
	id: uint32;
	filled: uint8;
	phase: uint8;
	round: uint8;
	cursor: uint8;
	epoch: uint64;
	roundSeed: uint64;
	requests: uint64;
	pendingRequest: uint64;
	requestedAt: int64;
	rotation: uint64;
	minStrength: uint64;
	maxStrength: uint64;
	crankSeq: uint64;
	dueSlot: uint64;
	dawnedEpoch: uint64;
	fightHead: uint8;
	bump: uint8;
	turns: uint8[10];
	started: uint8;
	pad: uint8[3];
	members: Pubkey[10];
	grudges: Grudge[10];
	fights: FightRecord[32];
	listings: Listing[10];
	listed: uint8[10];
	relationships: int8[45];
	pad2: uint8;
}

export function discriminator(this typeof Block): Discriminator {
	return @comptime { return accountDiscriminator("Block"); };
}

export struct PetAccount {
	owner: Pubkey;
	mint: Pubkey;
	ordinal: uint32;
	persona: uint8;
	bump: uint8;
	pad: uint16;
	claimedEpoch: uint64;
	diedEpoch: uint64;
	loaded: uint32[7];
	pad2: uint32;
	pet: Pet;
}

export function discriminator(this typeof PetAccount): Discriminator {
	return @comptime { return accountDiscriminator("PetAccount"); };
}

export struct Paid {
	mint: Pubkey;
	total: uint64;
	day: uint64;
	today: uint64;
	bump: uint8;
	pad: uint8[7];
}

export function discriminator(this typeof Paid): Discriminator {
	return @comptime { return accountDiscriminator("Paid"); };
}

export struct Resort {
	rotation: uint64;
	count: uint64;
	assigned: uint64;
	measure: uint8;
	bump: uint8;
	pad: uint16;
	cleared: uint32;
	bitmap: uint8[10000];
}

export function discriminator(this typeof Resort): Discriminator {
	return @comptime { return accountDiscriminator("Resort"); };
}

export struct VrfPayer {
	bump: uint8;
	pad: uint8[7];
}

export function discriminator(this typeof VrfPayer): Discriminator {
	return @comptime { return accountDiscriminator("VrfPayer"); };
}

export enum HibernalError {
	NotAuthority,
	PolicySealed,
	PolicyOutOfRange,
	PolicyUnsealed,
	EngineMismatch,
	NotAdmitted,
	NotTheOwner,
	BlockFull,
	AlreadyPlaced,
	NotPlaced,
	WrongBlock,
	NotAMember,
	WrongPhase,
	TooEarly,
	Pending,
	StaleCallback,
	Tick,
	Illegal,
	Dead,
	Resorting,
	OutOfOrder,
	AlreadyAssigned,
	Unfinished,
	WrongMint,
	NothingOwed,
	Rules,
	Refused,
	Full,
	FedToday,
	TalkedOut,
	Insured,
	EmptyHarvest,
	CoolingDown,
	NoSuchFood,
	OverCap,
	NoSuchItem,
	StaleStep,
	ChainAlive,
	NotIdle,
	BadClock,
	PetCap,
	TreasuryShort,
	SupplyCap,
	WrongTreasury,
	SlotsFull,
}

export converter hibernalError(error: HibernalError): ProgramError {
	return ProgramError.userError(error as uint32);
}

export function configSeeds(): Seeds {
	return Seeds.empty(1).addText("config");
}

export function policySeeds(): Seeds {
	return Seeds.empty(1).addText("policy");
}

export function worldSeeds(): Seeds {
	return Seeds.empty(1).addText("world");
}

export function mintSeeds(): Seeds {
	return Seeds.empty(1).addText("mint");
}

export function revenueSeeds(): Seeds {
	return Seeds.empty(1).addText("revenue");
}

export function resortSeeds(): Seeds {
	return Seeds.empty(1).addText("resort");
}

export function vrfPayerSeeds(): Seeds {
	return Seeds.empty(1).addText("vrf-payer");
}

export function blockSeeds(id: uint32): Seeds {
	return Seeds.empty(2).addText("block").addU64(id as uint64);
}

export function petSeeds(mint: Pubkey): Seeds {
	return Seeds.empty(2).addText("pet").addPubkey(mint);
}

export enum ShopItem {
	Food,
	Growth,
	Insurance,
	Skin,
}

export const OWNER_ITEM_KINDS: int32 = 7;

export struct Ledger {
	mint: Pubkey;
	bought: uint32[7];
	skin: uint8;
	bump: uint8;
	pad: uint16;
}

export function discriminator(this typeof Ledger): Discriminator {
	return @comptime { return accountDiscriminator("Ledger"); };
}

export function ledgerSeeds(mint: Pubkey): Seeds {
	return Seeds.empty(2).addText("ledger").addPubkey(mint);
}

export function paidSeeds(mint: Pubkey): Seeds {
	return Seeds.empty(2).addText("paid").addPubkey(mint);
}

export struct WithdrawRevenueArgs {
	amount: uint64;
}

export struct InitializeArgs {
	admissionGroup: Pubkey;
	engine: uint64;
	genesisTimestamp: uint64;
	claimCapPerDay: uint64;
	resortEvery: uint64;
	validator: Pubkey;
	skrMint: Pubkey;
	treasury: Pubkey;
	vrfQueue: Pubkey;
	secondsPerDay: uint64;
	staggerSeconds: uint64;
	slotMillis: uint64;
	turnGapSlots: uint64;
}

export struct CreateBlockArgs {
	id: uint32;
}

export struct BuyArgs {
	item: uint8;
	tier: uint8;
}

export struct ResortBeginArgs {
	measure: uint8;
	count: uint64;
}

export struct ResortAssignArgs {
	offset: uint64;
}

export struct SeededArgs {
	randomness: Pubkey;
	request: uint64;
}

export struct StepArgs {
	seq: uint64;
}

export struct StartBlockArgs {
	id: uint32;
}

export function dayAt(genesisTimestamp: uint64, secondsPerDay: uint64, unixTimestamp: int64): uint64 {
	if (unixTimestamp < 0 || (unixTimestamp as uint64) < genesisTimestamp) { return 0; }
	return ((unixTimestamp as uint64) - genesisTimestamp) / secondsPerDay;
}

export function gameSecondsAt(genesisTimestamp: uint64, secondsPerDay: uint64, unixTimestamp: int64): uint64 {
	if (unixTimestamp < 0 || (unixTimestamp as uint64) < genesisTimestamp) { return 0; }
	return ((unixTimestamp as uint64) - genesisTimestamp) * EPOCH_SECONDS / secondsPerDay;
}

export function dayOf(config: Readonly<Ptr<Config>>, unixTimestamp: int64): uint64 {
	return dayAt(config.genesisTimestamp, config.secondsPerDay, unixTimestamp);
}
