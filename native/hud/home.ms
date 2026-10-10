import { Color, rgba } from "@metascript/void/src/void2d/types";
import {
	Ui, PetHead, PetHeadHidden, box, createUi, beginUi, endUi, beginOverlay, endOverlay, held, pressable, DESIGN_W, DESIGN_H,
} from "../ui/ui";
import {
	Kit, PieceLayer, createKit, beginKit, endKit, beginKitOverlay, endKitOverlay, fill, iconTinted, measure, pieceSized, pieceHeight, plainLook, pressedLook, say, subId, INK_BRIGHT, INK_MUTED, HOLO_BLUE,
	HOLO_GREEN, ALERT_RED, STACKED_ROW_HEIGHT,
} from "./kit";
import { Toasts, emptyToasts, pushToast, drawToasts } from "./notices";
import {
	HOTBAR_HEIGHT, HOTBAR_SLOTS, PET_SLOTS, EMPTY_SLOT, NO_SLOT, HotbarTap, HotbarTapKind, hotbar,
	hotbarTopEdge, hotbarSlotCentreX,
} from "./hotbar";
import { ItemCard, itemPeek, gearCard, gearSummary, slotName } from "./itemCard";
import { NoticeKind, ShopNotice, ShopTap, ShopTapKind, goodCard, goodIcon, shopPanel } from "./shopStrip";
import { CartGood, ShopGood, ShopLock, SKR_UNIT, ownedGood, packedCart, shopLock, sulking } from "./ownerGoods";
import { Gear, Item, GearSlot, ItemSkill, at, isEmpty } from "../../rules/items";
import { OwnerItem, GIFT_BONDING } from "../../rules/owner";
import { Banner, BannerArt, BannerWord, BANNER_STEP, banner, banners, bannersHeight } from "./banners";
import { gearIcon } from "./gearIcons";
import { NO_PET_NAME, petDisplayName, randomPetName } from "./petNames";
import {
	Character, NoLeaning, STAT_COLUMN_HEIGHT, characterLeaning, characterStats, leaning, regionColour, regionName, statColumn,
	skillRing, skillPreview,
} from "./character";
import { toggleRow } from "./toggles";
import { Talent, TalentKind, TalentGrade } from "../../rules/talent";
import { petNewsAllowed, requestPetNews, requestWallpaperPicker, wallpaperPlace, WallpaperPlace } from "../host/host";
import { INFO_PANEL_HEIGHT } from "./shapes";
import { ActivityLog, activityLogState, activityLog } from "./activityLog";
import { NO_NEIGHBOUR, PetActivity, STAND_IN_ACTIVITIES } from "./activity";
import { onboarding, waitingLine } from "./onboarding";
import { mournedLine, mournedName, mournedPet } from "./mourning";
import { Gesture, Taps, noTaps, gestureOf } from "./gestures";
import { groupedAmount, hbrnAmount, heartShare, HeartCountError, levelProgress } from "./gameNumbers";
import {
	GiftStep, IncomeUnknown, buyStatus, currentLivePet, dailyIncome, giftOwedToOwner, giftStatus, giftStep, summonInFlight,
} from "./gameAvailability";
import { NeighbourBlock, currentNeighbourBlock, fightActivities } from "./neighbours";
import {
	NeighbourVisit, neighbourVisitState, HOME_SEAT, canVisit, stepVisit, visitCaption, visitHome, visitedNeighbour, neighbourName,
	neighbourCard,
} from "./neighbourVisit";
import { BPS } from "../../rules/units";
import { Region } from "../../rules/stats";
import { GameNeighbour, GamePet, PetLife, noGamePet, OwnerAction, OwnerActionOutcome, ownerActionOutcome, requestOwnerAction } from "../host/host";

interface Home {
	ui: Ui;
	kit: Kit;
	toasts: Toasts;
	activityLog: ActivityLog;
	visit: NeighbourVisit;
	taps: Taps;
	// This frame's swipe or double tap on the empty middle of the screen, for visitButtons.
	pageGesture: Gesture;
	// The owner action outcome is shared with Summon and Buy; show it only after CLAIM asked.
	giftAsked: boolean;
	hearts: int32;
	maxHearts: int32;
	harvest: uint64;
	burrow: uint64;
	bonding: int32;
	shopOpen: boolean;
	treeShown: boolean;
	selectedSkill: int32;
	shopCart: CartGood[];
	// The last refused tap, at most one; cleared by the next change to the cart.
	shopRefusal: ShopLock[];
	inventory: string[];
	skrBalance: int32;
	buyAsked: boolean;
	buyOutcome: OwnerActionOutcome;
	giftOutcome: OwnerActionOutcome;
	onboardingNameId: uint8;
	// The last live Pet read, at most one; the chain keeps no record of gear or level changes, so the app logs those it sees.
	seen: SeenPet[];
	// Newest first, PET_CHANGES_KEPT at most; gone when the app process ends.
	petChanges: PetActivity[];
}

interface SeenPet {
	generation: int32;
	level: int32;
	// In GEAR_SLOTS order.
	gear: Item[];
}

const PET_CHANGES_KEPT: int32 = 20;

// Made by initHudHome; a list so that frameHudHome can run before it without a null.
const homes: Home[] = [];

export function initHudHome(): void {
	const ui: Ui = createUi(rgba(0.0, 0.0, 0.0, 1.0));
	const home: Home = {
		ui: ui,
		kit: createKit(ui),
		toasts: emptyToasts(),
		activityLog: activityLogState(),
		visit: neighbourVisitState(),
		taps: noTaps(),
		pageGesture: Gesture.None,
		giftAsked: false,
		seen: [],
		petChanges: [],
		hearts: 7,
		maxHearts: 10,
		harvest: 1240 as uint64,
		burrow: 5600 as uint64,
		bonding: 40,
		shopOpen: false,
		treeShown: false,
		selectedSkill: -1,
		shopCart: [],
		shopRefusal: [],
		inventory: previewInventory(),
		skrBalance: STAND_IN_SKR_BALANCE,
		buyAsked: false,
		buyOutcome: OwnerActionOutcome.Idle,
		giftOutcome: OwnerActionOutcome.Idle,
		onboardingNameId: randomPetName(NO_PET_NAME),
	};
	homes.push(home);
}


