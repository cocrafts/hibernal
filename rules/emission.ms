import * as arithmetic from "./arithmetic";
import { EPOCH_SECONDS, HBRN_UNIT, BPS } from "./units";

export const NEWBORN_EPOCHS: uint64 = 3;
export const GROWTH_CAP_BPS: int32 = 12000;
export const REWARD_SCALE: uint64 = 100000;
export const EMISSION_START: uint64 = 100000 * HBRN_UNIT;
export const EMISSION_FLOOR: uint64 = EMISSION_START / 20;
export const EMISSION_DECAY_EPOCHS: uint64 = 90;
export const EMISSION_DECAY_NUMERATOR: uint64 = 3;
export const EMISSION_DECAY_DENOMINATOR: uint64 = 4;

export const SPEND_PROTOCOL_PERCENT: uint64 = 10;
export const SPEND_BURN_PERCENT: uint64 = 30;
export const STAKE_PROTOCOL_PERCENT: uint64 = 5;
export const SMALL_FOOD_PRICE: uint64 = 168;
export const MEDIUM_FOOD_PRICE: uint64 = 315;
export const LARGE_FOOD_PRICE: uint64 = 490;
export const FOOD_PRICE_PERCENT: uint64 = 100;

export enum Food {
	Small,
	Medium,
	Large,
}

export struct Split {
	recycled: uint64;
	burned: uint64;
	protocol: uint64;
}

export function epochOf(now: uint64, genesis: uint64): uint64 {
	return now < genesis ? 0 : (now - genesis) / EPOCH_SECONDS;
}

export function emissionFor(epoch: uint64): uint64 {
	let emission = EMISSION_START;
	let decaySteps = epoch / EMISSION_DECAY_EPOCHS;
	while (decaySteps > 0 && emission > EMISSION_FLOOR) {
		emission = emission * EMISSION_DECAY_NUMERATOR / EMISSION_DECAY_DENOMINATOR;
		decaySteps -= 1;
	}
	return Math.max(emission, EMISSION_FLOOR);
}

export function accrueReward(
	rewardPerWorkPower: uint64,
	totalWorkPower: uint64,
	amount: uint64,
): uint64 {
	if (totalWorkPower == 0) { return rewardPerWorkPower; }
	return rewardPerWorkPower + amount * REWARD_SCALE / totalWorkPower;
}

export function settleGlobal(
	rewardPerWorkPower: uint64,
	rewardEpoch: uint64,
	currentEpoch: uint64,
	totalWorkPower: uint64,
	recycled: uint64,
): uint64 {
	let accrued = rewardPerWorkPower;
	let extra = recycled;
	for (let epoch = rewardEpoch + 1; epoch <= currentEpoch; epoch++) {
		accrued = accrueReward(accrued, totalWorkPower, emissionFor(epoch) + extra);
		extra = 0;
	}
	return accrued;
}

export function pendingReward(
	workPower: uint64,
	rewardPerWorkPower: uint64,
	rewardSnapshot: uint64,
): uint64 {
	if (rewardPerWorkPower <= rewardSnapshot) { return 0; }
	return workPower * (rewardPerWorkPower - rewardSnapshot) / REWARD_SCALE;
}

export function growthBonus(pending: uint64, multiplierBps: int32): uint64 {
	const multiplier = match (multiplierBps) {
		_ when multiplierBps > GROWTH_CAP_BPS => GROWTH_CAP_BPS,
		_ when multiplierBps < BPS => BPS,
		_ => multiplierBps,
	};
	return pending * ((multiplier - BPS) as uint64) / (BPS as uint64);
}

export function foodCost(food: Food, level: int32): uint64 {
	const base: uint64 = match (food) {
		Food.Small => SMALL_FOOD_PRICE,
		Food.Medium => MEDIUM_FOOD_PRICE,
		Food.Large => LARGE_FOOD_PRICE,
	};
	const scaled = base * HBRN_UNIT * FOOD_PRICE_PERCENT / 100;
	return scaled * ((20 + level) as uint64) / 20;
}

export function foodHearts(food: Food): int32 {
	return match (food) {
		Food.Small => 3,
		Food.Medium => 6,
		Food.Large => 10,
	};
}

export function isShielded(epoch: uint64, bornEpoch: uint64): boolean {
	return epoch < bornEpoch + NEWBORN_EPOCHS;
}

export function ofSpend(this typeof Split, amount: uint64): Split {
	const protocol = amount * SPEND_PROTOCOL_PERCENT / 100;
	const burned = amount * SPEND_BURN_PERCENT / 100;
	return { recycled: amount - protocol - burned, burned: burned, protocol: protocol };
}

export function stakeSplit(amount: uint64): [uint64, uint64] {
	const protocol = amount * STAKE_PROTOCOL_PERCENT / 100;
	return [amount - protocol, protocol];
}

export function deathSplit(wallet: uint64, livingMates: int32): [uint64, uint64] {
	if (livingMates <= 0) { return [0, wallet]; }
	const perMate = wallet / 2 / (livingMates as uint64);
	return [perMate, wallet - perMate * (livingMates as uint64)];
}

test "emission decays by quarter every 90 epochs and floors" {
	assert emissionFor(0) == EMISSION_START;
	assert emissionFor(89) == EMISSION_START;
	assert emissionFor(90) == EMISSION_START * 3 / 4;
	assert emissionFor(180) == EMISSION_START * 9 / 16;
	assert emissionFor(100000) == EMISSION_FLOOR;
}

test "reward accumulator pays each pet its share exactly once" {
	const smallWorkPower: uint64 = 25;
	const largeWorkPower: uint64 = 75;
	const afterOneEpoch = settleGlobal(0, 0, 1, smallWorkPower + largeWorkPower, 0);
	const smallPay = pendingReward(smallWorkPower, afterOneEpoch, 0);
	const largePay = pendingReward(largeWorkPower, afterOneEpoch, 0);
	assert smallPay + largePay <= EMISSION_START;
	assert EMISSION_START - (smallPay + largePay) < 100;
	assert largePay == smallPay * 3;
	assert pendingReward(smallWorkPower, afterOneEpoch, afterOneEpoch) == 0;
}

test "recycled pot lands in the next settled epoch only" {
	const withoutRecycled = settleGlobal(0, 0, 3, 100, 0);
	const withRecycled = settleGlobal(0, 0, 3, 100, 1000 * HBRN_UNIT);
	assert withRecycled - withoutRecycled == 1000 * HBRN_UNIT * REWARD_SCALE / 100;
}

test "growth bonus is capped at 20 percent" {
	assert growthBonus(1000, 11000) == 100;
	assert growthBonus(1000, 15000) == 200;
	assert growthBonus(1000, 9000) == 0;
}

test "food cost curve" {
	assert foodCost(Food.Small, 0) == 168 * HBRN_UNIT;
	assert foodCost(Food.Large, 20) == 980 * HBRN_UNIT;
	assert foodHearts(Food.Small) == 3;
	assert foodHearts(Food.Medium) == 6;
	assert foodHearts(Food.Large) == 10;
}

test "splits conserve value" {
	const spend = Split.ofSpend(1001);
	assert spend.recycled + spend.burned + spend.protocol == 1001;
	assert spend.protocol == 100;
	assert spend.burned == 300;
	const [winner, fee] = stakeSplit(999);
	assert winner + fee == 999;
	const [perMate, burned] = deathSplit(1000, 3);
	assert perMate == 166;
	assert perMate * 3 + burned == 1000;
	const [toMates, allBurned] = deathSplit(1000, 0);
	assert toMates == 0 && allBurned == 1000;
}
