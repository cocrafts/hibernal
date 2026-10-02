@include("runtime/solana/solana.h");
import {
	Account,
	AccountMeta,
	Bytes,
	borshBuffer,
	Discriminator,
	Mutable,
	Owned,
	ProgramError,
	Pubkey,
	clock,
	instructionDiscriminator,
	mutable,
	pdaWithBump,
	readArgs,
	selectInstruction,
} from "std/solana";
import { accounts, args } from "std/solana/macro";
import { RandomnessRequest, requestRandomness, verifyVrfCallback } from "std/solana/vrf";
import {
	ACTS_PER_EPOCH,
	ALLOCATE_HOLD,
	ATTACK_HOLD,
	BLOCK_SLOTS,
	EPOCH_SECONDS,
	GRACE_EPOCHS,
	STAKE_LEVELS,
	BlockSlot,
	Combatant,
	Dice,
	EconomyAction,
	FightRecord,
	GlobalConfig,
	GrudgeError,
	Listing,
	MarketError,
	MarketView,
	Pet,
	PersonaKind,
	StakeLevel,
	actorPet,
	boughtBack,
	boughtListing,
	bury,
	checkPolicy,
	doEconomy,
	expiredAt,
	fightSeed,
	heirOf,
	legalNodes,
	listedItem,
	listingGain,
	mixSeeds,
	allocateNodeWithSums,
	paidFor,
	revealTalent,
	rivalsInto,
	roll,
	settle,
	settleAttack,
	summed,
	tickTo,
} from "../rules/index";
import {
	Block,
	Config,
	FIGHTS,
	Grudge,
	HibernalError,
	LISTINGS,
	PetAccount,
	Phase,
	Policy,
	SEATS,
	SeededArgs,
	VrfPayer,
	World,
	hibernalError,
	vrfPayerSeeds,
} from "./layout";
import {
	ActContext,
	attackChoice,
	buffersMatchRules,
	economyChoice,
	nodeChoice,
	observedSelf,
	observedSelfForNodeAndAttack,
	surroundingsIn,
} from "./brain";

extern function msSolAlloc(size: uint64): uint64;

export const GRUDGE_EPOCHS: uint64 = 3;
export const ECONOMY_SALT: uint64 = 7919;
export const STEP_PET_ACCOUNT: int32 = 10;
export const SEEDED_PET_ACCOUNT: int32 = 3;
export const SEED_RETRY_SECONDS: int64 = 30;

export struct StepAccounts {
	payer: Mutable<VrfPayer>;
	config: Owned<Config>;
	world: Mutable<World>;
	block: Mutable<Block>;
	policy: Owned<Policy>;
	programIdentity: Account;
	oracleQueue: Account;
	slotHashes: Account;
	systemProgram: Account;
	vrfProgram: Account;
}

export struct SeededAccounts {
	identity: Account;
	world: Mutable<World>;
	block: Mutable<Block>;
}

export struct BlockPets {
	pets: Pet[10];
	records: uint64[10];
}

struct Acted {
	global: GlobalConfig;
	choice: int32;
}

export function epochAt(genesisTimestamp: uint64, unixTimestamp: int64): uint64 {
	if (unixTimestamp < 0 || (unixTimestamp as uint64) < genesisTimestamp) { return 0; }
	return ((unixTimestamp as uint64) - genesisTimestamp) / EPOCH_SECONDS + 1;
}

export function seedOf(randomness: Pubkey): uint64 {
	let seed: uint64 = 0;
	for (let word = 0; word < 4; word++) {
		let value: uint64 = 0;
		for (let position = 7; position >= 0; position--) {
			value = (value << (8 as uint64)) | (randomness.bytes[word * 8 + position] as uint64);
		}
		seed = seed ^ value;
	}
	return seed;
}

function seededInstruction(): Discriminator {
	return @comptime { return instructionDiscriminator("Seeded"); };
}

export function seededDiscriminator(): uint64 {
	const discriminator = seededInstruction();
	let value: uint64 = 0;
	for (let position = 7; position >= 0; position--) {
		value = (value << (8 as uint64)) | (discriminator.bytes[position] as uint64);
	}
	return value;
}

