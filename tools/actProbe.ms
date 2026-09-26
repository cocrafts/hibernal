@include("runtime/solana/solana.h");
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
	BLOCK_SLOTS,
	Food,
	GlobalConfig,
	Pet,
	Stats,
	attackable,
	built,
	checkPolicy,
	combatant,
	combatantFacing,
	dawnHearts,
	foodCost,
	hungerPerDay,
	legalEconomy,
	legalNodes,
	ALLOCATE_HOLD,
	actorPet,
	ownStats,
	stats,
	talent,
	winChanceFromTable,
	pressureBps,
	log2Times32,
	oddsKeyAgainst,
	winChanceBps,
} from "../rules/index";
import { POLICY_BLOB_BYTES, PolicyBlob, buffersMatchPolicy } from "./policyBench";
import {
	ActChoice,
	ActContext,
	BlockPets,
	actTicked,
	appliedEconomy,
	appliedNode,
	attackChoice,
	buffersMatchRules,
	digestOf,
	economyChoice,
	nodeChoice,
	nodeRows,
	observedSelf,
	observedSelfForNodeAndAttack,
	surroundingsIn,
	targetRows,
} from "./actBench";

extern function msSolAlloc(size: uint64): uint64;

const POLICY_ACCOUNT: int32 = 0;
const CONTEXT_ACCOUNT: int32 = 1;
const CONFIG_ACCOUNT: int32 = 2;
const WILDS_ACCOUNT: int32 = 3;
const FIRST_PET_ACCOUNT: int32 = 4;

enum ProbeError {
	Layout,
	Policy,
	Unticked,
}

function failed(error: ProbeError): ProgramError {
	return ProgramError.custom(200 + (error as uint32));
}

function sized(holder: Account, bytes: uint64): Result<uint64, ProgramError> {
	if (holder.dataLength() != bytes) { return Result.err(failed(ProbeError.Layout)); }
	return Result.ok(holder.data().address);
}

function policyAt(engine: uint64): Result<Ptr<PolicyBlob>, ProgramError> {
	const holder = try account(POLICY_ACCOUNT);
	const address = try sized(holder, POLICY_BLOB_BYTES as uint64);
	const blob = address as Ptr<PolicyBlob>;
	if (!buffersMatchPolicy() || !checkPolicy(blob.bytes, engine).ok) {
		return Result.err(failed(ProbeError.Policy));
	}
	return Result.ok(blob);
}

function contextAt(): Result<ActContext, ProgramError> {
	const holder = try account(CONTEXT_ACCOUNT);
	const raw = (try sized(holder, sizeof ActContext as uint64)) as Ptr<ActContext>;
	return Result.ok({
		epoch: raw.epoch,
		round: raw.round,
		actor: raw.actor,
		persona: raw.persona,
		robber: raw.robber,
		market: raw.market,
		economySeed: raw.economySeed,
		trader: raw.trader,
	});
}

function configAt(): Result<Ptr<GlobalConfig>, ProgramError> {
	const holder = try account(CONFIG_ACCOUNT);
	return Result.ok((try sized(holder, sizeof GlobalConfig as uint64)) as Ptr<GlobalConfig>);
}

function loaded(raw: Ptr<GlobalConfig>): GlobalConfig {
	return {
		genesisTimestamp: raw.genesisTimestamp,
		rewardPerWorkPower: raw.rewardPerWorkPower,
		rewardEpoch: raw.rewardEpoch,
		totalWorkPower: raw.totalWorkPower,
		recycledPending: raw.recycledPending,
		protocolPending: raw.protocolPending,
		burned: raw.burned,
		livingPets: raw.livingPets,
		floorSlots: raw.floorSlots,
	};
}

function stored(raw: Ptr<GlobalConfig>, global: GlobalConfig): void {
	raw.genesisTimestamp = global.genesisTimestamp;
	raw.rewardPerWorkPower = global.rewardPerWorkPower;
	raw.rewardEpoch = global.rewardEpoch;
	raw.totalWorkPower = global.totalWorkPower;
	raw.recycledPending = global.recycledPending;
	raw.protocolPending = global.protocolPending;
	raw.burned = global.burned;
	raw.livingPets = global.livingPets;
	raw.floorSlots = global.floorSlots;
}

