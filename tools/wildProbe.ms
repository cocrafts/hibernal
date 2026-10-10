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
	failWith,
	logU64,
} from "std/solana";
import {
	DelegationAccounts,
	DelegationConfig,
	anyValidator,
	onValidator,
	delegate,
	isUndelegateCallback,
} from "std/solana/magicblock";

const SPONSOR_BYTES: uint64 = 8;
const CREATE_EPHEMERAL_ACCOUNT: uint32 = 12;
const CLOSE_EPHEMERAL_ACCOUNT: uint32 = 14;

enum WildError {
	WrongSponsor,
	WrongWild,
	WildNotOurs,
	WrongMagicProgram,
	Undelegation,
}

function failed(error: WildError): ProgramError {
	return ProgramError.custom(400 + (error as uint32));
}

function sponsorSeeds(): Seeds {
	return Seeds.empty(1).addText("sponsor");
}

function wildSeeds(blockId: uint64): Seeds {
	return Seeds.empty(2).addText("wild").addU64(blockId);
}

function bumpOf(holder: Account, seeds: Seeds, error: WildError): Result<uint8, ProgramError> {
	const expected = try seeds.findProgramAddress(programId());
	if (!expected.key.equals(holder.key())) { return Result.err(failed(error)); }
	return Result.ok(expected.bump);
}

function sponsorCreated(): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const sponsor = try account(1);
	const bump = try bumpOf(sponsor, sponsorSeeds(), WildError.WrongSponsor);
	return createProgramAccount(payer, sponsor, SPONSOR_BYTES, programId(), sponsorSeeds().withBump(bump));
}

function sponsorDelegated(): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const systemProgram = try account(1);
	const sponsor = try account(2);
	const ownerProgram = try account(3);
	const buffer = try account(4);
	const delegationRecord = try account(5);
	const delegationMetadata = try account(6);
	const bump = try bumpOf(sponsor, sponsorSeeds(), WildError.WrongSponsor);
	let config = DelegationConfig.anyValidator();
	if (accountCount() > 8) {
		const validator = try account(8);
		config = DelegationConfig.onValidator(validator.key());
	}
	const accounts: DelegationAccounts = {
		payer: payer,
		delegated: sponsor,
		ownerProgram: ownerProgram,
		buffer: buffer,
		delegationRecord: delegationRecord,
		delegationMetadata: delegationMetadata,
		systemProgram: systemProgram,
	};
	return delegate(accounts, sponsorSeeds(), bump, config);
}

function magicCall(data: Bytes, tag: uint32, withLength: boolean): Result<uint64, ProgramError> {
	const sponsor = try account(0);
	const wild = try account(1);
	const vault = try account(2);
	const magic = try account(3);
	if (!magic.key().equals(Pubkey.magicProgram())) { return Result.err(failed(WildError.WrongMagicProgram)); }
	const blockId = try data.readU64(8);
	const sponsorBump = try bumpOf(sponsor, sponsorSeeds(), WildError.WrongSponsor);
	const wildBump = try bumpOf(wild, wildSeeds(blockId), WildError.WrongWild);
	let instruction = Instruction.forProgram(Pubkey.magicProgram(), 3, 8)
		.addWritableSigner(sponsor)
		.addWritableSigner(wild)
		.addWritable(vault)
		.appendU32(tag);
	if (withLength) {
		const bytes = try data.readU64(16);
		instruction = instruction.appendU32(bytes as uint32);
	}
	const signers: Seeds[2] = [sponsorSeeds().withBump(sponsorBump), wildSeeds(blockId).withBump(wildBump)];
	return instruction.invokeSigned(signers);
}

function wildWritten(data: Bytes): Result<uint64, ProgramError> {
	const wild = try account(0);
	const blockId = try data.readU64(8);
	const value = try data.readU64(16);
	const _bump = try bumpOf(wild, wildSeeds(blockId), WildError.WrongWild);
	if (!wild.isOwnedBy(programId())) { return Result.err(failed(WildError.WildNotOurs)); }
	const before = try wild.data().readU64(0);
	logU64(before);
	return wild.data().writeU64(0, before + value);
}

function dispatch(): Result<uint64, ProgramError> {
	const data = instructionData();
	if (isUndelegateCallback(data)) { return Result.err(failed(WildError.Undelegation)); }
	const discriminator = try data.readU64(0);
	return match (discriminator) {
		0 => sponsorCreated(),
		1 => sponsorDelegated(),
		2 => magicCall(data, CREATE_EPHEMERAL_ACCOUNT, true),
		3 => wildWritten(data),
		4 => magicCall(data, CLOSE_EPHEMERAL_ACCOUNT, false),
		_ => Result.err(ProgramError.invalidInstructionData()),
	};
}

function main(): void {
	const outcome = dispatch();
	if (!outcome.ok) { failWith(outcome.error); }
}

main();