const STAND_IN_SKR_BALANCE: int32 = 1420;
// Slots 1 to 4: the Pet's gear; slot 5: a Medium Growth the owner bought; slot 6 empty.
const STAND_IN_GEAR: Item[] = [
	Item.minted(TalentGrade.Epic, TalentKind.Might, ItemSkill.DamageGuard, 9),
	Item.minted(TalentGrade.Common, TalentKind.Grit, ItemSkill.None, 4),
	Item.minted(TalentGrade.Rare, TalentKind.Might, ItemSkill.None, 7),
	Item.minted(TalentGrade.Legendary, TalentKind.Forage, ItemSkill.Revive, 12),
];
// rules/items.ms GearSlot order, the order the rules fill an empty Pet's gear in.
const GEAR_SLOTS: GearSlot[] = [GearSlot.Head, GearSlot.Body, GearSlot.Hands, GearSlot.Feet];
const STAND_IN_OWNER_GOOD: ShopGood = ShopGood.Growth;
const STAND_IN_OWNER_TIER: int32 = 1;
const ITEM_CARD_ID: int32 = 330;
const ITEM_CARD_LEFT: float32 = 18.0;
const SHOP_GAP: float32 = 4.0;
const ITEM_CARD_GAP: float32 = 4.0;

const HOTBAR_ID: int32 = 300;
const HOTBAR_BOTTOM_PADDING: float32 = 38.0;
export const STAND_IN_LEVEL: int32 = 1;
const STAND_IN_XP: uint32 = 620;
const STAND_IN_XP_TO_NEXT: uint32 = 1000;
const SHOP_ID: int32 = 320;
const TOASTS_Y: float32 = 371.0;
// "<  NAME  >" across the top: the arrows walk the Block, the name goes back home. Both columns start below it.
const TITLE_TOP: float32 = 46.0;
const TITLE_ROW: float32 = 32.0;
const TITLE_HEIGHT: float32 = TITLE_ROW + 18.0;
const COLUMNS_TOP: float32 = TITLE_TOP + TITLE_HEIGHT;
const COLUMN_RIGHT_PADDING: float32 = 8.0;
const WALLPAPER_ACTION_ID: int32 = 340;
const PET_NEWS_ID: int32 = 2972;
const BANNERS_ID: int32 = 350;
const PET_NAME_ID: int32 = 395;
const PET_REGION_ID: int32 = 398;
const PET_NAME_SIZE: float32 = 20.0;
const VISIT_CAPTION_ID: int32 = 399;
const VISIT_CAPTION_SIZE: float32 = 8.0;
// VISIT_CAPTION_GAP under the name's capitals, inside the gap under the title row that is there with or
// without it, so nothing moves.
const VISIT_CAPTION_GAP: float32 = 11.0;
const VISIT_CAPTION_Y: float32 = TITLE_TOP + (TITLE_ROW + PET_NAME_SIZE * 0.66) * 0.5 + VISIT_CAPTION_GAP
	- VISIT_CAPTION_SIZE * 0.375;
// Measured on Seeker: the capitals start 0.375 of the size below the line's top and stand 0.66 of it tall.
const PET_NAME_Y: float32 = (TITLE_ROW - PET_NAME_SIZE * 0.66) * 0.5 - PET_NAME_SIZE * 0.375;
const BANNERS_LEFT_PADDING: float32 = 8.0;
const STAND_IN_HARVEST_PER_DAY: uint64 = 200;
const CHARACTER_ID: int32 = 360;
const TREE_TOGGLE_ID: int32 = 370;
const SKILL_RING_ID: int32 = 380;
const SKILL_PREVIEW_ID: int32 = 381;
const TREE_SHADE_ID: int32 = 382;
const TREE_SHADE: Color = rgba(0.0, 0.01, 0.03, 0.7);
const ACTIVITY_LOG_ID: int32 = 2000;
const ACTIVITY_LOG_X: float32 = 12.0;
const ACTIVITY_LOG_WIDTH: float32 = DESIGN_W - 24.0;
const ACTIVITY_LOG_GAP: float32 = 8.0;
const NEIGHBOUR_CARD_ID: int32 = 2900;
const VISIT_HOME_ID: int32 = 394;
const VISIT_PREVIOUS_ID: int32 = 396;
const VISIT_NEXT_ID: int32 = 397;
const VISIT_BUTTON: float32 = TITLE_ROW;
const VISIT_LEFT: float32 = 8.0;
// Past the button's edges, so a thumb need not land on it exactly.
const VISIT_REACH: float32 = 6.0;
const NAME_GAP: float32 = 6.0;
const NAME_FIELD_LEFT: float32 = VISIT_LEFT + VISIT_BUTTON + NAME_GAP;
const NAME_FIELD_WIDTH: float32 = DESIGN_W - NAME_FIELD_LEFT * 2.0;
const NEXT_BUTTON_X: float32 = DESIGN_W - VISIT_LEFT - VISIT_BUTTON;
const HARVEST_ROW: int32 = 1;
const INCOME_ID: int32 = 2952;
const PAGE_GESTURE_ID: int32 = 2970;
const GROWTH_ID: int32 = 2971;
const BURROW_ROW: int32 = 0;
const GIFT_ROW: int32 = 2;
const CLAIM_ID: int32 = 2950;
const CLAIM_GAP: float32 = 4.0;
const HEAD_HEARTS_ID: int32 = 2962;
// In the scene's pixels, so the bar reads as part of the pixel-art scene.
const HEAD_BAR_GAP: int32 = 5;
const HEAD_BAR_WIDE: int32 = 24;
const HEAD_BAR_TALL: int32 = 3;
const HEAD_BAR_TRACK: Color = rgba(0.06, 0.05, 0.08, 1.0);
const HEART_SIZE: float32 = 10.0;
const HEART_GAP: float32 = 2.0;
// Between the stats column and the toggles under it.
const CHARACTER_STATS_GAP: float32 = 11.0;
const TREE_LABEL: string = "SKILL TREE / PREVIEW";
// A level-14 Worker on its forage clusters with a work talent.
const STAND_IN_CHARACTER: Character = {
	level: 14,
	tree: { bits: 0x3ff9 as uint64 },
	talent: { kind: TalentKind.Forage, multiplierBps: 13400 },
};
const WALLPAPER_LABEL: string = "SET AS WALLPAPER";
const PET_NEWS_LABEL: string = "ALLOW PET NOTIFICATIONS";
// Hearts over the Pet's head by bonding's share of GIFT_BONDING: from DEVOTED_SHARE on the Pet is
// about to gift.
const FOND_SHARE: float32 = 0.5;
const DEVOTED_SHARE: float32 = 0.95;

// What Home shows: the live Pet when the live-game gate passes, otherwise the labelled preview.
struct HomeNumbers {
	live: boolean;
	// "" in the preview: a name appears only for a live Pet.
	name: string;
	hearts: int32;
	maxHearts: int32;
	harvest: uint64;
	burrow: uint64;
	bonding: int32;
	level: int32;
	xp: uint32;
	xpToNext: uint32;
	character: Character;
}

