// The shop over the hotbar (art/hud/shopMockup.jpg): ten cells of items with their SKR price,
// several selectable at once up to the pet's free hotbar slots, the owner's balance, PURCHASE and
// CANCEL. Pieces assets/hud/pieces/shop* (art/hud/cutHud.py SHOP_*); positions in design units
// from the panel's top-left. Drawn on the overlay layers.

import { Ui, pressable, beginOverlay, endOverlay } from "../ui/ui";
import { Color, rgba } from "@metascript/void/src/void2d/types";
import { Kit, PieceLayer, TextSize, INK_BRIGHT, piece, pieceWidth, pieceHeight, say, measure, subId, beginKitOverlay,
	endKitOverlay } from "./kit";

// Canvas pixels of cutHud.py's SHOP_CANVAS (shopMockup.jpg's own pixels from the panel's
// top-left) to design units: the panel's outline, canvas x 11 to 1023, is as wide as the
// hotbar's XP frame (259).
const SCALE: float32 = 259.0 / 1012.0;
export const SHOP_WIDTH: float32 = 1030.0 * SCALE;
export const SHOP_HEIGHT: float32 = 640.0 * SCALE;
export const SHOP_OUTLINE_LEFT: float32 = 11.0 * SCALE;
// Between the panel's bottom and the hotbar's panel, where the hologram shines.
export const SHOP_GAP: float32 = 40.0 * SCALE;
const HOLOGRAM_HEIGHT: float32 = 110.0 * SCALE;
const CELLS: int32 = 10;
const COLUMNS: int32 = 5;
const CELL_X: float32 = 42.0 * SCALE;
const CELL_Y: float32 = 88.0 * SCALE;
const CELL_STEP_X: float32 = 193.75 * SCALE;
const CELL_STEP_Y: float32 = 185.0 * SCALE;
const CHECK_X: float32 = 122.0 * SCALE;
const CHECK_Y: float32 = 8.0 * SCALE;
const ITEM_CENTRE_X: float32 = 86.0 * SCALE;
const ITEM_CENTRE_Y: float32 = 66.0 * SCALE;
const TAG_X: float32 = 10.0 * SCALE;
const TAG_Y: float32 = 136.0 * SCALE;
const BALANCE_X: float32 = 839.0 * SCALE;
const BALANCE_Y: float32 = 462.0 * SCALE;
const GEM_GAP: float32 = 6.0 * SCALE;
const BUTTON_Y: float32 = 505.0 * SCALE;
const PURCHASE_X: float32 = 151.0 * SCALE;
const CANCEL_X: float32 = 534.0 * SCALE;
const CART_X: float32 = 68.0 * SCALE;
const PURCHASE_TEXT_X: float32 = 90.0 * SCALE;
const CLOSE_X: float32 = 923.0 * SCALE;
const CLOSE_Y: float32 = 8.0 * SCALE;
const CLOSE_WIDTH: float32 = 64.0 * SCALE;
const CLOSE_HEIGHT: float32 = 62.0 * SCALE;
const PRICE_SIZE: float32 = 8.0;
const LABEL_SIZE: float32 = 8.0;
const INK_DIM: Color = rgba(0.62, 0.72, 0.84, 1.0);

export struct ShopItem {
	// the hotbar's piece for it once bought, and the shop's own
	icon: string;
	shopIcon: string;
	price: int32;
}

export enum ShopTapKind {
	Nothing,
	Close,
	Toggle,
	Purchase,
	Cancel,
}

// `item` is the toggled item for Toggle, NO_ITEM otherwise.
export struct ShopTap {
	kind: ShopTapKind;
	item: int32;
}

export const NO_ITEM: int32 = -1;

function tap(kind: ShopTapKind): ShopTap {
	return { kind: kind, item: NO_ITEM };
}

function inside(px: float32, py: float32, x: float32, y: float32, width: float32, height: float32): boolean {
	return px >= x && px < x + width && py >= y && py < y + height;
}

// A gem and an amount, centred together on the plate at (x, y): the price under a cell, the balance.
function amountPlate(ui: Ui, kit: Kit, id: int32, plate: string, x: float32, y: float32, line: string): void {
	piece(kit, subId(id, 0), PieceLayer.Frames, plate, x, y);
	const plateWidth: float32 = pieceWidth(kit, plate);
	const plateHeight: float32 = pieceHeight(kit, plate);
	const text: TextSize = measure(kit, line, PRICE_SIZE);
	const gemWidth: float32 = pieceWidth(kit, "shopGem");
	const left: float32 = x + (plateWidth - (gemWidth + GEM_GAP + text.width)) * 0.5;
	const centreY: float32 = y + plateHeight * 0.5;
	piece(kit, subId(id, 1), PieceLayer.Icons, "shopGem", left, centreY - pieceHeight(kit, "shopGem") * 0.5);
	say(ui, kit, subId(id, 2), line, left + gemWidth + GEM_GAP, centreY - PRICE_SIZE * 0.625, text.width + 2.0, PRICE_SIZE,
		INK_BRIGHT, 0.0);
}

// 1420 → "1,420".
export function withCommas(value: int32): string {
	const digits: string = value.toString();
	let out: string = "";
	for (let i: int32 = 0; i < (digits.length as int32); i += 1) {
		const left: int32 = (digits.length as int32) - i;
		if (i > 0 && left % 3 == 0) { out = out + ","; }
		out = out + digits.charAt(i);
	}
	return out;
}

