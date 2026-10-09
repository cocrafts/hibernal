import * as arithmetic from "std/solana/arithmetic";
import { BPS } from "./units";
import {
	BASE_STAT,
	LEVEL_STAT_GROWTH,
	REWARD_WEIGHT_OFFSET,
	Mod,
	Region,
	Stats,
	aged,
} from "./stats";
import { Tree } from "./tree";
import { BlockSlot, Pet, GlobalConfig, Insurance } from "./layout";
import {
	EMISSION_START,
	Split,
	settleGlobal,
	pendingReward,
	Food,
	deathSplit,
	NEWBORN_EPOCHS,
} from "./emission";
import { Pantry, mealHearts } from "./pantry";
import {
	Gear,
	GearSlot,
	Item,
	ItemSkill,
	allWornBy,
	hasSkill,
	spentSkill,
	heirlooms,
	minted,
	with,
	bare,
} from "./items";
import { TALENT_LEVEL, Talent, TalentGrade, TalentKind, lineageNudgeBps } from "./talent";
import { NEWBORN_XP, workXp, gainXp, levelForXp, xpToReach } from "./level";
import {
	BONDING_MAX,
	BONDING_DECAY,
	INSURANCE_TREASURY_PERCENT,
	reviveHearts,
	foodReserve,
	giftFor,
	FEED_BONDING,
	PURCHASE_BONDING,
	growthBpsFor,
	ownerCover,
	ownerDose,
	ownerMeal,
	ownerSlots,
	OwnerItem,
	OwnerSlots,
	withSlots,
} from "./owner";

export const DEFAULT_MIN_HEARTS: int32 = 2;
export const LIFESPAN_EPOCHS: uint64 = 90;
export const DECLINE_START_EPOCHS: uint64 = 50;
export const DECLINE_KNEE_EPOCHS: uint64 = 60;
export const KNEE_VIGOR_BPS: int32 = 7000;
export const END_VIGOR_BPS: int32 = 5000;
export const INHERITANCE_TAX_PERCENT: uint64 = 30;
export const HEIR_POINTS_CAP: int32 = 5;
export const HEIRLOOM_SLOTS: int32 = 2;
export const HUNGER_BPS: int32 = 1000;
export const REWARD_FLOOR_SLOTS: uint32 = 500;
export const BOT_WORK_POWER: uint64 = 53;
export const BOT_WEIGHT: uint64 = (BOT_WORK_POWER + REWARD_WEIGHT_OFFSET) * (BOT_WORK_POWER + REWARD_WEIGHT_OFFSET);
export const MIGHT_APPETITE_BPS: int32 = 50;
export const FORAGE_APPETITE_BPS: int32 = 30;
export const GRIT_APPETITE_BPS: int32 = 40;
export const MIN_APPETITE_BPS: int32 = 5000;
export const MAX_APPETITE_BPS: int32 = 30000;
export const BERSERKER_APPETITE_BPS: int32 = 2500;

export enum TalentError {
	Dead,
	TooYoung,
	Revealed,
}

export enum TickError {
	Dead,
	Behind,
}

export enum BurialError {
	Alive,
}

export enum HeirError {
	Alive,
	TreasuryShort,
}

export struct PetAndGlobal {
	pet: Pet;
	global: GlobalConfig;
}

export struct Burial {
	pet: Pet;
	global: GlobalConfig;
	perMate: uint64;
}

export function genesis(this typeof GlobalConfig, genesisTimestamp: uint64): GlobalConfig {
	return {
		genesisTimestamp: genesisTimestamp,
		rewardPerWorkPower: 0,
		rewardEpoch: 0,
		totalWorkPower: 0,
		recycledPending: 0,
		treasury: 0,
		itemReserve: 0,
		emitted: 0,
		livingPets: 0,
		floorSlots: REWARD_FLOOR_SLOTS,
	};
}

export function rewardDenominator(this global: GlobalConfig): uint64 {
	const empty = Math.max((global.floorSlots as int64) - (global.livingPets as int64), 0 as int64);
	return global.totalWorkPower + BOT_WEIGHT * (empty as uint64);
}

export function withBirth(this global: GlobalConfig, weight: uint64): GlobalConfig {
	return { ...global.withWorkPower(0, weight), livingPets: global.livingPets + 1 };
}

export function withDeath(this global: GlobalConfig, weight: uint64): GlobalConfig {
	return { ...global.withWorkPower(weight, 0), livingPets: global.livingPets - 1 };
}

export function settle(this global: GlobalConfig, epoch: uint64): GlobalConfig {
	if (epoch <= global.rewardEpoch) { return global; }
	const settled = settleGlobal(
		global.rewardPerWorkPower,
		global.rewardEpoch,
		epoch,
		global.totalWorkPower,
		global.rewardDenominator(),
		global.recycledPending,
		global.emitted,
		global.treasury,
	);
	return {
		...global,
		rewardPerWorkPower: settled.rewardPerWorkPower,
		rewardEpoch: epoch,
		recycledPending: 0,
		treasury: settled.treasury,
		emitted: settled.emitted,
	};
}

