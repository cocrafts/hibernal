import { BPS, HBRN_UNIT } from "./units";
import { BlockSlot, Pet, GlobalConfig, Insurance } from "./layout";
import { Food, GROWTH_CAP_BPS, foodCost, foodHearts } from "./emission";
import { Pantry, mealHearts } from "./pantry";
import { Tree } from "./tree";
import { TalentKind } from "./talent";

export const BONDING_MAX: int32 = 127;
export const BONDING_DECAY: int32 = 2;
export const TALK_BONDING: int32 = 3;
export const TALKS_PER_DAY: int32 = 2;
export const FEED_BONDING: int32 = 6;
export const PURCHASE_BONDING: int32 = 15;
export const OWNER_FOOD_PER_DAY: int32 = 1;
export const REFUSAL_BONDING: int32 = -40;
export const GIFT_BONDING: int32 = 60;
export const GIFT_SHARE_BPS: int32 = 100;
export const GIFT_CAP: uint64 = 500 * HBRN_UNIT;
export const GIFT_RESERVE_DAYS: uint64 = 3;
export const GROWTH_STEP_BPS: int32 = 500;
export const GROWTH_STEPS_MAX: int32 = 3;
export const INSURANCE_REVIVE_BPS: int32 = 3000;
export const INSURANCE_BURN_PERCENT: uint64 = 50;

export enum OwnerError {
	Dead,
	Refused,
	Full,
	FedToday,
	TalkedOut,
	Insured,
	NoSuchTier,
}

export function bondedBy(this pet: Pet, amount: int32): Pet {
	const bonding = Math.max(-BONDING_MAX, Math.min((pet.bonding as int32) + amount, BONDING_MAX));
	return { ...pet, bonding: bonding as int8 };
}

export function ownerFed(this pet: Pet, food: Food): Result<Pet, OwnerError> {
	if (!pet.alive) { return Result.err(OwnerError.Dead); }
	if ((pet.bonding as int32) < REFUSAL_BONDING) { return Result.err(OwnerError.Refused); }
	if ((pet.ownerFedToday as int32) >= OWNER_FOOD_PER_DAY) { return Result.err(OwnerError.FedToday); }
	if (pet.hearts >= pet.maxHearts) { return Result.err(OwnerError.Full); }
	const restored = mealHearts(food, pet.stats().foodBps);
	const hearts = Math.min((pet.hearts as int32) + restored, pet.maxHearts as int32);
	const fed: Pet = { ...pet, hearts: hearts as uint8, ownerFedToday: pet.ownerFedToday + 1 };
	return Result.ok(fed.bondedBy(FEED_BONDING));
}

export function talkedTo(this pet: Pet): Result<Pet, OwnerError> {
	if (!pet.alive) { return Result.err(OwnerError.Dead); }
	if ((pet.talksToday as int32) >= TALKS_PER_DAY) { return Result.err(OwnerError.TalkedOut); }
	const talked: Pet = { ...pet, talksToday: pet.talksToday + 1 };
	return Result.ok(talked.bondedBy(TALK_BONDING));
}

export function grownBy(this pet: Pet, steps: int32, epoch: uint64): Result<Pet, OwnerError> {
	if (!pet.alive) { return Result.err(OwnerError.Dead); }
	if (steps < 1 || steps > GROWTH_STEPS_MAX) { return Result.err(OwnerError.NoSuchTier); }
	const active = pet.lastTickEpoch < pet.growthMultiplierExpiry;
	const current = active ? pet.growthMultiplierBps as int32 : BPS;
	const multiplier = Math.min(current + steps * GROWTH_STEP_BPS, GROWTH_CAP_BPS);
	const grown: Pet = {
		...pet,
		growthMultiplierBps: multiplier as uint16,
		growthMultiplierExpiry: epoch + 1,
	};
	return Result.ok(grown.bondedBy(PURCHASE_BONDING));
}

export function insured(this pet: Pet): Result<Pet, OwnerError> {
	if (!pet.alive) { return Result.err(OwnerError.Dead); }
	if (pet.insurance != (Insurance.None as uint8)) { return Result.err(OwnerError.Insured); }
	const armed: Pet = { ...pet, insurance: Insurance.Armed as uint8 };
	return Result.ok(armed.bondedBy(PURCHASE_BONDING));
}

export function reviveHearts(maxHearts: int32): int32 {
	return Math.max(maxHearts * INSURANCE_REVIVE_BPS / BPS, 1);
}

export function revived(this pet: Pet, global: GlobalConfig): [Pet, GlobalConfig] {
	if (pet.alive || pet.insurance != (Insurance.Armed as uint8)) { return [pet, global]; }
	const burnedHarvest = pet.harvest * INSURANCE_BURN_PERCENT / 100;
	const burnedBurrow = pet.burrow * INSURANCE_BURN_PERCENT / 100;
	const saved: Pet = {
		...pet,
		alive: true,
		hearts: reviveHearts(pet.maxHearts as int32) as uint8,
		harvest: pet.harvest - burnedHarvest,
		burrow: pet.burrow - burnedBurrow,
		insurance: Insurance.Used as uint8,
		scars: pet.scars + 1,
	};
	return [saved, { ...global, burned: global.burned + burnedHarvest + burnedBurrow }];
}

