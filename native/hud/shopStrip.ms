// The SKR shop in the activity log's look: one panel above the hotbar, a line per good, the cart and
// the buy row under them. Its height is fixed, so a tap never moves the lines under the finger.

import { Color } from "@metascript/void/src/void2d/types";
import { Ui, box, held, pressable, DESIGN_W, DESIGN_H } from "../ui/ui";
import {
	Kit, INK, INK_BRIGHT, INK_MUTED, HOLO_BLUE, EMBER_HOT, ALERT_RED, GROWTH_GREEN, plainLook, pressedLook, say, subId,
} from "./kit";
import { Food, foodHearts } from "../../rules/emission";
import { GROWTH_STEP_BPS, INSURANCE_REVIVE_BPS } from "../../rules/owner";
import { Insurance } from "../../rules/layout";
import { BPS } from "../../rules/units";
import { ItemCard, ItemRow, NO_ROW, percentOfBps } from "./itemCard";
import { hbrnAmount } from "./gameNumbers";
import { GamePet } from "../host/host";
import { CART_GOODS, CartGood, ShopGood, ShopLock, cartPrice, goodPrice, shopLock, freeSlots } from "./ownerGoods";
import { centredY, infoPanelSized, withAlpha } from "./shapes";

const PANEL_LEFT: float32 = 12.0;
const PANEL_WIDTH: float32 = 336.0;
const PANEL_PAD: float32 = 8.0;
const ROW_HEIGHT: float32 = 26.0;
const TEXT_SIZE: float32 = 10.0;
const SMALL_SIZE: float32 = 8.0;
const DIVIDER_GAP: float32 = 4.0;
const BUTTON_WIDTH: float32 = 76.0;
const BUTTON_GAP: float32 = 6.0;
const CLOSE_WIDTH: float32 = 30.0;
const NAME_SHARE: float32 = 0.4;
const EFFECT_SHARE: float32 = 0.33;
const FOOD_NAMES: string[] = ["SMALL FOOD", "MEDIUM FOOD", "LARGE FOOD"];
const GROWTH_NAMES: string[] = ["GROWTH I", "GROWTH II", "GROWTH III"];
const FOODS: Food[] = [Food.Small, Food.Medium, Food.Large];
const TIERS: int32 = 3;
// Food and growth in three tiers, then insurance. No skin exists yet, so none is listed.
const GOOD_ROWS: int32 = TIERS * 2 + 1;
// Ids: the panel's own parts on `id`, a good row each on id + 1 .. id + GOOD_ROWS, the cart and buy row after them.
const CART_ID: int32 = GOOD_ROWS + 1;

export enum ShopTapKind {
	Nothing,
	Add,
	Remove,
	Clear,
	Close,
	Purchase,
}

export struct ShopTap {
	kind: ShopTapKind;
	good: CartGood;
}

export enum NoticeKind {
	None,
	Ok,
	Warning,
	Error,
	Dead,
}

export struct ShopNotice {
	kind: NoticeKind;
	line: string;
}

export struct ShopView {
	pet: GamePet;
	cart: CartGood[];
	notice: ShopNotice;
	buying: boolean;
	// Panel bottom, just above the hotbar.
	bottom: float32;
}

const NO_TAP: ShopTap = { kind: ShopTapKind.Nothing, good: { good: ShopGood.Food, tier: 0 } };

// Hotbar icons for owner slots 5 and 6.
export function goodIcon(good: ShopGood): string {
	return match (good) {
		ShopGood.Food => "shopMedkit",
		ShopGood.Growth => "shopBattery",
		ShopGood.Insurance => "shopShield",
		ShopGood.Skin => "shopDrone",
	};
}

export function goodName(good: CartGood): string {
	return match (good.good) {
		ShopGood.Food => FOOD_NAMES[good.tier],
		ShopGood.Growth => GROWTH_NAMES[good.tier],
		ShopGood.Insurance => "INSURANCE",
		ShopGood.Skin => "SKIN",
	};
}

function factor(bps: int32): string {
	const hundredths: int32 = bps / 100;
	const cents: int32 = hundredths % 100;
	return "X" + (hundredths / 100).toString() + "." + (cents < 10 ? "0" : "") + cents.toString();
}

