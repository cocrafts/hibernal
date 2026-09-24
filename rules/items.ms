import { BPS, HBRN_UNIT } from "./units";
import { splitmix } from "./rng";
import { TalentGrade, TalentKind } from "./talent";

export const MINT_BASE_PRICE: uint64 = 600;
export const SELL_BACK_PERCENT: uint64 = 50;
export const ITEM_WEAR_PER_DAY: int32 = 1;
export const ITEM_WEAR_MAX: int32 = 100;
export const COMMON_ITEM_UNTIL_BPS: int32 = 5500;
export const RARE_ITEM_UNTIL_BPS: int32 = 8500;
export const EPIC_ITEM_UNTIL_BPS: int32 = 9700;
export const LEGENDARY_ITEM_UNTIL_BPS: int32 = 9950;

export enum GearSlot {
	Head,
	Body,
	Hands,
	Feet,
}

export struct Item {
	rarity: uint8;
	stat: uint8;
	wear: uint8;
}

export struct Gear {
	head: Item;
	body: Item;
	hands: Item;
	feet: Item;
}

export function none(this typeof Item): Item {
	return { rarity: 0, stat: TalentKind.None as uint8, wear: 0 };
}

export function bare(this typeof Gear): Gear {
	return { head: Item.none(), body: Item.none(), hands: Item.none(), feet: Item.none() };
}

export function rolledGrade(seed: uint64): TalentGrade {
	const roll = (splitmix(seed) % (BPS as uint64)) as int32;
	if (roll < COMMON_ITEM_UNTIL_BPS) { return TalentGrade.Common; }
	if (roll < RARE_ITEM_UNTIL_BPS) { return TalentGrade.Rare; }
	if (roll < EPIC_ITEM_UNTIL_BPS) { return TalentGrade.Epic; }
	if (roll < LEGENDARY_ITEM_UNTIL_BPS) { return TalentGrade.Legendary; }
	return TalentGrade.Mythic;
}

export function rolledStat(seed: uint64): TalentKind {
	const salt: uint64 = 0x9e3779b97f4a7c15;
	const pick = (splitmix(seed ^ salt) % 3) as int32;
	return (pick + 1) as TalentKind;
}

export function gradeBonusBps(grade: TalentGrade): int32 {
	return match (grade) {
		TalentGrade.Common => 200,
		TalentGrade.Rare => 400,
		TalentGrade.Epic => 700,
		TalentGrade.Legendary => 1000,
		TalentGrade.Mythic => 1300,
	};
}

export function minted(this typeof Item, grade: TalentGrade, stat: TalentKind): Item {
	return { rarity: ((grade as int32) + 1) as uint8, stat: stat as uint8, wear: 0 };
}

export function isEmpty(this item: Item): boolean {
	return item.rarity == 0;
}

export function bonusBps(this item: Item): int32 {
	if (item.isEmpty()) { return 0; }
	const grade = ((item.rarity as int32) - 1) as TalentGrade;
	return gradeBonusBps(grade) * (ITEM_WEAR_MAX - (item.wear as int32)) / ITEM_WEAR_MAX;
}

export function wornBy(this item: Item, days: int32): Item {
	if (item.isEmpty()) { return item; }
	const wear = Math.min((item.wear as int32) + days * ITEM_WEAR_PER_DAY, ITEM_WEAR_MAX);
	return { ...item, wear: wear as uint8 };
}

export function mintPrice(level: int32): uint64 {
	return MINT_BASE_PRICE * HBRN_UNIT * ((20 + level) as uint64) / 20;
}

export function sellPrice(this item: Item, level: int32): uint64 {
	if (item.isEmpty()) { return 0; }
	const left = (ITEM_WEAR_MAX - (item.wear as int32)) as uint64;
	return mintPrice(level) * SELL_BACK_PERCENT / 100 * left / (ITEM_WEAR_MAX as uint64);
}

export function at(this gear: Gear, slot: GearSlot): Item {
	return match (slot) {
		GearSlot.Head => gear.head,
		GearSlot.Body => gear.body,
		GearSlot.Hands => gear.hands,
		GearSlot.Feet => gear.feet,
	};
}

export function with(this gear: Gear, slot: GearSlot, item: Item): Gear {
	return match (slot) {
		GearSlot.Head => ({ ...gear, head: item }),
		GearSlot.Body => ({ ...gear, body: item }),
		GearSlot.Hands => ({ ...gear, hands: item }),
		GearSlot.Feet => ({ ...gear, feet: item }),
	};
}

export function statBonusBps(this gear: Gear, stat: TalentKind): int32 {
	let bonus = 0;
	for (let ordinal = 0; ordinal <= (GearSlot.Feet as int32); ordinal++) {
		const item = gear.at(ordinal as GearSlot);
		if (item.stat == (stat as uint8)) { bonus += item.bonusBps(); }
	}
	return bonus;
}

export function totalBonusBps(this gear: Gear): int32 {
	let bonus = 0;
	for (let ordinal = 0; ordinal <= (GearSlot.Feet as int32); ordinal++) {
		bonus += gear.at(ordinal as GearSlot).bonusBps();
	}
	return bonus;
}

export function weakestSlot(this gear: Gear): GearSlot {
	let weakest = GearSlot.Head;
	for (let ordinal = 1; ordinal <= (GearSlot.Feet as int32); ordinal++) {
		const slot = ordinal as GearSlot;
		if (gear.at(slot).bonusBps() < gear.at(weakest).bonusBps()) { weakest = slot; }
	}
	return weakest;
}

export function allWornBy(this gear: Gear, days: int32): Gear {
	return {
		head: gear.head.wornBy(days),
		body: gear.body.wornBy(days),
		hands: gear.hands.wornBy(days),
		feet: gear.feet.wornBy(days),
	};
}

test "items roll grades like talent, add a worn share of their bonus and sell below mint" {
	let mythic = 0;
	let common = 0;
	for (let seed: uint64 = 0; seed < 4000; seed++) {
		const grade = rolledGrade(seed);
		if (grade == TalentGrade.Mythic) { mythic += 1; }
		if (grade == TalentGrade.Common) { common += 1; }
	}
	assert common > 2000 && common < 2400;
	assert mythic < 60;
	const fresh = Item.minted(TalentGrade.Epic, TalentKind.Might);
	assert fresh.bonusBps() == 700;
	const half = fresh.wornBy(50);
	assert half.bonusBps() == 350;
	assert fresh.wornBy(500).wear == 100;
	assert fresh.sellPrice(20) == mintPrice(20) / 2;
	assert half.sellPrice(20) == mintPrice(20) / 4;
	assert Item.none().bonusBps() == 0;
}

test "gear sums bonuses per stat and names its weakest slot" {
	const gear = Gear.bare()
		.with(GearSlot.Head, Item.minted(TalentGrade.Rare, TalentKind.Might))
		.with(GearSlot.Body, Item.minted(TalentGrade.Epic, TalentKind.Might))
		.with(GearSlot.Hands, Item.minted(TalentGrade.Common, TalentKind.Grit));
	assert gear.statBonusBps(TalentKind.Might) == 1100;
	assert gear.statBonusBps(TalentKind.Grit) == 200;
	assert gear.statBonusBps(TalentKind.Forage) == 0;
	assert gear.weakestSlot() == GearSlot.Feet;
	const full = gear.with(GearSlot.Feet, Item.minted(TalentGrade.Mythic, TalentKind.Might));
	assert full.weakestSlot() == GearSlot.Hands;
	assert full.allWornBy(10).head.wear == 10;
}