export function turnOrder(roundSeed: uint64, epoch: uint64, blockId: uint32, round: int32, turns: Span<uint8>): void {
	const dice: Dice = {
		seed: mixSeeds(mixSeeds(roundSeed, epoch), ((blockId as uint64) << (8 as uint64)) | (round as uint64)),
		draw: 0,
	};
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) { turns[slot] = slot as uint8; }
	for (let last = BLOCK_SLOTS - 1; last > 0; last--) {
		const picked = dice.roll(last, 0, last);
		const waiting = turns[last];
		turns[last] = turns[picked];
		turns[picked] = waiting;
	}
}

export function economySeedOf(roundSeed: uint64, seat: int32, epoch: uint64, round: int32): uint64 {
	const turnSeed = (epoch << (2 as uint64)) | (round as uint64);
	return mixSeeds(mixSeeds(mixSeeds(roundSeed, ECONOMY_SALT), seat as uint64), turnSeed);
}

export function revealSeedOf(roundSeed: uint64, seat: int32, epoch: uint64): uint64 {
	return mixSeeds(mixSeeds(roundSeed, seat as uint64), epoch);
}

export function robberOf(block: Ptr<Block>, seat: int32, epoch: uint64): Result<BlockSlot, GrudgeError> {
	const grudge = block.grudges[seat];
	if (grudge.epoch == 0) { return Result.err(GrudgeError.None); }
	if (epoch > grudge.epoch + GRUDGE_EPOCHS) { return Result.err(GrudgeError.Stale); }
	return Result.ok(grudge.robber as BlockSlot);
}

function noGrudge(): Grudge {
	return { robber: 0, pad: [], epoch: 0 };
}

function outranks(listing: Listing, gain: int32, best: Listing, bestGain: int32): boolean {
	if (gain != bestGain) { return gain > bestGain; }
	if (listing.price != best.price) { return listing.price < best.price; }
	return listing.seller < best.seller;
}

export function bestListingFor(block: Ptr<Block>, pets: Span<Pet>, seat: int32): Result<int32, MarketError> {
	const pet = pets[seat];
	let best = -1;
	let bestGain = 0;
	for (let position = 0; position < LISTINGS; position++) {
		if (block.listed[position] == 0) { continue; }
		const listing = block.listings[position];
		const seller = listing.seller as int32;
		if (seller == seat || listing.price > pet.burrow) { continue; }
		const gain = pet.listingGain(listing);
		if (gain <= 0) { continue; }
		if (best < 0 || outranks(listing, gain, block.listings[best], bestGain)) {
			best = position;
			bestGain = gain;
		}
	}
	if (best < 0) { return Result.err(MarketError.NotWanted); }
	return Result.ok(best);
}

function hasListing(block: Ptr<Block>, seat: int32): boolean {
	for (let position = 0; position < LISTINGS; position++) {
		if (block.listed[position] != 0 && block.listings[position].seller == (seat as uint32)) { return true; }
	}
	return false;
}

export function marketViewOf(block: Ptr<Block>, pets: Span<Pet>, seat: int32): MarketView {
	const best = bestListingFor(block, pets, seat);
	const offer: Result<Listing, MarketError> = best.ok
		? Result.ok(block.listings[best.value])
		: Result.err(best.error);
	return { listed: hasListing(block, seat), offer: offer };
}

function freeListing(block: Ptr<Block>): int32 {
	for (let position = 0; position < LISTINGS; position++) {
		if (block.listed[position] == 0) { return position; }
	}
	return -1;
}

function listedBy(block: Ptr<Block>, pets: Span<Pet>, seat: int32, global: GlobalConfig, epoch: uint64): GlobalConfig {
	const position = freeListing(block);
	if (position < 0) { return global; }
	const listed = pets[seat].listedItem(global, seat as uint32, epoch);
	if (!listed.ok) { return global; }
	pets[seat] = listed.value.pet;
	block.listings[position] = listed.value.listing;
	block.listed[position] = 1;
	return listed.value.global;
}

