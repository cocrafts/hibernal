import { OwnerItem, REFUSAL_BONDING } from "../../rules/owner";
import { Insurance } from "../../rules/layout";
import { GamePet, PetLife, noGamePet, OWNER_ACTION_ITEM_MAX } from "../host/host";

export const SHOP_GOODS: int32 = 4;
export const CART_GOODS: int32 = 3;
// The SKR mint has 6 decimals; prices are whole SKR (program/shop.ms).
export const SKR_UNIT: uint64 = 1000000;
const FOOD_PRICE_SKR: int32[] = [1, 2, 3];
const GROWTH_PRICE_SKR_PER_STEP: int32 = 2;
const INSURANCE_PRICE_SKR: int32 = 20;
const SKIN_PRICE_SKR: int32 = 5;
export const NOT_IN_CART: int32 = -1;
export const NO_GOOD: int32 = -1;

// The cell order on the shop strip, and the program's ShopItem order (program/layout.ms).
export enum ShopGood {
	Food,
	Growth,
	Insurance,
	Skin,
}

// What sits in owner slot 5 or 6, as the shop sells it.
export struct OwnedGood {
	good: ShopGood;
	tier: int32;
}

export enum NoOwnedGood {
	Empty,
}

export function ownedGood(item: OwnerItem): Result<OwnedGood, NoOwnedGood> {
	return match (item) {
		OwnerItem.None => Result.err(NoOwnedGood.Empty),
		OwnerItem.SmallFood => Result.ok({ good: ShopGood.Food, tier: 0 }),
		OwnerItem.MediumFood => Result.ok({ good: ShopGood.Food, tier: 1 }),
		OwnerItem.LargeFood => Result.ok({ good: ShopGood.Food, tier: 2 }),
		OwnerItem.SmallGrowth => Result.ok({ good: ShopGood.Growth, tier: 0 }),
		OwnerItem.MediumGrowth => Result.ok({ good: ShopGood.Growth, tier: 1 }),
		OwnerItem.LargeGrowth => Result.ok({ good: ShopGood.Growth, tier: 2 }),
		OwnerItem.Insurance => Result.ok({ good: ShopGood.Insurance, tier: 0 }),
	};
}

export struct CartGood {
	good: ShopGood;
	tier: int32;
}

// Why a good cannot go into the cart. A sulking Pet is a warning, not a lock: its items wait.
export enum ShopLock {
	PetLost,
	ComingSoon,
	CartFull,
	InsuranceUsed,
	InsuranceBought,
	NoFreeSlot,
	NotEnoughSkr,
}

export function goodPrice(good: CartGood): int32 {
	return match (good.good) {
		ShopGood.Food => FOOD_PRICE_SKR[good.tier],
		ShopGood.Growth => GROWTH_PRICE_SKR_PER_STEP * (good.tier + 1),
		ShopGood.Insurance => INSURANCE_PRICE_SKR,
		ShopGood.Skin => SKIN_PRICE_SKR,
	};
}

export function cartPrice(cart: CartGood[]): int32 {
	let total: int32 = 0;
	for (const good of cart) { total += goodPrice(good); }
	return total;
}

// Insurance arms at once on a Pet without one; on an armed Pet it waits in slot 5 or 6 for the heir.
function takesSlot(pet: GamePet, good: ShopGood): boolean {
	return match (good) {
		ShopGood.Food => true,
		ShopGood.Growth => true,
		ShopGood.Insurance => pet.insurance != Insurance.None,
		ShopGood.Skin => false,
	};
}

function emptySlots(pet: GamePet): int32 {
	return (pet.ownerFirst == OwnerItem.None ? 1 : 0) + (pet.ownerSecond == OwnerItem.None ? 1 : 0);
}

export function freeSlots(pet: GamePet, cart: CartGood[]): int32 {
	let taken: int32 = pet.itemsInTransit;
	for (const good of cart) { if (takesSlot(pet, good.good)) { taken += 1; } }
	return Math.max(emptySlots(pet) - taken, 0);
}

function insuranceBought(pet: GamePet, cart: CartGood[]): boolean {
	if (pet.ownerFirst == OwnerItem.Insurance || pet.ownerSecond == OwnerItem.Insurance) { return true; }
	for (const good of cart) { if (good.good == ShopGood.Insurance) { return true; } }
	return false;
}

