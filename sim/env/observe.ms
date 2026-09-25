import {
	BLOCK_SLOTS,
	TREE_NODES,
	ALLOCATE_HOLD,
	ATTACK_HOLD,
	STAKE_LEVELS,
	BPS,
	BlockSlot,
	Mod,
	Food,
	Stats,
	Tree,
	EconomyAction,
	StakeLevel,
	foodCost,
	adjacent,
	nodeKind,
	nodeCost,
	NodeKind,
	log2Times32,
	winChanceFromTable,
	FOOD_BUYS_PER_DAY,
	mintPrice,
	totalBonusBps,
	weakestSlot,
	at,
	bonusBps,
	hungerPerDay,
} from "../../rules/index";
import { has, touches, built, regionOf } from "../../rules/tree";
import { ACTS_PER_EPOCH, World, blockStart } from "../world";
import { personaKindOf } from "../teacher";

export const FEATURE_ONE: int32 = 127;
export const ECONOMY_ACTIONS: int32 = (EconomyAction.SellItem as int32) + 1;
export const NODE_ACTIONS: int32 = ALLOCATE_HOLD + 1;
export const ATTACK_ACTIONS: int32 = ATTACK_HOLD + 1;

export enum Head {
	Economy,
	Node,
	Attack,
}

export enum SelfFeature {
	Hearts,
	MaxHearts,
	MealsAfforded,
	Harvest,
	Burrow,
	Level,
	PointsUnspent,
	RegionWorker,
	RegionFighter,
	RegionSurvivor,
	PersonaCautious,
	PersonaGreedy,
	PersonaVengeful,
	AttacksLeft,
	Age,
	Shielded,
	Round,
	FightsIn,
	Might,
	Grit,
	Forage,
	ModOvertime,
	ModScavenger,
	ModThickHide,
	ModPacifist,
	ModGlassCannon,
	ModCannibal,
	SmallMealCost,
	LivingMates,
	PantryHearts,
	RichestHarvest,
	Threat,
	ModRelentless,
	ModBerserker,
	Bonding,
	GearBonus,
	WeakestItemBonus,
	MintsAfforded,
	HungerShare,
	BuysLeft,
}

export enum NodeFeature {
	Hold,
	OwnRegion,
	Opens,
	Notable,
	Keystone,
	Cost,
	Forage,
	Might,
	Grit,
	MaxHearts,
	GainsOvertime,
	GainsScavenger,
	GainsThickHide,
	GainsPacifist,
	GainsGlassCannon,
	GainsCannibal,
	GainsRelentless,
	GainsBerserker,
	Food,
	Experience,
	Loot,
	BiteGuard,
}

export enum TargetFeature {
	Present,
	Hold,
	WinChance,
	ValueQuarter,
	ValueHalf,
	ValueThreeQuarters,
	ValueWhole,
	Harvest,
	Shielded,
	FightsIn,
	AttackedToday,
	Hearts,
	Grudge,
}

export const SELF_FEATURES: int32 = (SelfFeature.BuysLeft as int32) + 1;
export const NODE_FEATURES: int32 = (NodeFeature.BiteGuard as int32) + 1;
export const TARGET_FEATURES: int32 = (TargetFeature.Grudge as int32) + 1;
export const NODE_CANDIDATES: int32 = TREE_NODES + 1;
export const TARGET_CANDIDATES: int32 = BLOCK_SLOTS + 1;

export function observationSize(head: Head): int32 {
	return match (head) {
		Head.Economy => SELF_FEATURES,
		Head.Node => SELF_FEATURES + NODE_CANDIDATES * NODE_FEATURES,
		Head.Attack => SELF_FEATURES + TARGET_CANDIDATES * TARGET_FEATURES,
	};
}

export function actionCount(head: Head): int32 {
	return match (head) {
		Head.Economy => ECONOMY_ACTIONS,
		Head.Node => NODE_ACTIONS,
		Head.Attack => ATTACK_ACTIONS,
	};
}

