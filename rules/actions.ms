import { BPS, HBRN_UNIT } from "./units";
import { REWARD_WEIGHT_OFFSET, Mod, Region, Stats, aged } from "./stats";
import { revived } from "./owner";
import { TREE_NODES, KEYSTONE_CANNIBAL, AllocationError, Tree, nodeCost } from "./tree";
import { BLOCK_SLOTS, BlockSlot, Pet, GlobalConfig, FightRecord, Insurance } from "./layout";
import { Food, Split, foodCost, stakeSplit } from "./emission";
import {
	Gear,
	GearSlot,
	ItemSkill,
	hasSkill,
	bare,
	minted,
	isEmpty,
	Item,
	mintPrice,
	rolledGrade,
	rolledStat,
	rolledSkill,
	sellPrice,
	weakestSlot,
	at,
	with,
	score,
	weakestItemSlot,
	none,
	wardedLoot,
	damageGuardBps,
} from "./items";
import { TalentGrade, TalentKind } from "./talent";
import { FOOD_BUYS_PER_DAY, Pantry, mealHearts } from "./pantry";
import {
	INCOMING_CAP,
	MIN_BITE_STAKE,
	CANNIBAL_WALLET_BPS,
	RAGE_STEP_BPS,
	RAGE_MAX,
	AttackError,
	Outcome,
	maxStake,
	biteHearts,
	defeatHearts,
	guardedBite,
} from "./fight";
import { DEFENSE_WIN_XP, DEFENSE_LOSS_XP, raidXp, gainXp } from "./level";
import {
	PetAndGlobal,
	genesis,
	withSpend,
	withProtocolFee,
	withWorkPower,
	withDeath,
	born,
	tickTo,
	vigor,
} from "./life";

export enum EconomyAction {
	Rest,
	Bank,
	BuySmall,
	BuyMedium,
	BuyLarge,
	EatSmall,
	EatMedium,
	EatLarge,
	Mint,
	SellItem,
	ListItem,
	BuyItem,
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
	QuotaSpent,
	NoFood,
	NoGear,
	NeedsMarket,
}

export struct NodeMask {
	bits: uint64;
	hold: boolean;
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
	return { bits: 0, hold: true };
}

export function allowsNode(this mask: NodeMask, id: int32): boolean {
	if (id == ALLOCATE_HOLD) { return mask.hold; }
	return (mask.bits & bitOf(id)) != 0;
}

