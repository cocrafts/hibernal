import {
	BLOCK_SLOTS,
	STAKE_LEVELS,
	BPS,
	HBRN_UNIT,
	INCOMING_CAP,
	LEVEL_CAP,
	BlockSlot,
	Food,
	Pet,
	Persona,
	EconomyAction,
	StakeLevel,
	foodCost,
	Pantry,
	stakeShareBps,
	winChanceFromTable,
	agedOut,
	totalBonusBps,
} from "../../rules/index";
import { World, WorldStats, blockStart } from "../world";
import { personaKindOf } from "../teacher";
import { Head, zeros } from "./observe";

export const RECKLESS_WIN_CHANCE_BPS: int32 = 4000;
export const REVENGE_EPOCHS: uint64 = 3;
export const EARLY_LEVEL: int32 = 10;

export enum FeelCounter {
	Attacks,
	AttacksWon,
	RecklessAttacks,
	UnderPersonaAttacks,
	WinChanceSum,
	StakeShareSum,
	BurrowShareSum,
	Robbed,
	Avenged,
	Meals,
	MealHeartsSum,
	Banks,
	LivingEpochs,
	HeartsSum,
	Starved,
	StarvedUnbanked,
	StarvedStocked,
	Bitten,
	Wealth,
	Living,
	AgedOut,
	HeartsBitten,
	HeartsLostAttacking,
	Lives,
	DiedAttacking,
	EarlyLevelLives,
	EarlyLevelAgeSum,
	CapLevelLives,
	CapLevelAgeSum,
	Earned,
	EarnedAtCap,
	FoodSpent,
	FoodSpentAtCap,
	LootLost,
	FightsInSum,
	FightsInCapDays,
	BornAtEnd,
	BondingSum,
	Revived,
	Gifted,
	Skr,
	OwnerVisits,
	OwnerRefusals,
	Mints,
	MintSpent,
	GearBonusSum,
	RobbedAgain,
	WildRaids,
	WildLoot,
	Sells,
}

export const FEEL_COUNTERS: int32 = (FeelCounter.Sells as int32) + 1;

export enum Milestone {
	EarlyLevel,
	CapLevel,
}

export enum Larder {
	Dead,
	Empty,
	Unbanked,
	Stocked,
}

export struct Grudge {
	robber: BlockSlot;
	epoch: uint64;
}

export struct Moment {
	env: int32;
	index: int32;
	head: Head;
	action: int32;
	actor: Pet;
	defender: Pet;
	stats: WorldStats;
}

export struct Feel {
	counters: int32[];
	grudges: Grudge[];
	larders: Larder[];
	lifeBorns: uint64[];
	milestones: BitSet<Milestone>[];
	harvests: uint64[];
	scars: int32[];
	pets: int32;
}

export function create(this typeof Feel, envCount: int32, pets: int32): Feel {
	const grudges: Grudge[] = [];
	const larders: Larder[] = [];
	const lifeBorns: uint64[] = [];
	const milestones: BitSet<Milestone>[] = [];
	const harvests: uint64[] = [];
	const scars: int32[] = [];
	for (let key = 0; key < envCount * pets; key++) {
		grudges.push({ robber: BlockSlot.First, epoch: 0 });
		larders.push(Larder.Dead);
		lifeBorns.push(0);
		milestones.push(0 as BitSet<Milestone>);
		harvests.push(0);
		scars.push(0);
	}
	return {
		counters: zeros(envCount * pets * FEEL_COUNTERS),
		grudges: grudges,
		larders: larders,
		lifeBorns: lifeBorns,
		milestones: milestones,
		harvests: harvests,
		scars: scars,
		pets: pets,
	};
}

export function tallied(this feel: Feel, key: int32, counter: FeelCounter): int32 {
	return feel.counters[key * FEEL_COUNTERS + (counter as int32)];
}

function tally(this feel: Feel, key: int32, counter: FeelCounter, amount: int32): void {
	const counters = feel.counters;
	const position = key * FEEL_COUNTERS + (counter as int32);
	counters[position] = counters[position] + amount;
}

