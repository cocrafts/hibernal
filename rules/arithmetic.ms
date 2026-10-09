import {
	quotient,
	remainder,
	wideQuotient,
	wideRemainder,
} from "std/solana/arithmetic";

test "the unsigned-based quotient and remainder equal signed division" {
	const values: int32[] = [0, 1, 2, 3, 7, 99, 100, 101, 9999, 10000, 65535, 2147483647, -1, -2, -3, -7, -99, -100, -101, -10000, -2147483647, -2147483648];
	for (const dividend of values) {
		for (const divisor of values) {
			if (divisor == 0 || (dividend == -2147483648 && divisor == -1)) { continue; }
			assert quotient(dividend, divisor) == dividend / divisor;
			assert remainder(dividend, divisor) == dividend % divisor;
			const wideDividend = (dividend as int64) * 1000003;
			const wideDivisor = divisor as int64;
			assert wideQuotient(wideDividend, wideDivisor) == wideDividend / wideDivisor;
			assert wideRemainder(wideDividend, wideDivisor) == wideDividend % wideDivisor;
		}
	}
	when (c) {
		const lowest: int64 = -9223372036854775807 - 1;
		assert wideQuotient(lowest, 2) == lowest / 2;
		assert wideRemainder(lowest, 3) == lowest % 3;
		const highest: int64 = 9223372036854775807;
		const seven: int64 = -7;
		assert wideQuotient(highest, seven) == highest / seven;
	}
}
