@include("runtime/solana/solana.h");
import {
	Account,
	Bytes,
	Instruction,
	ProgramError,
	Pubkey,
	Seeds,
	account,
	accountCount,
	signerAccount,
	instructionData,
	programId,
	createProgramAccount,
	clock,
	failWith,
	logU64,
} from "std/solana";
import {
	DelegationAccounts,
	DelegationConfig,
	anyValidator,
	onValidator,
	delegate,
	delegationProgram,
	commitAndUndelegate,
	undelegate,
	isUndelegateCallback,
} from "std/solana/magicblock";
import {
	BLOCK_SLOTS,
	BlockSlot,
	Combatant,
	GlobalConfig,
	Pet,
	StrengthMeasure,
	checkPolicy,
	movedTo,
	strengthOf,
	rivalsInto,
	actorPet,
	legalNodes,
} from "../rules/index";
import { POLICY_BLOB_BYTES, PolicyBlob, buffersMatchPolicy } from "./policyBench";
import {
	ActContext,
	BlockPets,
	actTicked,
	attackChoice,
	buffersMatchRules,
	digestOf,
	observedSelf,
	observedSelfForNodeAndAttack,
	surroundingsIn,
	targetRows,
} from "./actBench";
import { Identity } from "./blockLayout";

extern function msSolAlloc(size: uint64): uint64;

const PET_KIND: uint8 = 2;
const PAGE_KIND: uint8 = 3;
const MIRROR_KIND: uint8 = 4;
const VERSION: uint8 = 1;
const PAGE_HEADER: uint64 = 48;
const MIRROR_PETS: int32 = 50;
const BITMAP_HEADER: uint64 = 32;
const CREATE_LIMIT: uint64 = 10_240;
const POLICY_ACCOUNT: int32 = 0;
const CONTEXT_ACCOUNT: int32 = 1;
const CONFIG_ACCOUNT: int32 = 2;
const WILDS_ACCOUNT: int32 = 3;
const PAGE_ACCOUNT: int32 = 4;
const FIRST_MEMBER_ACCOUNT: int32 = 5;
const MINT_BYTES: uint64 = 82;
const PAID_BYTES: uint64 = 24;
const HBRN_DECIMALS: uint8 = 6;
const CLAIM_CAP_PER_DAY: uint64 = 10_000_000;
const SECONDS_PER_DAY: int64 = 86_400;
const INITIALIZE_MINT: uint8 = 20;
const MINT_TO: uint8 = 7;

struct PetAccount {
	kind: uint8;
	version: uint8;
	pad: uint16;
	ordinal: uint32;
	identity: Identity;
	pet: Pet;
}

struct PageHeader {
	kind: uint8;
	version: uint8;
	pad: uint16;
	id: uint32;
	capacity: uint32;
	filled: uint32;
	rotation: uint64;
	minStrength: uint64;
	maxStrength: uint64;
	formedEpoch: uint64;
}

struct MirrorPage {
	kind: uint8;
	version: uint8;
	pad: uint16;
	id: uint32;
	page: uint32;
	count: uint32;
	pets: Pet[50];
}

struct BitmapHeader {
	count: uint64;
	assigned: uint64;
	rotation: uint64;
	measure: uint64;
}

enum HolderKind {
	Fixture,
	Pet,
	Page,
	Mirror,
	Bitmap,
}

enum ProbeError {
	Layout,
	Policy,
	Unticked,
	WrongHolder,
	NotAMember,
	OutOfRange,
	AlreadyAssigned,
	OutOfOrder,
	Unfinished,
	WrongLedger,
	WrongMint,
	WrongTokenProgram,
	NotTheOwner,
	PetNotOurs,
}

function failed(error: ProbeError): ProgramError {
	return ProgramError.custom(500 + (error as uint32));
}

function tokenProgram(): Pubkey {
	return {
		word0: 0x93a165d7e1f6dd06,
		word1: 0xac79ebce46e1cbd9,
		word2: 0x91375b5fed85b41c,
		word3: 0xa900ff7e85f58c3a,
	};
}

function petSeeds(mint: Pubkey): Seeds {
	return Seeds.empty(2).addText("pet").addPubkey(mint);
}

function pageSeeds(id: uint64): Seeds {
	return Seeds.empty(2).addText("block").addU64(id);
}

function mirrorSeeds(key: uint64): Seeds {
	return Seeds.empty(2).addText("mirror").addU64(key);
}

