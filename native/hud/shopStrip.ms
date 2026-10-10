// The SKR shop over the hotbar: four goods, the cart's total and the buttons, laid out on
// shopStrip.png (art/hud/cutItemShop.py) in that piece's pixels, scaled to the strip's width.

import { Color, rgba } from "@metascript/void/src/void2d/types";
import { BoxStyle, uniformRadii, uniformBorders } from "@metascript/void/src/void2d/boxStyle";
import { Ui, box, pressable } from "../ui/ui";
import { Kit, PieceLayer, INK, INK_BRIGHT, HOLO_BLUE, pieceSized, pieceWidth, pieceHeight, say, subId } from "./kit";
import { Food, foodHearts } from "../../rules/emission";
import { GROWTH_STEP_BPS, INSURANCE_REVIVE_BPS } from "../../rules/owner";
import { ItemCard, ItemRow, NO_ROW, percentOfBps } from "./itemCard";
import { groupedAmount } from "./gameNumbers";
import { NOT_IN_CART, NO_GOOD, SHOP_GOODS, ShopGood } from "./ownerGoods";

const STRIP_PIXELS_WIDE: float32 = 1088.0;
const STRIP_PIXELS_HIGH: float32 = 221.0;
const CELL_LEFTS: float32[] = [60.0, 180.0, 301.0, 422.0];
const CELL_WIDTH: float32 = 108.0;
const CELL_TOP: float32 = 50.0;
const CELL_ICON_BOTTOM: float32 = 150.0;
const CELL_BOTTOM: float32 = 184.0;
const PRICE_LEFT: float32 = 36.0;
const PRICE_RIGHT: float32 = 98.0;
const TOTAL_LEFT: float32 = 645.0;
const TOTAL_RIGHT: float32 = 801.0;
const TOTAL_TOP: float32 = 96.0;
const TOTAL_BOTTOM: float32 = 151.0;
const BALANCE_LEFT: float32 = 566.0;
const BALANCE_RIGHT: float32 = 820.0;
const BALANCE_Y: float32 = 46.0;
const CANCEL_LEFT: float32 = 857.0;
const CANCEL_RIGHT: float32 = 1009.0;
const CANCEL_TOP: float32 = 38.0;
const CANCEL_BOTTOM: float32 = 99.0;
const BUY_LEFT: float32 = 850.0;
const BUY_TEXT_LEFT: float32 = 910.0;
const BUY_RIGHT: float32 = 1016.0;
const BUY_TOP: float32 = 112.0;
const BUY_BOTTOM: float32 = 178.0;
const ICON_SIZE: float32 = 26.0;
const PRICE_SIZE: float32 = 6.5;
const TOTAL_SIZE: float32 = 9.0;
const BALANCE_SIZE: float32 = 5.5;
const BUTTON_SIZE: float32 = 7.0;
const IN_CART_RIM: Color = rgba(0.92, 0.96, 1.0, 0.95);
const FOCUS_RIM: Color = rgba(0.45, 0.78, 1.0, 0.7);

// program/shop.ms on main: FOOD_PRICE_SKR, GROWTH_PRICE_SKR_PER_STEP, INSURANCE_PRICE_SKR, SKIN_PRICE_SKR.
const FOOD_PRICE_SKR: int32[] = [1, 2, 3];
const GROWTH_PRICE_SKR_PER_STEP: int32 = 2;
const INSURANCE_PRICE_SKR: int32 = 20;
const SKIN_PRICE_SKR: int32 = 5;


export enum ShopStripTapKind {
	Nothing,
	Good,
	Cancel,
	Purchase,
}

export struct ShopStripTap {
	kind: ShopStripTapKind;
	good: int32;
}

export function stripHeight(width: float32): float32 {
	return width * STRIP_PIXELS_HIGH / STRIP_PIXELS_WIDE;
}

export function goodIcon(good: ShopGood): string {
	return match (good) {
		ShopGood.Food => "shopMedkit",
		ShopGood.Growth => "shopBattery",
		ShopGood.Insurance => "shopShield",
		ShopGood.Skin => "shopDrone",
	};
}

// Food and Growth come in three tiers; Insurance and Skin in one.
export function goodTiers(good: ShopGood): int32 {
	return match (good) {
		ShopGood.Food => 3,
		ShopGood.Growth => 3,
		ShopGood.Insurance => 1,
		ShopGood.Skin => 1,
	};
}

// Insurance arms at once; the rest wait in owner slot 5 or 6.
export function takesOwnerSlot(good: ShopGood): boolean {
	return good == ShopGood.Food || good == ShopGood.Growth;
}

