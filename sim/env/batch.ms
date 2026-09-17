import {
	BLOCK_SLOTS,
	ALLOCATE_HOLD,
	ATTACK_HOLD,
	Pet,
	PersonaKind,
	EconomyAction,
	splitmix,
	policyBytes,
} from "../../rules/index";
import { ACTS_PER_EPOCH, Masks, World } from "../world";
import { personaKindOf, playEpisode } from "../teacher";
import { Head, observationSize, actionCount, observeInto, legalInto, zeros } from "./observe";
import { Scratch, logitsInto, bestLegal } from "./actor";

export const MILLI_PER_UNIT: uint64 = 1000;
export const CONTROL_LEARNER: int32 = -2;
export const CONTROL_TEACHER: int32 = -1;
export const POLICY_SLOTS: int32 = 8;

export enum Done {
	Running,
	Died,
	Truncated,
}

export struct RewardWeights {
	heartMilli: int64;
	deathMilli: int64;
}

export struct Cursor {
	epoch: uint64;
	round: int32;
	slot: int32;
	head: Head;
}

export struct PolicyBytes {
	bytes: uint8[];
}

export struct Batch {
	worlds: World[];
	scores: int64[];
	controllers: int32[];
	policies: PolicyBytes[];
	scratch: Scratch;
	rowObservation: int32[];
	rowLegal: int32[];
	rowLogits: int32[];
	seed: uint64;
	blocks: int32;
	epochs: int32;
	episode: int32;
	cursor: Cursor;
}

export enum StepError {
	WrongHead,
}

export function of(this typeof RewardWeights, kind: PersonaKind): RewardWeights {
	return match (kind) {
		PersonaKind.Cautious => ({ heartMilli: 20000, deathMilli: 500000 }),
		PersonaKind.Greedy => ({ heartMilli: 20000, deathMilli: 500000 }),
		PersonaKind.Vengeful => ({ heartMilli: 20000, deathMilli: 500000 }),
	};
}

export function score(this pet: Pet, weights: RewardWeights): int64 {
	if (!pet.alive) { return -weights.deathMilli; }
	const wealth = ((pet.harvest + pet.burrow) / MILLI_PER_UNIT) as int64;
	return wealth + weights.heartMilli * (pet.hearts as int64);
}

export function worldSeed(seed: uint64, env: int32, episode: int32): uint64 {
	return splitmix(seed + ((env as uint64) << 32) + (episode as uint64));
}

function opened(this batch: Batch): Batch {
	const worlds = batch.worlds;
	const scores = batch.scores;
	const pets = batch.blocks * BLOCK_SLOTS;
	for (let env = 0; env < worlds.length; env++) {
		const seed = worldSeed(batch.seed, env, batch.episode);
		const world = World.create(batch.blocks, seed).beginEpoch(1);
		worlds[env] = world;
		for (let index = 0; index < pets; index++) {
			const weights = RewardWeights.of(personaKindOf(index));
			scores[env * pets + index] = world.pets[index].score(weights);
		}
	}
	return { ...batch, cursor: { epoch: 1, round: 0, slot: 0, head: Head.Economy } };
}

export function create(
	this typeof Batch,
	seed: uint64,
	envCount: int32,
	blocks: int32,
	epochs: int32,
): Batch {
	const worlds: World[] = [];
	const scores: int64[] = [];
	const controllers: int32[] = [];
	const policies: PolicyBytes[] = [];
	for (let env = 0; env < envCount; env++) {
		worlds.push(World.create(blocks, 0));
		for (let index = 0; index < blocks * BLOCK_SLOTS; index++) { scores.push(0); }
		for (let slot = 0; slot < BLOCK_SLOTS; slot++) { controllers.push(CONTROL_LEARNER); }
	}
	for (let slot = 0; slot < POLICY_SLOTS; slot++) { policies.push({ bytes: [] }); }
	const batch: Batch = {
		worlds: worlds,
		scores: scores,
		controllers: controllers,
		policies: policies,
		scratch: Scratch.create(),
		rowObservation: zeros(observationSize(Head.Node)),
		rowLegal: zeros(actionCount(Head.Attack)),
		rowLogits: zeros(actionCount(Head.Attack)),
		seed: seed,
		blocks: blocks,
		epochs: epochs,
		episode: 0,
		cursor: { epoch: 1, round: 0, slot: 0, head: Head.Economy },
	};
	return batch.opened();
}

export function rows(this batch: Batch): int32 {
	return batch.worlds.length * batch.blocks;
}

export function petOf(this batch: Batch, row: int32): int32 {
	return (row % batch.blocks) * BLOCK_SLOTS + batch.cursor.slot;
}

export function controllerOf(this batch: Batch, row: int32): int32 {
	return batch.controllers[(row / batch.blocks) * BLOCK_SLOTS + batch.cursor.slot];
}