export function allowingNode(this mask: NodeMask, id: int32): NodeMask {
	if (id == ALLOCATE_HOLD) { return { ...mask, hold: true }; }
	return { ...mask, bits: mask.bits | bitOf(id) };
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

export function buy(
	this pet: Pet,
	food: Food,
	global: GlobalConfig,
): Result<PetAndGlobal, EconomyError> {
	if (!pet.alive) { return Result.err(EconomyError.Dead); }
	if ((pet.foodBoughtToday as int32) >= FOOD_BUYS_PER_DAY) {
		return Result.err(EconomyError.QuotaSpent);
	}
	const cost = foodCost(food, pet.level as int32);
	if (pet.burrow < cost) { return Result.err(EconomyError.Broke); }
	return Result.ok({
		pet: {
			...pet,
			burrow: pet.burrow - cost,
			pantry: pet.pantry.adding(food, 1),
			foodBoughtToday: pet.foodBoughtToday + 1,
		},
		global: global.withSpend(Split.ofSpend(cost)),
	});
}

export function eat(
	this pet: Pet,
	food: Food,
	global: GlobalConfig,
): Result<PetAndGlobal, EconomyError> {
	if (!pet.alive) { return Result.err(EconomyError.Dead); }
	if (pet.hearts >= pet.maxHearts) { return Result.err(EconomyError.Full); }
	if (pet.pantry.portions(food) == 0) { return Result.err(EconomyError.NoFood); }
	const restored = mealHearts(food, pet.stats().foodBps);
	const hearts = Math.min((pet.hearts as int32) + restored, pet.maxHearts as int32);
	return Result.ok({
		pet: { ...pet, hearts: hearts as uint8, pantry: pet.pantry.adding(food, -1) },
		global: global,
	});
}

export function mintItem(
	this pet: Pet,
	global: GlobalConfig,
	seed: uint64,
): Result<PetAndGlobal, EconomyError> {
	if (!pet.alive) { return Result.err(EconomyError.Dead); }
	const level = pet.level as int32;
	const price = mintPrice(level);
	if (pet.burrow < price) { return Result.err(EconomyError.Broke); }
	const slot = pet.gear.weakestSlot();
	const worn = pet.gear.at(slot);
	const grade = rolledGrade(seed);
	const fresh = Item.minted(grade, rolledStat(seed), rolledSkill(seed, grade));
	const upgrade = fresh.score() > worn.score();
	const sold = upgrade ? worn : fresh;
	const spent = price - sold.sellPrice(level);
	const geared: Pet = {
		...pet,
		burrow: pet.burrow - spent,
		gear: upgrade ? pet.gear.with(slot, fresh) : pet.gear,
	};
	return Result.ok({
		pet: geared,
		global: global
			.withSpend(Split.ofSpend(spent))
			.withWorkPower(pet.stats().rewardWeight(), geared.stats().rewardWeight()),
	});
}

export function soldItem(this pet: Pet, global: GlobalConfig): Result<PetAndGlobal, EconomyError> {
	if (!pet.alive) { return Result.err(EconomyError.Dead); }
	const found = pet.gear.weakestItemSlot();
	if (!found.ok) { return Result.err(EconomyError.NoGear); }
	const slot = found.value;
	const price = pet.gear.at(slot).sellPrice(pet.level as int32);
	const bare: Pet = {
		...pet,
		burrow: pet.burrow + price,
		gear: pet.gear.with(slot, Item.none()),
	};
	return Result.ok({
		pet: bare,
		global: global.withWorkPower(pet.stats().rewardWeight(), bare.stats().rewardWeight()),
	});
}

export function doEconomy(
	this pet: Pet,
	action: EconomyAction,
	global: GlobalConfig,
	seed: uint64,
): Result<PetAndGlobal, EconomyError> {
	if (!pet.alive) { return Result.err(EconomyError.Dead); }
	return match (action) {
		EconomyAction.Rest => Result.ok({ pet: pet, global: global }),
		EconomyAction.Bank => pet.bank(global),
		EconomyAction.BuySmall => pet.buy(Food.Small, global),
		EconomyAction.BuyMedium => pet.buy(Food.Medium, global),
		EconomyAction.BuyLarge => pet.buy(Food.Large, global),
		EconomyAction.EatSmall => pet.eat(Food.Small, global),
		EconomyAction.EatMedium => pet.eat(Food.Medium, global),
		EconomyAction.EatLarge => pet.eat(Food.Large, global),
		EconomyAction.Mint => pet.mintItem(global, seed),
		EconomyAction.SellItem => pet.soldItem(global),
		EconomyAction.ListItem => Result.err(EconomyError.NeedsMarket),
		EconomyAction.BuyItem => Result.err(EconomyError.NeedsMarket),
	};
}

export function legalEconomy(this pet: Pet, global: GlobalConfig): BitSet<EconomyAction> {
	let legal = 0 as BitSet<EconomyAction>;
	for (let ordinal = 0; ordinal <= (EconomyAction.BuyItem as int32); ordinal++) {
		const action = ordinal as EconomyAction;
		if (pet.doEconomy(action, global, 0).ok) { legal = legal.incl(action); }
	}
	return legal;
}

export function grownTree(
	this pet: Pet,
	id: int32,
	global: GlobalConfig,
): Result<Tree, AllocationError> {
	if (!pet.alive) { return Result.err(AllocationError.Dead); }
	const settled = pet.lastTickEpoch == global.rewardEpoch &&
		pet.rewardSnapshot == global.rewardPerWorkPower;
	if (!settled) { return Result.err(AllocationError.Unsettled); }
	if ((pet.pointsUnspent as int32) < nodeCost(id)) { return Result.err(AllocationError.NoPoints); }
	return pet.tree.allocate(id, pet.startRegion());
}

export function allocateNode(
	this pet: Pet,
	id: int32,
	global: GlobalConfig,
): Result<PetAndGlobal, AllocationError> {
	const tree = try pet.grownTree(id, global);
	const cost = nodeCost(id);
	const derived = Stats.built(tree, pet.level as int32, pet.talent()).aged(pet.vigor());
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
		global: global.withWorkPower(pet.stats().rewardWeight(), grown.stats().rewardWeight()),
	});
}

