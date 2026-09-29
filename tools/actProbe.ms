@include("runtime/solana/solana.h");
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
	BLOCK_SLOTS,
	Combatant,
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
	doEconomy,
	EconomyAction,
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
	attackMask,
	writeTarget,
	writeNode,
	summed,
	has,
	touches,
	rivalsInto,
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
const FIRST_SLOT_CONTEXT: int32 = FIRST_PET_ACCOUNT + BLOCK_SLOTS;
const HOLDER_IDS: int32 = FIRST_SLOT_CONTEXT + BLOCK_SLOTS;

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
	let rivals: Combatant[10] = [];
	const morning = context.surroundingsIn(block.pets, wilds.pets, settled);
	morning.rivalsInto(rivals);
	context.observedSelf(morning, rivals, self);
	logComputeUnits();
	const economy = context.economyChoice(blob.bytes, morning, self);
	logComputeUnits();
	const afterEconomy = context.appliedEconomy(block.pets, settled, economy);
	logComputeUnits();
	const growing = context.surroundingsIn(block.pets, wilds.pets, afterEconomy);
	const legal = growing.actorPet().legalNodes(afterEconomy);
	const growable = legal.bits != 0;
	if (growable) { context.observedSelfForNodeAndAttack(growing, self); }
	logComputeUnits();
	let nodes = 0;
	let node = ALLOCATE_HOLD;
	let afterNode = afterEconomy;
	if (growable) {
		const sums = growing.actorPet().tree.summed(growing.actorPet().level as int32);
		nodes = nodeRows(growing, legal, sums);
		logComputeUnits();
		node = nodeChoice(blob.bytes, growing, legal, self, sums);
		logComputeUnits();
		afterNode = context.appliedNode(block.pets, afterEconomy, node, sums);
	} else {
		logComputeUnits();
		logComputeUnits();
	}
	logComputeUnits();
	const armed = context.surroundingsIn(block.pets, wilds.pets, afterNode);
	context.observedSelfForNodeAndAttack(armed, self);
	logComputeUnits();
	const targets = targetRows(armed, rivals);
	logComputeUnits();
	const attack = attackChoice(blob.bytes, armed, rivals, self);
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
	const wilds = try wildsAt();
	const around = context.surroundingsIn(block.pets, wilds.pets, global);
	let self: int32[46] = [];
	let row: int32[22] = [];
	let rivals: Combatant[10] = [];
	around.rivalsInto(rivals);
	let frontier = 0;
	while (actor.tree.has(frontier) || !actor.tree.touches(frontier)) { frontier += 1; }
	logComputeUnits();
	context.observedSelf(around, rivals, self);
	logComputeUnits();
	const attacks = around.attackMask(fighter);
	logComputeUnits();
	around.writeTarget(((context.actor as int32) + 1) % BLOCK_SLOTS, fighter, rivals, row, 0);
	logComputeUnits();
	const sums = actor.tree.summed(actor.level as int32);
	logComputeUnits();
	block.pets[context.actor as int32].writeNode(frontier, sums, built, row, 0);
	logComputeUnits();
	logU64((built.might as uint64) + (derived.grit as uint64) + (fighter.hearts as uint64) +
		(odds as uint64) + (reachable.ok ? 1 : 0) + (dawn as uint64) + (hunger as uint64) +
		(nodes.bits & 1) + meal + ((economy as uint16) as uint64) +
		(pressure as uint64) + (logged as uint64) + (key.ratio as uint64) + (cell as uint64) +
		(signedSum as uint64) + (unsignedSum as uint64) + (self[0] as uint64) + attacks.bits +
		(row[0] as uint64));
	return Result.ok(0);
}