function wildsAt(): Result<Ptr<BlockPets>, ProgramError> {
	const holder = try account(WILDS_ACCOUNT);
	return Result.ok((try sized(holder, sizeof BlockPets as uint64)) as Ptr<BlockPets>);
}

function petsCopied(): Result<Ptr<BlockPets>, ProgramError> {
	const heap = msSolAlloc(sizeof BlockPets as uint64);
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		const holder = try account(FIRST_PET_ACCOUNT + slot);
		const _address = try sized(holder, sizeof Pet as uint64);
		const target: Bytes = {
			address: heap + (slot as uint64) * (sizeof Pet as uint64),
			length: sizeof Pet as uint64,
		};
		const _copied = try target.copyFrom(holder.data());
	}
	return Result.ok(heap as Ptr<BlockPets>);
}

function petsWritten(block: Ptr<BlockPets>): Result<uint64, ProgramError> {
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		const holder = try account(FIRST_PET_ACCOUNT + slot);
		const source: Bytes = {
			address: (block as uint64) + (slot as uint64) * (sizeof Pet as uint64),
			length: sizeof Pet as uint64,
		};
		const _copied = try holder.data().copyFrom(source);
	}
	return Result.ok(0);
}

function ticked(this context: ActContext, pets: Span<Pet>): boolean {
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		if (pets[slot].alive && pets[slot].lastTickEpoch < context.epoch) { return false; }
	}
	return true;
}

function logChoice(choice: ActChoice): void {
	logU64(choice.economy as uint64);
	logU64(choice.node as uint64);
	logU64(choice.attack as uint64);
}

function actSplit(engine: uint64, write: boolean): Result<uint64, ProgramError> {
	logComputeUnits();
	logComputeUnits();
	const blob = try policyAt(engine);
	const context = try contextAt();
	const config = try configAt();
	const wilds = try wildsAt();
	const block = try petsCopied();
	if (!buffersMatchRules()) { return Result.err(failed(ProbeError.Layout)); }
	const settled = loaded(config);
	if (!context.ticked(block.pets)) { return Result.err(failed(ProbeError.Unticked)); }
	logComputeUnits();
	let self: int32[46] = [];
	const morning = context.surroundingsIn(block.pets, wilds.pets, settled);
	context.observedSelf(morning, self);
	logComputeUnits();
	const economy = context.economyChoice(blob.bytes, morning, self);
	logComputeUnits();
	const afterEconomy = context.appliedEconomy(block.pets, settled, economy);
	logComputeUnits();
	const growing = context.surroundingsIn(block.pets, wilds.pets, afterEconomy);
	const growable = growing.actorPet().legalNodes(afterEconomy).bits != 0;
	if (growable) { context.observedSelfForNodeAndAttack(growing, self); }
	logComputeUnits();
	const nodes = growable ? nodeRows(growing) : 0;
	logComputeUnits();
	const node = growable ? nodeChoice(blob.bytes, growing, self) : ALLOCATE_HOLD;
	logComputeUnits();
	const afterNode = context.appliedNode(block.pets, afterEconomy, node);
	logComputeUnits();
	const armed = context.surroundingsIn(block.pets, wilds.pets, afterNode);
	context.observedSelfForNodeAndAttack(armed, self);
	logComputeUnits();
	const targets = targetRows(armed);
	logComputeUnits();
	const attack = attackChoice(blob.bytes, armed, self);
	logComputeUnits();
	if (write) {
		const _pets = try petsWritten(block);
		stored(config, afterNode);
	}
	logComputeUnits();
	logChoice({ economy: economy, node: node, attack: attack });
	logU64((nodes as uint64) | ((targets as uint64) << 32));
	logU64(digestOf(block.pets, afterNode));
	return Result.ok(0);
}