function boughtBy(block: Ptr<Block>, pets: Span<Pet>, seat: int32, global: GlobalConfig): GlobalConfig {
	const found = bestListingFor(block, pets, seat);
	if (!found.ok) { return global; }
	const listing = block.listings[found.value];
	const bought = pets[seat].boughtListing(listing, seat as uint32, global);
	if (!bought.ok) { return global; }
	pets[seat] = bought.value.buyer;
	const seller = (listing.seller as int32) % BLOCK_SLOTS;
	const paid = pets[seller].paidFor(listing, bought.value.proceeds, bought.value.global);
	pets[seller] = paid.pet;
	block.listed[found.value] = 0;
	return paid.global;
}

export function appliedEconomy(
	block: Ptr<Block>,
	pets: Span<Pet>,
	seat: int32,
	global: GlobalConfig,
	action: EconomyAction,
	epoch: uint64,
	seed: uint64,
): GlobalConfig {
	const pet = pets[seat];
	if (!pet.alive) { return global; }
	if (action == EconomyAction.ListItem) { return listedBy(block, pets, seat, global, epoch); }
	if (action == EconomyAction.BuyItem) { return boughtBy(block, pets, seat, global); }
	const economy = pet.doEconomy(action, global, seed);
	if (!economy.ok) { return global; }
	pets[seat] = economy.value.pet;
	return economy.value.global;
}

function recorded(block: Ptr<Block>, record: FightRecord): void {
	const head = (block.fightHead as int32) % FIGHTS;
	block.fights[head] = record;
	block.fightHead = ((head + 1) % FIGHTS) as uint8;
}

export function appliedAttack(
	block: Ptr<Block>,
	pets: Span<Pet>,
	seat: int32,
	global: GlobalConfig,
	choice: int32,
	epoch: uint64,
	round: int32,
): GlobalConfig {
	const pet = pets[seat];
	if (!pet.alive || choice == ATTACK_HOLD) { return global; }
	const slot = choice / STAKE_LEVELS;
	const level = (choice % STAKE_LEVELS) as StakeLevel;
	if (slot < 0 || slot >= BLOCK_SLOTS || slot == seat) { return global; }
	const entropy = mixSeeds(block.roundSeed, pet.blockId as uint64);
	const seed = fightSeed(entropy, pet.slot as int32, slot, epoch, round);
	const defender = pets[slot];
	const settled = pet.settleAttack(defender, level, global, epoch, seed);
	if (!settled.ok) { return global; }
	pets[seat] = settled.value.attacker;
	pets[slot] = settled.value.defender;
	recorded(block, settled.value.record);
	const robber = robberOf(block, seat, epoch);
	if (robber.ok && robber.value == slot as BlockSlot) { block.grudges[seat] = noGrudge(); }
	if (settled.value.record.loot > 0) {
		block.grudges[slot] = { robber: pet.slot, pad: [], epoch: epoch };
	}
	return settled.value.global;
}

export function actedBy(
	block: Ptr<Block>,
	policy: Span<uint8>,
	pets: Span<Pet>,
	wilds: Span<Pet>,
	seat: int32,
	persona: PersonaKind,
	global: GlobalConfig,
): Acted {
	const epoch = block.epoch;
	const round = block.round as int32;
	const context: ActContext = {
		epoch: epoch,
		round: round,
		actor: seat as BlockSlot,
		persona: persona,
		robber: robberOf(block, seat, epoch),
		market: marketViewOf(block, pets, seat),
		economySeed: economySeedOf(block.roundSeed, seat, epoch, round),
		trader: seat as uint32,
	};
	let self: int32[46] = [];
	let rivals: Combatant[10] = [];
	const morning = context.surroundingsIn(pets, wilds, global);
	morning.rivalsInto(rivals);
	context.observedSelf(morning, rivals, self);
	const economy = context.economyChoice(policy, morning, self);
	const afterEconomy = appliedEconomy(block, pets, seat, global, economy, epoch, context.economySeed);
	const growing = context.surroundingsIn(pets, wilds, afterEconomy);
	let afterNode = afterEconomy;
	const growable = growing.actorPet().legalNodes(afterEconomy);
	let node = ALLOCATE_HOLD;
	if (growable.bits != 0) {
		context.observedSelfForNodeAndAttack(growing, self);
		const sums = growing.actorPet().tree.summed(growing.actorPet().level as int32);
		node = nodeChoice(policy, growing, growable, self, sums);
		if (node != ALLOCATE_HOLD) {
			const grown = pets[seat].allocateNodeWithSums(node, afterEconomy, sums);
			if (grown.ok) {
				pets[seat] = grown.value.pet;
				afterNode = grown.value.global;
			}
		}
	}
	const armed = context.surroundingsIn(pets, wilds, afterNode);
	context.observedSelfForNodeAndAttack(armed, self);
	const attack = attackChoice(policy, armed, rivals, self);
	const afterAttack = appliedAttack(block, pets, seat, afterNode, attack, epoch, round);
	const choice = ((economy as int32) << 16) | (node << 8) | attack;
	return { global: afterAttack, choice: choice };
}

