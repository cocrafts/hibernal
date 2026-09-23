import { BPS } from "./units";
import { BASE_STAT, Region, Stats, aged } from "./stats";
import { Tree } from "./tree";
import { BlockSlot, Pet, GlobalConfig } from "./layout";
import {
	EMISSION_START,
	Split,
	settleGlobal,
	pendingReward,
	growthBonus,
	Food,
	deathSplit,
} from "./emission";
import { Pantry } from "./pantry";
import { NEWBORN_XP, workXp, gainXp, levelForXp } from "./level";

export const DEFAULT_MIN_HEARTS: int32 = 2;
export const LIFESPAN_EPOCHS: uint64 = 90;
export const DECLINE_START_EPOCHS: uint64 = 50;
export const DECLINE_KNEE_EPOCHS: uint64 = 60;
export const KNEE_VIGOR_BPS: int32 = 7000;
export const END_VIGOR_BPS: int32 = 5000;
export const INHERITANCE_TAX_PERCENT: uint64 = 30;
export const HEIR_POINTS_CAP: int32 = 5;
export const HUNGER_BPS: int32 = 1000;
export const MIGHT_APPETITE_BPS: int32 = 50;
export const FORAGE_APPETITE_BPS: int32 = 30;
export const GRIT_APPETITE_BPS: int32 = 40;
export const MIN_APPETITE_BPS: int32 = 5000;

export enum TickError {
	Dead,
	Behind,
}

export enum BurialError {
	Alive,
}

export enum HeirError {
	Alive,
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
		protocolPending: 0,
		burned: 0,
	};
}

export function settle(this global: GlobalConfig, epoch: uint64): GlobalConfig {
	if (epoch <= global.rewardEpoch) { return global; }
	return {
		...global,
		rewardPerWorkPower: settleGlobal(
			global.rewardPerWorkPower,
			global.rewardEpoch,
			epoch,
			global.totalWorkPower,
			global.recycledPending,
		),
		rewardEpoch: epoch,
		recycledPending: 0,
	};
}

export function withSpend(this global: GlobalConfig, spend: Split): GlobalConfig {
	return {
		...global,
		recycledPending: global.recycledPending + spend.recycled,
		protocolPending: global.protocolPending + spend.protocol,
		burned: global.burned + spend.burned,
	};
}

export function withProtocolFee(this global: GlobalConfig, fee: uint64): GlobalConfig {
	return { ...global, protocolPending: global.protocolPending + fee };
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
	const stats = Stats.fromTree(tree);
	const level = levelForXp(NEWBORN_XP);
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
		insurance: 0,
		scars: 0,
		lineageGeneration: 0,
	};
	return { pet: pet, global: settled.withWorkPower(0, stats.workPower()) };
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

export function agedOut(this pet: Pet): boolean {
	return !pet.alive && pet.hearts > 0;
}

export function appetiteBps(this stats: Stats): int32 {
	const appetite = BPS +
		(stats.might - BASE_STAT) * MIGHT_APPETITE_BPS +
		(stats.forage - BASE_STAT) * FORAGE_APPETITE_BPS -
		(stats.grit - BASE_STAT) * GRIT_APPETITE_BPS;
	return Math.max(appetite, MIN_APPETITE_BPS);
}

