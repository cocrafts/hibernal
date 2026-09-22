import { BPS, HBRN_UNIT } from "./units";
import { Region, Stats, aged } from "./stats";
import { TREE_NODES, AllocationError, nodeCost } from "./tree";
import { BLOCK_SLOTS, BlockSlot, Pet, GlobalConfig, FightRecord } from "./layout";
import { Food, Split, foodCost, foodHearts, stakeSplit } from "./emission";
import {
	INCOMING_CAP,
	MIN_BITE_STAKE,
	AttackError,
	Outcome,
	maxStake,
	biteAllowed,
} from "./fight";
import { DEFENSE_WIN_XP, DEFENSE_LOSS_XP, raidXp, gainXp } from "./level";
import {
	PetAndGlobal,
	genesis,
	withSpend,
	withProtocolFee,
	withWorkPower,
	born,
	tickTo,
	vigor,
} from "./life";

export enum EconomyAction {
	Rest,
	Bank,
	EatSmall,
	EatMedium,
	EatLarge,
}

export enum StakeLevel {
	Quarter,
	Half,
	ThreeQuarters,
	Whole,
}

export const STAKE_LEVELS: int32 = (StakeLevel.Whole as int32) + 1;
export const ALLOCATE_HOLD: int32 = TREE_NODES;
export const ATTACK_HOLD: int32 = BLOCK_SLOTS * STAKE_LEVELS;

export enum EconomyError {
	Dead,
	EmptyHarvest,
	Full,
	Broke,
}

export struct NodeMask {
	bits: uint64;
}

export struct AttackMask {
	bits: uint64;
}

export struct FightSettlement {
	attacker: Pet;
	defender: Pet;
	global: GlobalConfig;
	record: FightRecord;
}

export function stakeShareBps(level: StakeLevel): int32 {
	return match (level) {
		StakeLevel.Quarter => 2500,
		StakeLevel.Half => 5000,
		StakeLevel.ThreeQuarters => 7500,
		StakeLevel.Whole => 10000,
	};
}

export function attackChoice(slot: BlockSlot, level: StakeLevel): int32 {
	return (slot as int32) * STAKE_LEVELS + (level as int32);
}

function bitOf(id: int32): uint64 {
	return (1 as uint64) << (id as uint64);
}

export function nodeHoldMask(): NodeMask {
	return { bits: bitOf(ALLOCATE_HOLD) };
}

export function allowsNode(this mask: NodeMask, id: int32): boolean {
	return (mask.bits & bitOf(id)) != 0;
}

export function allowingNode(this mask: NodeMask, id: int32): NodeMask {
	return { bits: mask.bits | bitOf(id) };
}

export function attackHoldMask(): AttackMask {
	return { bits: bitOf(ATTACK_HOLD) };
}

export function allowsChoice(this mask: AttackMask, choice: int32): boolean {
	return (mask.bits & bitOf(choice)) != 0;
}

export function allowsAttack(this mask: AttackMask, slot: BlockSlot, level: StakeLevel): boolean {
	return mask.allowsChoice(attackChoice(slot, level));
}

export function allowingAttack(
	this mask: AttackMask,
	slot: BlockSlot,
	level: StakeLevel,
): AttackMask {
	return { bits: mask.bits | bitOf(attackChoice(slot, level)) };
}

export function bank(this pet: Pet, global: GlobalConfig): Result<PetAndGlobal, EconomyError> {
	if (!pet.alive) { return Result.err(EconomyError.Dead); }
	if (pet.harvest == 0) { return Result.err(EconomyError.EmptyHarvest); }
	return Result.ok({
		pet: { ...pet, harvest: 0, burrow: pet.burrow + pet.harvest },
		global: global,
	});
}

