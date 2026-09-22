import {
	BLOCK_SLOTS,
	TREE_NODES,
	ALLOCATE_HOLD,
	ATTACK_HOLD,
	STAKE_LEVELS,
	KEYSTONE_PACIFIST,
	KEYSTONE_GLASS_CANNON,
	KEYSTONE_CANNIBAL,
	HBRN_UNIT,
	BlockSlot,
	NodeKind,
	Region,
	Food,
	Persona,
	PersonaKind,
	EconomyAction,
	StakeLevel,
	regionOf,
	nodeKind,
	adjacent,
	attackChoice,
	splitmix,
	winChanceFromTable,
} from "../rules/index";
import { ACTS_PER_EPOCH, ActionSet, Masks, World, blockStart } from "./world";

export const TEACHER_ODDS_RUNS: int32 = 64;
export const REVENGE_WIN_CHANCE_BPS: int32 = 4000;

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

export function regionOfNode(id: int32): Region {
	return nodeKind(id) == NodeKind.Keystone ? (id - KEYSTONE_PACIFIST) as Region : regionOf(id);
}

export function keystoneOf(kind: PersonaKind): int32 {
	return match (kind) {
		PersonaKind.Cautious => KEYSTONE_PACIFIST,
		PersonaKind.Greedy => KEYSTONE_GLASS_CANNON,
		PersonaKind.Vengeful => KEYSTONE_CANNIBAL,
	};
}

export function teachNode(this world: World, index: int32, masks: Masks): int32 {
	const pet = world.pets[index];
	const keystone = keystoneOf(personaKindOf(index));
	if (masks.nodes.allowsNode(keystone)) { return keystone; }
	let chosen = ALLOCATE_HOLD;
	for (let id = 0; id < TREE_NODES; id++) {
		if (!masks.nodes.allowsNode(id) || nodeKind(id) == NodeKind.Keystone) { continue; }
		if (chosen == ALLOCATE_HOLD || regionOfNode(id) == pet.startRegion()) { chosen = id; }
	}
	return chosen;
}

function oddsSeed(this world: World, index: int32, slot: int32): uint64 {
	return splitmix(world.seed ^ (world.epoch << 24) ^ ((index as uint64) << 8) ^ (slot as uint64));
}

export function revengeOn(this world: World, index: int32, masks: Masks): int32 {
	const robber = world.robberOf(index);
	if (!robber.ok) { return ATTACK_HOLD; }
	if (!masks.attacks.allowsAttack(robber.value, StakeLevel.Quarter)) { return ATTACK_HOLD; }
	const slot = robber.value as int32;
	const defender = world.pets[blockStart(index) + slot];
	const winChance = world.pets[index].combatant().winChanceFromTable(defender.combatant());
	if (winChance < REVENGE_WIN_CHANCE_BPS) { return ATTACK_HOLD; }
	return attackChoice(robber.value, StakeLevel.Quarter);
}

export function teachAttack(this world: World, index: int32, masks: Masks): int32 {
	const pet = world.pets[index];
	const kind = personaKindOf(index);
	const persona = Persona.of(kind);
	const attacker = pet.combatant();
	if (!attacker.attacksLeft(pet.fightsOutOn(world.epoch)).ok) { return ATTACK_HOLD; }
	if (kind == PersonaKind.Vengeful) {
		const revenge = world.revengeOn(index, masks);
		if (revenge != ATTACK_HOLD) { return revenge; }
	}
	const base = blockStart(index);
	let best = ATTACK_HOLD;
	let bestRank: int64 = 0;
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
		const winChance = attacker.winChanceAgainst(
			defender.combatant(),
			world.oddsSeed(index, slot),
			TEACHER_ODDS_RUNS,
		);
		if (winChance < persona.minWinChanceBps) { continue; }
		const value = defender.combatant().attackExpectedValue(
			winChance,
			stake,
			defender.harvest,
			defender.fightsInOn(world.epoch),
		);
		if (value <= 0) { continue; }
		const rank = kind == PersonaKind.Greedy ? defender.harvest as int64 : value;
		if (rank > bestRank) {
			bestRank = rank;
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
	let world = World.staggered(blocks, seed);
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

function armedBlock(): World {
	const start = World.create(1, 6);
	const pets = start.pets;
	for (let index = 0; index < pets.length; index++) {
		pets[index] = { ...pets[index], burrow: 400 * HBRN_UNIT };
	}
	const world = start.beginEpoch(10);
	for (let index = 0; index < pets.length; index++) {
		pets[index] = { ...pets[index], harvest: 400 * HBRN_UNIT, burrow: 400 * HBRN_UNIT };
	}
	return world;
}

test "a vengeful pet strikes back at its robber with a quarter stake while it can win" {
	const world = armedBlock();
	const pets = world.pets;
	const grudges = world.grudges;
	assert personaKindOf(7) == PersonaKind.Vengeful;
	assert personaKindOf(1) == PersonaKind.Cautious;
	grudges[7] = { robber: BlockSlot.Second, epoch: 9 };
	grudges[1] = { robber: BlockSlot.Eighth, epoch: 9 };
	pets[7] = { ...pets[7], might: 900 };
	pets[1] = { ...pets[1], might: 900 };
	const revenge = attackChoice(BlockSlot.Second, StakeLevel.Quarter);
	assert world.teachAttack(7, world.masksFor(7)) == revenge;
	assert world.teachAttack(1, world.masksFor(1)) != attackChoice(BlockSlot.Eighth, StakeLevel.Quarter);
	pets[7] = { ...pets[7], might: 1, grit: 1 };
	assert world.revengeOn(7, world.masksFor(7)) == ATTACK_HOLD;
}

test "a greedy pet goes for the biggest harvest it can win" {
	const world = armedBlock();
	const pets = world.pets;
	assert personaKindOf(4) == PersonaKind.Greedy;
	pets[4] = { ...pets[4], might: 900 };
	pets[8] = { ...pets[8], harvest: 900 * HBRN_UNIT };
	const choice = world.teachAttack(4, world.masksFor(4));
	assert choice / STAKE_LEVELS == (BlockSlot.Ninth as int32);
}

test "the teacher takes only its persona's keystone" {
	const world = armedBlock();
	const pets = world.pets;
	for (let index = 0; index < BLOCK_SLOTS; index++) {
		pets[index] = { ...pets[index], pointsUnspent: 20 };
	}
	for (let round = 0; round < 20; round++) {
		for (let index = 0; index < BLOCK_SLOTS; index++) {
			world.applyNode(index, world.teachNode(index, world.masksFor(index)));
		}
	}
	for (let index = 0; index < BLOCK_SLOTS; index++) {
		const pet = world.pets[index];
		const mine = keystoneOf(personaKindOf(index));
		const gate = 3 + (pet.startRegion() as int32) * 6 + 4;
		assert pet.tree.has(mine) == adjacent(mine, gate);
		for (let keystone = KEYSTONE_PACIFIST; keystone <= KEYSTONE_CANNIBAL; keystone++) {
			if (keystone != mine) { assert !pet.tree.has(keystone); }
		}
	}
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
