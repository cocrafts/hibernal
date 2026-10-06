import * as arithmetic from "./arithmetic";
import { ACTS_PER_EPOCH, BPS, EPOCH_SECONDS, HBRN_UNIT } from "./units";
import { BlockSlot, Pet, GlobalConfig, Insurance } from "./layout";
import { Food, GROWTH_CAP_BPS, foodCost, foodHearts } from "./emission";
import { Pantry } from "./pantry";
import { Tree } from "./tree";
import { noMods } from "./stats";
import { TalentKind } from "./talent";
import { Gear, ItemSkill, hasSkill, spentSkill } from "./items";

export const BONDING_MAX: int32 = 127;
export const BONDING_DECAY: int32 = 2;
export const ENGAGE_BONDING: int32 = 3;
export const ENGAGES_PER_DAY: int32 = 3;
export const FEED_BONDING: int32 = 6;
export const PURCHASE_BONDING: int32 = 15;
export const REFUSAL_BONDING: int32 = -40;
export const GIFT_BONDING: int32 = 60;
export const GIFT_SHARE_BPS: int32 = 500;
export const GIFT_RESERVE_DAYS: uint64 = 3;
export const GROWTH_STEP_BPS: int32 = 500;
export const GROWTH_STEPS_MAX: int32 = 3;
export const INSURANCE_REVIVE_BPS: int32 = 3000;
export const INSURANCE_TREASURY_PERCENT: uint64 = 50;
export const OWNER_BANK_PERCENT: uint64 = 50;
export const OWNER_BANK_COOLDOWN_SECONDS: uint64 = 8 * 3600;

export enum OwnerError {
	Dead,
	Refused,
	EngagedOut,
	NoSuchTier,
	EmptyHarvest,
	CoolingDown,
	SlotsFull,
	EngagedThisRound,
}

export enum OwnerItem {
	None,
	SmallFood,
	MediumFood,
	LargeFood,
	SmallGrowth,
	MediumGrowth,
	LargeGrowth,
	Insurance,
}

export struct OwnerSlots {
	first: OwnerItem;
	second: OwnerItem;
}

export struct OwnerMeal {
	food: Food;
	left: OwnerSlots;
}

export struct OwnerDose {
	steps: int32;
	left: OwnerSlots;
}

export function bondedBy(this pet: Pet, amount: int32): Pet {
	const bonding = Math.max(-BONDING_MAX, Math.min((pet.bonding as int32) + amount, BONDING_MAX));
	return { ...pet, bonding: bonding as int8 };
}

export function ownerSlots(this pet: Pet): OwnerSlots {
	return {
		first: (pet.ownerFirst as int32) as OwnerItem,
		second: (pet.ownerSecond as int32) as OwnerItem,
	};
}

export function withSlots(this pet: Pet, slots: OwnerSlots): Pet {
	return {
		...pet,
		ownerFirst: (slots.first as int32) as uint8,
		ownerSecond: (slots.second as int32) as uint8,
	};
}

export function foodItem(food: Food): OwnerItem {
	return match (food) {
		Food.Small => OwnerItem.SmallFood,
		Food.Medium => OwnerItem.MediumFood,
		Food.Large => OwnerItem.LargeFood,
	};
}

export function growthItem(steps: int32): Result<OwnerItem, OwnerError> {
	return match (steps) {
		1 => Result.ok(OwnerItem.SmallGrowth),
		2 => Result.ok(OwnerItem.MediumGrowth),
		3 => Result.ok(OwnerItem.LargeGrowth),
		_ => Result.err(OwnerError.NoSuchTier),
	};
}

function foodOf(item: OwnerItem): Result<Food, OwnerError> {
	return match (item) {
		OwnerItem.SmallFood => Result.ok(Food.Small),
		OwnerItem.MediumFood => Result.ok(Food.Medium),
		OwnerItem.LargeFood => Result.ok(Food.Large),
		_ => Result.err(OwnerError.NoSuchTier),
	};
}

function stepsOf(item: OwnerItem): int32 {
	return match (item) {
		OwnerItem.SmallGrowth => 1,
		OwnerItem.MediumGrowth => 2,
		OwnerItem.LargeGrowth => 3,
		_ => 0,
	};
}