function fixtureSeeds(id: uint64): Seeds {
	return Seeds.empty(2).addText("fixture").addU64(id);
}

function bitmapSeeds(): Seeds {
	return Seeds.empty(1).addText("assigned");
}

function paidSeeds(mint: Pubkey): Seeds {
	return Seeds.empty(2).addText("paid").addPubkey(mint);
}

function mintSeeds(): Seeds {
	return Seeds.empty(1).addText("mint");
}

function verifiedBump(holder: Account, seeds: Seeds): Result<uint8, ProgramError> {
	const expected = try seeds.findProgramAddress(programId());
	if (!expected.key.equals(holder.key())) { return Result.err(failed(ProbeError.WrongHolder)); }
	return Result.ok(expected.bump);
}

function sized(holder: Account, bytes: uint64): Result<uint64, ProgramError> {
	if (holder.dataLength() != bytes) { return Result.err(failed(ProbeError.Layout)); }
	return Result.ok(holder.data().address);
}

function ours(holder: Account): boolean {
	return holder.isOwnedBy(programId()) || holder.isOwnedBy(Pubkey.delegationProgram());
}

function petIn(holder: Account): Result<Ptr<PetAccount>, ProgramError> {
	if (!holder.isOwnedBy(programId())) { return Result.err(failed(ProbeError.PetNotOurs)); }
	const record = (try sized(holder, sizeof PetAccount as uint64)) as Ptr<PetAccount>;
	if (record.kind != PET_KIND || record.version != VERSION) { return Result.err(failed(ProbeError.Layout)); }
	return Result.ok(record);
}

function pageIn(holder: Account): Result<Ptr<PageHeader>, ProgramError> {
	if (!holder.isOwnedBy(programId()) || holder.dataLength() < PAGE_HEADER) { return Result.err(failed(ProbeError.Layout)); }
	const page = holder.data().address as Ptr<PageHeader>;
	if (page.kind != PAGE_KIND || holder.dataLength() < PAGE_HEADER + (page.capacity as uint64) * 32) {
		return Result.err(failed(ProbeError.Layout));
	}
	return Result.ok(page);
}

function memberAt(page: Ptr<PageHeader>, index: uint64): Ptr<Pubkey> {
	return ((page as uint64) + PAGE_HEADER + index * 32) as Ptr<Pubkey>;
}

function loaded(raw: Ptr<GlobalConfig>): GlobalConfig {
	return {
		genesisTimestamp: raw.genesisTimestamp,
		rewardPerWorkPower: raw.rewardPerWorkPower,
		rewardEpoch: raw.rewardEpoch,
		totalWorkPower: raw.totalWorkPower,
		recycledPending: raw.recycledPending,
		protocolPending: raw.protocolPending,
		burned: raw.burned,
		livingPets: raw.livingPets,
		floorSlots: raw.floorSlots,
	};
}

function stored(raw: Ptr<GlobalConfig>, global: GlobalConfig): void {
	raw.genesisTimestamp = global.genesisTimestamp;
	raw.rewardPerWorkPower = global.rewardPerWorkPower;
	raw.rewardEpoch = global.rewardEpoch;
	raw.totalWorkPower = global.totalWorkPower;
	raw.recycledPending = global.recycledPending;
	raw.protocolPending = global.protocolPending;
	raw.burned = global.burned;
	raw.livingPets = global.livingPets;
	raw.floorSlots = global.floorSlots;
}

function contextAt(): Result<ActContext, ProgramError> {
	const holder = try account(CONTEXT_ACCOUNT);
	const raw = (try sized(holder, sizeof ActContext as uint64)) as Ptr<ActContext>;
	return Result.ok({
		epoch: raw.epoch,
		round: raw.round,
		actor: raw.actor,
		persona: raw.persona,
		robber: raw.robber,
		market: raw.market,
		economySeed: raw.economySeed,
		trader: raw.trader,
	});
}

function policyAt(engine: uint64): Result<Ptr<PolicyBlob>, ProgramError> {
	const holder = try account(POLICY_ACCOUNT);
	const blob = (try sized(holder, POLICY_BLOB_BYTES as uint64)) as Ptr<PolicyBlob>;
	if (!buffersMatchPolicy() || !buffersMatchRules()) { return Result.err(failed(ProbeError.Layout)); }
	if (!checkPolicy(blob.bytes, engine).ok) { return Result.err(failed(ProbeError.Policy)); }
	return Result.ok(blob);
}

