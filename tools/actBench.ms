import {
	BLOCK_SLOTS,
	TREE_NODES,
	ALLOCATE_HOLD,
	ATTACK_HOLD,
	STAKE_LEVELS,
	FEATURE_ONE,
	SELF_FEATURES,
	NODE_FEATURES,
	TARGET_FEATURES,
	NODE_SELF_INPUTS,
	ATTACK_SELF_INPUTS,
	ECONOMY_INPUTS,
	ECONOMY_HIDDEN,
	ECONOMY_OUTPUTS,
	NODE_INPUTS,
	NODE_HIDDEN,
	ATTACK_INPUTS,
	ATTACK_HIDDEN,
	ATTACK_NARROW,
	ATTACK_OUTPUTS,
	AttackMask,
	BlockSlot,
	Combatant,
	EconomyAction,
	Item,
	GlobalConfig,
	GrudgeError,
	MarketView,
	Pet,
	PersonaKind,
	SelfFeature,
	Stats,
	Surroundings,
	TickError,
	TreeSums,
	allowsChoice,
	allowsNode,
	allocateNodeWithSums,
	actorPet,
	attackHoldMask,
	attackLogits,
	attackMask,
	combatant,
	attackSelfInput,
	boughtListing,
	finished,
	summed,
	doEconomy,
	economyLogits,
	economyMask,
	foldEatIntoBuy,
	foldPortionSizes,
	legalNodes,
	NodeMask,
	listedItem,
	nodeScore,
	nodeSelfInput,
	paidFor,
	splitmix,
	stats,
	talent,
	tickTo,
	writeNode,
	writeNodeHold,
	writeSelf,
	writeSelfForNodeAndAttack,
	writeTarget,
	writeTargetHold,
	rivalsInto,
} from "../rules/index";

export struct BlockPets {
	pets: Pet[10];
}

export struct ActContext {
	epoch: uint64;
	round: int32;
	actor: BlockSlot;
	persona: PersonaKind;
	robber: Result<BlockSlot, GrudgeError>;
	market: MarketView;
	economySeed: uint64;
	trader: uint32;
}

export struct ActChoice {
	economy: EconomyAction;
	node: int32;
	attack: int32;
}

export struct ActOutcome {
	choice: ActChoice;
	global: GlobalConfig;
}

export function buffersMatchRules(): boolean {
	return SELF_FEATURES == 46 && NODE_FEATURES == 22 && TARGET_FEATURES == 13 &&
		NODE_SELF_INPUTS == 8 && ATTACK_SELF_INPUTS == 12 &&
		ECONOMY_INPUTS == 46 && ECONOMY_HIDDEN == 32 && ECONOMY_OUTPUTS == 12 &&
		NODE_INPUTS == 30 && NODE_HIDDEN == 32 &&
		ATTACK_INPUTS == 25 && ATTACK_HIDDEN == 32 && ATTACK_NARROW == 16 && ATTACK_OUTPUTS == 4 &&
		BLOCK_SLOTS == 10 && ATTACK_HOLD == 40 && ALLOCATE_HOLD == 64;
}

export function surroundingsIn(
	this context: ActContext,
	pets: Span<Pet>,
	wilds: Span<Pet>,
	global: GlobalConfig,
): Surroundings {
	return {
		pets: pets,
		wilds: wilds,
		base: 0,
		actor: context.actor,
		global: global,
		epoch: context.epoch,
		round: context.round,
		robber: context.robber,
	};
}

export function tickedActor(
	this context: ActContext,
	pets: Span<Pet>,
	global: GlobalConfig,
): Result<GlobalConfig, TickError> {
	const slot = context.actor as int32;
	if (pets[slot].lastTickEpoch >= context.epoch) { return Result.ok(global); }
	const ticked = try pets[slot].tickTo(global, context.epoch);
	pets[slot] = ticked.pet;
	return Result.ok(ticked.global);
}

export function tickedNeighbours(
	this context: ActContext,
	pets: Span<Pet>,
	global: GlobalConfig,
): Result<GlobalConfig, TickError> {
	let settled = global;
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		const pet = pets[slot];
		if (slot == (context.actor as int32) || !pet.alive || pet.lastTickEpoch >= context.epoch) {
			continue;
		}
		const ticked = try pet.tickTo(settled, context.epoch);
		pets[slot] = ticked.pet;
		settled = ticked.global;
	}
	return Result.ok(settled);
}

