import {
	Account,
	Bytes,
	ProgramError,
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
	commit,
	commitAndUndelegate,
	undelegate,
	isUndelegateCallback,
} from "std/solana/magicblock";

function counterSeeds(initializer: Account): Seeds {
	return Seeds.empty(2).addText("counter").addAccountKey(initializer);
}

function verifiedCounterBump(initializer: Account, counter: Account): Result<uint8, ProgramError> {
	const expected = try counterSeeds(initializer).findProgramAddress(programId());
	if (!expected.key.equals(counter.key())) { return Result.err(ProgramError.invalidArgument()); }
	return Result.ok(expected.bump);
}

function addToCounter(counter: Account, increaseBy: uint64): Result<uint64, ProgramError> {
	const count = try counter.data().readU64(0);
	const next = count + increaseBy;
	if (next < count) { return Result.err(ProgramError.arithmeticOverflow()); }
	const _written = try counter.data().writeU64(0, next);
	logU64(next);
	return Result.ok(next);
}

function initializeCounter(): Result<uint64, ProgramError> {
	const initializer = try signerAccount(0);
	const counter = try account(1);
	const bump = try verifiedCounterBump(initializer, counter);
	if (counter.lamports() == 0) {
		const _created = try createProgramAccount(initializer, counter, 8, programId(), counterSeeds(initializer).withBump(bump));
	}
	return counter.data().writeU64(0, 0);
}

function increaseCounter(increaseBy: uint64): Result<uint64, ProgramError> {
	const initializer = try account(0);
	const counter = try account(1);
	const _bump = try verifiedCounterBump(initializer, counter);
	return addToCounter(counter, increaseBy);
}

function delegateCounter(): Result<uint64, ProgramError> {
	const initializer = try signerAccount(0);
	const systemProgram = try account(1);
	const counter = try account(2);
	const ownerProgram = try account(3);
	const buffer = try account(4);
	const delegationRecord = try account(5);
	const delegationMetadata = try account(6);
	const bump = try verifiedCounterBump(initializer, counter);
	let config = DelegationConfig.anyValidator();
	if (accountCount() > 8) {
		const validator = try account(8);
		config = DelegationConfig.onValidator(validator.key());
	}
	const accounts: DelegationAccounts = {
		payer: initializer,
		delegated: counter,
		ownerProgram: ownerProgram,
		buffer: buffer,
		delegationRecord: delegationRecord,
		delegationMetadata: delegationMetadata,
		systemProgram: systemProgram,
	};
	return delegate(accounts, counterSeeds(initializer), bump, config);
}

function commitCounter(andUndelegate: boolean, increaseBy: uint64): Result<uint64, ProgramError> {
	const initializer = try signerAccount(0);
	const counter = try account(1);
	const magicContext = try account(3);
	if (increaseBy > 0) {
		const _bump = try verifiedCounterBump(initializer, counter);
		const _next = try addToCounter(counter, increaseBy);
	}
	if (andUndelegate) { return commitAndUndelegate(initializer, counter, magicContext); }
	return commit(initializer, counter, magicContext);
}

function undelegateCounter(data: Bytes): Result<uint64, ProgramError> {
	const delegated = try account(0);
	const buffer = try account(1);
	const payer = try account(2);
	return undelegate(delegated, buffer, payer, programId(), data);
}

function dispatch(): Result<uint64, ProgramError> {
	const data = instructionData();
	if (isUndelegateCallback(data)) { return undelegateCounter(data); }
	const discriminator = try data.readU64(0);
	return match (discriminator) {
		0 => initializeCounter(),
		1 => {
			const increaseBy = try data.readU64(8);
			return increaseCounter(increaseBy);
		},
		2 => delegateCounter(),
		3 => commitCounter(true, 0),
		4 => commitCounter(false, 0),
		5 => {
			const increaseBy = try data.readU64(8);
			return commitCounter(false, increaseBy);
		},
		6 => {
			const increaseBy = try data.readU64(8);
			return commitCounter(true, increaseBy);
		},
		_ => Result.err(ProgramError.invalidInstructionData()),
	};
}

function main(): void {
	const outcome = dispatch();
	if (!outcome.ok) { failWith(outcome.error); }
}

main();