function ticked(this context: ActContext, pets: Span<Pet>): boolean {
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		if (pets[slot].alive && pets[slot].lastTickEpoch < context.epoch) { return false; }
	}
	return true;
}

function placed(pet: Pet, blockId: uint32, slot: int32): Pet {
	if (pet.blockId == blockId && (pet.slot as int32) == slot) { return pet; }
	return pet.movedTo(blockId, slot as BlockSlot);
}

function logChoice(economy: uint64, node: uint64, attack: uint64): void {
	logU64(economy);
	logU64(node);
	logU64(attack);
}

function actedDirect(engine: uint64): Result<uint64, ProgramError> {
	const blob = try policyAt(engine);
	const context = try contextAt();
	const config = (try sized(try account(CONFIG_ACCOUNT), sizeof GlobalConfig as uint64)) as Ptr<GlobalConfig>;
	const wilds = (try sized(try account(WILDS_ACCOUNT), sizeof BlockPets as uint64)) as Ptr<BlockPets>;
	const page = try pageIn(try account(PAGE_ACCOUNT));
	if (page.capacity != BLOCK_SLOTS as uint32) { return Result.err(failed(ProbeError.Layout)); }
	const heap = msSolAlloc(sizeof BlockPets as uint64) as Ptr<BlockPets>;
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		const holder = try account(FIRST_MEMBER_ACCOUNT + slot);
		if (!holder.key().equals(memberAt(page, slot as uint64)[0])) { return Result.err(failed(ProbeError.NotAMember)); }
		const record = try petIn(holder);
		heap.pets[slot] = placed(record.pet, page.id, slot);
	}
	if (!context.ticked(heap.pets)) { return Result.err(failed(ProbeError.Unticked)); }
	const outcome = context.actTicked(blob.bytes, heap.pets, wilds.pets, loaded(config));
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		const record = try petIn(try account(FIRST_MEMBER_ACCOUNT + slot));
		record.pet = heap.pets[slot];
	}
	stored(config, outcome.global);
	logChoice(outcome.choice.economy as uint64, outcome.choice.node as uint64, outcome.choice.attack as uint64);
	logU64(digestOf(heap.pets, outcome.global));
	return Result.ok(0);
}

function mirrorAt(index: int32): Result<Ptr<MirrorPage>, ProgramError> {
	const holder = try account(FIRST_MEMBER_ACCOUNT + 1 + index);
	if (!ours(holder)) { return Result.err(failed(ProbeError.Layout)); }
	const page = (try sized(holder, sizeof MirrorPage as uint64)) as Ptr<MirrorPage>;
	if (page.kind != MIRROR_KIND) { return Result.err(failed(ProbeError.Layout)); }
	return Result.ok(page);
}

function mirroredPet(member: uint64): Result<Pet, ProgramError> {
	const page = try mirrorAt((member / (MIRROR_PETS as uint64)) as int32);
	const slot = (member % (MIRROR_PETS as uint64)) as int32;
	if (slot >= (page.count as int32)) { return Result.err(failed(ProbeError.OutOfRange)); }
	return Result.ok(page.pets[slot]);
}