export function dawned(block: Ptr<Block>, pets: Span<Pet>, records: Span<uint64>, global: GlobalConfig, epoch: uint64): GlobalConfig {
	let settled = global;
	for (let seat = 0; seat < SEATS; seat++) {
		if (records[seat] == 0) { continue; }
		const record = records[seat] as Ptr<PetAccount>;
		const pet = pets[seat];
		if (!pet.alive) {
			const diedAt = record.diedEpoch;
			if (diedAt == 0 || epoch < diedAt + GRACE_EPOCHS) { continue; }
			const heir = pet.heirOf(epoch, settled);
			if (!heir.ok) { continue; }
			pets[seat] = heir.value.pet;
			settled = heir.value.global;
			record.diedEpoch = 0;
			block.grudges[seat] = noGrudge();
			continue;
		}
		const ticked = pet.tickTo(settled, epoch);
		if (!ticked.ok) { continue; }
		pets[seat] = ticked.value.pet;
		settled = ticked.value.global;
	}
	for (let position = 0; position < LISTINGS; position++) {
		if (block.listed[position] == 0) { continue; }
		const listing = block.listings[position];
		if (!listing.expiredAt(epoch)) { continue; }
		const seller = (listing.seller as int32) % BLOCK_SLOTS;
		pets[seller] = pets[seller].boughtBack(listing);
		block.listed[position] = 0;
	}
	return settled;
}

export function revealed(block: Ptr<Block>, pets: Span<Pet>, records: Span<uint64>, global: GlobalConfig): GlobalConfig {
	let settled = global;
	for (let seat = 0; seat < SEATS; seat++) {
		if (records[seat] == 0) { continue; }
		const talent = pets[seat].revealTalent(settled, revealSeedOf(block.roundSeed, seat, block.epoch));
		if (!talent.ok) { continue; }
		pets[seat] = talent.value.pet;
		settled = talent.value.global;
	}
	return settled;
}

function livingMates(pets: Span<Pet>, records: Span<uint64>, seat: int32): int32 {
	let living = 0;
	for (let mate = 0; mate < SEATS; mate++) {
		if (mate != seat && records[mate] != 0 && pets[mate].alive) { living += 1; }
	}
	return living;
}

export function dusked(block: Ptr<Block>, pets: Span<Pet>, records: Span<uint64>, global: GlobalConfig): GlobalConfig {
	let settled = global;
	for (let seat = 0; seat < SEATS; seat++) {
		if (records[seat] == 0) { continue; }
		const record = records[seat] as Ptr<PetAccount>;
		const pet = pets[seat];
		if (pet.alive || record.diedEpoch != 0) { continue; }
		const burial = pet.bury(livingMates(pets, records, seat), settled);
		if (!burial.ok) { continue; }
		pets[seat] = burial.value.pet;
		record.diedEpoch = block.epoch;
		settled = burial.value.global;
		if (burial.value.perMate == 0) { continue; }
		for (let mate = 0; mate < SEATS; mate++) {
			if (mate == seat || records[mate] == 0 || !pets[mate].alive) { continue; }
			pets[mate] = { ...pets[mate], harvest: pets[mate].harvest + burial.value.perMate };
		}
	}
	return settled;
}

