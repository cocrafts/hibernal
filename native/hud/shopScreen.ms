import { Ui } from "../ui/ui";
import { Kit, frame, icon, say, INK, INK_MUTED, EMBER, EMBER_HOT } from "./kit";
import { FrameLook } from "./frame";
import { ButtonStyle, SignState, ChipKind, button, textLink, signButton, chip } from "./buttons";
import { Rarity, rarityBorder } from "./rarity";
import { segmented } from "./controls";
import { pushToast } from "./notices";
import { Signing, idleSigning, startSigning, advanceSigning } from "./signing";
import { ScreenContext, screenTitle } from "./screenChrome";

const GROWTH_CAP: int32 = 120;
const CARD_HEIGHT: float32 = 76.0;
const CARD_STEP: float32 = 88.0;
const NO_ITEM: int32 = -1;
const SECTIONS: string[] = ["FOOD", "GROWTH", "INSURE", "SKINS"];

export enum ShopSection {
	Food,
	Growth,
	Insure,
	Skins,
}

export enum Insurance {
	Available,
	Armed,
	Used,
}

const SHOP_SECTIONS: ShopSection[] = [ShopSection.Food, ShopSection.Growth, ShopSection.Insure, ShopSection.Skins];

interface Offer {
	name: string;
	amount: int32;
	price: int32;
}

const FOOD: Offer[] = [{ name: "SMALL", amount: 1, price: 5 }, { name: "MEDIUM", amount: 2, price: 9 }, { name: "LARGE", amount: 3, price: 12 }];
const GROWTH: Offer[] = [{ name: "GROWTH +5%", amount: 5, price: 8 }, { name: "GROWTH +10%", amount: 10, price: 14 },
	{ name: "GROWTH +15%", amount: 15, price: 20 }];

interface ShopState {
	section: ShopSection;
	item: int32;
	signing: Signing;
	// in hundredths: 110 is x1.10
	growth: int32;
	insurance: Insurance;
	skinOwned: boolean;
	skinOn: boolean;
	balance: int32;
}

const shop: ShopState = {
	section: ShopSection.Food,
	item: NO_ITEM,
	signing: idleSigning(),
	growth: 110,
	insurance: Insurance.Available,
	skinOwned: false,
	skinOn: false,
	balance: 240,
};

function card(context: ScreenContext, id: int32, y: float32, name: string, effect: string, note: string, price: int32,
	state: SignState): boolean {
	const ui: Ui = context.ui;
	const kit: Kit = context.kit;
	frame(kit, id, 16.0, y, 328.0, CARD_HEIGHT, id, FrameLook.Normal);
	say(ui, kit, id, name, 32.0, y + 16.0, 150.0, 8.0, INK, 0.0);
	say(ui, kit, id + 1, effect, 32.0, y + 34.0, 150.0, 8.0, EMBER_HOT, 0.0);
	if (note != "") {
		say(ui, kit, id + 2, note, 32.0, y + 52.0, 150.0, 8.0, INK_MUTED, 0.0);
	}
	return signButton(ui, kit, id + 3, 190.0, y + 16.0, 138.0, 44.0, "BUY " + price.toString() + " SKR", state, id + 4, context.tick);
}

// The item being bought shows its signature; while one is out, the rest wait.
function offerState(item: int32, available: boolean): SignState {
	return match (item) {
		_ when item == shop.item => shop.signing.state,
		_ when shop.signing.state != SignState.Idle || !available => SignState.Disabled,
		_ => SignState.Idle,
	};
}

function growthLabel(growth: int32): string {
	const hundredths: int32 = growth % 100;
	return "X" + (growth / 100).toString() + "." + (hundredths < 10 ? "0" : "") + hundredths.toString();
}

function insuranceNote(insurance: Insurance): string {
	return match (insurance) {
		Insurance.Available => "ONCE PER PET",
		Insurance.Armed => "ARMED",
		Insurance.Used => "USED - NEVER AGAIN",
	};
}

// Returns the item tapped, or NO_ITEM.
function food(context: ScreenContext): int32 {
	let picked: int32 = NO_ITEM;
	for (let item: int32 = 0; item < FOOD.length; item += 1) {
		const offer: Offer = FOOD[item];
		if (card(context, 4010 + item * 10, 112.0 + (item as float32) * CARD_STEP, offer.name, "+" + offer.amount.toString() + " HEARTS",
			"", offer.price, offerState(item, true))) {
			picked = item;
		}
	}
	return picked;
}

