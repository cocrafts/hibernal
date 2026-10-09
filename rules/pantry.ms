import * as arithmetic from "std/solana/arithmetic";
import { BPS } from "./units";
import { Food, foodHearts, isShielded } from "./emission";

export const FOOD_BUYS_PER_DAY: int32 = 2;
export const NEWBORN_RATION: uint8 = 1;

export struct Pantry {
	small: uint8;
	medium: uint8;
	large: uint8;
}

export enum PantryError {
	Empty,
}

export function unstocked(this typeof Pantry): Pantry {
	return { small: 0, medium: 0, large: 0 };
}

export function rationOn(this typeof Pantry, day: uint64, bornEpoch: uint64): Pantry {
	if (!isShielded(day, bornEpoch)) { return Pantry.unstocked(); }
	return { ...Pantry.unstocked(), small: NEWBORN_RATION };
}

export function portions(this pantry: Pantry, food: Food): int32 {
	return match (food) {
		Food.Small => pantry.small as int32,
		Food.Medium => pantry.medium as int32,
		Food.Large => pantry.large as int32,
	};
}

export function stored(this pantry: Pantry): int32 {
	return (pantry.small as int32) + (pantry.medium as int32) + (pantry.large as int32);
}

export function storedHearts(this pantry: Pantry): int32 {
	let hearts = 0;
	for (let ordinal = 0; ordinal <= (Food.Large as int32); ordinal++) {
		const food = ordinal as Food;
		hearts += pantry.portions(food) * foodHearts(food);
	}
	return hearts;
}

export function adding(this pantry: Pantry, food: Food, count: int32): Pantry {
	const next = (pantry.portions(food) + count) as uint8;
	return match (food) {
		Food.Small => ({ ...pantry, small: next }),
		Food.Medium => ({ ...pantry, medium: next }),
		Food.Large => ({ ...pantry, large: next }),
	};
}

export function mealHearts(food: Food, foodBps: int32): int32 {
	return foodHearts(food) * (BPS + foodBps) / BPS;
}

export function nightMeals(
	this pantry: Pantry,
	hearts: int32,
	floor: int32,
	maxHearts: int32,
	foodBps: int32,
): [int32, Pantry] {
	let fed = hearts;
	let left = pantry;
	while (fed < floor) {
		const meal = left.smallest();
		if (!meal.ok) { break; }
		fed = Math.min(fed + mealHearts(meal.value, foodBps), maxHearts);
		left = left.adding(meal.value, -1);
	}
	return [fed, left];
}

export function smallest(this pantry: Pantry): Result<Food, PantryError> {
	for (let ordinal = 0; ordinal <= (Food.Large as int32); ordinal++) {
		const food = ordinal as Food;
		if (pantry.portions(food) > 0) { return Result.ok(food); }
	}
	return Result.err(PantryError.Empty);
}

export function largest(this pantry: Pantry): Result<Food, PantryError> {
	for (let ordinal = Food.Large as int32; ordinal >= 0; ordinal--) {
		const food = ordinal as Food;
		if (pantry.portions(food) > 0) { return Result.ok(food); }
	}
	return Result.err(PantryError.Empty);
}

test "a pantry counts portions and the hearts they hold" {
	const pantry = Pantry.unstocked().adding(Food.Large, 1).adding(Food.Small, 2);
	assert pantry.stored() == 3;
	assert pantry.storedHearts() == 16;
	assert pantry.adding(Food.Small, -1).portions(Food.Small) == 1;
}

test "a pantry picks its smallest and largest portion" {
	const pantry = Pantry.unstocked().adding(Food.Medium, 1).adding(Food.Large, 1);
	const small = pantry.smallest();
	assert small.ok;
	if (small.ok) { assert small.value == Food.Medium; }
	const large = pantry.largest();
	assert large.ok;
	if (large.ok) { assert large.value == Food.Large; }
	assert !Pantry.unstocked().smallest().ok;
}

test "at night a pet under its floor eats its smallest portions until it is back over it" {
	const pantry = Pantry.unstocked().adding(Food.Small, 2).adding(Food.Large, 1);
	const [fed, left] = pantry.nightMeals(-1, 4, 20, 0);
	assert fed == 5;
	assert left.portions(Food.Small) == 0;
	assert left.portions(Food.Large) == 1;
	const [calm, kept] = pantry.nightMeals(6, 4, 20, 0);
	assert calm == 6;
	assert kept == pantry;
	const [starving, _nothing] = Pantry.unstocked().nightMeals(-2, 4, 20, 0);
	assert mealHearts(Food.Large, 2500) == 12;
	assert starving == -2;
}

test "a newborn gets a ration on each shielded day only" {
	assert Pantry.rationOn(10, 10).small == NEWBORN_RATION;
	assert Pantry.rationOn(12, 10).small == NEWBORN_RATION;
	assert Pantry.rationOn(13, 10).stored() == 0;
}