export function legalNodes(this pet: Pet, global: GlobalConfig): NodeMask {
	if (!pet.alive) { return { bits: 0, hold: false }; }
	let mask = nodeHoldMask();
	for (let id = 0; id < TREE_NODES; id++) {
		if (pet.grownTree(id, global).ok) { mask = mask.allowingNode(id); }
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
	const attackerCombatant = attackerToday.combatantFacing(defenderToday);
	const defenderCombatant = defenderToday.combatantFacing(attackerToday);
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
		const baseLoot = defenderCombatant.lootFor(
			attackerCombatant,
			stake,
			harvestBefore,
			defenderToday.fightsInToday as int32,
		);
		const lootBps = (BPS + attackerToday.stats().lootBps) as uint64;
		const boosted = Math.min(baseLoot * lootBps / (BPS as uint64), harvestBefore);
		const loot = defenderToday.gear.wardedLoot(boosted);
		const [winnings, fee] = stakeSplit(loot);
		const bites = guardedBite(
			biteHearts(
				stake,
				loot,
				attackerToday.stats().power(),
				defenderToday.stats().power(),
				defenderToday.maxHearts as int32,
				defenderToday.bitesInToday as int32,
			),
			defenderToday.stats().biteGuardBps + defenderToday.gear.damageGuardBps(),
		);
		const hearts = Math.max((struck.hearts as int32) - bites, 0);
		const struckDown: Pet = {
			...struck,
			alive: hearts > 0,
			hearts: hearts as uint8,
			harvest: struck.harvest - loot,
			bitesInToday: ((struck.bitesInToday as int32) + (bites > 0 ? 1 : 0)) as uint8,
		};
		const hurt = loot > 0 || bites > 0;
		const robbed = hurt ? struckDown.robbedBy(attackerToday, epoch) : struckDown;
		const [survivor, insuredGlobal] = robbed.revived(global);
		const cannibal = attackerToday.stats().mods.has(Mod.Cannibal);
		const [remains, devoured] = survivor.devouredBy(cannibal);
		const paidOut: Pet = {
			...committed,
			burrow: committed.burrow + stake + winnings + devoured,
		};
		const raider = paidOut.calmedAgainst(defenderToday);
		const paid = insuredGlobal.withProtocolFee(fee);
		return Result.ok({
			attacker: raider.gainXp(raidXp(loot)),
			defender: remains.gainXp(DEFENSE_LOSS_XP),
			global: remains.alive ? paid : paid.withDeath(remains.stats().rewardWeight()),
			record: { ...record, loot: loot },
		});
	}
	const [keptStake, fee] = stakeSplit(stake);
	const defeat = defeatHearts(committed.maxHearts as int32);
	const lost = guardedBite(defeat, committed.gear.damageGuardBps());
	const hearts = Math.max((committed.hearts as int32) - lost, 0);
	const fallen: Pet = { ...committed, alive: hearts > 0, hearts: hearts as uint8 };
	const [beaten, insuredGlobal] = fallen.revived(global);
	const kept: Pet = { ...struck, burrow: struck.burrow + keptStake };
	const holder = kept.calmedAgainst(attackerToday);
	const paid = insuredGlobal.withProtocolFee(fee);
	return Result.ok({
		attacker: beaten,
		defender: holder.gainXp(DEFENSE_WIN_XP),
		global: beaten.alive ? paid : paid.withDeath(beaten.stats().rewardWeight()),
		record: record,
	});
}

function devouredBy(this victim: Pet, cannibal: boolean): [Pet, uint64] {
	if (!cannibal || victim.alive) { return [victim, 0]; }
	const wallet = victim.harvest + victim.burrow;
	const share = wallet * (CANNIBAL_WALLET_BPS as uint64) / (BPS as uint64);
	const fromHarvest = Math.min(share, victim.harvest);
	const remains: Pet = {
		...victim,
		harvest: victim.harvest - fromHarvest,
		burrow: victim.burrow - (share - fromHarvest),
	};
	return [remains, share];
}

