import { Color } from "@metascript/void/src/void2d/types";
import { Ui } from "../ui/ui";
import { Kit, subId, say, INK, INK_BRIGHT } from "./kit";
import { infoPanel, INFO_PANEL_HEIGHT } from "./shapes";
import { hbrnAmount } from "./gameNumbers";
import { petDisplayName } from "./petNames";
import { GameFight, GameNeighbour, SeatKind } from "../host/host";
import { AttackError, Outcome } from "../../rules/fight";
import {
	NeighbourBlock,
	StatVersus,
	Versus,
	ageDays,
	attackNow,
	fading,
	fightsBetween,
	maxLoot,
	rageTowardMe,
	versusMe,
	winChanceBps,
} from "./neighbours";

// The seat Home shows when it shows the owner's own Pet.
export const HOME_SEAT: int32 = -1;
const NO_SEAT: int32 = -1;
const CARD_PAD: float32 = 8.0;
const TEXT_SIZE: float32 = 8.0;
const CARD_ROW: float32 = 13.0;
const PERCENT_BPS: int32 = 100;

// Which neighbour's home is open, HOME_SEAT for the owner's own. The card's win chance runs
// ODDS_DEFAULT_RUNS fights, so it is cached per seat and Block day and only recomputed when either changes.
export interface NeighbourVisit {
	seat: int32;
	chanceSeat: int32;
	chanceEpoch: uint64;
	chance: Result<int32, AttackError>;
}

export function neighbourVisitState(): NeighbourVisit {
	return { seat: HOME_SEAT, chanceSeat: NO_SEAT, chanceEpoch: 0, chance: Result.err(AttackError.NotANeighbor) };
}

// The < > buttons stop at living neighbours only; empty, dead and missing seats have no home to show.
function visitable(kind: SeatKind): boolean {
	return match (kind) {
		SeatKind.Living | SeatKind.Wild => true,
		SeatKind.Empty | SeatKind.Self | SeatKind.Dead | SeatKind.Missing | SeatKind.Invalid => false,
	};
}

// The ring the < > buttons walk: the owner's home, then the visitable seats in seat order.
function visitRing(block: NeighbourBlock): int32[] {
	const ring: int32[] = [HOME_SEAT];
	for (const seat of block.neighbours) {
		if (visitable(seat.kind)) { ring.push(seat.seat); }
	}
	return ring;
}

export function canVisit(block: NeighbourBlock): boolean {
	return (visitRing(block).length as int32) > 1;
}

export function stepVisit(visit: NeighbourVisit, block: NeighbourBlock, forward: boolean): void {
	const ring: int32[] = visitRing(block);
	const count: int32 = ring.length as int32;
	let at: int32 = 0;
	for (let index: int32 = 0; index < count; index += 1) {
		if (ring[index] == visit.seat) { at = index; }
	}
	visit.seat = ring[(at + (forward ? 1 : count - 1)) % count];
}

// "(NEIGHBOUR 3 / 9)" in the order > walks them; "" at home.
export function visitCaption(visit: NeighbourVisit, block: NeighbourBlock): string {
	const ring: int32[] = visitRing(block);
	for (let index: int32 = 1; index < (ring.length as int32); index += 1) {
		if (ring[index] == visit.seat) {
			return "(NEIGHBOUR " + index.toString() + " / " + ((ring.length as int32) - 1).toString() + ")";
		}
	}
	return "";
}

export function visitHome(visit: NeighbourVisit): void {
	visit.seat = HOME_SEAT;
}

export enum NoVisit {
	AtHome,
	SeatLeft,
}

// A seat that stopped being visitable since the last read sends the owner home.
export function visitedNeighbour(visit: NeighbourVisit, block: NeighbourBlock): Result<GameNeighbour, NoVisit> {
	if (visit.seat == HOME_SEAT) { return Result.err(NoVisit.AtHome); }
	for (const seat of block.neighbours) {
		if (seat.seat == visit.seat && visitable(seat.kind)) { return Result.ok(seat); }
	}
	visit.seat = HOME_SEAT;
	return Result.err(NoVisit.SeatLeft);
}

export function neighbourName(seat: GameNeighbour): string {
	if (seat.kind == SeatKind.Wild) { return "WILD PET"; }
	return petDisplayName(seat.nameId, seat.lineageGeneration as uint16).toUpperCase();
}

function slotLabel(seat: int32): string {
	return (seat + 1).toString();
}

