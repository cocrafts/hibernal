import { BPS, HBRN_UNIT } from "./units";
import { splitmix } from "./rng";
import { TalentGrade, TalentKind } from "./talent";

export const MINT_BASE_PRICE: uint64 = 300;
export const SELL_BACK_PERCENT: uint64 = 50;
export const ITEM_WEAR_PER_DAY: int32 = 1;
export const ITEM_WEAR_MAX: int32 = 200;
export const COMMON_ITEM_UNTIL_BPS: int32 = 5500;
export const RARE_ITEM_UNTIL_BPS: int32 = 8500;
export const EPIC_ITEM_UNTIL_BPS: int32 = 9700;
export const LEGENDARY_ITEM_UNTIL_BPS: int32 = 9950;
export const SKILL_SCORE_BPS: int32 = 500;
export const ANTI_ROBBERY_CUT_BPS: int32 = 4000;
export const DAMAGE_GUARD_BPS: int32 = 4000;
export const ITEM_BONUS_PERCENT: int32 = 200;

export enum ItemSkill {
	None,
	Revive,
	AntiRobbery,
	DamageGuard,
}

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
	skill: uint8;
}

export struct Gear {
	head: Item;
	body: Item;
	hands: Item;
	feet: Item;
}

export function none(this typeof Item): Item {
	return { rarity: 0, stat: TalentKind.None as uint8, wear: 0, skill: ItemSkill.None as uint8 };
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

export function skillChanceBps(grade: TalentGrade): int32 {
	return match (grade) {
		TalentGrade.Common => 0,
		TalentGrade.Rare => 0,
		TalentGrade.Epic => 1000,
		TalentGrade.Legendary => 4000,
		TalentGrade.Mythic => 10000,
	};
}

export function rolledSkill(seed: uint64, grade: TalentGrade): ItemSkill {
	const salt: uint64 = 0x2545f4914f6cdd1d;
	const draw = splitmix(seed ^ salt);
	if (((draw % (BPS as uint64)) as int32) >= skillChanceBps(grade)) { return ItemSkill.None; }
	const pick = ((draw >> 32) % 3) as int32;
	return (pick + 1) as ItemSkill;
}

export function gradeBonusBps(grade: TalentGrade): int32 {
	const bonus = match (grade) {
		TalentGrade.Common => 200,
		TalentGrade.Rare => 400,
		TalentGrade.Epic => 700,
		TalentGrade.Legendary => 1000,
		TalentGrade.Mythic => 1300,
	};
	return bonus * ITEM_BONUS_PERCENT / 100;
}

export function minted(
	this typeof Item,
	grade: TalentGrade,
	stat: TalentKind,
	skill: ItemSkill,
): Item {
	return {
		rarity: ((grade as int32) + 1) as uint8,
		stat: stat as uint8,
		wear: 0,
		skill: skill as uint8,
	};
}

export function score(this item: Item): int32 {
	const skilled = item.skill != (ItemSkill.None as uint8);
	return item.bonusBps() + (skilled ? SKILL_SCORE_BPS : 0);
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
		if (gear.at(slot).score() < gear.at(weakest).score()) { weakest = slot; }
	}
	return weakest;
}

export enum GearError {
	Bare,
}

export function weakestItemSlot(this gear: Gear): Result<GearSlot, GearError> {
	let found = false;
	let weakest = GearSlot.Head;
	for (let ordinal = 0; ordinal <= (GearSlot.Feet as int32); ordinal++) {
		const slot = ordinal as GearSlot;
		const item = gear.at(slot);
		if (item.isEmpty()) { continue; }
		if (!found || item.score() < gear.at(weakest).score()) {
			weakest = slot;
			found = true;
		}
	}
	if (!found) { return Result.err(GearError.Bare); }
	return Result.ok(weakest);
}

export function itemCount(this gear: Gear): int32 {
	let count = 0;
	for (let ordinal = 0; ordinal <= (GearSlot.Feet as int32); ordinal++) {
		if (!gear.at(ordinal as GearSlot).isEmpty()) { count += 1; }
	}
	return count;
}

export function heirlooms(this gear: Gear, kept: int32, level: int32): [Gear, uint64] {
	let left = gear;
	let proceeds: uint64 = 0;
	for (let count = gear.itemCount(); count > kept; count--) {
		const weakest = left.weakestItemSlot();
		if (!weakest.ok) { break; }
		proceeds += left.at(weakest.value).sellPrice(level);
		left = left.with(weakest.value, Item.none());
	}
	return [left, proceeds];
}

export function resaleValue(this gear: Gear, level: int32): uint64 {
	let value: uint64 = 0;
	for (let ordinal = 0; ordinal <= (GearSlot.Feet as int32); ordinal++) {
		value += gear.at(ordinal as GearSlot).sellPrice(level);
	}
	return value;
}

export function hasSkill(this gear: Gear, skill: ItemSkill): boolean {
	for (let ordinal = 0; ordinal <= (GearSlot.Feet as int32); ordinal++) {
		if (gear.at(ordinal as GearSlot).skill == (skill as uint8)) { return true; }
	}
	return false;
}