export function assign(this batch: Batch, env: int32, slot: int32, controller: int32): boolean {
	const known = controller >= CONTROL_LEARNER && controller < POLICY_SLOTS;
	if (env < 0 || env >= batch.worlds.length || slot < 0 || slot >= BLOCK_SLOTS || !known) {
		return false;
	}
	if (controller >= 0 && batch.policies[controller].bytes.length == 0) { return false; }
	const controllers = batch.controllers;
	controllers[env * BLOCK_SLOTS + slot] = controller;
	return true;
}

export function observe(this batch: Batch, observations: int32[], legal: int32[]): void {
	const head = batch.cursor.head;
	const size = observationSize(head);
	const actions = actionCount(head);
	for (let row = 0; row < batch.rows(); row++) {
		if (batch.controllerOf(row) != CONTROL_LEARNER) {
			for (let position = 0; position < size; position++) {
				observations[row * size + position] = 0;
			}
			for (let action = 0; action < actions; action++) { legal[row * actions + action] = 0; }
			continue;
		}
		const world = batch.worlds[row / batch.blocks];
		world.observeInto(batch.petOf(row), head, observations, row * size);
		world.legalInto(batch.petOf(row), head, legal, row * actions);
	}
}

function masksOf(this world: World, index: int32, head: Head): Masks {
	const pet = world.pets[index];
	return match (head) {
		Head.Economy => ({
			economy: pet.legalEconomy(world.global),
			nodes: { bits: 0 },
			attacks: { bits: 0 },
		}),
		Head.Node => ({
			economy: 0 as BitSet<EconomyAction>,
			nodes: pet.legalNodes(world.global),
			attacks: { bits: 0 },
		}),
		Head.Attack => ({
			economy: 0 as BitSet<EconomyAction>,
			nodes: { bits: 0 },
			attacks: world.attackMaskFor(index),
		}),
	};
}

export function holdAction(head: Head): int32 {
	return match (head) {
		Head.Economy => EconomyAction.Rest as int32,
		Head.Node => ALLOCATE_HOLD,
		Head.Attack => ATTACK_HOLD,
	};
}

export function teacherAction(this world: World, index: int32, head: Head): int32 {
	if (!world.pets[index].alive) { return holdAction(head); }
	const masks = world.masksOf(index, head);
	return match (head) {
		Head.Economy => world.teachEconomy(index, masks) as int32,
		Head.Node => world.teachNode(index, masks),
		Head.Attack => world.teachAttack(index, masks),
	};
}

export function teacherActions(this batch: Batch, actions: int32[]): void {
	for (let row = 0; row < batch.rows(); row++) {
		const world = batch.worlds[row / batch.blocks];
		actions[row] = world.teacherAction(batch.petOf(row), batch.cursor.head);
	}
}

function logitsOf(this batch: Batch, world: World, index: int32, policy: int32): void {
	const head = batch.cursor.head;
	world.observeInto(index, head, batch.rowObservation, 0);
	world.legalInto(index, head, batch.rowLegal, 0);
	batch.scratch.logitsInto(
		batch.policies[policy].bytes,
		head,
		batch.rowObservation,
		0,
		batch.rowLegal,
		0,
		batch.rowLogits,
		0,
	);
}

export function policyAction(this batch: Batch, world: World, index: int32, policy: int32): int32 {
	const head = batch.cursor.head;
	if (!world.pets[index].alive) { return holdAction(head); }
	batch.logitsOf(world, index, policy);
	return bestLegal(head, batch.rowLogits, 0, batch.rowLegal, 0, holdAction(head));
}

export function policyLogits(this batch: Batch, policy: int32, logits: int32[]): void {
	const actions = actionCount(batch.cursor.head);
	for (let row = 0; row < batch.rows(); row++) {
		batch.logitsOf(batch.worlds[row / batch.blocks], batch.petOf(row), policy);
		for (let action = 0; action < actions; action++) {
			logits[row * actions + action] = batch.rowLogits[action];
		}
	}
}

export function withPolicy(this batch: Batch, slot: int32, bytes: uint8[]): boolean {
	if (slot < 0 || slot >= POLICY_SLOTS) { return false; }
	const policies = batch.policies;
	policies[slot] = { bytes: bytes };
	return true;
}

function applied(this world: World, index: int32, head: Head, action: int32): World {
	return match (head) {
		Head.Economy => world.applyEconomy(index, action as EconomyAction),
		Head.Node => world.applyNode(index, action),
		Head.Attack => world.applyAttack(index, action),
	};
}

