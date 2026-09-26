import * as arithmetic from "./arithmetic";
import { BPS, ACTS_PER_EPOCH } from "./units";
import { Mod, Stats, asCombatant } from "./stats";
import {
	TREE_NODES,
	NodeKind,
	Tree,
	adjacent,
	built,
	has,
	nodeCost,
	nodeKind,
	regionOf,
	touches,
	withNode,
} from "./tree";
import { Food, foodCost } from "./emission";
import { FOOD_BUYS_PER_DAY, storedHearts } from "./pantry";
import { attacksLeft } from "./fight";
import { log2Times32 } from "./logarithm";
import { winChanceFromTable } from "./oddsTable";
import {
	BLOCK_SLOTS,
	BlockSlot,
	GlobalConfig,
	Pet,
	attackedOn,
	blockSlot,
	combatantFacing,
	fightsInOn,
	fightsOutOn,
	ownStats,
	shieldedAt,
	startRegion,
	talent,
	wallet,
} from "./layout";
import { dawnHearts, hungerPerDay } from "./life";
import {
	ALLOCATE_HOLD,
	STAKE_LEVELS,
	AttackMask,
	EconomyAction,
	StakeLevel,
	allowsNode,
	attackHoldMask,
	attackable,
	attacksOn,
	legalEconomy,
	legalNodes,
	stakeAt,
} from "./actions";
import { PersonaKind, attackExpectedValue } from "./brain";
import { at, bonusBps, mintPrice, totalBonusBps, weakestSlot } from "./items";
import { Listing, MarketError, focusStat, listPrice, listingGain, spareSlot } from "./market";
import { GIFT_RESERVE_DAYS, foodReserve } from "./owner";
import { NODE_INPUTS, ATTACK_INPUTS } from "./policy";

export const FEATURE_ONE: int32 = 127;

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
	SpareItemPrice,
	Listed,
	MarketGain,
	MarketPrice,
	DawnHearts,
	FoodDays,
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

export const SELF_FEATURES: int32 = (SelfFeature.FoodDays as int32) + 1;
export const NODE_FEATURES: int32 = (NodeFeature.BiteGuard as int32) + 1;
export const TARGET_FEATURES: int32 = (TargetFeature.Grudge as int32) + 1;
export const NODE_SELF_INPUTS: int32 = NODE_INPUTS - NODE_FEATURES;
export const ATTACK_SELF_INPUTS: int32 = ATTACK_INPUTS - TARGET_FEATURES;

export enum GrudgeError {
	None,
	Stale,
}

export struct Surroundings {
	pets: Span<Pet>;
	wilds: Span<Pet>;
	base: int32;
	actor: BlockSlot;
	global: GlobalConfig;
	epoch: uint64;
	round: int32;
	robber: Result<BlockSlot, GrudgeError>;
}

export struct MarketView {
	listed: boolean;
	offer: Result<Listing, MarketError>;
}

export function moneyFeature(amount: uint64): int32 {
	return Math.min(log2Times32(amount / 1000 + 1) / 8, FEATURE_ONE);
}

export function signedMoneyFeature(amount: int64): int32 {
	return amount < 0 ? -moneyFeature((-amount) as uint64) : moneyFeature(amount as uint64);
}

export function nodeSelfInput(position: int32): SelfFeature {
	return match (position) {
		0 => SelfFeature.RegionWorker,
		1 => SelfFeature.RegionFighter,
		2 => SelfFeature.RegionSurvivor,
		3 => SelfFeature.PersonaCautious,
		4 => SelfFeature.PersonaGreedy,
		5 => SelfFeature.PersonaVengeful,
		6 => SelfFeature.Level,
		_ => SelfFeature.PointsUnspent,
	};
}

