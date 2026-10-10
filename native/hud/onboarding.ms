import { Color, rgba } from "@metascript/void/src/void2d/types";
import { Ui, DESIGN_W, DESIGN_H, box, pressable, held } from "../ui/ui";
import {
	Kit, PieceLayer, say, fill, pieceSized, capsCentredY, measure,
	INK_BRIGHT, INK_MUTED, HOLO_BLUE, DISABLED_INK,
} from "./kit";
import { connectLabel, connectWallet, ownerKnown, walletLine, walletPending, walletStatus } from "./walletConnection";
import { randomPetName, petDisplayName } from "./petNames";
import {
	gameOwnerState,
	gameRead,
	GamePet,
	GameReadError,
	GameReadState,
	OwnerAction,
	OwnerActionOutcome,
	markDeathNoticeSeen,
	ownerActionOutcome,
	requestOwnerAction,
} from "../host/host";
import {
	NotLive,
	livePet,
	unavailablePetStatus,
	petReadStatus,
	summonAllowed,
	summonInFlight,
	summonStatus,
} from "./gameAvailability";
import { Mourning, mournedPet } from "./mourning";
import { spinner } from "./buttons";

const LEFT: float32 = 28.0;
const WIDTH: float32 = DESIGN_W - LEFT * 2.0;
const NAME_BUTTON_SIZE: float32 = 52.0;
const HOLOGRAM_X: float32 = 82.0;
const HOLOGRAM_Y: float32 = 206.0;
const HOLOGRAM_WIDTH: float32 = 196.0;
const HOLOGRAM_HEIGHT: float32 = 229.0;
const DEAD_INK: Color = rgba(0.55, 0.57, 0.6, 1.0);
const SPINNER_SIZE: float32 = 16.0;
const SPINNER_GAP: float32 = 12.0;
const FRAMES_PER_SECOND: float64 = 60.0;
const WAITING_Y: float32 = 715.0;
export const PET_PREVIEW_X: float32 = HOLOGRAM_X + HOLOGRAM_WIDTH * 0.5;
export const PET_PREVIEW_Y: float32 = HOLOGRAM_Y + HOLOGRAM_HEIGHT * 0.76;

function onboardingButton(
	ui: Ui, kit: Kit, id: int32, art: string,
	x: float32, y: float32, width: float32, height: float32,
	label: string, enabled: boolean, busy: boolean = false,
): boolean {
	const tapped: boolean = pressable(ui, id, x, y, width, height) && enabled && !busy;
	const down: boolean = enabled && !busy && held(ui, id, x, y, width, height);
	pieceSized(kit, id, PieceLayer.Frames, art, x, y, width, height);
	if (label != "") {
		say(ui, kit, id, label, x, capsCentredY(kit, label, 16.0, y, height), width, 16.0,
			busy ? INK_BRIGHT : !enabled ? DISABLED_INK : (down ? HOLO_BLUE : INK_BRIGHT), 0.5);
	}
	if (busy) {
		const labelLeft: float32 = x + (width - measure(kit, label, 16.0).width) * 0.5;
		const tick: int32 = Math.floor(performance.now() / 1000.0 * FRAMES_PER_SECOND) as int32;
		spinner(ui, labelLeft - SPINNER_GAP - SPINNER_SIZE, y + (height - SPINNER_SIZE) * 0.5, SPINNER_SIZE, tick);
	}
	return tapped;
}

// The campfire's only HUD until a read says whether there is a Pet: a spinner and what is being waited on.
export function waitingLine(ui: Ui, kit: Kit, id: int32, status: string): void {
	const width: float32 = measure(kit, status, 8.0).width;
	const left: float32 = (DESIGN_W - width + SPINNER_SIZE + SPINNER_GAP) * 0.5;
	const tick: int32 = Math.floor(performance.now() / 1000.0 * FRAMES_PER_SECOND) as int32;
	spinner(ui, left - SPINNER_GAP - SPINNER_SIZE, WAITING_Y - SPINNER_SIZE * 0.5, SPINNER_SIZE, tick);
	say(ui, kit, id, status, left, WAITING_Y - 4.0, width + 8.0, 8.0, INK_MUTED, 0.0);
}