export function withSpend(this global: GlobalConfig, spend: Split): GlobalConfig {
	return {
		...global,
		recycledPending: global.recycledPending + spend.recycled,
		treasury: global.treasury + spend.treasury,
	};
}

export function withTreasuryIncome(this global: GlobalConfig, amount: uint64): GlobalConfig {
	return { ...global, treasury: global.treasury + amount };
}

export function withItemReserve(this global: GlobalConfig, amount: uint64): GlobalConfig {
	return { ...global, itemReserve: global.itemReserve + amount };
}

export function withWorkPower(
	this global: GlobalConfig,
	removed: uint64,
	added: uint64,
): GlobalConfig {
	return { ...global, totalWorkPower: global.totalWorkPower + added - removed };
}

export function born(
	this typeof Pet,
	blockId: uint32,
	slot: BlockSlot,
	region: Region,
	epoch: uint64,
	global: GlobalConfig,
): PetAndGlobal {
	const settled = global.settle(epoch);
	const tree = Tree.empty().withNode(region as int32);
	const level = levelForXp(NEWBORN_XP);
	const stats = Stats.built(tree, level, Talent.unrevealed());
	const pet: Pet = {
		blockId: blockId,
		slot: (slot as int32) as uint8,
		alive: true,
		region: (region as int32) as uint8,
		hearts: stats.maxHearts as uint8,
		maxHearts: stats.maxHearts as uint8,
		forage: stats.forage as uint16,
		might: stats.might as uint16,
		grit: stats.grit as uint16,
		level: level as uint16,
		pointsUnspent: level as uint8,
		xp: NEWBORN_XP,
		tree: tree,
		foodBps: stats.foodBps,
		experienceBps: stats.experienceBps,
		lootBps: stats.lootBps,
		biteGuardBps: stats.biteGuardBps,
		mods: stats.mods,
		harvest: 0,
		burrow: 0,
		rewardSnapshot: settled.rewardPerWorkPower,
		bornEpoch: epoch,
		lastTickEpoch: epoch,
		fightsOutToday: 0,
		fightsInToday: 0,
		bitesInToday: 0,
		slotsAttackedToday: 0 as BitSet<BlockSlot>,
		fightDay: epoch,
		growthMultiplierBps: 0,
		growthMultiplierExpiry: 0,
		minHearts: DEFAULT_MIN_HEARTS as uint8,
		pantry: Pantry.rationOn(epoch, epoch),
		foodBoughtToday: 0,
		talentKind: TalentKind.None as uint8,
		talentBps: BPS as uint16,
		insurance: 0,
		scars: 0,
		lineageGeneration: 0,
		bonding: 0,
		engagedToday: 0,
		ownerFedToday: 0,
		giftOwed: 0,
		ownerBankedAt: 0,
		gear: Gear.bare(),
		grudgeSlot: 0,
		rage: 0,
		rageEpoch: 0,
	};
	return { pet: pet, global: settled.withBirth(stats.rewardWeight()) };
}

export function wildOf(
	blockId: uint32,
	slot: BlockSlot,
	region: Region,
	level: int32,
	epoch: uint64,
	global: GlobalConfig,
): PetAndGlobal {
	const hatched = Pet.born(blockId, slot, region, epoch, global);
	const grown = Stats.built(hatched.pet.tree, level, Talent.unrevealed());
	const wild: Pet = {
		...hatched.pet.withTreeBonuses(grown),
		wild: true,
		level: level as uint16,
		xp: xpToReach(level),
		pointsUnspent: level as uint8,
		forage: grown.forage as uint16,
		might: grown.might as uint16,
		grit: grown.grit as uint16,
		maxHearts: grown.maxHearts as uint8,
		hearts: grown.maxHearts as uint8,
		bornEpoch: epoch - Math.min(epoch, NEWBORN_EPOCHS),
	};
	const before = hatched.pet.stats().rewardWeight();
	return { pet: wild, global: hatched.global.withWorkPower(before, wild.stats().rewardWeight()) };
}

export function retiredWild(this wild: Pet, global: GlobalConfig): GlobalConfig {
	const weight = wild.stats().rewardWeight();
	const unpaid = pendingReward(weight, global.rewardPerWorkPower, wild.rewardSnapshot);
	const owed = wild.alive ? unpaid : 0;
	const left = wild.alive ? global.withDeath(weight) : global;
	return left.withTreasuryIncome(wild.harvest + wild.burrow + wild.giftOwed + owed);
}

