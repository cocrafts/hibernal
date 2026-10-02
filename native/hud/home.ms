// Home over the scene, and the screens the dock and the gear open. The pet's numbers are a
// stand-in until the chain client exists.

import { rgba } from "@metascript/void/src/void2d/types";
import { loadNextPass } from "@metascript/void/src/sokol/gpu";
import { Ui, createUi, beginUi, endUi, box, pressable } from "@metascript/void/src/ui/ui";
import { Kit, createKit, beginKit, endKit, frame, badgeFrame, icon, say, INK, INK_MUTED, EMBER, EMBER_HOT, ALERT_RED,
	SCREEN_HEIGHT } from "./kit";
import { FrameLook } from "./frame";
import { ButtonStyle, SignState, ChipKind, button, textLink, signButton, chip, badge } from "./buttons";
import { heartPips, bar, bondingBar, balance } from "./meters";
import { Toasts, emptyToasts, pushToast, drawToasts, tooltip, reasonPill, walletBanner, syncChip } from "./notices";
import { sheet, sheetTop } from "./overlays";
import { DockTab, DockError, dock } from "./navigation";
import { chatBubble, chatInput } from "./chat";
import { CHAR_LIGHT } from "./shapes";
import { Signing, idleSigning, startSigning, advanceSigning } from "./signing";
import { Nav, ScreenContext, openOverlay, closeOverlay } from "./screenChrome";
import { screenFrame } from "./screens";

const MAX_HEARTS: int32 = 10;
const MAX_TALKS: int32 = 5;
const MAX_BONDING: int32 = 127;
const FEED_BONDING: int32 = 6;
const TALK_BONDING: int32 = 4;
const LOW_HEARTS: int32 = 2;
const SHOWN_FRAMES: int32 = 120;
const SHEET_EASE: float32 = 0.25;
const FEED_SHEET_HEIGHT: float32 = 360.0;
const TALK_SHEET_HEIGHT: float32 = 700.0;
const SHOWN_MESSAGES: int32 = 6;
const NO_PORTION: int32 = -1;

enum Sheet {
	None,
	Feed,
	Talk,
}

interface Portion {
	name: string;
	hearts: int32;
	price: int32;
}

interface StatusBadge {
	glyph: string;
	number: string;
	tip: string;
}

interface ChatLine {
	line: string;
	byOwner: boolean;
	counted: boolean;
}

const PORTIONS: Portion[] = [
	{ name: "SMALL", hearts: 1, price: 5 },
	{ name: "MEDIUM", hearts: 2, price: 9 },
	{ name: "LARGE", hearts: 3, price: 12 },
];
const BADGES: StatusBadge[] = [
	{ glyph: "winter", number: "12", tip: "WINTER IN 12 DAYS - EMISSION X0.75" },
	{ glyph: "growth", number: "X1.1", tip: "GROWTH X1.10 - 18H LEFT" },
	{ glyph: "insured", number: "", tip: "INSURED - REVIVES ONCE AT 3 HEARTS" },
];
const DRAFTS: string[] = ["STAY CLOSE TO THE FIRE.", "GOOD NIGHT.", "DON'T PICK FIGHTS TONIGHT."];
const REPLIES: string[] = ["I WILL. THE WIND IS COLD.", "NIGHT. WAKE ME AT DAWN.", "ONLY IF THEY START IT."];

interface Home {
	ui: Ui;
	kit: Kit;
	toasts: Toasts;
	tick: int32;
	screen: Nav;
	galleryAsked: boolean;
	hearts: int32;
	talks: int32;
	harvest: int32;
	burrow: int32;
	bonding: int32;
	expandedUntil: int32;
	tip: string;
	tipY: float32;
	tipUntil: int32;
	openSheet: Sheet;
	sheetOpen: float32;
	// a screen's own sheet or modal, as of the last frame
	screenOverlayOpen: boolean;
	feedPortion: int32;
	feedSigning: Signing;
	chat: ChatLine[];
	draft: string;
	draftsUsed: int32;
}

// Made by initHudHome; a list so that frameHudHome can run before it without a null.
const homes: Home[] = [];

