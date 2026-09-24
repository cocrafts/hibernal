@include("buffer.h");
@compile("buffer.c");

import { WORLD_BLOCKS, EPISODE_EPOCHS } from "../world";
import { engineVersion } from "../digests";
import { PersonaKind, checkPolicy } from "../../rules/index";
import { Head, observationSize, actionCount, largestActionCount, zeros } from "./observe";
import { selfInputs, selfInput } from "./actor";
import { POLICY_SLOTS, Batch, RewardTerm, withTerm } from "./batch";

extern function hibernalCopyOut(target: unknown, source: Borrow<int32>, count: int32): void;
extern function hibernalPeek(source: unknown, index: int32): int32;
extern function hibernalPeekByte(source: unknown, index: int32): int32;

export const FFI_REFUSED: int32 = -1;
export const STAT_FIELDS: int32 = 8;

let batch: Batch = Batch.create(0, 0, WORLD_BLOCKS, EPISODE_EPOCHS);
let observations: int32[] = [];
let legal: int32[] = [];
let actions: int32[] = [];
let rewards: int32[] = [];
let dones: int32[] = [];
let logits: int32[] = [];
let stats: int32[] = zeros(STAT_FIELDS);
let version: uint64 = 0;

function isHead(head: int32): boolean {
	return head >= 0 && head <= (Head.Attack as int32);
}

function largestObservation(): int32 {
	return Math.max(observationSize(Head.Node), observationSize(Head.Attack));
}

@exportName("hibernal_engine_version")
function ffiEngineVersion(): uint64 {
	if (version == 0) { version = engineVersion(); }
	return version;
}

@exportName("hibernal_reset")
function ffiReset(seed: uint64, envCount: int32, blocks: int32, epochs: int32): int32 {
	if (envCount <= 0 || blocks <= 0 || epochs <= 0) { return FFI_REFUSED; }
	batch = Batch.create(seed, envCount, blocks, epochs);
	const rows = batch.rows();
	observations = zeros(rows * largestObservation());
	legal = zeros(rows * largestActionCount());
	actions = zeros(rows);
	rewards = zeros(rows);
	dones = zeros(rows);
	logits = zeros(rows * largestActionCount());
	return rows;
}

@exportName("hibernal_rows")
function ffiRows(): int32 {
	return batch.rows();
}

@exportName("hibernal_head")
function ffiHead(): int32 {
	return batch.cursor.head as int32;
}

@exportName("hibernal_epoch")
function ffiEpoch(): int32 {
	return batch.cursor.epoch as int32;
}

@exportName("hibernal_episode")
function ffiEpisode(): int32 {
	return batch.episode;
}

@exportName("hibernal_observation_size")
function ffiObservationSize(head: int32): int32 {
	return isHead(head) ? observationSize(head as Head) : FFI_REFUSED;
}

@exportName("hibernal_action_count")
function ffiActionCount(head: int32): int32 {
	return isHead(head) ? actionCount(head as Head) : FFI_REFUSED;
}

@exportName("hibernal_observe")
function ffiObserve(head: int32, observationBuffer: unknown, legalBuffer: unknown): int32 {
	if (batch.rows() == 0 || head != (batch.cursor.head as int32)) { return FFI_REFUSED; }
	batch.observe(observations, legal);
	const rows = batch.rows();
	hibernalCopyOut(observationBuffer, observations[0], rows * observationSize(batch.cursor.head));
	hibernalCopyOut(legalBuffer, legal[0], rows * actionCount(batch.cursor.head));
	return rows;
}

@exportName("hibernal_teacher_actions")
function ffiTeacherActions(head: int32, actionBuffer: unknown): int32 {
	if (batch.rows() == 0 || head != (batch.cursor.head as int32)) { return FFI_REFUSED; }
	batch.teacherActions(actions);
	hibernalCopyOut(actionBuffer, actions[0], batch.rows());
	return batch.rows();
}

@exportName("hibernal_step")
function ffiStep(
	head: int32,
	actionBuffer: unknown,
	rewardBuffer: unknown,
	doneBuffer: unknown,
): int32 {
	if (batch.rows() == 0 || head != (batch.cursor.head as int32)) { return FFI_REFUSED; }
	const rows = batch.rows();
	for (let row = 0; row < rows; row++) { actions[row] = hibernalPeek(actionBuffer, row); }
	const stepped = batch.step(batch.cursor.head, actions, rewards, dones);
	if (!stepped.ok) { return FFI_REFUSED; }
	batch = stepped.value;
	hibernalCopyOut(rewardBuffer, rewards[0], rows);
	hibernalCopyOut(doneBuffer, dones[0], rows);
	return rows;
}

