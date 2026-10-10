import * as arithmetic from "std/solana/arithmetic";
export const LOG2_FRACTION_BITS: int32 = 5;
export const LOG2_ONE: int32 = 32;

export function log2Times32(value: uint64): int32 {
	if (value == 0) { return 0; }
	let exponent = 0;
	let rest = value;
	for (let shift = 32; shift > 0; shift = shift >> 1) {
		if ((rest >> (shift as uint64)) != 0) {
			rest = rest >> (shift as uint64);
			exponent += shift;
		}
	}
	let mantissa = exponent >= 16
		? value >> ((exponent - 16) as uint64)
		: value << ((16 - exponent) as uint64);
	let result = exponent;
	for (let bit = 0; bit < LOG2_FRACTION_BITS; bit++) {
		mantissa = (mantissa * mantissa) >> 16;
		result = result * 2;
		if (mantissa >= 131072) {
			mantissa = mantissa >> 1;
			result += 1;
		}
	}
	return result;
}

test "log2 in thirty-seconds of an octave" {
	assert log2Times32(0) == 0;
	assert log2Times32(1) == 0;
	assert log2Times32(2) == LOG2_ONE;
	assert log2Times32(1024) == 10 * LOG2_ONE;
	assert log2Times32(3) == 50;
	assert log2Times32(1000000) == 637;
	assert log2Times32(0x8000000000000000) == 63 * LOG2_ONE;
	assert log2Times32(0xffffffffffffffff) == 64 * LOG2_ONE - 1;
}

test "log2 never decreases" {
	let last = 0;
	for (let value = 1; value < 5000; value++) {
		const current = log2Times32(value as uint64);
		assert current >= last;
		last = current;
	}
}
