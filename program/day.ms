@include("runtime/solana/solana.h");
import {
	Account,
	Bytes,
	Clock,
	Mutable,
	Owned,
	ProgramError,
	Pubkey,
	SLOTHASHES_ID,
	SYSTEM_PROGRAM_ID,
	Signer,
	Writable,
	account,
	accountCount,
	clock,
	findProgramAddress,
	instructionDiscriminator,
	mutable,
	pdaWithBump,
	programAddress,
	putU64,
	signed,
} from "std/solana";
import { accounts, args } from "std/solana";
import { RandomnessRequest, VRF_PROGRAM_ID, requestRandomness, verifyVrfCallback } from "std/solana/vrf";
import { MAGIC_PROGRAM_ID } from "std/solana/magicblock";
import {
	ACTS_PER_EPOCH,
	ALLOCATE_HOLD,
	ATTACK_HOLD,
	BLOCK_SLOTS,
	STAKE_LEVELS,
	BlockSlot,
	Combatant,
	Dice,
	EconomyAction,
	FightRecord,
	GlobalConfig,
	GrudgeError,
	HeirError,
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
	luckyMateOf,
	agedOut,
	overtimeBanked,
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
	NO_BLOCK,
	NO_SEAT,
	PetAccount,
	Phase,
	Policy,
	SEATS,
	SeededArgs,
	StepArgs,
	VrfPayer,
	World,
	dayOf,
	hibernalError,
} from "./layout";
import {
	CrankAccounts,
	ScheduledMeta,
	cancelCrank,
	checkedCrankAccounts,
	crankAddress,
	crankSeed,
	createCrank,
	dueSlotFor,
	hydraProgram,
	magicVault,
	spentCrankOf,
} from "./hydra";
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
export const TURN_PET_ACCOUNT: int32 = 14;
export const SWEEP_CRANK_ACCOUNT: int32 = 4;
export const SEED_RETRY_SECONDS: int64 = 30;
export const ACTS_PER_TURN: int32 = 2;
export const SEED_WAIT_SLOTS: uint64 = 150;
export const RESORT_WAIT_SECONDS: int64 = 120;
export const RESUME_GRACE_SLOTS: uint64 = 3000;

export struct RoundStartAccounts {
	payer: Mutable<VrfPayer>;
	config: Owned<Config>;
	world: Owned<World>;
	block: Mutable<Block>;
	programIdentity: Account;
	oracleQueue: Writable;
	slotHashes: Account;
	systemProgram: Account;
	vrfProgram: Account;
	nextCrank: Writable;
	magicVault: Writable;
	magicProgram: Account;
	hydraProgram: Account;
}

export struct TurnAccounts {
	payer: Mutable<VrfPayer>;
	config: Owned<Config>;
	world: Mutable<World>;
	block: Mutable<Block>;
	policy: Owned<Policy>;
	programIdentity: Account;
	oracleQueue: Writable;
	slotHashes: Account;
	systemProgram: Account;
	vrfProgram: Account;
	nextCrank: Writable;
	magicVault: Writable;
	magicProgram: Account;
	hydraProgram: Account;
}

export struct SeededAccounts {
	identity: Account;
	block: Mutable<Block>;
}

export struct StartBlockAccounts {
	authority: Signer;
	config: Owned<Config>;
	world: Owned<World>;
	block: Mutable<Block>;
	payer: Mutable<VrfPayer>;
	crank: Writable;
	magicVault: Writable;
	magicProgram: Account;
	hydraProgram: Account;
}

export struct SweepAccounts {
	payer: Mutable<VrfPayer>;
	magicVault: Writable;
	magicProgram: Account;
	hydraProgram: Account;
}

export enum StepKind {
	RoundStart,
	Turn,
}

export struct BlockPets {
	pets: Pet[10];
	records: uint64[10];
}