function growth(context: ScreenContext): int32 {
	say(context.ui, context.kit, 4050, "NOW " + growthLabel(shop.growth) + " - CAP " + growthLabel(GROWTH_CAP), 16.0, 112.0, 328.0, 8.0,
		INK, 0.0);
	let picked: int32 = NO_ITEM;
	for (let item: int32 = 0; item < GROWTH.length; item += 1) {
		const offer: Offer = GROWTH[item];
		const capped: boolean = shop.growth + offer.amount > GROWTH_CAP;
		if (card(context, 4060 + item * 10, 132.0 + (item as float32) * CARD_STEP, offer.name, "HARVEST - 24H",
			capped ? "CAP " + growthLabel(GROWTH_CAP) : "", offer.price, offerState(item, !capped))) {
			picked = item;
		}
	}
	return picked;
}

function insure(context: ScreenContext): int32 {
	let picked: int32 = NO_ITEM;
	if (card(context, 4100, 112.0, "INSURANCE", "REVIVE ONCE AT 3 HEARTS", insuranceNote(shop.insurance), 25,
		offerState(0, shop.insurance == Insurance.Available))) {
		picked = 0;
	}
	const armed: boolean = shop.insurance == Insurance.Armed;
	if (textLink(context.ui, context.kit, 4110, 16.0, 212.0, armed ? "DEMO: MARK USED" : "DEMO: RESET", true)) {
		shop.insurance = armed ? Insurance.Used : Insurance.Available;
	}
	return picked;
}

function skins(context: ScreenContext): int32 {
	const ui: Ui = context.ui;
	const kit: Kit = context.kit;
	rarityBorder(ui, 16.0, 112.0, 120.0, 120.0, Rarity.Epic);
	icon(kit, 4150, "pet", 46.0, 142.0, 60.0);
	say(ui, kit, 4151, "ASH CLOAK", 150.0, 120.0, 194.0, 8.0, INK, 0.0);
	say(ui, kit, 4152, "COSMETIC - NO POWER", 150.0, 138.0, 194.0, 8.0, INK_MUTED, 0.0);
	let picked: int32 = NO_ITEM;
	if (!shop.skinOwned) {
		if (signButton(ui, kit, 4153, 150.0, 170.0, 178.0, 44.0, "BUY 30 SKR", offerState(0, true), 72, context.tick)) {
			picked = 0;
		}
	} else if (button(ui, kit, 4154, 150.0, 170.0, 178.0, 44.0, shop.skinOn ? "TAKE OFF" : "EQUIP", ButtonStyle.Primary, true, 73)) {
		shop.skinOn = !shop.skinOn;
	}
	if (shop.skinOn) {
		chip(ui, kit, 4155, 150.0, 150.0, "EQUIPPED", ChipKind.Filled, EMBER);
	}
	return picked;
}

function bought(context: ScreenContext): void {
	pushToast(context.toasts, "BOUGHT", false);
	match (shop.section) {
		ShopSection.Food => {},
		ShopSection.Growth => {
			const raised: int32 = shop.growth + GROWTH[shop.item].amount;
			shop.growth = raised > GROWTH_CAP ? GROWTH_CAP : raised;
		},
		ShopSection.Insure => {
			shop.insurance = Insurance.Armed;
		},
		ShopSection.Skins => {
			shop.skinOwned = true;
		},
	};
}

export function shopScreen(context: ScreenContext): void {
	screenTitle(context, 4000, "SHOP", "");
	icon(context.kit, 4002, "wallet", 236.0, 30.0, 16.0);
	say(context.ui, context.kit, 4003, shop.balance.toString() + " SKR", 256.0, 34.0, 88.0, 8.0, INK, 1.0);
	const picked: ShopSection = SHOP_SECTIONS[segmented(context.ui, context.kit, 4004, 16.0, 62.0, 328.0, SECTIONS, shop.section as int32, 71)];
	if (picked != shop.section && shop.signing.state != SignState.Waiting) {
		shop.item = NO_ITEM;
		shop.signing = idleSigning();
	}
	shop.section = picked;
	if (advanceSigning(shop.signing, context.tick)) {
		bought(context);
	}
	if (shop.signing.state == SignState.Idle) {
		shop.item = NO_ITEM;
	}
	const tapped: int32 = match (shop.section) {
		ShopSection.Food => food(context),
		ShopSection.Growth => growth(context),
		ShopSection.Insure => insure(context),
		ShopSection.Skins => skins(context),
	};
	if (tapped != NO_ITEM) {
		shop.item = tapped;
		startSigning(shop.signing, context.tick);
	}
	say(context.ui, context.kit, 4190, "EVERY PURCHASE RAISES BONDING. SKR NEVER BUYS POWER.", 16.0, 696.0, 328.0, 8.0, INK_MUTED, 0.5);
}
