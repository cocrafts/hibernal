import {
	Account,
	Delegated,
	External,
	ExternalMutable,
	Mutable,
	Owned,
	Program,
	ProgramError,
	Pubkey,
	System,
	Writable,
	WritableSigner,
	clock,
	createPda,
	expectAddress,
	expectHasOne,
	pdaWithBump,
	programId,
	readArgs,
	selectInstruction,
} from "std/solana";
import { accounts, args } from "std/solana/macro";
import { DelegationAccounts } from "std/solana/magicblock";
import { Mint, TokenAccount, transferTokens } from "std/solana/token";
import { Food, OwnerError, Pet, epochOf, grownBy, insured, ownerFed } from "../rules/index";
import { delegated } from "./admission";
import {
	BuyArgs,
	Config,
	HibernalError,
	PetAccount,
	Receipt,
	ShopItem,
	World,
	configSeeds,
	hibernalError,
	petSeeds,
	receiptSeeds,
	worldSeeds,
} from "./layout";
import { ownerFailure } from "./owner";

export const FOOD_PRICE_SKR: uint64[3] = [1, 2, 3];
export const GROWTH_PRICE_SKR_PER_STEP: uint64 = 2;
export const INSURANCE_PRICE_SKR: uint64 = 20;
export const SKIN_PRICE_SKR: uint64 = 5;
export const SKINS: uint8 = 2;
export const INSURANCE_NONCE_BASE: uint64 = 0xffffffff00000000;

export struct BuyAccounts {
	owner: WritableSigner;
	config: Owned<Config>;
	pet: Delegated<PetAccount>;
	skrMint: External<Mint>;
	source: ExternalMutable<TokenAccount>;
	treasury: ExternalMutable<TokenAccount>;
	receipt: Writable;
	ownerProgram: Account;
	buffer: Writable;
	delegationRecord: Writable;
	delegationMetadata: Writable;
	delegationProgram: Account;
	tokenProgram: Account;
	systemProgram: Program<System>;
}

export struct ConsumeAccounts {
	receipt: Mutable<Receipt>;
	pet: Mutable<PetAccount>;
	world: Owned<World>;
}

function itemOf(value: uint8): Result<ShopItem, ProgramError> {
	const item: Result<ShopItem, ProgramError> = match (value) {
		0 => Result.ok(ShopItem.Food),
		1 => Result.ok(ShopItem.Growth),
		2 => Result.ok(ShopItem.Insurance),
		3 => Result.ok(ShopItem.Skin),
		_ => Result.err(hibernalError(HibernalError.NoSuchItem)),
	};
	return item;
}

function foodEffect(pet: Pet, tier: uint8): Result<Pet, OwnerError> {
	const fed: Result<Pet, OwnerError> = match (tier) {
		0 => pet.ownerFed(Food.Small),
		1 => pet.ownerFed(Food.Medium),
		2 => pet.ownerFed(Food.Large),
		_ => Result.err(OwnerError.NoSuchTier),
	};
	return fed;
}

function shopEffect(pet: Pet, item: ShopItem, tier: uint8, epoch: uint64): Result<Pet, OwnerError> {
	const applied: Result<Pet, OwnerError> = match (item) {
		ShopItem.Food => foodEffect(pet, tier),
		ShopItem.Growth => pet.grownBy((tier as int32) + 1, epoch),
		ShopItem.Insurance => pet.insured(),
		ShopItem.Skin => Result.ok(pet),
	};
	return applied;
}

function wholePrice(item: ShopItem, tier: uint8): Result<uint64, ProgramError> {
	const price: Result<uint64, ProgramError> = match (item) {
		ShopItem.Food => tier < 3 ? Result.ok(FOOD_PRICE_SKR[tier]) : Result.err(hibernalError(HibernalError.NoSuchFood)),
		ShopItem.Growth => tier < 3 ? Result.ok(GROWTH_PRICE_SKR_PER_STEP * ((tier as uint64) + 1)) : Result.err(hibernalError(HibernalError.NoSuchItem)),
		ShopItem.Insurance => tier == 0 ? Result.ok(INSURANCE_PRICE_SKR) : Result.err(hibernalError(HibernalError.NoSuchItem)),
		ShopItem.Skin => tier < SKINS ? Result.ok(SKIN_PRICE_SKR) : Result.err(hibernalError(HibernalError.NoSuchItem)),
	};
	return price;
}