export function attackSelfInput(position: int32): SelfFeature {
	return match (position) {
		0 => SelfFeature.Hearts,
		1 => SelfFeature.MaxHearts,
		2 => SelfFeature.Harvest,
		3 => SelfFeature.Burrow,
		4 => SelfFeature.Level,
		5 => SelfFeature.AttacksLeft,
		6 => SelfFeature.PersonaCautious,
		7 => SelfFeature.PersonaGreedy,
		8 => SelfFeature.PersonaVengeful,
		9 => SelfFeature.Might,
		10 => SelfFeature.Grit,
		_ => SelfFeature.Round,
	};
}

function flag(on: boolean): int32 {
	return on ? FEATURE_ONE : 0;
}

function put(features: Span<int32>, position: int32, value: int32): void {
	features[position] = Math.max(-FEATURE_ONE, Math.min(value, FEATURE_ONE));
}

function heartShare(hearts: uint8, maxHearts: uint8): int32 {
	return (hearts as int32) * FEATURE_ONE / Math.max(maxHearts as int32, 1);
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

export function petAt(this around: Surroundings, slot: int32): Pet {
	return around.pets[around.base + slot];
}

export function actorPet(this around: Surroundings): Pet {
	return around.pets[around.base + (around.actor as int32)];
}

export function defenderAt(this around: Surroundings, slot: int32): Pet {
	const position = around.base + slot;
	const wild = !around.pets[position].alive && around.wilds[position].alive;
	return wild ? around.wilds[position] : around.pets[position];
}

export function livingMates(this around: Surroundings): int32 {
	let living = 0;
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		if (slot != (around.actor as int32) && around.petAt(slot).alive) { living += 1; }
	}
	return living;
}

export function economyMask(this around: Surroundings, market: MarketView): BitSet<EconomyAction> {
	const pet = around.actorPet();
	const legal = pet.legalEconomy(around.global);
	if (!pet.alive) { return legal; }
	const spare = pet.gear.spareSlot(pet.focusStat()).ok;
	const listable = spare && !market.listed ? legal.incl(EconomyAction.ListItem) : legal;
	return market.offer.ok ? listable.incl(EconomyAction.BuyItem) : listable;
}

export function attackMask(this around: Surroundings): AttackMask {
	const pet = around.actorPet();
	if (!pet.alive) { return { bits: 0 }; }
	let attacks = attackHoldMask();
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		if (slot == (around.actor as int32)) { continue; }
		attacks = attacks.attacksOn(pet, around.defenderAt(slot), around.epoch);
	}
	return attacks;
}

export function writeSelfForNodeAndAttack(
	this around: Surroundings,
	persona: PersonaKind,
	stats: Stats,
	features: Span<int32>,
	offset: int32,
): void {
	const pet = around.actorPet();
	const fighter = stats.asCombatant(pet.hearts as int32);
	const attacks = try fighter.attacksLeft(pet.fightsOutOn(around.epoch)) catch 0;
	put(features, selfSlot(offset, SelfFeature.Hearts), heartShare(pet.hearts, pet.maxHearts));
	put(features, selfSlot(offset, SelfFeature.MaxHearts), (pet.maxHearts as int32) * 2);
	put(features, selfSlot(offset, SelfFeature.Harvest), moneyFeature(pet.harvest));
	put(features, selfSlot(offset, SelfFeature.Burrow), moneyFeature(pet.burrow));
	put(features, selfSlot(offset, SelfFeature.Level), (pet.level as int32) * 6);
	put(features, selfSlot(offset, SelfFeature.PointsUnspent), (pet.pointsUnspent as int32) * 6);
	put(features, selfSlot(offset, SelfFeature.RegionWorker) + (pet.region as int32), FEATURE_ONE);
	put(features, selfSlot(offset, SelfFeature.PersonaCautious) + (persona as int32), FEATURE_ONE);
	put(features, selfSlot(offset, SelfFeature.AttacksLeft), attacks * 40);
	const roundShare = around.round * FEATURE_ONE / (ACTS_PER_EPOCH - 1);
	put(features, selfSlot(offset, SelfFeature.Round), roundShare);
	put(features, selfSlot(offset, SelfFeature.Might), stats.might / 2);
	put(features, selfSlot(offset, SelfFeature.Grit), stats.grit / 2);
}