export function vigorBps(age: uint64): int32 {
	if (age <= DECLINE_START_EPOCHS) { return BPS; }
	if (age <= DECLINE_KNEE_EPOCHS) {
		const left = (DECLINE_KNEE_EPOCHS - age) as int32;
		return KNEE_VIGOR_BPS + (BPS - KNEE_VIGOR_BPS) * left * left / 100;
	}
	const span = (LIFESPAN_EPOCHS - DECLINE_KNEE_EPOCHS) as int32;
	const past = Math.min(age - DECLINE_KNEE_EPOCHS, LIFESPAN_EPOCHS - DECLINE_KNEE_EPOCHS) as int32;
	return KNEE_VIGOR_BPS - (KNEE_VIGOR_BPS - END_VIGOR_BPS) * past / span;
}

export function vigor(this pet: Pet): int32 {
	return vigorBps(pet.lastTickEpoch - pet.bornEpoch);
}

export function revealTalent(
	this pet: Pet,
	global: GlobalConfig,
	randomness: uint64,
): Result<PetAndGlobal, TalentError> {
	if (!pet.alive) { return Result.err(TalentError.Dead); }
	if ((pet.level as int32) < TALENT_LEVEL) { return Result.err(TalentError.TooYoung); }
	if (pet.talentKind != (TalentKind.None as uint8)) { return Result.err(TalentError.Revealed); }
	const talent = Talent.rolled(randomness, lineageNudgeBps(pet.lineageGeneration as int32));
	const before = pet.stats().rewardWeight();
	const stats = Stats.built(pet.tree, pet.level as int32, talent).aged(pet.vigor());
	const revealed: Pet = {
		...pet,
		talentKind: talent.kind as uint8,
		talentBps: talent.multiplierBps as uint16,
		forage: stats.forage as uint16,
		might: stats.might as uint16,
		grit: stats.grit as uint16,
	};
	return Result.ok({
		pet: revealed,
		global: global.withWorkPower(before, revealed.stats().rewardWeight()),
	});
}

export function agedOut(this pet: Pet): boolean {
	return !pet.alive && pet.hearts > 0;
}

export function appetiteBps(this stats: Stats): int32 {
	const appetite = BPS +
		(stats.might - BASE_STAT) * MIGHT_APPETITE_BPS +
		(stats.forage - BASE_STAT) * FORAGE_APPETITE_BPS -
		(stats.grit - BASE_STAT) * GRIT_APPETITE_BPS +
		(stats.mods.has(Mod.Berserker) ? BERSERKER_APPETITE_BPS : 0);
	return Math.min(Math.max(appetite, MIN_APPETITE_BPS), MAX_APPETITE_BPS);
}

export function hungerPerDay(this stats: Stats): int32 {
	const scale = (BPS as int64) * (BPS as int64);
	const hunger = (stats.maxHearts as int64) *
		(HUNGER_BPS as int64) *
		(stats.appetiteBps() as int64);
	return Math.max(((hunger + scale / 2) / scale) as int32, 1);
}

export function dawnHearts(this pet: Pet): int32 {
	const hungry = (pet.hearts as int32) - pet.ownStats().hungerPerDay();
	const floor = pet.minHearts as int32;
	const [dawn, _left] = pet.pantry.nightMeals(hungry, floor, pet.maxHearts as int32, pet.stats().foodBps);
	return dawn;
}

