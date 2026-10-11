import {
	GameFight,
	GameNeighbour,
	GameRead,
	GameReadState,
	PetLife,
	Persona,
	SeatKind,
	gameRead,
	noGamePet,
} from "../host/host";
import { NotLive, livePet } from "./gameAvailability";
import { PetActivity } from "./activity";
import { stakeSplit } from "../../rules/emission";
import { BPS } from "../../rules/units";
import { Region, noMods } from "../../rules/stats";
import { Tree } from "../../rules/tree";
import { Gear, Item, ItemSkill, bare, wardedLoot } from "../../rules/items";
import { TalentKind } from "../../rules/talent";
import {
	AttackError,
	Outcome,
	lootFor,
	maxStake,
} from "../../rules/fight";
import {
	BlockSlot,
	Pet,
	combatantFacing,
	onFightDay,
	rageAt,
	stats,
} from "../../rules/layout";
import { STAKE_LEVELS, StakeLevel, attackable, stakeAt } from "../../rules/actions";
import { ODDS_DEFAULT_RUNS, winChanceAgainst } from "../../rules/winOdds";
import { vigorBps } from "../../rules/life";

export struct NeighbourBlock {
	epoch: uint64;
	me: GameNeighbour;
	neighbours: GameNeighbour[];
	fights: GameFight[];
}

export struct LootOutlook {
	stake: uint64;
	loot: uint64;
}

export enum Versus {
	Weaker,
	Even,
	Stronger,
}

export struct StatVersus {
	level: Versus;
	hearts: Versus;
	might: Versus;
	grit: Versus;
	forage: Versus;
	harvest: Versus;
	burrow: Versus;
}

export enum RelationshipError {
	NoChainWriter,
}

export function neighbourBlock(snapshot: GameRead): Result<NeighbourBlock, NotLive> {
	const pet = try livePet(snapshot);
	const neighbours: GameNeighbour[] = [];
	let selves: GameNeighbour[] = [];
	for (const seat of snapshot.seats) {
		if (seat.kind == SeatKind.Self) { selves.push(seat); } else { neighbours.push(seat); }
	}
	if (selves.length != 1) { return Result.err(NotLive.Inconsistent); }
	return Result.ok({
		epoch: pet.blockEpoch,
		me: selves[0],
		neighbours: neighbours,
		fights: snapshot.fights,
	});
}

export function currentNeighbourBlock(): Result<NeighbourBlock, NotLive> {
	const read = gameRead();
	if (!read.ok) { return Result.err(NotLive.NoPetRead); }
	return neighbourBlock(read.value);
}

function alive(life: PetLife): boolean {
	return life == PetLife.FirstLifeActive || life == PetLife.HeirActive;
}

export function rulesPet(this seat: GameNeighbour): Pet {
	return {
		blockId: 0,
		slot: seat.seat as uint8,
		alive: alive(seat.life),
		region: (seat.region as int32) as uint8,
		hearts: seat.hearts as uint8,
		maxHearts: seat.maxHearts as uint8,
		forage: seat.forage as uint16,
		might: seat.might as uint16,
		grit: seat.grit as uint16,
		level: seat.level as uint16,
		pointsUnspent: 0,
		xp: 0,
		tree: Tree.empty(),
		foodBps: 0,
		experienceBps: 0,
		lootBps: seat.lootBps,
		biteGuardBps: seat.biteGuardBps,
		mods: seat.mods,
		harvest: seat.harvest,
		burrow: seat.burrow,
		rewardSnapshot: 0,
		bornEpoch: seat.bornEpoch,
		lastTickEpoch: seat.lastTickEpoch,
		fightsOutToday: seat.fightsOutToday as uint8,
		fightsInToday: seat.fightsInToday as uint8,
		bitesInToday: seat.bitesInToday as uint8,
		slotsAttackedToday: seat.slotsAttackedToday,
		fightDay: seat.fightDay,
		growthMultiplierBps: 0,
		growthMultiplierExpiry: 0,
		minHearts: 0,
		pantry: { small: 0, medium: 0, large: 0 },
		foodBoughtToday: 0,
		talentKind: (seat.talentKind as int32) as uint8,
		talentBps: seat.talentBps as uint16,
		insurance: 0,
		scars: 0,
		lineageGeneration: seat.lineageGeneration as uint16,
		bonding: 0,
		engagedToday: 0,
		ownerFedToday: 0,
		giftOwed: 0,
		ownerBankReadyAt: 0,
		gear: seat.gear,
		grudgeSlot: seat.grudgeSlot as uint8,
		rage: seat.rage as uint8,
		rageEpoch: seat.rageEpoch,
		ownerFirst: 0,
		ownerSecond: 0,
		skin: 0,
		wild: seat.kind == SeatKind.Wild,
		engagedRound: 0,
	};
}

