import { STAKE_LEVELS, EconomyAction } from "./actions";
import { Food } from "./emission";

export const POLICY_MAGIC: int32 = 0x4e524248;
export const POLICY_FORMAT: int32 = 4;
export const POLICY_HEADER_BYTES: int32 = 16;
export const POLICY_WIDTH: int32 = 44;
export const ACTIVATION_MAX: int32 = 127;

export const ECONOMY_INPUTS: int32 = 44;
export const ECONOMY_HIDDEN: int32 = 32;
export const ECONOMY_OUTPUTS: int32 = 12;
export const NODE_INPUTS: int32 = 30;
export const NODE_HIDDEN: int32 = 32;
export const ATTACK_INPUTS: int32 = 25;
export const ATTACK_HIDDEN: int32 = 32;
export const ATTACK_NARROW: int32 = 16;
export const ATTACK_OUTPUTS: int32 = STAKE_LEVELS;

export enum PolicyError {
	WrongSize,
	WrongMagic,
	WrongFormat,
	WrongEngine,
}

export function layerBytes(inputs: int32, outputs: int32): int32 {
	return 1 + inputs * outputs + 4 * outputs;
}

export function economyOffset(): int32 {
	return POLICY_HEADER_BYTES;
}

export function nodeOffset(): int32 {
	return economyOffset() +
		layerBytes(ECONOMY_INPUTS, ECONOMY_HIDDEN) +
		layerBytes(ECONOMY_HIDDEN, ECONOMY_OUTPUTS);
}

export function attackOffset(): int32 {
	return nodeOffset() + layerBytes(NODE_INPUTS, NODE_HIDDEN) + layerBytes(NODE_HIDDEN, 1);
}

export function policyBytes(): int32 {
	return attackOffset() +
		layerBytes(ATTACK_INPUTS, ATTACK_HIDDEN) +
		layerBytes(ATTACK_HIDDEN, ATTACK_NARROW) +
		layerBytes(ATTACK_NARROW, ATTACK_OUTPUTS);
}

function signedByte(policy: Span<uint8>, position: int32): int32 {
	const raw = policy[position] as int32;
	return raw >= 128 ? raw - 256 : raw;
}

function wordAt(policy: Span<uint8>, position: int32): int32 {
	const low = (policy[position] as int32) + (policy[position + 1] as int32) * 256;
	const high = (policy[position + 2] as int32) + signedByte(policy, position + 3) * 256;
	return low + high * 65536;
}

export function engineVersionOf(policy: Span<uint8>): uint64 {
	let version: uint64 = 0;
	for (let position = 15; position >= 8; position--) {
		version = (version << 8) | (policy[position] as uint64);
	}
	return version;
}

export function checkPolicy(policy: Span<uint8>, engine: uint64): Result<int32, PolicyError> {
	if (policy.length != policyBytes()) { return Result.err(PolicyError.WrongSize); }
	if (wordAt(policy, 0) != POLICY_MAGIC) { return Result.err(PolicyError.WrongMagic); }
	if (wordAt(policy, 4) != POLICY_FORMAT) { return Result.err(PolicyError.WrongFormat); }
	if (engineVersionOf(policy) != engine) { return Result.err(PolicyError.WrongEngine); }
	return Result.ok(policyBytes());
}

export function dense(
	policy: Span<uint8>,
	offset: int32,
	input: Span<int32>,
	inputs: int32,
	output: Span<int32>,
	outputs: int32,
	activate: boolean,
): int32 {
	const shift = policy[offset] as int32;
	const weights = offset + 1;
	const biases = weights + inputs * outputs;
	for (let row = 0; row < outputs; row++) {
		let sum = wordAt(policy, biases + row * 4);
		for (let column = 0; column < inputs; column++) {
			sum += signedByte(policy, weights + row * inputs + column) * input[column];
		}
		const scaled = sum >> shift;
		output[row] = activate ? Math.max(0, Math.min(scaled, ACTIVATION_MAX)) : scaled;
	}
	return biases + outputs * 4;
}

