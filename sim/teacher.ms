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
	CLUSTERS,
	NodeRole,
	regionOf,
	roleOf,
	clusterOf,
	keystoneBorder,
	keystoneTouches,
	nodeKind,
	attackChoice,
	splitmix,
	winChanceFromTable,
} from "../rules/index";
// C emits PantryEq for `Pet ==` only where Pantry is imported (msc v0.2.55); remove with
// ~/metascript/.inbox/compiler/2026-09-22-struct-equality-on-js.md, second sighting.
import { Pantry } from "../rules/pantry";
import { ACTS_PER_EPOCH, ActionSet, Masks, World, blockStart } from "./world";

export const TEACHER_ODDS_RUNS: int32 = 64;
export const REVENGE_WIN_CHANCE_BPS: int32 = 4000;
export const NEVER_RANK: int32 = 1000;

export function personaKindOf(index: int32): PersonaKind {
	return (((index % BLOCK_SLOTS) / 3) % 3) as PersonaKind;
}

function eatAction(food: Food): EconomyAction {
	return match (food) {
		Food.Small => EconomyAction.EatSmall,
		Food.Medium => EconomyAction.EatMedium,
		Food.Large => EconomyAction.EatLarge,
	};
}

function buyAction(food: Food): EconomyAction {
	return match (food) {
		Food.Small => EconomyAction.BuySmall,
		Food.Medium => EconomyAction.BuyMedium,
		Food.Large => EconomyAction.BuyLarge,
	};
}

export function teachEconomy(this world: World, index: int32, masks: Masks): EconomyAction {
	const pet = world.pets[index];
	const persona = Persona.of(personaKindOf(index));
	const hearts = pet.hearts as int32;
	const meal = persona.pickMeal(hearts, pet.maxHearts as int32, pet.pantry);
	if (meal.ok && masks.economy.has(eatAction(meal.value))) { return eatAction(meal.value); }
	const purchase = persona.pickPurchase(
		hearts,
		pet.maxHearts as int32,
		pet.pantry,
		pet.burrow,
		pet.level as int32,
	);
	if (purchase.ok && masks.economy.has(buyAction(purchase.value))) {
		return buyAction(purchase.value);
	}
	const lastRound = world.round == ACTS_PER_EPOCH - 1;
	const heavy = pet.harvest * 4 > pet.burrow;
	if (masks.economy.has(EconomyAction.Bank) && (lastRound || heavy)) { return EconomyAction.Bank; }
	return EconomyAction.Rest;
}


export function keystoneOf(kind: PersonaKind): int32 {
	return match (kind) {
		PersonaKind.Cautious => KEYSTONE_PACIFIST,
		PersonaKind.Greedy => KEYSTONE_GLASS_CANNON,
		PersonaKind.Vengeful => KEYSTONE_CANNIBAL,
	};
}

function targetCluster(start: Region, keystone: int32): int32 {
	const [first, second] = keystoneBorder(keystone);
	if (start == first) { return CLUSTERS - 1; }
	if (start == second) { return CLUSTERS - 2; }
	return CLUSTERS;
}

export function nodeRank(id: int32, start: Region, keystone: int32): int32 {
	if (nodeKind(id) == NodeKind.Keystone) {
		return id == keystone && keystoneTouches(id, start) ? 2 : NEVER_RANK;
	}
	const home = regionOf(id);
	if (!home.ok) { return 20; }
	if (home.value != start) { return 30; }
	const role = roleOf(id);
	if (role == NodeRole.Entry || role == NodeRole.Fork || role == NodeRole.Start) { return 0; }
	const cluster = clusterOf(id);
	return cluster == targetCluster(start, keystone) ? 1 : 3 + cluster;
}

export function teachNode(this world: World, index: int32, masks: Masks): int32 {
	const pet = world.pets[index];
	const keystone = keystoneOf(personaKindOf(index));
	let chosen = ALLOCATE_HOLD;
	let best = NEVER_RANK;
	for (let id = 0; id < TREE_NODES; id++) {
		if (!masks.nodes.allowsNode(id)) { continue; }
		const rank = nodeRank(id, pet.startRegion(), keystone);
		if (rank < best) {
			best = rank;
			chosen = id;
		}
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

test "on day one the teacher banks, takes a node of its region and holds its attack" {
	const world = World.create(1, 6).beginEpoch(1);
	const masks = world.masksFor(1);
	const actions = world.teach(1, masks);
	assert actions.node != ALLOCATE_HOLD;
	const home = regionOf(actions.node);
	assert home.ok && home.value == world.pets[1].startRegion();
	assert actions.attack == ATTACK_HOLD;
	assert actions.economy == EconomyAction.Bank;
}

function armedBlock(): World {
	const start = World.create(1, 6);
	const pets = start.pets;
	for (let index = 0; index < pets.length; index++) {
		pets[index] = { ...pets[index], burrow: 400 * HBRN_UNIT, lastTickEpoch: 9 };
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
		assert pet.tree.has(mine) == keystoneTouches(mine, pet.startRegion());
		for (let keystone = KEYSTONE_GLASS_CANNON; keystone < TREE_NODES; keystone++) {
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
