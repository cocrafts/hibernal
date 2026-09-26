import {
	ECONOMY_INPUTS,
	ECONOMY_HIDDEN,
	ECONOMY_OUTPUTS,
	NODE_INPUTS,
	NODE_HIDDEN,
	ATTACK_INPUTS,
	ATTACK_HIDDEN,
	ATTACK_NARROW,
	ATTACK_OUTPUTS,
	economyLogits,
	nodeScore,
	attackLogits,
	policyBytes,
} from "../rules/policy";

export const POLICY_BLOB_BYTES: int32 = 4763;
export const ATTACK_TARGETS: int32 = 9;
export const NODE_CANDIDATES: int32 = 6;

export enum Section {
	Economy,
	Attack,
	Node,
}

export struct PolicyBlob {
	bytes: uint8[4763];
}

function feature(section: Section, candidate: int32, index: int32): int32 {
	return (index * index * 31 + candidate * 97 + (section as int32) * 13 + 7) % 128;
}

function fill(input: Span<int32>, count: int32, section: Section, candidate: int32): void {
	for (let index = 0; index < count; index++) {
		input[index] = feature(section, candidate, index);
	}
}

function mixed(checksum: uint64, value: int32): uint64 {
	return checksum * 1099511628211 + (((value as int64) + 2147483648) as uint64);
}

export function economyChecksum(policy: Span<uint8>, checksum: uint64): uint64 {
	let input: int32[46] = [];
	let hidden: int32[32] = [];
	let logits: int32[12] = [];
	fill(input, ECONOMY_INPUTS, Section.Economy, 0);
	economyLogits(policy, input, hidden, logits);
	let next = checksum;
	for (let index = 0; index < ECONOMY_OUTPUTS; index++) {
		next = mixed(next, logits[index]);
	}
	return next;
}

export function attackChecksum(policy: Span<uint8>, target: int32, checksum: uint64): uint64 {
	let input: int32[25] = [];
	let hidden: int32[32] = [];
	let narrow: int32[16] = [];
	let logits: int32[4] = [];
	fill(input, ATTACK_INPUTS, Section.Attack, target);
	attackLogits(policy, input, hidden, narrow, logits);
	let next = checksum;
	for (let index = 0; index < ATTACK_OUTPUTS; index++) {
		next = mixed(next, logits[index]);
	}
	return next;
}

export function nodeChecksum(policy: Span<uint8>, candidate: int32, checksum: uint64): uint64 {
	let input: int32[30] = [];
	let hidden: int32[32] = [];
	let score: int32[1] = [];
	fill(input, NODE_INPUTS, Section.Node, candidate);
	return mixed(checksum, nodeScore(policy, input, hidden, score));
}

export function buffersMatchPolicy(): boolean {
	return policyBytes() == POLICY_BLOB_BYTES &&
		ECONOMY_INPUTS == 46 && ECONOMY_HIDDEN == 32 && ECONOMY_OUTPUTS == 12 &&
		ATTACK_INPUTS == 25 && ATTACK_HIDDEN == 32 && ATTACK_NARROW == 16 && ATTACK_OUTPUTS == 4 &&
		NODE_INPUTS == 30 && NODE_HIDDEN == 32;
}

export function executedWeights(section: Section): int32 {
	return match (section) {
		Section.Economy => ECONOMY_INPUTS * ECONOMY_HIDDEN + ECONOMY_HIDDEN * ECONOMY_OUTPUTS,
		Section.Attack => ATTACK_INPUTS * ATTACK_HIDDEN + ATTACK_HIDDEN * ATTACK_NARROW + ATTACK_NARROW * ATTACK_OUTPUTS,
		Section.Node => NODE_INPUTS * NODE_HIDDEN + NODE_HIDDEN,
	};
}