function actPlain(engine: uint64, write: boolean): Result<uint64, ProgramError> {
	const blob = try policyAt(engine);
	const context = try contextAt();
	const config = try configAt();
	const wilds = try wildsAt();
	const block = try petsCopied();
	if (!context.ticked(block.pets)) { return Result.err(failed(ProbeError.Unticked)); }
	const outcome = context.actTicked(blob.bytes, block.pets, wilds.pets, loaded(config));
	if (write) {
		const _pets = try petsWritten(block);
		stored(config, outcome.global);
	}
	logChoice(outcome.choice);
	return Result.ok(0);
}

function costsLogged(): Result<uint64, ProgramError> {
	const context = try contextAt();
	const config = try configAt();
	const block = try petsCopied();
	const global = loaded(config);
	const actor = block.pets[context.actor as int32];
	const mate = block.pets[((context.actor as int32) + 1) % BLOCK_SLOTS];
	logComputeUnits();
	logComputeUnits();
	const built = Stats.built(actor.tree, actor.level as int32, actor.talent());
	logComputeUnits();
	const derived = actor.stats();
	logComputeUnits();
	const fighter = actor.combatant();
	logComputeUnits();
	const facing = mate.combatantFacing(actor);
	logComputeUnits();
	const odds = facing.winChanceFromTable(actor.combatantFacing(mate));
	logComputeUnits();
	const reachable = mate.attackable(actor, context.epoch);
	logComputeUnits();
	const dawn = actor.dawnHearts();
	logComputeUnits();
	const hunger = actor.ownStats().hungerPerDay();
	logComputeUnits();
	const economy = actor.legalEconomy(global);
	logComputeUnits();
	const nodes = actor.legalNodes(global);
	logComputeUnits();
	const meal = foodCost(Food.Small, actor.level as int32);
	logComputeUnits();
	const target = actor.combatantFacing(mate);
	logComputeUnits();
	const pressure = facing.pressureBps(target);
	logComputeUnits();
	const logged = log2Times32(123456789);
	logComputeUnits();
	const key = facing.oddsKeyAgainst(target);
	logComputeUnits();
	const cell = key.winChanceBps();
	logComputeUnits();
	let signedSum = 0;
	for (let step = 0; step < 100; step++) {
		signedSum += ((actor.might as int32) + step) / (7 + (context.round as int32));
	}
	logComputeUnits();
	let unsignedSum: uint32 = 0;
	for (let step = 0; step < 100; step++) {
		unsignedSum += ((actor.might as uint32) + (step as uint32)) / (7 + (context.round as uint32));
	}
	logComputeUnits();
	logU64((built.might as uint64) + (derived.grit as uint64) + (fighter.hearts as uint64) +
		(odds as uint64) + (reachable.ok ? 1 : 0) + (dawn as uint64) + (hunger as uint64) +
		(nodes.bits & 1) + meal + ((economy as uint16) as uint64) +
		(pressure as uint64) + (logged as uint64) + (key.ratio as uint64) + (cell as uint64) +
		(signedSum as uint64) + (unsignedSum as uint64));
	return Result.ok(0);
}

function digestLogged(): Result<uint64, ProgramError> {
	const config = try configAt();
	const block = try petsCopied();
	const digest = digestOf(block.pets, loaded(config));
	logU64(digest);
	return Result.ok(digest);
}

function written(data: Bytes): Result<uint64, ProgramError> {
	const holder = try account(0);
	const offset = try data.readU64(8);
	const chunk = try data.range(16, data.length - 16);
	const target = try holder.data().range(offset, chunk.length);
	return target.copyFrom(chunk);
}

function dispatch(): Result<uint64, ProgramError> {
	const data = instructionData();
	const discriminator = try data.readU64(0);
	return match (discriminator) {
		0 => {
			const engine = try data.readU64(8);
			const write = try data.readU8(16);
			return actSplit(engine, write == 1);
		},
		1 => {
			const engine = try data.readU64(8);
			const write = try data.readU8(16);
			return actPlain(engine, write == 1);
		},
		2 => digestLogged(),
		4 => costsLogged(),
		3 => written(data),
		_ => Result.err(ProgramError.invalidInstructionData()),
	};
}

function main(): void {
	const outcome = dispatch();
	if (!outcome.ok) { failWith(outcome.error); }
}

main();
