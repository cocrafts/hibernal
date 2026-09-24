import {
	BLOCK_SLOTS,
	GRACE_EPOCHS,
	ALLOCATE_HOLD,
	ATTACK_HOLD,
	STAKE_LEVELS,
	BlockSlot,
	Region,
	Pet,
	GlobalConfig,
	EconomyAction,
	StakeLevel,
	NodeMask,
	AttackMask,
	Dice,
	mixSeeds,
	fightSeed,
	attackHoldMask,
	attackChoice,
	HBRN_UNIT,
	LIFESPAN_EPOCHS,
	INHERITANCE_TAX_PERCENT,
	agedOut,
	heirOf,
} from "../rules/index";
// C emits PantryEq for `Pet ==` only where Pantry is imported (msc v0.2.55); remove with
// ~/metascript/.inbox/compiler/2026-09-22-struct-equality-on-js.md, second sighting.
import { Pantry } from "../rules/pantry";
import { OwnerKind, OwnerLedger, habitOf, ownerKindFor, visitDraw, visits, visited } from "./owner";

export const WORLD_BLOCKS: int32 = 20;
export const ACTS_PER_EPOCH: int32 = 4;
export const EPISODE_EPOCHS: int32 = 120;
export const INITIAL_CLAIM_DAYS: int32 = 30;
export const GRUDGE_EPOCHS: uint64 = 3;
export const PERSONA_BUILD: int32 = -2;
export const NO_KEYSTONE: int32 = -1;

export struct Grudge {
	robber: BlockSlot;
	epoch: uint64;
}

export enum GrudgeError {
	None,
	Stale,
}

export function none(this typeof Grudge): Grudge {
	return { robber: BlockSlot.First, epoch: 0 };
}

export struct ActionSet {
	economy: EconomyAction;
	node: int32;
	attack: int32;
}

export function hold(this typeof ActionSet): ActionSet {
	return { economy: EconomyAction.Rest, node: ALLOCATE_HOLD, attack: ATTACK_HOLD };
}

export struct Masks {
	economy: BitSet<EconomyAction>;
	nodes: NodeMask;
	attacks: AttackMask;
}

export struct WorldStats {
	fights: int32;
	wins: int32;
	deaths: int32;
	heirs: int32;
	illegal: int32;
}

export struct World {
	pets: Pet[];
	claimEpochs: uint64[];
	deathEpochs: uint64[];
	levelTenEpochs: uint64[];
	levelTwentyEpochs: uint64[];
	grudges: Grudge[];
	buildTargets: int32[];
	owners: OwnerKind[];
	ownerLedgers: OwnerLedger[];
	global: GlobalConfig;
	epoch: uint64;
	round: int32;
	turns: int32[];
	seed: uint64;
	stats: WorldStats;
}

export function create(this typeof World, blocks: int32, seed: uint64): World {
	let global = GlobalConfig.genesis(0);
	const pets: Pet[] = [];
	const claimEpochs: uint64[] = [];
	const deathEpochs: uint64[] = [];
	const levelTenEpochs: uint64[] = [];
	const levelTwentyEpochs: uint64[] = [];
	const grudges: Grudge[] = [];
	const buildTargets: int32[] = [];
	const owners: OwnerKind[] = [];
	const ownerLedgers: OwnerLedger[] = [];
	const turns: int32[] = [];
	for (let index = 0; index < blocks * BLOCK_SLOTS; index++) {
		const slot = index % BLOCK_SLOTS;
		turns.push(index);
		owners.push(ownerKindFor(seed, index));
		ownerLedgers.push({ visits: 0, skr: 0, refusals: 0 });
		grudges.push(Grudge.none());
		buildTargets.push(PERSONA_BUILD);
		const hatched = Pet.born(
			(index / BLOCK_SLOTS) as uint32,
			slot as BlockSlot,
			(slot % 3) as Region,
			0,
			global,
		);
		pets.push(hatched.pet);
		claimEpochs.push(0);
		deathEpochs.push(0);
		levelTenEpochs.push(0);
		levelTwentyEpochs.push(0);
		global = hatched.global;
	}
	return {
		pets: pets,
		claimEpochs: claimEpochs,
		deathEpochs: deathEpochs,
		levelTenEpochs: levelTenEpochs,
		levelTwentyEpochs: levelTwentyEpochs,
		grudges: grudges,
		buildTargets: buildTargets,
		owners: owners,
		ownerLedgers: ownerLedgers,
		global: global,
		epoch: 0,
		round: 0,
		turns: turns,
		seed: seed,
		stats: { fights: 0, wins: 0, deaths: 0, heirs: 0, illegal: 0 },
	};
}