export function largestActionCount(): int32 {
	const widest = Math.max(actionCount(Head.Node), actionCount(Head.Attack));
	return Math.max(actionCount(Head.Economy), widest);
}

export function moneyFeature(amount: uint64): int32 {
	return Math.min(log2Times32(amount / 1000 + 1) / 8, FEATURE_ONE);
}

export function signedMoneyFeature(amount: int64): int32 {
	return amount < 0 ? -moneyFeature((-amount) as uint64) : moneyFeature(amount as uint64);
}

function flag(on: boolean): int32 {
	return on ? FEATURE_ONE : 0;
}

function put(features: int32[], position: int32, value: int32): void {
	features[position] = Math.max(-FEATURE_ONE, Math.min(value, FEATURE_ONE));
}

function heartShare(hearts: uint8, maxHearts: uint8): int32 {
	return (hearts as int32) * FEATURE_ONE / Math.max(maxHearts as int32, 1);
}

function clear(features: int32[], offset: int32, count: int32): void {
	for (let position = offset; position < offset + count; position++) {
		features[position] = 0;
	}
}

function selfSlot(offset: int32, feature: SelfFeature): int32 {
	return offset + (feature as int32);
}

function nodeSlot(offset: int32, feature: NodeFeature): int32 {
	return offset + (feature as int32);
}

function targetSlot(offset: int32, feature: TargetFeature): int32 {
	return offset + (feature as int32);
}