function goodEffect(good: CartGood): string {
	return match (good.good) {
		ShopGood.Food => "+" + foodHearts(FOODS[good.tier]).toString() + " HEARTS",
		ShopGood.Growth => "FORAGE " + factor(BPS + GROWTH_STEP_BPS * (good.tier + 1)),
		ShopGood.Insurance => "REVIVE AT " + percentOfBps(INSURANCE_REVIVE_BPS),
		ShopGood.Skin => "LOOK ONLY",
	};
}

function lockLine(lock: ShopLock): string {
	return match (lock) {
		ShopLock.PetLost => "PET LOST",
		ShopLock.ComingSoon => "COMING SOON",
		ShopLock.CartFull => "CART FULL",
		ShopLock.InsuranceUsed => "USED THIS LIFE",
		ShopLock.InsuranceBought => "ALREADY BOUGHT",
		ShopLock.NoFreeSlot => "NO FREE SLOT",
		ShopLock.NotEnoughSkr => "NOT ENOUGH SKR",
	};
}

function inCart(cart: CartGood[], good: CartGood): int32 {
	let count: int32 = 0;
	for (const held of cart) { if (held.good == good.good && held.tier == good.tier) { count += 1; } }
	return count;
}

function slotLine(pet: GamePet, good: ShopGood): string {
	return match (good) {
		ShopGood.Food => "USES A SLOT",
		ShopGood.Growth => "USES A SLOT",
		ShopGood.Insurance => pet.insurance == Insurance.Armed ? "USES A SLOT" : "ARMS NOW",
		ShopGood.Skin => "NO SLOT",
	};
}

// A line vertically centred in a row.
function sayInRow(ui: Ui, kit: Kit, id: int32, line: string, x: float32, top: float32, width: float32, size: float32,
	color: Color, align: float32): void {
	say(ui, kit, id, line, x, centredY(kit, line, size, top, ROW_HEIGHT), width, size, color, align);
}

function divider(ui: Ui, y: float32): void {
	box(ui, PANEL_LEFT + PANEL_PAD, y, PANEL_WIDTH - PANEL_PAD * 2.0, 1.0, 0.0, withAlpha(HOLO_BLUE, 0.35));
}

// A press that dims its own text while held, as the log's toggle does.
function pressRow(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32): boolean {
	pressedLook(kit, id, held(ui, id, x, y, width, ROW_HEIGHT));
	return pressable(ui, id, x, y, width, ROW_HEIGHT);
}

// NAME  EFFECT  PRICE; a good in the cart says how many, a locked one why, dimmed.
function goodRow(ui: Ui, kit: Kit, id: int32, view: ShopView, good: CartGood, y: float32): ShopTap {
	const x: float32 = PANEL_LEFT + PANEL_PAD;
	const width: float32 = PANEL_WIDTH - PANEL_PAD * 2.0;
	const lock = shopLock(view.pet, view.cart, good);
	const count: int32 = inCart(view.cart, good);
	const tapped: boolean = pressRow(ui, kit, subId(id, 0), x, y, width);
	const ink: Color = lock.ok || count > 0 ? INK_BRIGHT : INK_MUTED;
	const name: string = count > 0 ? goodName(good) + " X" + count.toString() : goodName(good);
	sayInRow(ui, kit, subId(id, 1), name, x, y, width * NAME_SHARE, TEXT_SIZE, count > 0 ? HOLO_BLUE : ink, 0.0);
	sayInRow(ui, kit, subId(id, 2), goodEffect(good), x + width * NAME_SHARE, y, width * EFFECT_SHARE, SMALL_SIZE,
		lock.ok ? INK : INK_MUTED, 0.0);
	const right: string = lock.ok || count > 0 ? goodPrice(good).toString() + " SKR" : lockLine(lock.error);
	sayInRow(ui, kit, subId(id, 3), right, x, y, width, lock.ok || count > 0 ? TEXT_SIZE : SMALL_SIZE,
		lock.ok || count > 0 ? EMBER_HOT : INK_MUTED, 1.0);
	plainLook(kit);
	return tapped ? { kind: ShopTapKind.Add, good: good } : NO_TAP;
}

function noticeColour(kind: NoticeKind): Color {
	return match (kind) {
		NoticeKind.None => INK_MUTED,
		NoticeKind.Ok => GROWTH_GREEN,
		NoticeKind.Warning => EMBER_HOT,
		NoticeKind.Error => ALERT_RED,
		NoticeKind.Dead => ALERT_RED,
	};
}

