import {
	BPS,
	EPOCH_SECONDS,
	Food,
	Pet,
	Insurance,
	OwnerError,
	splitmix,
	mixSeeds,
	talkedTo,
	ownerFed,
	ownerBanked,
	grownBy,
	insured,
} from "../rules/index";

export const DEVOTED_PERCENT: uint64 = 25;
export const CASUAL_PERCENT: uint64 = 45;
export const INSURANCE_SKR: int32 = 20;
export const GROWTH_SKR_PER_STEP: int32 = 2;

export enum OwnerKind {
	Devoted,
	Casual,
	Absent,
}

export struct OwnerHabit {
	visitPercent: int32;
	feedBelowBps: int32;
	food: Food;
	growthPercent: int32;
	growthSteps: int32;
	insurePercent: int32;
}

export struct OwnerLedger {
	visits: int32;
	skr: int32;
	refusals: int32;
	banked: uint64;
}

export struct Visit {
	pet: Pet;
	skr: int32;
	refused: boolean;
	banked: uint64;
}

export function habitOf(kind: OwnerKind): OwnerHabit {
	return match (kind) {
		OwnerKind.Devoted => ({
			visitPercent: 90,
			feedBelowBps: 7000,
			food: Food.Large,
			growthPercent: 30,
			growthSteps: 3,
			insurePercent: 100,
		}),
		OwnerKind.Casual => ({
			visitPercent: 35,
			feedBelowBps: 5000,
			food: Food.Medium,
			growthPercent: 10,
			growthSteps: 1,
			insurePercent: 5,
		}),
		OwnerKind.Absent => ({
			visitPercent: 0,
			feedBelowBps: 0,
			food: Food.Small,
			growthPercent: 0,
			growthSteps: 1,
			insurePercent: 0,
		}),
	};
}

export function ownerKindFor(seed: uint64, index: int32): OwnerKind {
	const draw = splitmix(mixSeeds(seed, (index as uint64) + 104729)) % 100;
	if (draw < DEVOTED_PERCENT) { return OwnerKind.Devoted; }
	if (draw < DEVOTED_PERCENT + CASUAL_PERCENT) { return OwnerKind.Casual; }
	return OwnerKind.Absent;
}

export function foodSkr(food: Food): int32 {
	return match (food) {
		Food.Small => 1,
		Food.Medium => 2,
		Food.Large => 3,
	};
}

function rolled(draw: uint64, salt: uint64, percent: int32): boolean {
	return (splitmix(draw ^ salt) % 100) < (percent as uint64);
}

export function visited(this pet: Pet, habit: OwnerHabit, draw: uint64, epoch: uint64): Visit {
	let cared = pet;
	let skr = 0;
	let refused = false;
	let banked: uint64 = 0;
	const secured = cared.ownerBanked(epoch * EPOCH_SECONDS);
	if (secured.ok) {
		banked = secured.value.burrow - cared.burrow;
		cared = secured.value;
	}
	const talked = cared.talkedTo();
	if (talked.ok) { cared = talked.value; }
	const feedBelow = (cared.maxHearts as int64) * (habit.feedBelowBps as int64);
	const hungry = (cared.hearts as int64) * (BPS as int64) < feedBelow;
	if (hungry) {
		const fed = cared.ownerFed(habit.food);
		if (fed.ok) {
			cared = fed.value;
			skr += foodSkr(habit.food);
		} else if (fed.error == OwnerError.Refused) {
			refused = true;
		}
	}
	if (rolled(draw, 1, habit.growthPercent)) {
		const grown = cared.grownBy(habit.growthSteps, epoch);
		if (grown.ok) {
			cared = grown.value;
			skr += habit.growthSteps * GROWTH_SKR_PER_STEP;
		}
	}
	if (cared.insurance == (Insurance.None as uint8) && rolled(draw, 2, habit.insurePercent)) {
		const armed = cared.insured();
		if (armed.ok) {
			cared = armed.value;
			skr += INSURANCE_SKR;
		}
	}
	return { pet: cared, skr: skr, refused: refused, banked: banked };
}

export function visitDraw(seed: uint64, index: int32, epoch: uint64): uint64 {
	return mixSeeds(mixSeeds(seed, (index as uint64) + 130363), epoch);
}

export function visits(this habit: OwnerHabit, draw: uint64): boolean {
	return rolled(draw, 0, habit.visitPercent);
}

test "owner kinds split the slots and only a devoted owner visits almost daily" {
	let devoted = 0;
	let absent = 0;
	for (let index = 0; index < 1000; index++) {
		const kind = ownerKindFor(3, index);
		if (kind == OwnerKind.Devoted) { devoted += 1; }
		if (kind == OwnerKind.Absent) { absent += 1; }
	}
	assert devoted > 200 && devoted < 300;
	assert absent > 250 && absent < 350;
	let devotedVisits = 0;
	let absentVisits = 0;
	for (let epoch: uint64 = 1; epoch <= 100; epoch++) {
		if (habitOf(OwnerKind.Devoted).visits(visitDraw(3, 1, epoch))) { devotedVisits += 1; }
		if (habitOf(OwnerKind.Absent).visits(visitDraw(3, 1, epoch))) { absentVisits += 1; }
	}
	assert devotedVisits > 80;
	assert absentVisits == 0;
}