function actedMirrored(data: Bytes): Result<uint64, ProgramError> {
	const engine = try data.readU64(8);
	const actorMember = try data.readU64(16);
	const windows = try data.readU64(24);
	const blob = try policyAt(engine);
	const context = try contextAt();
	const config = (try sized(try account(CONFIG_ACCOUNT), sizeof GlobalConfig as uint64)) as Ptr<GlobalConfig>;
	const wilds = (try sized(try account(WILDS_ACCOUNT), sizeof BlockPets as uint64)) as Ptr<BlockPets>;
	const page = try pageIn(try account(PAGE_ACCOUNT));
	const members = page.capacity as uint64;
	const others = (BLOCK_SLOTS - 1) as uint64;
	if (actorMember >= members || windows == 0 || windows * others > members - 1) { return Result.err(failed(ProbeError.OutOfRange)); }
	const actorHolder = try account(FIRST_MEMBER_ACCOUNT);
	if (!actorHolder.key().equals(memberAt(page, actorMember)[0])) { return Result.err(failed(ProbeError.NotAMember)); }
	const actorRecord = try petIn(actorHolder);
	const actorSlot = context.actor as int32;
	const heap = msSolAlloc(sizeof BlockPets as uint64) as Ptr<BlockPets>;
	let neighbour: uint64 = 1;
	let settled = loaded(config);
	for (let window: uint64 = 0; window < windows; window++) {
		for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
			if (slot == actorSlot) {
				heap.pets[slot] = window == 0 ? actorRecord.pet : heap.pets[slot];
				continue;
			}
			const member = (actorMember + neighbour) % members;
			neighbour += 1;
			heap.pets[slot] = placed(try mirroredPet(member), page.id, slot);
		}
		if (window == 0) {
			if (!context.ticked(heap.pets)) { return Result.err(failed(ProbeError.Unticked)); }
			const outcome = context.actTicked(blob.bytes, heap.pets, wilds.pets, settled);
			settled = outcome.global;
			logChoice(outcome.choice.economy as uint64, outcome.choice.node as uint64, outcome.choice.attack as uint64);
			continue;
		}
		let self: int32[46] = [];
		let rivals: Combatant[10] = [];
		const armed = context.surroundingsIn(heap.pets, wilds.pets, settled);
		armed.rivalsInto(rivals);
		context.observedSelfForNodeAndAttack(armed, self);
		const _rows = targetRows(armed, rivals);
		logU64(attackChoice(blob.bytes, armed, rivals, self) as uint64);
	}
	actorRecord.pet = heap.pets[actorSlot];
	const home = try mirrorAt((actorMember / (MIRROR_PETS as uint64)) as int32);
	home.pets[(actorMember % (MIRROR_PETS as uint64)) as int32] = actorRecord.pet;
	stored(config, settled);
	return Result.ok(0);
}

function bitmapAt(holder: Account): Result<uint64, ProgramError> {
	const _bump = try verifiedBump(holder, bitmapSeeds());
	if (!holder.isOwnedBy(programId())) { return Result.err(failed(ProbeError.Layout)); }
	const address = holder.data().address;
	const header = address as Ptr<BitmapHeader>;
	if (holder.dataLength() != BITMAP_HEADER + (header.count + 7) / 8) { return Result.err(failed(ProbeError.Layout)); }
	return Result.ok(address);
}

function bitAt(bitmap: uint64, ordinal: uint64): Ptr<uint8> {
	return (bitmap + BITMAP_HEADER + ordinal / 8) as Ptr<uint8>;
}

function begun(data: Bytes): Result<uint64, ProgramError> {
	const bitmap = try bitmapAt(try account(0));
	const header = bitmap as Ptr<BitmapHeader>;
	const measure = try data.readU64(8);
	if (measure > (StrengthMeasure.Combat as uint64)) { return Result.err(ProgramError.invalidArgument()); }
	const bits: Bytes = { address: bitmap + BITMAP_HEADER, length: (header.count + 7) / 8 };
	bits.fillWith(0);
	header.assigned = 0;
	header.rotation = header.rotation + 1;
	header.measure = measure;
	return Result.ok(header.rotation);
}

function assigned(data: Bytes): Result<uint64, ProgramError> {
	const bitmap = try bitmapAt(try account(0));
	const header = bitmap as Ptr<BitmapHeader>;
	const pageHolder = try account(1);
	const page = try pageIn(pageHolder);
	const _pageBump = try verifiedBump(pageHolder, pageSeeds(page.id as uint64));
	const previous = try pageIn(try account(2));
	const offset = try data.readU64(8);
	if (page.rotation != header.rotation) {
		if (offset != 0) { return Result.err(failed(ProbeError.OutOfOrder)); }
		if (page.id > 0) {
			const ready = previous.rotation == header.rotation && previous.filled == previous.capacity && previous.id + 1 == page.id;
			if (!ready) { return Result.err(failed(ProbeError.OutOfOrder)); }
		}
		page.rotation = header.rotation;
		page.filled = 0;
		page.minStrength = 0xffffffffffffffff;
		page.maxStrength = 0;
	}
	if (offset != page.filled as uint64) { return Result.err(failed(ProbeError.OutOfOrder)); }
	const measure = header.measure as StrengthMeasure;
	const count = accountCount() - 3;
	if ((offset + (count as uint64)) > (page.capacity as uint64)) { return Result.err(failed(ProbeError.OutOfRange)); }
	for (let index = 0; index < count; index++) {
		const holder = try account(3 + index);
		const record = try petIn(holder);
		const ordinal = record.ordinal as uint64;
		if (ordinal >= header.count) { return Result.err(failed(ProbeError.OutOfRange)); }
		const cell = bitAt(bitmap, ordinal);
		const bit = (1 as uint8) << ((ordinal % 8) as uint8);
		if ((cell[0] & bit) != 0) { return Result.err(failed(ProbeError.AlreadyAssigned)); }
		cell[0] = cell[0] | bit;
		const pet = record.pet;
		const strength = pet.alive ? pet.strengthOf(measure) + 1 : 0;
		if (strength < page.minStrength) { page.minStrength = strength; }
		if (strength > page.maxStrength) { page.maxStrength = strength; }
		memberAt(page, offset + (index as uint64))[0] = holder.key();
	}
	page.filled = page.filled + (count as uint32);
	header.assigned = header.assigned + (count as uint64);
	if (page.filled == page.capacity && page.id > 0 && previous.minStrength < page.maxStrength) {
		return Result.err(failed(ProbeError.OutOfOrder));
	}
	return Result.ok(0);
}