const DUEL_EPOCH: uint64 = 4;

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
		attacker: { ...attacker.pet, hearts: 5, might: 80, burrow: 1000 * HBRN_UNIT },
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
	const noNodes: NodeMask = { bits: 0, hold: false };
	const nodes = noNodes.allowingNode(TREE_NODES - 1);
	assert nodes.allowsNode(TREE_NODES - 1);
	assert !nodes.allowsNode(0);
	assert !nodes.allowsNode(ALLOCATE_HOLD);
	assert nodeHoldMask().allowsNode(ALLOCATE_HOLD);
}

test "bank moves harvest, buying needs money and quota, eating needs room and food" {
	const newborn = Pet.born(0, BlockSlot.First, Region.Worker, 0, GlobalConfig.genesis(0));
	const earner: Pet = { ...newborn.pet, harvest: 500 };
	const banked = earner.bank(newborn.global);
	assert banked.ok;
	if (banked.ok) { assert banked.value.pet.harvest == 0 && banked.value.pet.burrow == 500; }
	assert !newborn.pet.bank(newborn.global).ok;
	const full = newborn.pet.eat(Food.Small, newborn.global);
	assert !full.ok;
	if (!full.ok) { assert full.error == EconomyError.Full; }
	const hurt: Pet = { ...newborn.pet, hearts: 2, pantry: Pantry.unstocked() };
	const hungry = hurt.eat(Food.Small, newborn.global);
	assert !hungry.ok;
	if (!hungry.ok) { assert hungry.error == EconomyError.NoFood; }
	const broke = hurt.buy(Food.Small, newborn.global);
	assert !broke.ok;
	if (!broke.ok) { assert broke.error == EconomyError.Broke; }
	const cost = foodCost(Food.Medium, 1);
	const hurtWithMoney: Pet = { ...hurt, burrow: cost * 10 };
	const bought = hurtWithMoney.buy(Food.Medium, newborn.global);
	assert bought.ok;
	if (!bought.ok) { return; }
	const spend = bought.value.global;
	assert bought.value.pet.burrow == cost * 9;
	assert bought.value.pet.pantry.portions(Food.Medium) == 1;
	assert spend.recycledPending + spend.burned + spend.protocolPending == cost;
	const fed = bought.value.pet.eat(Food.Medium, newborn.global);
	assert fed.ok;
	if (fed.ok) {
		assert fed.value.pet.hearts == 8;
		assert fed.value.pet.pantry.stored() == 0;
	}
	const spent: Pet = { ...hurtWithMoney, foodBoughtToday: FOOD_BUYS_PER_DAY as uint8 };
	const refused = spent.buy(Food.Small, newborn.global);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == EconomyError.QuotaSpent; }
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
	assert legal.has(EconomyAction.BuySmall);
	assert !legal.has(EconomyAction.BuyMedium);
	assert legal.has(EconomyAction.EatSmall);
	assert !legal.has(EconomyAction.EatMedium);
	assert !legal.has(EconomyAction.EatLarge);
	const dead: Pet = { ...pet, alive: false };
	assert dead.legalEconomy(newborn.global).isEmpty();
}

test "allocation needs a settled pet and points, and moves the work power" {
	const newborn = Pet.born(0, BlockSlot.First, Region.Worker, 0, GlobalConfig.genesis(0));
	const nodes = newborn.pet.legalNodes(newborn.global);
	assert !nodes.allowsNode(3);
	assert nodes.allowsNode(4);
	assert nodes.allowsNode(ALLOCATE_HOLD);
	assert !nodes.allowsNode(5);
	assert !nodes.allowsNode(0);
	const dead: Pet = { ...newborn.pet, alive: false };
	const deadMask = dead.legalNodes(newborn.global);
	assert deadMask.bits == 0 && !deadMask.hold;
	const grown = newborn.pet.allocateNode(4, newborn.global);
	assert grown.ok;
	if (grown.ok) {
		assert grown.value.pet.forage == 88;
		assert grown.value.pet.pointsUnspent == 0;
		const shifted = 36 + REWARD_WEIGHT_OFFSET;
		assert grown.value.global.totalWorkPower == shifted * shifted;
		const noPoints = grown.value.pet.allocateNode(5, grown.value.global);
		assert !noPoints.ok;
		if (!noPoints.ok) { assert noPoints.error == AllocationError.NoPoints; }
		assert grown.value.pet.legalNodes(grown.value.global) == nodeHoldMask();
	}
	const unsettled = newborn.pet.allocateNode(4, newborn.global.settle(1));
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
			assert (after.attacker.hearts as int32) == 5 - defeatHearts(duel.attacker.maxHearts as int32);
		}
	}
	assert wins > 0 && losses > 0;
}

