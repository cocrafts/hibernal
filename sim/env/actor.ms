import {
	BLOCK_SLOTS,
	STAKE_LEVELS,
	ATTACK_HOLD,
	POLICY_WIDTH,
	NODE_INPUTS,
	ATTACK_INPUTS,
	ATTACK_OUTPUTS,
	EconomyAction,
	economyLogits,
	foldPortionSizes,
	foldEatIntoBuy,
	nodeScore,
	attackLogits,
} from "../../rules/index";
import {
	ECONOMY_ACTIONS,
	FEATURE_ONE,
	Head,
	SelfFeature,
	SELF_FEATURES,
	NODE_FEATURES,
	NODE_CANDIDATES,
	TARGET_FEATURES,
	actionCount,
	zeros,
} from "./observe";

export const NODE_SELF_INPUTS: int32 = NODE_INPUTS - NODE_FEATURES;
export const ATTACK_SELF_INPUTS: int32 = ATTACK_INPUTS - TARGET_FEATURES;

export struct Scratch {
	input: int32[];
	hidden: int32[];
	narrow: int32[];
	logits: int32[];
}

export function create(this typeof Scratch): Scratch {
	return {
		input: zeros(POLICY_WIDTH),
		hidden: zeros(POLICY_WIDTH),
		narrow: zeros(POLICY_WIDTH),
		logits: zeros(POLICY_WIDTH),
	};
}

export function selfInputs(head: Head): int32 {
	return match (head) {
		Head.Economy => SELF_FEATURES,
		Head.Node => NODE_SELF_INPUTS,
		Head.Attack => ATTACK_SELF_INPUTS,
	};
}

function nodeSelfInput(position: int32): SelfFeature {
	return match (position) {
		0 => SelfFeature.RegionWorker,
		1 => SelfFeature.RegionFighter,
		2 => SelfFeature.RegionSurvivor,
		3 => SelfFeature.PersonaCautious,
		4 => SelfFeature.PersonaGreedy,
		5 => SelfFeature.PersonaVengeful,
		6 => SelfFeature.Level,
		_ => SelfFeature.PointsUnspent,
	};
}

function attackSelfInput(position: int32): SelfFeature {
	return match (position) {
		0 => SelfFeature.Hearts,
		1 => SelfFeature.MaxHearts,
		2 => SelfFeature.Harvest,
		3 => SelfFeature.Burrow,
		4 => SelfFeature.Level,
		5 => SelfFeature.AttacksLeft,
		6 => SelfFeature.PersonaCautious,
		7 => SelfFeature.PersonaGreedy,
		8 => SelfFeature.PersonaVengeful,
		9 => SelfFeature.Might,
		10 => SelfFeature.Grit,
		_ => SelfFeature.Round,
	};
}

export function selfInput(head: Head, position: int32): SelfFeature {
	return match (head) {
		Head.Economy => position as SelfFeature,
		Head.Node => nodeSelfInput(position),
		Head.Attack => attackSelfInput(position),
	};
}

function gather(
	this scratch: Scratch,
	head: Head,
	observations: int32[],
	offset: int32,
	candidate: int32,
	candidateFeatures: int32,
): void {
	const input = scratch.input;
	const own = selfInputs(head);
	for (let position = 0; position < own; position++) {
		input[position] = observations[offset + (selfInput(head, position) as int32)];
	}
	const row = offset + SELF_FEATURES + candidate * candidateFeatures;
	for (let position = 0; position < candidateFeatures; position++) {
		input[own + position] = observations[row + position];
	}
}

function economyMask(legal: int32[], legalOffset: int32): BitSet<EconomyAction> {
	let mask = 0 as BitSet<EconomyAction>;
	for (let ordinal = 0; ordinal < ECONOMY_ACTIONS; ordinal++) {
		if (legal[legalOffset + ordinal] == 1) { mask = mask.incl(ordinal as EconomyAction); }
	}
	return mask;
}