struct Acted {
	global: GlobalConfig;
	choice: int32;
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

export function seededDiscriminator(): uint64 {
	const discriminator: uint64 = @comptime { return instructionDiscriminator("Seeded").word(); };
	return discriminator;
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

export function dawned(
	block: Ptr<Block>,
	pets: Span<Pet>,
	records: Span<uint64>,
	global: GlobalConfig,
	epoch: uint64,
): Result<GlobalConfig, ProgramError> {
	let settled = global;
	for (let seat = 0; seat < SEATS; seat++) {
		if (records[seat] == 0) { continue; }
		const record = records[seat] as Ptr<PetAccount>;
		const pet = pets[seat];
		if (!pet.alive) { continue; }
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
		const back = pets[seller].boughtBack(listing, settled);
		if (!back.ok) { return Result.err(hibernalError(HibernalError.TreasuryShort)); }
		pets[seller] = back.value.pet;
		settled = back.value.global;
		block.listed[position] = 0;
	}
	return Result.ok(settled);
}

function heirFailure(error: HeirError): ProgramError {
	const mapped: HibernalError = match (error) {
		HeirError.Alive => HibernalError.Illegal,
		HeirError.TreasuryShort => HibernalError.TreasuryShort,
	};
	return hibernalError(mapped);
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

function livingMateAt(pets: Span<Pet>, records: Span<uint64>, seat: int32, nth: int32): int32 {
	let seen = 0;
	for (let mate = 0; mate < SEATS; mate++) {
		if (mate == seat || records[mate] == 0 || !pets[mate].alive) { continue; }
		if (seen == nth) { return mate; }
		seen += 1;
	}
	return seat;
}

function unseated(pet: Pet): Pet {
	return { ...pet, blockId: NO_BLOCK, slot: NO_SEAT };
}

function leftSeat(world: Ptr<World>, record: Ptr<PetAccount>, dead: Pet, epoch: uint64): Result<Pet, ProgramError> {
	const heir = dead.heirOf(epoch + 1, world.global);
	if (!heir.ok) { return Result.err(heirFailure(heir.error)); }
	world.global = heir.value.global;
	record.diedEpoch = 0;
	return Result.ok(unseated(heir.value.pet));
}

function vacated(block: Ptr<Block>, seat: int32): void {
	block.members[seat] = Pubkey.zero();
	block.filled = block.filled - 1;
	block.grudges[seat] = noGrudge();
	for (let mate = 0; mate < SEATS; mate++) {
		if (block.grudges[mate].epoch != 0 && (block.grudges[mate].robber as int32) == seat) { block.grudges[mate] = noGrudge(); }
	}
}

export function dusked(world: Ptr<World>, block: Ptr<Block>, pets: Span<Pet>, records: Span<uint64>): Result<void, ProgramError> {
	for (let seat = 0; seat < SEATS; seat++) {
		if (records[seat] == 0 || pets[seat].alive) { continue; }
		const record = records[seat] as Ptr<PetAccount>;
		let dead = pets[seat];
		if (record.diedEpoch == 0) {
			const mates = livingMates(pets, records, seat);
			const burial = dead.bury(mates, world.global);
			if (!burial.ok) { return Result.err(hibernalError(HibernalError.Illegal)); }
			dead = burial.value.pet;
			world.global = burial.value.global;
			record.diedEpoch = block.epoch;
			if (burial.value.toMate != 0) {
				const lucky = livingMateAt(pets, records, seat, luckyMateOf(block.roundSeed, seat, block.epoch, mates));
				pets[lucky] = { ...pets[lucky], harvest: pets[lucky].harvest + burial.value.toMate };
			}
		}
		record.pet = try leftSeat(world, record, dead, block.epoch);
		vacated(block, seat);
		world.placed = world.placed - 1;
		records[seat] = 0;
	}
	return Result.ok(null);
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
		if (emptySeat(member) || first + seat >= accountCount()) { continue; }
		const holder = try account(first + seat);
		if (!holder.key().equals(member)) { continue; }
		const proof = try mutable<PetAccount>(first + seat);
		const record = proof.data();
		if (record.pet.blockId != block.id || (record.pet.slot as int32) != seat) {
			block.members[seat] = Pubkey.zero();
			continue;
		}
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

struct SeedSource {
	payer: Mutable<VrfPayer>;
	config: Readonly<Ptr<Config>>;
	block: Account;
	programIdentity: Account;
	oracleQueue: Account;
	slotHashes: Account;
	systemProgram: Account;
}

function seedRequested(source: SeedSource, block: Ptr<Block>, now: Clock): Result<uint64, ProgramError> {
	if (source.oracleQueue.key() != source.config.vrfQueue) { return Result.err(ProgramError.invalidArgument()); }
	const bump = source.payer.data().bump;
	block.requests = block.requests + 1;
	block.pendingRequest = block.requests;
	block.requestedAt = now.unixTimestamp;
	block.phase = Phase.Seeding as uint8;
	let argumentBytes: uint8[8] = [];
	const _written = putU64(argumentBytes, 0, block.pendingRequest);
	const request: RandomnessRequest = {
		payer: source.payer.asAccount(),
		programIdentity: source.programIdentity,
		oracleQueue: source.oracleQueue,
		systemProgram: source.systemProgram,
		slotHashes: source.slotHashes,
	};
	return signed(
		requestRandomness(request, callerSeedOf(block), seededDiscriminator(), source.block, argumentBytes),
		["vrf-payer", [bump]],
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

export function staggerOf(config: Readonly<Ptr<Config>>, blockId: uint32): uint64 {
	if (config.staggerSeconds == 0) { return 0; }
	return ((blockId as uint64) * 2654435761) % config.staggerSeconds;
}

export function roundTarget(config: Readonly<Ptr<Config>>, blockId: uint32, epoch: uint64, round: int32): int64 {
	const roundSeconds = config.secondsPerDay / (ACTS_PER_EPOCH as uint64);
	const start = config.genesisTimestamp + epoch * config.secondsPerDay + (round as uint64) * roundSeconds;
	return (start + staggerOf(config, blockId)) as int64;
}

struct Schedule {
	payer: Mutable<VrfPayer>;
	config: Readonly<Ptr<Config>>;
	configKey: Pubkey;
	worldKey: Pubkey;
	blockKey: Pubkey;
	policyKey: Pubkey;
	cranks: CrankAccounts;
}

function policyKey(config: Readonly<Ptr<Config>>): Result<Pubkey, ProgramError> {
	return programAddress(["policy", [config.policyBump]]);
}

function identityKey(): Result<Pubkey, ProgramError> {
	const found = try findProgramAddress(["identity"]);
	return Result.ok(found.key);
}

function scheduled(schedule: Schedule, block: Ptr<Block>, kind: StepKind, dueSlot: uint64): Result<uint64, ProgramError> {
	const seq = block.crankSeq;
	const expected = try crankAddress(block.id, seq);
	const _checked = try checkedCrankAccounts(schedule.cranks, expected);
	const after = try crankAddress(block.id, seq + 1);
	const identity = try identityKey();
	const bump = schedule.payer.data().bump;
	const seed = crankSeed(block.id, seq);
	block.crankSeq = seq + 1;
	block.dueSlot = dueSlot;
	if (kind == StepKind.RoundStart) {
		let metas: ScheduledMeta[13] = [];
		metas[0] = { key: schedule.cranks.sponsor.key(), writable: true };
		metas[1] = { key: schedule.configKey, writable: false };
		metas[2] = { key: schedule.worldKey, writable: false };
		metas[3] = { key: schedule.blockKey, writable: true };
		metas[4] = { key: identity, writable: false };
		metas[5] = { key: schedule.config.vrfQueue, writable: true };
		metas[6] = { key: SLOTHASHES_ID, writable: false };
		metas[7] = { key: SYSTEM_PROGRAM_ID, writable: false };
		metas[8] = { key: VRF_PROGRAM_ID, writable: false };
		metas[9] = { key: after, writable: true };
		metas[10] = { key: Pubkey.magicVault(), writable: true };
		metas[11] = { key: MAGIC_PROGRAM_ID, writable: false };
		metas[12] = { key: Pubkey.hydraProgram(), writable: false };
		const discriminator: uint64 = @comptime { return instructionDiscriminator("RoundStart").word(); };
		return signed(
			createCrank(schedule.cranks, seed, dueSlot, metas, discriminator, seq),
			["vrf-payer", [bump]],
		);
	}
	let metas: ScheduledMeta[24] = [];
	metas[0] = { key: schedule.cranks.sponsor.key(), writable: true };
	metas[1] = { key: schedule.configKey, writable: false };
	metas[2] = { key: schedule.worldKey, writable: true };
	metas[3] = { key: schedule.blockKey, writable: true };
	metas[4] = { key: schedule.policyKey, writable: false };
	metas[5] = { key: identity, writable: false };
	metas[6] = { key: schedule.config.vrfQueue, writable: true };
	metas[7] = { key: SLOTHASHES_ID, writable: false };
	metas[8] = { key: SYSTEM_PROGRAM_ID, writable: false };
	metas[9] = { key: VRF_PROGRAM_ID, writable: false };
	metas[10] = { key: after, writable: true };
	metas[11] = { key: Pubkey.magicVault(), writable: true };
	metas[12] = { key: MAGIC_PROGRAM_ID, writable: false };
	metas[13] = { key: Pubkey.hydraProgram(), writable: false };
	for (let seat = 0; seat < SEATS; seat++) {
		const member = block.members[seat];
		metas[TURN_PET_ACCOUNT + seat] = emptySeat(member)
			? { key: SYSTEM_PROGRAM_ID, writable: false }
			: { key: member, writable: true };
	}
	const discriminator: uint64 = @comptime { return instructionDiscriminator("Turn").word(); };
	return signed(
		createCrank(schedule.cranks, seed, dueSlot, metas, discriminator, seq),
		["vrf-payer", [bump]],
	);
}

function roundStartScheduled(schedule: Schedule, block: Ptr<Block>, now: Clock): Result<uint64, ProgramError> {
	const target = roundTarget(schedule.config, block.id, block.epoch, block.round as int32);
	return scheduled(schedule, block, StepKind.RoundStart, dueSlotFor(now, target, schedule.config.slotMillis));
}

function freshStep(block: Ptr<Block>, seq: uint64, now: Clock): Result<uint64, ProgramError> {
	if (seq + 1 != block.crankSeq) { return Result.err(hibernalError(HibernalError.StaleStep)); }
	if (now.slot + 2 < block.dueSlot) { return Result.err(hibernalError(HibernalError.TooEarly)); }
	return Result.ok(seq);
}

export function roundStart(): Result<uint64, ProgramError> {
	const x = try accounts<RoundStartAccounts>();
	const a = try args<StepArgs>();
	const _payer = try pdaWithBump(x.payer, ["vrf-payer"], x.payer.data().bump);
	const block = x.block.data();
	const now = clock();
	const _fresh = try freshStep(block, a.seq, now);
	const config = x.config.data();
	const schedule: Schedule = {
		payer: x.payer,
		config: config,
		configKey: x.config.key(),
		worldKey: x.world.key(),
		blockKey: x.block.key(),
		policyKey: try policyKey(config),
		cranks: {
			sponsor: x.payer.asAccount(),
			crank: x.nextCrank.asAccount(),
			magicVault: x.magicVault.asAccount(),
			magicProgram: x.magicProgram,
			hydraProgram: x.hydraProgram,
		},
	};
	if (x.world.data().resorting != 0) {
		const later = now.unixTimestamp + RESORT_WAIT_SECONDS + (staggerOf(config, block.id) as int64);
		return scheduled(schedule, block, StepKind.RoundStart, dueSlotFor(now, later, config.slotMillis));
	}
	const source: SeedSource = {
		payer: x.payer,
		config: config,
		block: x.block.asAccount(),
		programIdentity: x.programIdentity,
		oracleQueue: x.oracleQueue.asAccount(),
		slotHashes: x.slotHashes,
		systemProgram: x.systemProgram,
	};
	const _requested = try seedRequested(source, block, now);
	return scheduled(schedule, block, StepKind.Turn, now.slot + SEED_WAIT_SLOTS);
}

function dawnedBlock(x: TurnAccounts, block: Ptr<Block>, heap: Ptr<BlockPets>): Result<void, ProgramError> {
	const world = x.world.data();
	const epoch = block.epoch;
	let global = world.global;
	if (world.epoch < epoch) {
		global = global.settle(epoch);
		world.epoch = epoch;
	}
	global = try dawned(block, heap.pets, heap.records, global, epoch);
	world.global = revealed(block, heap.pets, heap.records, global);
	block.dawnedEpoch = epoch;
	storedPets(heap);
	return Result.ok(null);
}

function dayEnded(x: TurnAccounts, block: Ptr<Block>, heap: Ptr<BlockPets>): Result<void, ProgramError> {
	const world = x.world.data();
	const _dusked = try dusked(world, block, heap.pets, heap.records);
	storedPets(heap);
	block.epoch = block.epoch + 1;
	block.round = 0;
	const _dawned = try dawnedBlock(x, block, heap);
	block.phase = Phase.Idle as uint8;
	return Result.ok(null);
}

function actingTurn(x: TurnAccounts, block: Ptr<Block>, heap: Ptr<BlockPets>): Result<boolean, ProgramError> {
	const policy = try policyBytes(x.config, x.policy);
	const world = x.world.data();
	for (let act = 0; act < ACTS_PER_TURN && (block.cursor as int32) < SEATS; act++) {
		const seat = block.turns[block.cursor as int32] as int32;
		if (heap.records[seat] != 0 && heap.pets[seat].alive) {
			const record = heap.records[seat] as Ptr<PetAccount>;
			const wilds = deadWilds();
			const acted = actedBy(block, policy.bytes, heap.pets, wilds.pets, seat, record.persona as PersonaKind, world.global);
			world.global = acted.global;
		}
		block.cursor = block.cursor + 1;
	}
	storedPets(heap);
	if ((block.cursor as int32) < SEATS || (block.round as int32) == ACTS_PER_EPOCH - 1) { return Result.ok(false); }
	block.round = block.round + 1;
	block.phase = Phase.Idle as uint8;
	return Result.ok(true);
}

export function turn(): Result<uint64, ProgramError> {
	const x = try accounts<TurnAccounts>();
	const a = try args<StepArgs>();
	const _payer = try pdaWithBump(x.payer, ["vrf-payer"], x.payer.data().bump);
	const block = x.block.data();
	const now = clock();
	const _fresh = try freshStep(block, a.seq, now);
	const config = x.config.data();
	const schedule: Schedule = {
		payer: x.payer,
		config: config,
		configKey: x.config.key(),
		worldKey: x.world.key(),
		blockKey: x.block.key(),
		policyKey: x.policy.key(),
		cranks: {
			sponsor: x.payer.asAccount(),
			crank: x.nextCrank.asAccount(),
			magicVault: x.magicVault.asAccount(),
			magicProgram: x.magicProgram,
			hydraProgram: x.hydraProgram,
		},
	};
	if ((block.phase as Phase) != Phase.Acting) {
		if ((block.phase as Phase) == Phase.Seeding && now.unixTimestamp >= block.requestedAt + SEED_RETRY_SECONDS) {
			const source: SeedSource = {
				payer: x.payer,
				config: config,
				block: x.block.asAccount(),
				programIdentity: x.programIdentity,
				oracleQueue: x.oracleQueue.asAccount(),
				slotHashes: x.slotHashes,
				systemProgram: x.systemProgram,
			};
			const _requested = try seedRequested(source, block, now);
		}
		if ((block.phase as Phase) == Phase.Idle) { return roundStartScheduled(schedule, block, now); }
		return scheduled(schedule, block, StepKind.Turn, now.slot + SEED_WAIT_SLOTS);
	}
	const heap = try loadedPets(block, TURN_PET_ACCOUNT);
	if (block.dawnedEpoch != block.epoch) {
		const _dawned = try dawnedBlock(x, block, heap);
		return scheduled(schedule, block, StepKind.Turn, now.slot + config.turnGapSlots);
	}
	if ((block.cursor as int32) >= SEATS) {
		const _ended = try dayEnded(x, block, heap);
		return roundStartScheduled(schedule, block, now);
	}
	const roundDone = try actingTurn(x, block, heap);
	if (roundDone) { return roundStartScheduled(schedule, block, now); }
	return scheduled(schedule, block, StepKind.Turn, now.slot + config.turnGapSlots);
}

export function seeded(): Result<uint64, ProgramError> {
	const callback = try args<SeededArgs>();
	const accountsOfCallback = try accounts<SeededAccounts>();
	const _verified = try verifyVrfCallback(accountsOfCallback.identity);
	const block = accountsOfCallback.block.data();
	if ((block.phase as Phase) != Phase.Seeding || callback.request != block.pendingRequest) {
		return Result.ok(0);
	}
	block.roundSeed = seedOf(callback.randomness);
	block.pendingRequest = 0;
	turnOrder(block.roundSeed, block.epoch, block.id, block.round as int32, block.turns);
	block.cursor = 0;
	block.phase = Phase.Acting as uint8;
	return Result.ok(block.roundSeed);
}

function startingRound(config: Readonly<Ptr<Config>>, block: Ptr<Block>, now: Clock): void {
	const day = dayOf(config, now.unixTimestamp);
	const roundSeconds = config.secondsPerDay / (ACTS_PER_EPOCH as uint64);
	const dayStart = config.genesisTimestamp + day * config.secondsPerDay;
	const into = (now.unixTimestamp as uint64) > dayStart ? (now.unixTimestamp as uint64) - dayStart : 0;
	block.epoch = day;
	block.round = Math.min(into / roundSeconds, (ACTS_PER_EPOCH - 1) as uint64) as uint8;
	block.phase = Phase.Idle as uint8;
	block.started = 1;
}

export function startBlock(): Result<uint64, ProgramError> {
	const x = try accounts<StartBlockAccounts>();
	const config = x.config.data();
	if (x.authority.key() != config.authority) { return Result.err(hibernalError(HibernalError.NotAuthority)); }
	const _payer = try pdaWithBump(x.payer, ["vrf-payer"], x.payer.data().bump);
	const block = x.block.data();
	const now = clock();
	if (block.started != 0 && now.slot <= block.dueSlot + RESUME_GRACE_SLOTS) {
		return Result.err(hibernalError(HibernalError.ChainAlive));
	}
	if (block.started == 0) { startingRound(config, block, now); }
	const schedule: Schedule = {
		payer: x.payer,
		config: config,
		configKey: x.config.key(),
		worldKey: x.world.key(),
		blockKey: x.block.key(),
		policyKey: try policyKey(config),
		cranks: {
			sponsor: x.payer.asAccount(),
			crank: x.crank.asAccount(),
			magicVault: x.magicVault.asAccount(),
			magicProgram: x.magicProgram,
			hydraProgram: x.hydraProgram,
		},
	};
	if ((block.phase as Phase) != Phase.Idle) { return scheduled(schedule, block, StepKind.Turn, now.slot + 1); }
	const spread = now.unixTimestamp + (staggerOf(config, block.id) as int64);
	const target = Math.max(roundTarget(config, block.id, block.epoch, block.round as int32), spread);
	return scheduled(schedule, block, StepKind.RoundStart, dueSlotFor(now, target, config.slotMillis));
}

export function sweep(): Result<uint64, ProgramError> {
	const x = try accounts<SweepAccounts>();
	const bump = x.payer.data().bump;
	const _payer = try pdaWithBump(x.payer, ["vrf-payer"], bump);
	const sponsor = x.payer.asAccount();
	let cancelled: uint64 = 0;
	for (let index = SWEEP_CRANK_ACCOUNT; index < accountCount(); index++) {
		const crank = try account(index);
		const spent = try spentCrankOf(crank, sponsor.key());
		if (!spent) { continue; }
		const _cancelled = try signed(cancelCrank(sponsor, crank, x.magicVault.asAccount(), x.magicProgram), ["vrf-payer", [bump]]);
		cancelled = cancelled + 1;
	}
	return Result.ok(cancelled);
}