function writeSelf(this world: World, index: int32, features: int32[], offset: int32): void {
	const pet = world.pets[index];
	const stats = pet.stats();
	const fighter = pet.combatant();
	const level = pet.level as int32;
	const meal = foodCost(Food.Small, level);
	const attacksLeft = try fighter.attacksLeft(pet.fightsOutOn(world.epoch)) catch 0;
	put(features, selfSlot(offset, SelfFeature.Hearts), heartShare(pet.hearts, pet.maxHearts));
	put(features, selfSlot(offset, SelfFeature.MaxHearts), (pet.maxHearts as int32) * 2);
	const mealsAfforded = Math.min(pet.burrow / meal, 31 as uint64) as int32;
	const age = Math.min(world.epoch - pet.bornEpoch, FEATURE_ONE as uint64) as int32;
	put(features, selfSlot(offset, SelfFeature.MealsAfforded), mealsAfforded * 4);
	put(features, selfSlot(offset, SelfFeature.Harvest), moneyFeature(pet.harvest));
	put(features, selfSlot(offset, SelfFeature.Burrow), moneyFeature(pet.burrow));
	put(features, selfSlot(offset, SelfFeature.Level), level * 6);
	put(features, selfSlot(offset, SelfFeature.PointsUnspent), (pet.pointsUnspent as int32) * 6);
	put(features, selfSlot(offset, SelfFeature.RegionWorker) + (pet.region as int32), FEATURE_ONE);
	put(
		features,
		selfSlot(offset, SelfFeature.PersonaCautious) + (personaKindOf(index) as int32),
		FEATURE_ONE,
	);
	put(features, selfSlot(offset, SelfFeature.AttacksLeft), attacksLeft * 40);
	put(features, selfSlot(offset, SelfFeature.Age), age);
	put(features, selfSlot(offset, SelfFeature.Shielded), flag(pet.shieldedAt(world.epoch)));
	const roundShare = world.round * FEATURE_ONE / (ACTS_PER_EPOCH - 1);
	put(features, selfSlot(offset, SelfFeature.Round), roundShare);
	put(features, selfSlot(offset, SelfFeature.FightsIn), pet.fightsInOn(world.epoch) * 40);
	put(features, selfSlot(offset, SelfFeature.Might), stats.might / 2);
	put(features, selfSlot(offset, SelfFeature.Grit), stats.grit / 2);
	put(features, selfSlot(offset, SelfFeature.Forage), stats.forage / 2);
	for (let ordinal = 0; ordinal <= (Mod.Cannibal as int32); ordinal++) {
		put(
			features,
			selfSlot(offset, SelfFeature.ModOvertime) + ordinal,
			flag(stats.mods.has(ordinal as Mod)),
		);
	}
	put(features, selfSlot(offset, SelfFeature.SmallMealCost), moneyFeature(meal));
	put(features, selfSlot(offset, SelfFeature.LivingMates), world.livingMates(index) * 14);
	put(features, selfSlot(offset, SelfFeature.PantryHearts), pet.pantry.storedHearts() * 4);
	const base = blockStart(index);
	let richest = 0;
	let threat = 0;
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		const mate = world.pets[base + slot];
		const target = world.defenderAt(base + slot);
		if (base + slot == index || !target.alive) { continue; }
		if (!target.shieldedAt(world.epoch)) {
			richest = Math.max(richest, moneyFeature(target.harvest));
		}
		if (!mate.alive) { continue; }
		if (mate.attackable(pet, world.epoch).ok) {
			const odds = mate.combatantFacing(pet).winChanceFromTable(pet.combatantFacing(mate));
			threat = Math.max(threat, odds);
		}
	}
	put(features, selfSlot(offset, SelfFeature.RichestHarvest), richest);
	put(features, selfSlot(offset, SelfFeature.Threat), threat * FEATURE_ONE / BPS);
	const relentless = flag(stats.mods.has(Mod.Relentless));
	put(features, selfSlot(offset, SelfFeature.ModRelentless), relentless);
	put(features, selfSlot(offset, SelfFeature.ModBerserker), flag(stats.mods.has(Mod.Berserker)));
	put(features, selfSlot(offset, SelfFeature.Bonding), pet.bonding as int32);
	put(features, selfSlot(offset, SelfFeature.GearBonus), pet.gear.totalBonusBps() / 40);
	const weakest = pet.gear.at(pet.gear.weakestSlot());
	put(features, selfSlot(offset, SelfFeature.WeakestItemBonus), weakest.bonusBps() / 11);
	const mintsAfforded = Math.min(pet.burrow / mintPrice(level), 31 as uint64) as int32;
	put(features, selfSlot(offset, SelfFeature.MintsAfforded), mintsAfforded * 4);
	const hungerShare = stats.hungerPerDay() * FEATURE_ONE / Math.max(pet.maxHearts as int32, 1);
	put(features, selfSlot(offset, SelfFeature.HungerShare), hungerShare);
	const buysLeft = FOOD_BUYS_PER_DAY - (pet.foodBoughtToday as int32);
	put(features, selfSlot(offset, SelfFeature.BuysLeft), buysLeft * 40);
}

function opensWith(this tree: Tree, id: int32): int32 {
	let opened = 0;
	for (let other = 0; other < TREE_NODES; other++) {
		if (adjacent(id, other) && !tree.has(other) && !tree.touches(other)) { opened += 1; }
	}
	return opened;
}