@exportName("hibernal_stats")
function ffiStats(env: int32, statBuffer: unknown): int32 {
	if (env >= batch.worlds.length) { return FFI_REFUSED; }
	let fights = 0;
	let wins = 0;
	let deaths = 0;
	let heirs = 0;
	let illegal = 0;
	let living = 0;
	let levels = 0;
	let wealth: uint64 = 0;
	for (let index = 0; index < batch.worlds.length; index++) {
		if (env >= 0 && env != index) { continue; }
		const world = batch.worlds[index];
		fights += world.stats.fights;
		wins += world.stats.wins;
		deaths += world.stats.deaths;
		heirs += world.stats.heirs;
		illegal += world.stats.illegal;
		for (let index = 0; index < world.pets.length; index++) {
			const pet = world.pets[index];
			if (!pet.alive) { continue; }
			living += 1;
			levels += pet.level as int32;
			wealth += (pet.harvest + pet.burrow) / 1000000;
		}
	}
	stats[0] = fights;
	stats[1] = wins;
	stats[2] = deaths;
	stats[3] = heirs;
	stats[4] = illegal;
	stats[5] = living;
	stats[6] = levels;
	stats[7] = Math.min(wealth, 2000000000 as uint64) as int32;
	hibernalCopyOut(statBuffer, stats[0], STAT_FIELDS);
	return STAT_FIELDS;
}

@exportName("hibernal_feel")
function ffiFeel(feelBuffer: unknown, capacity: int32): int32 {
	const counters = batch.feel.counters;
	if (counters.length == 0 || capacity != counters.length) { return FFI_REFUSED; }
	hibernalCopyOut(feelBuffer, counters[0], counters.length);
	return counters.length;
}

@exportName("hibernal_reward")
function ffiReward(persona: int32, term: int32, value: int32): int32 {
	const knownPersona = persona >= 0 && persona <= (PersonaKind.Vengeful as int32);
	const knownTerm = term >= 0 && term <= (RewardTerm.LossAversion as int32);
	if (batch.rows() == 0 || !knownPersona || !knownTerm) { return FFI_REFUSED; }
	const weights = batch.weights[persona].withTerm(term as RewardTerm, value as int64);
	batch.setWeights(persona as PersonaKind, weights);
	return 0;
}

@exportName("hibernal_self_inputs")
function ffiSelfInputs(head: int32): int32 {
	return isHead(head) ? selfInputs(head as Head) : FFI_REFUSED;
}

@exportName("hibernal_self_input")
function ffiSelfInput(head: int32, position: int32): int32 {
	if (!isHead(head) || position < 0) { return FFI_REFUSED; }
	if (position >= selfInputs(head as Head)) { return FFI_REFUSED; }
	return selfInput(head as Head, position) as int32;
}

@exportName("hibernal_load_policy")
function ffiLoadPolicy(slot: int32, policyBuffer: unknown, byteCount: int32): int32 {
	if (byteCount <= 0 || byteCount > 65536) { return FFI_REFUSED; }
	const bytes: uint8[] = [];
	for (let position = 0; position < byteCount; position++) {
		bytes.push(hibernalPeekByte(policyBuffer, position) as uint8);
	}
	const checked = checkPolicy(bytes, ffiEngineVersion());
	if (!checked.ok) { return FFI_REFUSED - 1 - (checked.error as int32); }
	return batch.withPolicy(slot, bytes) ? byteCount : FFI_REFUSED;
}

@exportName("hibernal_assign")
function ffiAssign(env: int32, slot: int32, controller: int32): int32 {
	return batch.assign(env, slot, controller) ? 0 : FFI_REFUSED;
}

@exportName("hibernal_policy_logits")
function ffiPolicyLogits(policy: int32, logitBuffer: unknown): int32 {
	if (batch.rows() == 0 || policy < 0 || policy >= POLICY_SLOTS) { return FFI_REFUSED; }
	if (batch.policies[policy].bytes.length == 0) { return FFI_REFUSED; }
	batch.policyLogits(policy, logits);
	hibernalCopyOut(logitBuffer, logits[0], batch.rows() * actionCount(batch.cursor.head));
	return batch.rows();
}