function emptySeat(key: Pubkey): boolean {
	return key.equals(Pubkey.zero());
}

function loadedPets(block: Ptr<Block>, first: int32): Result<Ptr<BlockPets>, ProgramError> {
	const heap = msSolAlloc(sizeof BlockPets as uint64) as Ptr<BlockPets>;
	for (let seat = 0; seat < SEATS; seat++) {
		heap.records[seat] = 0;
		heap.pets[seat].alive = false;
		const member = block.members[seat];
		if (emptySeat(member)) { continue; }
		const holder = try mutable<PetAccount>(first + seat);
		if (!(holder as Account).key().equals(member)) {
			return Result.err(hibernalError(HibernalError.NotAMember));
		}
		const record = holder.data();
		heap.pets[seat] = record.pet;
		heap.records[seat] = record as uint64;
	}
	return Result.ok(heap);
}

function storedPets(heap: Ptr<BlockPets>): void {
	for (let seat = 0; seat < SEATS; seat++) {
		if (heap.records[seat] == 0) { continue; }
		const record = heap.records[seat] as Ptr<PetAccount>;
		record.pet = heap.pets[seat];
	}
}

function deadWilds(): Ptr<BlockPets> {
	const heap = msSolAlloc(sizeof BlockPets as uint64) as Ptr<BlockPets>;
	for (let seat = 0; seat < SEATS; seat++) { heap.pets[seat].alive = false; }
	return heap;
}

function callerSeedOf(block: Ptr<Block>): Pubkey {
	let seed = Pubkey.zero();
	const parts: uint64[4] = [block.id as uint64, block.requests, block.epoch, block.round as uint64];
	for (let part = 0; part < 4; part++) {
		for (let position = 0; position < 8; position++) {
			seed.bytes[part * 8 + position] = ((parts[part] >> ((position * 8) as uint64)) & 255) as uint8;
		}
	}
	return seed;
}

function seedRequested(step: StepAccounts, block: Ptr<Block>): Result<uint64, ProgramError> {
	const bump = step.payer.data().bump;
	block.requests = block.requests + 1;
	block.pendingRequest = block.requests;
	block.requestedAt = clock().unixTimestamp;
	block.phase = Phase.Seeding as uint8;
	let callbackAccounts: AccountMeta[12] = [];
	callbackAccounts[0] = AccountMeta.writableKey((step.world as Account).key());
	callbackAccounts[1] = AccountMeta.writableKey((step.block as Account).key());
	for (let seat = 0; seat < SEATS; seat++) {
		const member = block.members[seat];
		callbackAccounts[2 + seat] = emptySeat(member)
			? AccountMeta.readonlyKey(Pubkey.systemProgram())
			: AccountMeta.writableKey(member);
	}
	const argumentBytes = try borshBuffer(8).u64(block.pendingRequest).written();
	const request: RandomnessRequest = {
		payer: step.payer as Account,
		programIdentity: step.programIdentity,
		oracleQueue: step.oracleQueue,
		systemProgram: step.systemProgram,
		slotHashes: step.slotHashes,
	};
	return requestRandomness(
		request,
		callerSeedOf(block),
		seededDiscriminator(),
		callbackAccounts,
		argumentBytes,
		vrfPayerSeeds().withBump(bump),
	);
}

function policyBytes(config: Owned<Config>, policy: Owned<Policy>): Result<Readonly<Ptr<Policy>>, ProgramError> {
	const held = policy.data();
	if (held.sealed == 0) { return Result.err(hibernalError(HibernalError.PolicyUnsealed)); }
	if (!buffersMatchRules()) { return Result.err(hibernalError(HibernalError.Rules)); }
	if (!checkPolicy(held.bytes, config.data().engine).ok) {
		return Result.err(hibernalError(HibernalError.EngineMismatch));
	}
	return Result.ok(held);
}