function writeNodes(this world: World, index: int32, features: int32[], offset: int32): void {
	const pet = world.pets[index];
	const legal = pet.legalNodes(world.global);
	const level = pet.level as int32;
	const before = Stats.built(pet.tree, level, pet.talent());
	for (let id = 0; id < TREE_NODES; id++) {
		if (!legal.allowsNode(id)) { continue; }
		const row = offset + id * NODE_FEATURES;
		const after = Stats.built(pet.tree.withNode(id), level, pet.talent());
		const gained = after.mods.difference(before.mods);
		const kind = nodeKind(id);
		const home = regionOf(id);
		const ownRegion = home.ok && home.value == pet.startRegion();
		put(features, nodeSlot(row, NodeFeature.OwnRegion), flag(ownRegion));
		put(features, nodeSlot(row, NodeFeature.Opens), pet.tree.opensWith(id) * 40);
		put(features, nodeSlot(row, NodeFeature.Notable), flag(kind == NodeKind.Notable));
		put(features, nodeSlot(row, NodeFeature.Keystone), flag(kind == NodeKind.Keystone));
		put(features, nodeSlot(row, NodeFeature.Cost), nodeCost(id) * 40);
		put(features, nodeSlot(row, NodeFeature.Forage), (after.forage - before.forage) * 6);
		put(features, nodeSlot(row, NodeFeature.Might), (after.might - before.might) * 6);
		put(features, nodeSlot(row, NodeFeature.Grit), (after.grit - before.grit) * 6);
		const heartsGained = after.maxHearts - before.maxHearts;
		put(features, nodeSlot(row, NodeFeature.MaxHearts), heartsGained * 30);
		for (let ordinal = 0; ordinal <= (Mod.Berserker as int32); ordinal++) {
			put(
				features,
				nodeSlot(row, NodeFeature.GainsOvertime) + ordinal,
				flag(gained.has(ordinal as Mod)),
			);
		}
		put(features, nodeSlot(row, NodeFeature.Food), (after.foodBps - before.foodBps) / 50);
		const experience = after.experienceBps - before.experienceBps;
		put(features, nodeSlot(row, NodeFeature.Experience), experience / 50);
		put(features, nodeSlot(row, NodeFeature.Loot), (after.lootBps - before.lootBps) / 50);
		const guard = after.biteGuardBps - before.biteGuardBps;
		put(features, nodeSlot(row, NodeFeature.BiteGuard), guard / 50);
	}
	put(features, nodeSlot(offset + ALLOCATE_HOLD * NODE_FEATURES, NodeFeature.Hold), FEATURE_ONE);
}

function writeTargets(this world: World, index: int32, features: int32[], offset: int32): void {
	const pet = world.pets[index];
	const fighter = pet.combatant();
	const base = blockStart(index);
	const robber = world.robberOf(index);
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		const target = world.defenderAt(base + slot);
		if (base + slot == index || !target.alive) { continue; }
		const row = offset + slot * TARGET_FEATURES;
		put(features, targetSlot(row, TargetFeature.Present), FEATURE_ONE);
		put(features, targetSlot(row, TargetFeature.Harvest), moneyFeature(target.harvest));
		const shielded = target.shieldedAt(world.epoch);
		put(features, targetSlot(row, TargetFeature.Shielded), flag(shielded));
		put(features, targetSlot(row, TargetFeature.FightsIn), target.fightsInOn(world.epoch) * 40);
		put(
			features,
			targetSlot(row, TargetFeature.AttackedToday),
			flag(pet.attackedOn(target.blockSlot(), world.epoch)),
		);
		put(features, targetSlot(row, TargetFeature.Hearts), heartShare(target.hearts, target.maxHearts));
		put(
			features,
			targetSlot(row, TargetFeature.Grudge),
			flag(robber.ok && robber.value == target.blockSlot()),
		);
		const stakeCap = pet.attackable(target, world.epoch);
		if (!stakeCap.ok) { continue; }
		const defender = target.combatantFacing(pet);
		const winChance = pet.combatantFacing(target).winChanceFromTable(defender);
		put(features, targetSlot(row, TargetFeature.WinChance), winChance * FEATURE_ONE / BPS);
		for (let ordinal = 0; ordinal < STAKE_LEVELS; ordinal++) {
			const stake = pet.stakeAt(stakeCap.value, ordinal as StakeLevel);
			if (!stake.ok) { continue; }
			const value = defender.attackExpectedValue(
				winChance,
				stake.value,
				target.harvest,
				target.fightsInOn(world.epoch),
			);
			put(
				features,
				targetSlot(row, TargetFeature.ValueQuarter) + ordinal,
				signedMoneyFeature(value),
			);
		}
	}
	const holdRow = offset + BLOCK_SLOTS * TARGET_FEATURES;
	put(features, targetSlot(holdRow, TargetFeature.Hold), FEATURE_ONE);
}

