import { Ui, pressable, held } from "../ui/ui";
import {
	Kit, PieceLayer, say, pieceSized, INK_MUTED, INK_BRIGHT,
	HOLO_BLUE, HOLO_GREEN, ALERT_RED, DISABLED_INK,
} from "./kit";
import { textLink } from "./buttons";
import {
	WalletState, walletState, walletAddress,
	requestWalletConnection, requestWalletDisconnect,
	GameOwnerState, gameOwnerState, gameOwnerAddress,
} from "../host/host";

const WALLET_ACTION_WIDTH: float32 = 148.0;

function walletAction(
	ui: Ui, kit: Kit, id: int32, x: float32, y: float32,
	label: string, enabled: boolean, holographic: boolean,
): boolean {
	if (!holographic) { return textLink(ui, kit, id, x, y, label, enabled); }
	const width: float32 = WALLET_ACTION_WIDTH;
	const tapped: boolean = pressable(ui, id, x, y - 14.0, width, 44.0) && enabled;
	const down: boolean = enabled && held(ui, id, x, y - 14.0, width, 44.0);
	pieceSized(kit, id, PieceLayer.Frames, "onboardingWallet", x, y - 8.0, width, 28.0);
	say(ui, kit, id, label, x + 8.0, y, width - 16.0, 8.0,
		!enabled ? DISABLED_INK : (down ? INK_BRIGHT : HOLO_BLUE), 0.5);
	return tapped;
}

export function walletConnection(
	ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32,
	holographic: boolean = false,
): void {
	const state: WalletState = walletState();
	const owner: GameOwnerState = gameOwnerState();
	const align: float32 = holographic ? 0.5 : 0.0;
	const actionX: float32 = holographic ? x + (width - WALLET_ACTION_WIDTH) * 0.5 : x;
	if (state == WalletState.Connected) {
		say(ui, kit, id, "WALLET CONNECTED", x, y, width, 8.0, HOLO_GREEN, align);
		say(ui, kit, id + 1, walletAddress(), x, y + 18.0, width, 8.0, INK_MUTED, align);
		if (walletAction(ui, kit, id + 2, actionX, y + 40.0,
			"DISCONNECT WALLET", true, holographic)) {
			requestWalletDisconnect();
		}
		if (owner == GameOwnerState.Failed) {
			say(ui, kit, id + 3, "OWNER COULD NOT BE SAVED ON THIS DEVICE.",
				x, y + 58.0, width, 8.0, ALERT_RED, align);
		}
		return;
	}
	const pending: boolean = state == WalletState.Connecting || state == WalletState.Disconnecting;
	const label: string = match (state) {
		WalletState.Disconnecting => "DISCONNECTING...",
		WalletState.Connecting => "OPENING WALLET...",
		_ => "CONNECT WALLET",
	};
	const remembered: boolean = owner == GameOwnerState.Remembered;
	const actionTop: float32 = remembered ? y + 40.0 : y;
	if (remembered) {
		say(ui, kit, id, "OWNER REMEMBERED", x, y, width, 8.0, HOLO_GREEN, align);
		say(ui, kit, id + 1, gameOwnerAddress(), x, y + 18.0, width, 8.0, INK_MUTED, align);
	}
	if (walletAction(ui, kit, id + 2, actionX, actionTop, label, !pending, holographic)) {
		requestWalletConnection();
	}
	const detail: string = match (state) {
		WalletState.NoWallet => "INSTALL A MOBILE WALLET TO CONNECT.",
		WalletState.Cancelled => "REQUEST CANCELLED. TAP TO TRY AGAIN.",
		WalletState.Failed => "WALLET REQUEST FAILED. TAP TO RETRY.",
		WalletState.Connecting => "CONFIRM IN YOUR WALLET. NO TRANSACTION.",
		_ => owner == GameOwnerState.Failed ? "OWNER CACHE UNREADABLE. SELECT WALLET AGAIN." : "",
	};
	if (detail != "") {
		say(ui, kit, id + 3, detail, x, actionTop + 18.0, width, 8.0,
			state == WalletState.Failed || state == WalletState.NoWallet
				|| owner == GameOwnerState.Failed ? ALERT_RED : INK_MUTED, align);
	}
}
