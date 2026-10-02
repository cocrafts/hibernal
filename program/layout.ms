import { Discriminator, ProgramError, Pubkey, Seeds, accountDiscriminator } from "std/solana";
import { FightRecord, GlobalConfig, Listing, Pet } from "../rules/index";

export const SEATS: int32 = 10;
export const FIGHTS: int32 = 32;
export const LISTINGS: int32 = 10;
export const RELATIONSHIPS: int32 = 45;
export const POLICY_BYTES: int32 = 4763;
export const MAX_PETS: int32 = 10_000;
export const RESORT_BITMAP_BYTES: int32 = 1_250;
export const NO_SEAT: uint8 = 255;
export const NO_BLOCK: uint32 = 0xffffffff;

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
	Step,
	Seeded,
	Talk,
	Bank,
	Buy,
	Consume,
	ResortBegin,
	ResortClear,
	ResortAssign,
	ResortFinish,
	DelegateResort,
	DelegateVrfPayer,
	CommitPet,
	ClaimReward,
}

export enum Phase {
	Dawn,
	Seeding,
	Acting,
	Dusk,
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
	fightHead: uint8;
	bump: uint8;
	turns: uint8[10];
	pad: uint32;
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
	bitmap: uint8[1250];
	pad2: uint8[6];
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
	AlreadyConsumed,
	WrongReceipt,
	AlreadyBought,
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

export struct Receipt {
	pet: Pubkey;
	owner: Pubkey;
	nonce: uint64;
	price: uint64;
	item: uint8;
	tier: uint8;
	consumed: uint8;
	bump: uint8;
	pad: uint32;
}

export function discriminator(this typeof Receipt): Discriminator {
	return @comptime { return accountDiscriminator("Receipt"); };
}

export function receiptSeeds(pet: Pubkey, nonce: uint64): Seeds {
	return Seeds.empty(3).addText("receipt").addPubkey(pet).addU64(nonce);
}

export function paidSeeds(mint: Pubkey): Seeds {
	return Seeds.empty(2).addText("paid").addPubkey(mint);
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
}

export struct CreateBlockArgs {
	id: uint32;
}

export struct BuyArgs {
	item: uint8;
	tier: uint8;
	nonce: uint64;
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