export function tickTo(
	this pet: Pet,
	global: GlobalConfig,
	epoch: uint64,
): Result<PetAndGlobal, TickError> {
	if (!pet.alive) { return Result.err(TickError.Dead); }
	if (epoch < pet.lastTickEpoch) { return Result.err(TickError.Behind); }
	const settled = global.settle(epoch);
	const workPower = pet.stats().workPower();
	const weight = pet.stats().rewardWeight();
	const pending = pendingReward(weight, settled.rewardPerWorkPower, pet.rewardSnapshot);
	const stats = pet.stats();
	const hunger = pet.ownStats().hungerPerDay();
	let hearts = pet.hearts as int32;
	let pantry = pet.pantry;
	let workedEpochs = 0;
	let old = false;
	let bonding = pet.bonding as int32;
	let armed = pet.insurance == (Insurance.Armed as uint8);
	let revivals = 0;
	let charm = pet.gear.hasSkill(ItemSkill.Revive);
	let slots = pet.ownerSlots();
	let ownerMeals = 0;

	let charmed = false;
	for (let day = pet.lastTickEpoch + 1; day <= epoch && hearts > 0 && !old; day++) {
		workedEpochs += 1;
		old = day >= pet.bornEpoch + LIFESPAN_EPOCHS;
		if (old) { continue; }
		bonding = Math.max(bonding - BONDING_DECAY, -BONDING_MAX);
		let night = hearts - hunger;
		const meal = slots.ownerMeal();
		if (meal.ok && night < (pet.maxHearts as int32)) {
			const restored = mealHearts(meal.value.food, stats.foodBps);
			night = Math.min(night + restored, pet.maxHearts as int32);
			slots = meal.value.left;
			bonding = Math.min(bonding + FEED_BONDING, BONDING_MAX);
			ownerMeals += 1;
		}
		const [fed, _uneaten] = pantry.nightMeals(
			night,
			pet.minHearts as int32,
			pet.maxHearts as int32,
			stats.foodBps,
		);
		hearts = fed;
		pantry = Pantry.rationOn(day, pet.bornEpoch);
		if (hearts <= 0 && charm) {
			hearts = reviveHearts(pet.maxHearts as int32);
			charm = false;
			charmed = true;
		}
		if (hearts <= 0 && armed) {
			hearts = reviveHearts(pet.maxHearts as int32);
			armed = false;
			revivals += 1;
		}
	}
	const newDay = epoch > pet.lastTickEpoch;
	const alive = hearts > 0 && !old;
	const earned = workXp(workPower, workedEpochs);
	const risen = pet.gainXp(earned * ((BPS + stats.experienceBps) as uint32) / (BPS as uint32));
	const faded = Stats.built(pet.tree, risen.level as int32, pet.talent())
		.aged(vigorBps(epoch - pet.bornEpoch));
	const income = pet.harvest + pending;
	const saved = revivals > 0;
	const harvestTaken = saved ? income * INSURANCE_TREASURY_PERCENT / 100 : 0;
	const burrowTaken = saved ? pet.burrow * INSURANCE_TREASURY_PERCENT / 100 : 0;
	let growthBps = pet.growthMultiplierBps as int32;
	let growthExpiry = pet.growthMultiplierExpiry;
	let insurance = saved ? Insurance.Used as uint8 : pet.insurance;
	if (alive) {
		const dose = slots.ownerDose();
		if (dose.ok) {
			growthBps = growthBpsFor(dose.value.steps);
			growthExpiry = epoch + 1;
			slots = dose.value.left;
			bonding = Math.min(bonding + PURCHASE_BONDING, BONDING_MAX);
		}
		const cover = slots.ownerCover();
		if (cover.ok && insurance == (Insurance.None as uint8)) {
			insurance = Insurance.Armed as uint8;
			slots = cover.value;
		}
	}
	const fed: Pet = {
		...risen,
		alive: alive,
		forage: faded.forage as uint16,
		might: faded.might as uint16,
		grit: faded.grit as uint16,
		maxHearts: faded.maxHearts as uint8,
		hearts: hearts as uint8,
		pantry: pantry,
		foodBoughtToday: newDay ? 0 : pet.foodBoughtToday,
		engagedToday: newDay ? 0 : pet.engagedToday,
		ownerFedToday: ((newDay ? 0 : pet.ownerFedToday as int32) + ownerMeals) as uint8,
		ownerFirst: (slots.first as int32) as uint8,
		ownerSecond: (slots.second as int32) as uint8,
		growthMultiplierBps: growthBps as uint16,
		growthMultiplierExpiry: growthExpiry,
		bonding: bonding as int8,
		rage: pet.rageAt(epoch),
		insurance: insurance,
		scars: ((pet.scars as int32) + revivals) as uint8,
		harvest: income - harvestTaken,
		burrow: pet.burrow - burrowTaken,
		gear: (charmed ? pet.gear.spentSkill(ItemSkill.Revive) : pet.gear).allWornBy(workedEpochs),
		rewardSnapshot: settled.rewardPerWorkPower,
		lastTickEpoch: epoch,
	};
	const reserve = foodReserve(fed.level as int32, hunger);
	const gift = newDay && alive ? fed.giftFor(reserve, pending) : 0;
	const gifted: Pet = { ...fed, burrow: fed.burrow - gift, giftOwed: fed.giftOwed + gift };
	const weighed = alive
		? settled.withWorkPower(weight, gifted.stats().rewardWeight())
		: settled.withDeath(weight);
	return Result.ok({
		pet: gifted.onFightDay(epoch),
		global: { ...weighed, treasury: weighed.treasury + harvestTaken + burrowTaken },
	});
}

export function bury(
	this pet: Pet,
	livingMates: int32,
	global: GlobalConfig,
): Result<Burial, BurialError> {
	if (pet.alive) { return Result.err(BurialError.Alive); }
	const wallet = pet.harvest + pet.burrow;
	if (pet.agedOut()) {
		const tax = wallet * INHERITANCE_TAX_PERCENT / 100;
		return Result.ok({
			pet: { ...pet, harvest: 0, burrow: wallet - tax },
			global: { ...global, recycledPending: global.recycledPending + tax },
			perMate: 0,
		});
	}
	const [perMate, unshared] = deathSplit(wallet, livingMates);
	return Result.ok({
		pet: { ...pet, harvest: 0, burrow: 0, gear: Gear.bare() },
		global: { ...global, treasury: global.treasury + unshared },
		perMate: perMate,
	});
}

