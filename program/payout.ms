import {
	Account,
	DELEGATION_PROGRAM_ID,
	ExternalMutable,
	Mutable,
	Owned,
	Program,
	ProgramError,
	Pubkey,
	SYSTEM_PROGRAM_ID,
	Signer,
	System,
	Writable,
	WritableSigner,
	clock,
	createPda,
	delegated,
	expectAddress,
	expectHasOne,
	mutable,
	owned,
	pdaWithBump,
	programAddress,
	signed,
} from "std/solana";
import { accounts } from "std/solana";
import { MAGIC_CONTEXT_ID, MAGIC_PROGRAM_ID, commit } from "std/solana/magicblock";
import { Mint, TokenAccount, expectTokenMint, expectTokenOwner, mintTokens } from "std/solana/token";
import {
	Config,
	HibernalError,
	Paid,
	PetAccount,
	VrfPayer,
	dayOf,
	hibernalError,
} from "./layout";
import { EMISSION_CAP } from "../rules/index";

const PET_INDEX: int32 = 2;
const PAID_INDEX: int32 = 3;

export struct CommitPetAccounts {
	committer: Signer;
	pet: Mutable<PetAccount>;
	payer: Mutable<VrfPayer>;
	magicContext: Writable;
	magicFeeVault: Writable;
	magicProgram: Account;
	config: Owned<Config>;
}

export struct ClaimRewardAccounts {
	owner: WritableSigner;
	config: Owned<Config>;
	pet: Account;
	paid: Writable;
	mint: ExternalMutable<Mint>;
	destination: ExternalMutable<TokenAccount>;
	tokenProgram: Account;
	systemProgram: Program<System>;
}

export function commitPet(): Result<uint64, ProgramError> {
	const x = try accounts<CommitPetAccounts>();
	const record = x.pet.data();
	const committer = x.committer.key();
	if (committer != record.owner && committer != x.config.data().authority) { return Result.err(ProgramError.constraintHasOne()); }
	const _seeds = try pdaWithBump(x.pet, ["pet", record.mint], record.bump);
	const _context = try expectAddress(x.magicContext.key(), MAGIC_CONTEXT_ID);
	const _program = try expectAddress(x.magicProgram.key(), MAGIC_PROGRAM_ID);
	const _payer = try pdaWithBump(x.payer, ["vrf-payer"], x.payer.data().bump);
	const committed: Account[1] = [x.pet.asAccount()];
	return signed(
		commit(x.payer.asAccount(), committed, x.magicContext.asAccount(), x.magicFeeVault.asAccount()),
		["vrf-payer", [x.payer.data().bump]],
	);
}

struct Claimant {
	owner: Pubkey;
	mint: Pubkey;
	giftOwed: uint64;
}

function claimantOf(record: Readonly<Ptr<PetAccount>>): Claimant {
	return { owner: record.owner, mint: record.mint, giftOwed: record.pet.giftOwed };
}

function claimant(holder: Account): Result<Claimant, ProgramError> {
	if (holder.owner() == DELEGATION_PROGRAM_ID) {
		const pet = try delegated<PetAccount>(PET_INDEX);
		const record = pet.data();
		const _seeds = try pdaWithBump(pet, ["pet", record.mint], record.bump);
		return Result.ok(claimantOf(record));
	}
	const pet = try owned<PetAccount>(PET_INDEX);
	const record = pet.data();
	const derived = try programAddress(["pet", record.mint, [record.bump]]);
	if (derived != pet.key()) { return Result.err(ProgramError.constraintSeeds()); }
	return Result.ok(claimantOf(record));
}

function paidLedger(x: ClaimRewardAccounts, mint: Pubkey): Result<Ptr<Paid>, ProgramError> {
	if (x.paid.asAccount().owner() == SYSTEM_PROGRAM_ID) {
		const made = try createPda<Paid>(x.owner, x.paid, ["paid", mint]);
		const created = made.account.data();
		created.mint = mint;
		created.bump = made.bump;
		return Result.ok(created);
	}
	const ledger = try mutable<Paid>(PAID_INDEX);
	const _seeds = try pdaWithBump(ledger, ["paid", mint], ledger.data().bump);
	const _mint = try expectAddress(ledger.data().mint, mint);
	return Result.ok(ledger.data());
}

export function claimReward(): Result<uint64, ProgramError> {
	const x = try accounts<ClaimRewardAccounts>();
	const config = x.config.data();
	const record = try claimant(x.pet);
	const _owner = try expectHasOne(record.owner, x.owner.key());
	const _mint = try expectAddress(x.mint.key(), config.hbrnMint);
	const _tokenProgram = try expectAddress(x.tokenProgram.key(), x.mint.owner());
	const destination = try x.destination.read();
	const _destinationMint = try expectTokenMint(destination, config.hbrnMint);
	const _destinationOwner = try expectTokenOwner(destination, x.owner.key());
	const ledger = try paidLedger(x, record.mint);
	const gifted = record.giftOwed;
	if (gifted <= ledger.total) { return Result.err(hibernalError(HibernalError.NothingOwed)); }
	const owed = gifted - ledger.total;
	const today = dayOf(config, clock().unixTimestamp);
	const paidToday = ledger.day == today ? ledger.today : 0;
	if (paidToday >= config.claimCapPerDay) { return Result.err(hibernalError(HibernalError.OverCap)); }
	const room = config.claimCapPerDay - paidToday;
	const amount = owed < room ? owed : room;
	const supply = (try x.mint.read()).supply;
	if (supply > EMISSION_CAP || amount > EMISSION_CAP - supply) {
		return Result.err(hibernalError(HibernalError.SupplyCap));
	}
	const _minted = try signed(
		mintTokens(x.mint, x.destination, x.mint.asAccount(), amount),
		["mint", [config.mintBump]],
	);
	ledger.total = ledger.total + amount;
	ledger.day = today;
	ledger.today = paidToday + amount;
	return Result.ok(amount);
}