function liveNumbers(pet: GamePet): HomeNumbers {
	const [xp, xpToNext] = levelProgress(pet.level, pet.xp);
	return {
		live: true,
		name: petDisplayName(pet.nameId, pet.lineageGeneration as uint16),
		hearts: pet.hearts,
		maxHearts: pet.maxHearts,
		harvest: pet.harvest,
		burrow: pet.burrow,
		bonding: pet.bonding,
		level: pet.level,
		xp: xp,
		xpToNext: xpToNext,
		character: {
			level: pet.level,
			tree: { bits: pet.tree },
			talent: { kind: pet.talentKind, multiplierBps: pet.talentBps },
		},
	};
}

function homeNumbers(home: Home): HomeNumbers {
	const pet = currentLivePet();
	if (pet.ok) { return liveNumbers(pet.value); }
	return {
		live: false,
		name: "",
		hearts: home.hearts,
		maxHearts: home.maxHearts,
		harvest: home.harvest,
		burrow: home.burrow,
		bonding: home.bonding,
		level: STAND_IN_LEVEL,
		xp: STAND_IN_XP,
		xpToNext: STAND_IN_XP_TO_NEXT,
		character: STAND_IN_CHARACTER,
	};
}

function closeShop(home: Home): void {
	home.shopOpen = false;
	home.shopCart = [];
	home.shopRefusal = [];
}

function ownerSlotItem(pet: GamePet, slot: int32): OwnerItem {
	return slot == PET_SLOTS ? pet.ownerFirst : pet.ownerSecond;
}

function gearIcons(gear: Gear): string[] {
	const slots: string[] = [];
	for (let slot: int32 = 0; slot < PET_SLOTS; slot += 1) {
		const icon = gearIcon(GEAR_SLOTS[slot], gear.at(GEAR_SLOTS[slot]));
		slots.push(icon.ok ? icon.value : EMPTY_SLOT);
	}
	return slots;
}

// The preview Pet wears STAND_IN_GEAR and holds a growth dose in slot 5.
function previewGear(): Gear {
	return { head: STAND_IN_GEAR[0], body: STAND_IN_GEAR[1], hands: STAND_IN_GEAR[2], feet: STAND_IN_GEAR[3] };
}

// Item.rarity per hotbar slot; owner slots hold goods, not graded items.
function slotRarities(gear: Gear): int32[] {
	const rarities: int32[] = [];
	for (const slot of GEAR_SLOTS) { rarities.push(gear.at(slot).rarity as int32); }
	for (let slot: int32 = PET_SLOTS; slot < HOTBAR_SLOTS; slot += 1) { rarities.push(0); }
	return rarities;
}

function previewInventory(): string[] {
	const slots: string[] = gearIcons(previewGear());
	slots.push("battery");
	slots.push(EMPTY_SLOT);
	return slots;
}

// A neighbour's owner items are not in its Pet account, so its owner slots stay empty.
function neighbourInventory(seat: GameNeighbour): string[] {
	const slots: string[] = gearIcons(seat.gear);
	for (let slot: int32 = PET_SLOTS; slot < HOTBAR_SLOTS; slot += 1) { slots.push(EMPTY_SLOT); }
	return slots;
}

function liveInventory(pet: GamePet): string[] {
	const slots: string[] = gearIcons(pet.gear);
	for (let slot: int32 = PET_SLOTS; slot < HOTBAR_SLOTS; slot += 1) {
		const owned = ownedGood(ownerSlotItem(pet, slot));
		slots.push(owned.ok ? goodIcon(owned.value.good) : EMPTY_SLOT);
	}
	return slots;
}

function slotCard(home: Home, slot: int32): ItemCard {
	const pet = currentLivePet();
	if (pet.ok) {
		if (slot < PET_SLOTS) {
			return gearCard(home.inventory[slot], GEAR_SLOTS[slot], pet.value.gear.at(GEAR_SLOTS[slot]), true);
		}
		const owned = ownedGood(ownerSlotItem(pet.value, slot));
		if (!owned.ok) {
			console.log("Home slot " + slot.toString() + " card asked for an empty owner slot");
			unreachable;
		}
		return goodCard(owned.value.good, owned.value.tier);
	}
	if (slot < PET_SLOTS) {
		return gearCard(home.inventory[slot], GEAR_SLOTS[slot], STAND_IN_GEAR[slot], false);
	}
	const card: ItemCard = goodCard(STAND_IN_OWNER_GOOD, STAND_IN_OWNER_TIER);
	return { ...card, icon: home.inventory[slot], tag: "PREVIEW" };
}

// A filled slot shows its card only while a finger is on it (heldItem); tapping an empty owner slot opens the shop.
function onHotbarSlot(home: Home, slot: int32): void {
	if (slot < PET_SLOTS || home.inventory[slot] != EMPTY_SLOT) { return; }
	home.treeShown = false;
	home.shopOpen = !home.shopOpen;
}

function withoutOne(cart: CartGood[], good: CartGood): CartGood[] {
	const left: CartGood[] = [];
	let removed: boolean = false;
	for (const held of cart) {
		if (!removed && held.good == good.good && held.tier == good.tier) { removed = true; } else { left.push(held); }
	}
	return left;
}

function onShopTap(home: Home, pet: GamePet, live: boolean, tap: ShopTap): void {
	match (tap.kind) {
		ShopTapKind.Nothing => {},
		ShopTapKind.Add => {
			const lock = shopLock(pet, home.shopCart, tap.good);
			if (lock.ok) {
				home.shopCart.push(tap.good);
				home.shopRefusal = [];
			} else {
				home.shopRefusal = [lock.error];
			}
		},
		ShopTapKind.Remove => {
			home.shopCart = withoutOne(home.shopCart, tap.good);
			home.shopRefusal = [];
		},
		ShopTapKind.Clear => {
			home.shopCart = [];
			home.shopRefusal = [];
		},
		ShopTapKind.Close => { closeShop(home); },
		ShopTapKind.Purchase => {
			if (!live) {
				pushToast(home.toasts, "PREVIEW SHOP. SUMMON A PET TO BUY.", true);
				return;
			}
			home.buyAsked = true;
			requestOwnerAction(OwnerAction.Buy, packedCart(home.shopCart));
			closeShop(home);
		},
	};
}

