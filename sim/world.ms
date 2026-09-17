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
	splitmix,
	attackHoldMask,
} from "../rules/index";

export const WORLD_BLOCKS: int32 = 20;
export const ACTS_PER_EPOCH: int32 = 4;
export const EPISODE_EPOCHS: int32 = 120;

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
	deathEpochs: uint64[];
	levelTenEpochs: uint64[];
	levelTwentyEpochs: uint64[];
	global: GlobalConfig;
	epoch: uint64;
	round: int32;
	seed: uint64;
	draws: uint64;
	stats: WorldStats;
}

export function create(this typeof World, blocks: int32, seed: uint64): World {
	let global = GlobalConfig.genesis(0);
	const pets: Pet[] = [];
	const deathEpochs: uint64[] = [];
	const levelTenEpochs: uint64[] = [];
	const levelTwentyEpochs: uint64[] = [];
	for (let index = 0; index < blocks * BLOCK_SLOTS; index++) {
		const slot = index % BLOCK_SLOTS;
		const hatched = Pet.born(
			(index / BLOCK_SLOTS) as uint32,
			slot as BlockSlot,
			(slot % 3) as Region,
			0,
			global,
		);
		pets.push(hatched.pet);
		deathEpochs.push(0);
		levelTenEpochs.push(0);
		levelTwentyEpochs.push(0);
		global = hatched.global;
	}
	return {
		pets: pets,
		deathEpochs: deathEpochs,
		levelTenEpochs: levelTenEpochs,
		levelTwentyEpochs: levelTwentyEpochs,
		global: global,
		epoch: 0,
		round: 0,
		seed: seed,
		draws: 0,
		stats: { fights: 0, wins: 0, deaths: 0, heirs: 0, illegal: 0 },
	};
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

export function beginEpoch(this world: World, epoch: uint64): World {
	const pets = world.pets;
	const deathEpochs = world.deathEpochs;
	const levelTenEpochs = world.levelTenEpochs;
	const levelTwentyEpochs = world.levelTwentyEpochs;
	let global = world.global;
	let heirs = world.stats.heirs;
	for (let index = 0; index < world.pets.length; index++) {
		const pet = pets[index];
		if (!pet.alive) {
			const diedAt = deathEpochs[index];
			if (diedAt == 0 || epoch < diedAt + GRACE_EPOCHS) { continue; }
			const hatched = Pet.born(pet.blockId, pet.blockSlot(), pet.startRegion(), epoch, global);
			levelTenEpochs[index] = 0;
			levelTwentyEpochs[index] = 0;
			pets[index] = {
				...hatched.pet,
				lineageGeneration: ((pet.lineageGeneration as int32) + 1) as uint16,
			};
			deathEpochs[index] = 0;
			global = hatched.global;
			heirs += 1;
			continue;
		}
		const ticked = pet.tickTo(global, epoch);
		if (!ticked.ok) { continue; }
		pets[index] = ticked.value.pet;
		global = ticked.value.global;
	}
	return {
		...world,
		global: global,
		epoch: epoch,
		round: 0,
		stats: { ...world.stats, heirs: heirs },
	};
}

export function endEpoch(this world: World): World {
	const pets = world.pets;
	const deathEpochs = world.deathEpochs;
	const levelTenEpochs = world.levelTenEpochs;
	const levelTwentyEpochs = world.levelTwentyEpochs;
	let global = world.global;
	let deaths = world.stats.deaths;
	for (let index = 0; index < world.pets.length; index++) {
		const pet = pets[index];
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
	const draws = world.draws + 1;
	const seed = splitmix(world.seed ^ (draws * 0x9e3779b97f4a7c15));
	const settled = pet.settleAttack(pets[target], level, world.global, world.epoch, seed);
	if (!settled.ok) { return world.counted(true); }
	pets[index] = settled.value.attacker;
	pets[target] = settled.value.defender;
	const won = settled.value.record.loot > 0 ? 1 : 0;
	return {
		...world,
		global: settled.value.global,
		draws: draws,
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
	let workPower: uint64 = 0;
	for (let index = 0; index < world.pets.length; index++) {
		workPower += world.pets[index].stats().workPower();
	}
	assert world.global.totalWorkPower == workPower;
	assert world.pets[13].blockId == 1;
	assert world.pets[13].slot == 3;
	assert world.pets[13].startRegion() == Region.Worker;
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
