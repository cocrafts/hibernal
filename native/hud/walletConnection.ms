import { Ui } from "../ui/ui";
import { Kit, say, measure, INK_MUTED } from "./kit";
import { textLink } from "./buttons";
import {
	WalletState, walletState, walletAddress,
	requestWalletConnection, requestWalletDisconnect,
	GameOwnerState, gameOwnerState, gameOwnerAddress,
} from "../host/host";

const ADDRESS_ENDS: int32 = 4;
const LINK_ROW: float32 = 20.0;
const LINK_GAP: float32 = 16.0;

function shortAddress(address: string): string {
	if ((address.length as int32) <= ADDRESS_ENDS * 2) { return address; }
	return address.slice(0, ADDRESS_ENDS) + "..." + address.slice((address.length as int32) - ADDRESS_ENDS);
}

// A remembered owner is enough to summon: the wallet opens to approve the transaction itself.
export function ownerKnown(): boolean {
	return walletState() == WalletState.Connected || gameOwnerState() == GameOwnerState.Remembered;
}

export function walletPending(): boolean {
	const state: WalletState = walletState();
	return state == WalletState.Connecting || state == WalletState.Disconnecting;
}

// The main button's label while no owner is known.
export function connectLabel(): string {
	return match (walletState()) {
		WalletState.Connecting => "OPENING WALLET...",
		WalletState.Disconnecting => "DISCONNECTING...",
		_ => "CONNECT WALLET",
	};
}

export function connectWallet(): void {
	requestWalletConnection();
}

// What the last wallet request left to say; empty when there is nothing.
export function walletStatus(): string {
	if (gameOwnerState() == GameOwnerState.Failed) { return "CONNECT YOUR WALLET AGAIN."; }
	return match (walletState()) {
		WalletState.NoWallet => "INSTALL A MOBILE WALLET TO CONNECT.",
		WalletState.Cancelled => "REQUEST CANCELLED. TAP TO TRY AGAIN.",
		WalletState.Failed => "WALLET REQUEST FAILED. TAP TO RETRY.",
		WalletState.Connecting => "CONFIRM IN YOUR WALLET. NOTHING IS SENT.",
		_ => "",
	};
}

// The known owner's short address, and under it the links to change or forget it, centred on `centreX`.
export function walletLine(ui: Ui, kit: Kit, id: int32, centreX: float32, y: float32): void {
	if (!ownerKnown()) { return; }
	const connected: boolean = walletState() == WalletState.Connected;
	const address: string = shortAddress(connected ? walletAddress() : gameOwnerAddress());
	const addressWidth: float32 = measure(kit, address, 8.0).width;
	say(ui, kit, id, address, centreX - addressWidth * 0.5, y, addressWidth + 8.0, 8.0, INK_MUTED, 0.0);
	const switchWidth: float32 = measure(kit, "SWITCH", 8.0).width;
	const left: float32 = centreX - (switchWidth + LINK_GAP + measure(kit, "DISCONNECT", 8.0).width) * 0.5;
	say(ui, kit, id + 3, "·", left + switchWidth, y + LINK_ROW, LINK_GAP, 8.0, INK_MUTED, 0.5);
	if (textLink(ui, kit, id + 1, left, y + LINK_ROW, "SWITCH", !walletPending())) { requestWalletConnection(); }
	if (textLink(ui, kit, id + 2, left + switchWidth + LINK_GAP, y + LINK_ROW, "DISCONNECT", !walletPending())) {
		requestWalletDisconnect();
	}
}