function refusalLine(lock: ShopLock): string {
	return match (lock) {
		ShopLock.PetLost => "YOUR PET HAS DIED.",
		ShopLock.ComingSoon => "SKINS ARE COMING SOON.",
		ShopLock.CartFull => "THE CART HOLDS 3 ITEMS.",
		ShopLock.InsuranceUsed => "INSURANCE WAS USED IN THIS LIFE.",
		ShopLock.InsuranceBought => "INSURANCE IS ALREADY BOUGHT.",
		ShopLock.NoFreeSlot => "OWNER SLOTS 5 AND 6 ARE FULL.",
		ShopLock.NotEnoughSkr => "NOT ENOUGH SKR FOR THIS CART.",
	};
}

function shopNotice(home: Home, pet: GamePet, live: boolean): ShopNotice {
	const lost = shopLock(pet, [], { good: ShopGood.Food, tier: 0 });
	if (!lost.ok && lost.error == ShopLock.PetLost) { return { kind: NoticeKind.Dead, line: refusalLine(ShopLock.PetLost) }; }
	if (home.shopRefusal.length > 0) { return { kind: NoticeKind.Error, line: refusalLine(home.shopRefusal[0]) }; }
	if (!live) { return { kind: NoticeKind.Warning, line: "PREVIEW SHOP. SUMMON A PET TO BUY." }; }
	if (sulking(pet)) { return { kind: NoticeKind.Warning, line: "YOUR PET IS SULKING. ITEMS WAIT UNTIL IT CALMS DOWN." }; }
	return { kind: NoticeKind.None, line: "" };
}

// On the overlay, so the Home widgets under the panel take no taps while it is open.
function shop(home: Home, barTop: float32): void {
	const live = currentLivePet();
	const pet: GamePet = live.ok ? live.value : { ...noGamePet(), life: PetLife.FirstLifeActive,
		skrBalance: (home.skrBalance as uint64) * SKR_UNIT };
	beginOverlay(home.ui);
	beginKitOverlay(home.kit);
	const tap: ShopTap = shopPanel(home.ui, home.kit, SHOP_ID, {
		pet: pet,
		cart: home.shopCart,
		notice: shopNotice(home, pet, live.ok),
		buying: home.buyAsked && summonInFlight(ownerActionOutcome()),
		bottom: barTop + hotbarTopEdge() - SHOP_GAP,
	});
	endKitOverlay(home.kit);
	endOverlay(home.ui);
	onShopTap(home, pet, live.ok, tap);
}

const WEALTH_ROWS: int32 = 2;

// Left: at the top in the app, centred on the screen's height on the wallpaper and lock screen.
// `title` "" leaves the title line empty.
// `more` rows follow HARVEST and BURROW; returns each row's right edge.
function wealth(home: Home, numbers: HomeNumbers, top: float32, more: Banner[]): float32[] {
	const harvest: BannerWord[] = numbers.live ? [
		{ text: "HARVEST", colour: HOLO_BLUE },
		{ text: hbrnAmount(numbers.harvest), colour: INK_BRIGHT },
	] : [
		{ text: "PREVIEW HARVEST", colour: HOLO_BLUE },
		{ text: groupedAmount(numbers.harvest), colour: INK_BRIGHT },
	];
	const rows: Banner[] = [
		{ words: [
			{ text: numbers.live ? "BURROW" : "PREVIEW BURROW", colour: HOLO_BLUE },
			{ text: numbers.live ? hbrnAmount(numbers.burrow) : groupedAmount(numbers.burrow), colour: INK_BRIGHT },
		] },
		{ words: harvest },
	];
	for (const row of more) { rows.push(row); }
	return banners(home.ui, home.kit, BANNERS_ID, BANNERS_LEFT_PADDING, top, rows);
}

// The same comparison as rules/layout.ms growthBoosted: a dose bought for the coming day.
function growthActive(pet: GamePet): boolean {
	return pet.lastTickEpoch + 1 == pet.growthMultiplierExpiry;
}

function petBanners(pet: GamePet): Banner[] {
	return [{ words: [
		{ text: "GIFT", colour: HOLO_BLUE },
		{ text: hbrnAmount(giftOwedToOwner(pet)), colour: INK_BRIGHT },
	] }];
}

// Right of the BURROW row while a growth dose is working.
function growthBanner(home: Home, pet: GamePet, left: float32): void {
	if (!growthActive(pet)) { return; }
	banner(home.ui, home.kit, GROWTH_ID, BannerArt.Display, left, COLUMNS_TOP + BANNER_STEP * (BURROW_ROW as float32), [
		{ text: "GROWTH", colour: HOLO_BLUE },
		{ text: "+" + (((pet.growthMultiplierBps - BPS) / 100) as int32).toString() + "%", colour: HOLO_GREEN },
	]);
}

// Right of the HARVEST row: what one full day pays at today's World.
function incomeBanner(home: Home, amount: string, left: float32): void {
	banner(home.ui, home.kit, INCOME_ID, BannerArt.Display, left, COLUMNS_TOP + BANNER_STEP * (HARVEST_ROW as float32), [
		{ text: "INCOME", colour: HOLO_BLUE },
		{ text: "+" + amount, colour: HOLO_GREEN },
	]);
}

// Right of the GIFT row, only while there is a gift to take or a claim to report on; orange while it can be pressed.
function claimBanner(home: Home, pet: GamePet, left: float32, y: float32): void {
	const step: GiftStep = giftStep(pet);
	const outcome: OwnerActionOutcome = ownerActionOutcome();
	if (step == GiftStep.Nothing) { return; }
	const enabled: boolean = step != GiftStep.Nothing && !(home.giftAsked && summonInFlight(outcome));
	const label: string = match (step) {
		GiftStep.Nothing => "CLAIM",
		GiftStep.Commit => "PREPARE CLAIM",
		GiftStep.Claim => "CLAIM",
	};
	pressedLook(home.kit, subId(CLAIM_ID, 15), enabled && home.ui.down && home.ui.activeId == subId(CLAIM_ID, 15));
	const right: float32 = banner(home.ui, home.kit, CLAIM_ID, enabled ? BannerArt.Pressable : BannerArt.Display, left, y,
		[{ text: label, colour: enabled ? INK_BRIGHT : INK_MUTED }]);
	plainLook(home.kit);
	const height: float32 = pieceHeight(home.kit, "bannerBody");
	if (pressable(home.ui, subId(CLAIM_ID, 15), left, y, right - left, height) && enabled) {
		home.giftAsked = true;
		requestOwnerAction(OwnerAction.ClaimReward, 0);
	}
}

enum Fondness {
	Cold,
	Warm,
	Fond,
	Devoted,
}

struct HeartHops {
	count: int32;
	height: float32;
	perSecond: float32;
}