export function staggered(this typeof World, blocks: int32, seed: uint64): World {
	const world = World.create(blocks, seed);
	const pets = world.pets;
	const claimEpochs = world.claimEpochs;
	const total = blocks * BLOCK_SLOTS;
	for (let index = 0; index < total; index++) {
		const block = index / BLOCK_SLOTS;
		const slot = index % BLOCK_SLOTS;
		const ordinal = slot * blocks + block;
		const claimEpoch = (1 + ordinal * INITIAL_CLAIM_DAYS / total) as uint64;
		pets[index] = {
			...pets[index],
			alive: false,
			bornEpoch: claimEpoch,
			lastTickEpoch: claimEpoch,
		};
		claimEpochs[index] = claimEpoch;
	}
	return { ...world, global: GlobalConfig.genesis(0) };
}

export function blockStart(index: int32): int32 {
	return index - (index % BLOCK_SLOTS);
}

export function livingMates(this world: World, index: int32): int32 {
	const base = blockStart(index);
	let living = 0;
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		if (base + slot != index && world.pets[base + slot].alive) { living += 1; }
	}
	return living;
}

export function robberOf(this world: World, index: int32): Result<BlockSlot, GrudgeError> {
	const grudge = world.grudges[index];
	if (grudge.epoch == 0) { return Result.err(GrudgeError.None); }
	if (world.epoch > grudge.epoch + GRUDGE_EPOCHS) { return Result.err(GrudgeError.Stale); }
	return Result.ok(grudge.robber);
}

export function beginEpoch(this world: World, epoch: uint64): World {
	const pets = world.pets;
	const claimEpochs = world.claimEpochs;
	const grudges = world.grudges;
	const deathEpochs = world.deathEpochs;
	const levelTenEpochs = world.levelTenEpochs;
	const levelTwentyEpochs = world.levelTwentyEpochs;
	let global = world.global;
	let heirs = world.stats.heirs;
	for (let index = 0; index < world.pets.length; index++) {
		let pet = pets[index];
		const claimEpoch = claimEpochs[index];
		if (claimEpoch != 0) {
			if (epoch < claimEpoch) { continue; }
			const claimed = Pet.born(
				pet.blockId,
				pet.blockSlot(),
				pet.startRegion(),
				claimEpoch,
				global,
			);
			pet = claimed.pet;
			pets[index] = pet;
			claimEpochs[index] = 0;
			global = claimed.global;
		}
		if (!pet.alive) {
			const diedAt = deathEpochs[index];
			if (diedAt == 0 || epoch < diedAt + GRACE_EPOCHS) { continue; }
			const heir = pet.heirOf(epoch, global);
			if (!heir.ok) { unreachable; }
			levelTenEpochs[index] = 0;
			levelTwentyEpochs[index] = 0;
			grudges[index] = Grudge.none();
			pets[index] = heir.value.pet;
			deathEpochs[index] = 0;
			global = heir.value.global;
			heirs += 1;
			continue;
		}
		const ticked = pet.tickTo(global, epoch);
		if (!ticked.ok) { continue; }
		pets[index] = ticked.value.pet;
		global = ticked.value.global;
		const randomness = mixSeeds(mixSeeds(world.seed, index as uint64), epoch);
		const revealed = pets[index].revealTalent(global, randomness);
		if (revealed.ok) {
			pets[index] = revealed.value.pet;
			global = revealed.value.global;
		}
	}
	const begun: World = {
		...world,
		global: global,
		epoch: epoch,
		stats: { ...world.stats, heirs: heirs },
	};
	return begun.ownersVisited().inRound(0);
}

