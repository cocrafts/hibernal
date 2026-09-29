import { readLines } from "std/fs";
import { checkPolicy } from "../rules/policy";
import { engineVersion } from "../sim/digests";
import {
	POLICY_BLOB_BYTES,
	ATTACK_TARGETS,
	NODE_CANDIDATES,
	Section,
	economyChecksum,
	attackChecksum,
	nodeChecksum,
	executedWeights,
	buffersMatchPolicy,
} from "./policyBench";

const POLICY_TEXT = "out/policyProbe/policy.txt";

function main(): int32 {
	const lines = readLines(POLICY_TEXT);
	if (!lines.ok) {
		console.log(`cannot read ${POLICY_TEXT}; run tools/chain/policyLiteSvm.mjs first`);
		return 1;
	}
	const policy: uint8[] = [];
	for (const line of lines.value) {
		if (line.length > 0) { policy.push(parseInt(line) as uint8); }
	}
	if (!buffersMatchPolicy()) {
		console.log("tools/policyBench.ms buffer sizes differ from rules/policy.ms");
		return 1;
	}
	if (policy.length != POLICY_BLOB_BYTES) {
		console.log(`policy is ${policy.length} bytes, expected ${POLICY_BLOB_BYTES}`);
		return 1;
	}
	const checked = checkPolicy(policy, engineVersion());
	if (!checked.ok) {
		console.log(`checkPolicy failed: ${checked.error as int32}`);
		return 1;
	}
	let checksum = economyChecksum(policy, 0);
	for (let target = 0; target < ATTACK_TARGETS; target++) {
		checksum = attackChecksum(policy, target, checksum);
	}
	for (let candidate = 0; candidate < NODE_CANDIDATES; candidate++) {
		checksum = nodeChecksum(policy, candidate, checksum);
	}
	console.log(`weights economy ${executedWeights(Section.Economy)} attack ${executedWeights(Section.Attack)} node ${executedWeights(Section.Node)}`);
	console.log(`host checksum 0x${checksum.toString(16)}`);
	return 0;
}

process.exit(main());