function fondnessOf(share: float32): Fondness {
	if (share <= 0.0) { return Fondness.Cold; }
	if (share < FOND_SHARE) { return Fondness.Warm; }
	return share < DEVOTED_SHARE ? Fondness.Fond : Fondness.Devoted;
}

function heartHops(bonding: int32): HeartHops {
	const share: float32 = (bonding as float32) / (GIFT_BONDING as float32);
	return match (fondnessOf(share)) {
		Fondness.Cold => ({ count: 0, height: 0.0, perSecond: 0.0 }),
		Fondness.Warm => ({ count: 1, height: 2.0, perSecond: 0.8 }),
		Fondness.Fond => ({ count: share < (FOND_SHARE + DEVOTED_SHARE) * 0.5 ? 2 : 3, height: 5.0, perSecond: 1.6 }),
		Fondness.Devoted => ({ count: bonding >= GIFT_BONDING ? 6 : 5, height: 9.0, perSecond: 4.0 }),
	};
}

// HEAD_BAR_TALL scene pixels tall with its four corner pixels left out, the pixel-art round end.
function pixelCapsule(ui: Ui, left: float32, top: float32, wide: int32, texel: float32, colour: Color): void {
	const tall: float32 = HEAD_BAR_TALL as float32;
	box(ui, left + texel, top, texel * ((wide - 2) as float32), texel * tall, 0.0, colour);
	box(ui, left, top + texel, texel * (wide as float32), texel * (tall - 2.0), 0.0, colour);
}

// RPG style over the walking Pet: its HP bar, and hearts that hop faster and more the nearer bonding
// is to a gift.
function aboveHead(home: Home, head: Result<PetHead, PetHeadHidden>, hpShare: float32, bonding: int32,
	seconds: float32): void {
	if (!head.ok) { return; }
	const barTop: float32 = headBar(home, head.value, hpShare);
	bondingHearts(home, head.value.x, barTop, bonding, seconds);
}

// Returns the bar's top.
function headBar(home: Home, head: PetHead, hpShare: float32): float32 {
	const texel: float32 = head.texel;
	const barLeft: float32 = (Math.floor(head.x / texel - ((HEAD_BAR_WIDE / 2) as float32)) as float32) * texel;
	const barTop: float32 = (Math.floor(head.y / texel - ((HEAD_BAR_GAP + HEAD_BAR_TALL) as float32)) as float32) * texel;
	pixelCapsule(home.ui, barLeft, barTop, HEAD_BAR_WIDE, texel, HEAD_BAR_TRACK);
	if (hpShare > 0.0) {
		const filled: int32 = Math.max(2, Math.round(hpShare * (HEAD_BAR_WIDE as float32)) as int32);
		pixelCapsule(home.ui, barLeft, barTop, filled, texel, ALERT_RED);
	}
	return barTop;
}

function bondingHearts(home: Home, centreX: float32, barTop: float32, bonding: int32, seconds: float32): void {
	const hops: HeartHops = heartHops(bonding);
	const step: float32 = HEART_SIZE + HEART_GAP;
	const firstX: float32 = centreX - step * ((hops.count - 1) as float32) * 0.5 - HEART_SIZE * 0.5;
	for (let index: int32 = 0; index < hops.count; index += 1) {
		const phase: float64 = ((seconds * hops.perSecond) as float64) * 6.2831853 + (index as float64) * 1.3;
		const lift: float32 = (Math.abs(Math.sin(phase)) as float32) * hops.height;
		const sway: float32 = hops.count > 3 ? (Math.sin(phase * 1.7) as float32) * 1.5 : 0.0;
		iconTinted(home.kit, subId(HEAD_HEARTS_ID, index), "heart", firstX + step * (index as float32) + sway,
			barTop - HEART_GAP - HEART_SIZE - lift, HEART_SIZE, ALERT_RED);
	}
}

function seenOf(pet: GamePet): SeenPet {
	const gear: Item[] = [];
	for (const slot of GEAR_SLOTS) { gear.push(pet.gear.at(slot)); }
	return { generation: pet.lineageGeneration, level: pet.level, gear: gear };
}

// Wear moves with every fight, so it is not a change worth a row.
function sameItem(left: Item, right: Item): boolean {
	return left.rarity == right.rarity && left.stat == right.stat && left.skill == right.skill && left.level == right.level;
}

function logPetChange(home: Home, line: string): void {
	const rows: PetActivity[] = [{ day: 0, glyph: "lock", line: line, amount: 0, slot: NO_NEIGHBOUR }];
	for (const row of home.petChanges) {
		if ((rows.length as int32) < PET_CHANGES_KEPT) { rows.push(row); }
	}
	home.petChanges = rows;
}

// The first read of a Pet, or of its heir, is the baseline and logs nothing.
function notePetChanges(home: Home, pet: GamePet): void {
	const now: SeenPet = seenOf(pet);
	if ((home.seen.length as int32) == 0 || home.seen[0].generation != now.generation) {
		home.seen = [now];
		home.petChanges = [];
		return;
	}
	const before: SeenPet = home.seen[0];
	for (let slot: int32 = 0; slot < PET_SLOTS; slot += 1) {
		const item: Item = now.gear[slot];
		if (sameItem(item, before.gear[slot])) { continue; }
		const part: string = slotName(GEAR_SLOTS[slot]);
		logPetChange(home, item.isEmpty() ? part + " GEAR GONE" : "NEW " + part + " GEAR, " + gearSummary(item));
	}
	if (now.level > before.level) { logPetChange(home, "REACHED LEVEL " + now.level.toString()); }
	home.seen = [now];
}

// The chain records fights only; gear and level changes come from what the app saw while it ran.
function liveActivities(home: Home, block: NeighbourBlock): PetActivity[] {
	const rows: PetActivity[] = [];
	for (const row of home.petChanges) { rows.push(row); }
	for (const row of fightActivities(block)) { rows.push(row); }
	if ((rows.length as int32) > 0) { return rows; }
	return [{ day: 0, glyph: "lock", line: "NO FIGHTS OR CHANGES SEEN YET", amount: 0, slot: NO_NEIGHBOUR }];
}

function toastOutcome(home: Home, outcome: OwnerActionOutcome, status: string): void {
	if (status == "") { return; }
	pushToast(home.toasts, status, outcome != OwnerActionOutcome.SentPending && outcome != OwnerActionOutcome.Requested
		&& outcome != OwnerActionOutcome.ConfirmedAwaitingRead);
}

function settled(outcome: OwnerActionOutcome): boolean {
	return outcome != OwnerActionOutcome.Requested && outcome != OwnerActionOutcome.SentPending;
}

