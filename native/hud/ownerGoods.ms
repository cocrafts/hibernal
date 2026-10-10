import { OwnerItem } from "../../rules/owner";

export const SHOP_GOODS: int32 = 4;
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

// OwnerShop.cart in the Kotlin shell: two bits per good, its tier + 1, 0 when not in the cart.
export function cartCode(cart: int32[]): int32 {
	let code: int32 = 0;
	for (let good: int32 = 0; good < SHOP_GOODS; good += 1) {
		if (cart[good] != NOT_IN_CART) { code = code | ((cart[good] + 1) << (good * 2)); }
	}
	return code;
}

test "an owner slot item is the shop good and tier it was bought as" {
	assert !ownedGood(OwnerItem.None).ok;
	const growth = ownedGood(OwnerItem.MediumGrowth);
	assert growth.ok && growth.value.good == ShopGood.Growth && growth.value.tier == 1;
	const insurance = ownedGood(OwnerItem.Insurance);
	assert insurance.ok && insurance.value.good == ShopGood.Insurance;
}

test "the cart code packs each good's tier" {
	assert cartCode([NOT_IN_CART, NOT_IN_CART, NOT_IN_CART, NOT_IN_CART]) == 0;
	assert cartCode([2, NOT_IN_CART, 0, NOT_IN_CART]) == (3 | (1 << 4));
}
