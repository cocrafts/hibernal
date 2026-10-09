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
	attackChoice,
	HBRN_UNIT,
	EPOCH_SECONDS,
	LIFESPAN_EPOCHS,
	INHERITANCE_TAX_PERCENT,
	agedOut,
	heirOf,
	TalentKind,
	built,
	withNode,
	unrevealed,
	settle,
	Listing,
	MarketError,
	listingGain,
	listedItem,
	boughtListing,
	expiredAt,
	paidFor,
	boughtBack,
	LISTING_DAYS,
	MARKET_FEE_BPS,
	BPS,
	GearSlot,
	ItemSkill,
	TalentGrade,
	minted,
	bare,
	with,
	sellPrice,
	ACTS_PER_EPOCH,
	GrudgeError,
	Surroundings,
	MarketView,
	economyMask,
	attackMask,
	actorPet,
	combatant,
	PersonaKind,
	StrengthMeasure,
	strengthOf,
	resortsAt,
	movedTo,
	overtimeBanked,
	wildOf,
	retiredWild,
} from "../rules/index";
import { Gear, Item } from "../rules/items";
import { OwnerKind, OwnerLedger, habitOf, ownerKindFor, visitDraw, visits, visited, openDraw, opens } from "./owner";

export { ACTS_PER_EPOCH, GrudgeError } from "../rules/index";

export const WORLD_BLOCKS: int32 = 20;
export const EPISODE_EPOCHS: int32 = 120;
export const INITIAL_CLAIM_DAYS: int32 = 30;
export const GRUDGE_EPOCHS: uint64 = 3;
export const PERSONA_BUILD: int32 = -2;
export const NO_KEYSTONE: int32 = -1;

