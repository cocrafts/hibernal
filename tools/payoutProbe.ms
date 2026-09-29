import {
	Account,
	Bytes,
	Instruction,
	ProgramError,
	Pubkey,
	Seeds,
	account,
	accountCount,
	signerAccount,
	instructionData,
	programId,
	createProgramAccount,
	clock,
	failWith,
	logU64,
} from "std/solana";
import {
	DelegationAccounts,
	DelegationConfig,
	anyValidator,
	onValidator,
	delegate,
	delegationProgram,
	commit,
	commitAndUndelegate,
	undelegate,
	isUndelegateCallback,
} from "std/solana/magicblock";

const PET_BYTES: uint64 = 40;
const PET_OWNER: uint64 = 0;
const PET_EARNED: uint64 = 32;
const PAID_BYTES: uint64 = 24;
const PAID_TOTAL: uint64 = 0;
const PAID_DAY: uint64 = 8;
const PAID_TODAY: uint64 = 16;
const MINT_BYTES: uint64 = 82;
const HBRN_DECIMALS: uint8 = 6;
const CLAIM_CAP_PER_DAY: uint64 = 10_000_000;
const SECONDS_PER_DAY: int64 = 86_400;
const INITIALIZE_MINT: uint8 = 20;
const MINT_TO: uint8 = 7;

enum PayoutError {
	WrongPet,
	WrongLedger,
	WrongMint,
	WrongTokenProgram,
	NotTheOwner,
	PetNotOurs,
}

function failed(error: PayoutError): ProgramError {
	return ProgramError.custom(300 + (error as uint32));
}

function tokenProgram(): Pubkey {
	return {
		word0: 0x93a165d7e1f6dd06,
		word1: 0xac79ebce46e1cbd9,
		word2: 0x91375b5fed85b41c,
		word3: 0xa900ff7e85f58c3a,
	};
}

function petSeeds(id: uint8): Seeds {
	return Seeds.empty(2).addText("pet").addU8(id);
}

function paidSeeds(id: uint8): Seeds {
	return Seeds.empty(2).addText("paid").addU8(id);
}

function mintSeeds(): Seeds {
	return Seeds.empty(2).addText("mint");
}

function bumpOf(holder: Account, seeds: Seeds, error: PayoutError): Result<uint8, ProgramError> {
	const expected = try seeds.findProgramAddress(programId());
	if (!expected.key.equals(holder.key())) { return Result.err(failed(error)); }
	return Result.ok(expected.bump);
}

function idIn(data: Bytes): Result<uint8, ProgramError> {
	const id = try data.readU64(8);
	if (id > 255) { return Result.err(ProgramError.invalidArgument()); }
	return Result.ok(id as uint8);
}

function mintCreated(): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const mint = try account(1);
	const tokens = try account(3);
	if (!tokens.key().equals(tokenProgram())) { return Result.err(failed(PayoutError.WrongTokenProgram)); }
	const bump = try bumpOf(mint, mintSeeds(), PayoutError.WrongMint);
	const _created = try createProgramAccount(payer, mint, MINT_BYTES, tokenProgram(), mintSeeds().withBump(bump));
	return Instruction.forProgram(tokenProgram(), 1, 35)
		.addWritable(mint)
		.appendU8(INITIALIZE_MINT)
		.appendU8(HBRN_DECIMALS)
		.appendPubkey(mint.key())
		.appendU8(0)
		.invoke();
}

function petCreated(data: Bytes): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const pet = try account(1);
	const paid = try account(2);
	const id = try idIn(data);
	const owner = try data.readPubkey(16);
	const petBump = try bumpOf(pet, petSeeds(id), PayoutError.WrongPet);
	const paidBump = try bumpOf(paid, paidSeeds(id), PayoutError.WrongLedger);
	const _pet = try createProgramAccount(payer, pet, PET_BYTES, programId(), petSeeds(id).withBump(petBump));
	const _paid = try createProgramAccount(payer, paid, PAID_BYTES, programId(), paidSeeds(id).withBump(paidBump));
	return pet.data().writePubkey(PET_OWNER, owner);
}