// From the wallet's approval until the Pet sits in a Block: the transaction lands, the next read
// finds the Pet, and the operator places it.
function summoning(outcome: OwnerActionOutcome, named: boolean): boolean {
	if (summonInFlight(outcome)) { return true; }
	if (outcome == OwnerActionOutcome.ConfirmedAwaitingRead && !named) { return true; }
	const read = gameRead();
	if (!read.ok || read.value.state != GameReadState.PetFound) { return false; }
	const live = livePet(read.value);
	return !live.ok && live.error == NotLive.AwaitingPlacement;
}

// A Pet already on chain: its name is fixed there, so the picker shows it instead.
function namedPet(): Result<GamePet, NotLive> {
	const read = gameRead();
	if (!read.ok || read.value.state != GameReadState.PetFound) { return Result.err(NotLive.NoPetRead); }
	return Result.ok(read.value.pet);
}

// An old Pet's heir hatches when dusk records the death, then waits for a Block (program/day.ms dusked).
function heirStatus(mourning: Mourning): string {
	return mourning == Mourning.HeirArrived ? "THE HEIR HAS HATCHED." : "THE HEIR IS ON ITS WAY.";
}

// What the chain keeps of a lost Pet's life.
function lifeLine(lost: GamePet): string {
	const reached: string = "REACHED LEVEL " + lost.level.toString();
	if (lost.diedEpoch <= lost.bornEpoch) { return reached; }
	return "LIVED " + ((lost.diedEpoch - lost.bornEpoch) as int32).toString() + " DAYS / " + reached;
}