export function eat(
	this pet: Pet,
	food: Food,
	global: GlobalConfig,
): Result<PetAndGlobal, EconomyError> {
	if (!pet.alive) { return Result.err(EconomyError.Dead); }
	if (pet.hearts >= pet.maxHearts) { return Result.err(EconomyError.Full); }
	const cost = foodCost(food, pet.level as int32);
	if (pet.burrow < cost) { return Result.err(EconomyError.Broke); }
	const hearts = Math.min((pet.hearts as int32) + foodHearts(food), pet.maxHearts as int32);
	return Result.ok({
		pet: { ...pet, hearts: hearts as uint8, burrow: pet.burrow - cost },
		global: global.withSpend(Split.ofSpend(cost)),
	});
}

export function doEconomy(
	this pet: Pet,
	action: EconomyAction,
	global: GlobalConfig,
): Result<PetAndGlobal, EconomyError> {
	if (!pet.alive) { return Result.err(EconomyError.Dead); }
	return match (action) {
		EconomyAction.Rest => Result.ok({ pet: pet, global: global }),
		EconomyAction.Bank => pet.bank(global),
		EconomyAction.EatSmall => pet.eat(Food.Small, global),
		EconomyAction.EatMedium => pet.eat(Food.Medium, global),
		EconomyAction.EatLarge => pet.eat(Food.Large, global),
	};
}

export function legalEconomy(this pet: Pet, global: GlobalConfig): BitSet<EconomyAction> {
	let legal = 0 as BitSet<EconomyAction>;
	for (let ordinal = 0; ordinal <= (EconomyAction.EatLarge as int32); ordinal++) {
		const action = ordinal as EconomyAction;
		if (pet.doEconomy(action, global).ok) { legal = legal.incl(action); }
	}
	return legal;
}

export function allocateNode(
	this pet: Pet,
	id: int32,
	global: GlobalConfig,
): Result<PetAndGlobal, AllocationError> {
	if (!pet.alive) { return Result.err(AllocationError.Dead); }
	const settled = pet.lastTickEpoch == global.rewardEpoch &&
		pet.rewardSnapshot == global.rewardPerWorkPower;
	if (!settled) { return Result.err(AllocationError.Unsettled); }
	const cost = nodeCost(id);
	if ((pet.pointsUnspent as int32) < cost) { return Result.err(AllocationError.NoPoints); }
	const tree = try pet.tree.allocate(id, pet.startRegion());
	const derived = Stats.fromTree(tree).aged(pet.vigor());
	const grown: Pet = {
		...pet,
		tree: tree,
		forage: derived.forage as uint16,
		might: derived.might as uint16,
		grit: derived.grit as uint16,
		maxHearts: derived.maxHearts as uint8,
		hearts: Math.min(pet.hearts as int32, derived.maxHearts) as uint8,
		pointsUnspent: ((pet.pointsUnspent as int32) - cost) as uint8,
	};
	return Result.ok({
		pet: grown,
		global: global.withWorkPower(pet.stats().workPower(), grown.stats().workPower()),
	});
}

export function legalNodes(this pet: Pet, global: GlobalConfig): NodeMask {
	if (!pet.alive) { return { bits: 0 }; }
	let mask = nodeHoldMask();
	for (let id = 0; id < TREE_NODES; id++) {
		if (pet.allocateNode(id, global).ok) { mask = mask.allowingNode(id); }
	}
	return mask;
}

export function attackable(
	this attacker: Pet,
	defender: Pet,
	epoch: uint64,
): Result<uint64, AttackError> {
	if (!attacker.alive) { return Result.err(AttackError.Dead); }
	if (!defender.alive) { return Result.err(AttackError.TargetDead); }
	if (attacker.blockId != defender.blockId || attacker.slot == defender.slot) {
		return Result.err(AttackError.NotANeighbor);
	}
	if (attacker.lastTickEpoch != epoch || defender.lastTickEpoch != epoch) {
		return Result.err(AttackError.Unsettled);
	}
	if (attacker.shieldedAt(epoch)) { return Result.err(AttackError.Shielded); }
	if (defender.shieldedAt(epoch)) { return Result.err(AttackError.TargetShielded); }
	const _left = try attacker.combatant().attacksLeft(attacker.fightsOutOn(epoch));
	if (attacker.attackedOn(defender.blockSlot(), epoch)) {
		return Result.err(AttackError.AlreadyAttacked);
	}
	if (defender.fightsInOn(epoch) >= INCOMING_CAP) { return Result.err(AttackError.TargetBusy); }
	return Result.ok(maxStake(defender.harvest));
}

