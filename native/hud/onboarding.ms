import { Color, rgba } from "@metascript/void/src/void2d/types";
import { Ui, DESIGN_W, DESIGN_H, box, pressable, held } from "../ui/ui";
import {
	Kit, PieceLayer, say, fill, pieceSized, measure,
	INK_BRIGHT, INK_MUTED, HOLO_BLUE, DISABLED_INK,
} from "./kit";
import { walletConnection } from "./walletConnection";
import { petNameStep, petDisplayName } from "./petNames";
import {
	gameOwnerState,
	gameRead,
	GamePet,
	GameReadError,
	GameReadState,
	OwnerAction,
	markDeathNoticeSeen,
	ownerActionOutcome,
	requestOwnerAction,
} from "../host/host";
import {
	NotLive,
	unavailablePetStatus,
	petReadStatus,
	summonAllowed,
	summonInFlight,
	summonStatus,
} from "./gameAvailability";
import { Mourning, mournedPet } from "./mourning";

const LEFT: float32 = 28.0;
const WIDTH: float32 = DESIGN_W - LEFT * 2.0;
const NAME_BUTTON_SIZE: float32 = 52.0;
const HOLOGRAM_X: float32 = 82.0;
const HOLOGRAM_Y: float32 = 206.0;
const HOLOGRAM_WIDTH: float32 = 196.0;
const HOLOGRAM_HEIGHT: float32 = 229.0;
const DEAD_INK: Color = rgba(0.55, 0.57, 0.6, 1.0);
export const PET_PREVIEW_X: float32 = HOLOGRAM_X + HOLOGRAM_WIDTH * 0.5;
export const PET_PREVIEW_Y: float32 = HOLOGRAM_Y + HOLOGRAM_HEIGHT * 0.76;

function onboardingButton(
	ui: Ui, kit: Kit, id: int32, art: string,
	x: float32, y: float32, width: float32, height: float32,
	label: string, enabled: boolean,
): boolean {
	const tapped: boolean = pressable(ui, id, x, y, width, height) && enabled;
	const down: boolean = enabled && held(ui, id, x, y, width, height);
	pieceSized(kit, id, PieceLayer.Frames, art, x, y, width, height);
	if (label != "") {
		const labelHeight: float32 = measure(kit, label, 16.0).height;
		say(ui, kit, id, label, x, y + (height - labelHeight) * 0.5, width, 16.0,
			!enabled ? DISABLED_INK : (down ? HOLO_BLUE : INK_BRIGHT), 0.5);
	}
	return tapped;
}

// A Pet already on chain: its name is fixed there, so the picker shows it instead.
function namedPet(): Result<GamePet, NotLive> {
	const read = gameRead();
	if (!read.ok || read.value.state != GameReadState.PetFound) { return Result.err(NotLive.NoPetRead); }
	return Result.ok(read.value.pet);
}

// Old age turns the PetAccount into the heir at once; a Pet still dead on chain with hearts left
// awaits that turn, one with none starved or lost a fight and has no heir.
function heirStatus(mourning: Mourning): string {
	return mourning == Mourning.HeirArrived ? "THE HEIR HAS HATCHED." : "THE HEIR IS WAITING FOR A BLOCK.";
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
		selected = petNameStep(selected, false);
	}
	if (picking && onboardingButton(ui, kit, id + 5, "onboardingNext",
		DESIGN_W - LEFT - NAME_BUTTON_SIZE, 300.0,
		NAME_BUTTON_SIZE, NAME_BUTTON_SIZE, "", true)) {
		selected = petNameStep(selected, true);
	}
	const nameId: uint8 = dead.ok ? dead.value.pet.nameId : (named.ok ? named.value.nameId : selected);
	const heirArrived: boolean = dead.ok && dead.value.mourning == Mourning.HeirArrived;
	const heirGeneration: int32 = dead.ok && !lost ? dead.value.pet.lineageGeneration : 0;
	const generation: uint16 = lost ? (dead.value.pet.lineageGeneration as uint16)
		: (dead.ok ? ((heirGeneration - 1) as uint16) : (named.ok ? (named.value.lineageGeneration as uint16) : 0));
	const name: string = petDisplayName(nameId, generation);
	pieceSized(kit, id + 6, PieceLayer.Frames, dead.ok ? "onboardingNameDead" : "onboardingName", 80.0, 452.0, 200.0, 38.0);
	say(ui, kit, id + 6, name, 80.0, 452.0 + (38.0 - measure(kit, name, 16.0).height) * 0.5,
		200.0, 16.0, dead.ok ? DEAD_INK : INK_BRIGHT, 0.5);
	say(ui, kit, id + 7, lost ? "LOST FOR GOOD" : dead.ok ? "DIED OF OLD AGE / ITS HEIR CARRIES ON"
		: (named.ok ? "YOUR PET / NAMED ON CHAIN" : "FIRST LIFE / NAME PREVIEW"), LEFT, 504.0, WIDTH, 8.0,
		HOLO_BLUE, 0.5);
	const summoned: string = dead.ok ? "CONTINUE WITH " + petDisplayName(nameId, heirGeneration as uint16) : "SUMMON " + name;
	walletConnection(ui, kit, id + 10, LEFT, 538.0, WIDTH, true);
	const outcome = ownerActionOutcome();
	let availability: string = unavailablePetStatus(gameOwnerState());
	let detail: string = "";
	let summon: boolean = false;
	const read = gameRead();
	if (read.ok) {
		const snapshot = read.value;
		if (snapshot.state != GameReadState.Unavailable) {
			availability = petReadStatus(snapshot);
			summon = summonAllowed(snapshot) && !summonInFlight(outcome);
		}
		detail = snapshot.detail;
	} else {
		availability = match (read.error) {
			GameReadError.Updating => "CHAIN SNAPSHOT UPDATING. PET STATE UNKNOWN.",
			GameReadError.InvalidState => "INVALID CHAIN SNAPSHOT. PET STATE UNKNOWN.",
		};
	}
	if (lost) {
		say(ui, kit, id + 20, lifeLine(dead.value.pet), LEFT, 664.0, WIDTH, 8.0, DEAD_INK, 0.5);
	} else if (onboardingButton(ui, kit, id + 20, "onboardingCreate", LEFT, 635.0, WIDTH,
		74.0, summoned.toUpperCase(), dead.ok ? heirArrived : summon)) {
		if (dead.ok) {
			markDeathNoticeSeen(heirGeneration);
		} else {
			requestOwnerAction(OwnerAction.Claim, selected as int32, 0);
		}
	}
	say(ui, kit, id + 24, lost ? "" : dead.ok ? heirStatus(dead.value.mourning) : summonStatus(outcome), LEFT, 716.0, WIDTH, 8.0, HOLO_BLUE, 0.5);
	say(ui, kit, id + 21, "MODEL PREVIEW / NO VERIFIED PET STATE.", LEFT, 732.0,
		WIDTH, 8.0, INK_MUTED, 0.5);
	say(ui, kit, id + 22, availability, LEFT, 752.0,
		WIDTH, 8.0, INK_MUTED, 0.5);
	say(ui, kit, id + 23, detail, LEFT, 770.0, WIDTH, 8.0, INK_MUTED, 0.5);
	return selected;
}
