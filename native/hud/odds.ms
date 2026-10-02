import { rgba } from "@metascript/void/src/void2d/types";
import { Ui, box } from "@metascript/void/src/ui/ui";
import { Kit, subId, frame, iconTinted, say, INK, INK_MUTED, EMBER, EMBER_HOT, ALERT_RED, GROWTH_GREEN } from "./kit";
import { FrameLook } from "./frame";
import { spinner } from "./buttons";
import { CHAR_MID } from "./shapes";

const HALF: float32 = 0.5;
const ODDS_WIDTH: float32 = 328.0;
const ODDS_HEIGHT: float32 = 168.0;
const TALLEST_ROUND: float32 = 44.0;

export enum OddsState {
	Ready,
	Computing,
	NotAttackable,
}

export interface Odds {
	winPercent: int32;
	expectedLoot: int32;
	maxLoot: int32;
	// the share of fights that end in each round, 1 to 6
	rounds: float32[];
}

function computing(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, tick: int32): void {
	spinner(ui, x + ODDS_WIDTH * HALF - 8.0, y + 68.0, 16.0, tick);
	say(ui, kit, subId(id, 0), "SIMULATING 2,000 FIGHTS...", x, y + 94.0, ODDS_WIDTH, 8.0, INK_MUTED, 0.5);
}

function notAttackable(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, reason: string): void {
	iconTinted(kit, subId(id, 0), "shield", x + ODDS_WIDTH * HALF - 10.0, y + 58.0, 20.0, rgba(0.7, 0.68, 0.66, 1.0));
	say(ui, kit, subId(id, 1), "NOT ATTACKABLE", x, y + 88.0, ODDS_WIDTH, 8.0, INK, 0.5);
	say(ui, kit, subId(id, 2), reason, x + 18.0, y + 104.0, ODDS_WIDTH - 36.0, 8.0, INK_MUTED, 0.5);
}

function roundsChart(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, rounds: float32[]): void {
	const baseline: float32 = y + 108.0;
	say(ui, kit, subId(id, 6), "ROUNDS", x, y + 44.0, 130.0, 8.0, INK_MUTED, 0.0);
	let most: float32 = 0.0;
	for (const share of rounds) {
		most = share > most ? share : most;
	}
	for (let round: int32 = 0; round < rounds.length; round += 1) {
		const barHeight: float32 = most > 0.0 ? TALLEST_ROUND * rounds[round] / most : 0.0;
		const barX: float32 = x + (round as float32) * 22.0;
		box(ui, barX, baseline - barHeight, 14.0, barHeight, 0.0, rounds[round] == most ? EMBER_HOT : EMBER);
		box(ui, barX, baseline - barHeight, 14.0, 1.0, 0.0, rgba(1.0, 0.75, 0.45, 0.6));
		say(ui, kit, subId(id, 9 + round), (round + 1).toString(), barX, baseline + 4.0, 14.0, 8.0, INK_MUTED, 0.5);
	}
	box(ui, x - 2.0, baseline, 134.0, 1.0, 0.0, CHAR_MID);
}

function ready(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, odds: Odds): void {
	say(ui, kit, subId(id, 0), "WIN CHANCE", x + 18.0, y + 44.0, 120.0, 8.0, INK_MUTED, 0.0);
	say(ui, kit, subId(id, 1), odds.winPercent.toString() + "%", x + 18.0, y + 56.0, 120.0, 16.0,
		odds.winPercent >= 50 ? GROWTH_GREEN : ALERT_RED, 0.0);
	say(ui, kit, subId(id, 2), "EXP. LOOT", x + 18.0, y + 84.0, 70.0, 8.0, INK_MUTED, 0.0);
	say(ui, kit, subId(id, 3), odds.expectedLoot.toString(), x + 18.0, y + 96.0, 70.0, 8.0, INK, 0.0);
	say(ui, kit, subId(id, 4), "MAX LOOT", x + 88.0, y + 84.0, 70.0, 8.0, INK_MUTED, 0.0);
	say(ui, kit, subId(id, 5), odds.maxLoot.toString(), x + 88.0, y + 96.0, 70.0, 8.0, INK, 0.0);
	roundsChart(ui, kit, id, x + 176.0, y, odds.rounds);
	box(ui, x + 18.0, y + ODDS_HEIGHT - 36.0, ODDS_WIDTH - 36.0, 1.0, 0.0, CHAR_MID);
	say(ui, kit, subId(id, 8), "YOUR PET DECIDES ON ITS OWN.", x, y + ODDS_HEIGHT - 26.0, ODDS_WIDTH, 8.0, INK_MUTED, 0.5);
}

// "IF YOUR PET ATTACKS": win chance, loot, and how many rounds the fights last.
export function oddsBlock(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, state: OddsState, odds: Odds, reason: string,
	seed: int32, tick: int32): void {
	frame(kit, id, x, y, ODDS_WIDTH, ODDS_HEIGHT, seed, FrameLook.Normal);
	say(ui, kit, id, "IF YOUR PET ATTACKS", x + 18.0, y + 18.0, ODDS_WIDTH - 36.0, 8.0, EMBER_HOT, 0.0);
	box(ui, x + 18.0, y + 32.0, ODDS_WIDTH - 36.0, 1.0, 0.0, CHAR_MID);
	match (state) {
		OddsState.Computing => computing(ui, kit, id, x, y, tick),
		OddsState.NotAttackable => notAttackable(ui, kit, id, x, y, reason),
		OddsState.Ready => ready(ui, kit, id, x, y, odds),
	};
}