function assignedInPlace(data: Bytes): Result<uint64, ProgramError> {
	const bitmap = try bitmapAt(try account(0));
	const header = bitmap as Ptr<BitmapHeader>;
	const pageHolder = try account(1);
	const page = try pageIn(pageHolder);
	const _pageBump = try verifiedBump(pageHolder, pageSeeds(page.id as uint64));
	const previous = try pageIn(try account(2));
	const offset = try data.readU64(8);
	if (page.rotation != header.rotation) {
		if (offset != 0) { return Result.err(failed(ProbeError.OutOfOrder)); }
		if (page.id > 0) {
			const ready = previous.rotation == header.rotation && previous.filled == previous.capacity && previous.id + 1 == page.id;
			if (!ready) { return Result.err(failed(ProbeError.OutOfOrder)); }
		}
		page.rotation = header.rotation;
		page.filled = 0;
		page.minStrength = 0xffffffffffffffff;
		page.maxStrength = 0;
	}
	if (offset != page.filled as uint64) { return Result.err(failed(ProbeError.OutOfOrder)); }
	const measure = header.measure as StrengthMeasure;
	const count = accountCount() - 3;
	if ((offset + (count as uint64)) > (page.capacity as uint64)) { return Result.err(failed(ProbeError.OutOfRange)); }
	for (let index = 0; index < count; index++) {
		const holder = try account(3 + index);
		const record = try petIn(holder);
		const ordinal = record.ordinal as uint64;
		if (ordinal >= header.count) { return Result.err(failed(ProbeError.OutOfRange)); }
		const cell = bitAt(bitmap, ordinal);
		const bit = (1 as uint8) << ((ordinal % 8) as uint8);
		if ((cell[0] & bit) != 0) { return Result.err(failed(ProbeError.AlreadyAssigned)); }
		cell[0] = cell[0] | bit;
		const seat = (offset as int32) + index;
		const pet = placed(record.pet, page.id, seat);
		record.pet = pet;
		const strength = pet.alive ? pet.strengthOf(measure) + 1 : 0;
		if (strength < page.minStrength) { page.minStrength = strength; }
		if (strength > page.maxStrength) { page.maxStrength = strength; }
		memberAt(page, seat as uint64)[0] = holder.key();
	}
	page.filled = page.filled + (count as uint32);
	header.assigned = header.assigned + (count as uint64);
	if (page.filled == page.capacity && page.id > 0 && previous.minStrength < page.maxStrength) {
		return Result.err(failed(ProbeError.OutOfOrder));
	}
	return Result.ok(0);
}

function finished(): Result<uint64, ProgramError> {
	const bitmap = try bitmapAt(try account(0));
	const header = bitmap as Ptr<BitmapHeader>;
	logU64(header.assigned);
	if (header.assigned != header.count) { return Result.err(failed(ProbeError.Unfinished)); }
	return Result.ok(header.assigned);
}

function layoutLogged(): Result<uint64, ProgramError> {
	logU64(sizeof PetAccount as uint64);
	logU64(PAGE_HEADER);
	logU64(sizeof MirrorPage as uint64);
	logU64(BITMAP_HEADER);
	logU64(sizeof Pet as uint64);
	logU64(sizeof Identity as uint64);
	return Result.ok(0);
}

