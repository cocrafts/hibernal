@include("runtime/solana/solana.h");
import {
	Account,
	Bytes,
	ProgramError,
	Pubkey,
	Seeds,
	account,
	accountCount,
	signerAccount,
	instructionData,
	programId,
	createProgramAccount,
	failWith,
	logU64,
} from "std/solana";
import {
	DelegationAccounts,
	DelegationConfig,
	anyValidator,
	onValidator,
	delegate,
	commitAndUndelegate,
	undelegate,
	isUndelegateCallback,
} from "std/solana/magicblock";
import { BLOCK_SLOTS, BlockSlot, StrengthMeasure, movedTo, strengthOf } from "../rules/index";
import { BLOCK_KIND, BLOCK_VERSION, Block } from "./blockLayout";

const LADDER_HEADER: uint64 = 32;
const CREATE_LIMIT: uint64 = 10_240;

enum HolderKind {
	Block,
	Index,
	Ladder,
}

struct LadderHeader {
	count: uint64;
	measure: uint64;
	sortedArea: uint64;
	placed: uint64;
}

struct Entry {
	strength: uint64;
	position: uint64;
	mint: Pubkey;
}

struct PetIndex {
	blockId: uint64;
	slot: uint64;
	bump: uint64;
}

enum ProbeError {
	Layout,
	WrongBlock,
	WrongLadder,
	OutOfRange,
	AlreadyPlaced,
	NotItsRank,
	Unfinished,
	WrongIndex,
}

function failed(error: ProbeError): ProgramError {
	return ProgramError.custom(400 + (error as uint32));
}

function blockSeeds(id: uint64): Seeds {
	return Seeds.empty(2).addText("block").addU64(id);
}

function ladderSeeds(): Seeds {
	return Seeds.empty(1).addText("ladder");
}

function ladderBytes(count: uint64): uint64 {
	return LADDER_HEADER + 2 * count * (sizeof Entry as uint64) + (count + 7) / 8;
}

function blockAt(holder: Account, id: uint64): Result<Ptr<Block>, ProgramError> {
	const expected = try blockSeeds(id).findProgramAddress(programId());
	if (!expected.key.equals(holder.key())) { return Result.err(failed(ProbeError.WrongBlock)); }
	if (holder.dataLength() != sizeof Block as uint64) { return Result.err(failed(ProbeError.Layout)); }
	const block = holder.data().address as Ptr<Block>;
	if (block.kind != BLOCK_KIND || block.version != BLOCK_VERSION || (block.id as uint64) != id) {
		return Result.err(failed(ProbeError.Layout));
	}
	return Result.ok(block);
}

function ladderAt(holder: Account): Result<uint64, ProgramError> {
	const expected = try ladderSeeds().findProgramAddress(programId());
	if (!expected.key.equals(holder.key()) || !holder.isOwnedBy(programId())) {
		return Result.err(failed(ProbeError.WrongLadder));
	}
	const address = holder.data().address;
	const header = address as Ptr<LadderHeader>;
	if (holder.dataLength() != ladderBytes(header.count)) { return Result.err(failed(ProbeError.Layout)); }
	return Result.ok(address);
}

function entryAt(ladder: uint64, area: uint64, index: uint64): Ptr<Entry> {
	const header = ladder as Ptr<LadderHeader>;
	const offset = LADDER_HEADER + (area * header.count + index) * (sizeof Entry as uint64);
	return (ladder + offset) as Ptr<Entry>;
}

function placedByte(ladder: uint64, index: uint64): Ptr<uint8> {
	const header = ladder as Ptr<LadderHeader>;
	return (ladder + LADDER_HEADER + 2 * header.count * (sizeof Entry as uint64) + index / 8) as Ptr<uint8>;
}

function isPlaced(ladder: uint64, index: uint64): boolean {
	return (placedByte(ladder, index)[0] & ((1 as uint8) << ((index % 8) as uint8))) != 0;
}

function place(ladder: uint64, index: uint64): void {
	const cell = placedByte(ladder, index);
	cell[0] = cell[0] | ((1 as uint8) << ((index % 8) as uint8));
	const header = ladder as Ptr<LadderHeader>;
	header.placed = header.placed + 1;
}

function ranksBefore(this entry: Entry, other: Entry): boolean {
	if (entry.strength != other.strength) { return entry.strength > other.strength; }
	return entry.position < other.position;
}

function layoutLogged(): Result<uint64, ProgramError> {
	logU64(sizeof Block as uint64);
	logU64(sizeof Entry as uint64);
	logU64(LADDER_HEADER);
	return Result.ok(0);
}

