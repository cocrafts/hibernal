@include("rawBytes.h");
@compile("rawBytes.c");
import { readLines, writeFile } from "std/fs";
import {
	ACTS_PER_EPOCH,
	ALLOCATE_HOLD,
	ATTACK_HOLD,
	BLOCK_SLOTS,
	BlockSlot,
	EconomyAction,
	GlobalConfig,
	Pet,
	attackHoldMask,
	checkPolicy,
	mixSeeds,
} from "../rules/index";
import {
	EPISODE_EPOCHS,
	World,
	actorAt,
	applyEconomy,
	applyNode,
	attackMaskFor,
	beginEpoch,
	endEpoch,
	inRound,
	marketViewOf,
	robberOf,
	staggered,
} from "../sim/world";
import { act, personaKindOf } from "../sim/teacher";
import {
	Head,
	actionCount,
	largestActionCount,
	legalInto,
	observationSize,
	observeInto,
	zeros,
} from "../sim/env/observe";
import { Scratch, bestLegal, create, logitsInto } from "../sim/env/actor";
import { engineVersion } from "../sim/digests";
import { ActChoice, ActContext, actOnce, buffersMatchRules, digestOf } from "./actBench";

extern function hibernalPetBytes(target: Span<uint8>, source: Span<Pet>, elementBytes: int64): void;
extern function hibernalContextBytes(
	target: Span<uint8>,
	source: Span<ActContext>,
	elementBytes: int64,
): void;
extern function hibernalGlobalBytes(
	target: Span<uint8>,
	source: Span<GlobalConfig>,
	elementBytes: int64,
): void;

const PROBE_DIRECTORY = "out/actProbe";
const WORLD_SEED: uint64 = 9001;
const TYPICAL_DAY: uint64 = 40;
const TYPICAL_ROUND: int32 = 2;
const BUSY_FROM_DAY: uint64 = 30;

enum Scenario {
	Typical,
	Busiest,
}

struct Moment {
	day: uint64;
	round: int32;
	turn: int32;
	index: int32;
}

struct Reference {
	choice: ActChoice;
	digest: uint64;
}

enum HostError {
	NoPolicy,
	NoMoment,
	Tick,
	Mismatch,
	Write,
}

function holdAction(head: Head): int32 {
	return match (head) {
		Head.Economy => EconomyAction.Rest as int32,
		Head.Node => ALLOCATE_HOLD,
		Head.Attack => ATTACK_HOLD,
	};
}

function matches(this world: World, index: int32, moment: Moment, scenario: Scenario): boolean {
	const pet = world.pets[index];
	if (!pet.alive) { return false; }
	return match (scenario) {
		Scenario.Typical => moment.day == TYPICAL_DAY && moment.round == TYPICAL_ROUND,
		Scenario.Busiest =>
			moment.day >= BUSY_FROM_DAY &&
			moment.round == 0 &&
			pet.pointsUnspent > 0 &&
			world.attackMaskFor(index).bits != attackHoldMask().bits,
	};
}

function momentOf(scenario: Scenario): Result<Moment, HostError> {
	let world = World.staggered(1, WORLD_SEED);
	for (let day: uint64 = 1; day <= (EPISODE_EPOCHS as uint64); day++) {
		world = world.beginEpoch(day);
		for (let round = 0; round < ACTS_PER_EPOCH; round++) {
			world = world.inRound(round);
			for (let turn = 0; turn < world.pets.length; turn++) {
				const index = world.actorAt(turn);
				const moment: Moment = { day: day, round: round, turn: turn, index: index };
				if (world.matches(index, moment, scenario)) { return Result.ok(moment); }
				world = world.act(index);
			}
		}
		world = world.endEpoch();
	}
	return Result.err(HostError.NoMoment);
}