export function larderOf(this pet: Pet): Larder {
	if (!pet.alive) { return Larder.Dead; }
	const meal = foodCost(Food.Small, pet.level as int32);
	if (pet.pantry.stored() > 0 || pet.burrow >= meal) { return Larder.Stocked; }
	return pet.harvest + pet.burrow >= meal ? Larder.Unbanked : Larder.Empty;
}

export function momentOf(
	this world: World,
	env: int32,
	index: int32,
	head: Head,
	action: int32,
): Moment {
	const slot = action / STAKE_LEVELS;
	const attacking = head == Head.Attack && slot >= 0 && slot < BLOCK_SLOTS;
	const target = attacking ? blockStart(index) + slot : index;
	return {
		env: env,
		index: index,
		head: head,
		action: action,
		actor: world.pets[index],
		defender: world.defenderAt(target),
		stats: world.stats,
	};
}

function noteEconomy(this feel: Feel, key: int32, action: int32, actor: Pet, after: Pet): void {
	if (action == (EconomyAction.SellItem as int32) && after.burrow > actor.burrow) {
		feel.tally(key, FeelCounter.Sells, 1);
	}
	if (action == (EconomyAction.Mint as int32) && after.burrow < actor.burrow) {
		feel.tally(key, FeelCounter.Mints, 1);
		const spent = ((actor.burrow - after.burrow) / HBRN_UNIT) as int32;
		feel.tally(key, FeelCounter.MintSpent, spent);
	}
	if (after.pantry.stored() > actor.pantry.stored()) {
		const spent = ((actor.burrow - after.burrow) / HBRN_UNIT) as int32;
		feel.tally(key, FeelCounter.FoodSpent, spent);
		if ((actor.level as int32) >= LEVEL_CAP) {
			feel.tally(key, FeelCounter.FoodSpentAtCap, spent);
		}
	}
	if (after.hearts > actor.hearts) {
		feel.tally(key, FeelCounter.Meals, 1);
		feel.tally(key, FeelCounter.MealHeartsSum, actor.hearts as int32);
	}
	if (after.burrow > actor.burrow) { feel.tally(key, FeelCounter.Banks, 1); }
}

function noteAttack(this feel: Feel, key: int32, moment: Moment, world: World): void {
	if (world.stats.fights == moment.stats.fights) { return; }
	const attacker = moment.actor;
	const defender = moment.defender;
	const level = (moment.action % STAKE_LEVELS) as StakeLevel;
	const facing = defender.combatantFacing(attacker);
	const winChance = attacker.combatantFacing(defender).winChanceFromTable(facing);
	const persona = Persona.of(personaKindOf(moment.index));
	feel.tally(key, FeelCounter.Attacks, 1);
	feel.tally(key, FeelCounter.WinChanceSum, winChance);
	feel.tally(key, FeelCounter.StakeShareSum, stakeShareBps(level));
	if (winChance < RECKLESS_WIN_CHANCE_BPS) { feel.tally(key, FeelCounter.RecklessAttacks, 1); }
	if (winChance < persona.minWinChanceBps) {
		feel.tally(key, FeelCounter.UnderPersonaAttacks, 1);
	}
	const stake = attacker.stakeFor(defender, level, world.epoch);
	if (stake.ok && attacker.burrow > 0) {
		const share = stake.value * (BPS as uint64) / attacker.burrow;
		feel.tally(key, FeelCounter.BurrowShareSum, share as int32);
	}
	const grudges = feel.grudges;
	const grudge = grudges[key];
	const fresh = grudge.epoch != 0 && world.epoch <= grudge.epoch + REVENGE_EPOCHS;
	if (fresh && grudge.robber == defender.blockSlot()) {
		feel.tally(key, FeelCounter.Avenged, 1);
		grudges[key] = { robber: BlockSlot.First, epoch: 0 };
	}
	if (world.stats.wins == moment.stats.wins) {
		const beaten = world.pets[moment.index];
		const lost = (attacker.hearts as int32) - (beaten.hearts as int32);
		feel.tally(key, FeelCounter.HeartsLostAttacking, lost);
		if (!beaten.alive) { feel.tally(key, FeelCounter.DiedAttacking, 1); }
		return;
	}
	const victim = moment.env * feel.pets + blockStart(moment.index) + (defender.slot as int32);
	feel.tally(key, FeelCounter.AttacksWon, 1);
	const target = blockStart(moment.index) + (defender.slot as int32);
	if (!world.pets[target].alive) {
		const taken = defender.harvest - world.wilds[target].harvest;
		feel.tally(key, FeelCounter.WildRaids, 1);
		feel.tally(key, FeelCounter.WildLoot, (taken / HBRN_UNIT) as int32);
		return;
	}
	feel.tally(victim, FeelCounter.Robbed, 1);
	const last = grudges[victim];
	const again = last.epoch != 0 && world.epoch <= last.epoch + REVENGE_EPOCHS;
	if (again && last.robber == attacker.blockSlot()) {
		feel.tally(victim, FeelCounter.RobbedAgain, 1);
	}
	grudges[victim] = { robber: attacker.blockSlot(), epoch: world.epoch };
	const struck = world.pets[blockStart(moment.index) + (defender.slot as int32)];
	const bitten = (defender.hearts as int32) - (struck.hearts as int32);
	const lost = ((defender.harvest - struck.harvest) / HBRN_UNIT) as int32;
	feel.tally(victim, FeelCounter.LootLost, lost);
	feel.tally(victim, FeelCounter.HeartsBitten, bitten);
	if (!struck.alive) { feel.tally(victim, FeelCounter.Bitten, 1); }
}