export function heirOf(
	this dead: Pet,
	epoch: uint64,
	global: GlobalConfig,
): Result<PetAndGlobal, HeirError> {
	if (dead.alive) { return Result.err(HeirError.Alive); }
	const [heirlooms, proceeds] = dead.gear.heirlooms(HEIRLOOM_SLOTS);
	if (global.itemReserve < proceeds) { return Result.err(HeirError.TreasuryShort); }
	const paid: GlobalConfig = { ...global, itemReserve: global.itemReserve - proceeds };
	const hatched = Pet.born(dead.blockId, dead.blockSlot(), dead.startRegion(), epoch, paid);
	const generation = (dead.lineageGeneration as int32) + 1;
	const points = (hatched.pet.pointsUnspent as int32) + Math.min(generation, HEIR_POINTS_CAP);
	const heir: Pet = {
		...hatched.pet,
		burrow: dead.burrow + proceeds,
		pointsUnspent: points as uint8,
		lineageGeneration: generation as uint16,
		giftOwed: dead.giftOwed,
		ownerFirst: dead.ownerFirst,
		ownerSecond: dead.ownerSecond,
		skin: dead.skin,
		gear: heirlooms,
	};
	return Result.ok({
		pet: heir,
		global: hatched.global.withWorkPower(
			hatched.pet.stats().rewardWeight(),
			heir.stats().rewardWeight(),
		),
	});
}

function hatch(region: Region, epoch: uint64, global: GlobalConfig): PetAndGlobal {
	return Pet.born(0, BlockSlot.First, region, epoch, global);
}

function tickedTo(this pet: Pet, global: GlobalConfig, epoch: uint64): PetAndGlobal {
	const result = pet.tickTo(global, epoch);
	if (!result.ok) { unreachable; }
	return result.value;
}

function fedDailyTo(this pet: Pet, global: GlobalConfig, epoch: uint64): PetAndGlobal {
	let state: PetAndGlobal = { pet: pet, global: global };
	for (let day = pet.lastTickEpoch + 1; day <= epoch; day++) {
		const stocked: Pet = {
			...state.pet,
			minHearts: state.pet.maxHearts,
			pantry: Pantry.unstocked().adding(Food.Large, 3),
		};
		state = stocked.tickedTo(state.global, day);
	}
	return state;
}

test "a newborn starts at its region with one point and joins the work power" {
	const worker = hatch(Region.Worker, 4, GlobalConfig.genesis(0));
	assert worker.pet.forage == 80;
	assert worker.pet.level == 1;
	assert worker.pet.pointsUnspent == 1;
	assert worker.pet.xp == NEWBORN_XP;
	assert worker.pet.startRegion() == Region.Worker;
	assert worker.pet.tree.has(Region.Worker as int32);
	const shifted = 34 + REWARD_WEIGHT_OFFSET;
	assert worker.global.totalWorkPower == shifted * shifted;
	assert worker.global.rewardEpoch == 4;
	assert worker.pet.rewardSnapshot == worker.global.rewardPerWorkPower;
}

test "the first tick pays the emission share and levels on work xp" {
	const small: GlobalConfig = { ...GlobalConfig.genesis(0), floorSlots: 2 };
	const first = hatch(Region.Worker, 0, small);
	const second = Pet.born(0, BlockSlot.Second, Region.Fighter, 0, first.global);
	const firstTicked = first.pet.tickedTo(second.global, 1);
	const secondTicked = second.pet.tickedTo(firstTicked.global, 1);
	const paid = firstTicked.pet.harvest + secondTicked.pet.harvest;
	assert paid <= EMISSION_START;
	assert EMISSION_START - paid < 100;
	assert firstTicked.pet.harvest > secondTicked.pet.harvest;
	assert firstTicked.pet.xp == NEWBORN_XP + workXp(34, 1);
	assert firstTicked.pet.level == 3;
	assert firstTicked.pet.pointsUnspent == 3;
}

test "hunger is a share of max hearts that might and forage raise and grit lowers, within bounds" {
	const pet: Stats = { ...Stats.base(), maxHearts: 40 };
	const mighty: Stats = { ...pet, might: BASE_STAT + 100 };
	const forager: Stats = { ...pet, forage: BASE_STAT + 100 };
	const gritty: Stats = { ...pet, grit: BASE_STAT + 100 };
	const stone: Stats = { ...pet, grit: BASE_STAT + 400 };
	const tiny: Stats = { ...pet, maxHearts: 1 };
	const titan: Stats = { ...pet, might: BASE_STAT + 900 };
	assert pet.hungerPerDay() == 4;
	assert mighty.hungerPerDay() == 6;
	assert forager.hungerPerDay() == 5;
	assert gritty.hungerPerDay() == 2;
	assert stone.appetiteBps() == MIN_APPETITE_BPS;
	assert titan.appetiteBps() == MAX_APPETITE_BPS && titan.hungerPerDay() == 12;
	assert tiny.hungerPerDay() == 1;
}