function recordedPet(seat: GameNeighbour): Result<Pet, AttackError> {
	return match (seat.kind) {
		SeatKind.Living | SeatKind.Wild | SeatKind.Dead => Result.ok(seat.rulesPet()),
		SeatKind.Empty | SeatKind.Self | SeatKind.Missing | SeatKind.Invalid =>
			Result.err(AttackError.NotANeighbor),
	};
}

function opponent(seat: GameNeighbour): Result<Pet, AttackError> {
	const pet = try recordedPet(seat);
	if (seat.kind == SeatKind.Dead) { return Result.err(AttackError.TargetDead); }
	return Result.ok(pet);
}

export function winChanceBps(
	block: NeighbourBlock,
	seat: GameNeighbour,
): Result<int32, AttackError> {
	const them = try opponent(seat);
	const me = block.me.rulesPet();
	const seed = block.epoch * 16 + (seat.seat as uint64);
	const defender = them.combatantFacing(me);
	return Result.ok(me.combatantFacing(them).winChanceAgainst(defender, seed, ODDS_DEFAULT_RUNS));
}

export function attackNow(block: NeighbourBlock, seat: GameNeighbour): Result<uint64, AttackError> {
	const them = try opponent(seat);
	return block.me.rulesPet().attackable(them, block.epoch);
}

function highestStake(attacker: Pet, stakeCap: uint64): Result<uint64, AttackError> {
	for (let ordinal = STAKE_LEVELS - 1; ordinal >= 0; ordinal--) {
		const stake = attacker.stakeAt(stakeCap, ordinal as StakeLevel);
		if (stake.ok) { return Result.ok(stake.value); }
	}
	return Result.err(AttackError.Broke);
}

// Keep in step with the loot lines of rules/actions.ms settleAttack.
export function maxLoot(
	block: NeighbourBlock,
	seat: GameNeighbour,
): Result<LootOutlook, AttackError> {
	const defender = (try opponent(seat)).onFightDay(block.epoch);
	const attacker = block.me.rulesPet().onFightDay(block.epoch);
	const stake = try highestStake(attacker, maxStake(defender.harvest));
	const baseLoot = defender.combatantFacing(attacker).lootFor(
		attacker.combatantFacing(defender),
		stake,
		defender.harvest,
		defender.fightsInToday as int32,
	);
	const lootBps = (BPS + attacker.stats().lootBps) as uint64;
	const boosted = Math.min(baseLoot * lootBps / (BPS as uint64), defender.harvest);
	return Result.ok({ stake: stake, loot: defender.gear.wardedLoot(boosted) });
}

function versus(theirs: uint64, mine: uint64): Versus {
	if (theirs > mine) { return Versus.Stronger; }
	if (theirs < mine) { return Versus.Weaker; }
	return Versus.Even;
}

function versusInt(theirs: int32, mine: int32): Versus {
	return versus(Math.max(theirs, 0) as uint64, Math.max(mine, 0) as uint64);
}

export function versusMe(
	block: NeighbourBlock,
	seat: GameNeighbour,
): Result<StatVersus, AttackError> {
	const them = try recordedPet(seat);
	const me = block.me.rulesPet();
	const theirFight = them.combatantFacing(me);
	const myFight = me.combatantFacing(them);
	return Result.ok({
		level: versusInt(seat.level, block.me.level),
		hearts: versusInt(seat.hearts, block.me.hearts),
		might: versusInt(theirFight.might, myFight.might),
		grit: versusInt(theirFight.grit, myFight.grit),
		forage: versusInt(them.stats().forage, me.stats().forage),
		harvest: versus(seat.harvest, block.me.harvest),
		burrow: versus(seat.burrow, block.me.burrow),
	});
}