export struct Grudge {
	robber: BlockSlot;
	epoch: uint64;
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

export struct Resort {
	every: uint64;
	measure: StrengthMeasure;
	wildDefenders: boolean;
}

export function fixed(this typeof Resort): Resort {
	return { every: 0, measure: StrengthMeasure.Combat, wildDefenders: true };
}

export struct WorldStats {
	fights: int32;
	wins: int32;
	deaths: int32;
	heirs: int32;
	illegal: int32;
	sales: int32;
	lastSeller: int32;
	lastPrice: uint64;
	lastProceeds: uint64;
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
	personas: PersonaKind[];
	origins: int32[];
	movedEpoch: uint64;
	resort: Resort;
	global: GlobalConfig;
	epoch: uint64;
	round: int32;
	turns: int32[];
	absent: Pet[];
	market: Listing[];
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
	const personas: PersonaKind[] = [];
	const origins: int32[] = [];
	const turns: int32[] = [];
	const absent: Pet[] = [];
	for (let index = 0; index < blocks * BLOCK_SLOTS; index++) {
		const slot = index % BLOCK_SLOTS;
		turns.push(index);
		owners.push(ownerKindFor(seed, index));
		ownerLedgers.push({ visits: 0, skr: 0, refusals: 0, banked: 0 });
		personas.push(((slot / 3) % 3) as PersonaKind);
		origins.push(index);
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
		absent.push({ ...hatched.pet, alive: false });
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
		personas: personas,
		origins: origins,
		movedEpoch: 0,
		resort: Resort.fixed(),
		global: { ...global, floorSlots: (blocks * BLOCK_SLOTS) as uint32 },
		epoch: 0,
		round: 0,
		turns: turns,
		absent: absent,
		market: [],
		seed: seed,
		stats: {
			fights: 0,
			wins: 0,
			deaths: 0,
			heirs: 0,
			illegal: 0,
			sales: 0,
			lastSeller: 0,
			lastPrice: 0,
			lastProceeds: 0,
		},
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
	return { ...world, global: { ...GlobalConfig.genesis(0), floorSlots: total as uint32 } };
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
	const absent = world.absent;
	const claimEpochs = world.claimEpochs;
	const grudges = world.grudges;
	const deathEpochs = world.deathEpochs;
	const levelTenEpochs = world.levelTenEpochs;
	const levelTwentyEpochs = world.levelTwentyEpochs;
	let global = world.global.settle(epoch);
	let heirs = world.stats.heirs;
	for (let index = 0; index < world.pets.length; index++) {
		const claimEpoch = claimEpochs[index];
		if (claimEpoch != 0 && epoch >= claimEpoch) {
			global = vacated(pets, absent, index, global);
			const seat = pets[index];
			const claimed = Pet.born(seat.blockId, seat.blockSlot(), seat.startRegion(), claimEpoch, global);
			pets[index] = claimed.pet;
			claimEpochs[index] = 0;
			global = claimed.global;
		}
		const real = pets[index].wild ? absent[index] : pets[index];
		const diedAt = deathEpochs[index];
		if (claimEpochs[index] == 0 && !real.alive && diedAt != 0 && epoch >= diedAt + GRACE_EPOCHS) {
			global = vacated(pets, absent, index, global);
			const heir = real.heirOf(epoch, global);
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
		if (!pets[index].alive) { continue; }
		const ticked = pets[index].tickTo(global, epoch);
		if (!ticked.ok) { continue; }
		pets[index] = ticked.value.pet;
		global = ticked.value.global;
		if (pets[index].wild && !pets[index].alive) {
			global = vacated(pets, absent, index, global);
			continue;
		}
		const randomness = mixSeeds(mixSeeds(world.seed, index as uint64), epoch);
		const revealed = pets[index].revealTalent(global, randomness);
		if (revealed.ok) {
			pets[index] = revealed.value.pet;
			global = revealed.value.global;
		}
	}
	const market: Listing[] = [];
	for (const listing of world.market) {
		if (!listing.expiredAt(epoch)) {
			market.push(listing);
			continue;
		}
		const seller = listing.seller as int32;
		const back = pets[seller].boughtBack(listing, global);
		if (!back.ok) { unreachable; }
		pets[seller] = back.value.pet;
		global = back.value.global;
	}
	const begun: World = {
		...world,
		global: global,
		epoch: epoch,
		market: market,
		stats: { ...world.stats, heirs: heirs },
	};
	const placed = resortsAt(epoch, world.resort.every) ? begun.resorted() : begun.newbornsPlacedWeak();
	return placed.ownersVisited().wildsSpawned().inRound(0);
}

export function personaOf(this world: World, index: int32): PersonaKind {
	return world.personas[index];
}

function isFree(this world: World, index: int32): boolean {
	return !world.realAt(index).alive && world.claimEpochs[index] == 0;
}

export function realAt(this world: World, index: int32): Pet {
	return world.pets[index].wild ? world.absent[index] : world.pets[index];
}

function vacated(pets: Pet[], absent: Pet[], index: int32, global: GlobalConfig): GlobalConfig {
	const wild = pets[index];
	if (!wild.wild) { return global; }
	pets[index] = absent[index];
	return wild.retiredWild(global);
}

export function strengthOrder(this world: World): int32[] {
	const measure = world.resort.measure;
	const strengths: uint64[] = [];
	const order: int32[] = [];
	for (let index = 0; index < world.pets.length; index++) {
		strengths.push(world.pets[index].strengthOf(measure));
		if (!world.pets[index].alive) { continue; }
		let position = order.length;
		order.push(index);
		while (position > 0 && strengths[order[position - 1]] < strengths[index]) {
			order[position] = order[position - 1];
			position -= 1;
		}
		order[position] = index;
	}
	for (let index = 0; index < world.pets.length; index++) {
		if (!world.pets[index].alive) { order.push(index); }
	}
	return order;
}

export function permuted(this world: World, origins: int32[]): World {
	const pets: Pet[] = [];
	const absent: Pet[] = [];
	const claimEpochs: uint64[] = [];
	const deathEpochs: uint64[] = [];
	const levelTenEpochs: uint64[] = [];
	const levelTwentyEpochs: uint64[] = [];
	const grudges: Grudge[] = [];
	const buildTargets: int32[] = [];
	const owners: OwnerKind[] = [];
	const ownerLedgers: OwnerLedger[] = [];
	const personas: PersonaKind[] = [];
	for (let index = 0; index < origins.length; index++) {
		const origin = origins[index];
		const blockId = (index / BLOCK_SLOTS) as uint32;
		const slot = (index % BLOCK_SLOTS) as BlockSlot;
		const moved = origin != index;
		pets.push(moved ? world.pets[origin].movedTo(blockId, slot) : world.pets[origin]);
		absent.push(world.absent[origin].movedTo(blockId, slot));
		claimEpochs.push(world.claimEpochs[origin]);
		deathEpochs.push(world.deathEpochs[origin]);
		levelTenEpochs.push(world.levelTenEpochs[origin]);
		levelTwentyEpochs.push(world.levelTwentyEpochs[origin]);
		grudges.push(moved ? Grudge.none() : world.grudges[origin]);
		buildTargets.push(world.buildTargets[origin]);
		owners.push(world.owners[origin]);
		ownerLedgers.push(world.ownerLedgers[origin]);
		personas.push(world.personas[origin]);
	}
	return {
		...world,
		pets: pets,
		absent: absent,
		claimEpochs: claimEpochs,
		deathEpochs: deathEpochs,
		levelTenEpochs: levelTenEpochs,
		levelTwentyEpochs: levelTwentyEpochs,
		grudges: grudges,
		buildTargets: buildTargets,
		owners: owners,
		ownerLedgers: ownerLedgers,
		personas: personas,
		origins: origins,
		movedEpoch: world.epoch,
	};
}

export function resorted(this world: World): World {
	const pets = world.pets;
	let global = world.global;
	for (let index = 0; index < pets.length; index++) {
		global = vacated(pets, world.absent, index, global);
	}
	for (const listing of world.market) {
		const seller = listing.seller as int32;
		const back = pets[seller].boughtBack(listing, global);
		if (!back.ok) { unreachable; }
		pets[seller] = back.value.pet;
		global = back.value.global;
	}
	const unlisted: World = { ...world, global: global, market: [] };
	const order = unlisted.strengthOrder();
	const everyone: World = unlisted.permuted(order);
	const forgotten = everyone.pets;
	const grudges = everyone.grudges;
	for (let index = 0; index < forgotten.length; index++) {
		forgotten[index] = forgotten[index].movedTo(forgotten[index].blockId, forgotten[index].blockSlot());
		grudges[index] = Grudge.none();
	}
	return everyone;
}

export function newbornsPlacedWeak(this world: World): World {
	if (world.resort.every == 0) { return world; }
	const origins: int32[] = [];
	for (let index = 0; index < world.pets.length; index++) { origins.push(index); }
	let moved = false;
	let free = world.pets.length - 1;
	for (let index = 0; index < world.pets.length; index++) {
		const pet = world.pets[index];
		if (!pet.alive || pet.bornEpoch != world.epoch) { continue; }
		while (free > index && !(world.isFree(origins[free]) && origins[free] == free)) { free -= 1; }
		if (free / BLOCK_SLOTS <= index / BLOCK_SLOTS) { continue; }
		origins[index] = free;
		origins[free] = index;
		free -= 1;
		moved = true;
	}
	if (!moved) { return world; }
	let global = world.global;
	for (let index = 0; index < origins.length; index++) {
		if (origins[index] != index) { global = vacated(world.pets, world.absent, index, global); }
	}
	const settled: World = { ...world, global: global };
	return settled.permuted(origins);
}

export function wildsSpawned(this world: World): World {
	if (!world.resort.wildDefenders) { return world; }
	const pets = world.pets;
	const absent = world.absent;
	const level = Math.max(world.medianLevel(), 1);
	let global = world.global;
	for (let index = 0; index < pets.length; index++) {
		const seat = pets[index];
		const settled = world.claimEpochs[index] != 0 || world.deathEpochs[index] != 0;
		if (seat.alive || !settled) { continue; }
		const region = seat.startRegion();
		const spawned = wildOf(seat.blockId, seat.blockSlot(), region, level, world.epoch, global);
		absent[index] = seat;
		pets[index] = spawned.pet;
		world.grudges[index] = Grudge.none();
		global = spawned.global;
	}
	return { ...world, global: global };
}

export function isWild(this world: World, position: int32): boolean {
	return world.pets[position].wild;
}

export function defenderAt(this world: World, position: int32): Pet {
	return world.pets[position];
}

export function ownersVisited(this world: World): World {
	const pets = world.pets;
	const ledgers = world.ownerLedgers;
	for (let index = 0; index < pets.length; index++) {
		if (!pets[index].alive || pets[index].wild) { continue; }
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
			banked: ledger.banked + visit.banked,
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
	const shuffled: World = { ...world, round: round };
	return round > 0 ? shuffled.ownersOpened() : shuffled;
}

export function ownersOpened(this world: World): World {
	const pets = world.pets;
	const ledgers = world.ownerLedgers;
	const roundSeconds = EPOCH_SECONDS / (ACTS_PER_EPOCH as uint64);
	const now = world.epoch * EPOCH_SECONDS + (world.round as uint64) * roundSeconds;
	for (let index = 0; index < pets.length; index++) {
		const pet = pets[index];
		if (!pet.alive || pet.wild) { continue; }
		const draw = openDraw(world.seed, index, world.epoch, world.round);
		if (!habitOf(world.owners[index]).opens(draw)) { continue; }
		const engaged = pet.engagedAt(now);
		const opened = engaged.ok ? engaged.value : pet;
		const banked = opened.ownerBanked(now);
		if (!banked.ok) {
			pets[index] = opened;
			continue;
		}
		const ledger = ledgers[index];
		ledgers[index] = { ...ledger, banked: ledger.banked + banked.value.burrow - opened.burrow };
		pets[index] = banked.value;
	}
	return world;
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
		if (pet.wild) {
			if (!pet.alive) { global = vacated(pets, world.absent, index, global); }
			continue;
		}
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
	for (let index = 0; index < world.pets.length; index++) {
		pets[index] = pets[index].overtimeBanked();
	}
	return { ...world, global: global, stats: { ...world.stats, deaths: deaths } };
}

export function surroundingsOf(this world: World, index: int32): Surroundings {
	return {
		pets: world.pets,
		wilds: world.absent,
		base: blockStart(index),
		actor: (index % BLOCK_SLOTS) as BlockSlot,
		global: world.global,
		epoch: world.epoch,
		round: world.round,
		robber: world.robberOf(index),
	};
}

export function marketViewOf(this world: World, index: int32): MarketView {
	const best = world.bestListingFor(index);
	const offer: Result<Listing, MarketError> = best.ok
		? Result.ok(world.market[best.value])
		: Result.err(best.error);
	return { listed: world.hasListing(index), offer: offer };
}

export function attackMaskFor(this world: World, index: int32): AttackMask {
	const around = world.surroundingsOf(index);
	return around.attackMask(around.actorPet().combatant());
}

export function hasListing(this world: World, index: int32): boolean {
	for (const listing of world.market) {
		if (listing.seller == (index as uint32)) { return true; }
	}
	return false;
}

function outranks(this listing: Listing, gain: int32, best: Listing, bestGain: int32): boolean {
	if (gain != bestGain) { return gain > bestGain; }
	if (listing.price != best.price) { return listing.price < best.price; }
	return listing.seller < best.seller;
}

export function bestListingFor(this world: World, index: int32): Result<int32, MarketError> {
	const pet = world.pets[index];
	const block = blockStart(index);
	let best = -1;
	let bestGain = 0;
	for (let position = 0; position < world.market.length; position++) {
		const listing = world.market[position];
		const seller = listing.seller as int32;
		if (blockStart(seller) != block || seller == index || listing.price > pet.burrow) {
			continue;
		}
		const gain = pet.listingGain(listing);
		if (gain <= 0) { continue; }
		if (best < 0 || listing.outranks(gain, world.market[best], bestGain)) {
			best = position;
			bestGain = gain;
		}
	}
	if (best < 0) { return Result.err(MarketError.NotWanted); }
	return Result.ok(best);
}

export function economyMaskFor(this world: World, index: int32): BitSet<EconomyAction> {
	return world.surroundingsOf(index).economyMask(world.marketViewOf(index));
}

export function masksFor(this world: World, index: int32): Masks {
	const pet = world.pets[index];
	return {
		economy: world.economyMaskFor(index),
		nodes: pet.legalNodes(world.global),
		attacks: world.attackMaskFor(index),
	};
}

function counted(this world: World, illegal: boolean): World {
	if (!illegal) { return world; }
	return { ...world, stats: { ...world.stats, illegal: world.stats.illegal + 1 } };
}

function listedBy(this world: World, index: int32): World {
	if (!world.economyMaskFor(index).has(EconomyAction.ListItem)) { return world.counted(true); }
	const listed = world.pets[index].listedItem(world.global, index as uint32, world.epoch);
	if (!listed.ok) { return world.counted(true); }
	const pets = world.pets;
	const market = world.market;
	pets[index] = listed.value.pet;
	market.push(listed.value.listing);
	return { ...world, global: listed.value.global };
}

function boughtBy(this world: World, index: int32): World {
	const found = world.bestListingFor(index);
	if (!found.ok) { return world.counted(true); }
	const listing = world.market[found.value];
	const bought = world.pets[index].boughtListing(listing, index as uint32, world.global);
	if (!bought.ok) { return world.counted(true); }
	const pets = world.pets;
	pets[index] = bought.value.buyer;
	const seller = listing.seller as int32;
	const paid = pets[seller].paidFor(listing, bought.value.proceeds, bought.value.global);
	pets[seller] = paid.pet;
	const market: Listing[] = [];
	for (let position = 0; position < world.market.length; position++) {
		if (position != found.value) { market.push(world.market[position]); }
	}
	const stats: WorldStats = {
		...world.stats,
		sales: world.stats.sales + 1,
		lastSeller: seller,
		lastPrice: listing.price,
		lastProceeds: bought.value.proceeds,
	};
	return { ...world, global: paid.global, market: market, stats: stats };
}

export function applyEconomy(this world: World, index: int32, action: EconomyAction): World {
	const pets = world.pets;
	const pet = pets[index];
	if (!pet.alive) { return world; }
	if (action == EconomyAction.ListItem) { return world.listedBy(index); }
	if (action == EconomyAction.BuyItem) { return world.boughtBy(index); }
	const round = (world.epoch << (2 as uint64)) | (world.round as uint64);
	const seed = mixSeeds(mixSeeds(mixSeeds(world.seed, 7919), index as uint64), round);
	const economy = pet.doEconomy(action, world.global, seed);
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
	const defender = world.defenderAt(target);
	const settled = pet.settleAttack(defender, level, world.global, world.epoch, seed);
	if (!settled.ok) { return world.counted(true); }
	pets[index] = settled.value.attacker;
	const won = settled.value.record.loot > 0 ? 1 : 0;
	pets[target] = settled.value.defender;
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
		if (!pet.alive || pet.wild) { continue; }
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
		if (!pet.alive || pet.wild) { continue; }
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
		if (world.pets[index].alive && !world.pets[index].wild) { count += 1; }
	}
	return count;
}

test "alive wilds count in global work but not owner metrics" {
	const world = World.staggered(1, 7).wildsSpawned();
	let weight: uint64 = 0;
	for (let index = 0; index < world.pets.length; index++) {
		const pet = world.pets[index];
		assert pet.alive && pet.wild;
		assert !world.realAt(index).alive;
		weight += pet.stats().rewardWeight();
	}
	assert weight > 0;
	assert world.global.livingPets == (BLOCK_SLOTS as uint32);
	assert world.global.totalWorkPower == weight;
	assert world.living() == 0;
	assert world.sortedWealth().length == 0;
	assert world.medianLevel() == 0;
	const ended = world.endEpoch();
	assert ended.stats.deaths == 0 && ended.stats.heirs == 0;
	assert ended.global.livingPets == world.global.livingPets;
	assert ended.global.totalWorkPower == weight;
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

test "an owner who opens the app again waits out the 8-hour cooldown" {
	const world = World.create(2, 5).beginEpoch(1);
	const dawn = world.epoch * EPOCH_SECONDS;
	const before: uint64[] = [];
	for (const ledger of world.ownerLedgers) { before.push(ledger.banked); }
	const later = world.inRound(1);
	let opened = 0;
	for (let index = 0; index < later.pets.length; index++) {
		const moved = later.ownerLedgers[index].banked - before[index];
		if (later.pets[index].ownerBankedAt == dawn) { assert moved == 0; }
		if (moved > 0) { opened += 1; }
	}
	const noon = later.inRound(2);
	let banked = 0;
	for (let index = 0; index < noon.pets.length; index++) {
		if (noon.pets[index].ownerBankedAt > dawn) { banked += 1; }
	}
	assert banked > opened;
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

test "a listed item sells to a pet that wants it, and an unsold one is bought back" {
	let world = World.create(1, 6).beginEpoch(1);
	const might = Item.minted(TalentGrade.Epic, TalentKind.Might, ItemSkill.None, 1);
	world.pets[0] = { ...world.pets[0], gear: Gear.bare().with(GearSlot.Head, might) };
	assert world.economyMaskFor(0).has(EconomyAction.ListItem);
	world = world.applyEconomy(0, EconomyAction.ListItem);
	assert world.market.length == 1 && world.hasListing(0);
	assert !world.economyMaskFor(0).has(EconomyAction.ListItem);
	const price = world.market[0].price;
	world.pets[1] = { ...world.pets[1], burrow: price };
	assert world.economyMaskFor(1).has(EconomyAction.BuyItem);
	assert !world.economyMaskFor(2).has(EconomyAction.BuyItem);
	const far = World.create(2, 6).beginEpoch(1);
	far.market.push(world.market[0]);
	far.pets[11] = { ...far.pets[11], burrow: price };
	assert !far.economyMaskFor(11).has(EconomyAction.BuyItem);
	const sellerBurrow = world.pets[0].burrow;
	world = world.applyEconomy(1, EconomyAction.BuyItem);
	assert world.market.length == 0;
	assert world.pets[1].gear.head == might;
	const fee = price * (MARKET_FEE_BPS as uint64) / (BPS as uint64);
	assert world.pets[0].burrow == sellerBurrow + price - fee;
	assert world.stats.sales == 1 && world.stats.lastSeller == 0;
	assert world.stats.illegal == 0;
	world.pets[0] = { ...world.pets[0], gear: Gear.bare().with(GearSlot.Head, might) };
	const reserve = world.global.itemReserve + might.sellPrice();
	world = { ...world, global: { ...world.global, itemReserve: reserve } };
	world = world.applyEconomy(0, EconomyAction.ListItem);
	const listedBurrow = world.pets[0].burrow;
	world = world.endEpoch().beginEpoch(1 + LISTING_DAYS - 1);
	assert world.market.length == 1;
	world = world.endEpoch().beginEpoch(1 + LISTING_DAYS);
	assert world.market.length == 0;
	assert world.pets[0].burrow == listedBurrow + might.sellPrice();
}

test "a dead wild retires its wallet once and restores the absent pet" {
	let world = World.create(1, 5).beginEpoch(1);
	world.pets[7] = { ...world.pets[7], alive: false, hearts: 0 };
	world = world.endEpoch().beginEpoch(2);
	assert world.pets[7].wild && world.pets[7].alive;
	const absent = world.absent[7];
	const wild: Pet = { ...world.pets[7], alive: false, hearts: 0, harvest: 40, burrow: 60 };
	world.pets[7] = wild;
	const expected = wild.retiredWild(world.global);
	world = world.endEpoch();
	assert world.pets[7] == absent;
	assert world.global.treasury == expected.treasury;
	assert world.global.livingPets == expected.livingPets;
	assert world.global.totalWorkPower == expected.totalWorkPower;
	const treasury = world.global.treasury;
	world = world.endEpoch();
	assert world.global.treasury == treasury;
}

test "an heir takes the slot after the grace period" {
	let world = World.create(1, 5).beginEpoch(1);
	world.pets[7] = { ...world.pets[7], alive: false, hearts: 0 };
	world = world.endEpoch().beginEpoch(1 + GRACE_EPOCHS - 1);
	assert !world.realAt(7).alive;
	assert world.pets[7].wild && world.pets[7].alive;
	assert world.stats.heirs == 0;
	world = world.beginEpoch(1 + GRACE_EPOCHS);
	assert world.pets[7].alive && !world.pets[7].wild;
	assert world.pets[7].lineageGeneration == 1;
	assert world.pets[7].slot == 7;
	assert world.pets[7].bornEpoch == 1 + GRACE_EPOCHS;
	assert world.deathEpochs[7] == 0;
	assert world.stats.heirs == 1;
}

test "a wild replaced by an heir before re-sort retires its share exactly once" {
	let world = World.create(1, 5);
	const heirEpoch = 1 + GRACE_EPOCHS;
	world = {
		...world,
		epoch: 1,
		resort: {
			every: heirEpoch,
			measure: StrengthMeasure.Combat,
			wildDefenders: true,
		},
	};
	for (let index = 0; index < world.pets.length; index++) {
		world.owners[index] = OwnerKind.Absent;
	}
	const victim = world.pets[7];
	world.pets[7] = { ...victim, alive: false, hearts: 0 };
	world = { ...world, global: world.global.withDeath(victim.stats().rewardWeight()) };
	world = world.endEpoch().wildsSpawned();
	assert world.pets[7].wild && world.pets[7].alive;
	const wild: Pet = { ...world.pets[7], harvest: 40, burrow: 60, giftOwed: 7 };
	world.pets[7] = wild;
	const settled = world.global.settle(heirEpoch);
	const expected = wild.retiredWild(settled);
	assert expected.treasury > settled.treasury + 107;
	world = world.beginEpoch(heirEpoch);
	assert world.global.treasury == expected.treasury;
	assert world.global.livingPets == (world.pets.length as uint32);
	let weight: uint64 = 0;
	let heirs = 0;
	for (let index = 0; index < world.pets.length; index++) {
		const pet = world.pets[index];
		assert pet.alive && !pet.wild;
		weight += pet.stats().rewardWeight();
		if (world.origins[index] != 7) { continue; }
		assert pet.lineageGeneration == 1 && pet.bornEpoch == heirEpoch;
		assert pet.burrow == 0 && pet.giftOwed == 0;
		assert world.deathEpochs[index] == 0;
		heirs += 1;
	}
	assert heirs == 1 && world.stats.heirs == 1;
	assert world.global.totalWorkPower == weight;
	const before = world.global;
	world = world.resorted().resorted();
	assert world.global == before;
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

test "a re-sort puts the strongest ten in the first block and forgets every grudge" {
	const start = World.create(3, 11);
	const world: World = { ...start, resort: { every: 7, measure: StrengthMeasure.Combat, wildDefenders: false } };
	const pets = world.pets;
	const grudges = world.grudges;
	for (let index = 0; index < pets.length; index++) {
		pets[index] = { ...pets[index], might: (100 + ((index * 37) % 29) * 10) as uint16, rage: 1, grudgeSlot: 2 };
	}
	pets[25] = { ...pets[25], alive: false };
	grudges[4] = { robber: BlockSlot.Third, epoch: 5 };
	const persona = world.personaOf(17);
	const might = pets[17].might;
	const sorted = world.resorted();
	for (let index = 1; index < 29; index++) {
		assert sorted.pets[index - 1].strengthOf(StrengthMeasure.Combat) >= sorted.pets[index].strengthOf(StrengthMeasure.Combat);
	}
	assert !sorted.pets[29].alive;
	for (let index = 0; index < sorted.pets.length; index++) {
		const pet = sorted.pets[index];
		assert pet.blockId == ((index / BLOCK_SLOTS) as uint32) && (pet.slot as int32) == index % BLOCK_SLOTS;
		assert pet.rage == 0 && sorted.grudges[index].epoch == 0;
		if (sorted.origins[index] == 17) {
			assert sorted.personaOf(index) == persona && pet.might == might;
		}
	}
}

test "a newborn takes a free slot in a weaker block between two re-sorts" {
	const start = World.create(3, 11);
	const world: World = { ...start, epoch: 9, resort: { every: 7, measure: StrengthMeasure.Combat, wildDefenders: false } };
	const pets = world.pets;
	pets[27] = { ...pets[27], alive: false };
	pets[3] = { ...pets[3], bornEpoch: 9 };
	const placed = world.newbornsPlacedWeak();
	assert placed.pets[27].alive && placed.pets[27].bornEpoch == 9 && placed.pets[27].blockId == 2;
	assert !placed.pets[3].alive;
	assert placed.origins[27] == 3 && placed.origins[3] == 27;
}
