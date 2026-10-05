import {
	Account,
	Delegated,
	ExternalMutable,
	Instruction,
	Mutable,
	Owned,
	Program,
	ProgramError,
	Pubkey,
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
	programId,
	readArgs,
	selectInstruction,
} from "std/solana";
import { accounts } from "std/solana/macro";
import { delegationProgram, magicContext, magicProgram } from "std/solana/magicblock";
import { Mint, TokenAccount, expectTokenMint, expectTokenOwner, mintTokens } from "std/solana/token";
import {
	Config,
	HibernalError,
	Paid,
	PetAccount,
	VrfPayer,
	dayOf,
	hibernalError,
	mintSeeds,
	paidSeeds,
	petSeeds,
	vrfPayerSeeds,
} from "./layout";
import { EMISSION_CAP } from "../rules/index";

const PET_INDEX: int32 = 2;
const PAID_INDEX: int32 = 3;

export struct CommitPetAccounts {
	owner: Signer;
	pet: Mutable<PetAccount>;
	payer: Mutable<VrfPayer>;
	magicContext: Writable;
	magicFeeVault: Writable;
	magicProgram: Account;
}

const SCHEDULE_COMMIT: uint32 = 1;

function paidCommit(payer: Mutable<VrfPayer>, committed: Account, context: Account, feeVault: Account): Result<uint64, ProgramError> {
	const instruction = Instruction.forProgram(Pubkey.magicProgram(), 4, 4);
	instruction.addWritableSigner(payer as Account);
	instruction.addWritable(context);
	instruction.addWritable(feeVault);
	instruction.addAccount(committed, committed.isWritable(), false);
	instruction.appendU32(SCHEDULE_COMMIT);
	return instruction.invokeSigned(vrfPayerSeeds().withBump(payer.data().bump));
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
	const _owner = try expectHasOne(record.owner, x.owner.key());
	const _seeds = try pdaWithBump(x.pet, petSeeds(record.mint), record.bump);
	const _context = try expectAddress((x.magicContext as Account).key(), Pubkey.magicContext());
	const _program = try expectAddress(x.magicProgram.key(), Pubkey.magicProgram());
	const _payer = try pdaWithBump(x.payer, vrfPayerSeeds(), x.payer.data().bump);
	return paidCommit(x.payer, x.pet as Account, x.magicContext as Account, x.magicFeeVault as Account);
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
	if (holder.owner() == Pubkey.delegationProgram()) {
		const pet = try delegated<PetAccount>(PET_INDEX);
		const record = pet.data();
		const _seeds = try pdaWithBump(pet, petSeeds(record.mint), record.bump);
		return Result.ok(claimantOf(record));
	}
	const pet = try owned<PetAccount>(PET_INDEX);
	const record = pet.data();
	const derived = try petSeeds(record.mint).withBump(record.bump).createProgramAddress(programId());
	if (derived != pet.key()) { return Result.err(ProgramError.constraintSeeds()); }
	return Result.ok(claimantOf(record));
}

function paidLedger(x: ClaimRewardAccounts, mint: Pubkey): Result<Ptr<Paid>, ProgramError> {
	if ((x.paid as Account).owner() == Pubkey.systemProgram()) {
		const made = try createPda<Paid>(x.owner, x.paid, paidSeeds(mint));
		const created = made.account.data();
		created.mint = mint;
		created.bump = made.bump;
		return Result.ok(created);
	}
	const ledger = try mutable<Paid>(PAID_INDEX);
	const _seeds = try pdaWithBump(ledger, paidSeeds(mint), ledger.data().bump);
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
	const _minted = try mintTokens(
		x.mint,
		x.destination,
		x.mint as Account,
		amount,
		mintSeeds().withBump(config.mintBump),
	);
	ledger.total = ledger.total + amount;
	ledger.day = today;
	ledger.today = paidToday + amount;
	return Result.ok(amount);
}
