export const NO_NEIGHBOUR: int32 = 0;

export interface PetActivity {
	day: int32;
	glyph: string;
	line: string;
	amount: int32;
	// the neighbour it involved, or NO_NEIGHBOUR
	slot: int32;
}

// Newest first.
export const STAND_IN_ACTIVITIES: PetActivity[] = [
	{ day: 0, glyph: "worked", line: "WORKED", amount: 420, slot: NO_NEIGHBOUR },
	{ day: 0, glyph: "fightLost", line: "ROBBED BY SLOT 4", amount: -310, slot: 4 },
	{ day: 0, glyph: "ate", line: "ATE A MEDIUM PORTION", amount: -315, slot: NO_NEIGHBOUR },
	{ day: 0, glyph: "levelUp", line: "LEVELLED UP - LV 11 > 12", amount: 0, slot: NO_NEIGHBOUR },
	{ day: 0, glyph: "fightWon", line: "ATTACKED SLOT 7 - WON", amount: 280, slot: 7 },
	{ day: 0, glyph: "gearBought", line: "MINTED RARE BOOTS", amount: -300, slot: NO_NEIGHBOUR },
	{ day: 0, glyph: "gift", line: "GAVE YOU A GIFT", amount: 60, slot: NO_NEIGHBOUR },
	{ day: 0, glyph: "worked", line: "WORKED THE NIGHT SHIFT", amount: 210, slot: NO_NEIGHBOUR },
	{ day: 0, glyph: "skull", line: "SLOT 2 DIED - INHERITANCE", amount: 150, slot: 2 },
	{ day: 0, glyph: "fightWon", line: "ATTACKED SLOT 10 - WON", amount: 190, slot: 10 },
	{ day: 0, glyph: "ate", line: "ATE A SMALL PORTION", amount: -120, slot: NO_NEIGHBOUR },
	{ day: 0, glyph: "gearSold", line: "SOLD COMMON GLOVES", amount: 90, slot: NO_NEIGHBOUR },
	{ day: 1, glyph: "worked", line: "WORKED", amount: 380, slot: NO_NEIGHBOUR },
	{ day: 1, glyph: "ate", line: "ATE A SMALL PORTION", amount: -120, slot: NO_NEIGHBOUR },
	{ day: 1, glyph: "fightWon", line: "ATTACKED SLOT 10 - WON", amount: 150, slot: 10 },
	{ day: 1, glyph: "skull", line: "SLOT 2 DIED - INHERITANCE", amount: 150, slot: 2 },
	{ day: 1, glyph: "gearSold", line: "SOLD COMMON GLOVES", amount: 90, slot: NO_NEIGHBOUR },
	{ day: 2, glyph: "worked", line: "WORKED", amount: 400, slot: NO_NEIGHBOUR },
	{ day: 2, glyph: "fightLost", line: "ROBBED BY SLOT 4", amount: -320, slot: 4 },
	{ day: 2, glyph: "fightLost", line: "BITTEN BY SLOT 4 - -2 HEARTS", amount: 0, slot: 4 },
	{ day: 2, glyph: "ate", line: "ATE A LARGE PORTION", amount: -500, slot: NO_NEIGHBOUR },
];