export function withOwnerItem(this pet: Pet, item: OwnerItem): Result<Pet, OwnerError> {
	if (!pet.alive) { return Result.err(OwnerError.Dead); }
	if (item == OwnerItem.None) { return Result.err(OwnerError.NoSuchTier); }
	if ((pet.bonding as int32) < REFUSAL_BONDING) { return Result.err(OwnerError.Refused); }
	if (item == OwnerItem.Insurance && pet.insurance == (Insurance.None as uint8)) {
		return Result.ok({ ...pet, insurance: Insurance.Armed as uint8 });
	}
	const slots = pet.ownerSlots();
	if (slots.first == OwnerItem.None) {
		return Result.ok(pet.withSlots({ ...slots, first: item }));
	}
	if (slots.second == OwnerItem.None) {
		return Result.ok(pet.withSlots({ ...slots, second: item }));
	}
	return Result.err(OwnerError.SlotsFull);
}

export function withSkin(this pet: Pet, skin: uint8): Result<Pet, OwnerError> {
	if (!pet.alive) { return Result.err(OwnerError.Dead); }
	return Result.ok({ ...pet, skin: skin + 1 });
}

export function ownerMeal(this slots: OwnerSlots): Result<OwnerMeal, OwnerError> {
	const first = foodOf(slots.first);
	if (first.ok) {
		return Result.ok({ food: first.value, left: { ...slots, first: OwnerItem.None } });
	}
	const second = foodOf(slots.second);
	if (second.ok) {
		return Result.ok({ food: second.value, left: { ...slots, second: OwnerItem.None } });
	}
	return Result.err(OwnerError.NoSuchTier);
}

export function ownerDose(this slots: OwnerSlots): Result<OwnerDose, OwnerError> {
	const first = stepsOf(slots.first);
	if (first > 0) {
		return Result.ok({ steps: first, left: { ...slots, first: OwnerItem.None } });
	}
	const second = stepsOf(slots.second);
	if (second > 0) {
		return Result.ok({ steps: second, left: { ...slots, second: OwnerItem.None } });
	}
	return Result.err(OwnerError.NoSuchTier);
}

export function ownerCover(this slots: OwnerSlots): Result<OwnerSlots, OwnerError> {
	if (slots.first == OwnerItem.Insurance) { return Result.ok({ ...slots, first: OwnerItem.None }); }
	if (slots.second == OwnerItem.Insurance) { return Result.ok({ ...slots, second: OwnerItem.None }); }
	return Result.err(OwnerError.NoSuchTier);
}

export function growthBpsFor(steps: int32): int32 {
	return Math.min(BPS + steps * GROWTH_STEP_BPS, GROWTH_CAP_BPS);
}

export function ownerBanked(this pet: Pet, now: uint64): Result<Pet, OwnerError> {
	if (!pet.alive) { return Result.err(OwnerError.Dead); }
	if (pet.harvest == 0) { return Result.err(OwnerError.EmptyHarvest); }
	if (now < pet.ownerBankedAt + OWNER_BANK_COOLDOWN_SECONDS) {
		return Result.err(OwnerError.CoolingDown);
	}
	const moved = pet.harvest * OWNER_BANK_PERCENT / 100;
	return Result.ok({
		...pet,
		harvest: pet.harvest - moved,
		burrow: pet.burrow + moved,
		ownerBankedAt: now,
	});
}

export function roundOfDay(now: uint64): uint8 {
	return ((now % EPOCH_SECONDS) / (EPOCH_SECONDS / (ACTS_PER_EPOCH as uint64))) as uint8;
}

export function engagedAt(this pet: Pet, now: uint64): Result<Pet, OwnerError> {
	if (!pet.alive) { return Result.err(OwnerError.Dead); }
	if ((pet.engagedToday as int32) >= ENGAGES_PER_DAY) { return Result.err(OwnerError.EngagedOut); }
	const round = roundOfDay(now);
	if (pet.engagedToday > 0 && round <= pet.engagedRound) { return Result.err(OwnerError.EngagedThisRound); }
	const engaged: Pet = { ...pet, engagedToday: pet.engagedToday + 1, engagedRound: round };
	return Result.ok(engaged.bondedBy(ENGAGE_BONDING));
}


export function reviveHearts(maxHearts: int32): int32 {
	return Math.max(maxHearts * INSURANCE_REVIVE_BPS / BPS, 1);
}

