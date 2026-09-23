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
	assert pantry.storedHearts() == 5;
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

test "a newborn gets a ration on each shielded day only" {
	assert Pantry.rationOn(10, 10).small == NEWBORN_RATION;
	assert Pantry.rationOn(12, 10).small == NEWBORN_RATION;
	assert Pantry.rationOn(13, 10).stored() == 0;
}