export function note(this feel: Feel, moment: Moment, world: World): void {
	const key = moment.env * feel.pets + moment.index;
	if (!moment.actor.alive) { return; }
	match (moment.head) {
		Head.Economy => {
			feel.noteEconomy(key, moment.action, moment.actor, world.pets[moment.index]);
		},
		Head.Node => {},
		Head.Attack => { feel.noteAttack(key, moment, world); },
	}
}

export function closeEpoch(this feel: Feel, env: int32, world: World): void {
	const larders = feel.larders;
	const harvests = feel.harvests;
	for (let index = 0; index < feel.pets; index++) {
		const key = env * feel.pets + index;
		const pet = world.pets[index];
		larders[key] = pet.larderOf();
		if (!pet.alive) { continue; }
		feel.tally(key, FeelCounter.LivingEpochs, 1);
		feel.tally(key, FeelCounter.HeartsSum, pet.hearts as int32);
		feel.tally(key, FeelCounter.BondingSum, pet.bonding as int32);
		feel.tally(key, FeelCounter.GearBonusSum, pet.gear.totalBonusBps());
		const fightsIn = pet.fightsInOn(world.epoch);
		feel.tally(key, FeelCounter.FightsInSum, fightsIn);
		if (fightsIn >= INCOMING_CAP) { feel.tally(key, FeelCounter.FightsInCapDays, 1); }
		feel.noteMilestones(key, pet, world.epoch);
		harvests[key] = pet.harvest;
	}
}

function noteMilestones(this feel: Feel, key: int32, pet: Pet, epoch: uint64): void {
	const lifeBorns = feel.lifeBorns;
	const milestones = feel.milestones;
	const scars = feel.scars;
	if (lifeBorns[key] != pet.bornEpoch + 1) {
		lifeBorns[key] = pet.bornEpoch + 1;
		milestones[key] = 0 as BitSet<Milestone>;
		scars[key] = pet.scars as int32;
		feel.tally(key, FeelCounter.Lives, 1);
	}
	if ((pet.scars as int32) > scars[key]) {
		feel.tally(key, FeelCounter.Revived, (pet.scars as int32) - scars[key]);
		scars[key] = pet.scars as int32;
	}
	const age = (epoch - pet.bornEpoch) as int32;
	const level = pet.level as int32;
	if (level >= EARLY_LEVEL && !milestones[key].has(Milestone.EarlyLevel)) {
		milestones[key] = milestones[key].incl(Milestone.EarlyLevel);
		feel.tally(key, FeelCounter.EarlyLevelLives, 1);
		feel.tally(key, FeelCounter.EarlyLevelAgeSum, age);
	}
	if (level >= LEVEL_CAP && !milestones[key].has(Milestone.CapLevel)) {
		milestones[key] = milestones[key].incl(Milestone.CapLevel);
		feel.tally(key, FeelCounter.CapLevelLives, 1);
		feel.tally(key, FeelCounter.CapLevelAgeSum, age);
	}
}