function worldAt(moment: Moment): World {
	let world = World.staggered(1, WORLD_SEED);
	for (let day: uint64 = 1; day <= moment.day; day++) {
		world = world.beginEpoch(day);
		for (let round = 0; round < ACTS_PER_EPOCH; round++) {
			world = world.inRound(round);
			for (let turn = 0; turn < world.pets.length; turn++) {
				if (day == moment.day && round == moment.round && turn == moment.turn) { return world; }
				world = world.act(world.actorAt(turn));
			}
		}
		world = world.endEpoch();
	}
	return world;
}

function worldBeforeDawn(day: uint64): World {
	let world = World.staggered(1, WORLD_SEED);
	for (let previous: uint64 = 1; previous < day; previous++) {
		world = world.beginEpoch(previous);
		for (let round = 0; round < ACTS_PER_EPOCH; round++) {
			world = world.inRound(round);
			for (let turn = 0; turn < world.pets.length; turn++) {
				world = world.act(world.actorAt(turn));
			}
		}
		world = world.endEpoch();
	}
	return world;
}

function contextOf(this world: World, index: int32, epoch: uint64, round: int32): ActContext {
	const dated: World = { ...world, epoch: epoch, round: round };
	const turnSeed = (epoch << (2 as uint64)) | (round as uint64);
	return {
		epoch: epoch,
		round: round,
		actor: (index % BLOCK_SLOTS) as BlockSlot,
		persona: personaKindOf(index),
		robber: dated.robberOf(index),
		market: dated.marketViewOf(index),
		economySeed: mixSeeds(mixSeeds(mixSeeds(world.seed, 7919), index as uint64), turnSeed),
		trader: index as uint32,
	};
}

function copied(pets: Pet[]): Pet[] {
	const copy: Pet[] = [];
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) { copy.push(pets[slot]); }
	return copy;
}

function zeroBytes(count: int32): uint8[] {
	const bytes: uint8[] = [];
	for (let position = 0; position < count; position++) { bytes.push(0); }
	return bytes;
}

function line(name: string, bytes: uint8[]): string {
	let text = name;
	for (const value of bytes) { text = text + ` ${value}`; }
	return text + "\n";
}

function petLine(name: string, pets: Pet[]): string {
	const bytes = zeroBytes(pets.length * (sizeof Pet as int32));
	hibernalPetBytes(bytes, pets, sizeof Pet as int64);
	return line(name, bytes);
}

function contextLine(context: ActContext): string {
	const bytes = zeroBytes(sizeof ActContext as int32);
	const contexts: ActContext[] = [context];
	hibernalContextBytes(bytes, contexts, sizeof ActContext as int64);
	return line("context", bytes);
}

function globalLine(name: string, global: GlobalConfig): string {
	const bytes = zeroBytes(sizeof GlobalConfig as int32);
	const globals: GlobalConfig[] = [global];
	hibernalGlobalBytes(bytes, globals, sizeof GlobalConfig as int64);
	return line(name, bytes);
}

function policyChoice(
	this world: World,
	index: int32,
	head: Head,
	scratch: Scratch,
	policy: uint8[],
): int32 {
	const observations = zeros(observationSize(head));
	const legal = zeros(actionCount(head));
	const logits = zeros(largestActionCount());
	world.observeInto(index, head, observations, 0);
	world.legalInto(index, head, legal, 0);
	scratch.logitsInto(policy, head, observations, 0, legal, 0, logits, 0);
	return bestLegal(head, logits, 0, legal, 0, holdAction(head));
}

function referenceOf(world: World, index: int32, policy: uint8[]): Reference {
	const scratch = Scratch.create();
	const economy = world.policyChoice(index, Head.Economy, scratch, policy);
	const afterEconomy = world.applyEconomy(index, economy as EconomyAction);
	const node = afterEconomy.policyChoice(index, Head.Node, scratch, policy);
	const afterNode = afterEconomy.applyNode(index, node);
	const attack = afterNode.policyChoice(index, Head.Attack, scratch, policy);
	const choice: ActChoice = { economy: economy as EconomyAction, node: node, attack: attack };
	return { choice: choice, digest: digestOf(copied(afterNode.pets), afterNode.global) };
}

