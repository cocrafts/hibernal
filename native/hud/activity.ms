import { HBRN_UNIT } from "../../rules/units";

export const NO_NEIGHBOUR: int32 = 0;
// The stand-in rows below are in whole HBRN.
const WHOLE: int64 = HBRN_UNIT as int64;

export interface PetActivity {
	day: int32;
	glyph: string;
	line: string;
	// signed HBRN base units (HBRN_UNIT per HBRN); 0 shows no amount
	amount: int64;
	// the neighbour it involved, or NO_NEIGHBOUR
	slot: int32;
}

// Newest first.
export const STAND_IN_ACTIVITIES: PetActivity[] = [
	{ day: 0, glyph: "lock", line: "MOVED 620 TO BURROW", amount: 0, slot: NO_NEIGHBOUR },
	{ day: 0, glyph: "worked", line: "WORKED", amount: 420 * WHOLE, slot: NO_NEIGHBOUR },
	{ day: 0, glyph: "fightLost", line: "ROBBED BY SLOT 4", amount: -310 * WHOLE, slot: 4 },
	{ day: 0, glyph: "ate", line: "ATE A MEDIUM PORTION", amount: -315 * WHOLE, slot: NO_NEIGHBOUR },
	{ day: 0, glyph: "levelUp", line: "LEVELLED UP - LV 11 > 12", amount: 0, slot: NO_NEIGHBOUR },
	{ day: 0, glyph: "fightWon", line: "ATTACKED SLOT 7 - WON", amount: 280 * WHOLE, slot: 7 },
	{ day: 0, glyph: "gearBought", line: "MINTED RARE BOOTS", amount: -300 * WHOLE, slot: NO_NEIGHBOUR },
	{ day: 0, glyph: "gift", line: "GAVE YOU A GIFT", amount: 60 * WHOLE, slot: NO_NEIGHBOUR },
	{ day: 0, glyph: "worked", line: "WORKED THE NIGHT SHIFT", amount: 210 * WHOLE, slot: NO_NEIGHBOUR },
	{ day: 0, glyph: "skull", line: "SLOT 2 DIED - INHERITANCE", amount: 150 * WHOLE, slot: 2 },
	{ day: 0, glyph: "fightWon", line: "ATTACKED SLOT 10 - WON", amount: 190 * WHOLE, slot: 10 },
	{ day: 0, glyph: "ate", line: "ATE A SMALL PORTION", amount: -120 * WHOLE, slot: NO_NEIGHBOUR },
	{ day: 0, glyph: "gearSold", line: "SOLD COMMON GLOVES", amount: 90 * WHOLE, slot: NO_NEIGHBOUR },
	{ day: 1, glyph: "worked", line: "WORKED", amount: 380 * WHOLE, slot: NO_NEIGHBOUR },
	{ day: 1, glyph: "ate", line: "ATE A SMALL PORTION", amount: -120 * WHOLE, slot: NO_NEIGHBOUR },
	{ day: 1, glyph: "fightWon", line: "ATTACKED SLOT 10 - WON", amount: 150 * WHOLE, slot: 10 },
	{ day: 1, glyph: "skull", line: "SLOT 2 DIED - INHERITANCE", amount: 150 * WHOLE, slot: 2 },
	{ day: 1, glyph: "gearSold", line: "SOLD COMMON GLOVES", amount: 90 * WHOLE, slot: NO_NEIGHBOUR },
	{ day: 2, glyph: "worked", line: "WORKED", amount: 400 * WHOLE, slot: NO_NEIGHBOUR },
	{ day: 2, glyph: "fightLost", line: "ROBBED BY SLOT 4", amount: -320 * WHOLE, slot: 4 },
	{ day: 2, glyph: "fightLost", line: "BITTEN BY SLOT 4 - -2 HEARTS", amount: 0, slot: 4 },
	{ day: 2, glyph: "ate", line: "ATE A LARGE PORTION", amount: -500 * WHOLE, slot: NO_NEIGHBOUR },
];