export function openEpoch(this feel: Feel, env: int32, world: World): void {
	const grudges = feel.grudges;
	for (let index = 0; index < feel.pets; index++) {
		const key = env * feel.pets + index;
		const pet = world.pets[index];
		if (pet.alive && pet.bornEpoch == world.epoch) {
			grudges[key] = { robber: BlockSlot.First, epoch: 0 };
		}
		const sameLife = feel.lifeBorns[key] == pet.bornEpoch + 1;
		if (pet.alive && sameLife && pet.harvest >= feel.harvests[key]) {
			const earned = ((pet.harvest - feel.harvests[key]) / HBRN_UNIT) as int32;
			feel.tally(key, FeelCounter.Earned, earned);
			if ((pet.level as int32) >= LEVEL_CAP) {
				feel.tally(key, FeelCounter.EarnedAtCap, earned);
			}
		}
		const larder = feel.larders[key];
		if (pet.alive || larder == Larder.Dead) { continue; }
		if (pet.agedOut()) {
			feel.tally(key, FeelCounter.AgedOut, 1);
			continue;
		}
		feel.tally(key, FeelCounter.Starved, 1);
		if (larder == Larder.Unbanked) { feel.tally(key, FeelCounter.StarvedUnbanked, 1); }
		if (larder == Larder.Stocked) { feel.tally(key, FeelCounter.StarvedStocked, 1); }
	}
}

export function closeEpisode(this feel: Feel, env: int32, world: World): void {
	const grudges = feel.grudges;
	const lifeBorns = feel.lifeBorns;
	feel.closeEpoch(env, world);
	for (let index = 0; index < feel.pets; index++) {
		const key = env * feel.pets + index;
		const pet = world.pets[index];
		grudges[key] = { robber: BlockSlot.First, epoch: 0 };
		lifeBorns[key] = 0;
		const ledger = world.ownerLedgers[index];
		feel.tally(key, FeelCounter.Gifted, (pet.giftOwed / HBRN_UNIT) as int32);
		feel.tally(key, FeelCounter.Skr, ledger.skr);
		feel.tally(key, FeelCounter.OwnerVisits, ledger.visits);
		feel.tally(key, FeelCounter.OwnerRefusals, ledger.refusals);
		if (!pet.alive) { continue; }
		feel.tally(key, FeelCounter.Living, 1);
		feel.tally(key, FeelCounter.Wealth, ((pet.harvest + pet.burrow) / HBRN_UNIT) as int32);
		feel.tally(key, FeelCounter.BornAtEnd, pet.bornEpoch as int32);
	}
}

function fought(this world: World, epoch: uint64, won: boolean): World {
	const wins = world.stats.wins + (won ? 1 : 0);
	const stats: WorldStats = { ...world.stats, fights: world.stats.fights + 1, wins: wins };
	return { ...world, epoch: epoch, stats: stats };
}

function attackOn(slot: int32): int32 {
	return slot * STAKE_LEVELS + (StakeLevel.Half as int32);
}

test "a moment keeps the pet as it was before the action applied" {
	const world = World.create(1, 3).beginEpoch(1);
	const pets = world.pets;
	pets[0] = { ...pets[0], harvest: 50 * HBRN_UNIT, burrow: 0 };
	const moment = world.momentOf(0, 0, Head.Economy, EconomyAction.Bank as int32);
	const banked = world.applyEconomy(0, EconomyAction.Bank);
	assert banked.pets[0].burrow > 0;
	assert moment.actor.burrow == 0;
	const feel = Feel.create(1, BLOCK_SLOTS);
	feel.note(moment, banked);
	assert feel.tallied(0, FeelCounter.Banks) == 1;
	assert feel.tallied(0, FeelCounter.Meals) == 0;
}