function snapshot(data: Bytes): Result<uint64, ProgramError> {
	const ladder = try ladderAt(try account(0));
	const id = try data.readU64(8);
	const block = try blockAt(try account(1), id);
	const header = ladder as Ptr<LadderHeader>;
	const measure = header.measure as StrengthMeasure;
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		const position = id * (BLOCK_SLOTS as uint64) + (slot as uint64);
		if (position >= header.count) { return Result.err(failed(ProbeError.OutOfRange)); }
		const pet = block.pets[slot];
		const entry = entryAt(ladder, 0, position);
		entry.strength = pet.alive ? pet.strengthOf(measure) + 1 : 0;
		entry.position = position;
		entry.mint = block.identities[slot].admissionMint;
	}
	return Result.ok(0);
}

function runsSorted(data: Bytes): Result<uint64, ProgramError> {
	const ladder = try ladderAt(try account(0));
	const start = try data.readU64(8);
	const count = try data.readU64(16);
	const run = try data.readU64(24);
	const header = ladder as Ptr<LadderHeader>;
	if (run == 0 || start + count > header.count) { return Result.err(failed(ProbeError.OutOfRange)); }
	let from = start;
	while (from < start + count) {
		const end = Math.min(from + run, start + count);
		for (let index = from + 1; index < end; index++) {
			const moving = entryAt(ladder, 0, index)[0];
			let hole = index;
			while (hole > from && moving.ranksBefore(entryAt(ladder, 0, hole - 1)[0])) {
				entryAt(ladder, 0, hole)[0] = entryAt(ladder, 0, hole - 1)[0];
				hole -= 1;
			}
			entryAt(ladder, 0, hole)[0] = moving;
		}
		from = end;
	}
	header.sortedArea = 0;
	return Result.ok(0);
}

function merged(data: Bytes): Result<uint64, ProgramError> {
	const ladder = try ladderAt(try account(0));
	const width = try data.readU64(8);
	const start = try data.readU64(16);
	const count = try data.readU64(24);
	const source = try data.readU64(32);
	const header = ladder as Ptr<LadderHeader>;
	if (width == 0 || source > 1 || start % (2 * width) != 0 || start + count > header.count) {
		return Result.err(failed(ProbeError.OutOfRange));
	}
	const target = 1 - source;
	let left = start;
	while (left < start + count) {
		const middle = Math.min(left + width, start + count);
		const end = Math.min(left + 2 * width, start + count);
		let from = left;
		let other = middle;
		let out = left;
		while (out < end) {
			const takeLeft = other >= end ||
				(from < middle && entryAt(ladder, source, from)[0].ranksBefore(entryAt(ladder, source, other)[0]));
			if (takeLeft) {
				entryAt(ladder, target, out)[0] = entryAt(ladder, source, from)[0];
				from += 1;
			} else {
				entryAt(ladder, target, out)[0] = entryAt(ladder, source, other)[0];
				other += 1;
			}
			out += 1;
		}
		left = end;
	}
	header.sortedArea = target;
	return Result.ok(0);
}

function swapped(block: Ptr<Block>, slot: int32, other: Ptr<Block>, otherSlot: int32): void {
	const pet = block.pets[slot];
	const identity = block.identities[slot];
	const grace = block.graces[slot];
	block.pets[slot] = other.pets[otherSlot].movedTo(block.id, slot as BlockSlot);
	block.identities[slot] = other.identities[otherSlot];
	block.graces[slot] = other.graces[otherSlot];
	other.pets[otherSlot] = pet.movedTo(other.id, otherSlot as BlockSlot);
	other.identities[otherSlot] = identity;
	other.graces[otherSlot] = grace;
}

function indexed(holder: Account, mint: Pubkey, position: uint64): Result<uint64, ProgramError> {
	if (holder.dataLength() != sizeof PetIndex as uint64 || !holder.isOwnedBy(programId())) {
		return Result.err(failed(ProbeError.WrongIndex));
	}
	const index = holder.data().address as Ptr<PetIndex>;
	const expected = try Seeds.empty(2).addText("pet").addPubkey(mint).withBump(index.bump as uint8).createProgramAddress(programId());
	if (!expected.equals(holder.key())) { return Result.err(failed(ProbeError.WrongIndex)); }
	index.blockId = position / (BLOCK_SLOTS as uint64);
	index.slot = position % (BLOCK_SLOTS as uint64);
	return Result.ok(0);
}

function recounted(block: Ptr<Block>): void {
	let living = 0;
	for (let slot = 0; slot < BLOCK_SLOTS; slot++) {
		if (block.pets[slot].alive) { living += 1; }
	}
	block.livingCount = living as uint8;
}

