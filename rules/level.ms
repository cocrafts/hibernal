import * as arithmetic from "std/solana/arithmetic";
import { HBRN_UNIT } from "./units";
import { Pet } from "./layout";

export const LEVEL_CAP: int32 = 20;
export const LEVEL_XP_PER_STEP: uint32 = 190;
export const NEWBORN_XP: uint32 = 190;
export const WORK_XP_PER_WORK_POWER: uint32 = 7;
export const RAID_XP_PER_HBRN: uint64 = 3;
export const RAID_XP_CAP: uint32 = 500;
export const DEFENSE_WIN_XP: uint32 = 60;
export const DEFENSE_LOSS_XP: uint32 = 20;
export const LATE_LEVEL: int32 = 10;
export const LATE_LEVEL_XP_PER_CUBE: uint32 = 7;

export function xpToReach(level: int32): uint32 {
	const steps = (Math.max(level, 1) - 1) as uint32;
	const lateLevels = Math.max(level - LATE_LEVEL, 0);
	const late = lateLevels as uint32;
	return LEVEL_XP_PER_STEP * steps +
		steps * steps * steps +
		LATE_LEVEL_XP_PER_CUBE * late * late * late;
}

export function levelForXp(xp: uint32): int32 {
	for (let next = 2; next <= LEVEL_CAP; next++) {
		if (xp < xpToReach(next)) { return next - 1; }
	}
	return LEVEL_CAP;
}

export function workXp(workPower: uint64, epochs: int32): uint32 {
	return (workPower as uint32) * WORK_XP_PER_WORK_POWER * (epochs as uint32);
}

export function raidXp(loot: uint64): uint32 {
	const earned = loot * RAID_XP_PER_HBRN / HBRN_UNIT;
	return Math.min(earned, RAID_XP_CAP as uint64) as uint32;
}

export function gainXp(this pet: Pet, amount: uint32): Pet {
	const xp = pet.xp + amount;
	const level = levelForXp(xp);
	const gained = Math.max(level - (pet.level as int32), 0);
	return {
		...pet,
		xp: xp,
		level: level as uint16,
		pointsUnspent: ((pet.pointsUnspent as int32) + gained) as uint8,
	};
}

test "xp curve matches the leveling table" {
	const farBeyondCap: uint32 = 4000000000;
	assert xpToReach(1) == 0;
	assert xpToReach(2) == 191;
	assert xpToReach(10) == 2439;
	assert xpToReach(11) == 2900 + LATE_LEVEL_XP_PER_CUBE;
	assert xpToReach(20) == 10469 + LATE_LEVEL_XP_PER_CUBE * 1000;
	assert levelForXp(0) == 1;
	assert levelForXp(NEWBORN_XP) == 1;
	assert levelForXp(191) == 2;
	assert levelForXp(2438) == 9;
	assert levelForXp(2439) == 10;
	assert levelForXp(farBeyondCap) == LEVEL_CAP;
}

test "work xp follows work power, raid xp follows loot and caps" {
	assert workXp(25, 1) == 175;
	assert workXp(34, 3) == 714;
	assert raidXp(0) == 0;
	assert raidXp(10 * HBRN_UNIT) == 30;
	assert raidXp(100000 * HBRN_UNIT) == RAID_XP_CAP;
}