function gifted(data: Bytes): Result<uint64, ProgramError> {
	const record = try petIn(try account(0));
	const amount = try data.readU64(8);
	if (amount > 0xffffffffffffffff - record.pet.giftOwed) { return Result.err(ProgramError.arithmeticOverflow()); }
	record.pet.giftOwed = record.pet.giftOwed + amount;
	logU64(record.pet.giftOwed);
	return Result.ok(0);
}

function mintCreated(): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const mint = try account(1);
	const tokens = try account(3);
	if (!tokens.key().equals(tokenProgram())) { return Result.err(failed(ProbeError.WrongTokenProgram)); }
	const bump = try verifiedBump(mint, mintSeeds());
	const _created = try createProgramAccount(payer, mint, MINT_BYTES, tokenProgram(), mintSeeds().withBump(bump));
	return Instruction.forProgram(tokenProgram(), 1, 35)
		.addWritable(mint)
		.appendU8(INITIALIZE_MINT)
		.appendU8(HBRN_DECIMALS)
		.appendPubkey(mint.key())
		.appendU8(0)
		.invoke();
}

function ledgerCreated(data: Bytes): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const paid = try account(1);
	const mint = try data.readPubkey(8);
	const bump = try verifiedBump(paid, paidSeeds(mint));
	return createProgramAccount(payer, paid, PAID_BYTES, programId(), paidSeeds(mint).withBump(bump));
}

function claimed(): Result<uint64, ProgramError> {
	const owner = try signerAccount(0);
	const holder = try account(1);
	const paid = try account(2);
	const mint = try account(3);
	const destination = try account(4);
	const tokens = try account(5);
	if (!ours(holder)) { return Result.err(failed(ProbeError.PetNotOurs)); }
	const record = (try sized(holder, sizeof PetAccount as uint64)) as Ptr<PetAccount>;
	const admission = record.identity.admissionMint;
	const _petBump = try verifiedBump(holder, petSeeds(admission));
	const _paidBump = try verifiedBump(paid, paidSeeds(admission));
	if (!paid.isOwnedBy(programId())) { return Result.err(failed(ProbeError.WrongLedger)); }
	const mintBump = try verifiedBump(mint, mintSeeds());
	if (!tokens.key().equals(tokenProgram())) { return Result.err(failed(ProbeError.WrongTokenProgram)); }
	if (!record.identity.owner.equals(owner.key())) { return Result.err(failed(ProbeError.NotTheOwner)); }
	const giftTotal = record.pet.giftOwed;
	const paidTotal = try paid.data().readU64(0);
	const owed = giftTotal > paidTotal ? giftTotal - paidTotal : 0;
	const today = (clock().unixTimestamp / SECONDS_PER_DAY) as uint64;
	const paidDay = try paid.data().readU64(8);
	const storedToday = try paid.data().readU64(16);
	const paidToday = paidDay == today ? storedToday : 0;
	const room = CLAIM_CAP_PER_DAY - paidToday;
	const amount = owed < room ? owed : room;
	logU64(giftTotal);
	logU64(paidTotal);
	logU64(amount);
	if (amount == 0) { return Result.ok(0); }
	const _minted = try Instruction.forProgram(tokenProgram(), 3, 9)
		.addWritable(mint)
		.addWritable(destination)
		.addReadonlySigner(mint)
		.appendU8(MINT_TO)
		.appendU64(amount)
		.invokeSigned(mintSeeds().withBump(mintBump));
	const _total = try paid.data().writeU64(0, paidTotal + amount);
	const _day = try paid.data().writeU64(8, today);
	return paid.data().writeU64(16, paidToday + amount);
}

function kindIn(data: Bytes): Result<HolderKind, ProgramError> {
	const kind = try data.readU64(8);
	if (kind > (HolderKind.Bitmap as uint64)) { return Result.err(ProgramError.invalidArgument()); }
	return Result.ok(kind as HolderKind);
}

function holderSeeds(data: Bytes): Result<Seeds, ProgramError> {
	const kind = try kindIn(data);
	const id = try data.readU64(16);
	const mint = try data.readPubkey(16);
	const seeds: Seeds = match (kind) {
		HolderKind.Fixture => fixtureSeeds(id),
		HolderKind.Pet => petSeeds(mint),
		HolderKind.Page => pageSeeds(id),
		HolderKind.Mirror => mirrorSeeds(id),
		HolderKind.Bitmap => bitmapSeeds(),
	};
	return Result.ok(seeds);
}