function textButton(ui: Ui, kit: Kit, id: int32, label: string, x: float32, y: float32, enabled: boolean, ink: Color): boolean {
	infoPanelSized(ui, x, y + 1.0, BUTTON_WIDTH, ROW_HEIGHT - 2.0);
	const tapped: boolean = enabled && pressRow(ui, kit, id, x, y, BUTTON_WIDTH);
	sayInRow(ui, kit, subId(id, 1), label, x, y, BUTTON_WIDTH, TEXT_SIZE, enabled ? ink : INK_MUTED, 0.5);
	plainLook(kit);
	return tapped;
}

// Above, below, left and right of the panel: a tap there closes the shop.
function tappedOutside(ui: Ui, id: int32, top: float32, bottom: float32): boolean {
	const above: boolean = pressable(ui, subId(id, 5), 0.0, 0.0, DESIGN_W, top);
	const below: boolean = pressable(ui, subId(id, 6), 0.0, bottom, DESIGN_W, DESIGN_H - bottom);
	const left: boolean = pressable(ui, subId(id, 7), 0.0, top, PANEL_LEFT, bottom - top);
	const right: boolean = pressable(ui, subId(id, 8), PANEL_LEFT + PANEL_WIDTH, top, DESIGN_W - PANEL_LEFT - PANEL_WIDTH,
		bottom - top);
	return above || below || left || right;
}

function panelHeight(): float32 {
	const rows: int32 = 1 + GOOD_ROWS + CART_GOODS + 2;
	return PANEL_PAD * 2.0 + ROW_HEIGHT * (rows as float32) + DIVIDER_GAP * 4.0;
}