// Each change of the Buy outcome after a Purchase tap is told once, as a toast.
function followPurchase(home: Home): void {
	const outcome = ownerActionOutcome();
	if (!home.buyAsked || outcome == home.buyOutcome) { return; }
	home.buyOutcome = outcome;
	toastOutcome(home, outcome, buyStatus(outcome));
	if (settled(outcome)) { home.buyAsked = false; }
}

// The same for a gift Claim tap.
function followGift(home: Home): void {
	const outcome = ownerActionOutcome();
	if (!home.giftAsked || outcome == home.giftOutcome) { return; }
	home.giftOutcome = outcome;
	toastOutcome(home, outcome, giftStatus(outcome));
	if (settled(outcome)) { home.giftAsked = false; }
}

// Registered before the widgets over the area, so a press that starts on one of them belongs to it.
function pageGesture(home: Home, top: float32, bottom: float32): Gesture {
	if (!pressable(home.ui, PAGE_GESTURE_ID, 0.0, top, DESIGN_W, bottom - top)) { return Gesture.None; }
	const ui = home.ui;
	return gestureOf(home.taps, ui.pressX, ui.pressY, ui.releaseX, ui.releaseY, performance.now() / 1000.0);
}

function homeFrame(home: Home, petHead: Result<PetHead, PetHeadHidden>, seconds: float32): void {
	const block = currentNeighbourBlock();
	const gesturesTop: float32 = TITLE_TOP + TITLE_ROW + VISIT_REACH;
	const gesturesBottom: float32 = DESIGN_H - HOTBAR_HEIGHT - HOTBAR_BOTTOM_PADDING + hotbarTopEdge();
	home.pageGesture = block.ok && canVisit(block.value) && !home.shopOpen && !home.treeShown
		? pageGesture(home, gesturesTop, gesturesBottom)
		: Gesture.None;
	if (block.ok) {
		const visiting = visitedNeighbour(home.visit, block.value);
		if (visiting.ok) {
			neighbourFrame(home, block.value, visiting.value, petHead);
			return;
		}
	}
	const live = currentLivePet();
	home.inventory = live.ok ? liveInventory(live.value) : previewInventory();
	if (live.ok) { notePetChanges(home, live.value); }
	followPurchase(home);
	followGift(home);
	home.ui.blockBase = home.shopOpen;
	const numbers: HomeNumbers = homeNumbers(home);
	const heartMeterShare: Result<float32, HeartCountError> = heartShare(numbers.hearts, numbers.maxHearts);
	if (!heartMeterShare.ok) {
		console.log("Home heart count outside actual maximum");
		unreachable;
	}
	const barTop: float32 = DESIGN_H - HOTBAR_HEIGHT - HOTBAR_BOTTOM_PADDING;
	const tapped: HotbarTap = hotbar(home.ui, home.kit, HOTBAR_ID, barTop, numbers.level, numbers.xp, numbers.xpToNext,
		home.inventory, slotRarities(live.ok ? live.value.gear : previewGear()), true);
	const heldItem: int32 = tapped.held != NO_SLOT && home.inventory[tapped.held] != EMPTY_SLOT ? tapped.held : NO_SLOT;
	if (heldItem != NO_SLOT) {
		itemPeek(home.ui, home.kit, ITEM_CARD_ID, hotbarSlotCentreX(home.kit, heldItem), barTop + hotbarTopEdge() - ITEM_CARD_GAP,
			slotCard(home, heldItem));
	}
	match (tapped.kind) {
		HotbarTapKind.Nothing => {},
		HotbarTapKind.Slot => { onHotbarSlot(home, tapped.slot); },
	};
	if (!home.treeShown) { aboveHead(home, petHead, heartMeterShare.value, numbers.bonding, seconds); }
	characterStats(home.ui, home.kit, CHARACTER_ID, DESIGN_W - COLUMN_RIGHT_PADDING, COLUMNS_TOP, numbers.character);
	const treeToggleTop: float32 = COLUMNS_TOP + STAT_COLUMN_HEIGHT + CHARACTER_STATS_GAP;
	const wallpaperTop: float32 = treeToggleTop + STACKED_ROW_HEIGHT;
	// One action for both: the system picker asks for the home screen, the lock screen or both.
	if (toggleRow(home.ui, home.kit, WALLPAPER_ACTION_ID, DESIGN_W - COLUMN_RIGHT_PADDING, wallpaperTop, STACKED_ROW_HEIGHT,
		WALLPAPER_LABEL, wallpaperPlace() != WallpaperPlace.Off, true)) {
		requestWallpaperPicker();
	}
	// Gone once Android lets the news through; turning it off again is Android's Settings.
	if (numbers.live && !petNewsAllowed() && toggleRow(home.ui, home.kit, PET_NEWS_ID, DESIGN_W - COLUMN_RIGHT_PADDING,
		wallpaperTop + STACKED_ROW_HEIGHT, STACKED_ROW_HEIGHT, PET_NEWS_LABEL, false, true)) {
		requestPetNews();
	}
	if (home.treeShown) { skillTree(home, numbers.character, barTop, numbers.live); }
	const treeLabel: string = numbers.live ? "SKILL TREE" : TREE_LABEL;
	if (toggleRow(home.ui, home.kit, TREE_TOGGLE_ID, DESIGN_W - COLUMN_RIGHT_PADDING, treeToggleTop, STACKED_ROW_HEIGHT, treeLabel,
		home.treeShown, true)) {
		home.treeShown = !home.treeShown;
		closeShop(home);
	}
	titleName(home, numbers.name.toUpperCase(), characterLeaning(numbers.character));
	const none: Banner[] = [];
	const rights: float32[] = wealth(home, numbers, COLUMNS_TOP, live.ok ? petBanners(live.value) : none);
	if (!home.treeShown) {
		const income: Result<uint64, IncomeUnknown> = live.ok ? dailyIncome(live.value) : Result.ok(STAND_IN_HARVEST_PER_DAY);
		if (income.ok) {
			incomeBanner(home, live.ok ? hbrnAmount(income.value) : groupedAmount(income.value), rights[HARVEST_ROW] + CLAIM_GAP);
		}
		if (live.ok) { growthBanner(home, live.value, rights[BURROW_ROW] + CLAIM_GAP); }
	}
	if (live.ok && !home.treeShown) {
		claimBanner(home, live.value, rights[GIFT_ROW] + CLAIM_GAP, COLUMNS_TOP + BANNER_STEP * (GIFT_ROW as float32));
	}
	// Before the log: its scroll area limits the presses of the widgets after it to the log.
	if (block.ok && !home.treeShown) { visitButtons(home, block.value); }
	if (!home.shopOpen && !home.treeShown && heldItem == NO_SLOT) {
		const logBottom: float32 = barTop + hotbarTopEdge() - ACTIVITY_LOG_GAP;
		activityLog(
			home.ui, home.kit, ACTIVITY_LOG_ID, home.activityLog, block.ok ? liveActivities(home, block.value) : STAND_IN_ACTIVITIES,
			ACTIVITY_LOG_X, logBottom, ACTIVITY_LOG_WIDTH, seconds,
		);
	}
	if (home.shopOpen && heldItem == NO_SLOT) { shop(home, barTop); }
	drawToasts(home.ui, home.kit, 60, home.toasts, 16.0, TOASTS_Y, 328.0);
}