export function hungerPerDay(this stats: Stats): int32 {
	const scale = (BPS as int64) * (BPS as int64);
	const hunger = (stats.maxHearts as int64) *
		(HUNGER_BPS as int64) *
		(stats.appetiteBps() as int64);
	return Math.max(((hunger + scale / 2) / scale) as int32, 1);
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
	const pending = pendingReward(workPower, settled.rewardPerWorkPower, pet.rewardSnapshot);
	const growing = epoch < pet.growthMultiplierExpiry;
	const multiplierBps = growing ? pet.growthMultiplierBps as int32 : 0;
	const hunger = pet.stats().hungerPerDay();
	let hearts = pet.hearts as int32;
	let pantry = pet.pantry;
	let workedEpochs = 0;
	let old = false;
	for (let day = pet.lastTickEpoch + 1; day <= epoch && hearts > 0 && !old; day++) {
		workedEpochs += 1;
		old = day >= pet.bornEpoch + LIFESPAN_EPOCHS;
		if (old) { continue; }
		const [fed, _uneaten] = pantry.nightMeals(
			hearts - hunger,
			pet.minHearts as int32,
			pet.maxHearts as int32,
		);
		hearts = fed;
		pantry = Pantry.rationOn(day, pet.bornEpoch);
	}
	const newDay = epoch > pet.lastTickEpoch;
	const alive = hearts > 0 && !old;
	const faded = Stats.fromTree(pet.tree).aged(vigorBps(epoch - pet.bornEpoch));
	const fed: Pet = {
		...pet,
		alive: alive,
		forage: faded.forage as uint16,
		might: faded.might as uint16,
		grit: faded.grit as uint16,
		hearts: hearts as uint8,
		pantry: pantry,
		foodBoughtToday: newDay ? 0 : pet.foodBoughtToday,
		harvest: pet.harvest + pending + growthBonus(pending, multiplierBps),
		rewardSnapshot: settled.rewardPerWorkPower,
		lastTickEpoch: epoch,
	};
	return Result.ok({
		pet: fed.gainXp(workXp(workPower, workedEpochs)).onFightDay(epoch),
		global: settled.withWorkPower(workPower, alive ? faded.workPower() : 0),
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
	const [perMate, burned] = deathSplit(wallet, livingMates);
	return Result.ok({
		pet: { ...pet, harvest: 0, burrow: 0 },
		global: { ...global, burned: global.burned + burned },
		perMate: perMate,
	});
}

export function heirOf(
	this dead: Pet,
	epoch: uint64,
	global: GlobalConfig,
): Result<PetAndGlobal, HeirError> {
	if (dead.alive) { return Result.err(HeirError.Alive); }
	const hatched = Pet.born(dead.blockId, dead.blockSlot(), dead.startRegion(), epoch, global);
	const generation = (dead.lineageGeneration as int32) + 1;
	const points = (hatched.pet.pointsUnspent as int32) + Math.min(generation, HEIR_POINTS_CAP);
	return Result.ok({
		pet: {
			...hatched.pet,
			burrow: dead.burrow,
			pointsUnspent: points as uint8,
			lineageGeneration: generation as uint16,
		},
		global: hatched.global,
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
	assert worker.global.totalWorkPower == 34;
	assert worker.global.rewardEpoch == 4;
	assert worker.pet.rewardSnapshot == worker.global.rewardPerWorkPower;
}

test "the first tick pays the emission share and levels on work xp" {
	const first = hatch(Region.Worker, 0, GlobalConfig.genesis(0));
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

test "hunger is a share of max hearts that might and forage raise and grit lowers" {
	const pet: Stats = { ...Stats.base(), maxHearts: 40 };
	const mighty: Stats = { ...pet, might: BASE_STAT + 100 };
	const forager: Stats = { ...pet, forage: BASE_STAT + 100 };
	const gritty: Stats = { ...pet, grit: BASE_STAT + 100 };
	const stone: Stats = { ...pet, grit: BASE_STAT + 400 };
	const tiny: Stats = { ...pet, maxHearts: 1 };
	assert pet.hungerPerDay() == 4;
	assert mighty.hungerPerDay() == 6;
	assert forager.hungerPerDay() == 5;
	assert gritty.hungerPerDay() == 2;
	assert stone.appetiteBps() == MIN_APPETITE_BPS;
	assert tiny.hungerPerDay() == 1;
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
	assert fed.global.burned == newborn.global.burned;
	const unfed = fed.pet.tickedTo(fed.global, 12);
	assert unfed.pet.hearts == 8;
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
		assert burial.value.global.burned == 1001 - 166 * 3;
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
	assert prime.pet.forage == 80;
	const fading = prime.pet.fedDailyTo(prime.global, DECLINE_KNEE_EPOCHS);
	assert fading.pet.alive;
	assert fading.pet.forage == 71;
	assert fading.global.totalWorkPower == Stats.fromTree(fading.pet.tree).aged(KNEE_VIGOR_BPS).workPower();
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
