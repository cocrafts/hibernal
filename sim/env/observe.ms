import {
	BLOCK_SLOTS,
	TREE_NODES,
	ALLOCATE_HOLD,
	ATTACK_HOLD,
	STAKE_LEVELS,
	BlockSlot,
	Food,
	EconomyAction,
	FEATURE_ONE,
	SelfFeature,
	TargetFeature,
	SELF_FEATURES,
	NODE_FEATURES,
	TARGET_FEATURES,
	moneyFeature,
	signedMoneyFeature,
	writeSelf,
	writeNodes,
	writeTargets,
	Combatant,
	Surroundings,
	plain,
	rivalsInto,
	hungerPerDay,
	foodReserve,
	GIFT_RESERVE_DAYS,
	adding,
	unstocked,
	Pantry,
} from "../../rules/index";
import {
	World,
	economyMaskFor,
	surroundingsOf,
	marketViewOf,
} from "../world";
import { personaKindOf } from "../teacher";

export const ECONOMY_ACTIONS: int32 = (EconomyAction.BuyItem as int32) + 1;
export const NODE_ACTIONS: int32 = ALLOCATE_HOLD + 1;
export const ATTACK_ACTIONS: int32 = ATTACK_HOLD + 1;

export enum Head {
	Economy,
	Node,
	Attack,
}

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

function clear(features: int32[], offset: int32, count: int32): void {
	for (let position = offset; position < offset + count; position++) {
		features[position] = 0;
	}
}

export function rivalsAround(around: Surroundings): Combatant[] {
	const idle = Combatant.plain(0, 0, 0);
	const rivals: Combatant[] = [];
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) { rivals.push(idle); }
	around.rivalsInto(rivals);
	return rivals;
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
	const around = world.surroundingsOf(index);
	const rivals = rivalsAround(around);
	around.writeSelf(personaKindOf(index), world.marketViewOf(index), rivals, features, offset);
	if (head == Head.Node) { around.writeNodes(features, offset + SELF_FEATURES); }
	if (head == Head.Attack) { around.writeTargets(rivals, features, offset + SELF_FEATURES); }
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
		const economy = world.economyMaskFor(index);
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
	assert SELF_FEATURES == 46;
	assert observationSize(Head.Economy) == 46;
	assert observationSize(Head.Node) == 46 + 65 * 22;
	assert observationSize(Head.Attack) == 46 + 11 * 13;
	assert actionCount(Head.Economy) == 12;
	assert actionCount(Head.Node) == 65;
	assert actionCount(Head.Attack) == 41;
}

test "a pet sees the hearts it will wake up with, pantry meals included" {
	const world = World.create(1, 6).beginEpoch(1);
	const pets = world.pets;
	const pet = pets[4];
	const hunger = pet.ownStats().hungerPerDay();
	pets[4] = { ...pet, hearts: hunger as uint8, pantry: Pantry.unstocked() };
	const features = zeros(observationSize(Head.Economy));
	world.observeInto(4, Head.Economy, features, 0);
	assert features[SelfFeature.DawnHearts as int32] == 0;
	pets[4] = { ...pets[4], pantry: Pantry.unstocked().adding(Food.Large, 1) };
	world.observeInto(4, Head.Economy, features, 0);
	assert features[SelfFeature.DawnHearts as int32] > 0;
	pets[4] = { ...pets[4], harvest: 0, burrow: 0 };
	world.observeInto(4, Head.Economy, features, 0);
	assert features[SelfFeature.FoodDays as int32] == 0;
	const perDay = foodReserve(pets[4].level as int32, hunger) / GIFT_RESERVE_DAYS;
	pets[4] = { ...pets[4], burrow: perDay * 5 };
	world.observeInto(4, Head.Economy, features, 0);
	assert features[SelfFeature.FoodDays as int32] == 5 * 4;
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
