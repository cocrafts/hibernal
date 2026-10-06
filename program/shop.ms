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
	SYSTEM_PROGRAM_ID,
	System,
	Writable,
	WritableSigner,
	createPda,
	expectAddress,
	expectHasOne,
	mutable,
	pdaWithBump,
	programAddress,
} from "std/solana";
import { accounts, args } from "std/solana/macro";
import { Mint, TokenAccount, transferTokens } from "std/solana/token";
import { Food, OwnerItem, Pet, foodItem, growthItem, withOwnerItem, withSkin } from "../rules/index";
import {
	BuyArgs,
	Config,
	HibernalError,
	Ledger,
	OWNER_ITEM_KINDS,
	PetAccount,
	ShopItem,
	hibernalError,
} from "./layout";

export const FOOD_PRICE_SKR: uint64[3] = [1, 2, 3];
export const GROWTH_PRICE_SKR_PER_STEP: uint64 = 2;
export const INSURANCE_PRICE_SKR: uint64 = 20;
export const SKIN_PRICE_SKR: uint64 = 5;
export const SKINS: uint8 = 2;

const LEDGER_INDEX: int32 = 3;
const INSURANCE_KIND: int32 = 6;

export struct BuyAccounts {
	owner: WritableSigner;
	config: Owned<Config>;
	pet: Delegated<PetAccount>;
	ledger: Writable;
	skrMint: External<Mint>;
	source: ExternalMutable<TokenAccount>;
	treasury: ExternalMutable<TokenAccount>;
	tokenProgram: Account;
	systemProgram: Program<System>;
}

export struct LoadAccounts {
	pet: Mutable<PetAccount>;
	ledger: Owned<Ledger>;
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

function foodKind(tier: uint8): Result<OwnerItem, ProgramError> {
	const kind: Result<OwnerItem, ProgramError> = match (tier) {
		0 => Result.ok(foodItem(Food.Small)),
		1 => Result.ok(foodItem(Food.Medium)),
		2 => Result.ok(foodItem(Food.Large)),
		_ => Result.err(hibernalError(HibernalError.NoSuchFood)),
	};
	return kind;
}

function growthKind(tier: uint8): Result<OwnerItem, ProgramError> {
	const dose = growthItem((tier as int32) + 1);
	if (!dose.ok) { return Result.err(hibernalError(HibernalError.NoSuchItem)); }
	return Result.ok(dose.value);
}

function ownerKind(item: ShopItem, tier: uint8): Result<OwnerItem, ProgramError> {
	const kind: Result<OwnerItem, ProgramError> = match (item) {
		ShopItem.Food => foodKind(tier),
		ShopItem.Growth => growthKind(tier),
		ShopItem.Insurance => Result.ok(OwnerItem.Insurance),
		ShopItem.Skin => Result.ok(OwnerItem.None),
	};
	return kind;
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
		if (amount > (0xffffffffffffffff as uint64) / 10) { return Result.err(ProgramError.arithmeticOverflow()); }
		amount = amount * 10;
	}
	return Result.ok(amount);
}

function configIn(config: Owned<Config>): Result<Readonly<Ptr<Config>>, ProgramError> {
	const stored = config.data();
	const derived = programAddress(["config", [stored.bump]]);
	if (!derived.ok || derived.value != config.key()) { return Result.err(ProgramError.constraintSeeds()); }
	return Result.ok(stored);
}

function ledgerOf(x: BuyAccounts, mint: Pubkey): Result<Ptr<Ledger>, ProgramError> {
	if (x.ledger.asAccount().owner() == SYSTEM_PROGRAM_ID) {
		const made = try createPda<Ledger>(x.owner, x.ledger, ["ledger", mint]);
		const created = made.account.data();
		created.mint = mint;
		created.bump = made.bump;
		return Result.ok(created);
	}
	const ledger = try mutable<Ledger>(LEDGER_INDEX);
	const _seeds = try pdaWithBump(ledger, ["ledger", mint], ledger.data().bump);
	const _mint = try expectAddress(ledger.data().mint, mint);
	return Result.ok(ledger.data());
}

export function buy(): Result<uint64, ProgramError> {
	const a = try args<BuyArgs>();
	const item = try itemOf(a.item);
	const whole = try wholePrice(item, a.tier);
	const kind = try ownerKind(item, a.tier);
	const x = try accounts<BuyAccounts>();
	const config = try configIn(x.config);
	const record = x.pet.data();
	const _petAddress = try pdaWithBump(x.pet, ["pet", record.mint], record.bump);
	const _owner = try expectHasOne(record.owner, x.owner.key());
	const _skrMint = try expectAddress(x.skrMint.key(), config.skrMint);
	const _treasury = try expectAddress(x.treasury.key(), config.treasury);
	const ledger = try ledgerOf(x, record.mint);
	const decimals = (try x.skrMint.read()).decimals;
	const price = try baseUnits(whole, decimals);
	const _paid = try transferTokens(x.source, x.treasury, x.skrMint, x.owner.asAccount(), price);
	if (item == ShopItem.Skin) {
		ledger.skin = a.tier + 1;
		return Result.ok(price);
	}
	const index = (kind as int32) - 1;
	ledger.bought[index] = ledger.bought[index] + 1;
	return Result.ok(price);
}

function loadedKind(record: Ptr<PetAccount>, ledger: Readonly<Ptr<Ledger>>, index: int32): uint64 {
	let moved: uint64 = 0;
	while (record.loaded[index] < ledger.bought[index]) {
		const next = record.pet.withOwnerItem((index + 1) as OwnerItem);
		if (!next.ok) { break; }
		record.pet = next.value;
		record.loaded[index] = record.loaded[index] + 1;
		moved = moved + 1;
	}
	return moved;
}

export function load(): Result<uint64, ProgramError> {
	const x = try accounts<LoadAccounts>();
	const record = x.pet.data();
	const _petAddress = try pdaWithBump(x.pet, ["pet", record.mint], record.bump);
	const ledger = x.ledger.data();
	const derived = programAddress(["ledger", record.mint, [ledger.bump]]);
	if (!derived.ok || derived.value != x.ledger.key()) { return Result.err(ProgramError.constraintSeeds()); }
	let moved = loadedKind(record, ledger, INSURANCE_KIND);
	for (let index = 0; index < INSURANCE_KIND; index++) {
		moved = moved + loadedKind(record, ledger, index);
	}
	if (ledger.skin != 0 && record.pet.skin != ledger.skin) {
		const dressed = record.pet.withSkin(ledger.skin - 1);
		if (dressed.ok) { record.pet = dressed.value; }
	}
	return Result.ok(moved);
}