export function observedSelf(
	this context: ActContext,
	around: Surroundings,
	rivals: Span<Combatant>,
	self: Span<int32>,
): void {
	for (let position = 0; position < self.length; position++) { self[position] = 0; }
	around.writeSelf(context.persona, context.market, rivals, self, 0);
}

export function observedSelfForNodeAndAttack(
	this context: ActContext,
	around: Surroundings,
	self: Span<int32>,
): void {
	for (let position = 0; position < self.length; position++) { self[position] = 0; }
	around.writeSelfForNodeAndAttack(context.persona, around.actorPet().stats(), self, 0);
}

export function economyChoice(
	this context: ActContext,
	policy: Span<uint8>,
	around: Surroundings,
	self: Span<int32>,
): EconomyAction {
	const legal = around.economyMask(context.market);
	let hidden: int32[32] = [];
	let logits: int32[12] = [];
	economyLogits(policy, self, hidden, logits);
	foldEatIntoBuy(logits, legal, self[SelfFeature.Hearts as int32] >= FEATURE_ONE);
	foldPortionSizes(logits, legal);
	let best = EconomyAction.Rest;
	let found = false;
	for (let ordinal = 0; ordinal < ECONOMY_OUTPUTS; ordinal++) {
		if (!legal.has(ordinal as EconomyAction)) { continue; }
		if (!found || logits[ordinal] > logits[best as int32]) {
			best = ordinal as EconomyAction;
			found = true;
		}
	}
	return best;
}

export function appliedEconomy(
	this context: ActContext,
	pets: Span<Pet>,
	global: GlobalConfig,
	action: EconomyAction,
): GlobalConfig {
	const slot = context.actor as int32;
	const pet = pets[slot];
	if (!pet.alive) { return global; }
	if (action == EconomyAction.ListItem) {
		const listed = pet.listedItem(global, context.trader, context.epoch);
		if (!listed.ok) { return global; }
		pets[slot] = listed.value.pet;
		return listed.value.global;
	}
	if (action == EconomyAction.BuyItem) {
		if (!context.market.offer.ok) { return global; }
		const listing = context.market.offer.value;
		const bought = pet.boughtListing(listing, context.trader, global);
		if (!bought.ok) { return global; }
		pets[slot] = bought.value.buyer;
		const seller = (listing.seller as int32) % BLOCK_SLOTS;
		const paid = pets[seller].paidFor(listing, bought.value.proceeds, bought.value.global);
		pets[seller] = paid.pet;
		return paid.global;
	}
	const economy = pet.doEconomy(action, global, context.economySeed);
	if (!economy.ok) { return global; }
	pets[slot] = economy.value.pet;
	return economy.value.global;
}

export function nodeRows(around: Surroundings, legal: NodeMask, sums: TreeSums): int32 {
	const pet = around.actorPet();
	if (legal.bits == 0) { return 0; }
	const before = sums.finished(pet.tree, pet.talent());
	let row: int32[22] = [];
	let rows = 0;
	for (let id = 0; id < TREE_NODES; id++) {
		if (!legal.allowsNode(id)) { continue; }
		for (let position = 0; position < NODE_FEATURES; position++) { row[position] = 0; }
		pet.writeNode(id, sums, before, row, 0);
		rows += 1;
	}
	return rows;
}

export function nodeChoice(
	policy: Span<uint8>,
	around: Surroundings,
	legal: NodeMask,
	self: Span<int32>,
	sums: TreeSums,
): int32 {
	const pet = around.actorPet();
	if (legal.bits == 0) { return ALLOCATE_HOLD; }
	const before = sums.finished(pet.tree, pet.talent());
	let input: int32[30] = [];
	let hidden: int32[32] = [];
	let score: int32[1] = [];
	for (let position = 0; position < NODE_SELF_INPUTS; position++) {
		input[position] = self[nodeSelfInput(position) as int32];
	}
	let best = ALLOCATE_HOLD;
	let bestScore = 0;
	let found = false;
	for (let id = 0; id <= ALLOCATE_HOLD; id++) {
		if (!legal.allowsNode(id)) { continue; }
		for (let position = NODE_SELF_INPUTS; position < NODE_INPUTS; position++) { input[position] = 0; }
		if (id == ALLOCATE_HOLD) {
			writeNodeHold(input, NODE_SELF_INPUTS);
		} else {
			pet.writeNode(id, sums, before, input, NODE_SELF_INPUTS);
		}
		const value = nodeScore(policy, input, hidden, score);
		if (!found || value > bestScore) {
			best = id;
			bestScore = value;
			found = true;
		}
	}
	return best;
}

