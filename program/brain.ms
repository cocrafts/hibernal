import {
	BLOCK_SLOTS,
	ALLOCATE_HOLD,
	ATTACK_HOLD,
	STAKE_LEVELS,
	FEATURE_ONE,
	NODE_SELF_INPUTS,
	ATTACK_SELF_INPUTS,
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
	GlobalConfig,
	GrudgeError,
	MarketView,
	NodeMask,
	Pet,
	PersonaKind,
	SelfFeature,
	Surroundings,
	TreeSums,
	actorPet,
	allowsChoice,
	allowsNode,
	attackHoldMask,
	attackLogits,
	attackMask,
	attackSelfInput,
	combatant,
	economyLogits,
	economyMask,
	finished,
	foldEatIntoBuy,
	foldPortionSizes,
	nodeScore,
	nodeSelfInput,
	stats,
	talent,
	writeNode,
	writeNodeHold,
	writeSelf,
	writeSelfForNodeAndAttack,
	writeTarget,
	writeTargetHold,
} from "../rules/index";

const ATTACK_CHOICES: int32 = ATTACK_HOLD + 1;

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
	let hidden: int32[ECONOMY_HIDDEN] = [];
	let logits: int32[ECONOMY_OUTPUTS] = [];
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
	let input: int32[NODE_INPUTS] = [];
	let hidden: int32[NODE_HIDDEN] = [];
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

function wantsSlot(mask: AttackMask, slot: int32): boolean {
	if (slot == BLOCK_SLOTS) { return mask.allowsChoice(ATTACK_HOLD); }
	for (let level = 0; level < STAKE_LEVELS; level++) {
		if (mask.allowsChoice(slot * STAKE_LEVELS + level)) { return true; }
	}
	return false;
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
	let input: int32[ATTACK_INPUTS] = [];
	let hidden: int32[ATTACK_HIDDEN] = [];
	let narrow: int32[ATTACK_NARROW] = [];
	let out: int32[ATTACK_OUTPUTS] = [];
	let logits: int32[ATTACK_CHOICES] = [];
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