export function spentSkill(this gear: Gear, skill: ItemSkill): Gear {
	for (let ordinal = 0; ordinal <= (GearSlot.Feet as int32); ordinal++) {
		const slot = ordinal as GearSlot;
		const item = gear.at(slot);
		if (item.skill == (skill as uint8)) {
			return gear.with(slot, { ...item, skill: ItemSkill.None as uint8 });
		}
	}
	return gear;
}

export function wardedLoot(this gear: Gear, loot: uint64): uint64 {
	if (!gear.hasSkill(ItemSkill.AntiRobbery)) { return loot; }
	return loot * ((BPS - ANTI_ROBBERY_CUT_BPS) as uint64) / (BPS as uint64);
}

export function damageGuardBps(this gear: Gear): int32 {
	return gear.hasSkill(ItemSkill.DamageGuard) ? DAMAGE_GUARD_BPS : 0;
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
	const fresh = Item.minted(TalentGrade.Epic, TalentKind.Might, ItemSkill.None);
	const epic = gradeBonusBps(TalentGrade.Epic);
	assert fresh.bonusBps() == epic;
	const half = fresh.wornBy(ITEM_WEAR_MAX / 2);
	assert half.bonusBps() == epic / 2;
	assert (fresh.wornBy(ITEM_WEAR_MAX * 5).wear as int32) == ITEM_WEAR_MAX;
	assert fresh.sellPrice(20) == mintPrice(20) / 2;
	assert half.sellPrice(20) == mintPrice(20) / 4;
	assert Item.none().bonusBps() == 0;
}

test "gear sums bonuses per stat and names its weakest slot" {
	const gear = Gear.bare()
		.with(GearSlot.Head, Item.minted(TalentGrade.Rare, TalentKind.Might, ItemSkill.None))
		.with(GearSlot.Body, Item.minted(TalentGrade.Epic, TalentKind.Might, ItemSkill.None))
		.with(GearSlot.Hands, Item.minted(TalentGrade.Common, TalentKind.Grit, ItemSkill.None));
	const might = gradeBonusBps(TalentGrade.Rare) + gradeBonusBps(TalentGrade.Epic);
	assert gear.statBonusBps(TalentKind.Might) == might;
	assert gear.statBonusBps(TalentKind.Grit) == gradeBonusBps(TalentGrade.Common);
	assert gear.statBonusBps(TalentKind.Forage) == 0;
	assert gear.weakestSlot() == GearSlot.Feet;
	const mythic = Item.minted(TalentGrade.Mythic, TalentKind.Might, ItemSkill.AntiRobbery);
	const full = gear.with(GearSlot.Feet, mythic);
	assert full.weakestSlot() == GearSlot.Hands;
	assert full.allWornBy(10).head.wear == 10;
}

test "an heir keeps the best items and the estate sells the rest back" {
	const gear = Gear.bare()
		.with(GearSlot.Head, Item.minted(TalentGrade.Rare, TalentKind.Might, ItemSkill.None))
		.with(GearSlot.Body, Item.minted(TalentGrade.Epic, TalentKind.Might, ItemSkill.None))
		.with(GearSlot.Hands, Item.minted(TalentGrade.Common, TalentKind.Grit, ItemSkill.None));
	assert gear.itemCount() == 3;
	const [kept, proceeds] = gear.heirlooms(2, 20);
	assert kept.itemCount() == 2;
	assert kept.hands.isEmpty() && !kept.body.isEmpty() && !kept.head.isEmpty();
	assert proceeds == gear.hands.sellPrice(20);
	const [same, nothing] = gear.heirlooms(4, 20);
	assert same.itemCount() == 3 && nothing == 0;
}

test "strong items may carry one skill, which wards loot or guards damage once owned" {
	let skilled = 0;
	for (let seed: uint64 = 0; seed < 1000; seed++) {
		assert rolledSkill(seed, TalentGrade.Common) == ItemSkill.None;
		assert rolledSkill(seed, TalentGrade.Mythic) != ItemSkill.None;
		if (rolledSkill(seed, TalentGrade.Legendary) != ItemSkill.None) { skilled += 1; }
	}
	assert skilled > 330 && skilled < 470;
	const ward = Item.minted(TalentGrade.Mythic, TalentKind.Grit, ItemSkill.AntiRobbery);
	const warded = Gear.bare().with(GearSlot.Feet, ward);
	assert warded.wardedLoot(1000) == 600;
	assert Gear.bare().wardedLoot(1000) == 1000;
	const guard = Item.minted(TalentGrade.Epic, TalentKind.Grit, ItemSkill.DamageGuard);
	const guarded = Gear.bare().with(GearSlot.Head, guard);
	assert guarded.damageGuardBps() == DAMAGE_GUARD_BPS;
	const charm = Item.minted(TalentGrade.Epic, TalentKind.Grit, ItemSkill.Revive);
	const reviving = Gear.bare().with(GearSlot.Body, charm);
	assert reviving.hasSkill(ItemSkill.Revive);
	assert !reviving.spentSkill(ItemSkill.Revive).hasSkill(ItemSkill.Revive);
	assert reviving.spentSkill(ItemSkill.Revive).body.rarity == reviving.body.rarity;
}