export function writeSelf(
	this around: Surroundings,
	persona: PersonaKind,
	market: MarketView,
	features: Span<int32>,
	offset: int32,
): void {
	const pet = around.actorPet();
	const epoch = around.epoch;
	const stats = pet.stats();
	around.writeSelfForNodeAndAttack(persona, stats, features, offset);
	const level = pet.level as int32;
	const meal = foodCost(Food.Small, level);
	const mealsAfforded = Math.min(pet.wallet() / meal, 31 as uint64) as int32;
	const age = Math.min(epoch - pet.bornEpoch, FEATURE_ONE as uint64) as int32;
	put(features, selfSlot(offset, SelfFeature.MealsAfforded), mealsAfforded * 4);
	put(features, selfSlot(offset, SelfFeature.Age), age);
	put(features, selfSlot(offset, SelfFeature.Shielded), flag(pet.shieldedAt(epoch)));
	put(features, selfSlot(offset, SelfFeature.FightsIn), pet.fightsInOn(epoch) * 40);
	put(features, selfSlot(offset, SelfFeature.Forage), stats.forage / 2);
	for (let ordinal = 0; ordinal <= (Mod.Cannibal as int32); ordinal++) {
		put(
			features,
			selfSlot(offset, SelfFeature.ModOvertime) + ordinal,
			flag(stats.mods.has(ordinal as Mod)),
		);
	}
	put(features, selfSlot(offset, SelfFeature.SmallMealCost), moneyFeature(meal));
	put(features, selfSlot(offset, SelfFeature.LivingMates), around.livingMates() * 14);
	put(features, selfSlot(offset, SelfFeature.PantryHearts), pet.pantry.storedHearts() * 4);
	let richest = 0;
	let threat = 0;
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		const mate = around.petAt(slot);
		const target = around.defenderAt(slot);
		if (slot == (around.actor as int32) || !target.alive) { continue; }
		if (!target.shieldedAt(epoch)) {
			richest = Math.max(richest, moneyFeature(target.harvest));
		}
		if (!mate.alive) { continue; }
		if (mate.attackable(pet, epoch).ok) {
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
	const mintsAfforded = Math.min(pet.wallet() / mintPrice(level), 31 as uint64) as int32;
	put(features, selfSlot(offset, SelfFeature.MintsAfforded), mintsAfforded * 4);
	const hunger = pet.ownStats().hungerPerDay();
	const hungerShare = hunger * FEATURE_ONE / Math.max(pet.maxHearts as int32, 1);
	put(features, selfSlot(offset, SelfFeature.HungerShare), hungerShare);
	const buysLeft = FOOD_BUYS_PER_DAY - (pet.foodBoughtToday as int32);
	put(features, selfSlot(offset, SelfFeature.BuysLeft), buysLeft * 40);
	const spare = pet.gear.spareSlot(pet.focusStat());
	if (spare.ok) {
		const price = pet.gear.at(spare.value).listPrice();
		put(features, selfSlot(offset, SelfFeature.SpareItemPrice), moneyFeature(price));
	}
	put(features, selfSlot(offset, SelfFeature.Listed), flag(market.listed));
	if (market.offer.ok) {
		const listing = market.offer.value;
		put(features, selfSlot(offset, SelfFeature.MarketGain), pet.listingGain(listing) / 11);
		put(features, selfSlot(offset, SelfFeature.MarketPrice), moneyFeature(listing.price));
	}
	put(features, selfSlot(offset, SelfFeature.DawnHearts), pet.dawnHearts() * 8);
	const perDay = Math.max(foodReserve(level, hunger) / GIFT_RESERVE_DAYS, 1 as uint64);
	const foodDays = Math.min(pet.wallet() / perDay, 31 as uint64) as int32;
	put(features, selfSlot(offset, SelfFeature.FoodDays), foodDays * 4);
}

function opensWith(this tree: Tree, id: int32): int32 {
	let opened = 0;
	for (let other = 0; other < TREE_NODES; other++) {
		if (adjacent(id, other) && !tree.has(other) && !tree.touches(other)) { opened += 1; }
	}
	return opened;
}

export function writeNode(
	this pet: Pet,
	id: int32,
	before: Stats,
	features: Span<int32>,
	row: int32,
): void {
	const level = pet.level as int32;
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

export function writeNodeHold(features: Span<int32>, row: int32): void {
	put(features, nodeSlot(row, NodeFeature.Hold), FEATURE_ONE);
}

export function writeNodes(this around: Surroundings, features: Span<int32>, offset: int32): void {
	const pet = around.actorPet();
	const legal = pet.legalNodes(around.global);
	const before = Stats.built(pet.tree, pet.level as int32, pet.talent());
	for (let id = 0; id < TREE_NODES; id++) {
		if (!legal.allowsNode(id)) { continue; }
		pet.writeNode(id, before, features, offset + id * NODE_FEATURES);
	}
	writeNodeHold(features, offset + ALLOCATE_HOLD * NODE_FEATURES);
}

export function writeTarget(
	this around: Surroundings,
	slot: int32,
	features: Span<int32>,
	row: int32,
): void {
	const pet = around.actorPet();
	const epoch = around.epoch;
	const target = around.defenderAt(slot);
	if (slot == (around.actor as int32) || !target.alive) { return; }
	put(features, targetSlot(row, TargetFeature.Present), FEATURE_ONE);
	put(features, targetSlot(row, TargetFeature.Harvest), moneyFeature(target.harvest));
	const shielded = target.shieldedAt(epoch);
	put(features, targetSlot(row, TargetFeature.Shielded), flag(shielded));
	put(features, targetSlot(row, TargetFeature.FightsIn), target.fightsInOn(epoch) * 40);
	put(
		features,
		targetSlot(row, TargetFeature.AttackedToday),
		flag(pet.attackedOn(target.blockSlot(), epoch)),
	);
	put(features, targetSlot(row, TargetFeature.Hearts), heartShare(target.hearts, target.maxHearts));
	const robber = around.robber;
	put(
		features,
		targetSlot(row, TargetFeature.Grudge),
		flag(robber.ok && robber.value == target.blockSlot()),
	);
	const stakeCap = pet.attackable(target, epoch);
	if (!stakeCap.ok) { return; }
	const defender = target.combatantFacing(pet);
	const attacker = pet.combatantFacing(target);
	const winChance = attacker.winChanceFromTable(defender);
	put(features, targetSlot(row, TargetFeature.WinChance), winChance * FEATURE_ONE / BPS);
	for (let ordinal = 0; ordinal < STAKE_LEVELS; ordinal++) {
		const stake = pet.stakeAt(stakeCap.value, ordinal as StakeLevel);
		if (!stake.ok) { continue; }
		const value = defender.attackExpectedValue(
			attacker,
			winChance,
			stake.value,
			target.harvest,
			target.fightsInOn(epoch),
		);
		put(
			features,
			targetSlot(row, TargetFeature.ValueQuarter) + ordinal,
			signedMoneyFeature(value),
		);
	}
}

export function writeTargetHold(features: Span<int32>, row: int32): void {
	put(features, targetSlot(row, TargetFeature.Hold), FEATURE_ONE);
}

export function writeTargets(this around: Surroundings, features: Span<int32>, offset: int32): void {
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		around.writeTarget(slot, features, offset + slot * TARGET_FEATURES);
	}
	writeTargetHold(features, offset + BLOCK_SLOTS * TARGET_FEATURES);
}
