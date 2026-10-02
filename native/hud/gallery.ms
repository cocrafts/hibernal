// Every kit piece, a page at a time, to review on the phone. Tapping the title goes back to Home.

import { rgba } from "@metascript/void/src/void2d/types";
import { loadNextPass } from "@metascript/void/src/sokol/gpu";
import { Ui, createUi, beginUi, endUi, pressable, held } from "@metascript/void/src/ui/ui";
import { Kit, createKit, beginKit, endKit, frame, badgeFrame, icon, say, INK, INK_MUTED, EMBER, EMBER_HOT, EMBER_PRESSED, ALERT_RED,
	GROWTH_GREEN } from "./kit";
import { FrameLook } from "./frame";
import { ButtonStyle, SignState, ChipKind, button, textLink, signButton, chip, badge } from "./buttons";
import { heartPips, bar, bondingBar, balance, delta } from "./meters";
import { Rarity, rarityPlate, rarityChip, RARE_BLUE, EPIC_PURPLE, LEGENDARY_GOLD, MYTHIC_CYAN, COMMON_ASH } from "./rarity";
import { ToggleState, toggle, segmented, tabs, radioRow } from "./controls";
import { RowKind, listRow, sectionHeader, labelDivider, skeleton, emptyState } from "./rows";
import { Toasts, emptyToasts, pushToast, drawToasts, tooltip, reasonPill, walletBanner, syncChip } from "./notices";
import { ModalAnswer, sheet, sheetTop, modal } from "./overlays";
import { DockTab, DockError, dock, pager } from "./navigation";
import { chatBubble, chatInput } from "./chat";
import { LineageState, lineageEntry } from "./lineage";
import { talentCard, gradeLadder } from "./talent";
import { NodeShape, NodeState, treeNode, treeLink } from "./skillTree";
import { OddsState, oddsBlock } from "./odds";
import { Signing, idleSigning, startSigning, advanceSigning } from "./signing";
import { closeOverlay } from "./screenChrome";

const SHEET_EASE: float32 = 0.25;
const FLIP_EASE: float32 = 0.12;
const NO_NODE: int32 = -1;
const ICONS: string[] = ["heart", "bag", "lock", "warning", "winter", "growth", "insured", "gear", "home", "pet", "block", "shop",
	"digest"];
const PAGER_LABELS: string[] = ["SLOT 4 - THREAT", "SLOT 7 - THREAT", "SLOT 10 - THREAT", "SLOT 2 - THREAT"];
const ODDS_STATES: OddsState[] = [OddsState.Ready, OddsState.Computing, OddsState.NotAttackable];

export enum GalleryPage {
	Frames,
	Basics,
	Controls,
	Overlays,
	PetViews,
	Odds,
}

const PAGES: GalleryPage[] = [GalleryPage.Frames, GalleryPage.Basics, GalleryPage.Controls, GalleryPage.Overlays,
	GalleryPage.PetViews, GalleryPage.Odds];

interface DemoNode {
	x: float32;
	y: float32;
	shape: NodeShape;
	state: NodeState;
	name: string;
}

interface DemoLink {
	from: int32;
	to: int32;
}

// A gate, a fork, a notable and a keystone.
const DEMO_NODES: DemoNode[] = [
	{ x: 180.0, y: 700.0, shape: NodeShape.Notable, state: NodeState.Allocated, name: "GATE" },
	{ x: 120.0, y: 650.0, shape: NodeShape.Small, state: NodeState.Allocated, name: "IRON HIDE" },
	{ x: 240.0, y: 650.0, shape: NodeShape.Small, state: NodeState.Reachable, name: "QUICK HANDS" },
	{ x: 80.0, y: 600.0, shape: NodeShape.Notable, state: NodeState.Allocated, name: "BRAWLER" },
	{ x: 150.0, y: 600.0, shape: NodeShape.Small, state: NodeState.Reachable, name: "SCAVENGER" },
	{ x: 210.0, y: 600.0, shape: NodeShape.Small, state: NodeState.Locked, name: "WARDEN" },
	{ x: 280.0, y: 600.0, shape: NodeShape.Small, state: NodeState.Locked, name: "LOOKOUT" },
	{ x: 180.0, y: 556.0, shape: NodeShape.Keystone, state: NodeState.Reachable, name: "BLOOD OATH" },
];
const DEMO_LINKS: DemoLink[] = [
	{ from: 0, to: 1 }, { from: 0, to: 2 }, { from: 1, to: 3 }, { from: 1, to: 4 }, { from: 2, to: 5 }, { from: 2, to: 6 },
	{ from: 4, to: 7 }, { from: 5, to: 7 },
];