test "gear makes a pet stronger without making it hungrier" {
	const newborn = hatch(Region.Fighter, 0, GlobalConfig.genesis(0));
	const strong: Pet = { ...newborn.pet, might: 400, maxHearts: 40 };
	const mythic = Item.minted(TalentGrade.Mythic, TalentKind.Might, ItemSkill.None, 1);
	const armed: Pet = { ...strong, gear: Gear.bare().with(GearSlot.Head, mythic) };
	assert armed.stats().might > strong.stats().might;
	assert armed.stats().hungerPerDay() > armed.ownStats().hungerPerDay();
	assert armed.ownStats().hungerPerDay() == strong.ownStats().hungerPerDay();
}

test "hunger takes a heart every day and starvation leaves the work power" {
	const newborn = hatch(Region.Survivor, 0, GlobalConfig.genesis(0));
	const hungry: Pet = { ...newborn.pet, minHearts: 0 };
	assert hungry.tickedTo(newborn.global, 3).pet.hearts == 7;
	const starved = hungry.tickedTo(newborn.global, 10);
	assert starved.pet.hearts == 0;
	assert !starved.pet.alive;
	assert starved.global.totalWorkPower == 0;
}

test "the floor eats from the pantry at night, never from the burrow" {
	const newborn = hatch(Region.Worker, 0, GlobalConfig.genesis(0));
	const stocked: Pet = {
		...newborn.pet,
		hearts: 2,
		burrow: 1000 * EMISSION_START,
		pantry: Pantry.unstocked().adding(Food.Large, 1),
		foodBoughtToday: 1,
		lastTickEpoch: 9,
	};
	const fed = stocked.tickedTo(newborn.global, 10);
	assert fed.pet.hearts == 10;
	assert fed.pet.pantry.stored() == 0;
	assert fed.pet.foodBoughtToday == 0;
	assert fed.pet.burrow == stocked.burrow;
	assert fed.global.recycledPending == newborn.global.recycledPending;
	const unfed = fed.pet.tickedTo(fed.global, 12);
	assert unfed.pet.hearts == 8;
}

test "the pet eats the owner's food at night, takes a dose the day it wakes and arms insurance it lacks" {
	const newborn = hatch(Region.Worker, 0, GlobalConfig.genesis(0));
	const slots: OwnerSlots = { first: OwnerItem.LargeFood, second: OwnerItem.MediumGrowth };
	const slotted = newborn.pet.withSlots(slots);
	const hungry: Pet = { ...slotted, hearts: 3, pantry: Pantry.unstocked() };
	const woke = hungry.tickedTo(newborn.global, 1).pet;
	assert woke.hearts > 3;
	assert woke.ownerFedToday == 1;
	assert woke.ownerSlots().first == OwnerItem.None && woke.ownerSlots().second == OwnerItem.None;
	assert woke.growthBoosted() && woke.growthMultiplierBps == 11000;
	assert woke.stats().forage > hungry.stats().forage;
	assert (woke.bonding as int32) > (hungry.bonding as int32);
	const later = woke.tickedTo(newborn.global, 2).pet;
	assert !later.growthBoosted();
	const spent: Pet = {
		...newborn.pet.withSlots({ first: OwnerItem.Insurance, second: OwnerItem.None }),
		insurance: Insurance.Used as uint8,
	};
	const waiting = spent.tickedTo(newborn.global, 1).pet;
	assert waiting.ownerSlots().first == OwnerItem.Insurance;
	const gone: Pet = { ...waiting, alive: false };
	const heir = gone.heirOf(9, newborn.global);
	assert heir.ok;
	if (!heir.ok) { return; }
	assert heir.value.pet.ownerSlots().first == OwnerItem.Insurance;
	const covered = heir.value.pet.tickedTo(heir.value.global, 10).pet;
	assert covered.insurance == (Insurance.Armed as uint8);
	assert covered.ownerSlots().first == OwnerItem.None;
}

test "a retired wild leaves its wallet and its unpaid share to the treasury" {
	const settled = GlobalConfig.genesis(0);
	const spawned = wildOf(0, BlockSlot.First, Region.Fighter, 5, 1, settled);
	assert spawned.pet.wild && spawned.pet.level == 5;
	assert spawned.global.livingPets == 1;
	const rich: Pet = { ...spawned.pet, harvest: 40, burrow: 60 };
	const later = spawned.global.settle(2);
	const owed = pendingReward(rich.stats().rewardWeight(), later.rewardPerWorkPower, rich.rewardSnapshot);
	assert owed > 0;
	const retired = rich.retiredWild(later);
	assert retired.livingPets == 0 && retired.totalWorkPower == 0;
	assert retired.treasury == later.treasury + 100 + owed;
}