export function appliedNode(
	this context: ActContext,
	pets: Span<Pet>,
	global: GlobalConfig,
	node: int32,
	sums: TreeSums,
): GlobalConfig {
	const slot = context.actor as int32;
	const pet = pets[slot];
	if (!pet.alive || node == ALLOCATE_HOLD) { return global; }
	const grown = pet.allocateNodeWithSums(node, global, sums);
	if (!grown.ok) { return global; }
	pets[slot] = grown.value.pet;
	return grown.value.global;
}

function wantsSlot(mask: AttackMask, slot: int32): boolean {
	if (slot == BLOCK_SLOTS) { return mask.allowsChoice(ATTACK_HOLD); }
	for (let level = 0; level < STAKE_LEVELS; level++) {
		if (mask.allowsChoice(slot * STAKE_LEVELS + level)) { return true; }
	}
	return false;
}

export function targetRows(around: Surroundings, rivals: Span<Combatant>): int32 {
	const own = around.actorPet().combatant();
	const mask = around.attackMask(own);
	if (mask.bits == attackHoldMask().bits) { return 0; }
	let row: int32[13] = [];
	let rows = 0;
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		if (!wantsSlot(mask, slot)) { continue; }
		for (let position = 0; position < TARGET_FEATURES; position++) { row[position] = 0; }
		around.writeTarget(slot, own, rivals, row, 0);
		rows += 1;
	}
	return rows;
}

export function attackChoice(
	policy: Span<uint8>,
	around: Surroundings,
	rivals: Span<Combatant>,
	self: Span<int32>,
): int32 {
	const own = around.actorPet().combatant();
	const mask = around.attackMask(own);
	if (mask.bits == attackHoldMask().bits) { return ATTACK_HOLD; }
	let input: int32[25] = [];
	let hidden: int32[32] = [];
	let narrow: int32[16] = [];
	let out: int32[4] = [];
	let logits: int32[41] = [];
	for (let position = 0; position < ATTACK_SELF_INPUTS; position++) {
		input[position] = self[attackSelfInput(position) as int32];
	}
	for (let slot = 0; slot <= BLOCK_SLOTS; slot++) {
		if (!wantsSlot(mask, slot)) { continue; }
		for (let position = ATTACK_SELF_INPUTS; position < ATTACK_INPUTS; position++) {
			input[position] = 0;
		}
		if (slot == BLOCK_SLOTS) {
			writeTargetHold(input, ATTACK_SELF_INPUTS);
		} else {
			around.writeTarget(slot, own, rivals, input, ATTACK_SELF_INPUTS);
		}
		attackLogits(policy, input, hidden, narrow, out);
		if (slot == BLOCK_SLOTS) {
			logits[ATTACK_HOLD] = out[0];
			continue;
		}
		for (let level = 0; level < ATTACK_OUTPUTS; level++) {
			if (mask.allowsChoice(slot * STAKE_LEVELS + level)) {
				logits[slot * STAKE_LEVELS + level] = out[level];
			}
		}
	}
	let best = ATTACK_HOLD;
	let found = false;
	for (let choice = 0; choice <= ATTACK_HOLD; choice++) {
		if (!mask.allowsChoice(choice)) { continue; }
		if (!found || logits[choice] > logits[best]) {
			best = choice;
			found = true;
		}
	}
	return best;
}

struct Digest {
	value: uint64;
}

function absorb(this digest: Digest, input: uint64): Digest {
	return { value: splitmix(digest.value ^ input) };
}

function absorbItem(this digest: Digest, item: Item): Digest {
	return digest.absorb(
		(item.rarity as uint64) |
		((item.stat as uint64) << 8) |
		((item.wear as uint64) << 16) |
		((item.skill as uint64) << 24) |
		((item.level as uint64) << 32),
	);
}