export function initHudHome(): void {
	const ui: Ui = createUi(rgba(0.0, 0.0, 0.0, 1.0));
	const home: Home = {
		ui: ui,
		kit: createKit(ui),
		toasts: emptyToasts(),
		tick: 0,
		screen: Nav.Home,
		galleryAsked: false,
		hearts: 7,
		talks: 3,
		harvest: 1240,
		burrow: 5600,
		bonding: 40,
		expandedUntil: 0,
		tip: "",
		tipY: 0.0,
		tipUntil: 0,
		openSheet: Sheet.None,
		sheetOpen: 0.0,
		screenOverlayOpen: false,
		feedPortion: NO_PORTION,
		feedSigning: idleSigning(),
		chat: [
			{ line: "DID YOU EAT TODAY?", byOwner: true, counted: true },
			{ line: "ATE A LITTLE. THE FIRE IS WARM.", byOwner: false, counted: false },
		],
		draft: "",
		draftsUsed: 0,
	};
	pushToast(home.toasts, "MOVED 620 TO BURROW - NEXT IN 8H", false);
	homes.push(home);
}

export function takeGalleryRequest(): boolean {
	if ((homes.length as int32) == 0) {
		return false;
	}
	const asked: boolean = homes[0].galleryAsked;
	homes[0].galleryAsked = false;
	return asked;
}

function grouped(amount: int32): string {
	if (amount < 1000) {
		return amount.toString();
	}
	const rest: int32 = amount % 1000;
	const padding: string = rest < 10 ? "00" : (rest < 100 ? "0" : "");
	return (amount / 1000).toString() + "," + padding + rest.toString();
}

function capped(value: int32, cap: int32): int32 {
	return value > cap ? cap : value;
}

function heartsLine(home: Home): string {
	return home.hearts.toString() + "/" + MAX_HEARTS.toString();
}

function expandedCard(home: Home, alert: boolean): void {
	const ui: Ui = home.ui;
	const kit: Kit = home.kit;
	frame(kit, 10, 16.0, 32.0, 272.0, 220.0, 12, alert ? FrameLook.Alert : FrameLook.Normal);
	say(ui, kit, 11, "EMBER", 32.0, 48.0, 160.0, 16.0, INK, 0.0);
	say(ui, kit, 12, "TAP SCENE X", 180.0, 52.0, 92.0, 8.0, INK_MUTED, 1.0);
	say(ui, kit, 13, "LV 12 / 20", 32.0, 74.0, 120.0, 8.0, INK, 0.0);
	say(ui, kit, 14, "620 / 1,000 XP", 140.0, 74.0, 132.0, 8.0, INK_MUTED, 1.0);
	bar(ui, 32.0, 86.0, 240.0, 6.0, 0.62, EMBER);
	heartPips(ui, kit, 15, 32.0, 100.0, home.hearts, MAX_HEARTS, 12.0);
	say(ui, kit, 16, heartsLine(home), 200.0, 102.0, 72.0, 8.0, INK, 1.0);
	balance(ui, kit, 17, 32.0, 122.0, 240.0, "bag", "warning", grouped(home.harvest));
	say(ui, kit, 18, "AT RISK - NEIGHBOURS CAN STEAL IT", 52.0, 138.0, 220.0, 8.0, INK_MUTED, 0.0);
	balance(ui, kit, 19, 32.0, 154.0, 240.0, "lock", "", grouped(home.burrow));
	say(ui, kit, 20, "BANKED - SAFE", 52.0, 170.0, 220.0, 8.0, INK_MUTED, 0.0);
	let chipX: float32 = 32.0;
	chipX += chip(ui, kit, 21, chipX, 190.0, "DAY 34/90", ChipKind.Outline, INK) + 4.0;
	chipX += chip(ui, kit, 22, chipX, 190.0, "WINTER 12D", ChipKind.Outline, INK) + 4.0;
	chip(ui, kit, 23, chipX, 190.0, "GROWTH X1.10", ChipKind.Filled, EMBER);
	chip(ui, kit, 24, 32.0, 210.0, "INSURED", ChipKind.Outline, INK);
	if (pressable(ui, 25, 16.0, 32.0, 272.0, 220.0)) {
		home.expandedUntil = 0;
	}
}