interface Gallery {
	ui: Ui;
	kit: Kit;
	tick: int32;
	page: int32;
	homeAsked: boolean;
	seedShift: int32;
	hearts: int32;
	bonding: int32;
	signing: Signing;
	toggleOn: boolean;
	segment: int32;
	tab: int32;
	radio: int32;
	row: int32;
	toasts: Toasts;
	toastsPushed: int32;
	pagerPage: int32;
	dockTab: DockTab;
	sheetWanted: boolean;
	sheetOpen: float32;
	modalOpen: boolean;
	chatText: string;
	cardFlip: float32;
	cardTarget: float32;
	pickedNode: int32;
	oddsState: int32;
}

const galleries: Gallery[] = [];

export function initGallery(): void {
	const ui: Ui = createUi(rgba(0.0, 0.0, 0.0, 1.0));
	galleries.push({
		ui: ui,
		kit: createKit(ui),
		tick: 0,
		page: 0,
		homeAsked: false,
		seedShift: 0,
		hearts: 7,
		bonding: 35,
		signing: idleSigning(),
		toggleOn: true,
		segment: 0,
		tab: 0,
		radio: 1,
		row: 1,
		toasts: emptyToasts(),
		toastsPushed: 0,
		pagerPage: 0,
		dockTab: DockTab.Home,
		sheetWanted: false,
		sheetOpen: 0.0,
		modalOpen: false,
		chatText: "",
		cardFlip: 0.0,
		cardTarget: 0.0,
		pickedNode: NO_NODE,
		oddsState: 0,
	});
}

export function takeHomeRequest(): boolean {
	if ((galleries.length as int32) == 0) {
		return false;
	}
	const asked: boolean = galleries[0].homeAsked;
	galleries[0].homeAsked = false;
	return asked;
}

function pageTitle(page: GalleryPage): string {
	return match (page) {
		GalleryPage.Frames => "UI KIT - FRAMES",
		GalleryPage.Basics => "UI KIT - BASICS",
		GalleryPage.Controls => "UI KIT - CONTROLS",
		GalleryPage.Overlays => "UI KIT - OVERLAYS",
		GalleryPage.PetViews => "UI KIT - PET VIEWS",
		GalleryPage.Odds => "UI KIT - ODDS",
	};
}