export function observeInto(
	this world: World,
	index: int32,
	head: Head,
	features: int32[],
	offset: int32,
): void {
	clear(features, offset, observationSize(head));
	if (!world.pets[index].alive) { return; }
	world.writeSelf(index, features, offset);
	if (head == Head.Node) { world.writeNodes(index, features, offset + SELF_FEATURES); }
	if (head == Head.Attack) { world.writeTargets(index, features, offset + SELF_FEATURES); }
}

export function legalInto(
	this world: World,
	index: int32,
	head: Head,
	legal: int32[],
	offset: int32,
): void {
	clear(legal, offset, actionCount(head));
	const pet = world.pets[index];
	if (!pet.alive) { return; }
	if (head == Head.Economy) {
		const economy = pet.legalEconomy(world.global);
		for (let ordinal = 0; ordinal < ECONOMY_ACTIONS; ordinal++) {
			legal[offset + ordinal] = economy.has(ordinal as EconomyAction) ? 1 : 0;
		}
		return;
	}
	if (head == Head.Node) {
		const nodes = pet.legalNodes(world.global);
		for (let id = 0; id < NODE_ACTIONS; id++) {
			legal[offset + id] = nodes.allowsNode(id) ? 1 : 0;
		}
		return;
	}
	const attacks = world.attackMaskFor(index);
	for (let choice = 0; choice < ATTACK_ACTIONS; choice++) {
		legal[offset + choice] = attacks.allowsChoice(choice) ? 1 : 0;
	}
}

export function zeros(count: int32): int32[] {
	const values: int32[] = [];
	for (let position = 0; position < count; position++) { values.push(0); }
	return values;
}

function total(values: int32[], offset: int32, count: int32): int32 {
	let sum = 0;
	for (let position = offset; position < offset + count; position++) { sum += values[position]; }
	return sum;
}

test "money features are quarter octaves of a thousandth of a token" {
	assert moneyFeature(0) == 0;
	assert moneyFeature(1000000) == 39;
	assert moneyFeature(2000000) == 43;
	assert moneyFeature(0xffffffffffffffff) == FEATURE_ONE;
	assert signedMoneyFeature(-1000000) == -39;
}

test "sizes follow the three heads" {
	assert SELF_FEATURES == 40;
	assert observationSize(Head.Economy) == 40;
	assert observationSize(Head.Node) == 40 + 65 * 22;
	assert observationSize(Head.Attack) == 40 + 11 * 13;
	assert actionCount(Head.Economy) == 10;
	assert actionCount(Head.Node) == 65;
	assert actionCount(Head.Attack) == 41;
}

test "a newborn sees itself, its legal nodes and no attackable target" {
	const world = World.create(1, 6).beginEpoch(1);
	const features = zeros(observationSize(Head.Node) + 3);
	world.observeInto(4, Head.Economy, features, 3);
	const pet = world.pets[4];
	assert pet.hearts < pet.maxHearts;
	const share = (pet.hearts as int32) * FEATURE_ONE / (pet.maxHearts as int32);
	assert features[3 + (SelfFeature.Hearts as int32)] == share;
	assert features[3 + (SelfFeature.MaxHearts as int32)] == (pet.maxHearts as int32) * 2;
	assert features[3 + (SelfFeature.RegionFighter as int32)] == FEATURE_ONE;
	assert total(features, 3 + (SelfFeature.RegionWorker as int32), 3) == FEATURE_ONE;
	assert total(features, 3 + (SelfFeature.PersonaCautious as int32), 3) == FEATURE_ONE;
	assert features[3 + (SelfFeature.PersonaGreedy as int32)] == FEATURE_ONE;
	assert features[3 + (SelfFeature.Shielded as int32)] == FEATURE_ONE;
	assert features[3 + (SelfFeature.Threat as int32)] == 0;
	assert features[2] == 0;
	world.observeInto(4, Head.Node, features, 0);
	const legal = zeros(actionCount(Head.Node));
	world.legalInto(4, Head.Node, legal, 0);
	for (let id = 0; id < NODE_CANDIDATES; id++) {
		const row = SELF_FEATURES + id * NODE_FEATURES;
		const filled = total(features, row, NODE_FEATURES) != 0;
		assert filled == (legal[id] == 1);
	}
	assert features[SELF_FEATURES + ALLOCATE_HOLD * NODE_FEATURES] == FEATURE_ONE;
	world.observeInto(4, Head.Attack, features, 0);
	world.legalInto(4, Head.Attack, legal, 0);
	assert total(legal, 0, ATTACK_ACTIONS) == 1;
	assert legal[ATTACK_HOLD] == 1;
	assert total(features, SELF_FEATURES + 4 * TARGET_FEATURES, TARGET_FEATURES) == 0;
	assert features[SELF_FEATURES + 5 * TARGET_FEATURES] == FEATURE_ONE;
	assert features[SELF_FEATURES + 5 * TARGET_FEATURES + (TargetFeature.Shielded as int32)] ==
		FEATURE_ONE;
	assert features[SELF_FEATURES + 5 * TARGET_FEATURES + (TargetFeature.WinChance as int32)] == 0;
}