export function ownersVisited(this world: World): World {
	const pets = world.pets;
	const ledgers = world.ownerLedgers;
	for (let index = 0; index < pets.length; index++) {
		if (!pets[index].alive) { continue; }
		const habit = habitOf(world.owners[index]);
		const draw = visitDraw(world.seed, index, world.epoch);
		if (!habit.visits(draw)) { continue; }
		const visit = pets[index].visited(habit, draw, world.epoch);
		pets[index] = visit.pet;
		const ledger = ledgers[index];
		ledgers[index] = {
			visits: ledger.visits + 1,
			skr: ledger.skr + visit.skr,
			refusals: ledger.refusals + (visit.refused ? 1 : 0),
		};
	}
	return world;
}

export function inRound(this world: World, round: int32): World {
	const turns = world.turns;
	for (let base = 0; base < turns.length; base += BLOCK_SLOTS) {
		const block = (base / BLOCK_SLOTS) as uint64;
		const dice: Dice = {
			seed: mixSeeds(mixSeeds(world.seed, world.epoch), (block << 8) | (round as uint64)),
			draw: 0,
		};
		for (let slot = 0; slot < BLOCK_SLOTS; slot++) { turns[base + slot] = base + slot; }
		for (let last = BLOCK_SLOTS - 1; last > 0; last--) {
			const picked = base + dice.roll(last, 0, last);
			const waiting = turns[base + last];
			turns[base + last] = turns[picked];
			turns[picked] = waiting;
		}
	}
	return { ...world, round: round };
}

export function actorAt(this world: World, turn: int32): int32 {
	return world.turns[turn];
}

export function endEpoch(this world: World): World {
	const pets = world.pets;
	const claimEpochs = world.claimEpochs;
	const deathEpochs = world.deathEpochs;
	const levelTenEpochs = world.levelTenEpochs;
	const levelTwentyEpochs = world.levelTwentyEpochs;
	let global = world.global;
	let deaths = world.stats.deaths;
	for (let index = 0; index < world.pets.length; index++) {
		const pet = pets[index];
		if (claimEpochs[index] != 0) { continue; }
		if (pet.alive && pet.level >= 10 && levelTenEpochs[index] == 0) {
			levelTenEpochs[index] = world.epoch;
		}
		if (pet.alive && pet.level >= 20 && levelTwentyEpochs[index] == 0) {
			levelTwentyEpochs[index] = world.epoch;
		}
		if (pet.alive || deathEpochs[index] != 0) { continue; }
		const burial = pet.bury(world.livingMates(index), global);
		if (!burial.ok) { continue; }
		pets[index] = burial.value.pet;
		deathEpochs[index] = world.epoch;
		global = burial.value.global;
		deaths += 1;
		if (burial.value.perMate == 0) { continue; }
		const base = blockStart(index);
		for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
			const mate = pets[base + slot];
			if (base + slot == index || !mate.alive) { continue; }
			pets[base + slot] = { ...mate, harvest: mate.harvest + burial.value.perMate };
		}
	}
	return { ...world, global: global, stats: { ...world.stats, deaths: deaths } };
}

export function attackMaskFor(this world: World, index: int32): AttackMask {
	const pet = world.pets[index];
	if (!pet.alive) { return { bits: 0 }; }
	const base = blockStart(index);
	let attacks = attackHoldMask();
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		if (base + slot == index) { continue; }
		attacks = attacks.attacksOn(pet, world.pets[base + slot], world.epoch);
	}
	return attacks;
}

export function masksFor(this world: World, index: int32): Masks {
	const pet = world.pets[index];
	return {
		economy: pet.legalEconomy(world.global),
		nodes: pet.legalNodes(world.global),
		attacks: world.attackMaskFor(index),
	};
}