export function revived(this pet: Pet, global: GlobalConfig): [Pet, GlobalConfig] {
	if (pet.alive) { return [pet, global]; }
	if (pet.gear.hasSkill(ItemSkill.Revive)) {
		const spared: Pet = {
			...pet,
			alive: true,
			hearts: reviveHearts(pet.maxHearts as int32) as uint8,
			gear: pet.gear.spentSkill(ItemSkill.Revive),
		};
		return [spared, global];
	}
	if (pet.insurance != (Insurance.Armed as uint8)) { return [pet, global]; }
	const takenHarvest = pet.harvest * INSURANCE_TREASURY_PERCENT / 100;
	const takenBurrow = pet.burrow * INSURANCE_TREASURY_PERCENT / 100;
	const saved: Pet = {
		...pet,
		alive: true,
		hearts: reviveHearts(pet.maxHearts as int32) as uint8,
		harvest: pet.harvest - takenHarvest,
		burrow: pet.burrow - takenBurrow,
		insurance: Insurance.Used as uint8,
		scars: pet.scars + 1,
	};
	return [saved, { ...global, treasury: global.treasury + takenHarvest + takenBurrow }];
}

export function foodReserve(level: int32, hungerPerDay: int32): uint64 {
	const largeHearts = foodHearts(Food.Large) as uint64;
	const perDay = foodCost(Food.Large, level) * (hungerPerDay as uint64) / largeHearts;
	return perDay * GIFT_RESERVE_DAYS;
}

export function giftFor(this pet: Pet, reserve: uint64, income: uint64): uint64 {
	const bonding = pet.bonding as int32;
	if (bonding < GIFT_BONDING || pet.burrow <= reserve) { return 0; }
	const shareBps = GIFT_SHARE_BPS * (bonding - GIFT_BONDING) / (BONDING_MAX - GIFT_BONDING);
	const share = income * (shareBps as uint64) / (BPS as uint64);
	return Math.min(share, pet.burrow - reserve);
}

test "bonding moves with owner care and stays inside its range" {
	const pet: Pet = { ...testPet(), bonding: 120 };
	assert pet.bondedBy(50).bonding == 127;
	assert pet.bondedBy(-400).bonding == -127;
}

test "an owner engages once a round, three times a day at most" {
	const round = EPOCH_SECONDS / (ACTS_PER_EPOCH as uint64);
	const day: uint64 = 7 * EPOCH_SECONDS;
	const first = testPet().engagedAt(day + 10);
	assert first.ok;
	if (!first.ok) { return; }
	assert (first.value.bonding as int32) == ENGAGE_BONDING;
	const sameRound = first.value.engagedAt(day + round - 1);
	assert !sameRound.ok;
	if (!sameRound.ok) { assert sameRound.error == OwnerError.EngagedThisRound; }
	const second = first.value.engagedAt(day + 2 * round);
	assert second.ok;
	if (!second.ok) { return; }
	const earlier = second.value.engagedAt(day + round);
	assert !earlier.ok;
	const third = second.value.engagedAt(day + 3 * round);
	assert third.ok;
	if (!third.ok) { return; }
	assert (third.value.bonding as int32) == 3 * ENGAGE_BONDING;
	assert third.value.engagedToday == 3;
	const fourth = third.value.engagedAt(day + EPOCH_SECONDS);
	assert !fourth.ok;
	if (!fourth.ok) { assert fourth.error == OwnerError.EngagedOut; }
	const deadPet: Pet = { ...testPet(), alive: false };
	const dead = deadPet.engagedAt(day);
	assert !dead.ok;
	if (!dead.ok) { assert dead.error == OwnerError.Dead; }
}

test "owner items fill two slots, insurance arms at once, a resentful pet refuses" {
	const pet = testPet();
	const fed = pet.withOwnerItem(foodItem(Food.Medium));
	assert fed.ok;
	if (!fed.ok) { return; }
	assert fed.value.ownerSlots().first == OwnerItem.MediumFood;
	const dose = growthItem(2);
	assert dose.ok;
	if (!dose.ok) { return; }
	const both = fed.value.withOwnerItem(dose.value);
	assert both.ok;
	if (!both.ok) { return; }
	assert both.value.ownerSlots().second == OwnerItem.MediumGrowth;
	const full = both.value.withOwnerItem(foodItem(Food.Small));
	assert !full.ok;
	if (!full.ok) { assert full.error == OwnerError.SlotsFull; }
	const covered = both.value.withOwnerItem(OwnerItem.Insurance);
	assert covered.ok;
	if (!covered.ok) { return; }
	assert covered.value.insurance == (Insurance.Armed as uint8);
	assert covered.value.ownerSlots() == both.value.ownerSlots();
	const again = covered.value.withOwnerItem(OwnerItem.Insurance);
	assert !again.ok;
	if (!again.ok) { assert again.error == OwnerError.SlotsFull; }
	const resentful: Pet = { ...pet, bonding: (REFUSAL_BONDING - 1) as int8 };
	const refused = resentful.withOwnerItem(foodItem(Food.Small));
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == OwnerError.Refused; }
	assert !growthItem(4).ok;
	const dead: Pet = { ...pet, alive: false };
	assert !dead.withOwnerItem(foodItem(Food.Small)).ok;
	const skinned = pet.withSkin(1);
	assert skinned.ok && skinned.value.skin == 2;
}