function attackReason(error: AttackError): string {
	return match (error) {
		AttackError.Pacifist => "PACIFIST",
		AttackError.OutOfAttacks => "NO ATTACKS LEFT TODAY",
		AttackError.Dead => "YOUR PET IS DEAD",
		AttackError.TargetDead => "DEAD",
		AttackError.NotANeighbor => "NOT A NEIGHBOUR",
		AttackError.Unsettled => "DAY NOT SETTLED YET",
		AttackError.Shielded => "YOU ARE SHIELDED",
		AttackError.TargetShielded => "NEWBORN SHIELD",
		AttackError.AlreadyAttacked => "ALREADY ATTACKED TODAY",
		AttackError.TargetBusy => "BUSY",
		AttackError.Broke => "BURROW TOO SMALL",
	};
}

function versusWord(versus: Versus): string {
	return match (versus) {
		Versus.Weaker => "<",
		Versus.Even => "=",
		Versus.Stronger => ">",
	};
}

function cachedChance(visit: NeighbourVisit, block: NeighbourBlock, seat: GameNeighbour): Result<int32, AttackError> {
	if (visit.chanceSeat != seat.seat || visit.chanceEpoch != block.epoch) {
		visit.chance = winChanceBps(block, seat);
		visit.chanceSeat = seat.seat;
		visit.chanceEpoch = block.epoch;
	}
	return visit.chance;
}

function chanceLine(chance: Result<int32, AttackError>): string {
	if (!chance.ok) { return "WIN CHANCE - " + attackReason(chance.error); }
	return "WIN CHANCE " + (chance.value / PERCENT_BPS).toString() + "%";
}

function lootLine(block: NeighbourBlock, seat: GameNeighbour): string {
	const loot = maxLoot(block, seat);
	if (!loot.ok) { return "MAX LOOT - " + attackReason(loot.error); }
	return "MAX LOOT " + hbrnAmount(loot.value.loot) + " AT STAKE " + hbrnAmount(loot.value.stake);
}

function attackLine(block: NeighbourBlock, seat: GameNeighbour): string {
	const now = attackNow(block, seat);
	if (!now.ok) { return "ATTACK NOW - " + attackReason(now.error); }
	return "ATTACK NOW - READY";
}

function statsLine(block: NeighbourBlock, seat: GameNeighbour): string {
	const compared: Result<StatVersus, AttackError> = versusMe(block, seat);
	if (!compared.ok) { return "STATS - " + attackReason(compared.error); }
	const them = compared.value;
	return "LV " + versusWord(them.level) + "  HP " + versusWord(them.hearts) + "  MIGHT " + versusWord(them.might)
		+ "  GRIT " + versusWord(them.grit) + "  FORAGE " + versusWord(them.forage) + "  HARVEST " + versusWord(them.harvest);
}

function historyLine(block: NeighbourBlock, seat: GameNeighbour): string {
	const fights: GameFight[] = fightsBetween(block, seat.seat);
	let won: int32 = 0;
	for (const fight of fights) {
		const attackerWon: boolean = fight.outcome == Outcome.AttackerWins;
		const iAttacked: boolean = fight.attackerSeat == block.me.seat;
		if (attackerWon == iAttacked) { won += 1; }
	}
	return "FIGHTS WITH YOU " + fights.length.toString() + " - YOU WON " + won.toString();
}

function headerLine(block: NeighbourBlock, seat: GameNeighbour): string {
	let line: string = "SLOT " + slotLabel(seat.seat) + "  LV " + seat.level.toString() + " VS YOUR " + block.me.level.toString()
		+ "  AGE " + ageDays(block, seat).toString() + "D";
	if (seat.kind == SeatKind.Wild) { line += "  WILD"; }
	if (fading(block, seat)) { line += "  FADING"; }
	const rage: int32 = rageTowardMe(block, seat);
	if (rage > 0) { line += "  RAGE " + rage.toString(); }
	return line;
}

// What a fight with this neighbour would look like, and how past ones went.
export function neighbourCard(ui: Ui, kit: Kit, id: int32, visit: NeighbourVisit, block: NeighbourBlock, seat: GameNeighbour, x: float32,
	bottom: float32, width: float32): void {
	const top: float32 = bottom - INFO_PANEL_HEIGHT;
	infoPanel(ui, x, top, width);
	const lines: string[] = [
		headerLine(block, seat),
		chanceLine(cachedChance(visit, block, seat)),
		lootLine(block, seat),
		attackLine(block, seat),
		statsLine(block, seat),
		historyLine(block, seat),
	];
	for (let row: int32 = 0; row < (lines.length as int32); row += 1) {
		const color: Color = row == 0 ? INK_BRIGHT : INK;
		say(ui, kit, subId(id, row), lines[row], x + CARD_PAD, top + CARD_PAD + (row as float32) * CARD_ROW,
			width - CARD_PAD * 2.0, TEXT_SIZE, color, 0.0);
	}
}
