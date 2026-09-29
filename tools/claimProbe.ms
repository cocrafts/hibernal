import {
	Account,
	Bytes,
	ProgramError,
	Pubkey,
	account,
	signerAccount,
	instructionData,
	failWith,
	logU64,
} from "std/solana";

const ACCOUNT_TYPE_OFFSET: uint64 = 165;
const EXTENSIONS_OFFSET: uint64 = 166;
const ACCOUNT_TYPE_MINT: uint8 = 1;
const GROUP_MEMBER_POINTER: uint16 = 22;
const TOKEN_GROUP_MEMBER: uint16 = 23;

export enum ClaimError {
	WrongTokenProgram,
	NotAMint,
	WrongMintAuthority,
	NoGroupMember,
	MemberElsewhere,
	WrongGroup,
	WrongTokenMint,
	WrongHolder,
	NotExactlyOne,
}

function rejected(error: ClaimError): ProgramError {
	return ProgramError.custom(1 + (error as uint32));
}

function token2022(): Pubkey {
	return {
		word0: 0xde8f75eee1f6dd06,
		word1: 0xdacd6ce4bc5d4218,
		word2: 0x270db9834dfc1ab6,
		word3: 0xfc8ba1d828f9bdfe,
	};
}

function extensionOf(mint: Account, kind: uint16): Result<Bytes, ProgramError> {
	const data = mint.data();
	let offset = EXTENSIONS_OFFSET;
	while (offset + 4 <= data.length) {
		const found = try data.readU16(offset);
		const length = try data.readU16(offset + 2);
		if (found == kind) { return data.range(offset + 4, length as uint64); }
		if (found == 0) { break; }
		offset += 4 + (length as uint64);
	}
	return Result.err(rejected(ClaimError.NoGroupMember));
}

function verifyAdmission(data: Bytes): Result<uint64, ProgramError> {
	const holder = try signerAccount(0);
	const mint = try account(1);
	const held = try account(2);
	const group = try data.readPubkey(8);
	const authority = try data.readPubkey(40);
	if (!mint.isOwnedBy(token2022()) || !held.isOwnedBy(token2022())) {
		return Result.err(rejected(ClaimError.WrongTokenProgram));
	}
	const mintData = mint.data();
	const accountType = try mintData.readU8(ACCOUNT_TYPE_OFFSET);
	if (accountType != ACCOUNT_TYPE_MINT) { return Result.err(rejected(ClaimError.NotAMint)); }
	const authorityTag = try mintData.readU32(0);
	const mintAuthority = try mintData.readPubkey(4);
	if (authorityTag != 1 || !mintAuthority.equals(authority)) {
		return Result.err(rejected(ClaimError.WrongMintAuthority));
	}
	const pointer = try extensionOf(mint, GROUP_MEMBER_POINTER);
	const memberAddress = try pointer.readPubkey(32);
	const member = try extensionOf(mint, TOKEN_GROUP_MEMBER);
	const memberMint = try member.readPubkey(0);
	const memberGroup = try member.readPubkey(32);
	const memberNumber = try member.readU64(64);
	if (!memberAddress.equals(mint.key()) || !memberMint.equals(mint.key())) {
		return Result.err(rejected(ClaimError.MemberElsewhere));
	}
	if (!memberGroup.equals(group)) { return Result.err(rejected(ClaimError.WrongGroup)); }
	const heldData = held.data();
	const heldMint = try heldData.readPubkey(0);
	const heldBy = try heldData.readPubkey(32);
	const amount = try heldData.readU64(64);
	if (!heldMint.equals(mint.key())) { return Result.err(rejected(ClaimError.WrongTokenMint)); }
	if (!heldBy.equals(holder.key())) { return Result.err(rejected(ClaimError.WrongHolder)); }
	if (amount != 1) { return Result.err(rejected(ClaimError.NotExactlyOne)); }
	logU64(memberNumber);
	return Result.ok(memberNumber);
}

function dispatch(): Result<uint64, ProgramError> {
	const data = instructionData();
	const discriminator = try data.readU64(0);
	return match (discriminator) {
		0 => verifyAdmission(data),
		_ => Result.err(ProgramError.invalidInstructionData()),
	};
}

function main(): void {
	const outcome = dispatch();
	if (!outcome.ok) { failWith(outcome.error); }
}

main();