function petDelegated(data: Bytes): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const systemProgram = try account(1);
	const pet = try account(2);
	const ownerProgram = try account(3);
	const buffer = try account(4);
	const delegationRecord = try account(5);
	const delegationMetadata = try account(6);
	const id = try idIn(data);
	const bump = try bumpOf(pet, petSeeds(id), PayoutError.WrongPet);
	let config = DelegationConfig.anyValidator();
	if (accountCount() > 8) {
		const validator = try account(8);
		config = DelegationConfig.onValidator(validator.key());
	}
	const accounts: DelegationAccounts = {
		payer: payer,
		delegated: pet,
		ownerProgram: ownerProgram,
		buffer: buffer,
		delegationRecord: delegationRecord,
		delegationMetadata: delegationMetadata,
		systemProgram: systemProgram,
	};
	return delegate(accounts, petSeeds(id), bump, config);
}

function earned(data: Bytes): Result<uint64, ProgramError> {
	const pet = try account(0);
	if (!pet.isOwnedBy(programId())) { return Result.err(failed(PayoutError.PetNotOurs)); }
	const amount = try data.readU64(8);
	const before = try pet.data().readU64(PET_EARNED);
	if (amount > 0xffffffffffffffff - before) { return Result.err(ProgramError.arithmeticOverflow()); }
	return pet.data().writeU64(PET_EARNED, before + amount);
}

function committed(undelegating: boolean): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const pet = try account(1);
	const magicContext = try account(3);
	if (undelegating) { return commitAndUndelegate(payer, pet, magicContext); }
	return commit(payer, pet, magicContext);
}

function claimed(data: Bytes): Result<uint64, ProgramError> {
	const owner = try signerAccount(0);
	const pet = try account(1);
	const paid = try account(2);
	const mint = try account(3);
	const destination = try account(4);
	const tokens = try account(5);
	const id = try idIn(data);
	const _petBump = try bumpOf(pet, petSeeds(id), PayoutError.WrongPet);
	if (!pet.isOwnedBy(programId()) && !pet.isOwnedBy(Pubkey.delegationProgram())) {
		return Result.err(failed(PayoutError.PetNotOurs));
	}
	const _paidBump = try bumpOf(paid, paidSeeds(id), PayoutError.WrongLedger);
	if (!paid.isOwnedBy(programId())) { return Result.err(failed(PayoutError.WrongLedger)); }
	const mintBump = try bumpOf(mint, mintSeeds(), PayoutError.WrongMint);
	if (!tokens.key().equals(tokenProgram())) { return Result.err(failed(PayoutError.WrongTokenProgram)); }
	const petOwner = try pet.data().readPubkey(PET_OWNER);
	if (!petOwner.equals(owner.key())) { return Result.err(failed(PayoutError.NotTheOwner)); }
	const earnedTotal = try pet.data().readU64(PET_EARNED);
	const paidTotal = try paid.data().readU64(PAID_TOTAL);
	const owed = earnedTotal > paidTotal ? earnedTotal - paidTotal : 0;
	const today = (clock().unixTimestamp / SECONDS_PER_DAY) as uint64;
	const paidDay = try paid.data().readU64(PAID_DAY);
	const storedToday = try paid.data().readU64(PAID_TODAY);
	const paidToday = paidDay == today ? storedToday : 0;
	const room = CLAIM_CAP_PER_DAY - paidToday;
	const amount = owed < room ? owed : room;
	logU64(earnedTotal);
	logU64(paidTotal);
	logU64(amount);
	if (amount == 0) { return Result.ok(0); }
	const _minted = try Instruction.forProgram(tokenProgram(), 3, 9)
		.addWritable(mint)
		.addWritable(destination)
		.addReadonlySigner(mint)
		.appendU8(MINT_TO)
		.appendU64(amount)
		.invokeSigned(mintSeeds().withBump(mintBump));
	const _total = try paid.data().writeU64(PAID_TOTAL, paidTotal + amount);
	const _day = try paid.data().writeU64(PAID_DAY, today);
	return paid.data().writeU64(PAID_TODAY, paidToday + amount);
}

function undelegated(data: Bytes): Result<uint64, ProgramError> {
	const holder = try account(0);
	const buffer = try account(1);
	const payer = try account(2);
	return undelegate(holder, buffer, payer, programId(), data);
}

function dispatch(): Result<uint64, ProgramError> {
	const data = instructionData();
	if (isUndelegateCallback(data)) { return undelegated(data); }
	const discriminator = try data.readU64(0);
	return match (discriminator) {
		0 => mintCreated(),
		1 => petCreated(data),
		2 => petDelegated(data),
		3 => earned(data),
		4 => committed(false),
		5 => committed(true),
		6 => claimed(data),
		_ => Result.err(ProgramError.invalidInstructionData()),
	};
}

function main(): void {
	const outcome = dispatch();
	if (!outcome.ok) { failWith(outcome.error); }
}

main();