test "a fresh grudge marks the robber and nobody else" {
	const world = World.create(1, 8).beginEpoch(2);
	const grudges = world.grudges;
	grudges[4] = { robber: BlockSlot.Eighth, epoch: 1 };
	const features = zeros(observationSize(Head.Attack));
	world.observeInto(4, Head.Attack, features, 0);
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		const row = SELF_FEATURES + slot * TARGET_FEATURES;
		assert features[row + (TargetFeature.Grudge as int32)] == (slot == 7 ? FEATURE_ONE : 0);
	}
	const stale: World = { ...world, epoch: 5 };
	stale.observeInto(4, Head.Attack, features, 0);
	assert features[SELF_FEATURES + 7 * TARGET_FEATURES + (TargetFeature.Grudge as int32)] == 0;
}

test "grown pets see odds and values for every attack the mask allows" {
	let world = World.create(1, 8);
	for (let day = 1; day <= 6; day++) {
		world = world.beginEpoch(day as uint64);
		for (let index = 0; index < world.pets.length; index++) {
			world = world.applyEconomy(index, EconomyAction.Bank);
			world = world.applyEconomy(index, EconomyAction.BuyLarge);
		}
		world = world.endEpoch();
	}
	world = world.beginEpoch(7);
	const features = zeros(observationSize(Head.Attack));
	const legal = zeros(actionCount(Head.Attack));
	world.observeInto(3, Head.Attack, features, 0);
	world.legalInto(3, Head.Attack, legal, 0);
	assert total(legal, 0, ATTACK_HOLD) > 0;
	for (let choice = 0; choice < ATTACK_HOLD; choice++) {
		const row = SELF_FEATURES + (choice / STAKE_LEVELS) * TARGET_FEATURES;
		const value = features[row + (TargetFeature.ValueQuarter as int32) + choice % STAKE_LEVELS];
		if (legal[choice] == 1) {
			assert features[row + (TargetFeature.WinChance as int32)] > 0;
			assert value != 0;
		} else {
			assert value == 0;
		}
	}
	assert features[SelfFeature.Threat as int32] > 0;
}

test "a dead pet observes nothing and may do nothing" {
	const world = World.create(1, 4).beginEpoch(1);
	world.pets[2] = { ...world.pets[2], alive: false, hearts: 0 };
	const features = zeros(observationSize(Head.Node));
	const legal = zeros(actionCount(Head.Node));
	world.observeInto(2, Head.Node, features, 0);
	world.legalInto(2, Head.Node, legal, 0);
	assert total(features, 0, observationSize(Head.Node)) == 0;
	assert total(legal, 0, actionCount(Head.Node)) == 0;
}
