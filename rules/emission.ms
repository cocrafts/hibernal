import * as arithmetic from "./arithmetic";
import { EPOCH_SECONDS, HBRN_UNIT, BPS } from "./units";

export const NEWBORN_EPOCHS: uint64 = 3;
export const GROWTH_CAP_BPS: int32 = 12000;
export const REWARD_SCALE: uint64 = 100000;
export const EMISSION_CAP: uint64 = 21000000 * HBRN_UNIT;
export const EMISSION_START: uint64 = 11666667 * HBRN_UNIT / 100;
export const EMISSION_HALVING_EPOCHS: uint64 = 90;
export const TREASURY_RELEASE_BPS: uint64 = 100;

export const SPEND_TREASURY_PERCENT: uint64 = 40;
export const STAKE_TREASURY_PERCENT: uint64 = 5;
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
	treasury: uint64;
}

export struct Settlement {
	rewardPerWorkPower: uint64;
	emitted: uint64;
	treasury: uint64;
}

export function epochOf(now: uint64, genesis: uint64): uint64 {
	return now < genesis ? 0 : (now - genesis) / EPOCH_SECONDS;
}

export function emissionFor(epoch: uint64): uint64 {
	const halvings = epoch / EMISSION_HALVING_EPOCHS;
	return halvings >= 64 ? 0 : EMISSION_START >> halvings;
}

export function allocatedFor(epoch: uint64, emitted: uint64): uint64 {
	const room = emitted >= EMISSION_CAP ? 0 : EMISSION_CAP - emitted;
	return Math.min(emissionFor(epoch), room);
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
	paidWorkPower: uint64,
	rewardDenominator: uint64,
	recycled: uint64,
	emitted: uint64,
	treasury: uint64,
): Settlement {
	let accrued = rewardPerWorkPower;
	let allocated = emitted;
	let held = treasury;
	let extra = recycled;
	for (let epoch = rewardEpoch + 1; epoch <= currentEpoch; epoch++) {
		const fresh = allocatedFor(epoch - 1, allocated);
		const released = held * TREASURY_RELEASE_BPS / (BPS as uint64);
		const amount = fresh + extra + released;
		const raised = accrueReward(accrued, rewardDenominator, amount);
		const paid = (raised - accrued) * paidWorkPower / REWARD_SCALE;
		held = held - released + amount - paid;
		accrued = raised;
		allocated = allocated + fresh;
		extra = 0;
	}
	return { rewardPerWorkPower: accrued, emitted: allocated, treasury: held };
}

export function pendingReward(
	workPower: uint64,
	rewardPerWorkPower: uint64,
	rewardSnapshot: uint64,
): uint64 {
	if (rewardPerWorkPower <= rewardSnapshot) { return 0; }
	return workPower * (rewardPerWorkPower - rewardSnapshot) / REWARD_SCALE;
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
	const treasury = amount * SPEND_TREASURY_PERCENT / 100;
	return { recycled: amount - treasury, treasury: treasury };
}

export function stakeSplit(amount: uint64): [uint64, uint64] {
	const treasury = amount * STAKE_TREASURY_PERCENT / 100;
	return [amount - treasury, treasury];
}

export function deathSplit(wallet: uint64, livingMates: int32): [uint64, uint64] {
	if (livingMates <= 0) { return [0, wallet]; }
	const perMate = wallet / 2 / (livingMates as uint64);
	return [perMate, wallet - perMate * (livingMates as uint64)];
}

test "emission halves every 90 epochs and stops at the cap" {
	assert emissionFor(0) == EMISSION_START;
	assert emissionFor(89) == EMISSION_START;
	assert emissionFor(90) == EMISSION_START / 2;
	assert emissionFor(180) == EMISSION_START / 4;
	assert emissionFor(100000) == 0;
	assert allocatedFor(0, EMISSION_CAP - 5) == 5;
	assert allocatedFor(0, EMISSION_CAP) == 0;
	const lifetime = settleGlobal(0, 0, EMISSION_HALVING_EPOCHS * 64, 100, 100, 0, 0, 0);
	assert lifetime.emitted == EMISSION_CAP;
	const firstWinter = settleGlobal(0, 0, EMISSION_HALVING_EPOCHS + 1, 100, 100, 0, 0, 0);
	assert firstWinter.emitted == EMISSION_START * EMISSION_HALVING_EPOCHS + EMISSION_START / 2;
}

test "reward accumulator pays each pet its share exactly once" {
	const smallWorkPower: uint64 = 25;
	const largeWorkPower: uint64 = 75;
	const paidWorkPower = smallWorkPower + largeWorkPower;
	const afterOneEpoch = settleGlobal(0, 0, 1, paidWorkPower, paidWorkPower, 0, 0, 0);
	const smallPay = pendingReward(smallWorkPower, afterOneEpoch.rewardPerWorkPower, 0);
	const largePay = pendingReward(largeWorkPower, afterOneEpoch.rewardPerWorkPower, 0);
	assert afterOneEpoch.emitted == EMISSION_START;
	assert smallPay + largePay + afterOneEpoch.treasury == EMISSION_START;
	assert afterOneEpoch.treasury < 100;
	assert largePay == smallPay * 3;
	assert pendingReward(smallWorkPower, afterOneEpoch.rewardPerWorkPower, afterOneEpoch.rewardPerWorkPower) == 0;
}

test "the share of empty floor slots is left unpaid for the treasury" {
	const paidWorkPower: uint64 = 100;
	const settled = settleGlobal(0, 0, 1, paidWorkPower, paidWorkPower * 4, 0, 0, 0);
	const paid = pendingReward(paidWorkPower, settled.rewardPerWorkPower, 0);
	assert paid + settled.treasury == EMISSION_START;
	assert settled.treasury >= EMISSION_START / 4 * 3;
}

test "the treasury releases a hundredth of its balance into each settled day" {
	const balance: uint64 = 1000000 * HBRN_UNIT;
	const settled = settleGlobal(0, 0, 1, 100, 100, 0, EMISSION_CAP, balance);
	const released = balance * TREASURY_RELEASE_BPS / 10000;
	assert released == 10000 * HBRN_UNIT;
	const paid = pendingReward(100, settled.rewardPerWorkPower, 0);
	assert settled.emitted == EMISSION_CAP;
	assert paid + settled.treasury == balance;
	assert paid + 100 >= released;
	const kept = settleGlobal(0, 0, 1, 100, 400, 0, EMISSION_CAP, balance);
	assert kept.treasury > settled.treasury;
}

test "recycled pot lands in the next settled epoch only" {
	const withoutRecycled = settleGlobal(0, 0, 3, 100, 100, 0, 0, 0);
	const withRecycled = settleGlobal(0, 0, 3, 100, 100, 1000 * HBRN_UNIT, 0, 0);
	const raised = withRecycled.rewardPerWorkPower - withoutRecycled.rewardPerWorkPower;
	assert raised == 1000 * HBRN_UNIT * REWARD_SCALE / 100;
	assert withRecycled.emitted == withoutRecycled.emitted;
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
	assert spend.recycled + spend.treasury == 1001;
	assert spend.treasury == 400;
	const [winner, fee] = stakeSplit(999);
	assert winner + fee == 999;
	const [perMate, unshared] = deathSplit(1000, 3);
	assert perMate == 166;
	assert perMate * 3 + unshared == 1000;
	const [toMates, allUnshared] = deathSplit(1000, 0);
	assert toMates == 0 && allUnshared == 1000;
}