export function stakeAt(
	this attacker: Pet,
	stakeCap: uint64,
	level: StakeLevel,
): Result<uint64, AttackError> {
	const share = stakeCap * (stakeShareBps(level) as uint64) / (BPS as uint64);
	const stake = Math.max(share, MIN_BITE_STAKE);
	if (attacker.burrow < stake) { return Result.err(AttackError.Broke); }
	return Result.ok(stake);
}

export function stakeFor(
	this attacker: Pet,
	defender: Pet,
	level: StakeLevel,
	epoch: uint64,
): Result<uint64, AttackError> {
	const stakeCap = try attacker.attackable(defender, epoch);
	return attacker.stakeAt(stakeCap, level);
}

export function attacksOn(
	this mask: AttackMask,
	attacker: Pet,
	defender: Pet,
	epoch: uint64,
): AttackMask {
	const capped = attacker.attackable(defender, epoch);
	if (!capped.ok) { return mask; }
	let allowed = mask;
	for (let ordinal = 0; ordinal < STAKE_LEVELS; ordinal++) {
		const level = ordinal as StakeLevel;
		if (attacker.stakeAt(capped.value, level).ok) {
			allowed = allowed.allowingAttack(defender.blockSlot(), level);
		}
	}
	return allowed;
}

export function settleAttack(
	this attacker: Pet,
	defender: Pet,
	level: StakeLevel,
	global: GlobalConfig,
	epoch: uint64,
	seed: uint64,
): Result<FightSettlement, AttackError> {
	const stake = try attacker.stakeFor(defender, level, epoch);
	const attackerToday = attacker.onFightDay(epoch);
	const defenderToday = defender.onFightDay(epoch);
	const attackerCombatant = attackerToday.combatant();
	const defenderCombatant = defenderToday.combatant();
	const result = attackerCombatant.fight(defenderCombatant, seed);
	const committed: Pet = {
		...attackerToday,
		burrow: attackerToday.burrow - stake,
		fightsOutToday: ((attackerToday.fightsOutToday as int32) + 1) as uint8,
		slotsAttackedToday: attackerToday.slotsAttackedToday.incl(defender.blockSlot()),
	};
	const struck: Pet = {
		...defenderToday,
		fightsInToday: ((defenderToday.fightsInToday as int32) + 1) as uint8,
	};
	const record: FightRecord = {
		epoch: epoch,
		seed: seed,
		attackerSlot: attacker.slot as int32,
		defenderSlot: defender.slot as int32,
		attacker: attackerCombatant,
		defender: defenderCombatant,
		stake: stake,
		loot: 0,
		outcome: result.outcome,
		rounds: result.rounds,
	};
	if (result.outcome == Outcome.AttackerWins) {
		const harvestBefore = defenderToday.harvest;
		const loot = defenderCombatant.lootFor(
			stake,
			harvestBefore,
			defenderToday.fightsInToday as int32,
		);
		const [winnings, fee] = stakeSplit(loot);
		const bite = biteAllowed(
			harvestBefore,
			attackerToday.stats().power(),
			defenderToday.stats().power(),
			defenderToday.bitesInToday as int32,
		);
		const bites = bite ? 1 : 0;
		const hearts = (struck.hearts as int32) - bites;
		const robbed: Pet = {
			...struck,
			alive: hearts > 0,
			hearts: hearts as uint8,
			harvest: struck.harvest - loot,
			bitesInToday: ((struck.bitesInToday as int32) + bites) as uint8,
		};
		const raider: Pet = { ...committed, burrow: committed.burrow + stake + winnings };
		const paid = global.withProtocolFee(fee);
		return Result.ok({
			attacker: raider.gainXp(raidXp(loot)),
			defender: robbed.gainXp(DEFENSE_LOSS_XP),
			global: robbed.alive ? paid : paid.withWorkPower(robbed.stats().workPower(), 0),
			record: { ...record, loot: loot },
		});
	}
	const [kept, fee] = stakeSplit(stake);
	const hearts = (committed.hearts as int32) - 1;
	const beaten: Pet = { ...committed, alive: hearts > 0, hearts: hearts as uint8 };
	const holder: Pet = { ...struck, burrow: struck.burrow + kept };
	const paid = global.withProtocolFee(fee);
	return Result.ok({
		attacker: beaten,
		defender: holder.gainXp(DEFENSE_WIN_XP),
		global: beaten.alive ? paid : paid.withWorkPower(beaten.stats().workPower(), 0),
		record: record,
	});
}