export function goodPrice(good: ShopGood, tier: int32): int32 {
	return match (good) {
		ShopGood.Food => FOOD_PRICE_SKR[tier],
		ShopGood.Growth => GROWTH_PRICE_SKR_PER_STEP * (tier + 1),
		ShopGood.Insurance => INSURANCE_PRICE_SKR,
		ShopGood.Skin => SKIN_PRICE_SKR,
	};
}

export function cartTotal(cart: int32[]): int32 {
	let total: int32 = 0;
	for (let good: int32 = 0; good < SHOP_GOODS; good += 1) {
		if (cart[good] != NOT_IN_CART) { total += goodPrice(good as ShopGood, cart[good]); }
	}
	return total;
}

function skr(amount: int32): string {
	return groupedAmount(amount as uint64) + " SKR";
}

// The card's tag says SKR; a row has room for the number only.
function price(good: ShopGood, tier: int32): string {
	return groupedAmount(goodPrice(good, tier) as uint64);
}

const EMPTY_ROW: ItemRow = { label: "", value: "" };

function shopCard(good: ShopGood, title: string, rows: ItemRow[], notes: string[], tier: int32, owned: boolean): ItemCard {
	const tiered: boolean = goodTiers(good) > 1;
	return {
		icon: goodIcon(good),
		title: title,
		tag: owned ? "OWNED" : "SKR",
		tagColour: HOLO_BLUE,
		rows: rows,
		notes: notes,
		choosableRows: tiered && !owned ? goodTiers(good) : NO_ROW,
		chosenRow: tiered ? tier : NO_ROW,
	};
}

// A good on the card. In the shop its tier rows can be tapped; `owned` is one sitting in slot 5 or 6.
export function goodCard(good: ShopGood, tier: int32, owned: boolean): ItemCard {
	return match (good) {
		ShopGood.Food => shopCard(good, "OWNER FOOD", [
			{ label: "+" + foodHearts(Food.Small).toString() + " HEARTS", value: price(good, 0) },
			{ label: "+" + foodHearts(Food.Medium).toString() + " HEARTS", value: price(good, 1) },
			{ label: "+" + foodHearts(Food.Large).toString() + " HEARTS", value: price(good, 2) },
			EMPTY_ROW,
		], ["WAITS IN OWNER SLOT 5 OR 6", "UNTIL THE PET EATS IT."], tier, owned),
		ShopGood.Growth => shopCard(good, "GROWTH", [
			{ label: "+" + percentOfBps(GROWTH_STEP_BPS) + " FORAGE", value: price(good, 0) },
			{ label: "+" + percentOfBps(GROWTH_STEP_BPS * 2) + " FORAGE", value: price(good, 1) },
			{ label: "+" + percentOfBps(GROWTH_STEP_BPS * 3) + " FORAGE", value: price(good, 2) },
			EMPTY_ROW,
		], ["FORAGE RISES THE DAY AFTER", "THE PET TAKES IT. A NEW DOSE", "REPLACES THE LAST ONE."], tier, owned),
		ShopGood.Insurance => shopCard(good, "INSURANCE", [
			{ label: "REVIVE", value: percentOfBps(INSURANCE_REVIVE_BPS) },
			{ label: "USES", value: "1" },
			{ label: "SLOT", value: "NONE" },
			{ label: "PRICE", value: price(good, 0) },
		], ["REVIVES ONCE WITH " + percentOfBps(INSURANCE_REVIVE_BPS) + " HEARTS.", "ARMS AS SOON AS IT IS BOUGHT.",
			"ONE AT A TIME."], tier, owned),
		ShopGood.Skin => shopCard(good, "SKIN", [
			{ label: "LOOK", value: "NEW" },
			{ label: "STATS", value: "NONE" },
			{ label: "SLOT", value: "NONE" },
			{ label: "PRICE", value: price(good, 0) },
		], ["CHANGES THE PET'S LOOK.", "COSMETIC ONLY."], tier, owned),
	};
}

function rimmed(ui: Ui, x: float32, y: float32, width: float32, height: float32, radius: float32, colour: Color): void {
	const rim = BoxStyle.create(uniformRadii(radius), uniformBorders(1.2), colour);
	box(ui, x, y, width, height, radius, rgba(0.0, 0.0, 0.0, 0.0), rim);
}