export function ageDays(block: NeighbourBlock, seat: GameNeighbour): uint64 {
	return block.epoch > seat.bornEpoch ? block.epoch - seat.bornEpoch : 0;
}

export function fading(block: NeighbourBlock, seat: GameNeighbour): boolean {
	return vigorBps(ageDays(block, seat)) < BPS;
}

export function rageTowardMe(block: NeighbourBlock, seat: GameNeighbour): int32 {
	if (seat.grudgeSlot != block.me.seat) { return 0; }
	return seat.rulesPet().rageAt(block.epoch) as int32;
}

export function relationship(
	block: NeighbourBlock,
	seat: GameNeighbour,
): Result<int32, RelationshipError> {
	return Result.err(RelationshipError.NoChainWriter);
}

// A ring record names seats, not Pets: a fight before a seat changed hands lists the new occupant.
export function fightsBetween(block: NeighbourBlock, seat: int32): GameFight[] {
	const fights: GameFight[] = [];
	const mine = block.me.seat;
	for (const fight of block.fights) {
		const pair = (fight.attackerSeat == mine && fight.defenderSeat == seat) ||
			(fight.attackerSeat == seat && fight.defenderSeat == mine);
		if (pair) { fights.push(fight); }
	}
	return fights;
}

export function myFights(block: NeighbourBlock): GameFight[] {
	const fights: GameFight[] = [];
	for (const fight of block.fights) {
		const mine = fight.attackerSeat == block.me.seat || fight.defenderSeat == block.me.seat;
		if (mine) { fights.push(fight); }
	}
	return fights;
}

// My fights as activity rows, newest first; seats show as slot numbers (seat + 1), amounts in HBRN base units.
export function fightActivities(block: NeighbourBlock): PetActivity[] {
	const mine = myFights(block);
	const rows: PetActivity[] = [];
	for (let index = (mine.length as int32) - 1; index >= 0; index--) {
		const fight = mine[index];
		const attacked = fight.attackerSeat == block.me.seat;
		const other: int32 = (attacked ? fight.defenderSeat : fight.attackerSeat) + 1;
		const won = fight.outcome == Outcome.AttackerWins;
		const slot: string = other.toString();
		const line: string = attacked
			? (won ? "RAIDED SLOT " + slot : "ATTACKED SLOT " + slot + " - LOST")
			: (won ? "ROBBED BY SLOT " + slot : "HELD OFF SLOT " + slot);
		// rules/actions.ms attackerWon and defenderHeld: the winner keeps the share stakeSplit leaves
		// after the treasury fee; a Cannibal's devoured burrow is not in the record.
		const [winnings, _raidFee] = stakeSplit(fight.loot);
		const [keptStake, _heldFee] = stakeSplit(fight.stake);
		const amount: int64 = attacked
			? (won ? winnings as int64 : -(fight.stake as int64))
			: (won ? -(fight.loot as int64) : keptStake as int64);
		rows.push({
			day: (block.epoch - fight.epoch) as int32,
			glyph: attacked == won ? "fightWon" : "fightLost",
			line: line,
			amount: amount,
			slot: other,
		});
	}
	return rows;
}

function seatOf(seat: int32, kind: SeatKind): GameNeighbour {
	return {
		seat: seat,
		kind: kind,
		life: PetLife.FirstLifeActive,
		level: 5,
		hearts: 10,
		maxHearts: 12,
		forage: 70,
		might: 80,
		grit: 50,
		mods: noMods(),
		lootBps: 0,
		biteGuardBps: 0,
		harvest: 30000000,
		burrow: 50000000,
		bornEpoch: 1,
		lastTickEpoch: 40,
		fightDay: 40,
		fightsOutToday: 0,
		fightsInToday: 0,
		bitesInToday: 0,
		slotsAttackedToday: 0 as BitSet<BlockSlot>,
		grudgeSlot: 255,
		rage: 0,
		rageEpoch: 0,
		region: Region.Fighter,
		persona: Persona.Greedy,
		lineageGeneration: 0,
		talentKind: TalentKind.None,
		talentBps: BPS,
		blockGrudgeRobber: 0,
		blockGrudgeEpoch: 0,
		nameId: 0,
		tree: 0,
		gear: Gear.bare(),
	};
}

