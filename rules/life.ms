import { Region, Stats } from "./stats";
import { Tree } from "./tree";
import { BlockSlot, Pet, GlobalConfig } from "./layout";
import {
	EMISSION_START,
	Food,
	Split,
	settleGlobal,
	pendingReward,
	growthBonus,
	foodCost,
	hungerOn,
	deathSplit,
} from "./emission";
import { NEWBORN_XP, workXp, gainXp, levelForXp } from "./level";

export const DEFAULT_MIN_HEARTS: int32 = 2;

export enum TickError {
	Dead,
	Behind,
}

export enum BurialError {
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
		insurance: 0,
		scars: 0,
		lineageGeneration: 0,
	};
	return { pet: pet, global: settled.withWorkPower(0, stats.workPower()) };
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
	const meal = foodCost(Food.Small, pet.level as int32);
	let hearts = pet.hearts as int32;
	let burrow = pet.burrow;
	let spent: uint64 = 0;
	let workedEpochs = 0;
	for (let day = pet.lastTickEpoch + 1; day <= epoch && hearts > 0; day++) {
		workedEpochs += 1;
		if (!hungerOn(day, pet.bornEpoch)) { continue; }
		if (hearts - 1 < (pet.minHearts as int32) && burrow >= meal) {
			burrow -= meal;
			spent += meal;
		} else {
			hearts -= 1;
		}
	}
	const alive = hearts > 0;
	const fed: Pet = {
		...pet,
		alive: alive,
		hearts: hearts as uint8,
		burrow: burrow,
		harvest: pet.harvest + pending + growthBonus(pending, multiplierBps),
		rewardSnapshot: settled.rewardPerWorkPower,
		lastTickEpoch: epoch,
	};
	const afterSpend = settled.withSpend(Split.ofSpend(spent));
	return Result.ok({
		pet: fed.gainXp(workXp(workPower, workedEpochs)).onFightDay(epoch),
		global: alive ? afterSpend : afterSpend.withWorkPower(workPower, 0),
	});
}

export function bury(
	this pet: Pet,
	livingMates: int32,
	global: GlobalConfig,
): Result<Burial, BurialError> {
	if (pet.alive) { return Result.err(BurialError.Alive); }
	const [perMate, burned] = deathSplit(pet.harvest + pet.burrow, livingMates);
	return Result.ok({
		pet: { ...pet, harvest: 0, burrow: 0 },
		global: { ...global, burned: global.burned + burned },
		perMate: perMate,
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

test "hunger takes hearts, the floor eats from the burrow, starvation leaves the work power" {
	const newborn = hatch(Region.Survivor, 0, GlobalConfig.genesis(0));
	const hungry: Pet = { ...newborn.pet, minHearts: 0 };
	const starved = hungry.tickedTo(newborn.global, 6);
	assert starved.pet.hearts == 0;
	assert !starved.pet.alive;
	assert starved.global.totalWorkPower == 0;
	const floored: Pet = { ...newborn.pet, burrow: 1000 * EMISSION_START };
	const fed = floored.tickedTo(newborn.global, 10);
	assert fed.pet.alive;
	assert (fed.pet.hearts as int32) == DEFAULT_MIN_HEARTS;
	assert fed.global.burned > 0;
	assert fed.global.recycledPending + fed.global.burned + fed.global.protocolPending ==
		floored.burrow - fed.pet.burrow;
}

test "newborn hunger is halved while shielded" {
	const newborn = hatch(Region.Worker, 0, GlobalConfig.genesis(0));
	const hungry: Pet = { ...newborn.pet, minHearts: 0 };
	assert hungry.tickedTo(newborn.global, 3).pet.hearts == 3;
}

test "ticks refuse the dead and the past, and a burial splits the wallet" {
	const newborn = hatch(Region.Worker, 0, GlobalConfig.genesis(0));
	const dead: Pet = { ...newborn.pet, alive: false, hearts: 0, harvest: 700, burrow: 301 };
	const refused = dead.tickTo(newborn.global, 1);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == TickError.Dead; }
	const later = newborn.pet.tickedTo(newborn.global, 5);
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