function counted(this world: World, illegal: boolean): World {
	if (!illegal) { return world; }
	return { ...world, stats: { ...world.stats, illegal: world.stats.illegal + 1 } };
}

export function applyEconomy(this world: World, index: int32, action: EconomyAction): World {
	const pets = world.pets;
	const pet = pets[index];
	if (!pet.alive) { return world; }
	const economy = pet.doEconomy(action, world.global);
	if (!economy.ok) { return world.counted(true); }
	pets[index] = economy.value.pet;
	return { ...world, global: economy.value.global };
}

export function applyNode(this world: World, index: int32, node: int32): World {
	const pets = world.pets;
	const pet = pets[index];
	if (!pet.alive || node == ALLOCATE_HOLD) { return world; }
	const grown = pet.allocateNode(node, world.global);
	if (!grown.ok) { return world.counted(true); }
	pets[index] = grown.value.pet;
	return { ...world, global: grown.value.global };
}

export function applyAttack(this world: World, index: int32, choice: int32): World {
	const pets = world.pets;
	const pet = pets[index];
	if (!pet.alive || choice == ATTACK_HOLD) { return world; }
	const slot = choice / STAKE_LEVELS;
	const level = (choice % STAKE_LEVELS) as StakeLevel;
	const target = blockStart(index) + slot;
	if (slot < 0 || slot >= BLOCK_SLOTS || target == index) { return world.counted(true); }
	const entropy = mixSeeds(world.seed, pet.blockId as uint64);
	const seed = fightSeed(entropy, pet.slot as int32, slot, world.epoch, world.round);
	const settled = pet.settleAttack(pets[target], level, world.global, world.epoch, seed);
	if (!settled.ok) { return world.counted(true); }
	pets[index] = settled.value.attacker;
	pets[target] = settled.value.defender;
	const won = settled.value.record.loot > 0 ? 1 : 0;
	const grudges = world.grudges;
	const robber = world.robberOf(index);
	if (robber.ok && robber.value == slot as BlockSlot) { grudges[index] = Grudge.none(); }
	if (won == 1) { grudges[target] = { robber: pet.blockSlot(), epoch: world.epoch }; }
	return {
		...world,
		global: settled.value.global,
		stats: { ...world.stats, fights: world.stats.fights + 1, wins: world.stats.wins + won },
	};
}

export function apply(this world: World, index: int32, actions: ActionSet): World {
	return world
		.applyEconomy(index, actions.economy)
		.applyNode(index, actions.node)
		.applyAttack(index, actions.attack);
}

export function sortedWealth(this world: World): uint64[] {
	const wealth: uint64[] = [];
	for (let index = 0; index < world.pets.length; index++) {
		const pet = world.pets[index];
		if (!pet.alive) { continue; }
		const value = pet.harvest + pet.burrow;
		let position = wealth.length;
		wealth.push(value);
		while (position > 0 && wealth[position - 1] > value) {
			wealth[position] = wealth[position - 1];
			position -= 1;
		}
		wealth[position] = value;
	}
	return wealth;
}

export function percentile(sorted: uint64[], percent: int32): uint64 {
	if (sorted.length == 0) { return 0; }
	const index = Math.min(sorted.length - 1, (sorted.length * percent) / 100);
	return sorted[index];
}

export function medianLevel(this world: World): int32 {
	const levels: int32[] = [];
	for (let index = 0; index < world.pets.length; index++) {
		const pet = world.pets[index];
		if (!pet.alive) { continue; }
		const level = pet.level as int32;
		let position = levels.length;
		levels.push(level);
		while (position > 0 && levels[position - 1] > level) {
			levels[position] = levels[position - 1];
			position -= 1;
		}
		levels[position] = level;
	}
	return levels.length == 0 ? 0 : levels[levels.length / 2];
}

export function medianEpoch(epochs: uint64[]): uint64 {
	const reached: uint64[] = [];
	for (let index = 0; index < epochs.length; index++) {
		const value = epochs[index];
		if (value == 0) { continue; }
		let position = reached.length;
		reached.push(value);
		while (position > 0 && reached[position - 1] > value) {
			reached[position] = reached[position - 1];
			position -= 1;
		}
		reached[position] = value;
	}
	return reached.length == 0 ? 0 : reached[reached.length / 2];
}