function dawnStep(step: StepAccounts, block: Ptr<Block>, heap: Ptr<BlockPets>): Result<uint64, ProgramError> {
	const world = step.world.data();
	const epoch = epochAt(world.global.genesisTimestamp, clock().unixTimestamp);
	if (epoch <= block.epoch) { return Result.err(hibernalError(HibernalError.TooEarly)); }
	let global = world.global;
	if (world.epoch < epoch) {
		global = global.settle(epoch);
		world.epoch = epoch;
	}
	global = dawned(block, heap.pets, heap.records, global, epoch);
	world.global = global;
	block.epoch = epoch;
	block.round = 0;
	block.cursor = 0;
	storedPets(heap);
	return seedRequested(step, block);
}

function actingStep(step: StepAccounts, block: Ptr<Block>, heap: Ptr<BlockPets>): Result<uint64, ProgramError> {
	const policy = try policyBytes(step.config, step.policy);
	const seat = block.turns[block.cursor as int32] as int32;
	if (heap.records[seat] != 0 && heap.pets[seat].alive) {
		const world = step.world.data();
		const record = heap.records[seat] as Ptr<PetAccount>;
		const wilds = deadWilds();
		const acted = actedBy(block, policy.bytes, heap.pets, wilds.pets, seat, record.persona as PersonaKind, world.global);
		world.global = acted.global;
		storedPets(heap);
	}
	block.cursor = block.cursor + 1;
	if ((block.cursor as int32) < SEATS) { return Result.ok(seat as uint64); }
	block.round = block.round + 1;
	if ((block.round as int32) < ACTS_PER_EPOCH) { return seedRequested(step, block); }
	block.phase = Phase.Dusk as uint8;
	return Result.ok(seat as uint64);
}

function duskStep(step: StepAccounts, block: Ptr<Block>, heap: Ptr<BlockPets>): Result<uint64, ProgramError> {
	const world = step.world.data();
	world.global = dusked(block, heap.pets, heap.records, world.global);
	storedPets(heap);
	block.phase = Phase.Dawn as uint8;
	return Result.ok(block.epoch);
}

function seedingStep(step: StepAccounts, block: Ptr<Block>): Result<uint64, ProgramError> {
	if (clock().unixTimestamp < block.requestedAt + SEED_RETRY_SECONDS) {
		return Result.err(hibernalError(HibernalError.Pending));
	}
	return seedRequested(step, block);
}

export function step(): Result<uint64, ProgramError> {
	const accountsOfStep = try accounts<StepAccounts>();
	const _payer = try pdaWithBump(accountsOfStep.payer, vrfPayerSeeds(), accountsOfStep.payer.data().bump);
	if (accountsOfStep.world.data().resorting != 0) { return Result.err(hibernalError(HibernalError.Resorting)); }
	const block = accountsOfStep.block.data();
	const heap = try loadedPets(block, STEP_PET_ACCOUNT);
	return match (block.phase as Phase) {
		Phase.Dawn => dawnStep(accountsOfStep, block, heap),
		Phase.Seeding => seedingStep(accountsOfStep, block),
		Phase.Acting => actingStep(accountsOfStep, block, heap),
		Phase.Dusk => duskStep(accountsOfStep, block, heap),
	};
}

export function seeded(): Result<uint64, ProgramError> {
	const callback = try args<SeededArgs>();
	const accountsOfCallback = try accounts<SeededAccounts>();
	const _verified = try verifyVrfCallback(accountsOfCallback.identity);
	if (accountsOfCallback.world.data().resorting != 0) { return Result.err(hibernalError(HibernalError.Resorting)); }
	const block = accountsOfCallback.block.data();
	if ((block.phase as Phase) != Phase.Seeding || callback.request != block.pendingRequest) {
		return Result.err(hibernalError(HibernalError.StaleCallback));
	}
	const heap = try loadedPets(block, SEEDED_PET_ACCOUNT);
	block.roundSeed = seedOf(callback.randomness);
	block.pendingRequest = 0;
	turnOrder(block.roundSeed, block.epoch, block.id, block.round as int32, block.turns);
	block.cursor = 0;
	block.phase = Phase.Acting as uint8;
	if (block.round == 0) {
		const world = accountsOfCallback.world.data();
		world.global = revealed(block, heap.pets, heap.records, world.global);
		storedPets(heap);
	}
	return Result.ok(block.roundSeed);
}