function framesPage(gallery: Gallery): void {
	const ui: Ui = gallery.ui;
	const kit: Kit = gallery.kit;
	const shift: int32 = gallery.seedShift;
	for (let panel: int32 = 0; panel < 2; panel += 1) {
		const x: float32 = 16.0 + (panel as float32) * 172.0;
		frame(kit, 10 + panel, x, 76.0, 156.0, 96.0, 1 + panel + shift, FrameLook.Normal);
		say(ui, kit, 10 + panel, "SEED " + (1 + panel + shift).toString(), x + 14.0, 88.0, 128.0, 8.0, INK, 0.0);
		if (pressable(ui, 10 + panel, x, 76.0, 156.0, 96.0)) {
			gallery.seedShift += 2;
		}
	}
	frame(kit, 12, 16.0, 190.0, 156.0, 70.0, 3 + shift, FrameLook.Alert);
	say(ui, kit, 12, "ALERT", 30.0, 202.0, 128.0, 8.0, INK, 0.0);
	frame(kit, 13, 188.0, 190.0, 156.0, 70.0, 4 + shift, FrameLook.Disabled);
	say(ui, kit, 13, "DISABLED", 202.0, 202.0, 128.0, 8.0, INK_MUTED, 0.0);
	frame(kit, 14, 16.0, 278.0, 328.0, 56.0, 5 + shift, FrameLook.Normal);
	say(ui, kit, 14, "WIDE 328 X 56", 30.0, 300.0, 300.0, 8.0, INK, 0.0);
	frame(kit, 15, 16.0, 352.0, 100.0, 170.0, 6 + shift, FrameLook.Normal);
	say(ui, kit, 15, "TALL", 30.0, 364.0, 80.0, 8.0, INK, 0.0);
	for (let position: int32 = 0; position < 2; position += 1) {
		const x: float32 = 132.0 + (position as float32) * 108.0;
		const id: int32 = 20 + position;
		const enabled: boolean = position == 0;
		const down: boolean = held(ui, id, x, 352.0, 100.0, 48.0);
		pressable(ui, id, x, 352.0, 100.0, 48.0);
		frame(kit, id, x, 352.0, 100.0, 48.0, 20 + position + shift, enabled ? FrameLook.Normal : FrameLook.Disabled);
		say(ui, kit, id, enabled ? "PRESS" : "OFF", x, 370.0 + (down ? 1.0 : 0.0), 100.0, 8.0,
			!enabled ? INK_MUTED : (down ? EMBER_PRESSED : EMBER_HOT), 0.5);
	}
	const badgeIcons: string[] = ["gear", "winter", "growth", "insured"];
	for (let position: int32 = 0; position < badgeIcons.length; position += 1) {
		const x: float32 = 132.0 + (position as float32) * 54.0;
		badgeFrame(kit, 30 + position, x, 420.0, 40.0, 30 + position);
		icon(kit, 30 + position, badgeIcons[position], x + 10.0, 430.0, 20.0);
	}
	say(ui, kit, 40, "ICONS", 16.0, 540.0, 200.0, 8.0, INK_MUTED, 0.0);
	for (let position: int32 = 0; position < ICONS.length; position += 1) {
		icon(kit, 41 + position, ICONS[position], 16.0 + ((position % 7) as float32) * 48.0, 556.0 + ((position / 7) as float32) * 40.0, 24.0);
	}
	say(ui, kit, 50, "RARITY - PLATE AND CHIP", 16.0, 628.0, 300.0, 8.0, INK_MUTED, 0.0);
	rarityPlate(ui, kit, 51, 16.0, 644.0, 104.0, 40.0, Rarity.Common);
	rarityPlate(ui, kit, 52, 128.0, 644.0, 104.0, 40.0, Rarity.Rare);
	rarityPlate(ui, kit, 53, 240.0, 644.0, 104.0, 40.0, Rarity.Epic);
	rarityPlate(ui, kit, 54, 16.0, 694.0, 160.0, 40.0, Rarity.Legendary);
	rarityPlate(ui, kit, 55, 184.0, 694.0, 160.0, 40.0, Rarity.Mythic);
	const rarities: Rarity[] = [Rarity.Common, Rarity.Rare, Rarity.Epic, Rarity.Legendary, Rarity.Mythic];
	let chipX: float32 = 16.0;
	for (let position: int32 = 0; position < rarities.length; position += 1) {
		chipX += rarityChip(ui, kit, 56 + position, chipX, 748.0, rarities[position]) + 6.0;
	}
}