test "a winning attacker that takes back its stake leaves the hearts alone" {
	const duel = duelOver(400 * HBRN_UNIT);
	let won = 0;
	for (let seed: uint64 = 0; seed < 60; seed++) {
		const after = duel.settledOn(StakeLevel.Quarter, seed);
		if (after.record.outcome == Outcome.AttackerWins && after.record.loot >= after.record.stake) {
			assert after.defender.hearts == 5;
			assert after.defender.bitesInToday == 0;
			won += 1;
		}
	}
	assert won > 0;
}

test "a winning attacker bites an empty harvest" {
	const duel = duelOver(0);
	let bitten = 0;
	for (let seed: uint64 = 0; seed < 60; seed++) {
		const after = duel.settledOn(StakeLevel.Quarter, seed);
		if (after.record.outcome == Outcome.AttackerWins) {
			const bite = biteHearts(
				after.record.stake,
				after.record.loot,
				duel.attacker.stats().power(),
				duel.defender.stats().power(),
				duel.defender.maxHearts as int32,
				0,
			);
			assert bite > 0;
			assert (after.defender.hearts as int32) == 5 - bite;
			assert after.defender.bitesInToday == 1;
			bitten += 1;
		}
	}
	assert bitten > 0;
}

test "a cannibal whose bite kills takes half of what the victim left" {
	const duel = duelOver(0);
	const cannibalTree = (1 as uint64) << (KEYSTONE_CANNIBAL as uint64);
	const cannibal: Pet = { ...duel.attacker, tree: { bits: cannibalTree } };
	const frail: Pet = { ...duel.defender, hearts: 1 };
	let kills = 0;
	for (let seed: uint64 = 0; seed < 60; seed++) {
		const result = cannibal.settleAttack(
			frail,
			StakeLevel.Quarter,
			duel.global,
			DUEL_EPOCH,
			seed,
		);
		if (!result.ok) { unreachable; }
		const after = result.value;
		if (after.record.outcome != Outcome.AttackerWins) { continue; }
		assert !after.defender.alive;
		assert after.defender.burrow == frail.burrow / 2;
		assert after.attacker.burrow == cannibal.burrow + frail.burrow / 2;
		kills += 1;
	}
	assert kills > 0;
	for (let seed: uint64 = 0; seed < 60; seed++) {
		const plain = duel.attacker.settleAttack(
			frail,
			StakeLevel.Quarter,
			duel.global,
			DUEL_EPOCH,
			seed,
		);
		if (!plain.ok) { unreachable; }
		if (plain.value.record.outcome != Outcome.AttackerWins) { continue; }
		assert plain.value.defender.burrow == frail.burrow;
	}
}

test "an insured pet bitten to death comes back once, and no cannibal eats it" {
	const duel = duelOver(0);
	const cannibalTree = (1 as uint64) << (KEYSTONE_CANNIBAL as uint64);
	const cannibal: Pet = { ...duel.attacker, tree: { bits: cannibalTree } };
	const frail: Pet = { ...duel.defender, hearts: 1, insurance: Insurance.Armed as uint8 };
	let saves = 0;
	for (let seed: uint64 = 0; seed < 60; seed++) {
		const result = cannibal.settleAttack(
			frail,
			StakeLevel.Quarter,
			duel.global,
			DUEL_EPOCH,
			seed,
		);
		if (!result.ok) { unreachable; }
		const after = result.value;
		if (after.record.outcome != Outcome.AttackerWins) { continue; }
		assert after.defender.alive;
		assert after.defender.insurance == (Insurance.Used as uint8);
		assert after.defender.scars == 1;
		assert after.defender.burrow == frail.burrow / 2;
		assert after.attacker.burrow == cannibal.burrow;
		assert after.global.burned == duel.global.burned + frail.burrow / 2;
		saves += 1;
	}
	assert saves > 0;
}

