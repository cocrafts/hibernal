import { LEVEL_CAP, xpToReach } from "../../rules/level";
import { HBRN_UNIT } from "../../rules/units";

export enum HeartCountError { InvalidCount }

// Cumulative XP as progress within the level and that level's span; none past the cap.
// The live gate has already checked that the level is the rules' level for this XP.
export function levelProgress(level: int32, xp: uint32): [uint32, uint32] {
	const reached: uint32 = xpToReach(level);
	const span: uint32 = level >= LEVEL_CAP ? 0 : xpToReach(level + 1) - reached;
	return [xp - reached, span];
}

export function heartShare(hearts: int32, maxHearts: int32): Result<float32, HeartCountError> {
	if (maxHearts <= 0 || hearts < 0 || hearts > maxHearts) {
		return Result.err(HeartCountError.InvalidCount);
	}
	return Result.ok((hearts as float32) / (maxHearts as float32));
}

export function groupedAmount(amount: uint64): string {
	const digits: string = amount.toString();
	let words: string = "";
	for (let index: int32 = 0; index < digits.length; index += 1) {
		if (index > 0 && (digits.length - index) % 3 == 0) { words += ","; }
		words += digits.slice(index, index + 1);
	}
	return words;
}

// Base units as HBRN, cut (not rounded) to thousandths so a shown amount is never more than held: most
// prices and daily incomes are under one HBRN.
export function hbrnAmount(baseUnits: uint64): string {
	const whole: uint64 = baseUnits / HBRN_UNIT;
	const thousandths: uint64 = (baseUnits % HBRN_UNIT) / (HBRN_UNIT / 1000);
	if (whole == 0 && thousandths == 0 && baseUnits > 0) { return "<0.001"; }
	if (thousandths == 0) { return groupedAmount(whole); }
	const padded: string = thousandths < 10 ? "00" : thousandths < 100 ? "0" : "";
	return groupedAmount(whole) + "." + padded + thousandths.toString();
}

test "HBRN amounts read base units at six decimals" {
	assert hbrnAmount(0 as uint64) == "0";
	assert hbrnAmount(692110195 as uint64) == "692.110";
	assert hbrnAmount(1240000000 as uint64) == "1,240";
	assert hbrnAmount(1050000 as uint64) == "1.050";
	assert hbrnAmount(420000 as uint64) == "0.420";
	assert hbrnAmount(12500 as uint64) == "0.012";
	assert hbrnAmount(5000 as uint64) == "0.005";
	assert hbrnAmount(999 as uint64) == "<0.001";
	assert hbrnAmount(2179950569 as uint64) == "2,179.950";
}

test "grouped amounts preserve preview and billion-unit balances" {
	assert groupedAmount(0 as uint64) == "0";
	assert groupedAmount(999 as uint64) == "999";
	assert groupedAmount(1240 as uint64) == "1,240";
	assert groupedAmount(5600 as uint64) == "5,600";
	const observedBurrow: uint64 = 2179950569;
	assert groupedAmount(observedBurrow) == "2,179,950,569";
}

test "heart meter uses actual maximum without preview cap" {
	const observed: Result<float32, HeartCountError> = heartShare(8, 18);
	assert observed.ok;
	assert observed.value > 0.444 && observed.value < 0.445;
	const full: Result<float32, HeartCountError> = heartShare(18, 18);
	const large: Result<float32, HeartCountError> = heartShare(255, 255);
	const empty: Result<float32, HeartCountError> = heartShare(0, 18);
	assert full.ok && large.ok && empty.ok;
	assert full.value == 1.0 && large.value == 1.0 && empty.value == 0.0;
	assert !heartShare(0, 0).ok;
	assert !heartShare(-1, 18).ok;
	assert !heartShare(19, 18).ok;
	assert !heartShare(0, -1).ok;
}

test "XP decimal text preserves full uint32" {
	const signedBoundary: uint32 = 2147483648;
	const maximum: uint32 = 4294967295;
	assert signedBoundary.toString() == "2147483648";
	assert maximum.toString() == "4294967295";
}

test "grouped amounts preserve full unsigned width" {
	const signedBoundary: uint64 = 9223372036854775808;
	const maximum: uint64 = 18446744073709551615;
	assert groupedAmount(signedBoundary) == "9,223,372,036,854,775,808";
	assert groupedAmount(maximum) == "18,446,744,073,709,551,615";
}

test "cumulative XP becomes progress within the level by the rules' curve" {
	const [newborn, newbornSpan] = levelProgress(1, 190);
	assert newborn == 190 && newbornSpan == 191;
	const [second, secondSpan] = levelProgress(2, 200);
	assert second == 9 && secondSpan == xpToReach(3) - 191;
	const [capped, cappedSpan] = levelProgress(LEVEL_CAP, xpToReach(LEVEL_CAP) + 5);
	assert capped == 5 && cappedSpan == 0;
}