test "a meal counts the hearts the pet had when it ate" {
	const world = World.create(1, 3).beginEpoch(1);
	const pets = world.pets;
	pets[4] = { ...pets[4], hearts: 2, pantry: Pantry.unstocked().adding(Food.Small, 1) };
	const moment = world.momentOf(0, 4, Head.Economy, EconomyAction.EatSmall as int32);
	const feel = Feel.create(1, BLOCK_SLOTS);
	feel.note(moment, world.applyEconomy(4, EconomyAction.EatSmall));
	assert feel.tallied(4, FeelCounter.Meals) == 1;
	assert feel.tallied(4, FeelCounter.MealHeartsSum) == 2;
}

test "a robbery answered within three epochs is one revenge, and only once" {
	const world = World.create(1, 3).beginEpoch(1);
	const feel = Feel.create(1, BLOCK_SLOTS);
	feel.note(world.momentOf(0, 3, Head.Attack, attackOn(5)), world.fought(10, true));
	assert feel.tallied(3, FeelCounter.Attacks) == 1;
	assert feel.tallied(3, FeelCounter.AttacksWon) == 1;
	assert feel.tallied(5, FeelCounter.Robbed) == 1;
	feel.note(world.momentOf(0, 5, Head.Attack, attackOn(4)), world.fought(11, false));
	assert feel.tallied(5, FeelCounter.Avenged) == 0;
	feel.note(world.momentOf(0, 5, Head.Attack, attackOn(3)), world.fought(13, false));
	assert feel.tallied(5, FeelCounter.Avenged) == 1;
	feel.note(world.momentOf(0, 5, Head.Attack, attackOn(3)), world.fought(13, false));
	assert feel.tallied(5, FeelCounter.Avenged) == 1;
	assert feel.tallied(5, FeelCounter.Attacks) == 3;
}

test "a stale grudge is no revenge and an action without a fight counts nothing" {
	const world = World.create(1, 3).beginEpoch(1);
	const feel = Feel.create(1, BLOCK_SLOTS);
	feel.note(world.momentOf(0, 3, Head.Attack, attackOn(5)), world.fought(10, true));
	feel.note(world.momentOf(0, 5, Head.Attack, attackOn(3)), world.fought(14, true));
	assert feel.tallied(5, FeelCounter.Avenged) == 0;
	assert feel.tallied(3, FeelCounter.Robbed) == 1;
	feel.note(world.momentOf(0, 7, Head.Attack, attackOn(3)), world);
	assert feel.tallied(7, FeelCounter.Attacks) == 0;
}

test "an attack under forty percent is reckless and under every persona" {
	const world = World.create(1, 3).beginEpoch(1);
	const pets = world.pets;
	pets[6] = { ...pets[6], might: 1, grit: 1 };
	pets[2] = { ...pets[2], might: 900, grit: 900 };
	const feel = Feel.create(1, BLOCK_SLOTS);
	feel.note(world.momentOf(0, 6, Head.Attack, attackOn(2)), world.fought(10, false));
	assert feel.tallied(6, FeelCounter.RecklessAttacks) == 1;
	assert feel.tallied(6, FeelCounter.UnderPersonaAttacks) == 1;
	assert feel.tallied(6, FeelCounter.WinChanceSum) < RECKLESS_WIN_CHANCE_BPS;
	feel.note(world.momentOf(0, 2, Head.Attack, attackOn(6)), world.fought(10, true));
	assert feel.tallied(2, FeelCounter.RecklessAttacks) == 0;
	assert feel.tallied(2, FeelCounter.UnderPersonaAttacks) == 0;
	assert feel.tallied(2, FeelCounter.StakeShareSum) == 5000;
}