test "a revive charm spares a bitten pet without a burn, and a ward cuts the loot" {
	const duel = duelOver(0);
	const charm = Item.minted(TalentGrade.Epic, TalentKind.Grit, ItemSkill.Revive);
	const charmed: Pet = {
		...duel.defender,
		hearts: 1,
		gear: Gear.bare().with(GearSlot.Body, charm),
	};
	let saves = 0;
	for (let seed: uint64 = 0; seed < 60; seed++) {
		const result = duel.attacker.settleAttack(
			charmed,
			StakeLevel.Quarter,
			duel.global,
			DUEL_EPOCH,
			seed,
		);
		if (!result.ok) { unreachable; }
		const after = result.value;
		if (after.record.outcome != Outcome.AttackerWins) { continue; }
		assert after.defender.alive;
		assert after.defender.burrow == charmed.burrow;
		assert !after.defender.gear.hasSkill(ItemSkill.Revive);
		saves += 1;
	}
	assert saves > 0;
	const rich = duelOver(900 * HBRN_UNIT);
	const ward = Item.minted(TalentGrade.Mythic, TalentKind.Grit, ItemSkill.AntiRobbery);
	const warded: Pet = {
		...rich.defender,
		gear: Gear.bare().with(GearSlot.Feet, ward),
	};
	let compared = 0;
	for (let seed: uint64 = 0; seed < 60; seed++) {
		const plain = rich.attacker.settleAttack(
			rich.defender,
			StakeLevel.Whole,
			rich.global,
			DUEL_EPOCH,
			seed,
		);
		const guarded = rich.attacker.settleAttack(
			warded,
			StakeLevel.Whole,
			rich.global,
			DUEL_EPOCH,
			seed,
		);
		if (!plain.ok || !guarded.ok) { unreachable; }
		if (plain.value.record.outcome != Outcome.AttackerWins) { continue; }
		if (guarded.value.record.outcome != Outcome.AttackerWins) { continue; }
		assert guarded.value.record.loot < plain.value.record.loot;
		compared += 1;
	}
	assert compared > 0;
}

test "rage builds against a repeat robber, strengthens only that fight and ends with a win" {
	const duel = duelOver(0);
	const robber = duel.attacker;
	const other: Pet = { ...duel.attacker, slot: 7 };
	const victim = duel.defender.robbedBy(robber, 10);
	assert victim.rage == 1 && victim.grudgeSlot == robber.slot;
	const angrier = victim.robbedBy(robber, 11).robbedBy(robber, 12).robbedBy(robber, 13);
	assert (angrier.rage as int32) == RAGE_MAX;
	assert angrier.rageAt(15) == angrier.rage;
	assert angrier.rageAt(16) == 0;
	assert angrier.robbedBy(other, 13).rage == 1;
	const calm = duel.defender.combatant();
	const raged = angrier.combatantFacing(robber);
	assert raged.might == calm.might * (BPS + RAGE_MAX * RAGE_STEP_BPS) / BPS;
	assert angrier.combatantFacing(other).might == calm.might;
	assert angrier.calmedAgainst(robber).rage == 0;
	assert angrier.calmedAgainst(other).rage == angrier.rage;
}

test "a pet sells its weakest item for cash and cannot sell bare" {
	const duel = duelOver(0);
	const epic = Item.minted(TalentGrade.Epic, TalentKind.Grit, ItemSkill.None);
	const common = Item.minted(TalentGrade.Common, TalentKind.Might, ItemSkill.None);
	const geared: Pet = {
		...duel.defender,
		gear: Gear.bare().with(GearSlot.Head, epic).with(GearSlot.Feet, common),
	};
	const sold = geared.soldItem(duel.global);
	assert sold.ok;
	if (!sold.ok) { return; }
	assert sold.value.pet.gear.feet.isEmpty();
	assert !sold.value.pet.gear.head.isEmpty();
	assert sold.value.pet.burrow == geared.burrow + common.sellPrice(geared.level as int32);
	const bare = duel.defender.soldItem(duel.global);
	assert !bare.ok;
	if (!bare.ok) { assert bare.error == EconomyError.NoGear; }
}