function fightOf(attackerSeat: int32, defenderSeat: int32, epoch: uint64): GameFight {
	const fighter = seatOf(0, SeatKind.Living).rulesPet();
	return {
		epoch: epoch,
		seed: 9,
		stake: 5000000,
		loot: 100,
		attackerSeat: attackerSeat,
		defenderSeat: defenderSeat,
		rounds: 3,
		outcome: Outcome.AttackerWins,
		attacker: fighter.combatantFacing(fighter),
		defender: fighter.combatantFacing(fighter),
	};
}

// Seat 4 is mine; on day 40 seats 7 and 9 robbed it.
export function blockRead(): GameRead {
	const seats: GameNeighbour[] = [];
	for (let seat = 0; seat < 10; seat++) {
		const kind = match (seat) {
			4 => SeatKind.Self,
			2 => SeatKind.Empty,
			3 => SeatKind.Dead,
			5 => SeatKind.Wild,
			6 => SeatKind.Missing,
			8 => SeatKind.Invalid,
			_ => SeatKind.Living,
		};
		seats.push(seatOf(seat, kind));
	}
	seats[3].life = PetLife.DeathRecorded;
	seats[0].might = 400;
	seats[0].grit = 300;
	seats[1].might = 20;
	return {
		ownerRevision: 2,
		state: GameReadState.PetFound,
		baseSlot: 10,
		ephemeralSlot: 20,
		admissionHoldings: 1,
		admissionMembers: 1,
		unclaimedMembers: 0,
		detail: "",
		ageSeconds: 30,
		pet: {
			...noGamePet(),
			life: PetLife.FirstLifeActive,
			delegated: true,
			member: true,
			blockStarted: true,
			blockEpoch: 40,
			worldDay: 41,
			level: 2,
			xp: 191,
			hearts: 8,
			maxHearts: 18,
		},
		seats: seats,
		fights: [fightOf(4, 7, 38), fightOf(1, 2, 39), fightOf(7, 4, 40), fightOf(9, 4, 40)],
	};
}

function liveBlock(): NeighbourBlock {
	const block = neighbourBlock(blockRead());
	if (!block.ok) { unreachable; }
	return block.value;
}

test "my Block splits into me and the nine other seats in seat order" {
	const block = liveBlock();
	assert block.me.seat == 4 && block.epoch == 40;
	assert block.neighbours.length == 9;
	assert block.neighbours[3].seat == 3 && block.neighbours[4].seat == 5;
	let twoSelves = blockRead();
	twoSelves.seats[0].kind = SeatKind.Self;
	const refused = neighbourBlock(twoSelves);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == NotLive.Inconsistent; }
	let stale = blockRead();
	stale.ageSeconds = 1000;
	assert !neighbourBlock(stale).ok;
}

test "win chance follows the neighbour's strength and refuses seats without a living Pet" {
	const block = liveBlock();
	const strong = winChanceBps(block, block.neighbours[0]);
	const weak = winChanceBps(block, block.neighbours[1]);
	const wild = winChanceBps(block, block.neighbours[4]);
	assert strong.ok && weak.ok && wild.ok;
	if (strong.ok && weak.ok) { assert strong.value < weak.value; }
	if (weak.ok) { assert weak.value > 0 && weak.value <= BPS; }
	const empty = winChanceBps(block, block.neighbours[2]);
	const dead = winChanceBps(block, block.neighbours[3]);
	const missing = winChanceBps(block, block.neighbours[5]);
	const invalid = winChanceBps(block, block.neighbours[7]);
	assert !empty.ok && !dead.ok && !missing.ok && !invalid.ok;
	if (!empty.ok) { assert empty.error == AttackError.NotANeighbor; }
	if (!dead.ok) { assert dead.error == AttackError.TargetDead; }
	if (!missing.ok && !invalid.ok) {
		assert missing.error == AttackError.NotANeighbor;
		assert invalid.error == AttackError.NotANeighbor;
	}
	assert !winChanceBps(block, block.me).ok;
}