function basicsPage(gallery: Gallery): void {
	const ui: Ui = gallery.ui;
	const kit: Kit = gallery.kit;
	const tick: int32 = gallery.tick;
	if (button(ui, kit, 100, 16.0, 76.0, 156.0, 48.0, "FEED", ButtonStyle.Primary, gallery.hearts < 10, 101)) {
		gallery.hearts += 1;
	}
	button(ui, kit, 102, 188.0, 76.0, 156.0, 48.0, "DISCONNECT", ButtonStyle.Danger, true, 103);
	if (textLink(ui, kit, 104, 28.0, 142.0, "RESET HEARTS", true)) {
		gallery.hearts = 3;
	}
	button(ui, kit, 105, 188.0, 132.0, 156.0, 40.0, "FEED", ButtonStyle.Primary, false, 106);
	advanceSigning(gallery.signing, tick);
	if (signButton(ui, kit, 110, 16.0, 188.0, 156.0, 44.0, "BUY 9 SKR", gallery.signing.state, 111, tick)) {
		startSigning(gallery.signing, tick);
	}
	signButton(ui, kit, 112, 188.0, 188.0, 156.0, 44.0, "BUY", SignState.Waiting, 113, tick);
	signButton(ui, kit, 114, 16.0, 244.0, 156.0, 44.0, "BUY", SignState.Done, 115, tick);
	signButton(ui, kit, 116, 188.0, 244.0, 156.0, 44.0, "BUY", SignState.Failed, 117, tick);
	signButton(ui, kit, 118, 16.0, 300.0, 156.0, 44.0, "BUY 9 SKR", SignState.Disabled, 119, tick);
	say(ui, kit, 120, "TAP THE FIRST ONE", 188.0, 318.0, 156.0, 8.0, INK_MUTED, 0.0);
	let chipX: float32 = 16.0;
	chipX += chip(ui, kit, 130, chipX, 362.0, "SHIELD 2D", ChipKind.Outline, INK) + 6.0;
	chipX += chip(ui, kit, 131, chipX, 362.0, "GROWTH X1.1", ChipKind.Filled, EMBER) + 6.0;
	chip(ui, kit, 132, chipX, 362.0, "FADING", ChipKind.Dashed, INK_MUTED);
	chipX = 16.0;
	chipX += chip(ui, kit, 133, chipX, 384.0, "COMMON", ChipKind.Outline, COMMON_ASH) + 6.0;
	chipX += chip(ui, kit, 134, chipX, 384.0, "RARE", ChipKind.Outline, RARE_BLUE) + 6.0;
	chipX += chip(ui, kit, 135, chipX, 384.0, "EPIC", ChipKind.Outline, EPIC_PURPLE) + 6.0;
	chipX += chip(ui, kit, 136, chipX, 384.0, "LEGEND", ChipKind.Outline, LEGENDARY_GOLD) + 6.0;
	chip(ui, kit, 137, chipX, 384.0, "MYTHIC", ChipKind.Outline, MYTHIC_CYAN);
	chip(ui, kit, 138, 16.0, 406.0, "RAGE 2", ChipKind.Filled, ALERT_RED);
	badge(ui, kit, 140, 16.0, 436.0, "winter", "12", 1);
	badge(ui, kit, 141, 70.0, 436.0, "growth", "X1.1", 2);
	badge(ui, kit, 142, 124.0, 436.0, "insured", "", 3);
	badge(ui, kit, 143, 178.0, 436.0, "shield", "2", 4);
	badge(ui, kit, 144, 232.0, 436.0, "fading", "", 5);
	heartPips(ui, kit, 150, 16.0, 496.0, gallery.hearts, 10, 14.0);
	heartPips(ui, kit, 151, 190.0, 494.0, 13, 20, 7.0);
	heartPips(ui, kit, 152, 16.0, 520.0, 17, 25, 14.0);
	say(ui, kit, 160, "LV12", 16.0, 552.0, 40.0, 8.0, INK, 0.0);
	bar(ui, 56.0, 552.0, 120.0, 8.0, 0.62, EMBER);
	say(ui, kit, 161, "D34", 180.0, 552.0, 40.0, 8.0, INK, 0.0);
	bar(ui, 230.0, 552.0, 114.0, 6.0, 0.4, GROWTH_GREEN);
	if (pressable(ui, 162, 16.0, 572.0, 328.0, 36.0)) {
		gallery.bonding = gallery.bonding > 100 ? -110 : gallery.bonding + 40;
	}
	bondingBar(ui, kit, 163, 16.0, 580.0, 328.0, gallery.bonding);
	say(ui, kit, 164, "BONDING " + gallery.bonding.toString() + " - TAP TO MOVE", 16.0, 610.0, 328.0, 8.0, INK_MUTED, 0.0);
	frame(kit, 170, 16.0, 636.0, 156.0, 80.0, 7, FrameLook.Normal);
	balance(ui, kit, 171, 30.0, 652.0, 128.0, "bag", "warning", "1,240");
	balance(ui, kit, 172, 30.0, 672.0, 128.0, "lock", "", "5,600");
	balance(ui, kit, 173, 30.0, 692.0, 128.0, "heart", "", gallery.hearts.toString() + "/10");
	delta(ui, kit, 174, 188.0, 652.0, 156.0, 280, 0.0);
	delta(ui, kit, 175, 188.0, 672.0, 156.0, -310, 0.0);
	delta(ui, kit, 176, 188.0, 692.0, 156.0, 0, 0.0);
}