test "a starved pet is sorted by what it could still have eaten" {
	const world = World.create(1, 3).beginEpoch(1);
	const pets = world.pets;
	const meal = foodCost(Food.Small, pets[0].level as int32);
	pets[0] = { ...pets[0], harvest: 0, burrow: 0, pantry: Pantry.unstocked() };
	pets[1] = { ...pets[1], harvest: meal, burrow: 0, pantry: Pantry.unstocked() };
	pets[2] = { ...pets[2], harvest: 0, burrow: meal, pantry: Pantry.unstocked() };
	assert pets[0].larderOf() == Larder.Empty;
	assert pets[1].larderOf() == Larder.Unbanked;
	assert pets[2].larderOf() == Larder.Stocked;
	const feel = Feel.create(1, BLOCK_SLOTS);
	feel.closeEpoch(0, world);
	for (let index = 0; index < 3; index++) {
		pets[index] = { ...pets[index], alive: false, hearts: 0 };
	}
	feel.openEpoch(0, world);
	feel.closeEpoch(0, world);
	feel.openEpoch(0, world);
	assert feel.tallied(0, FeelCounter.Starved) == 1;
	assert feel.tallied(0, FeelCounter.StarvedUnbanked) == 0;
	assert feel.tallied(1, FeelCounter.StarvedUnbanked) == 1;
	assert feel.tallied(2, FeelCounter.StarvedStocked) == 1;
	assert feel.tallied(3, FeelCounter.Starved) == 0;
	assert feel.tallied(3, FeelCounter.LivingEpochs) == 2;
	assert feel.tallied(3, FeelCounter.HeartsSum) == 2 * (pets[3].hearts as int32);
}

test "hearts lost to a bite and to a lost attack are counted on the pet that lost them" {
	const world = World.create(1, 3).beginEpoch(1);
	const pets = world.pets;
	const feel = Feel.create(1, BLOCK_SLOTS);
	const bite = world.momentOf(0, 3, Head.Attack, attackOn(5));
	pets[5] = { ...pets[5], hearts: (pets[5].hearts as int32 - 2) as uint8 };
	feel.note(bite, world.fought(10, true));
	assert feel.tallied(5, FeelCounter.HeartsBitten) == 2;
	const loss = world.momentOf(0, 6, Head.Attack, attackOn(4));
	pets[6] = { ...pets[6], hearts: (pets[6].hearts as int32 - 1) as uint8 };
	feel.note(loss, world.fought(10, false));
	assert feel.tallied(6, FeelCounter.HeartsLostAttacking) == 1;
	assert feel.tallied(4, FeelCounter.HeartsBitten) == 0;
}

test "a life counts once, with the age at which it first reached level ten" {
	const world = World.create(1, 3).beginEpoch(1);
	const pets = world.pets;
	const feel = Feel.create(1, BLOCK_SLOTS);
	feel.closeEpoch(0, world);
	assert feel.tallied(0, FeelCounter.Lives) == 1;
	pets[0] = { ...pets[0], level: 12 };
	const later: World = { ...world, epoch: 8 };
	feel.closeEpoch(0, later);
	feel.closeEpoch(0, later);
	assert feel.tallied(0, FeelCounter.Lives) == 1;
	assert feel.tallied(0, FeelCounter.EarlyLevelLives) == 1;
	assert feel.tallied(0, FeelCounter.EarlyLevelAgeSum) == (8 - (pets[0].bornEpoch as int32));
	assert feel.tallied(0, FeelCounter.CapLevelLives) == 0;
}

test "income is what reaches the harvest between one close and the next open" {
	const world = World.create(1, 3).beginEpoch(1);
	const pets = world.pets;
	pets[1] = { ...pets[1], harvest: 10 * HBRN_UNIT };
	const feel = Feel.create(1, BLOCK_SLOTS);
	feel.closeEpoch(0, world);
	pets[1] = { ...pets[1], harvest: 25 * HBRN_UNIT };
	feel.openEpoch(0, world);
	assert feel.tallied(1, FeelCounter.Earned) == 15;
	assert feel.tallied(1, FeelCounter.EarnedAtCap) == 0;
}

test "a portion bought counts its price as food spent" {
	const world = World.create(1, 3).beginEpoch(1);
	const pets = world.pets;
	pets[2] = { ...pets[2], burrow: 2000 * HBRN_UNIT };
	const moment = world.momentOf(0, 2, Head.Economy, EconomyAction.BuyLarge as int32);
	const feel = Feel.create(1, BLOCK_SLOTS);
	feel.note(moment, world.applyEconomy(2, EconomyAction.BuyLarge));
	const price = (foodCost(Food.Large, pets[2].level as int32) / HBRN_UNIT) as int32;
	assert feel.tallied(2, FeelCounter.FoodSpent) == price;
}