export function living(this world: World): int32 {
	let count = 0;
	for (let index = 0; index < world.pets.length; index++) {
		if (world.pets[index].alive) { count += 1; }
	}
	return count;
}

test "a world starts full, alive and settled" {
	const world = World.create(2, 1);
	assert world.pets.length == 20;
	assert world.living() == 20;
	let weight: uint64 = 0;
	for (let index = 0; index < world.pets.length; index++) {
		weight += world.pets[index].stats().rewardWeight();
	}
	assert world.global.totalWorkPower == weight;
	assert world.pets[13].blockId == 1;
	assert world.pets[13].slot == 3;
	assert world.pets[13].startRegion() == Region.Worker;
}

test "every round draws a turn order per block in which each pet acts once" {
	const start = World.create(2, 9);
	const firsts: int32[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
	const everyone = ((1 as uint64) << (BLOCK_SLOTS as uint64)) - 1;
	for (let day = 1; day <= 40; day++) {
		const dawn: World = { ...start, epoch: day as uint64 };
		for (let round = 0; round < ACTS_PER_EPOCH; round++) {
			const world = dawn.inRound(round);
			for (let base = 0; base < world.pets.length; base += BLOCK_SLOTS) {
				let seen: uint64 = 0;
				for (let turn = base; turn < base + BLOCK_SLOTS; turn++) {
					const actor = world.actorAt(turn);
					assert actor / BLOCK_SLOTS == base / BLOCK_SLOTS;
					seen = seen | ((1 as uint64) << ((actor - base) as uint64));
				}
				assert seen == everyone;
			}
			firsts[world.actorAt(0)] += 1;
		}
	}
	for (const count of firsts) { assert count > 0; }
	const again: World = { ...start, epoch: 7 };
	assert again.inRound(2).actorAt(13) == again.inRound(2).actorAt(13);
}

test "a staggered world claims every slot across the first thirty days" {
	let world = World.staggered(WORLD_BLOCKS, 1);
	assert world.living() == 0;
	for (let day = 1; day <= INITIAL_CLAIM_DAYS; day++) {
		world = world.beginEpoch(day as uint64);
		let claimedToday = 0;
		for (let index = 0; index < world.pets.length; index++) {
			const pet = world.pets[index];
			if (pet.alive && pet.lineageGeneration == 0 && pet.bornEpoch == (day as uint64)) {
				claimedToday += 1;
			}
		}
		assert claimedToday >= 6 && claimedToday <= 7;
	}
	for (const claimEpoch of world.claimEpochs) { assert claimEpoch == 0; }
}

test "hold applies nothing and stays legal" {
	const world = World.create(1, 2).beginEpoch(1);
	const before = world.pets[4];
	const masks = world.masksFor(4);
	assert masks.economy.has(EconomyAction.Rest);
	assert masks.nodes.allowsNode(ALLOCATE_HOLD);
	assert masks.attacks.allowsChoice(ATTACK_HOLD);
	const after = world.apply(4, ActionSet.hold());
	assert after.pets[4] == before;
	assert after.stats.illegal == 0;
	assert after.pets[4].lastTickEpoch == 1;
	assert after.pets[4].harvest > 0;
}

test "an illegal action counts and changes nothing" {
	const world = World.create(1, 3).beginEpoch(1);
	const before = world.pets[0];
	const after = world.apply(0, { ...ActionSet.hold(), node: 23 });
	assert after.pets[0] == before;
	assert after.stats.illegal == 1;
}

test "a dead pet has empty masks and is buried once" {
	let world = World.create(1, 4).beginEpoch(1);
	const victim = world.pets[2];
	world.pets[2] = { ...victim, alive: false, hearts: 0, burrow: 900, harvest: 100 };
	const masks = world.masksFor(2);
	assert masks.economy.isEmpty();
	assert masks.nodes.bits == 0;
	assert masks.attacks.bits == 0;
	const mateBefore = world.pets[5].harvest;
	world = world.endEpoch();
	assert world.stats.deaths == 1;
	assert world.deathEpochs[2] == 1;
	assert world.pets[2].burrow == 0;
	assert world.pets[5].harvest == mateBefore + 55;
	const again = world.endEpoch();
	assert again.stats.deaths == 1;
}

test "an heir takes the slot after the grace period" {
	let world = World.create(1, 5).beginEpoch(1);
	world.pets[7] = { ...world.pets[7], alive: false, hearts: 0 };
	world = world.endEpoch().beginEpoch(1 + GRACE_EPOCHS - 1);
	assert !world.pets[7].alive;
	assert world.stats.heirs == 0;
	world = world.beginEpoch(1 + GRACE_EPOCHS);
	assert world.pets[7].alive;
	assert world.pets[7].lineageGeneration == 1;
	assert world.pets[7].slot == 7;
	assert world.pets[7].bornEpoch == 1 + GRACE_EPOCHS;
	assert world.deathEpochs[7] == 0;
	assert world.stats.heirs == 1;
}

test "a pet dies of age on day 90 and its heir returns with the estate after the grace" {
	const start = World.create(1, 5);
	const pets = start.pets;
	pets[4] = { ...pets[4], lastTickEpoch: LIFESPAN_EPOCHS - 2 };
	let world = start.beginEpoch(LIFESPAN_EPOCHS - 1);
	assert world.pets[4].alive;
	world = world.endEpoch().beginEpoch(LIFESPAN_EPOCHS);
	assert world.pets[4].agedOut();
	const wallet = world.pets[4].harvest + world.pets[4].burrow;
	const mateHarvest = world.pets[5].harvest;
	world = world.endEpoch();
	assert world.pets[5].harvest == mateHarvest;
	assert world.pets[4].burrow == wallet - wallet * INHERITANCE_TAX_PERCENT / 100;
	world = world.beginEpoch(LIFESPAN_EPOCHS + GRACE_EPOCHS);
	assert world.pets[4].alive;
	assert world.pets[4].lineageGeneration == 1;
	assert world.pets[4].burrow == wallet - wallet * INHERITANCE_TAX_PERCENT / 100;
}

test "a robbery leaves a grudge for three epochs and striking back settles it" {
	const start = World.create(1, 6);
	const pets = start.pets;
	for (let index = 0; index < pets.length; index++) {
		pets[index] = { ...pets[index], burrow: 400 * HBRN_UNIT, lastTickEpoch: 9 };
	}
	const world = start.beginEpoch(10);
	for (let index = 0; index < pets.length; index++) {
		pets[index] = { ...pets[index], harvest: 400 * HBRN_UNIT, burrow: 400 * HBRN_UNIT };
	}
	pets[3] = { ...pets[3], hearts: 5, might: 900 };
	const robbed = world.applyAttack(3, attackChoice(BlockSlot.Sixth, StakeLevel.Quarter));
	assert robbed.stats.illegal == 0;
	assert robbed.stats.wins == 1;
	const grudge = robbed.robberOf(5);
	assert grudge.ok;
	if (grudge.ok) { assert grudge.value == BlockSlot.Fourth; }
	const robber = robbed.robberOf(3);
	assert !robber.ok;
	if (!robber.ok) { assert robber.error == GrudgeError.None; }
	const later: World = { ...robbed, epoch: 13 };
	assert later.robberOf(5).ok;
	const stale: World = { ...robbed, epoch: 14 };
	const forgotten = stale.robberOf(5);
	assert !forgotten.ok;
	if (!forgotten.ok) { assert forgotten.error == GrudgeError.Stale; }
	const struckBack = robbed.applyAttack(5, attackChoice(BlockSlot.Fourth, StakeLevel.Quarter));
	assert struckBack.stats.fights == 2;
	assert !struckBack.robberOf(5).ok;
}
