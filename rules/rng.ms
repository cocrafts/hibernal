export function splitmix(state: uint64): uint64 {
	let z: uint64 = state + 11400714819323198485;
	z = (z ^ (z >> 30)) * 13787848793156543929;
	z = (z ^ (z >> 27)) * 10723151780598845931;
	return z ^ (z >> 31);
}

export function mix(a: uint64, b: uint64): uint64 {
	return splitmix(a ^ splitmix(b));
}

export function fightSeed(entropy: uint64, attackerSlot: int32, defenderSlot: int32, epoch: uint64, nonce: int32): uint64 {
	const slots: uint64 = ((attackerSlot as uint64) << 8) | (defenderSlot as uint64);
	return mix(mix(mix(entropy, slots), epoch), nonce as uint64);
}

export function pct(seed: uint64, draw: int32): int32 {
	return (splitmix(seed + (draw as uint64)) % 100) as int32;
}

export function rangeRoll(seed: uint64, draw: int32, lo: int32, hi: int32): int32 {
	const span = (hi - lo + 1) as uint64;
	return lo + ((splitmix(seed + (draw as uint64)) % span) as int32);
}

test "splitmix reference values" {
	assert splitmix(1) == 10451216379200822465;
	assert splitmix(123456789) == 2466975172287755897;
}

test "fightSeed depends on every input" {
	const base = fightSeed(7, 1, 2, 10, 0);
	assert base != fightSeed(8, 1, 2, 10, 0);
	assert base != fightSeed(7, 2, 1, 10, 0);
	assert base != fightSeed(7, 1, 2, 11, 0);
	assert base != fightSeed(7, 1, 2, 10, 1);
	assert base == fightSeed(7, 1, 2, 10, 0);
}

test "pct and rangeRoll stay in range" {
	let i = 0;
	while (i < 1000) {
		const p = pct(99, i);
		assert p >= 0 && p < 100;
		const r = rangeRoll(99, i, 80, 120);
		assert r >= 80 && r <= 120;
		i += 1;
	}
}