function absorbPet(this digest: Digest, pet: Pet): Digest {
	return digest
		.absorb((pet.blockId as uint64) | ((pet.slot as uint64) << 32) | ((pet.alive ? 1 as uint64 : 0 as uint64) << 40))
		.absorb((pet.region as uint64) | ((pet.hearts as uint64) << 8) | ((pet.maxHearts as uint64) << 16))
		.absorb((pet.forage as uint64) | ((pet.might as uint64) << 16) | ((pet.grit as uint64) << 32))
		.absorb((pet.level as uint64) | ((pet.pointsUnspent as uint64) << 16) | ((pet.xp as uint64) << 24))
		.absorb(pet.tree.bits)
		.absorb(pet.harvest)
		.absorb(pet.burrow)
		.absorb(pet.rewardSnapshot)
		.absorb(pet.bornEpoch)
		.absorb(pet.lastTickEpoch)
		.absorb(
			(pet.fightsOutToday as uint64) |
			((pet.fightsInToday as uint64) << 8) |
			((pet.bitesInToday as uint64) << 16) |
			(((pet.slotsAttackedToday as uint16) as uint64) << 24),
		)
		.absorb(pet.fightDay)
		.absorb((pet.growthMultiplierBps as uint64) | ((pet.minHearts as uint64) << 16))
		.absorb(pet.growthMultiplierExpiry)
		.absorb(
			(pet.pantry.small as uint64) |
			((pet.pantry.medium as uint64) << 8) |
			((pet.pantry.large as uint64) << 16) |
			((pet.foodBoughtToday as uint64) << 24) |
			((pet.talentKind as uint64) << 32) |
			((pet.talentBps as uint64) << 40),
		)
		.absorb(
			(pet.insurance as uint64) |
			((pet.scars as uint64) << 8) |
			((pet.lineageGeneration as uint64) << 16) |
			((((pet.bonding as int64) + 128) as uint64) << 32) |
			((pet.talksToday as uint64) << 40) |
			((pet.ownerFedToday as uint64) << 48),
		)
		.absorb(pet.giftOwed)
		.absorb(pet.ownerBankedAt)
		.absorbItem(pet.gear.head)
		.absorbItem(pet.gear.body)
		.absorbItem(pet.gear.hands)
		.absorbItem(pet.gear.feet)
		.absorb((pet.grudgeSlot as uint64) | ((pet.rage as uint64) << 8))
		.absorb(pet.rageEpoch);
}

export function digestOf(pets: Span<Pet>, global: GlobalConfig): uint64 {
	let digest: Digest = { value: 0x9e3779b97f4a7c15 };
	for (let slot = 0; slot < pets.length; slot++) { digest = digest.absorbPet(pets[slot]); }
	return digest
		.absorb(global.genesisTimestamp)
		.absorb(global.rewardPerWorkPower)
		.absorb(global.rewardEpoch)
		.absorb(global.totalWorkPower)
		.absorb(global.recycledPending)
		.absorb(global.treasury)
		.absorb(global.itemReserve)
		.absorb(global.emitted)
		.absorb((global.livingPets as uint64) | ((global.floorSlots as uint64) << 32))
		.value;
}

export function actTicked(
	this context: ActContext,
	policy: Span<uint8>,
	pets: Span<Pet>,
	wilds: Span<Pet>,
	settled: GlobalConfig,
): ActOutcome {
	let self: int32[46] = [];
	let rivals: Combatant[10] = [];
	const morning = context.surroundingsIn(pets, wilds, settled);
	morning.rivalsInto(rivals);
	context.observedSelf(morning, rivals, self);
	const economy = context.economyChoice(policy, morning, self);
	const afterEconomy = context.appliedEconomy(pets, settled, economy);
	const growing = context.surroundingsIn(pets, wilds, afterEconomy);
	let node = ALLOCATE_HOLD;
	let afterNode = afterEconomy;
	const growable = growing.actorPet().legalNodes(afterEconomy);
	if (growable.bits != 0) {
		context.observedSelfForNodeAndAttack(growing, self);
		const sums = growing.actorPet().tree.summed(growing.actorPet().level as int32);
		node = nodeChoice(policy, growing, growable, self, sums);
		afterNode = context.appliedNode(pets, afterEconomy, node, sums);
	}
	const armed = context.surroundingsIn(pets, wilds, afterNode);
	context.observedSelfForNodeAndAttack(armed, self);
	const attack = attackChoice(policy, armed, rivals, self);
	return { choice: { economy: economy, node: node, attack: attack }, global: afterNode };
}

export function actOnce(
	this context: ActContext,
	policy: Span<uint8>,
	pets: Span<Pet>,
	wilds: Span<Pet>,
	global: GlobalConfig,
): Result<ActOutcome, TickError> {
	const ticked = try context.tickedActor(pets, global);
	const settled = try context.tickedNeighbours(pets, ticked);
	return Result.ok(context.actTicked(policy, pets, wilds, settled));
}