export function selectedCount(selected: boolean[]): int32 {
	let count: int32 = 0;
	for (const on of selected) {
		if (on) { count += 1; }
	}
	return count;
}

// `limit` is how many items may be selected (the pet's free hotbar slots); unselected items show
// disabled once that many are.
export function shopPopup(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, items: ShopItem[], selected: boolean[],
	limit: int32, balance: int32): ShopTap {
	beginOverlay(ui);
	beginKitOverlay(kit);
	piece(kit, subId(id, 11), PieceLayer.Frames, "shopHologram", x, y + SHOP_HEIGHT + SHOP_GAP + 1.0 - HOLOGRAM_HEIGHT);
	piece(kit, subId(id, 0), PieceLayer.Frames, "shopFrame", x, y);
	let result: ShopTap = tap(ShopTapKind.Nothing);
	const full: boolean = selectedCount(selected) >= limit;
	const cellWidth: float32 = pieceWidth(kit, "shopCell");
	const cellHeight: float32 = pieceHeight(kit, "shopCell");
	for (let cell: int32 = 0; cell < CELLS; cell += 1) {
		const cellX: float32 = x + CELL_X + CELL_STEP_X * ((cell % COLUMNS) as float32);
		const cellY: float32 = y + CELL_Y + CELL_STEP_Y * ((cell / COLUMNS) as float32);
		if (cell >= items.length) {
			piece(kit, subId(id + 1, cell), PieceLayer.Frames, "shopCellPlus", cellX, cellY);
			continue;
		}
		const item: ShopItem = items[cell];
		const on: boolean = selected[cell];
		const look: string = on ? "shopCellSelected" : (full ? "shopCellDisabled" : "shopCell");
		piece(kit, subId(id + 1, cell), PieceLayer.Frames, look, cellX, cellY);
		piece(kit, subId(id + 2, cell), PieceLayer.Icons, item.shopIcon, cellX + ITEM_CENTRE_X - pieceWidth(kit, item.shopIcon) * 0.5,
			cellY + ITEM_CENTRE_Y - pieceHeight(kit, item.shopIcon) * 0.5);
		if (on) {
			piece(kit, subId(id + 4, cell), PieceLayer.Icons, "shopCheck", cellX + CHECK_X, cellY + CHECK_Y);
		}
		amountPlate(ui, kit, subId(id + 3, cell), "shopTag", cellX + TAG_X, cellY + TAG_Y, item.price.toString());
		if (pressable(ui, subId(id + 6, cell), cellX, cellY, cellWidth, cellHeight) && (on || !full)) {
			result = { kind: ShopTapKind.Toggle, item: cell };
		}
	}
	amountPlate(ui, kit, subId(id, 1), "shopBalance", x + BALANCE_X, y + BALANCE_Y, withCommas(balance));
	const purchaseWidth: float32 = pieceWidth(kit, "shopPurchase");
	const cancelWidth: float32 = pieceWidth(kit, "shopCancel");
	const buttonHeight: float32 = pieceHeight(kit, "shopPurchase");
	piece(kit, subId(id, 4), PieceLayer.Frames, "shopPurchase", x + PURCHASE_X, y + BUTTON_Y);
	const buttonMiddle: float32 = y + BUTTON_Y + buttonHeight * 0.5;
	const labelY: float32 = buttonMiddle - LABEL_SIZE * 0.625;
	piece(kit, subId(id, 12), PieceLayer.Icons, "shopCart", x + PURCHASE_X + CART_X, buttonMiddle - pieceHeight(kit, "shopCart") * 0.5);
	say(ui, kit, subId(id, 5), "PURCHASE", x + PURCHASE_X + PURCHASE_TEXT_X, labelY, purchaseWidth - PURCHASE_TEXT_X, LABEL_SIZE,
		selectedCount(selected) > 0 ? INK_BRIGHT : INK_DIM, 0.5);
	piece(kit, subId(id, 6), PieceLayer.Frames, "shopCancel", x + CANCEL_X, y + BUTTON_Y);
	say(ui, kit, subId(id, 7), "CANCEL", x + CANCEL_X, labelY, cancelWidth, LABEL_SIZE, INK_DIM, 0.5);
	if (pressable(ui, subId(id, 8), x + PURCHASE_X, y + BUTTON_Y, purchaseWidth, buttonHeight)) {
		result = tap(ShopTapKind.Purchase);
	}
	if (pressable(ui, subId(id, 9), x + CANCEL_X, y + BUTTON_Y, cancelWidth, buttonHeight)) {
		result = tap(ShopTapKind.Cancel);
	}
	if (pressable(ui, subId(id, 10), x + CLOSE_X, y + CLOSE_Y, CLOSE_WIDTH, CLOSE_HEIGHT)) {
		result = tap(ShopTapKind.Close);
	}
	if (ui.released && !inside(ui.pressX, ui.pressY, x, y, SHOP_WIDTH, SHOP_HEIGHT)
		&& !inside(ui.releaseX, ui.releaseY, x, y, SHOP_WIDTH, SHOP_HEIGHT)) {
		result = tap(ShopTapKind.Close);
	}
	endKitOverlay(kit);
	endOverlay(ui);
	return result;
}