test "food left after the night is thrown away" {
	const newborn = hatch(Region.Worker, 0, GlobalConfig.genesis(0));
	const full: Pet = {
		...newborn.pet,
		pantry: Pantry.unstocked().adding(Food.Small, 2),
		lastTickEpoch: 9,
	};
	const ticked = full.tickedTo(newborn.global, 10);
	assert ticked.pet.hearts == 9;
	assert ticked.pet.pantry.stored() == 0;
}

test "a newborn gets a small ration on each of its three shielded days" {
	const newborn = hatch(Region.Worker, 0, GlobalConfig.genesis(0));
	assert newborn.pet.pantry.portions(Food.Small) == 1;
	assert newborn.pet.tickedTo(newborn.global, 2).pet.pantry.portions(Food.Small) == 1;
	assert newborn.pet.tickedTo(newborn.global, 3).pet.pantry.stored() == 0;
	const faint: Pet = { ...newborn.pet, hearts: 1 };
	const rescued = faint.tickedTo(newborn.global, 1);
	assert rescued.pet.alive;
	assert rescued.pet.hearts == 3;
}

test "ticks refuse the dead and the past, and a burial splits the wallet" {
	const newborn = hatch(Region.Worker, 0, GlobalConfig.genesis(0));
	const dead: Pet = { ...newborn.pet, alive: false, hearts: 0, harvest: 700, burrow: 301 };
	const refused = dead.tickTo(newborn.global, 1);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == TickError.Dead; }
	const later = newborn.pet.tickedTo(newborn.global, 4);
	const behind = later.pet.tickTo(later.global, 3);
	assert !behind.ok;
	if (!behind.ok) { assert behind.error == TickError.Behind; }
	const burial = dead.bury(3, newborn.global);
	assert burial.ok;
	if (burial.ok) {
		assert burial.value.perMate == 166;
		assert burial.value.pet.harvest == 0 && burial.value.pet.burrow == 0;
		assert burial.value.global.treasury == 1001 - 166 * 3;
	}
	assert !newborn.pet.bury(3, newborn.global).ok;
}

test "vigor holds to day 50, bends to 70% on day 60 and ends at half" {
	assert vigorBps(0) == BPS;
	assert vigorBps(DECLINE_START_EPOCHS) == BPS;
	assert vigorBps(55) == KNEE_VIGOR_BPS + 750;
	assert vigorBps(DECLINE_KNEE_EPOCHS) == KNEE_VIGOR_BPS;
	assert vigorBps(75) == 6000;
	assert vigorBps(LIFESPAN_EPOCHS) == END_VIGOR_BPS;
	assert vigorBps(500) == END_VIGOR_BPS;
}

test "an old pet fades, dies on day 90 with its hearts, and pays the tax once" {
	const newborn = hatch(Region.Worker, 0, GlobalConfig.genesis(0));
	const prime = newborn.pet.fedDailyTo(newborn.global, DECLINE_START_EPOCHS);
	const primeLevel = prime.pet.level as int32;
	const primeStats = Stats.built(prime.pet.tree, primeLevel, prime.pet.talent());
	assert (prime.pet.forage as int32) == primeStats.forage;
	assert prime.pet.forage > 80;
	const fading = prime.pet.fedDailyTo(prime.global, DECLINE_KNEE_EPOCHS);
	assert fading.pet.alive;
	const knee = Stats.built(fading.pet.tree, fading.pet.level as int32, fading.pet.talent())
		.aged(KNEE_VIGOR_BPS);
	assert (fading.pet.forage as int32) == knee.forage;
	assert fading.pet.forage < prime.pet.forage;
	assert fading.global.totalWorkPower == knee.rewardWeight();
	const last = fading.pet.fedDailyTo(fading.global, LIFESPAN_EPOCHS - 1);
	assert last.pet.alive;
	const gone = last.pet.tickedTo(last.global, LIFESPAN_EPOCHS);
	assert !gone.pet.alive;
	assert gone.pet.agedOut();
	assert gone.global.totalWorkPower == 0;
	const wallet = gone.pet.harvest + gone.pet.burrow;
	const burial = gone.pet.bury(4, gone.global);
	assert burial.ok;
	if (burial.ok) {
		const tax = wallet * INHERITANCE_TAX_PERCENT / 100;
		assert burial.value.perMate == 0;
		assert burial.value.pet.burrow == wallet - tax;
		assert burial.value.global.recycledPending == gone.global.recycledPending + tax;
	}
}

function strongForager(talent: Talent): boolean {
	return talent.kind == TalentKind.Forage && talent.multiplierBps >= 13000;
}