test "insurance revives once, sends half the wallet to the treasury and leaves a scar" {
	const global: GlobalConfig = {
		genesisTimestamp: 0,
		rewardPerWorkPower: 0,
		rewardEpoch: 0,
		totalWorkPower: 0,
		recycledPending: 0,
		treasury: 7,
		itemReserve: 0,
		emitted: 0,
		livingPets: 1,
		floorSlots: 500,
	};
	const dying: Pet = {
		...testPet(),
		alive: false,
		hearts: 0,
		maxHearts: 20,
		harvest: 100,
		burrow: 300,
		insurance: Insurance.Armed as uint8,
	};
	const [saved, after] = dying.revived(global);
	assert saved.alive;
	assert saved.hearts == 6;
	assert saved.harvest == 50 && saved.burrow == 150;
	assert saved.scars == 1;
	assert saved.insurance == (Insurance.Used as uint8);
	assert after.treasury == global.treasury + 200;
	const spent: Pet = { ...dying, insurance: Insurance.Used as uint8 };
	const [gone, _same] = spent.revived(global);
	assert !gone.alive;
}

test "a devoted pet gifts a share of the day's income and keeps its food reserve" {
	const reserve = foodReserve(20, 4);
	assert reserve == foodCost(Food.Large, 20) * 4 / 10 * GIFT_RESERVE_DAYS;
	const income = 1500 * HBRN_UNIT;
	const devoted: Pet = { ...testPet(), bonding: 127, burrow: 100000 * HBRN_UNIT };
	assert devoted.giftFor(reserve, income) == income * (GIFT_SHARE_BPS as uint64) / (BPS as uint64);
	const lean: Pet = { ...devoted, burrow: reserve + HBRN_UNIT };
	assert lean.giftFor(reserve, income) == HBRN_UNIT;
	const poor: Pet = { ...devoted, burrow: reserve };
	assert poor.giftFor(reserve, income) == 0;
	const cool: Pet = { ...devoted, bonding: (GIFT_BONDING - 1) as int8 };
	assert cool.giftFor(reserve, income) == 0;
}

test "the owner banks half the harvest once per cooldown" {
	const now: uint64 = 100 * 86400;
	const exposed: Pet = { ...testPet(), harvest: 900, burrow: 100 };
	const banked = exposed.ownerBanked(now);
	assert banked.ok;
	if (!banked.ok) { return; }
	assert banked.value.harvest == 450 && banked.value.burrow == 550;
	const refilled: Pet = { ...banked.value, harvest: 900 };
	const early = refilled.ownerBanked(now + OWNER_BANK_COOLDOWN_SECONDS - 1);
	assert !early.ok;
	if (!early.ok) { assert early.error == OwnerError.CoolingDown; }
	assert refilled.ownerBanked(now + OWNER_BANK_COOLDOWN_SECONDS).ok;
	const empty = testPet().ownerBanked(now);
	assert !empty.ok;
	if (!empty.ok) { assert empty.error == OwnerError.EmptyHarvest; }
}

function testPet(): Pet {
	return {
		blockId: 0,
		slot: 0,
		alive: true,
		region: 0,
		hearts: 10,
		maxHearts: 10,
		forage: 50,
		might: 50,
		grit: 50,
		level: 1,
		pointsUnspent: 0,
		xp: 0,
		tree: Tree.empty(),
		foodBps: 0,
		experienceBps: 0,
		lootBps: 0,
		biteGuardBps: 0,
		mods: noMods(),
		harvest: 0,
		burrow: 0,
		rewardSnapshot: 0,
		bornEpoch: 0,
		lastTickEpoch: 5,
		fightsOutToday: 0,
		fightsInToday: 0,
		bitesInToday: 0,
		slotsAttackedToday: 0 as BitSet<BlockSlot>,
		fightDay: 5,
		growthMultiplierBps: 0,
		growthMultiplierExpiry: 0,
		minHearts: 2,
		pantry: Pantry.unstocked(),
		foodBoughtToday: 0,
		talentKind: TalentKind.None as uint8,
		talentBps: BPS as uint16,
		insurance: Insurance.None as uint8,
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
}
