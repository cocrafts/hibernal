import { checkPolicy } from "../rules/policy";
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
	logComputeUnits,
} from "std/solana";
import {
	DelegationAccounts,
	DelegationConfig,
	anyValidator,
	onValidator,
	delegate,
	commitAndUndelegate,
	undelegate,
	isUndelegateCallback,
} from "std/solana/magicblock";
import {
	POLICY_BLOB_BYTES,
	ATTACK_TARGETS,
	NODE_CANDIDATES,
	PolicyBlob,
	economyChecksum,
	attackChecksum,
	nodeChecksum,
	buffersMatchPolicy,
} from "./policyBench";

function policySeeds(): Seeds {
	return Seeds.empty(1).addText("policy");
}

function verifiedPolicyBump(policy: Account): Result<uint8, ProgramError> {
	const expected = try policySeeds().findProgramAddress(programId());
	if (!expected.key.equals(policy.key())) { return Result.err(ProgramError.invalidSeeds()); }
	return Result.ok(expected.bump);
}

function policyBlob(holder: Account): Result<Ptr<PolicyBlob>, ProgramError> {
	if (!buffersMatchPolicy() || holder.dataLength() != POLICY_BLOB_BYTES as uint64) {
		return Result.err(ProgramError.invalidAccountData());
	}
	return Result.ok(holder.data().address as Ptr<PolicyBlob>);
}

function runPolicy(data: Bytes): Result<uint64, ProgramError> {
	const engine = try data.readU64(8);
	const holder = try account(0);
	const blob = try policyBlob(holder);
	logComputeUnits();
	logComputeUnits();
	const checked = checkPolicy(blob.bytes, engine);
	if (!checked.ok) { return Result.err(ProgramError.custom(100 + (checked.error as uint32))); }
	logComputeUnits();
	let checksum = economyChecksum(blob.bytes, 0);
	logComputeUnits();
	for (let target = 0; target < ATTACK_TARGETS; target++) {
		checksum = attackChecksum(blob.bytes, target, checksum);
	}
	logComputeUnits();
	for (let candidate = 0; candidate < NODE_CANDIDATES; candidate++) {
		checksum = nodeChecksum(blob.bytes, candidate, checksum);
	}
	logComputeUnits();
	logU64(checksum);
	return Result.ok(checksum);
}

function initializePolicy(): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const policy = try account(1);
	const bump = try verifiedPolicyBump(policy);
	if (policy.lamports() == 0) {
		const _created = try createProgramAccount(payer, policy, POLICY_BLOB_BYTES as uint64, programId(), policySeeds().withBump(bump));
	}
	return Result.ok(policy.dataLength());
}

function writePolicy(data: Bytes): Result<uint64, ProgramError> {
	const _payer = try signerAccount(0);
	const policy = try account(1);
	const _bump = try verifiedPolicyBump(policy);
	if (!policy.isOwnedBy(programId())) { return Result.err(ProgramError.illegalOwner()); }
	const offset = try data.readU64(8);
	const chunk = try data.range(16, data.length - 16);
	const target = try policy.data().range(offset, chunk.length);
	return target.copyFrom(chunk);
}

function delegatePolicy(): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const systemProgram = try account(1);
	const policy = try account(2);
	const ownerProgram = try account(3);
	const buffer = try account(4);
	const delegationRecord = try account(5);
	const delegationMetadata = try account(6);
	const bump = try verifiedPolicyBump(policy);
	let config = DelegationConfig.anyValidator();
	if (accountCount() > 8) {
		const validator = try account(8);
		config = DelegationConfig.onValidator(validator.key());
	}
	const accounts: DelegationAccounts = {
		payer: payer,
		delegated: policy,
		ownerProgram: ownerProgram,
		buffer: buffer,
		delegationRecord: delegationRecord,
		delegationMetadata: delegationMetadata,
		systemProgram: systemProgram,
	};
	return delegate(accounts, policySeeds(), bump, config);
}

function returnPolicy(): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const policy = try account(1);
	const magicContext = try account(3);
	return commitAndUndelegate(payer, policy, magicContext);
}

function undelegatePolicy(data: Bytes): Result<uint64, ProgramError> {
	const delegated = try account(0);
	const buffer = try account(1);
	const payer = try account(2);
	return undelegate(delegated, buffer, payer, programId(), data);
}

function dispatch(): Result<uint64, ProgramError> {
	const data = instructionData();
	if (isUndelegateCallback(data)) { return undelegatePolicy(data); }
	const discriminator = try data.readU64(0);
	return match (discriminator) {
		0 => runPolicy(data),
		1 => initializePolicy(),
		2 => writePolicy(data),
		3 => delegatePolicy(),
		4 => returnPolicy(),
		_ => Result.err(ProgramError.invalidInstructionData()),
	};
}

function main(): void {
	const outcome = dispatch();
	if (!outcome.ok) { failWith(outcome.error); }
}

main();
