import { InstructionAccount, ProgramError, account, accountCount, failWith, findProgramAddressOf, instructionData, invokeList, programId, putBytes, signed } from "std/solana";

const CALLBACK: uint8 = 0xaa;
const REQUEST: uint8 = 10;

function calledBack(): Result<uint64, ProgramError> {
	const data = instructionData();
	const identity = try account(0);
	const target = try account(1);
	const found = try findProgramAddressOf(programId(), ["identity", target.key()]);
	const count = accountCount();
	let accounts: InstructionAccount[64] = [];
	accounts[0] = InstructionAccount.readonlySigner(identity);
	for (let index = 2; index < count; index++) {
		const held = try account(index);
		accounts[index - 1] = held.isWritable() ? InstructionAccount.writable(held) : InstructionAccount.readonly(held);
	}
	let storage: uint8[1024] = [];
	const length = putBytes(storage, 0, try data.range(1, data.length - 1));
	const targetKey = target.key();
	return signed(invokeList(targetKey, accounts[0..(count - 1)], storage, length), ["identity", targetKey, [found.bump]]);
}

function requested(): Result<uint64, ProgramError> {
	const payer = try account(0);
	const identity = try account(1);
	if (!payer.isSigner() || !payer.isWritable() || !identity.isSigner()) {
		return Result.err(ProgramError.missingRequiredSignature());
	}
	return Result.ok(0);
}

function dispatch(): Result<uint64, ProgramError> {
	const data = instructionData();
	if (data.length == 0) { return Result.err(ProgramError.invalidInstructionData()); }
	const kind = try data.readU8(0);
	if (kind == CALLBACK) { return calledBack(); }
	if (kind == REQUEST) { return requested(); }
	return Result.err(ProgramError.invalidInstructionData());
}

function entry(): void {
	const result = dispatch();
	if (!result.ok) { failWith(result.error); }
}

entry();