test "max loot is the settled loot at the largest affordable stake" {
	const block = liveBlock();
	const seven = block.neighbours[6];
	assert seven.seat == 7;
	const loot = maxLoot(block, seven);
	assert loot.ok;
	if (loot.ok) { assert loot.value.stake == 20000000 && loot.value.loot == 30000000; }
	let warded = seven;
	const antiRobbery: Item = {
		rarity: 1,
		stat: 0,
		wear: 0,
		skill: ItemSkill.AntiRobbery as uint8,
		level: 1,
	};
	warded.gear = { ...warded.gear, feet: antiRobbery };
	const cut = maxLoot(block, warded);
	assert cut.ok;
	if (cut.ok) { assert cut.value.loot == 18000000; }
	let poor = block;
	poor.me.burrow = 1;
	const broke = maxLoot(poor, seven);
	assert !broke.ok;
	if (!broke.ok) { assert broke.error == AttackError.Broke; }
}

test "attacking now reports the rules' reason when it cannot happen" {
	const block = liveBlock();
	const seven = block.neighbours[6];
	const now = attackNow(block, seven);
	assert now.ok;
	if (now.ok) { assert now.value == 20000000; }
	let unsettled = seven;
	unsettled.lastTickEpoch = 39;
	const waiting = attackNow(block, unsettled);
	assert !waiting.ok;
	if (!waiting.ok) { assert waiting.error == AttackError.Unsettled; }
	let newborn = seven;
	newborn.bornEpoch = 39;
	const shielded = attackNow(block, newborn);
	assert !shielded.ok;
	if (!shielded.ok) { assert shielded.error == AttackError.TargetShielded; }
}

test "stats compare from the neighbour's side, rage included" {
	const block = liveBlock();
	const strong = versusMe(block, block.neighbours[0]);
	assert strong.ok;
	if (strong.ok) {
		assert strong.value.might == Versus.Stronger && strong.value.grit == Versus.Stronger;
		assert strong.value.forage == Versus.Even && strong.value.harvest == Versus.Even;
	}
	let angry = block.neighbours[6];
	angry.grudgeSlot = 4;
	angry.rage = 2;
	angry.rageEpoch = 39;
	assert rageTowardMe(block, angry) == 2;
	const enraged = versusMe(block, angry);
	assert enraged.ok;
	if (enraged.ok) { assert enraged.value.might == Versus.Stronger; }
	angry.rageEpoch = 30;
	assert rageTowardMe(block, angry) == 0;
	const dead = versusMe(block, block.neighbours[3]);
	assert dead.ok;
	assert !versusMe(block, block.neighbours[2]).ok;
}

test "age fades past day fifty and relationships have no chain writer" {
	let block = liveBlock();
	const seven = block.neighbours[6];
	assert ageDays(block, seven) == 39 && !fading(block, seven);
	block.epoch = 52;
	assert fading(block, seven);
	assert !relationship(block, seven).ok;
}

test "the fight ring gives my fights and the ones with one neighbour, oldest first" {
	const block = liveBlock();
	const withSeven = fightsBetween(block, 7);
	assert withSeven.length == 2;
	assert withSeven[0].epoch == 38 && withSeven[1].attackerSeat == 7;
	assert fightsBetween(block, 1).length == 0;
	const mine = myFights(block);
	assert mine.length == 3 && mine[2].attackerSeat == 9;
}

test "my fights read as activity rows, newest first, in slot numbers with signed base-unit amounts" {
	const rows = fightActivities(liveBlock());
	assert rows.length == 3;
	assert rows[0].line == "ROBBED BY SLOT 10" && rows[0].amount == -100 && rows[0].glyph == "fightLost" && rows[0].day == 0;
	assert rows[2].line == "RAIDED SLOT 8" && rows[2].amount == (stakeSplit(100)[0] as int64) && rows[2].glyph == "fightWon";
	assert rows[2].day == 2;
	assert rows[2].slot == 8;
	const held = liveBlock();
	held.fights[3].outcome = Outcome.DefenderWins;
	held.fights[0].outcome = Outcome.DefenderWins;
	const heldRows = fightActivities(held);
	assert heldRows[0].line == "HELD OFF SLOT 10" && heldRows[0].amount == (stakeSplit(5000000)[0] as int64);
	assert heldRows[2].line == "ATTACKED SLOT 8 - LOST" && heldRows[2].amount == -5000000;
}