// Tapped, it expands for a while or until the scene is tapped.
function statusCard(home: Home): void {
	const ui: Ui = home.ui;
	const kit: Kit = home.kit;
	const alert: boolean = home.hearts <= LOW_HEARTS;
	if (home.tick < home.expandedUntil) {
		expandedCard(home, alert);
		return;
	}
	frame(kit, 10, 16.0, 32.0, 150.0, 104.0, 11, alert ? FrameLook.Alert : FrameLook.Normal);
	icon(kit, 30, "heart", 34.0, 50.0, 14.0);
	say(ui, kit, 30, heartsLine(home), 62.0, 54.0, 90.0, 8.0, alert ? ALERT_RED : INK, 0.0);
	icon(kit, 31, "bag", 34.0, 68.0, 14.0);
	icon(kit, 31, "warning", 41.0, 74.0, 9.0);
	say(ui, kit, 31, grouped(home.harvest), 62.0, 72.0, 90.0, 8.0, INK, 0.0);
	icon(kit, 32, "lock", 34.0, 86.0, 14.0);
	say(ui, kit, 32, grouped(home.burrow), 62.0, 90.0, 90.0, 8.0, INK, 0.0);
	box(ui, 32.0, 105.0, 118.0, 1.0, 0.0, CHAR_LIGHT);
	say(ui, kit, 33, "LV12", 34.0, 113.0, 30.0, 8.0, INK, 0.0);
	bar(ui, 62.0, 114.0, 56.0, 5.0, 0.62, EMBER);
	say(ui, kit, 34, "D34", 100.0, 113.0, 48.0, 8.0, INK, 1.0);
	if (pressable(ui, 35, 16.0, 32.0, 150.0, 104.0)) {
		home.expandedUntil = home.tick + SHOWN_FRAMES;
	}
	if (alert) {
		reasonPill(ui, kit, 36, 16.0, 142.0, "HEARTS LOW - FEED OR IT STARVES", true);
	}
}

// A tapped badge explains itself in a tooltip.
function badges(home: Home): void {
	const ui: Ui = home.ui;
	const kit: Kit = home.kit;
	badgeFrame(kit, 40, 308.0, 34.0, 36.0, 41);
	icon(kit, 40, "gear", 316.0, 42.0, 20.0);
	if (pressable(ui, 40, 300.0, 28.0, 52.0, 48.0)) {
		home.screen = Nav.Settings;
	}
	for (let position: int32 = 0; position < BADGES.length; position += 1) {
		const shown: StatusBadge = BADGES[position];
		const y: float32 = 84.0 + (position as float32) * 48.0;
		if (badge(ui, kit, 41 + position, 304.0, y, shown.glyph, shown.number, 50 + position)) {
			home.tip = shown.tip;
			home.tipY = y + 20.0;
			home.tipUntil = home.tick + SHOWN_FRAMES;
		}
	}
	syncChip(ui, kit, 45, 252.0, 232.0, "SYNCING...", true, home.tick);
	if (home.tick < home.tipUntil) {
		tooltip(ui, kit, 46, 300.0, home.tipY, home.tip);
	}
}

function portionState(home: Home, position: int32): SignState {
	const fits: boolean = home.hearts + PORTIONS[position].hearts <= MAX_HEARTS;
	return match (position) {
		_ when position == home.feedPortion => home.feedSigning.state,
		_ when home.feedPortion != NO_PORTION || !fits => SignState.Disabled,
		_ => SignState.Idle,
	};
}

function fed(home: Home): void {
	const portion: Portion = PORTIONS[home.feedPortion];
	home.hearts = capped(home.hearts + portion.hearts, MAX_HEARTS);
	home.bonding = capped(home.bonding + FEED_BONDING, MAX_BONDING);
	pushToast(home.toasts, "FED " + portion.name + " - +" + portion.hearts.toString() + " HEARTS", false);
}