export function shopLock(pet: GamePet, cart: CartGood[], candidate: CartGood): Result<CartGood, ShopLock> {
	if (pet.life == PetLife.DeathRecorded || pet.life == PetLife.InactiveWithoutDeathRecord) {
		return Result.err(ShopLock.PetLost);
	}
	if (candidate.good == ShopGood.Skin) { return Result.err(ShopLock.ComingSoon); }
	if ((cart.length as int32) >= CART_GOODS) { return Result.err(ShopLock.CartFull); }
	if (candidate.good == ShopGood.Insurance) {
		if (pet.insurance == Insurance.Used) { return Result.err(ShopLock.InsuranceUsed); }
		if (insuranceBought(pet, cart)) { return Result.err(ShopLock.InsuranceBought); }
	}
	if (takesSlot(pet, candidate.good) && freeSlots(pet, cart) == 0) { return Result.err(ShopLock.NoFreeSlot); }
	const total: uint64 = (cartPrice(cart) + goodPrice(candidate)) as uint64;
	if (total * SKR_UNIT > pet.skrBalance) { return Result.err(ShopLock.NotEnoughSkr); }
	return Result.ok(candidate);
}

export function sulking(pet: GamePet): boolean {
	return pet.bonding < REFUSAL_BONDING;
}

// OwnerShop.cart in the Kotlin shell: 4 bits per good, good * 3 + tier + 1, in cart order.
export function packedCart(cart: CartGood[]): int32 {
	let code: int32 = 0;
	let shift: int32 = 0;
	for (const good of cart) {
		code = code | (((good.good as int32) * 3 + good.tier + 1) << shift);
		shift += 4;
	}
	return code;
}

// The tier-per-good cart of the current shop strip, in the packed form.
export function cartCode(cart: int32[]): int32 {
	const goods: CartGood[] = [];
	for (let good: int32 = 0; good < SHOP_GOODS; good += 1) {
		if (cart[good] != NOT_IN_CART) { goods.push({ good: good as ShopGood, tier: cart[good] }); }
	}
	return packedCart(goods);
}

test "an owner slot item is the shop good and tier it was bought as" {
	assert !ownedGood(OwnerItem.None).ok;
	const growth = ownedGood(OwnerItem.MediumGrowth);
	assert growth.ok && growth.value.good == ShopGood.Growth && growth.value.tier == 1;
	const insurance = ownedGood(OwnerItem.Insurance);
	assert insurance.ok && insurance.value.good == ShopGood.Insurance;
}

test "the packed cart keeps each good and tier in order, duplicates included" {
	assert packedCart([]) == 0;
	const food: CartGood = { good: ShopGood.Food, tier: 0 };
	assert packedCart([food, food, { good: ShopGood.Insurance, tier: 0 }]) == (1 | (1 << 4) | (7 << 8));
	assert cartCode([2, NOT_IN_CART, 0, NOT_IN_CART]) == (3 | (7 << 4));
	const lastGood: CartGood = { good: ShopGood.Skin, tier: 2 };
	assert packedCart([lastGood, lastGood, lastGood]) <= OWNER_ACTION_ITEM_MAX;
}

function lockedBy(result: Result<CartGood, ShopLock>, lock: ShopLock): boolean {
	if (result.ok) { return false; }
	return result.error == lock;
}

function shopper(): GamePet {
	return { ...noGamePet(), life: PetLife.FirstLifeActive, skrBalance: 25 * SKR_UNIT };
}

test "slot goods stop at the free owner slots, in transit included" {
	const food: CartGood = { good: ShopGood.Food, tier: 0 };
	const pet = shopper();
	assert shopLock(pet, [food], food).ok;
	assert !shopLock(pet, [food, food], food).ok;
	const busy: GamePet = { ...pet, ownerFirst: OwnerItem.SmallFood, itemsInTransit: 1 };
	assert lockedBy(shopLock(busy, [], food), ShopLock.NoFreeSlot);
	assert shopLock(busy, [], { good: ShopGood.Insurance, tier: 0 }).ok;
}

test "insurance once per life, skins coming soon, lost pets and short balances locked" {
	const insurance: CartGood = { good: ShopGood.Insurance, tier: 0 };
	const pet = shopper();
	assert lockedBy(shopLock({ ...pet, insurance: Insurance.Used }, [], insurance), ShopLock.InsuranceUsed);
	assert lockedBy(shopLock(pet, [insurance], insurance), ShopLock.InsuranceBought);
	assert lockedBy(shopLock(pet, [], { good: ShopGood.Skin, tier: 0 }), ShopLock.ComingSoon);
	assert lockedBy(shopLock({ ...pet, life: PetLife.DeathRecorded }, [], insurance), ShopLock.PetLost);
	assert shopLock(pet, [insurance], { good: ShopGood.Food, tier: 2 }).ok;
	assert lockedBy(shopLock(pet, [insurance], { good: ShopGood.Growth, tier: 2 }), ShopLock.NotEnoughSkr);
	assert sulking({ ...pet, bonding: -41 }) && !sulking({ ...pet, bonding: -40 });
}