function controlsPage(gallery: Gallery): void {
	const ui: Ui = gallery.ui;
	const kit: Kit = gallery.kit;
	const tick: int32 = gallery.tick;
	if (toggle(ui, kit, 200, 16.0, 70.0, gallery.toggleOn ? ToggleState.On : ToggleState.Off, tick)) {
		gallery.toggleOn = !gallery.toggleOn;
	}
	toggle(ui, kit, 201, 70.0, 70.0, ToggleState.Off, tick);
	toggle(ui, kit, 202, 124.0, 70.0, ToggleState.Pending, tick);
	toggle(ui, kit, 203, 178.0, 70.0, ToggleState.Disabled, tick);
	if (textLink(ui, kit, 204, 260.0, 88.0, "TOAST", true)) {
		gallery.toastsPushed += 1;
		const failed: boolean = gallery.toastsPushed % 3 == 0;
		pushToast(gallery.toasts, failed ? "FAILED: NOT ENOUGH SKR" : "MOVED 620 TO BURROW - " + gallery.toastsPushed.toString(), failed);
	}
	gallery.segment = segmented(ui, kit, 210, 16.0, 124.0, 328.0, ["THREAT", "LOOT", "WEAK"], gallery.segment, 21);
	gallery.tab = tabs(ui, kit, 211, 16.0, 172.0, 200.0, ["PET", "TREE"], [0, 2], gallery.tab);
	frame(kit, 219, 16.0, 210.0, 328.0, 292.0, 22, FrameLook.Normal);
	if (radioRow(ui, kit, 220, 30.0, 220.0, 300.0, "CAUTIOUS", "AVOIDS FIGHTS IT MIGHT LOSE", gallery.radio == 0, true)) {
		gallery.radio = 0;
	}
	if (radioRow(ui, kit, 221, 30.0, 268.0, 300.0, "GREEDY", "GOES FOR THE FATTEST HARVEST", gallery.radio == 1, false)) {
		gallery.radio = 1;
	}
	if (listRow(ui, kit, 230, 30.0, 316.0, 300.0, "ate", "ATE A MEDIUM PORTION", "-315", ALERT_RED,
		gallery.row == 0 ? RowKind.Selected : RowKind.Plain, true, false)) {
		gallery.row = 0;
	}
	if (listRow(ui, kit, 231, 30.0, 364.0, 300.0, "fightLost", "ROBBED BY SLOT 4", "-310", ALERT_RED,
		gallery.row == 1 ? RowKind.Selected : RowKind.Plain, true, false)) {
		gallery.row = 1;
	}
	listRow(ui, kit, 232, 30.0, 412.0, 300.0, "", "DISCONNECT", "", INK, RowKind.Destructive, false, false);
	listRow(ui, kit, 233, 30.0, 446.0, 300.0, "", "NETWORK", "DEVNET", INK_MUTED, RowKind.Locked, false, false);
	sectionHeader(ui, kit, 240, 16.0, 516.0, 328.0, "THIS MORNING", "OCT 2");
	labelDivider(ui, kit, 241, 16.0, 540.0, 328.0, "NEW SINCE 23:10", EMBER);
	reasonPill(ui, kit, 250, 16.0, 560.0, "BONDING LOW", false);
	reasonPill(ui, kit, 251, 140.0, 560.0, "ROBBED BY SLOT 4: -310", true);
	tooltip(ui, kit, 252, 344.0, 598.0, "INSURED - REVIVES ONCE AT 3");
	walletBanner(ui, kit, 260, 16.0, 618.0, 328.0, "MEDIUM - +2 HEARTS - 9 SKR", 26, tick);
	skeleton(ui, 16.0, 680.0, 150.0, 8.0, tick);
	skeleton(ui, 16.0, 694.0, 100.0, 8.0, tick);
	syncChip(ui, kit, 270, 180.0, 676.0, "SYNCING...", true, tick);
	syncChip(ui, kit, 271, 180.0, 698.0, "OFFLINE - 3 MIN AGO", false, tick);
	emptyState(ui, kit, 280, 16.0, 724.0, 328.0, 32.0, "", "NOTHING YET. FIRST DAY UNDER WAY.");
	drawToasts(ui, kit, 290, gallery.toasts, 16.0, 760.0, 328.0);
}