export function logitsInto(
	this scratch: Scratch,
	policy: uint8[],
	head: Head,
	observations: int32[],
	offset: int32,
	legal: int32[],
	legalOffset: int32,
	logits: int32[],
	logitsOffset: int32,
): void {
	const actions = actionCount(head);
	for (let action = 0; action < actions; action++) { logits[logitsOffset + action] = 0; }
	if (head == Head.Economy) {
		scratch.gather(head, observations, offset, 0, 0);
		economyLogits(policy, scratch.input, scratch.hidden, scratch.logits);
		const mask = economyMask(legal, legalOffset);
		const full = observations[offset + (SelfFeature.Hearts as int32)] >= FEATURE_ONE;
		foldEatIntoBuy(scratch.logits, mask, full);
		foldPortionSizes(scratch.logits, mask);
		for (let action = 0; action < actionCount(head); action++) {
			logits[logitsOffset + action] = scratch.logits[action];
		}
		return;
	}
	if (head == Head.Node) {
		for (let id = 0; id < NODE_CANDIDATES; id++) {
			if (legal[legalOffset + id] == 0) { continue; }
			scratch.gather(head, observations, offset, id, NODE_FEATURES);
			const score = nodeScore(policy, scratch.input, scratch.hidden, scratch.logits);
			logits[logitsOffset + id] = score;
		}
		return;
	}
	for (let slot = 0; slot <= BLOCK_SLOTS; slot++) {
		const hold = slot == BLOCK_SLOTS;
		let wanted = hold && legal[legalOffset + ATTACK_HOLD] == 1;
		for (let level = 0; level < STAKE_LEVELS && !hold; level++) {
			if (legal[legalOffset + slot * STAKE_LEVELS + level] == 1) { wanted = true; }
		}
		if (!wanted) { continue; }
		scratch.gather(head, observations, offset, slot, TARGET_FEATURES);
		attackLogits(policy, scratch.input, scratch.hidden, scratch.narrow, scratch.logits);
		if (hold) {
			logits[logitsOffset + ATTACK_HOLD] = scratch.logits[0];
			continue;
		}
		for (let level = 0; level < ATTACK_OUTPUTS; level++) {
			if (legal[legalOffset + slot * STAKE_LEVELS + level] == 0) { continue; }
			logits[logitsOffset + slot * STAKE_LEVELS + level] = scratch.logits[level];
		}
	}
}

export function bestLegal(
	head: Head,
	logits: int32[],
	logitsOffset: int32,
	legal: int32[],
	legalOffset: int32,
	fallback: int32,
): int32 {
	let best = fallback;
	let found = false;
	for (let action = 0; action < actionCount(head); action++) {
		if (legal[legalOffset + action] == 0) { continue; }
		if (!found || logits[logitsOffset + action] > logits[logitsOffset + best]) {
			best = action;
			found = true;
		}
	}
	return best;
}

test "each head gathers its own inputs" {
	assert selfInputs(Head.Economy) == 44;
	assert NODE_SELF_INPUTS == 8;
	assert ATTACK_SELF_INPUTS == 12;
	assert selfInput(Head.Economy, 5) == SelfFeature.Level;
	assert selfInput(Head.Node, 7) == SelfFeature.PointsUnspent;
	assert selfInput(Head.Attack, 11) == SelfFeature.Round;
	const scratch = Scratch.create();
	const observations = zeros(3 + SELF_FEATURES + 11 * TARGET_FEATURES);
	for (let position = 0; position < observations.length; position++) {
		observations[position] = position;
	}
	scratch.gather(Head.Attack, observations, 3, 2, TARGET_FEATURES);
	assert scratch.input[0] == 3 + (SelfFeature.Hearts as int32);
	assert scratch.input[11] == 3 + (SelfFeature.Round as int32);
	assert scratch.input[12] == 3 + SELF_FEATURES + 2 * TARGET_FEATURES;
	assert scratch.input[24] == 3 + SELF_FEATURES + 2 * TARGET_FEATURES + 12;
}

test "the best legal action ignores illegal logits and falls back when nothing is legal" {
	const logits: int32[] = [9, 5, 7, -2, 8, 1, 0, 3, 6, 2, 1, 4];
	const legal: int32[] = [0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0];
	assert bestLegal(Head.Economy, logits, 0, legal, 0, 0) == 2;
	const none: int32[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
	assert bestLegal(Head.Economy, logits, 0, none, 0, 0) == 0;
	const tied: int32[] = [4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4];
	assert bestLegal(Head.Economy, tied, 0, legal, 0, 0) == 1;
}
