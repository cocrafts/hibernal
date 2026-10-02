import { Instruction, ProgramError, Seeds, account, accountCount, failWith, instructionData, programId } from "std/solana";

const CALLBACK: uint8 = 0xaa;
const REQUEST: uint8 = 10;

function calledBack(): Result<uint64, ProgramError> {
	const data = instructionData();
	const identity = try account(0);
	const target = try account(1);
	const found = try Seeds.empty(2).addText("identity").addPubkey(target.key()).findProgramAddress(programId());
	const count = accountCount();
	const instruction = Instruction.forProgram(target.key(), (count - 1) as uint64, data.length);
	instruction.addReadonlySigner(identity);
	for (let index = 2; index < count; index++) {
		const held = try account(index);
		instruction.addAccount(held, held.isWritable(), false);
	}
	instruction.appendBytes(try data.range(1, data.length - 1));
	return instruction.invokeSigned(Seeds.empty(3).addText("identity").addPubkey(target.key()).addU8(found.bump));
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