// `cart` holds each good's tier, NOT_IN_CART when it is not in the cart; `focus` is the good on the card.
export function shopStrip(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, cart: int32[], focus: int32,
	balanceLabel: string): ShopStripTap {
	const scale: float32 = width / STRIP_PIXELS_WIDE;
	pieceSized(kit, subId(id, 0), PieceLayer.Frames, "shopStrip", x, y, width, stripHeight(width));
	let result: ShopStripTap = { kind: ShopStripTapKind.Nothing, good: NO_GOOD };
	for (let good: int32 = 0; good < SHOP_GOODS; good += 1) {
		const left: float32 = x + CELL_LEFTS[good] * scale;
		const top: float32 = y + CELL_TOP * scale;
		const cellWidth: float32 = CELL_WIDTH * scale;
		const iconBottom: float32 = y + CELL_ICON_BOTTOM * scale;
		const icon: string = goodIcon(good as ShopGood);
		const fit: float32 = ICON_SIZE / Math.max(pieceWidth(kit, icon), pieceHeight(kit, icon));
		const iconWidth: float32 = pieceWidth(kit, icon) * fit;
		const iconHeight: float32 = pieceHeight(kit, icon) * fit;
		pieceSized(kit, subId(id, 1 + good), PieceLayer.Icons, icon, left + (cellWidth - iconWidth) * 0.5,
			top + (iconBottom - top - iconHeight) * 0.5, iconWidth, iconHeight);
		const tier: int32 = cart[good] == NOT_IN_CART ? 0 : cart[good];
		const priceTop: float32 = iconBottom + (CELL_BOTTOM - CELL_ICON_BOTTOM) * scale * 0.5 - PRICE_SIZE * 0.6;
		say(ui, kit, subId(id, 5 + good), goodPrice(good as ShopGood, tier).toString(), left + PRICE_LEFT * scale, priceTop,
			(PRICE_RIGHT - PRICE_LEFT) * scale, PRICE_SIZE, INK_BRIGHT, 0.0);
		const cellHeight: float32 = (CELL_BOTTOM - CELL_TOP) * scale;
		if (cart[good] != NOT_IN_CART) {
			rimmed(ui, left - 1.0, top - 1.0, cellWidth + 2.0, cellHeight + 2.0, 3.0, IN_CART_RIM);
		} else if (good == focus) {
			rimmed(ui, left - 1.0, top - 1.0, cellWidth + 2.0, cellHeight + 2.0, 3.0, FOCUS_RIM);
		}
		if (pressable(ui, subId(id, 9 + good), left, top, cellWidth, cellHeight)) {
			result = { kind: ShopStripTapKind.Good, good: good };
		}
	}
	say(ui, kit, subId(id, 13), balanceLabel, x + BALANCE_LEFT * scale, y + BALANCE_Y * scale,
		(BALANCE_RIGHT - BALANCE_LEFT) * scale, BALANCE_SIZE, INK, 0.5);
	say(ui, kit, subId(id, 14), skr(cartTotal(cart)), x + TOTAL_LEFT * scale,
		y + (TOTAL_TOP + TOTAL_BOTTOM) * 0.5 * scale - TOTAL_SIZE * 0.6, (TOTAL_RIGHT - TOTAL_LEFT) * scale, TOTAL_SIZE,
		INK_BRIGHT, 0.5);
	say(ui, kit, subId(id, 15), "CANCEL", x + CANCEL_LEFT * scale,
		y + (CANCEL_TOP + CANCEL_BOTTOM) * 0.5 * scale - BUTTON_SIZE * 0.6, (CANCEL_RIGHT - CANCEL_LEFT) * scale, BUTTON_SIZE,
		INK_BRIGHT, 0.5);
	if (pressable(ui, subId(id, 16), x + CANCEL_LEFT * scale, y + CANCEL_TOP * scale, (CANCEL_RIGHT - CANCEL_LEFT) * scale,
		(CANCEL_BOTTOM - CANCEL_TOP) * scale)) {
		result = { kind: ShopStripTapKind.Cancel, good: NO_GOOD };
	}
	say(ui, kit, subId(id + 1, 0), "BUY", x + BUY_TEXT_LEFT * scale,
		y + (BUY_TOP + BUY_BOTTOM) * 0.5 * scale - BUTTON_SIZE * 0.6, (BUY_RIGHT - BUY_TEXT_LEFT) * scale, BUTTON_SIZE,
		INK_BRIGHT, 0.5);
	if (pressable(ui, subId(id + 1, 1), x + BUY_LEFT * scale, y + BUY_TOP * scale, (BUY_RIGHT - BUY_LEFT) * scale,
		(BUY_BOTTOM - BUY_TOP) * scale)) {
		result = { kind: ShopStripTapKind.Purchase, good: NO_GOOD };
	}
	return result;
}
