import { checkPolicy } from "../rules/policy";
import {
	Account,
	Bytes,
	ProgramError,
	account,
	instructionData,
	failWith,
	logU64,
	logComputeUnits,
} from "std/solana";
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

function dispatch(): Result<uint64, ProgramError> {
	const data = instructionData();
	const discriminator = try data.readU64(0);
	return match (discriminator) {
		0 => runPolicy(data),
		_ => Result.err(ProgramError.invalidInstructionData()),
	};
}

function main(): void {
	const outcome = dispatch();
	if (!outcome.ok) { failWith(outcome.error); }
}

main();