function advanced(this batch: Batch): Batch {
	const cursor = batch.cursor;
	if (cursor.head != Head.Attack) {
		return { ...batch, cursor: { ...cursor, head: ((cursor.head as int32) + 1) as Head } };
	}
	if (cursor.slot + 1 < BLOCK_SLOTS) {
		return { ...batch, cursor: { ...cursor, slot: cursor.slot + 1, head: Head.Economy } };
	}
	const worlds = batch.worlds;
	if (cursor.round + 1 < ACTS_PER_EPOCH) {
		for (let env = 0; env < worlds.length; env++) {
			worlds[env] = { ...worlds[env], round: cursor.round + 1 };
		}
		return {
			...batch,
			cursor: { ...cursor, round: cursor.round + 1, slot: 0, head: Head.Economy },
		};
	}
	if (cursor.epoch >= (batch.epochs as uint64)) {
		const next: Batch = { ...batch, episode: batch.episode + 1 };
		return next.opened();
	}
	const scores = batch.scores;
	const pets = batch.blocks * BLOCK_SLOTS;
	for (let env = 0; env < worlds.length; env++) {
		const world = worlds[env].endEpoch().beginEpoch(cursor.epoch + 1);
		worlds[env] = world;
		for (let index = 0; index < pets; index++) {
			const pet = world.pets[index];
			if (pet.alive && pet.bornEpoch == world.epoch) {
				scores[env * pets + index] = pet.score(RewardWeights.of(personaKindOf(index)));
			}
		}
	}
	return {
		...batch,
		cursor: { epoch: cursor.epoch + 1, round: 0, slot: 0, head: Head.Economy },
	};
}

export function step(
	this batch: Batch,
	head: Head,
	actions: int32[],
	rewards: int32[],
	dones: int32[],
): Result<Batch, StepError> {
	const cursor = batch.cursor;
	if (head != cursor.head) { return Result.err(StepError.WrongHead); }
	const worlds = batch.worlds;
	const scores = batch.scores;
	const pets = batch.blocks * BLOCK_SLOTS;
	const lastEpoch = cursor.epoch >= (batch.epochs as uint64);
	const lastRound = lastEpoch && cursor.round == ACTS_PER_EPOCH - 1;
	const closing = lastRound && head == Head.Attack;
	for (let row = 0; row < batch.rows(); row++) {
		const env = row / batch.blocks;
		const index = batch.petOf(row);
		const controller = batch.controllerOf(row);
		const action = match (controller) {
			CONTROL_LEARNER => actions[row],
			CONTROL_TEACHER => worlds[env].teacherAction(index, head),
			_ => batch.policyAction(worlds[env], index, controller),
		};
		const world = worlds[env].applied(index, head, action);
		worlds[env] = world;
		const pet = world.pets[index];
		const now = pet.score(RewardWeights.of(personaKindOf(index)));
		rewards[row] = (now - scores[env * pets + index]) as int32;
		scores[env * pets + index] = now;
		const running = closing ? Done.Truncated : Done.Running;
		dones[row] = (pet.alive ? running : Done.Died) as int32;
	}
	return Result.ok(batch.advanced());
}

function playTeacher(this start: Batch, untilEpoch: uint64): Batch {
	let batch = start;
	const actions = zeros(batch.rows());
	const rewards = zeros(batch.rows());
	const dones = zeros(batch.rows());
	while (batch.cursor.epoch < untilEpoch && batch.episode == start.episode) {
		batch.teacherActions(actions);
		const stepped = batch.step(batch.cursor.head, actions, rewards, dones);
		if (!stepped.ok) { unreachable; }
		batch = stepped.value;
	}
	return batch;
}

test "a batch opens on day one with every block on its first slot" {
	const batch = Batch.create(5, 3, 2, 12);
	assert batch.rows() == 6;
	assert batch.cursor.epoch == 1;
	assert batch.cursor.head == Head.Economy;
	assert batch.petOf(0) == 0;
	assert batch.petOf(1) == 10;
	assert batch.petOf(2) == 0;
	assert batch.worlds[0].seed != batch.worlds[1].seed;
	const observations = zeros(batch.rows() * observationSize(Head.Economy));
	const legal = zeros(batch.rows() * actionCount(Head.Economy));
	batch.observe(observations, legal);
	for (let row = 0; row < batch.rows(); row++) {
		assert legal[row * actionCount(Head.Economy) + (EconomyAction.Rest as int32)] == 1;
		assert observations[row * observationSize(Head.Economy)] > 0;
	}
}

test "heads step in order and a wrong head is refused" {
	const batch = Batch.create(5, 1, 1, 12);
	const actions = zeros(1);
	const rewards = zeros(1);
	const dones = zeros(1);
	assert !batch.step(Head.Attack, actions, rewards, dones).ok;
	actions[0] = holdAction(Head.Economy);
	const afterEconomy = batch.step(Head.Economy, actions, rewards, dones);
	assert afterEconomy.ok;
	if (afterEconomy.ok) {
		assert afterEconomy.value.cursor.head == Head.Node;
		assert afterEconomy.value.cursor.slot == 0;
		assert rewards[0] == 0;
		assert dones[0] == (Done.Running as int32);
	}
}