function sameChoice(left: ActChoice, right: ActChoice): boolean {
	return left.economy == right.economy && left.node == right.node && left.attack == right.attack;
}

function written(
	name: string,
	moment: Moment,
	world: World,
	context: ActContext,
	policy: uint8[],
	checkSim: boolean,
): Result<ActChoice, HostError> {
	const pets = copied(world.pets);
	const wilds = copied(world.wilds);
	const before = petLine("pets", pets) + petLine("wilds", wilds) + contextLine(context) +
		globalLine("global", world.global);
	const outcome = context.actOnce(policy, pets, wilds, world.global);
	if (!outcome.ok) { return Result.err(HostError.Tick); }
	const choice = outcome.value.choice;
	const digest = digestOf(pets, outcome.value.global);
	if (checkSim) {
		const reference = referenceOf(world, moment.index, policy);
		const agrees = sameChoice(choice, reference.choice) && digest == reference.digest;
		const simChoice = reference.choice;
		console.log(`${name}: sim ${simChoice.economy as int32} ${simChoice.node} ${simChoice.attack} digest 0x${reference.digest.toString(16)} · bench agrees ${agrees}`);
		if (!agrees) { return Result.err(HostError.Mismatch); }
	}
	const header = `scenario ${name} day ${moment.day} round ${moment.round} actor ${context.actor as int32}\n`;
	const tail = `choice ${choice.economy as int32} ${choice.node} ${choice.attack}\n` +
		`digest ${digest}\nengine ${engineVersion()}\n` +
		petLine("after", pets) + globalLine("afterGlobal", outcome.value.global);
	const saved = writeFile(`${PROBE_DIRECTORY}/${name}.txt`, header + before + tail);
	if (!saved.ok) { return Result.err(HostError.Write); }
	console.log(`${name}: day ${moment.day} round ${moment.round} slot ${context.actor as int32} · points ${pets[context.actor as int32].pointsUnspent} · choice ${choice.economy as int32} ${choice.node} ${choice.attack} · digest 0x${digest.toString(16)}`);
	return Result.ok(choice);
}

function policyBytes(): Result<uint8[], HostError> {
	const lines = readLines(`${PROBE_DIRECTORY}/policy.txt`);
	if (!lines.ok) { return Result.err(HostError.NoPolicy); }
	const policy: uint8[] = [];
	for (const text of lines.value) {
		if (text.length > 0) { policy.push(parseInt(text) as uint8); }
	}
	if (!checkPolicy(policy, engineVersion()).ok) { return Result.err(HostError.NoPolicy); }
	return Result.ok(policy);
}

function run(): Result<int32, HostError> {
	if (!buffersMatchRules()) { return Result.err(HostError.Mismatch); }
	const policy = try policyBytes();
	const typical = try momentOf(Scenario.Typical);
	const typicalWorld = worldAt(typical);
	const typicalContext = typicalWorld.contextOf(typical.index, typical.day, typical.round);
	const _typical = try written("typical", typical, typicalWorld, typicalContext, policy, true);
	const busiest = try momentOf(Scenario.Busiest);
	const busiestWorld = worldAt(busiest);
	const busiestContext = busiestWorld.contextOf(busiest.index, busiest.day, busiest.round);
	const _busiest = try written("busiest", busiest, busiestWorld, busiestContext, policy, true);
	const dawnWorld = worldBeforeDawn(busiest.day);
	const dawnContext = dawnWorld.contextOf(busiest.index, busiest.day, 0);
	const _dawn = try written("dawn", busiest, dawnWorld, dawnContext, policy, false);
	return Result.ok(0);
}

function main(): int32 {
	const outcome = run();
	if (!outcome.ok) {
		console.log(`actHost failed: ${outcome.error as int32}`);
		return 1;
	}
	return 0;
}

process.exit(main());