test "a talent shows at level ten once, scales its whole stat and moves the work power" {
	const newborn = hatch(Region.Worker, 0, GlobalConfig.genesis(0));
	const young = newborn.pet.revealTalent(newborn.global, 7);
	assert !young.ok;
	if (!young.ok) { assert young.error == TalentError.TooYoung; }
	const grown = newborn.pet.fedDailyTo(newborn.global, 20);
	assert (grown.pet.level as int32) >= TALENT_LEVEL;
	let seed: uint64 = 1;
	while (!strongForager(Talent.rolled(seed, 0))) { seed += 1; }
	const shown = grown.pet.revealTalent(grown.global, seed);
	assert shown.ok;
	if (!shown.ok) { return; }
	const pet = shown.value.pet;
	const talent = Talent.rolled(seed, 0);
	const growth = ((pet.level as int32) - 1) * LEVEL_STAT_GROWTH;
	assert (pet.forage as int32) == (80 + growth) * talent.multiplierBps / BPS;
	assert pet.might == grown.pet.might;
	const added = pet.stats().rewardWeight() - grown.pet.stats().rewardWeight();
	assert shown.value.global.totalWorkPower == grown.global.totalWorkPower + added;
	const again = pet.revealTalent(shown.value.global, seed);
	assert !again.ok;
	if (!again.ok) { assert again.error == TalentError.Revealed; }
}

test "an heir keeps the slot and the estate and gets a point per generation" {
	const newborn = hatch(Region.Survivor, 0, GlobalConfig.genesis(0));
	const estate: Pet = { ...newborn.pet, alive: false, hearts: 3, burrow: 700, lineageGeneration: 6 };
	const heir = estate.heirOf(97, newborn.global);
	assert heir.ok;
	if (heir.ok) {
		assert heir.value.pet.alive;
		assert heir.value.pet.bornEpoch == 97;
		assert heir.value.pet.burrow == 700;
		assert heir.value.pet.lineageGeneration == 7;
		assert heir.value.pet.pointsUnspent == newborn.pet.pointsUnspent + (HEIR_POINTS_CAP as uint8);
		assert heir.value.pet.startRegion() == Region.Survivor;
	}
	const refused = newborn.pet.heirOf(97, newborn.global);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == HeirError.Alive; }
}

test "each day bonding slips, and a devoted pet gifts what it can spare" {
	const newborn = hatch(Region.Worker, 0, GlobalConfig.genesis(0));
	const plenty: uint64 = 5000000000;
	const devoted: Pet = {
		...newborn.pet,
		bonding: 127,
		burrow: plenty,
		engagedToday: 2,
		ownerFedToday: 1,
	};
	const next = devoted.tickedTo(newborn.global, 1);
	assert (next.pet.bonding as int32) == 127 - BONDING_DECAY;
	assert next.pet.engagedToday == 0 && next.pet.ownerFedToday == 0;
	assert next.pet.giftOwed > 0;
	assert next.pet.burrow + next.pet.giftOwed == plenty;
}

test "an insured pet that starves comes back once from its tick" {
	const newborn = hatch(Region.Worker, 0, GlobalConfig.genesis(0));
	const hungry: Pet = {
		...newborn.pet,
		hearts: 1,
		minHearts: 0,
		burrow: 400,
		insurance: Insurance.Armed as uint8,
		pantry: Pantry.unstocked(),
	};
	const next = hungry.tickedTo(newborn.global, 1);
	assert next.pet.alive;
	assert next.pet.insurance == (Insurance.Used as uint8);
	assert next.pet.scars == 1;
	assert next.pet.burrow == 200;
	assert next.global.treasury >= newborn.global.treasury + 200;
}

test "below the floor, empty slots count as bots and their share is not paid" {
	const floored: GlobalConfig = { ...GlobalConfig.genesis(0), floorSlots: 10 };
	const lone = hatch(Region.Worker, 0, floored);
	assert lone.global.livingPets == 1;
	assert lone.global.rewardDenominator() == lone.global.totalWorkPower + BOT_WEIGHT * 9;
	const ticked = lone.pet.tickedTo(lone.global, 1);
	const share = EMISSION_START * lone.global.totalWorkPower / lone.global.rewardDenominator();
	assert ticked.pet.harvest <= share + 1 && ticked.pet.harvest + 100 >= share;
	const dead: Pet = { ...ticked.pet, hearts: 1, minHearts: 0, pantry: Pantry.unstocked() };
	const gone = dead.tickedTo(ticked.global, 2);
	assert !gone.pet.alive;
	assert gone.global.livingPets == 0;
	assert gone.global.totalWorkPower == 0;
}

test "a common level-twenty pet weighs what a bot weighs" {
	const fighterTree = Tree.empty().withNode(Region.Fighter as int32);
	const common = Stats.built(fighterTree, 20, Talent.unrevealed());
	assert common.rewardWeight() == BOT_WEIGHT;
}
