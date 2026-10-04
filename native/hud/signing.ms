// A stand-in for a wallet signature until the chain client exists: it answers after a pause.

import { SignState } from "./buttons";

const WALLET_FRAMES: int32 = 75;
const DONE_FRAMES: int32 = 50;

export interface Signing {
	state: SignState;
	since: int32;
}

export function idleSigning(): Signing {
	return { state: SignState.Idle, since: 0 };
}

export function startSigning(signing: Signing, tick: int32): void {
	signing.state = SignState.Waiting;
	signing.since = tick;
}

// True on the frame the wallet answers; Done goes back to Idle a moment later.
export function advanceSigning(signing: Signing, tick: int32): boolean {
	if (signing.state == SignState.Waiting && tick - signing.since > WALLET_FRAMES) {
		signing.state = SignState.Done;
		signing.since = tick;
		return true;
	}
	if (signing.state == SignState.Done && tick - signing.since > DONE_FRAMES) {
		signing.state = SignState.Idle;
	}
	return false;
}