function demoSheet(gallery: Gallery): void {
	const ui: Ui = gallery.ui;
	const kit: Kit = gallery.kit;
	gallery.sheetOpen = gallery.sheetOpen + ((gallery.sheetWanted ? 1.0 : 0.0) - gallery.sheetOpen) * SHEET_EASE;
	if (gallery.sheetOpen <= 0.01) {
		return;
	}
	if (sheet(ui, kit, 340, 360.0, gallery.sheetOpen, 38)) {
		gallery.sheetWanted = false;
	}
	const top: float32 = sheetTop(360.0, gallery.sheetOpen);
	say(ui, kit, 341, "FEED", 32.0, top + 28.0, 200.0, 16.0, INK, 0.0);
	say(ui, kit, 342, "SWIPE DOWN OR TAP THE SCENE TO CLOSE", 32.0, top + 52.0, 296.0, 8.0, INK_MUTED, 0.0);
	if (button(ui, kit, 343, 32.0, top + 80.0, 296.0, 44.0, "CLOSE", ButtonStyle.Primary, true, 39)) {
		gallery.sheetWanted = false;
	}
	closeOverlay(ui, kit);
}

function overlaysPage(gallery: Gallery): void {
	const ui: Ui = gallery.ui;
	const kit: Kit = gallery.kit;
	const page: int32 = gallery.pagerPage;
	gallery.pagerPage = pager(ui, kit, 300, 16.0, 76.0, 328.0, PAGER_LABELS[page] + " - " + (page + 1).toString() + " OF 4", page, 4);
	frame(kit, 309, 16.0, 120.0, 328.0, 300.0, 31, FrameLook.Normal);
	let chatY: float32 = 136.0;
	chatY += chatBubble(ui, kit, 310, 30.0, 330.0, chatY, "DID YOU EAT TODAY?", true, true, 0);
	chatY += chatBubble(ui, kit, 311, 30.0, 330.0, chatY, "ATE A LITTLE. THE FIRE IS WARM AND THE NIGHT IS LONG.", false, false, 33);
	chatBubble(ui, kit, 312, 30.0, 330.0, chatY, "STAY CLOSE TO IT.", true, false, 0);
	if (chatInput(ui, kit, 313, 30.0, 360.0, 300.0, gallery.chatText, 34)) {
		gallery.chatText = "";
	}
	if (textLink(ui, kit, 314, 30.0, 432.0, gallery.chatText == "" ? "TYPE (DEMO)" : "CLEAR", true)) {
		gallery.chatText = gallery.chatText == "" ? "GOOD NIGHT" : "";
	}
	if (button(ui, kit, 320, 16.0, 470.0, 156.0, 48.0, "OPEN SHEET", ButtonStyle.Primary, true, 35)) {
		gallery.sheetWanted = true;
	}
	if (button(ui, kit, 321, 188.0, 470.0, 156.0, 48.0, "OPEN MODAL", ButtonStyle.Primary, true, 36)) {
		gallery.modalOpen = true;
	}
	const tapped: Result<DockTab, DockError> = dock(ui, kit, 330, gallery.dockTab, true, 37);
	if (tapped.ok) {
		gallery.dockTab = tapped.value;
	}
	demoSheet(gallery);
	if (gallery.modalOpen) {
		const answer: ModalAnswer = modal(ui, kit, 350, "DISCONNECT WALLET?", "YOUR PET KEEPS PLAYING ON ITS OWN.", "DISCONNECT", true, 40);
		if (answer != ModalAnswer.None) {
			gallery.modalOpen = false;
		}
		closeOverlay(ui, kit);
	}
}