function feedSheet(home: Home, top: float32): void {
	const ui: Ui = home.ui;
	const kit: Kit = home.kit;
	say(ui, kit, 100, "FEED", 32.0, top + 28.0, 200.0, 16.0, INK, 0.0);
	heartPips(ui, kit, 101, 32.0, top + 52.0, home.hearts, MAX_HEARTS, 14.0);
	say(ui, kit, 102, heartsLine(home), 230.0, top + 55.0, 98.0, 8.0, INK, 1.0);
	if (advanceSigning(home.feedSigning, home.tick)) {
		fed(home);
	}
	if (home.feedSigning.state == SignState.Idle) {
		home.feedPortion = NO_PORTION;
	}
	for (let position: int32 = 0; position < PORTIONS.length; position += 1) {
		const portion: Portion = PORTIONS[position];
		const y: float32 = top + 84.0 + (position as float32) * 64.0;
		say(ui, kit, 110 + position, portion.name, 32.0, y + 10.0, 140.0, 8.0, INK, 0.0);
		say(ui, kit, 120 + position, "+" + portion.hearts.toString() + " HEARTS", 32.0, y + 26.0, 140.0, 8.0, INK_MUTED, 0.0);
		if (signButton(ui, kit, 130 + position, 180.0, y, 148.0, 44.0, "BUY " + portion.price.toString() + " SKR",
			portionState(home, position), 60 + position, home.tick)) {
			home.feedPortion = position;
			startSigning(home.feedSigning, home.tick);
		}
	}
	if (home.feedSigning.state == SignState.Waiting) {
		const portion: Portion = PORTIONS[home.feedPortion];
		walletBanner(ui, kit, 140, 16.0, top + 282.0, 328.0,
			portion.name + " - +" + portion.hearts.toString() + " HEARTS - " + portion.price.toString() + " SKR", 64, home.tick);
	} else {
		say(ui, kit, 141, home.hearts >= MAX_HEARTS ? "HEARTS FULL - NOTHING TO FEED" : "FEEDING RAISES BONDING.", 32.0, top + 296.0,
			296.0, 8.0, INK_MUTED, 0.0);
	}
}

// A stand-in for typing: a tap on the field fills in the next draft, and the pet answers it.
function send(home: Home): void {
	const counts: boolean = home.talks > 0;
	home.chat.push({ line: home.draft, byOwner: true, counted: counts });
	home.chat.push({ line: REPLIES[home.draftsUsed % REPLIES.length], byOwner: false, counted: false });
	if (counts) {
		home.talks -= 1;
		home.bonding = capped(home.bonding + TALK_BONDING, MAX_BONDING);
	}
	home.draftsUsed += 1;
	home.draft = "";
}

function talkSheet(home: Home, top: float32): void {
	const ui: Ui = home.ui;
	const kit: Kit = home.kit;
	say(ui, kit, 200, "TALK", 32.0, top + 28.0, 120.0, 16.0, INK, 0.0);
	say(ui, kit, 201, "EMBER - LV 12", 110.0, top + 34.0, 120.0, 8.0, INK_MUTED, 0.0);
	bondingBar(ui, kit, 202, 32.0, top + 60.0, 296.0, home.bonding);
	const counting: boolean = home.talks > 0;
	say(ui, kit, 203, counting ? "TALKS THAT COUNT TODAY: " + home.talks.toString() + "/" + MAX_TALKS.toString() : "NO MORE BONDING TODAY",
		32.0, top + 88.0, 296.0, 8.0, counting ? EMBER_HOT : INK_MUTED, 0.0);
	let y: float32 = top + 108.0;
	const total: int32 = home.chat.length as int32;
	const first: int32 = total > SHOWN_MESSAGES ? total - SHOWN_MESSAGES : 0;
	for (let position: int32 = first; position < total; position += 1) {
		const message: ChatLine = home.chat[position];
		y += chatBubble(ui, kit, 210 + position * 4, 24.0, 336.0, y, message.line, message.byOwner, message.counted, 70);
	}
	const inputY: float32 = SCREEN_HEIGHT - 70.0;
	if (pressable(ui, 250, 24.0, inputY, 220.0, 44.0)) {
		home.draft = DRAFTS[home.draftsUsed % DRAFTS.length];
	}
	if (chatInput(ui, kit, 251, 24.0, inputY, 312.0, home.draft, 71)) {
		send(home);
	}
}

