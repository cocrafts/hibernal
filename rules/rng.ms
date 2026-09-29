import * as arithmetic from "./arithmetic";
export function splitmix(state: uint64): uint64 {
	let mixed: uint64 = state + 11400714819323198485;
	mixed = (mixed ^ (mixed >> 30)) * 13787848793156543929;
	mixed = (mixed ^ (mixed >> 27)) * 10723151780598845931;
	return mixed ^ (mixed >> 31);
}

export function mixSeeds(first: uint64, second: uint64): uint64 {
	return splitmix(first ^ splitmix(second));
}

export function fightSeed(
	entropy: uint64,
	attackerSlot: int32,
	defenderSlot: int32,
	epoch: uint64,
	nonce: int32,
): uint64 {
	const slots: uint64 = ((attackerSlot as uint64) << 8) | (defenderSlot as uint64);
	return mixSeeds(mixSeeds(mixSeeds(entropy, slots), epoch), nonce as uint64);
}

export struct Dice {
	seed: uint64;
	draw: int32;
}

export function percent(this dice: Dice, offset: int32): int32 {
	return (splitmix(dice.seed + ((dice.draw + offset) as uint64)) % 100) as int32;
}

export function roll(this dice: Dice, offset: int32, low: int32, high: int32): int32 {
	const span = (high - low + 1) as uint64;
	return low + ((splitmix(dice.seed + ((dice.draw + offset) as uint64)) % span) as int32);
}

export function advance(this dice: Dice, steps: int32): Dice {
	return { ...dice, draw: dice.draw + steps };
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

test "percent and roll stay in range" {
	for (let draw = 0; draw < 1000; draw++) {
		const dice: Dice = { seed: 99, draw: draw };
		const rolledPercent = dice.percent(0);
		assert rolledPercent >= 0 && rolledPercent < 100;
		assert dice.advance(5).percent(0) == dice.percent(5);
		const rolled = dice.roll(0, 80, 120);
		assert rolled >= 80 && rolled <= 120;
	}
}