export function shopPanel(ui: Ui, kit: Kit, id: int32, view: ShopView): ShopTap {
	const top: float32 = view.bottom - panelHeight();
	infoPanelSized(ui, PANEL_LEFT, top, PANEL_WIDTH, view.bottom - top);
	const x: float32 = PANEL_LEFT + PANEL_PAD;
	const width: float32 = PANEL_WIDTH - PANEL_PAD * 2.0;
	let tap: ShopTap = tappedOutside(ui, id, top, view.bottom) ? { ...NO_TAP, kind: ShopTapKind.Close } : NO_TAP;
	let y: float32 = top + PANEL_PAD;

	sayInRow(ui, kit, subId(id, 0), "SHOP", x, y, width * 0.3, TEXT_SIZE, INK_BRIGHT, 0.0);
	sayInRow(ui, kit, subId(id, 1), freeSlots(view.pet, view.cart).toString() + " FREE SLOTS  " +
		view.pet.itemsInTransit.toString() + " ON THE WAY", x + width * 0.2, y, width * 0.5, SMALL_SIZE, INK, 0.5);
	sayInRow(ui, kit, subId(id, 2), hbrnAmount(view.pet.skrBalance) + " SKR", x, y, width - CLOSE_WIDTH, TEXT_SIZE, EMBER_HOT,
		1.0);
	const closeX: float32 = x + width - CLOSE_WIDTH;
	if (pressRow(ui, kit, subId(id, 3), closeX - 6.0, y, CLOSE_WIDTH + 6.0)) { tap = { ...NO_TAP, kind: ShopTapKind.Close }; }
	sayInRow(ui, kit, subId(id, 4), "X", closeX, y, CLOSE_WIDTH, TEXT_SIZE, INK_BRIGHT, 1.0);
	plainLook(kit);
	y += ROW_HEIGHT + DIVIDER_GAP;
	divider(ui, y - DIVIDER_GAP * 0.5);

	const goods: CartGood[] = [];
	for (let tier: int32 = 0; tier < TIERS; tier += 1) { goods.push({ good: ShopGood.Food, tier: tier }); }
	for (let tier: int32 = 0; tier < TIERS; tier += 1) { goods.push({ good: ShopGood.Growth, tier: tier }); }
	goods.push({ good: ShopGood.Insurance, tier: 0 });
	for (let row: int32 = 0; row < GOOD_ROWS; row += 1) {
		const tapped: ShopTap = goodRow(ui, kit, id + 1 + row, view, goods[row], y);
		if (tapped.kind != ShopTapKind.Nothing) { tap = tapped; }
		y += ROW_HEIGHT;
		if (row == TIERS - 1 || row == TIERS * 2 - 1) {
			divider(ui, y + DIVIDER_GAP * 0.5);
			y += DIVIDER_GAP;
		}
	}
	divider(ui, y + DIVIDER_GAP * 0.5);
	y += DIVIDER_GAP;

	const shown: CartGood[] = [];
	for (const good of view.cart) { if (inCart(shown, good) == 0) { shown.push(good); } }
	if (shown.length == 0) {
		sayInRow(ui, kit, subId(id + CART_ID, 0), "CART EMPTY. TAP A LINE ABOVE TO ADD IT.", x, y, width, SMALL_SIZE, INK_MUTED, 0.0);
	}
	for (let line: int32 = 0; line < (shown.length as int32); line += 1) {
		const good: CartGood = shown[line];
		const rowTop: float32 = y + ROW_HEIGHT * (line as float32);
		if (pressRow(ui, kit, subId(id + CART_ID, 1 + line * 4), x, rowTop, width)) { tap = { kind: ShopTapKind.Remove, good: good }; }
		const count: int32 = inCart(view.cart, good);
		sayInRow(ui, kit, subId(id + CART_ID, 2 + line * 4), "-  " + count.toString() + " X " + goodName(good), x, rowTop, width * 0.7,
			TEXT_SIZE, INK_BRIGHT, 0.0);
		sayInRow(ui, kit, subId(id + CART_ID, 3 + line * 4), (goodPrice(good) * count).toString() + " SKR", x, rowTop, width, TEXT_SIZE,
			INK, 1.0);
		plainLook(kit);
	}
	y += ROW_HEIGHT * (CART_GOODS as float32);

	const line: string = view.notice.kind == NoticeKind.None ? "ONE BUY = ONE WALLET APPROVAL" : view.notice.line;
	sayInRow(ui, kit, subId(id + CART_ID, 12), line, x, y, width, SMALL_SIZE, noticeColour(view.notice.kind), 0.0);
	y += ROW_HEIGHT + DIVIDER_GAP;
	divider(ui, y - DIVIDER_GAP * 0.5);

	sayInRow(ui, kit, subId(id + CART_ID, 13), "TOTAL " + cartPrice(view.cart).toString() + " SKR", x, y, width * 0.5, TEXT_SIZE,
		INK_BRIGHT, 0.0);
	const open: boolean = !view.buying && view.cart.length > 0;
	const buyX: float32 = x + width - BUTTON_WIDTH;
	const cancelX: float32 = buyX - BUTTON_GAP - BUTTON_WIDTH;
	if (textButton(ui, kit, subId(id + CART_ID, 14), "CLEAR", cancelX, y, open, INK_BRIGHT)) {
		tap = { ...NO_TAP, kind: ShopTapKind.Clear };
	}
	if (textButton(ui, kit, subId(id + CART_ID, 15), view.buying ? "BUYING" : "BUY", buyX, y, open, EMBER_HOT)) {
		tap = { ...NO_TAP, kind: ShopTapKind.Purchase };
	}
	return tap;
}

// The card a filled owner slot shows while held.
const EMPTY_ROW: ItemRow = { label: "", value: "" };

export function goodCard(good: ShopGood, tier: int32): ItemCard {
	const held: CartGood = { good: good, tier: tier };
	return {
		icon: goodIcon(good),
		title: goodName(held),
		tag: "OWNED",
		tagColour: HOLO_BLUE,
		rows: [{ label: goodEffect(held), value: "" }, EMPTY_ROW, EMPTY_ROW, EMPTY_ROW],
		notes: match (good) {
			ShopGood.Food => ["THE PET EATS IT ON A NIGHT", "IT IS NOT AT FULL HEARTS."],
			ShopGood.Growth => ["THE PET TAKES IT AT THE NEXT", "DAY; IT LASTS ONE DAY."],
			ShopGood.Insurance => ["WAITS FOR THE HEIR WHILE", "THE PET IS INSURED."],
			ShopGood.Skin => ["COSMETIC ONLY."],
		},
		choosableRows: NO_ROW,
		chosenRow: NO_ROW,
	};
}