export function economyLogits(
	policy: Span<uint8>,
	input: Span<int32>,
	hidden: Span<int32>,
	logits: Span<int32>,
): void {
	const first = economyOffset();
	const second = dense(policy, first, input, ECONOMY_INPUTS, hidden, ECONOMY_HIDDEN, true);
	const _end = dense(policy, second, hidden, ECONOMY_HIDDEN, logits, ECONOMY_OUTPUTS, false);
}

export function nodeScore(
	policy: Span<uint8>,
	input: Span<int32>,
	hidden: Span<int32>,
	score: Span<int32>,
): int32 {
	const second = dense(policy, nodeOffset(), input, NODE_INPUTS, hidden, NODE_HIDDEN, true);
	const _end = dense(policy, second, hidden, NODE_HIDDEN, score, 1, false);
	return score[0];
}

export function attackLogits(
	policy: Span<uint8>,
	input: Span<int32>,
	hidden: Span<int32>,
	narrow: Span<int32>,
	logits: Span<int32>,
): void {
	const second = dense(policy, attackOffset(), input, ATTACK_INPUTS, hidden, ATTACK_HIDDEN, true);
	const third = dense(policy, second, hidden, ATTACK_HIDDEN, narrow, ATTACK_NARROW, true);
	const _end = dense(policy, third, narrow, ATTACK_NARROW, logits, ATTACK_OUTPUTS, false);
}

export function foldEatIntoBuy(
	logits: Span<int32>,
	legal: BitSet<EconomyAction>,
	full: boolean,
): void {
	if (full) { return; }
	for (let size = 0; size <= (Food.Large as int32); size++) {
		const eat = ((EconomyAction.EatSmall as int32) + size) as EconomyAction;
		if (legal.has(eat)) { return; }
	}
	for (let size = 0; size <= (Food.Large as int32); size++) {
		const eat = (EconomyAction.EatSmall as int32) + size;
		const buy = (EconomyAction.BuySmall as int32) + size;
		logits[buy] = Math.max(logits[buy], logits[eat]);
	}
}

export function foldPortionSizes(logits: Span<int32>, legal: BitSet<EconomyAction>): void {
	foldFamily(logits, legal, EconomyAction.BuySmall);
	foldFamily(logits, legal, EconomyAction.EatSmall);
}

function foldFamily(
	logits: Span<int32>,
	legal: BitSet<EconomyAction>,
	smallest: EconomyAction,
): void {
	let carried = 0;
	let carrying = false;
	for (let size = Food.Large as int32; size >= 0; size--) {
		const action = ((smallest as int32) + size) as EconomyAction;
		const logit = logits[action as int32];
		if (!legal.has(action)) {
			carried = carrying ? Math.max(carried, logit) : logit;
			carrying = true;
			continue;
		}
		if (carrying) { logits[action as int32] = Math.max(logit, carried); }
		carrying = false;
	}
}

test "the policy fits one account and the heads follow each other" {
	assert layerBytes(32, 32) == 1 + 1024 + 128;
	assert economyOffset() == 16;
	assert nodeOffset() == 16 + 1537 + 433;
	assert attackOffset() == nodeOffset() + 1089 + 37;
	assert policyBytes() == attackOffset() + 929 + 577 + 81;
	assert policyBytes() == 4699;
	assert policyBytes() <= 10240;
}

test "a dense layer multiplies signed bytes, adds the bias, shifts and clamps" {
	const layer: uint8[] = [2, 1, 255, 2, 254, 3, 253, 0xf6, 0xff, 0xff, 0xff, 100, 0, 0, 0];
	const input: int32[] = [10, 20, 30];
	const output: int32[] = [0, 0];
	const end = dense(layer, 0, input, 3, output, 2, false);
	assert end == 15;
	assert output[0] == 10;
	assert output[1] == 12;
	const negative: uint8[] = [1, 255, 0xfd, 0xff, 0xff, 0xff];
	const one: int32[] = [4];
	const out: int32[] = [0];
	const _raw = dense(negative, 0, one, 1, out, 1, false);
	assert out[0] == -4;
	const _clamped = dense(negative, 0, one, 1, out, 1, true);
	assert out[0] == 0;
	const large: uint8[] = [0, 127, 0, 0, 0, 0];
	const big: int32[] = [127];
	const _high = dense(large, 0, big, 1, out, 1, true);
	assert out[0] == ACTIVATION_MAX;
}