function visitPress(home: Home, id: int32, x: float32, width: float32): boolean {
	return pressable(home.ui, id, x - VISIT_REACH, TITLE_TOP - VISIT_REACH, width + VISIT_REACH * 2.0,
		TITLE_ROW + VISIT_REACH * 2.0);
}

function visitHeld(home: Home, id: int32, x: float32, width: float32): boolean {
	return held(home.ui, id, x - VISIT_REACH, TITLE_TOP - VISIT_REACH, width + VISIT_REACH * 2.0,
		TITLE_ROW + VISIT_REACH * 2.0);
}

// "NAME · FIGHTER", the region after the name in its skill-tree colour; smaller when it would not fit.
// "" in the preview leaves the row empty.
function titleName(home: Home, name: string, region: Result<Region, NoLeaning>): void {
	if (name == "") { return; }
	const suffix: string = region.ok ? " · " + regionName(region.value) : "";
	const natural: float32 = measure(home.kit, name + suffix, PET_NAME_SIZE).width;
	const size: float32 = natural > NAME_FIELD_WIDTH ? PET_NAME_SIZE * NAME_FIELD_WIDTH / natural : PET_NAME_SIZE;
	const nameWidth: float32 = measure(home.kit, name, size).width;
	const left: float32 = NAME_FIELD_LEFT + (NAME_FIELD_WIDTH - measure(home.kit, name + suffix, size).width) * 0.5;
	const y: float32 = TITLE_TOP + (TITLE_ROW - size * 0.66) * 0.5 - size * 0.375;
	pressedLook(home.kit, VISIT_HOME_ID, visitHeld(home, VISIT_HOME_ID, NAME_FIELD_LEFT, NAME_FIELD_WIDTH));
	say(home.ui, home.kit, PET_NAME_ID, name, left, y, nameWidth + 2.0, size, INK_BRIGHT, 0.0);
	if (region.ok) {
		say(home.ui, home.kit, PET_REGION_ID, suffix, left + nameWidth, y, NAME_FIELD_WIDTH, size, regionColour(region.value), 0.0);
	}
	plainLook(home.kit);
}

function arrowButton(home: Home, id: int32, art: string, x: float32): boolean {
	pressedLook(home.kit, id, visitHeld(home, id, x, VISIT_BUTTON));
	pieceSized(home.kit, id, PieceLayer.Frames, art, x, TITLE_TOP, VISIT_BUTTON, VISIT_BUTTON);
	plainLook(home.kit);
	return visitPress(home, id, x, VISIT_BUTTON);
}

// < and > walk the owner's home and the living neighbours' homes, as a swipe on the empty middle does; a tap on a
// neighbour's name or a double tap there goes back home.
function visitButtons(home: Home, block: NeighbourBlock): void {
	if (!canVisit(block)) { return; }
	const gesture: Gesture = home.pageGesture;
	const backHome: boolean = (home.visit.seat != HOME_SEAT && visitPress(home, VISIT_HOME_ID, NAME_FIELD_LEFT, NAME_FIELD_WIDTH))
		|| gesture == Gesture.DoubleTap;
	const previous: boolean = arrowButton(home, VISIT_PREVIOUS_ID, "onboardingPrevious", VISIT_LEFT)
		|| gesture == Gesture.SwipeRight;
	const next: boolean = arrowButton(home, VISIT_NEXT_ID, "onboardingNext", NEXT_BUTTON_X) || gesture == Gesture.SwipeLeft;
	if (!backHome && !previous && !next) { return; }
	if (backHome) { visitHome(home.visit); } else { stepVisit(home.visit, block, next); }
	closeShop(home);
	home.treeShown = false;
	home.selectedSkill = -1;
}

// A neighbour's home: its Pet's account read only, nothing of the owner's to buy, gift or claim.
// The scene's Pet stands for the visited one: its HP over its head, no hearts (bonding is with its own owner).
// Over the scene, shaded: the ring with the chosen node's card above the hotbar.
function skillTree(home: Home, character: Character, barTop: float32, live: boolean): void {
	fill(home.kit, TREE_SHADE_ID, 0.0, 0.0, DESIGN_W, DESIGN_H, TREE_SHADE);
	home.selectedSkill = skillRing(home.ui, home.kit, SKILL_RING_ID, DESIGN_W * 0.5, DESIGN_H * 0.475, character,
		home.selectedSkill);
	skillPreview(home.ui, home.kit, SKILL_PREVIEW_ID, barTop + hotbarTopEdge() - INFO_PANEL_HEIGHT - 8.0, home.selectedSkill,
		character.tree, live);
}

