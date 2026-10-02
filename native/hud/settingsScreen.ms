import { Ui, box } from "@metascript/void/src/ui/ui";
import { Kit, say, INK, INK_MUTED, GROWTH_GREEN } from "./kit";
import { textLink } from "./buttons";
import { ToggleState, toggle } from "./controls";
import { RowKind, listRow, sectionHeader } from "./rows";
import { pushToast } from "./notices";
import { ModalAnswer, modal } from "./overlays";
import { CHAR_MID } from "./shapes";
import { Nav, ScreenContext, closeOverlay } from "./screenChrome";

const SESSION_KEY_FRAMES: int32 = 75;

interface SettingsState {
	sessionKey: ToggleState;
	sessionKeySince: int32;
	ongoingNotification: boolean;
	digestNotification: boolean;
	wallpaperSet: boolean;
	askingToDisconnect: boolean;
	connected: boolean;
}

const settings: SettingsState = {
	sessionKey: ToggleState.Off,
	sessionKeySince: 0,
	ongoingNotification: true,
	digestNotification: true,
	wallpaperSet: false,
	askingToDisconnect: false,
	connected: true,
};

function onOff(on: boolean): ToggleState {
	return on ? ToggleState.On : ToggleState.Off;
}

function wallet(context: ScreenContext): void {
	const ui: Ui = context.ui;
	const kit: Kit = context.kit;
	sectionHeader(ui, kit, 5010, 16.0, 66.0, 328.0, "WALLET", "");
	if (!settings.connected) {
		if (listRow(ui, kit, 5013, 16.0, 84.0, 328.0, "wallet", "CONNECT WALLET", "", INK, RowKind.Plain, true, true)) {
			settings.connected = true;
		}
		return;
	}
	if (listRow(ui, kit, 5011, 16.0, 84.0, 328.0, "wallet", "CONNECTED WALLET", "7XKP...3FQA", INK_MUTED, RowKind.Plain, false, true)) {
		pushToast(context.toasts, "ADDRESS COPIED", false);
	}
	if (listRow(ui, kit, 5012, 16.0, 140.0, 328.0, "", "DISCONNECT", "", INK, RowKind.Destructive, false, true)) {
		settings.askingToDisconnect = true;
	}
}

function sessionKey(context: ScreenContext): void {
	const ui: Ui = context.ui;
	const kit: Kit = context.kit;
	sectionHeader(ui, kit, 5020, 16.0, 210.0, 328.0, "SESSION KEY", "");
	if (settings.sessionKey == ToggleState.Pending && context.tick - settings.sessionKeySince > SESSION_KEY_FRAMES) {
		settings.sessionKey = ToggleState.On;
	}
	const active: boolean = settings.sessionKey == ToggleState.On;
	say(ui, kit, 5021, active ? "ACTIVE - EXPIRES IN 6 DAYS" : "SIGN FOR YOUR PET YOURSELF", 16.0, 240.0, 250.0, 8.0,
		active ? GROWTH_GREEN : INK, 0.0);
	if (toggle(ui, kit, 5022, 296.0, 222.0, settings.sessionKey, context.tick)) {
		if (settings.sessionKey == ToggleState.Off) {
			settings.sessionKey = ToggleState.Pending;
			settings.sessionKeySince = context.tick;
		} else {
			settings.sessionKey = ToggleState.Off;
			pushToast(context.toasts, "SESSION KEY REVOKED", false);
		}
	}
	say(ui, kit, 5023, "YOUR PET PLAYS ON ITS OWN WITHOUT IT.", 16.0, 258.0, 270.0, 8.0, INK_MUTED, 0.0);
}

function preferences(context: ScreenContext): void {
	const ui: Ui = context.ui;
	const kit: Kit = context.kit;
	sectionHeader(ui, kit, 5030, 16.0, 290.0, 328.0, "LIVE WALLPAPER", settings.wallpaperSet ? "ON" : "OFF");
	if (listRow(ui, kit, 5031, 16.0, 308.0, 328.0, "home", settings.wallpaperSet ? "CHANGE WALLPAPER" : "SET AS WALLPAPER", "", INK,
		RowKind.Plain, true, false)) {
		settings.wallpaperSet = true;
		pushToast(context.toasts, "OPENS THE SYSTEM PICKER", false);
	}
	sectionHeader(ui, kit, 5040, 16.0, 372.0, 328.0, "NOTIFICATIONS", "");
	say(ui, kit, 5041, "ONGOING - PET IN THE SHADE", 16.0, 402.0, 250.0, 8.0, INK, 0.0);
	if (toggle(ui, kit, 5042, 296.0, 384.0, onOff(settings.ongoingNotification), context.tick)) {
		settings.ongoingNotification = !settings.ongoingNotification;
	}
	say(ui, kit, 5043, "MORNING DIGEST", 16.0, 446.0, 250.0, 8.0, INK, 0.0);
	if (toggle(ui, kit, 5044, 296.0, 428.0, onOff(settings.digestNotification), context.tick)) {
		settings.digestNotification = !settings.digestNotification;
	}
	sectionHeader(ui, kit, 5050, 16.0, 486.0, 328.0, "NETWORK", "");
	listRow(ui, kit, 5051, 16.0, 504.0, 328.0, "", "NETWORK", "DEVNET", INK_MUTED, RowKind.Locked, false, false);
	sectionHeader(ui, kit, 5060, 16.0, 566.0, 328.0, "ABOUT", "VERSION 0.1.0 (HACKATHON)");
	if (listRow(ui, kit, 5061, 16.0, 584.0, 328.0, "", "UI KIT GALLERY", "", INK, RowKind.Plain, true, false)) {
		context.navigate = Nav.Gallery;
	}
	if (listRow(ui, kit, 5062, 16.0, 632.0, 328.0, "", "HOW THE GAME WORKS", "", INK, RowKind.Plain, true, false)) {
		pushToast(context.toasts, "NOT BUILT YET", false);
	}
}

function disconnectModal(context: ScreenContext): void {
	context.overlayOpen = true;
	const answer: ModalAnswer = modal(context.ui, context.kit, 5100, "DISCONNECT WALLET?", "YOUR PET KEEPS PLAYING ON ITS OWN.",
		"DISCONNECT", true, 74);
	if (answer == ModalAnswer.Confirm) {
		settings.connected = false;
		pushToast(context.toasts, "WALLET DISCONNECTED", false);
	}
	if (answer != ModalAnswer.None) {
		settings.askingToDisconnect = false;
	}
	closeOverlay(context.ui, context.kit);
}

export function settingsScreen(context: ScreenContext): void {
	if (textLink(context.ui, context.kit, 5000, 16.0, 34.0, "< HOME", true)) {
		context.navigate = Nav.Home;
	}
	say(context.ui, context.kit, 5001, "SETTINGS", 100.0, 30.0, 160.0, 16.0, INK, 0.5);
	box(context.ui, 16.0, 52.0, 328.0, 1.0, 0.0, CHAR_MID);
	wallet(context);
	sessionKey(context);
	preferences(context);
	if (settings.askingToDisconnect) {
		disconnectModal(context);
	}
}