const DUEL_EPOCH: uint64 = 5;

struct Duel {
	attacker: Pet;
	defender: Pet;
	global: GlobalConfig;
}

function readyAt(this pet: Pet, global: GlobalConfig, epoch: uint64): PetAndGlobal {
	const result = pet.tickTo(global, epoch);
	if (!result.ok) { unreachable; }
	return result.value;
}

function duelOver(defenderHarvest: uint64): Duel {
	const fighter = Pet.born(0, BlockSlot.First, Region.Fighter, 0, GlobalConfig.genesis(0));
	const worker = Pet.born(0, BlockSlot.Second, Region.Worker, 0, fighter.global);
	const attacker = fighter.pet.readyAt(worker.global, DUEL_EPOCH);
	const defender = worker.pet.readyAt(attacker.global, DUEL_EPOCH);
	return {
		attacker: { ...attacker.pet, hearts: 5, burrow: 1000 * HBRN_UNIT },
		defender: { ...defender.pet, hearts: 5, harvest: defenderHarvest, burrow: 40 * HBRN_UNIT },
		global: defender.global,
	};
}

function totalMoney(this duel: Duel): uint64 {
	return duel.attacker.burrow +
		duel.defender.harvest +
		duel.defender.burrow +
		duel.global.protocolPending;
}

function totalMoney(this settlement: FightSettlement): uint64 {
	return settlement.attacker.burrow +
		settlement.defender.harvest +
		settlement.defender.burrow +
		settlement.global.protocolPending;
}

function refusalOf(result: Result<uint64, AttackError>): AttackError {
	if (result.ok) { unreachable; }
	return result.error;
}

function settledOn(this duel: Duel, level: StakeLevel, seed: uint64): FightSettlement {
	const result = duel.attacker.settleAttack(duel.defender, level, duel.global, DUEL_EPOCH, seed);
	if (!result.ok) { unreachable; }
	return result.value;
}

test "action ids and masks" {
	assert attackChoice(BlockSlot.First, StakeLevel.Quarter) == 0;
	assert attackChoice(BlockSlot.Tenth, StakeLevel.Whole) == ATTACK_HOLD - 1;
	assert ALLOCATE_HOLD == TREE_NODES;
	const noAttacks: AttackMask = { bits: 0 };
	const attacks = noAttacks.allowingAttack(BlockSlot.Fourth, StakeLevel.ThreeQuarters);
	assert attacks.allowsAttack(BlockSlot.Fourth, StakeLevel.ThreeQuarters);
	assert !attacks.allowsAttack(BlockSlot.Third, StakeLevel.Whole);
	assert !attacks.allowsChoice(ATTACK_HOLD);
	assert attackHoldMask().allowsChoice(ATTACK_HOLD);
	const noNodes: NodeMask = { bits: 0 };
	const nodes = noNodes.allowingNode(TREE_NODES - 1);
	assert nodes.allowsNode(TREE_NODES - 1);
	assert !nodes.allowsNode(0);
	assert !nodes.allowsNode(ALLOCATE_HOLD);
	assert nodeHoldMask().allowsNode(ALLOCATE_HOLD);
}