function petViewsPage(gallery: Gallery): void {
	const ui: Ui = gallery.ui;
	const kit: Kit = gallery.kit;
	frame(kit, 400, 16.0, 76.0, 328.0, 136.0, 41, FrameLook.Normal);
	say(ui, kit, 401, "LINEAGE", 30.0, 88.0, 200.0, 8.0, EMBER_HOT, 0.0);
	lineageEntry(ui, kit, 402, 30.0, 108.0, 300.0, "GEN 1 - FIGHTER - LIVED 90 DAYS", LineageState.Lived, false);
	lineageEntry(ui, kit, 403, 30.0, 140.0, 300.0, "GEN 2 - WORKER - DIED DAY 61", LineageState.Died, false);
	lineageEntry(ui, kit, 404, 30.0, 172.0, 300.0, "GEN 3 - FIGHTER - NOW - DAY 34", LineageState.Now, true);
	gallery.cardFlip = gallery.cardFlip + (gallery.cardTarget - gallery.cardFlip) * FLIP_EASE;
	if (pressable(ui, 410, 30.0, 232.0, 120.0, 160.0)) {
		gallery.cardTarget = gallery.cardTarget > 0.5 ? 0.0 : 1.0;
	}
	talentCard(ui, kit, 411, 30.0, 232.0, gallery.cardFlip, "FIGHT", Rarity.Epic, "X1.35", 42);
	say(ui, kit, 412, "TAP THE CARD", 166.0, 240.0, 170.0, 8.0, INK_MUTED, 0.0);
	say(ui, kit, 413, "TALENT REVEALED", 166.0, 262.0, 170.0, 8.0, INK, 0.0);
	gradeLadder(ui, kit, 414, 16.0, 410.0, Rarity.Epic);
	say(ui, kit, 420, "TREE - TAP A NODE", 16.0, 450.0, 200.0, 8.0, INK_MUTED, 0.0);
	frame(kit, 421, 16.0, 470.0, 328.0, 260.0, 43, FrameLook.Normal);
	for (const link of DEMO_LINKS) {
		const from: DemoNode = DEMO_NODES[link.from];
		const to: DemoNode = DEMO_NODES[link.to];
		treeLink(ui, from.x, from.y, to.x, to.y, from.state == NodeState.Allocated && to.state == NodeState.Allocated);
	}
	for (let position: int32 = 0; position < DEMO_NODES.length; position += 1) {
		const node: DemoNode = DEMO_NODES[position];
		if (treeNode(ui, kit, 430 + position, node.x, node.y, node.shape, node.state)) {
			gallery.pickedNode = position;
		}
	}
	icon(kit, 445, "recenter", 300.0, 690.0, 26.0);
	if (gallery.pickedNode != NO_NODE) {
		const node: DemoNode = DEMO_NODES[gallery.pickedNode];
		say(ui, kit, 440, node.name + (node.shape == NodeShape.Keystone ? " - KEYSTONE" : ""), 30.0, 486.0, 300.0, 8.0, EMBER_HOT, 0.0);
	}
}

function oddsPage(gallery: Gallery): void {
	oddsBlock(gallery.ui, gallery.kit, 500, 16.0, 80.0, ODDS_STATES[gallery.oddsState],
		{ winPercent: 62, expectedLoot: 310, maxLoot: 480, rounds: [0.08, 0.12, 0.28, 0.40, 0.33, 0.18] }, "NEWBORN SHIELD - 2 DAYS LEFT",
		50, gallery.tick);
	if (textLink(gallery.ui, gallery.kit, 501, 16.0, 270.0, "NEXT STATE", true)) {
		gallery.oddsState = (gallery.oddsState + 1) % (ODDS_STATES.length as int32);
	}
	oddsBlock(gallery.ui, gallery.kit, 502, 16.0, 310.0, OddsState.Ready,
		{ winPercent: 38, expectedLoot: 120, maxLoot: 260, rounds: [0.30, 0.25, 0.20, 0.12, 0.08, 0.05] }, "", 51, gallery.tick);
}

export function frameGallery(): void {
	if ((galleries.length as int32) == 0) {
		return;
	}
	const gallery: Gallery = galleries[0];
	const ui: Ui = gallery.ui;
	const kit: Kit = gallery.kit;
	const page: GalleryPage = PAGES[gallery.page];
	beginUi(ui);
	beginKit(kit);
	gallery.tick += 1;
	ui.blockBase = page == GalleryPage.Overlays && (gallery.sheetWanted || gallery.modalOpen);
	say(ui, kit, 1, pageTitle(page), 16.0, 30.0, 260.0, 16.0, INK, 0.0);
	say(ui, kit, 2, "TAP THE TITLE FOR HOME", 16.0, 52.0, 260.0, 8.0, INK_MUTED, 0.0);
	if (pressable(ui, 3, 0.0, 20.0, 250.0, 44.0)) {
		gallery.homeAsked = true;
	}
	const count: int32 = PAGES.length as int32;
	if (textLink(ui, kit, 4, 284.0, 34.0, "NEXT " + (gallery.page + 1).toString() + "/" + count.toString(), true)) {
		gallery.page = (gallery.page + 1) % count;
	}
	match (page) {
		GalleryPage.Frames => framesPage(gallery),
		GalleryPage.Basics => basicsPage(gallery),
		GalleryPage.Controls => controlsPage(gallery),
		GalleryPage.Overlays => overlaysPage(gallery),
		GalleryPage.PetViews => petViewsPage(gallery),
		GalleryPage.Odds => oddsPage(gallery),
	};
	endKit(kit);
	loadNextPass();
	endUi(ui);
}