function neighbourFrame(home: Home, block: NeighbourBlock, seat: GameNeighbour, petHead: Result<PetHead, PetHeadHidden>): void {
	const barTop: float32 = DESIGN_H - HOTBAR_HEIGHT - HOTBAR_BOTTOM_PADDING;
	const inventory: string[] = neighbourInventory(seat);
	// The Pet account keeps no XP to the next level for a neighbour's bar to show.
	const tapped: HotbarTap = hotbar(home.ui, home.kit, HOTBAR_ID, barTop, seat.level, 0, 0, inventory,
		slotRarities(seat.gear), false);
	const heldItem: int32 = tapped.held != NO_SLOT && inventory[tapped.held] != EMPTY_SLOT ? tapped.held : NO_SLOT;
	if (heldItem != NO_SLOT) {
		itemPeek(home.ui, home.kit, ITEM_CARD_ID, hotbarSlotCentreX(home.kit, heldItem), barTop + hotbarTopEdge() - ITEM_CARD_GAP,
			gearCard(inventory[heldItem], GEAR_SLOTS[heldItem], seat.gear.at(GEAR_SLOTS[heldItem]), true));
	}
	const hearts: Result<float32, HeartCountError> = heartShare(seat.hearts, seat.maxHearts);
	if (!hearts.ok) {
		console.log("Neighbour seat " + seat.seat.toString() + " heart count outside its maximum");
		unreachable;
	}
	if (petHead.ok && !home.treeShown) { headBar(home, petHead.value, hearts.value); }
	const talent: Talent = { kind: seat.talentKind, multiplierBps: seat.talentBps };
	statColumn(home.ui, home.kit, CHARACTER_ID, DESIGN_W - COLUMN_RIGHT_PADDING, COLUMNS_TOP, seat.forage, seat.might, seat.grit,
		talent);
	// Read only: the ring selects a node to read about, nothing to allocate.
	if (home.treeShown) { skillTree(home, { level: seat.level, tree: { bits: seat.tree }, talent: talent }, barTop, true); }
	if (toggleRow(home.ui, home.kit, TREE_TOGGLE_ID, DESIGN_W - COLUMN_RIGHT_PADDING,
		COLUMNS_TOP + STAT_COLUMN_HEIGHT + CHARACTER_STATS_GAP, STACKED_ROW_HEIGHT, "SKILL TREE", home.treeShown, true)) {
		home.treeShown = !home.treeShown;
	}
	titleName(home, neighbourName(seat), leaning(seat.forage, seat.might, seat.grit));
	say(home.ui, home.kit, VISIT_CAPTION_ID, visitCaption(home.visit, block), NAME_FIELD_LEFT, VISIT_CAPTION_Y, NAME_FIELD_WIDTH,
		VISIT_CAPTION_SIZE, HOLO_BLUE, 0.5);
	const none: Banner[] = [];
	wealth(home, { ...homeNumbers(home), live: true, harvest: seat.harvest, burrow: seat.burrow }, COLUMNS_TOP, none);
	visitButtons(home, block);
	if (heldItem == NO_SLOT && !home.treeShown) {
		const logBottom: float32 = barTop + hotbarTopEdge() - ACTIVITY_LOG_GAP;
		neighbourCard(home.ui, home.kit, NEIGHBOUR_CARD_ID, home.visit, block, seat, ACTIVITY_LOG_X, logBottom,
			ACTIVITY_LOG_WIDTH);
	}
	drawToasts(home.ui, home.kit, 60, home.toasts, 16.0, TOASTS_Y, 328.0);
}


// The wallpaper and the lock screen: the scene and the harvest and burrow, nothing to tap.
const WALLPAPER_TITLE_WIDTH: float32 = 300.0;
const WALLPAPER_LEVEL_SIZE: float32 = 11.0;
const WALLPAPER_LEVEL_ROW: float32 = 12.0;
// Where onboarding puts a dead Pet's name and line under its hologram.
const MOURNED_NAME_Y: float32 = 463.0;
const MOURNED_LINE_Y: float32 = 504.0;

export function frameHudWallpaper(petHead: Result<PetHead, PetHeadHidden>, seconds: float32): void {
	if ((homes.length as int32) == 0) {
		return;
	}
	const home: Home = homes[0];
	const live = currentLivePet();
	if (live.ok) { notePetChanges(home, live.value); }
	beginUi(home.ui);
	beginKit(home.kit);
	// A dead Pet shows as the app's death screen does: grey under its name, no stand-in numbers.
	const mourned = mournedPet();
	if (mourned.ok) {
		say(home.ui, home.kit, PET_NAME_ID, mournedName(mourned.value).toUpperCase(), 0.0, MOURNED_NAME_Y, DESIGN_W, 16.0,
			INK_BRIGHT, 0.5);
		say(home.ui, home.kit, PET_REGION_ID, mournedLine(mourned.value), 0.0, MOURNED_LINE_Y, DESIGN_W, 8.0,
			HOLO_BLUE, 0.5);
		endKit(home.kit);
		endUi(home.ui);
		return;
	}
	const numbers: HomeNumbers = homeNumbers(home);
	const titleHeight: float32 = TITLE_HEIGHT + WALLPAPER_LEVEL_ROW;
	const top: float32 = (DESIGN_H - titleHeight - bannersHeight(home.kit, WEALTH_ROWS)) * 0.5;
	if (numbers.name != "") {
		const name: string = numbers.name.toUpperCase();
		const natural: float32 = measure(home.kit, name, PET_NAME_SIZE).width;
		const size: float32 = natural > WALLPAPER_TITLE_WIDTH ? PET_NAME_SIZE * WALLPAPER_TITLE_WIDTH / natural : PET_NAME_SIZE;
		say(home.ui, home.kit, PET_NAME_ID, name, BANNERS_LEFT_PADDING + 8.0, top + PET_NAME_Y, WALLPAPER_TITLE_WIDTH + 2.0,
			size, INK_BRIGHT, 0.0);
		say(home.ui, home.kit, PET_REGION_ID, "LEVEL " + numbers.level.toString(), BANNERS_LEFT_PADDING + 8.0,
			top + PET_NAME_Y + PET_NAME_SIZE * 1.1, WALLPAPER_TITLE_WIDTH, WALLPAPER_LEVEL_SIZE, INK_BRIGHT, 0.0);
	}
	const none: Banner[] = [];
	wealth(home, numbers, top + titleHeight, none);
	const hearts: Result<float32, HeartCountError> = heartShare(numbers.hearts, numbers.maxHearts);
	if (live.ok && hearts.ok) { aboveHead(home, petHead, hearts.value, numbers.bonding, seconds); }
	endKit(home.kit);
	endUi(home.ui);
}

export function frameHudWaiting(status: string): void {
	if ((homes.length as int32) == 0) {
		return;
	}
	const home: Home = homes[0];
	beginUi(home.ui);
	beginKit(home.kit);
	home.ui.blockBase = false;
	waitingLine(home.ui, home.kit, 3000, status);
	endKit(home.kit);
	endUi(home.ui);
}

export function frameHudOnboarding(): void {
	if ((homes.length as int32) == 0) {
		return;
	}
	const home: Home = homes[0];
	beginUi(home.ui);
	beginKit(home.kit);
	home.ui.blockBase = false;
	home.onboardingNameId = onboarding(home.ui, home.kit, 3000, home.onboardingNameId);
	endKit(home.kit);
	endUi(home.ui);
}

export function frameHudHome(petHead: Result<PetHead, PetHeadHidden>, seconds: float32): void {
	if ((homes.length as int32) == 0) {
		return;
	}
	const home: Home = homes[0];
	beginUi(home.ui);
	beginKit(home.kit);
	home.ui.blockBase = false;
	homeFrame(home, petHead, seconds);
	endKit(home.kit);
	endUi(home.ui);
}