function baseUnits(whole: uint64, decimals: uint8): Result<uint64, ProgramError> {
	let amount = whole;
	for (let step: uint8 = 0; step < decimals; step++) {
		if (amount > 0xffffffffffffffff / 10) { return Result.err(ProgramError.arithmeticOverflow()); }
		amount = amount * 10;
	}
	return Result.ok(amount);
}

function configIn(config: Owned<Config>): Result<Readonly<Ptr<Config>>, ProgramError> {
	const stored = config.data();
	const derived = configSeeds().withBump(stored.bump).createProgramAddress(programId());
	if (!derived.ok || derived.value != config.key()) { return Result.err(ProgramError.constraintSeeds()); }
	return Result.ok(stored);
}

function worldIn(world: Owned<World>): Result<Readonly<Ptr<World>>, ProgramError> {
	const stored = world.data();
	const derived = worldSeeds().withBump(stored.bump).createProgramAddress(programId());
	if (!derived.ok || derived.value != world.key()) { return Result.err(ProgramError.constraintSeeds()); }
	return Result.ok(stored);
}

export function buy(): Result<uint64, ProgramError> {
	const a = try args<BuyArgs>();
	const item = try itemOf(a.item);
	const whole = try wholePrice(item, a.tier);
	const x = try accounts<BuyAccounts>();
	const config = try configIn(x.config);
	const record = x.pet.data();
	const _petAddress = try pdaWithBump(x.pet, petSeeds(record.mint), record.bump);
	const _owner = try expectHasOne(record.owner, x.owner.key());
	const _skrMint = try expectAddress(x.skrMint.key(), config.skrMint);
	const _treasury = try expectAddress(x.treasury.key(), config.treasury);
	const nonce = item == ShopItem.Insurance ? INSURANCE_NONCE_BASE + (record.pet.lineageGeneration as uint64) : a.nonce;
	if (item != ShopItem.Insurance && nonce >= INSURANCE_NONCE_BASE) { return Result.err(hibernalError(HibernalError.WrongReceipt)); }
	if (!(x.receipt as Account).isOwnedBy(Pubkey.systemProgram())) { return Result.err(hibernalError(HibernalError.AlreadyBought)); }
	const decimals = (try x.skrMint.read()).decimals;
	const price = try baseUnits(whole, decimals);
	const _paid = try transferTokens(x.source, x.treasury, x.skrMint, x.owner.asSigner(), price);
	const made = try createPda<Receipt>(x.owner, x.receipt, receiptSeeds(x.pet.key(), nonce));
	const receipt = made.account.data();
	receipt.pet = x.pet.key();
	receipt.owner = x.owner.key();
	receipt.nonce = nonce;
	receipt.price = price;
	receipt.item = item as uint8;
	receipt.tier = a.tier;
	receipt.bump = made.bump;
	const request: DelegationAccounts = {
		payer: x.owner as Account,
		delegated: made.account as Account,
		ownerProgram: x.ownerProgram,
		buffer: x.buffer as Account,
		delegationRecord: x.delegationRecord as Account,
		delegationMetadata: x.delegationMetadata as Account,
		systemProgram: x.systemProgram as Account,
	};
	return delegated(request, x.delegationProgram, receiptSeeds(x.pet.key(), nonce), made.bump, config);
}

export function consume(): Result<uint64, ProgramError> {
	const x = try accounts<ConsumeAccounts>();
	const receipt = x.receipt.data();
	const _receiptAddress = try pdaWithBump(x.receipt, receiptSeeds(receipt.pet, receipt.nonce), receipt.bump);
	if (receipt.consumed != 0) { return Result.err(hibernalError(HibernalError.AlreadyConsumed)); }
	const _pet = try expectHasOne(receipt.pet, x.pet.key());
	const record = x.pet.data();
	const _petAddress = try pdaWithBump(x.pet, petSeeds(record.mint), record.bump);
	const world = try worldIn(x.world);
	const item = try itemOf(receipt.item);
	const epoch = epochOf(clock().unixTimestamp as uint64, world.global.genesisTimestamp);
	const applied = shopEffect(record.pet, item, receipt.tier, epoch);
	if (!applied.ok) { return Result.err(ownerFailure(applied.error)); }
	record.pet = applied.value;
	receipt.consumed = 1;
	return Result.ok(receipt.nonce);
}
