import { ProgramError, account, failWith, instructionData } from "std/solana";

const CREATE: uint8 = 0;
const CANCEL: uint8 = 2;

function sponsored(): Result<uint64, ProgramError> {
	const sponsor = try account(0);
	if (!sponsor.isSigner() || !sponsor.isWritable()) { return Result.err(ProgramError.missingRequiredSignature()); }
	return Result.ok(0);
}

function dispatch(): Result<uint64, ProgramError> {
	const data = instructionData();
	if (data.length == 0) { return Result.err(ProgramError.invalidInstructionData()); }
	const kind = try data.readU8(0);
	if (kind == CREATE || kind == CANCEL) { return sponsored(); }
	return Result.err(ProgramError.invalidInstructionData());
}

function entry(): void {
	const result = dispatch();
	if (!result.ok) { failWith(result.error); }
}

entry();