export function foodReserve(level: int32, hungerPerDay: int32): uint64 {
	const perDay = foodCost(Food.Large, level) * (hungerPerDay as uint64) / (foodHearts(Food.Large) as uint64);
	return perDay * GIFT_RESERVE_DAYS;
}

export function giftFor(this pet: Pet, reserve: uint64): uint64 {
	const bonding = pet.bonding as int32;
	if (bonding < GIFT_BONDING || pet.burrow <= reserve) { return 0; }
	const shareBps = GIFT_SHARE_BPS * (bonding - GIFT_BONDING) / (BONDING_MAX - GIFT_BONDING);
	const share = pet.burrow * (shareBps as uint64) / (BPS as uint64);
	return Math.min(Math.min(share, GIFT_CAP), pet.burrow - reserve);
}

test "bonding moves with owner care and stays inside its range" {
	const pet: Pet = { ...testPet(), bonding: 120 };
	assert pet.bondedBy(50).bonding == 127;
	assert pet.bondedBy(-400).bonding == -127;
	const talked = testPet().talkedTo();
	assert talked.ok;
	if (!talked.ok) { return; }
	assert (talked.value.bonding as int32) == TALK_BONDING;
	const twice = talked.value.talkedTo();
	assert twice.ok;
	if (!twice.ok) { return; }
	const thrice = twice.value.talkedTo();
	assert !thrice.ok;
	if (!thrice.ok) { assert thrice.error == OwnerError.TalkedOut; }
}

test "a pet takes one owner meal a day and refuses it when it resents the owner" {
	const hungry: Pet = { ...testPet(), hearts: 4, maxHearts: 20 };
	const fed = hungry.ownerFed(Food.Medium);
	assert fed.ok;
	if (!fed.ok) { return; }
	assert fed.value.hearts == 10;
	assert (fed.value.bonding as int32) == FEED_BONDING;
	const again: Pet = { ...fed.value, hearts: 4 };
	const second = again.ownerFed(Food.Small);
	assert !second.ok;
	if (!second.ok) { assert second.error == OwnerError.FedToday; }
	const resentful: Pet = { ...hungry, bonding: (REFUSAL_BONDING - 1) as int8 };
	const refused = resentful.ownerFed(Food.Small);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == OwnerError.Refused; }
}

test "growth stacks to its cap for the next day and insurance is bought once" {
	const pet = testPet();
	const once = pet.grownBy(3, 5);
	assert once.ok;
	if (!once.ok) { return; }
	assert once.value.growthMultiplierBps == 11500;
	assert once.value.growthMultiplierExpiry == 6;
	const twice = once.value.grownBy(3, 5);
	assert twice.ok;
	if (twice.ok) { assert (twice.value.growthMultiplierBps as int32) == GROWTH_CAP_BPS; }
	assert !pet.grownBy(4, 5).ok;
	const armed = pet.insured();
	assert armed.ok;
	if (!armed.ok) { return; }
	assert !armed.value.insured().ok;
}

test "insurance revives once, burns half the wallet and leaves a scar" {
	const global: GlobalConfig = {
		genesisTimestamp: 0,
		rewardPerWorkPower: 0,
		rewardEpoch: 0,
		totalWorkPower: 0,
		recycledPending: 0,
		protocolPending: 0,
		burned: 7,
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
	assert after.burned == global.burned + 200;
	const spent: Pet = { ...dying, insurance: Insurance.Used as uint8 };
	const [gone, _same] = spent.revived(global);
	assert !gone.alive;
}

test "a devoted pet gifts a capped share and keeps its food reserve" {
	const reserve = foodReserve(20, 4);
	assert reserve == foodCost(Food.Large, 20) * 4 / 10 * GIFT_RESERVE_DAYS;
	const devoted: Pet = { ...testPet(), bonding: 127, burrow: 100000 * HBRN_UNIT };
	assert devoted.giftFor(reserve) == GIFT_CAP;
	const modest: Pet = { ...devoted, burrow: 2000 * HBRN_UNIT };
	assert modest.giftFor(reserve) == 2000 * HBRN_UNIT * (GIFT_SHARE_BPS as uint64) / (BPS as uint64);
	const poor: Pet = { ...devoted, burrow: reserve };
	assert poor.giftFor(reserve) == 0;
	const cool: Pet = { ...devoted, bonding: (GIFT_BONDING - 1) as int8 };
	assert cool.giftFor(reserve) == 0;
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
		talksToday: 0,
		ownerFedToday: 0,
		giftOwed: 0,
	};
}