test "the teacher through the batch equals the teacher episode, block-parallel" {
	const start = Batch.create(21, 2, 2, 120);
	const batch = start.playTeacher(9);
	assert batch.cursor.epoch == 9;
	for (let env = 0; env < 2; env++) {
		const episode = playEpisode(2, 8, worldSeed(21, env, 0)).beginEpoch(9);
		const world = batch.worlds[env];
		assert world.stats.fights == episode.stats.fights;
		assert world.stats.fights > 0;
		assert world.stats.illegal == 0;
		assert world.global == episode.global;
		for (let index = 0; index < world.pets.length; index++) {
			assert world.pets[index] == episode.pets[index];
		}
	}
}

test "rewards add up to the change in score and an episode truncates then reopens" {
	let batch = Batch.create(33, 1, 1, 3);
	const actions = zeros(batch.rows());
	const rewards = zeros(batch.rows());
	const dones = zeros(batch.rows());
	const weights = RewardWeights.of(PersonaKind.Cautious);
	const before = batch.worlds[0].pets[0].score(weights);
	let earned: int64 = 0;
	let truncated = 0;
	let last: Pet = batch.worlds[0].pets[0];
	while (batch.episode == 0) {
		batch.teacherActions(actions);
		const slot = batch.cursor.slot;
		const stepped = batch.step(batch.cursor.head, actions, rewards, dones);
		if (!stepped.ok) { unreachable; }
		if (slot == 0) {
			earned += rewards[0] as int64;
			last = batch.worlds[0].pets[0];
		}
		if (dones[0] == (Done.Truncated as int32)) { truncated += 1; }
		batch = stepped.value;
	}
	assert earned == last.score(weights) - before;
	assert earned > 0;
	assert truncated == BLOCK_SLOTS;
	assert batch.episode == 1;
	assert batch.cursor.epoch == 1;
	assert batch.worlds[0].seed == worldSeed(33, 0, 1);
}

test "a dead pet scores the death weight once" {
	const weights = RewardWeights.of(PersonaKind.Greedy);
	const world = World.create(1, 4).beginEpoch(1);
	const alive = world.pets[2];
	const dead: Pet = { ...alive, alive: false, hearts: 0 };
	const wealth = (alive.harvest / MILLI_PER_UNIT) as int64;
	assert alive.score(weights) == 4 * weights.heartMilli + wealth;
	assert dead.score(weights) == -weights.deathMilli;
	const buried: Pet = { ...dead, harvest: 0, burrow: 0 };
	assert buried.score(weights) == dead.score(weights);
}

function blankPolicy(): uint8[] {
	const bytes: uint8[] = [];
	for (let position = 0; position < policyBytes(); position++) { bytes.push(0); }
	return bytes;
}

test "teacher-controlled slots play the same episode as teacher actions fed from outside" {
	const outside = Batch.create(21, 1, 2, 120).playTeacher(6);
	let inside = Batch.create(21, 1, 2, 120);
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		assert inside.assign(0, slot, CONTROL_TEACHER);
	}
	const actions = zeros(inside.rows());
	const rewards = zeros(inside.rows());
	const dones = zeros(inside.rows());
	const observations = zeros(inside.rows() * observationSize(Head.Node));
	const legal = zeros(inside.rows() * actionCount(Head.Attack));
	while (inside.cursor.epoch < 6) {
		inside.observe(observations, legal);
		assert legal[0] == 0 && observations[0] == 0;
		const stepped = inside.step(inside.cursor.head, actions, rewards, dones);
		if (!stepped.ok) { unreachable; }
		inside = stepped.value;
	}
	for (let index = 0; index < outside.worlds[0].pets.length; index++) {
		assert inside.worlds[0].pets[index] == outside.worlds[0].pets[index];
	}
}

test "a policy slot must be loaded before it controls a pet, and a blank policy plays legally" {
	let batch = Batch.create(8, 1, 1, 120);
	assert !batch.assign(0, 0, 0);
	assert !batch.assign(0, 0, POLICY_SLOTS);
	assert !batch.assign(1, 0, CONTROL_TEACHER);
	assert batch.withPolicy(0, blankPolicy());
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		assert batch.assign(0, slot, slot % 2 == 0 ? 0 : CONTROL_TEACHER);
	}
	const actions = zeros(batch.rows());
	const rewards = zeros(batch.rows());
	const dones = zeros(batch.rows());
	while (batch.cursor.epoch < 8) {
		const stepped = batch.step(batch.cursor.head, actions, rewards, dones);
		if (!stepped.ok) { unreachable; }
		batch = stepped.value;
	}
	assert batch.worlds[0].stats.illegal == 0;
	assert batch.worlds[0].pets[0].tree.nodeCount() > 1;
}
