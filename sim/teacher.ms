import {
	BLOCK_SLOTS,
	TREE_NODES,
	ALLOCATE_HOLD,
	ATTACK_HOLD,
	STAKE_LEVELS,
	KEYSTONE_PACIFIST,
	NodeKind,
	Region,
	Food,
	Persona,
	PersonaKind,
	EconomyAction,
	StakeLevel,
	regionOf,
	nodeKind,
	attackChoice,
	splitmix,
} from "../rules/index";
import { ACTS_PER_EPOCH, ActionSet, Masks, World, blockStart } from "./world";

export const TEACHER_ODDS_RUNS: int32 = 64;

export function personaKindOf(index: int32): PersonaKind {
	return (((index % BLOCK_SLOTS) / 3) % 3) as PersonaKind;
}

function foodAction(food: Food): EconomyAction {
	return match (food) {
		Food.Small => EconomyAction.EatSmall,
		Food.Medium => EconomyAction.EatMedium,
		Food.Large => EconomyAction.EatLarge,
	};
}

export function teachEconomy(this world: World, index: int32, masks: Masks): EconomyAction {
	const pet = world.pets[index];
	const persona = Persona.of(personaKindOf(index));
	const food = persona.pickFood(pet.hearts as int32, pet.burrow, pet.level as int32);
	if (food.ok && masks.economy.has(foodAction(food.value))) { return foodAction(food.value); }
	const lastRound = world.round == ACTS_PER_EPOCH - 1;
	const heavy = pet.harvest * 4 > pet.burrow;
	if (masks.economy.has(EconomyAction.Bank) && (lastRound || heavy)) { return EconomyAction.Bank; }
	return EconomyAction.Rest;
}

function regionOfNode(id: int32): Region {
	return nodeKind(id) == NodeKind.Keystone ? (id - KEYSTONE_PACIFIST) as Region : regionOf(id);
}

export function teachNode(this world: World, index: int32, masks: Masks): int32 {
	const pet = world.pets[index];
	let chosen = ALLOCATE_HOLD;
	let ownRegion = false;
	for (let id = 0; id < TREE_NODES; id++) {
		if (!masks.nodes.allowsNode(id)) { continue; }
		const mine = regionOfNode(id) == pet.startRegion();
		if (chosen == ALLOCATE_HOLD || (mine && !ownRegion) || (mine && ownRegion)) {
			chosen = id;
			ownRegion = mine;
		}
	}
	return chosen;
}

export function teachAttack(this world: World, index: int32, masks: Masks): int32 {
	const pet = world.pets[index];
	const persona = Persona.of(personaKindOf(index));
	const attacker = pet.combatant();
	if (!attacker.attacksLeft(pet.fightsOutOn(world.epoch)).ok) { return ATTACK_HOLD; }
	const base = blockStart(index);
	let best = ATTACK_HOLD;
	let bestValue: int64 = 0;
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		if (base + slot == index) { continue; }
		const defender = world.pets[base + slot];
		const capped = pet.attackable(defender, world.epoch);
		if (!capped.ok) { continue; }
		const budget = persona.chooseStake(defender.harvest, pet.burrow);
		if (budget == 0) { continue; }
		let level = -1;
		let stake: uint64 = 0;
		for (let ordinal = STAKE_LEVELS - 1; ordinal >= 0 && level < 0; ordinal--) {
			const priced = pet.stakeAt(capped.value, ordinal as StakeLevel);
			if (priced.ok && priced.value <= budget) {
				level = ordinal;
				stake = priced.value;
			}
		}
		if (level < 0) { continue; }
		if (!masks.attacks.allowsAttack(defender.blockSlot(), level as StakeLevel)) { continue; }
		const seed = splitmix(
			world.seed ^ (world.epoch << 24) ^ ((index as uint64) << 8) ^ (slot as uint64),
		);
		const winChance = attacker.winChanceAgainst(defender.combatant(), seed, TEACHER_ODDS_RUNS);
		if (winChance < persona.minWinChanceBps) { continue; }
		const value = defender.combatant().attackExpectedValue(
			winChance,
			stake,
			defender.harvest,
			defender.fightsInOn(world.epoch),
		);
		if (value > bestValue) {
			bestValue = value;
			best = attackChoice(defender.blockSlot(), level as StakeLevel);
		}
	}
	return best;
}

export function teach(this world: World, index: int32, masks: Masks): ActionSet {
	if (!world.pets[index].alive) { return ActionSet.hold(); }
	return {
		economy: world.teachEconomy(index, masks),
		node: world.teachNode(index, masks),
		attack: world.teachAttack(index, masks),
	};
}

export function act(this world: World, index: int32): World {
	if (!world.pets[index].alive) { return world; }
	const economy = world.teachEconomy(index, world.masksFor(index));
	const afterEconomy = world.applyEconomy(index, economy);
	const node = afterEconomy.teachNode(index, afterEconomy.masksFor(index));
	const afterNode = afterEconomy.applyNode(index, node);
	const attack = afterNode.teachAttack(index, afterNode.masksFor(index));
	return afterNode.applyAttack(index, attack);
}

export function playEpisode(blocks: int32, epochs: int32, seed: uint64): World {
	let world = World.create(blocks, seed);
	for (let day = 1; day <= epochs; day++) {
		world = world.beginEpoch(day as uint64);
		for (let round = 0; round < ACTS_PER_EPOCH; round++) {
			world = { ...world, round: round };
			for (let index = 0; index < world.pets.length; index++) {
				world = world.act(index);
			}
		}
		world = world.endEpoch();
	}
	return world;
}

test "the teacher takes a node of its own region on day one and never attacks under shield" {
	const world = World.create(1, 6).beginEpoch(1);
	const masks = world.masksFor(1);
	const actions = world.teach(1, masks);
	assert actions.node != ALLOCATE_HOLD;
	assert regionOfNode(actions.node) == world.pets[1].startRegion();
	assert actions.attack == ATTACK_HOLD;
	assert actions.economy == EconomyAction.Bank;
}

test "a short episode is legal, deterministic and has fights" {
	const first = playEpisode(1, 12, 9);
	const second = playEpisode(1, 12, 9);
	assert first.stats.illegal == 0;
	assert first.stats.fights > 0;
	assert first.stats.fights == second.stats.fights;
	assert first.global.burned == second.global.burned;
	for (let index = 0; index < first.pets.length; index++) {
		assert first.pets[index] == second.pets[index];
	}
}