function sheets(home: Home): void {
	const ui: Ui = home.ui;
	const kit: Kit = home.kit;
	const wanted: float32 = home.openSheet != Sheet.None ? 1.0 : 0.0;
	home.sheetOpen = home.sheetOpen + (wanted - home.sheetOpen) * SHEET_EASE;
	if (home.sheetOpen <= 0.01 && home.openSheet == Sheet.None) {
		return;
	}
	const talking: boolean = home.openSheet == Sheet.Talk;
	const height: float32 = talking ? TALK_SHEET_HEIGHT : FEED_SHEET_HEIGHT;
	const signing: boolean = home.feedSigning.state == SignState.Waiting;
	if (sheet(ui, kit, 90, height, home.sheetOpen, talking ? 92 : 91) && !signing) {
		home.openSheet = Sheet.None;
	}
	const top: float32 = sheetTop(height, home.sheetOpen);
	if (textLink(ui, kit, 95, 284.0, top + 32.0, "CLOSE", !signing)) {
		home.openSheet = Sheet.None;
	}
	match (home.openSheet) {
		Sheet.Feed => feedSheet(home, top),
		Sheet.Talk => talkSheet(home, top),
		Sheet.None => {},
	};
	closeOverlay(ui, kit);
}

function navFor(tab: DockTab): Nav {
	return match (tab) {
		DockTab.Home => Nav.Home,
		DockTab.Pet => Nav.Pet,
		DockTab.Block => Nav.Block,
		DockTab.Shop => Nav.Shop,
		DockTab.Digest => Nav.Digest,
	};
}

function dockTabFor(screen: Nav): DockTab {
	return match (screen) {
		Nav.Pet => DockTab.Pet,
		Nav.Block => DockTab.Block,
		Nav.Shop => DockTab.Shop,
		Nav.Digest => DockTab.Digest,
		_ => DockTab.Home,
	};
}

function homeFrame(home: Home): void {
	const ui: Ui = home.ui;
	// A tap on the scene collapses the expanded card.
	if (home.tick < home.expandedUntil && ui.released && ui.releaseY > 260.0 && ui.releaseY < 600.0) {
		home.expandedUntil = 0;
	}
	statusCard(home);
	badges(home);
	drawToasts(ui, home.kit, 60, home.toasts, 16.0, 612.0, 328.0);
	if (button(ui, home.kit, 70, 16.0, 668.0, 156.0, 48.0, "FEED", ButtonStyle.Primary, true, 21)) {
		home.openSheet = Sheet.Feed;
	}
	if (button(ui, home.kit, 71, 188.0, 668.0, 156.0, 48.0, "TALK " + home.talks.toString() + "/" + MAX_TALKS.toString(),
		ButtonStyle.Primary, true, 22)) {
		home.openSheet = Sheet.Talk;
	}
	const tapped: Result<DockTab, DockError> = dock(ui, home.kit, 80, DockTab.Home, true, 31);
	if (tapped.ok) {
		home.screen = navFor(tapped.value);
	}
	sheets(home);
}

// The screen scrolls under the toasts and the dock, so they go on the overlay.
function screenOfHome(home: Home): void {
	const context: ScreenContext = {
		ui: home.ui,
		kit: home.kit,
		toasts: home.toasts,
		tick: home.tick,
		navigate: Nav.Stay,
		overlayOpen: false,
	};
	screenFrame(context, home.screen);
	home.screenOverlayOpen = context.overlayOpen;
	openOverlay(home.ui, home.kit);
	drawToasts(home.ui, home.kit, 61, home.toasts, 16.0, 676.0, 328.0);
	if (home.screen != Nav.Settings) {
		const tapped: Result<DockTab, DockError> = dock(home.ui, home.kit, 81, dockTabFor(home.screen), true, 32);
		if (tapped.ok) {
			home.screen = navFor(tapped.value);
		}
	}
	closeOverlay(home.ui, home.kit);
	match (context.navigate) {
		Nav.Stay => {},
		Nav.Gallery => {
			home.galleryAsked = true;
			home.screen = Nav.Home;
		},
		_ => {
			home.screen = context.navigate;
		},
	};
}

export function frameHudHome(): void {
	if ((homes.length as int32) == 0) {
		return;
	}
	const home: Home = homes[0];
	beginUi(home.ui);
	beginKit(home.kit);
	home.tick += 1;
	home.ui.blockBase = home.openSheet != Sheet.None || (home.screen != Nav.Home && home.screenOverlayOpen);
	if (home.screen == Nav.Home) {
		homeFrame(home);
	} else {
		screenOfHome(home);
	}
	endKit(home.kit);
	loadNextPass();
	endUi(home.ui);
}