function created(data: Bytes): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const holder = try account(1);
	const seeds = try holderSeeds(data);
	const size = try data.readU64(48);
	const bump = try verifiedBump(holder, seeds);
	if (holder.lamports() == 0) {
		const _created = try createProgramAccount(payer, holder, Math.min(size, CREATE_LIMIT), programId(), seeds.withBump(bump));
	}
	return Result.ok(holder.dataLength());
}

function written(data: Bytes): Result<uint64, ProgramError> {
	const _payer = try signerAccount(0);
	const holder = try account(1);
	const seeds = try holderSeeds(data);
	const _bump = try verifiedBump(holder, seeds);
	if (!holder.isOwnedBy(programId())) { return Result.err(ProgramError.illegalOwner()); }
	const offset = try data.readU64(48);
	const chunk = try data.range(56, data.length - 56);
	const target = try holder.data().range(offset, chunk.length);
	return target.copyFrom(chunk);
}

function delegated(data: Bytes): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const systemProgram = try account(1);
	const holder = try account(2);
	const ownerProgram = try account(3);
	const buffer = try account(4);
	const delegationRecord = try account(5);
	const delegationMetadata = try account(6);
	const seeds = try holderSeeds(data);
	const bump = try verifiedBump(holder, seeds);
	let config = DelegationConfig.anyValidator();
	if (accountCount() > 8) {
		const validator = try account(8);
		config = DelegationConfig.onValidator(validator.key());
	}
	const accounts: DelegationAccounts = {
		payer: payer,
		delegated: holder,
		ownerProgram: ownerProgram,
		buffer: buffer,
		delegationRecord: delegationRecord,
		delegationMetadata: delegationMetadata,
		systemProgram: systemProgram,
	};
	return delegate(accounts, seeds, bump, config);
}

function returned(): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const holder = try account(1);
	const magicContext = try account(3);
	return commitAndUndelegate(payer, holder, magicContext);
}

function undelegated(data: Bytes): Result<uint64, ProgramError> {
	const holder = try account(0);
	const buffer = try account(1);
	const payer = try account(2);
	return undelegate(holder, buffer, payer, programId(), data);
}

function closed(data: Bytes): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const holder = try account(1);
	const seeds = try holderSeeds(data);
	const _bump = try verifiedBump(holder, seeds);
	if (!holder.isOwnedBy(programId())) { return Result.err(ProgramError.illegalOwner()); }
	const refund = holder.lamports();
	payer.setLamports(payer.lamports() + refund);
	holder.setLamports(0);
	holder.data().fillWith(0);
	return Result.ok(refund);
}

function strengthsLogged(data: Bytes): Result<uint64, ProgramError> {
	const measure = try data.readU64(8);
	if (measure > (StrengthMeasure.Combat as uint64)) { return Result.err(ProgramError.invalidArgument()); }
	for (let index = 0; index < accountCount(); index++) {
		const record = try petIn(try account(index));
		const pet = record.pet;
		logU64(pet.alive ? pet.strengthOf(measure as StrengthMeasure) + 1 : 0);
	}
	return Result.ok(0);
}

function touched(): Result<uint64, ProgramError> {
	return Result.ok(accountCount() as uint64);
}

function dispatch(): Result<uint64, ProgramError> {
	const data = instructionData();
	if (isUndelegateCallback(data)) { return undelegated(data); }
	const discriminator = try data.readU64(0);
	return match (discriminator) {
		0 => layoutLogged(),
		1 => {
			const engine = try data.readU64(8);
			return actedDirect(engine);
		},
		2 => actedMirrored(data),
		3 => begun(data),
		4 => assigned(data),
		5 => finished(),
		6 => gifted(data),
		7 => mintCreated(),
		8 => ledgerCreated(data),
		9 => claimed(),
		10 => created(data),
		11 => written(data),
		12 => delegated(data),
		13 => returned(),
		14 => closed(data),
		15 => touched(),
		16 => strengthsLogged(data),
		17 => assignedInPlace(data),
		_ => Result.err(ProgramError.invalidInstructionData()),
	};
}

function main(): void {
	const outcome = dispatch();
	if (!outcome.ok) { failWith(outcome.error); }
}

main();