test "bank moves harvest and eating needs room and money" {
	const newborn = Pet.born(0, BlockSlot.First, Region.Worker, 0, GlobalConfig.genesis(0));
	const earner: Pet = { ...newborn.pet, harvest: 500 };
	const banked = earner.bank(newborn.global);
	assert banked.ok;
	if (banked.ok) { assert banked.value.pet.harvest == 0 && banked.value.pet.burrow == 500; }
	assert !newborn.pet.bank(newborn.global).ok;
	const full = newborn.pet.eat(Food.Small, newborn.global);
	assert !full.ok;
	if (!full.ok) { assert full.error == EconomyError.Full; }
	const hurt: Pet = { ...newborn.pet, hearts: 2 };
	const broke = hurt.eat(Food.Small, newborn.global);
	assert !broke.ok;
	if (!broke.ok) { assert broke.error == EconomyError.Broke; }
	const cost = foodCost(Food.Medium, 1);
	const hurtWithMoney: Pet = { ...hurt, burrow: cost };
	const fed = hurtWithMoney.eat(Food.Medium, newborn.global);
	assert fed.ok;
	if (fed.ok) {
		const spend = fed.value.global;
		assert fed.value.pet.hearts == 4;
		assert fed.value.pet.burrow == 0;
		assert spend.recycledPending + spend.burned + spend.protocolPending == cost;
	}
}

test "the economy mask is exactly the actions that apply" {
	const newborn = Pet.born(0, BlockSlot.First, Region.Worker, 0, GlobalConfig.genesis(0));
	const pet: Pet = {
		...newborn.pet,
		hearts: 3,
		harvest: 1,
		burrow: foodCost(Food.Small, 1),
	};
	const legal = pet.legalEconomy(newborn.global);
	assert legal.has(EconomyAction.Rest);
	assert legal.has(EconomyAction.Bank);
	assert legal.has(EconomyAction.EatSmall);
	assert !legal.has(EconomyAction.EatMedium);
	assert !legal.has(EconomyAction.EatLarge);
	const dead: Pet = { ...pet, alive: false };
	assert dead.legalEconomy(newborn.global).isEmpty();
}

test "allocation needs a settled pet and points, and moves the work power" {
	const newborn = Pet.born(0, BlockSlot.First, Region.Worker, 0, GlobalConfig.genesis(0));
	const nodes = newborn.pet.legalNodes(newborn.global);
	assert nodes.allowsNode(3);
	assert nodes.allowsNode(4);
	assert nodes.allowsNode(ALLOCATE_HOLD);
	assert !nodes.allowsNode(5);
	assert !nodes.allowsNode(0);
	const dead: Pet = { ...newborn.pet, alive: false };
	assert dead.legalNodes(newborn.global).bits == 0;
	const grown = newborn.pet.allocateNode(3, newborn.global);
	assert grown.ok;
	if (grown.ok) {
		assert grown.value.pet.forage == 90;
		assert grown.value.pet.pointsUnspent == 0;
		assert grown.value.global.totalWorkPower == 37;
		const noPoints = grown.value.pet.allocateNode(4, grown.value.global);
		assert !noPoints.ok;
		if (!noPoints.ok) { assert noPoints.error == AllocationError.NoPoints; }
		assert grown.value.pet.legalNodes(grown.value.global).bits == nodeHoldMask().bits;
	}
	const unsettled = newborn.pet.allocateNode(3, newborn.global.settle(1));
	assert !unsettled.ok;
	if (!unsettled.ok) { assert unsettled.error == AllocationError.Unsettled; }
}