function economyCostsLogged(): Result<uint64, ProgramError> {
	const context = try contextAt();
	const config = try configAt();
	const block = try petsCopied();
	const global = loaded(config);
	const actor = block.pets[context.actor as int32];
	let legal: uint64 = 0;
	logComputeUnits();
	logComputeUnits();
	for (let ordinal = 0; ordinal <= (EconomyAction.BuyItem as int32); ordinal++) {
		if (actor.doEconomy(ordinal as EconomyAction, global, 0).ok) {
			legal = legal | ((1 as uint64) << (ordinal as uint64));
		}
		logComputeUnits();
	}
	logU64(legal);
	return Result.ok(0);
}

function digestLogged(): Result<uint64, ProgramError> {
	const config = try configAt();
	const block = try petsCopied();
	const digest = digestOf(block.pets, loaded(config));
	logU64(digest);
	return Result.ok(digest);
}

function actSeeds(id: uint8): Seeds {
	return Seeds.empty(2).addText("act").addU8(id);
}

function idIn(data: Bytes): Result<uint8, ProgramError> {
	const id = try data.readU64(8);
	if (id >= HOLDER_IDS as uint64) { return Result.err(ProgramError.invalidArgument()); }
	return Result.ok(id as uint8);
}

function verifiedBump(holder: Account, id: uint8): Result<uint8, ProgramError> {
	const expected = try actSeeds(id).findProgramAddress(programId());
	if (!expected.key.equals(holder.key())) { return Result.err(ProgramError.invalidSeeds()); }
	return Result.ok(expected.bump);
}

function initialized(data: Bytes): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const holder = try account(1);
	const id = try idIn(data);
	const size = try data.readU64(16);
	const bump = try verifiedBump(holder, id);
	if (holder.lamports() == 0) {
		const _created = try createProgramAccount(payer, holder, size, programId(), actSeeds(id).withBump(bump));
	}
	return Result.ok(holder.dataLength());
}

function written(data: Bytes): Result<uint64, ProgramError> {
	const _payer = try signerAccount(0);
	const holder = try account(1);
	const id = try idIn(data);
	const _bump = try verifiedBump(holder, id);
	if (!holder.isOwnedBy(programId())) { return Result.err(ProgramError.illegalOwner()); }
	const offset = try data.readU64(16);
	const chunk = try data.range(24, data.length - 24);
	const target = try holder.data().range(offset, chunk.length);
	return target.copyFrom(chunk);
}

function delegated(data: Bytes): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const systemProgram = try account(1);
	const holder = try account(2);
	const ownerProgram = try account(3);
	const buffer = try account(4);
	const delegationRecord = try account(5);
	const delegationMetadata = try account(6);
	const id = try idIn(data);
	const bump = try verifiedBump(holder, id);
	let config = DelegationConfig.anyValidator();
	if (accountCount() > 8) {
		const validator = try account(8);
		config = DelegationConfig.onValidator(validator.key());
	}
	const accounts: DelegationAccounts = {
		payer: payer,
		delegated: holder,
		ownerProgram: ownerProgram,
		buffer: buffer,
		delegationRecord: delegationRecord,
		delegationMetadata: delegationMetadata,
		systemProgram: systemProgram,
	};
	return delegate(accounts, actSeeds(id), bump, config);
}

function returned(): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const holder = try account(1);
	const magicContext = try account(3);
	return commitAndUndelegate(payer, holder, magicContext);
}

function undelegated(data: Bytes): Result<uint64, ProgramError> {
	const holder = try account(0);
	const buffer = try account(1);
	const payer = try account(2);
	return undelegate(holder, buffer, payer, programId(), data);
}

function dispatch(): Result<uint64, ProgramError> {
	const data = instructionData();
	if (isUndelegateCallback(data)) { return undelegated(data); }
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
		5 => economyCostsLogged(),
		3 => written(data),
		7 => initialized(data),
		8 => delegated(data),
		9 => returned(),
		_ => Result.err(ProgramError.invalidInstructionData()),
	};
}

function main(): void {
	const outcome = dispatch();
	if (!outcome.ok) { failWith(outcome.error); }
}

main();