function swap(data: Bytes): Result<uint64, ProgramError> {
	const ladder = try ladderAt(try account(0));
	const from = try data.readU64(8);
	const to = try data.readU64(16);
	const header = ladder as Ptr<LadderHeader>;
	if (from >= header.count || to >= header.count || from == to) { return Result.err(failed(ProbeError.OutOfRange)); }
	if (isPlaced(ladder, to)) { return Result.err(failed(ProbeError.AlreadyPlaced)); }
	const slots = BLOCK_SLOTS as uint64;
	const fromHolder = try account(1);
	const toHolder = try account(2);
	const fromBlock = try blockAt(fromHolder, from / slots);
	const toBlock = try blockAt(toHolder, to / slots);
	const fromSlot = (from % slots) as int32;
	const toSlot = (to % slots) as int32;
	const area = header.sortedArea;
	if (!fromBlock.identities[fromSlot].admissionMint.equals(entryAt(ladder, area, to).mint)) {
		return Result.err(failed(ProbeError.NotItsRank));
	}
	swapped(fromBlock, fromSlot, toBlock, toSlot);
	const _arrived = try indexed(try account(3), toBlock.identities[toSlot].admissionMint, to);
	const _left = try indexed(try account(4), fromBlock.identities[fromSlot].admissionMint, from);
	place(ladder, to);
	if (!isPlaced(ladder, from) && fromBlock.identities[fromSlot].admissionMint.equals(entryAt(ladder, area, from).mint)) {
		place(ladder, from);
	}
	recounted(fromBlock);
	recounted(toBlock);
	return Result.ok(0);
}

function confirmed(data: Bytes): Result<uint64, ProgramError> {
	const ladder = try ladderAt(try account(0));
	const position = try data.readU64(8);
	const header = ladder as Ptr<LadderHeader>;
	if (position >= header.count) { return Result.err(failed(ProbeError.OutOfRange)); }
	if (isPlaced(ladder, position)) { return Result.err(failed(ProbeError.AlreadyPlaced)); }
	const slots = BLOCK_SLOTS as uint64;
	const block = try blockAt(try account(1), position / slots);
	if (!block.identities[(position % slots) as int32].admissionMint.equals(entryAt(ladder, header.sortedArea, position).mint)) {
		return Result.err(failed(ProbeError.NotItsRank));
	}
	place(ladder, position);
	return Result.ok(0);
}

function finished(): Result<uint64, ProgramError> {
	const ladder = try ladderAt(try account(0));
	const header = ladder as Ptr<LadderHeader>;
	logU64(header.placed);
	if (header.placed != header.count) { return Result.err(failed(ProbeError.Unfinished)); }
	return Result.ok(header.placed);
}

function kindIn(data: Bytes): Result<HolderKind, ProgramError> {
	const kind = try data.readU64(8);
	if (kind > (HolderKind.Ladder as uint64)) { return Result.err(ProgramError.invalidArgument()); }
	return Result.ok(kind as HolderKind);
}

function holderSeeds(data: Bytes): Result<Seeds, ProgramError> {
	const kind = try kindIn(data);
	const id = try data.readU64(16);
	const mint = try data.readPubkey(16);
	const seeds: Seeds = match (kind) {
		HolderKind.Block => blockSeeds(id),
		HolderKind.Index => Seeds.empty(2).addText("pet").addPubkey(mint),
		HolderKind.Ladder => ladderSeeds(),
	};
	return Result.ok(seeds);
}

function verifiedBump(holder: Account, seeds: Seeds): Result<uint8, ProgramError> {
	const expected = try seeds.findProgramAddress(programId());
	if (!expected.key.equals(holder.key())) { return Result.err(ProgramError.invalidSeeds()); }
	return Result.ok(expected.bump);
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

function grown(data: Bytes): Result<uint64, ProgramError> {
	const _payer = try signerAccount(0);
	const holder = try account(1);
	const seeds = try holderSeeds(data);
	const size = try data.readU64(48);
	const _bump = try verifiedBump(holder, seeds);
	if (!holder.isOwnedBy(programId())) { return Result.err(ProgramError.illegalOwner()); }
	return holder.resize(Math.min(size, holder.dataLength() + CREATE_LIMIT));
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

function dispatch(): Result<uint64, ProgramError> {
	const data = instructionData();
	if (isUndelegateCallback(data)) { return undelegated(data); }
	const discriminator = try data.readU64(0);
	return match (discriminator) {
		0 => layoutLogged(),
		1 => snapshot(data),
		2 => runsSorted(data),
		3 => merged(data),
		4 => swap(data),
		5 => finished(),
		6 => confirmed(data),
		7 => created(data),
		8 => written(data),
		9 => grown(data),
		10 => delegated(data),
		11 => returned(),
		12 => closed(data),
		_ => Result.err(ProgramError.invalidInstructionData()),
	};
}

function main(): void {
	const outcome = dispatch();
	if (!outcome.ok) { failWith(outcome.error); }
}

main();