test "a policy is refused on size, magic, format and engine" {
	const bytes: uint8[] = [];
	for (let position = 0; position < policyBytes(); position++) { bytes.push(0); }
	const blank = checkPolicy(bytes, 7);
	assert !blank.ok;
	if (!blank.ok) { assert blank.error == PolicyError.WrongMagic; }
	bytes[0] = 0x48;
	bytes[1] = 0x42;
	bytes[2] = 0x52;
	bytes[3] = 0x4e;
	const unversioned = checkPolicy(bytes, 7);
	if (!unversioned.ok) { assert unversioned.error == PolicyError.WrongFormat; }
	bytes[4] = POLICY_FORMAT as uint8;
	const stale = checkPolicy(bytes, 7);
	if (!stale.ok) { assert stale.error == PolicyError.WrongEngine; }
	bytes[8] = 7;
	bytes[15] = 0x80;
	assert engineVersionOf(bytes) == 0x8000000000000007;
	assert checkPolicy(bytes, 0x8000000000000007).ok;
	const short: uint8[] = [1, 2, 3];
	const tiny = checkPolicy(short, 7);
	if (!tiny.ok) { assert tiny.error == PolicyError.WrongSize; }
}

test "a portion size out of reach passes its logit to the nearest smaller legal size" {
	const logits: int32[] = [10, 5, -40, -30, 90, 7, 60, 20];
	const legal = (0 as BitSet<EconomyAction>)
		.incl(EconomyAction.Rest)
		.incl(EconomyAction.BuySmall)
		.incl(EconomyAction.EatSmall)
		.incl(EconomyAction.EatLarge);
	foldPortionSizes(logits, legal);
	assert logits[EconomyAction.BuySmall as int32] == 90;
	assert logits[EconomyAction.EatSmall as int32] == 60;
	assert logits[EconomyAction.EatLarge as int32] == 20;
	assert logits[EconomyAction.Rest as int32] == 10;
	assert logits[EconomyAction.Bank as int32] == 5;
	const broke: int32[] = [10, 5, -40, -30, 90, 7, 60, 20];
	foldPortionSizes(broke, (0 as BitSet<EconomyAction>).incl(EconomyAction.Rest));
	assert broke[EconomyAction.Rest as int32] == 10;
	assert broke[EconomyAction.BuySmall as int32] == -40;
}

test "a pet that wants to eat from an empty pantry buys that portion instead" {
	const logits: int32[] = [10, 5, -40, -30, 20, 7, 60, 90, 0, 0];
	const hungry = (0 as BitSet<EconomyAction>)
		.incl(EconomyAction.Rest)
		.incl(EconomyAction.BuySmall)
		.incl(EconomyAction.BuyMedium);
	foldEatIntoBuy(logits, hungry, false);
	assert logits[EconomyAction.BuyMedium as int32] == 60;
	assert logits[EconomyAction.BuyLarge as int32] == 90;
	foldPortionSizes(logits, hungry);
	assert logits[EconomyAction.BuyMedium as int32] == 90;
	const sated: int32[] = [10, 5, -40, -30, 20, 7, 60, 90, 0, 0];
	foldEatIntoBuy(sated, hungry, true);
	assert sated[EconomyAction.BuyLarge as int32] == 20;
	const stocked: int32[] = [10, 5, -40, -30, 20, 7, 60, 90, 0, 0];
	foldEatIntoBuy(stocked, hungry.incl(EconomyAction.EatSmall), false);
	assert stocked[EconomyAction.BuyLarge as int32] == 20;
}