test "stakes scale with the level and the rules refuse illegal attacks" {
	const duel = duelOver(60 * HBRN_UNIT);
	const quarter = duel.attacker.stakeFor(duel.defender, StakeLevel.Quarter, DUEL_EPOCH);
	const whole = duel.attacker.stakeFor(duel.defender, StakeLevel.Whole, DUEL_EPOCH);
	assert quarter.ok && whole.ok;
	if (quarter.ok && whole.ok) {
		assert quarter.value == 10 * HBRN_UNIT;
		assert whole.value == 40 * HBRN_UNIT;
	}
	const self = duel.attacker.stakeFor(duel.attacker, StakeLevel.Quarter, DUEL_EPOCH);
	assert refusalOf(self) == AttackError.NotANeighbor;
	const stale = duel.attacker.stakeFor(duel.defender, StakeLevel.Quarter, DUEL_EPOCH + 1);
	assert refusalOf(stale) == AttackError.Unsettled;
	const poor: Pet = { ...duel.attacker, burrow: 0 };
	assert refusalOf(poor.stakeFor(duel.defender, StakeLevel.Quarter, DUEL_EPOCH)) ==
		AttackError.Broke;
	const halfFunded: Pet = { ...duel.attacker, burrow: 20 * HBRN_UNIT };
	const mask = attackHoldMask().attacksOn(halfFunded, duel.defender, DUEL_EPOCH);
	assert mask.allowsChoice(ATTACK_HOLD);
	assert mask.allowsAttack(BlockSlot.Second, StakeLevel.Quarter);
	assert mask.allowsAttack(BlockSlot.Second, StakeLevel.Half);
	assert !mask.allowsAttack(BlockSlot.Second, StakeLevel.ThreeQuarters);
	assert !mask.allowsAttack(BlockSlot.Second, StakeLevel.Whole);
	assert attackHoldMask().attacksOn(poor, duel.defender, DUEL_EPOCH).bits ==
		attackHoldMask().bits;
	assert attackHoldMask().attacksOn(duel.attacker, duel.attacker, DUEL_EPOCH).bits ==
		attackHoldMask().bits;
	const busy: Pet = { ...duel.defender, fightDay: DUEL_EPOCH, fightsInToday: 3 };
	assert refusalOf(duel.attacker.stakeFor(busy, StakeLevel.Quarter, DUEL_EPOCH)) ==
		AttackError.TargetBusy;
	const young: Pet = { ...duel.defender, bornEpoch: DUEL_EPOCH - 1 };
	assert refusalOf(duel.attacker.stakeFor(young, StakeLevel.Quarter, DUEL_EPOCH)) ==
		AttackError.TargetShielded;
	const after = duel.settledOn(StakeLevel.Quarter, 1);
	const spent = after.attacker.stakeFor(after.defender, StakeLevel.Quarter, DUEL_EPOCH);
	assert refusalOf(spent) == AttackError.OutOfAttacks;
	const mighty: Duel = { ...duel, attacker: { ...duel.attacker, might: 150 } };
	const afterMighty = mighty.settledOn(StakeLevel.Quarter, 1);
	const attacker = afterMighty.attacker;
	const again = attacker.stakeFor(afterMighty.defender, StakeLevel.Quarter, DUEL_EPOCH);
	assert refusalOf(again) == AttackError.AlreadyAttacked;
}

test "attack settlement conserves money and counts the fight" {
	const duel = duelOver(60 * HBRN_UNIT);
	let wins = 0;
	let losses = 0;
	for (let seed: uint64 = 0; seed < 60; seed++) {
		const after = duel.settledOn(StakeLevel.ThreeQuarters, seed);
		assert after.totalMoney() == duel.totalMoney();
		assert after.attacker.fightsOutToday == 1;
		assert after.defender.fightsInToday == 1;
		assert after.attacker.attackedOn(BlockSlot.Second, DUEL_EPOCH);
		if (after.record.outcome == Outcome.AttackerWins) {
			wins += 1;
			assert after.record.loot == duel.defender.harvest - after.defender.harvest;
			assert after.attacker.hearts == 5;
		} else {
			losses += 1;
			assert after.record.loot == 0;
			assert after.attacker.hearts == 4;
		}
	}
	assert wins > 0 && losses > 0;
}

test "a winning attacker bites an empty harvest" {
	const duel = duelOver(0);
	let bitten = 0;
	for (let seed: uint64 = 0; seed < 60; seed++) {
		const after = duel.settledOn(StakeLevel.Quarter, seed);
		if (after.record.outcome == Outcome.AttackerWins) {
			assert after.defender.hearts == 4;
			assert after.defender.bitesInToday == 1;
			bitten += 1;
		}
	}
	assert bitten > 0;
}