export function onboarding(ui: Ui, kit: Kit, id: int32, nameId: uint8): uint8 {
	const dead = mournedPet();
	const named = namedPet();
	const picking: boolean = !dead.ok && !named.ok;
	const lost: boolean = dead.ok && dead.value.mourning == Mourning.Lost;
	fill(kit, id, 0.0, 0.0, DESIGN_W, DESIGN_H, rgba(0.0, 0.02, 0.06, 0.55));
	say(ui, kit, id, "HIBERNAL", LEFT, 72.0, WIDTH, 32.0, INK_BRIGHT, 0.5);
	say(ui, kit, id + 1, "ONE PET. ONE LIFE.", LEFT, 124.0, WIDTH, 8.0, HOLO_BLUE, 0.5);
	if (dead.ok) {
		say(ui, kit, id + 2, lost ? "YOUR PET IS GONE" : "YOUR PET HAS DIED", LEFT, 175.0, WIDTH, 16.0, INK_BRIGHT, 0.5);
	} else {
		say(ui, kit, id + 2, "CHOOSE YOUR LINEAGE", LEFT, 178.0, WIDTH, 8.0, HOLO_BLUE, 0.5);
	}
	box(ui, 28.0, 183.0, 40.0, 1.0, 0.0, HOLO_BLUE);
	box(ui, 292.0, 183.0, 40.0, 1.0, 0.0, HOLO_BLUE);
	pieceSized(kit, id + 3, PieceLayer.Frames, dead.ok ? "onboardingHologramDead" : "onboardingHologram",
		HOLOGRAM_X, HOLOGRAM_Y, HOLOGRAM_WIDTH, HOLOGRAM_HEIGHT);
	let selected: uint8 = nameId;
	if (picking && onboardingButton(ui, kit, id + 4, "onboardingPrevious",
		LEFT, 300.0, NAME_BUTTON_SIZE, NAME_BUTTON_SIZE, "", true)) {
		selected = randomPetName(selected as int32);
	}
	if (picking && onboardingButton(ui, kit, id + 5, "onboardingNext",
		DESIGN_W - LEFT - NAME_BUTTON_SIZE, 300.0,
		NAME_BUTTON_SIZE, NAME_BUTTON_SIZE, "", true)) {
		selected = randomPetName(selected as int32);
	}
	const nameId: uint8 = dead.ok ? dead.value.pet.nameId : (named.ok ? named.value.nameId : selected);
	const heirArrived: boolean = dead.ok && dead.value.mourning == Mourning.HeirArrived;
	const heirGeneration: int32 = dead.ok && !lost ? dead.value.pet.lineageGeneration : 0;
	const generation: uint16 = lost ? (dead.value.pet.lineageGeneration as uint16)
		: (dead.ok ? ((heirGeneration - 1) as uint16) : (named.ok ? (named.value.lineageGeneration as uint16) : 0));
	const name: string = petDisplayName(nameId, generation);
	pieceSized(kit, id + 6, PieceLayer.Frames, dead.ok ? "onboardingNameDead" : "onboardingName", 80.0, 452.0, 200.0, 38.0);
	say(ui, kit, id + 6, name, 80.0, capsCentredY(kit, name, 16.0, 452.0, 38.0),
		200.0, 16.0, dead.ok ? DEAD_INK : INK_BRIGHT, 0.5);
	say(ui, kit, id + 7, lost ? "LOST FOR GOOD" : dead.ok ? "DIED OF OLD AGE / ITS HEIR CARRIES ON"
		: (named.ok ? "YOUR PET" : "PICK A NAME. IT STAYS FOR LIFE."), LEFT, 504.0, WIDTH, 8.0,
		HOLO_BLUE, 0.5);
	const summoned: string = dead.ok ? "CONTINUE WITH " + petDisplayName(nameId, heirGeneration as uint16) : "SUMMON " + name;
	const known: boolean = dead.ok || named.ok || ownerKnown();
	const outcome = ownerActionOutcome();
	let availability: string = unavailablePetStatus(gameOwnerState());
	let summon: boolean = false;
	const read = gameRead();
	if (read.ok) {
		const snapshot = read.value;
		if (snapshot.state != GameReadState.Unavailable) {
			availability = petReadStatus(snapshot);
			summon = summonAllowed(snapshot) && !summonInFlight(outcome);
		}
	} else {
		availability = match (read.error) {
			GameReadError.Updating => "LOOKING FOR YOUR PET...",
			GameReadError.InvalidState => "SOMETHING LOOKS OFF. CHECKING AGAIN SOON.",
		};
	}
	if (lost) {
		say(ui, kit, id + 20, lifeLine(dead.value.pet), LEFT, 664.0, WIDTH, 8.0, DEAD_INK, 0.5);
	} else if (!known) {
		if (onboardingButton(ui, kit, id + 20, "onboardingCreate", LEFT, 635.0, WIDTH, 74.0, connectLabel(), !walletPending())) {
			connectWallet();
		}
	} else if (!dead.ok && summoning(outcome, named.ok)) {
		onboardingButton(ui, kit, id + 20, "onboardingCreate", LEFT, 635.0, WIDTH, 74.0, "SUMMONING...", false, true);
	} else if (onboardingButton(ui, kit, id + 20, "onboardingCreate", LEFT, 635.0, WIDTH,
		74.0, summoned.toUpperCase(), dead.ok ? heirArrived : summon)) {
		if (dead.ok) {
			markDeathNoticeSeen(heirGeneration);
		} else {
			requestOwnerAction(OwnerAction.Claim, selected as int32);
		}
	}
	// One line under the button: what the last wallet request did, else why Summon waits.
	const wallet: string = walletStatus();
	const action: string = dead.ok ? heirStatus(dead.value.mourning) : wallet != "" ? wallet : summonStatus(outcome);
	const status: string = lost ? "" : action != "" ? action : summon || !known ? "" : availability;
	walletLine(ui, kit, id + 10, DESIGN_W * 0.5, 715.0);
	say(ui, kit, id + 24, status, LEFT, 762.0, WIDTH, 8.0, action != "" ? HOLO_BLUE : INK_MUTED, 0.5);
	return selected;
}
