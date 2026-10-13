import {
	Account,
	Mutable,
	Owned,
	Program,
	DELEGATION_PROGRAM_ID,
	ProgramError,
	Pubkey,
	Signer,
	System,
	Writable,
	WritableSigner,
	accountCount,
	createPda,
	findProgramAddress,
	mutable,
	owned,
	programId,
} from "std/solana";
import { accounts, args } from "std/solana";
import { DelegationAccounts, DelegationConfig, delegate } from "std/solana/magicblock";
import { BlockSlot, Pet, StrengthMeasure, boughtBack, movedTo, shuffleDraw, strengthOf } from "../rules/index";
import {
	Block,
	Config,
	HibernalError,
	LISTINGS,
	NO_BLOCK,
	PetAccount,
	RESORT_BITMAP_BYTES,
	Resort,
	ResortAssignArgs,
	ResortBeginArgs,
	SEATS,
	World,
	hibernalError,
} from "./layout";

const CLEARED_MEMBERS_FROM: int32 = 5;
const PREVIOUS_BLOCK_AT: int32 = 4;
const ASSIGNED_PETS_FROM: int32 = 5;
const NO_STRENGTH: uint64 = 0xffffffffffffffff;

export struct ResortBeginAccounts {
	authority: Signer;
	config: Owned<Config>;
	world: Mutable<World>;
	resort: Mutable<Resort>;
}

export struct ResortClearAccounts {
	authority: Signer;
	config: Owned<Config>;
	world: Mutable<World>;
	resort: Mutable<Resort>;
	block: Mutable<Block>;
}

export struct ResortAssignAccounts {
	authority: Signer;
	config: Owned<Config>;
	resort: Mutable<Resort>;
	block: Mutable<Block>;
	previous: Account;
}

export struct ResortFinishAccounts {
	authority: Signer;
	config: Owned<Config>;
	world: Mutable<World>;
	resort: Owned<Resort>;
}

export struct DelegateResortAccounts {
	authority: WritableSigner;
	config: Owned<Config>;
	resort: Writable;
	ownerProgram: Account;
	buffer: Writable;
	delegationRecord: Writable;
	delegationMetadata: Writable;
	delegationProgram: Account;
	systemProgram: Program<System>;
}

function failed(error: HibernalError): Result<uint64, ProgramError> {
	return Result.err(hibernalError(error));
}

function authorized(config: Owned<Config>, authority: Signer): Result<uint64, ProgramError> {
	if (config.data().authority != authority.key()) { return failed(HibernalError.NotAuthority); }
	return Result.ok(0);
}

function resorting(world: Readonly<Ptr<World>>): Result<uint64, ProgramError> {
	if (world.resorting == 0) { return failed(HibernalError.WrongPhase); }
	return Result.ok(0);
}

function placed(pet: Pet, blockId: uint32, seat: int32): Pet {
	if (pet.blockId == blockId && (pet.slot as int32) == seat) { return pet; }
	return pet.movedTo(blockId, seat as BlockSlot);
}

function strengthIn(pet: Pet, measure: StrengthMeasure, shuffled: uint64): uint64 {
	return pet.alive ? pet.strengthOf(measure, shuffled) + 1 : 0;
}

export function resortBegin(): Result<uint64, ProgramError> {
	const given = try args<ResortBeginArgs>();
	if (given.measure > (StrengthMeasure.Shuffle as uint8)) { return Result.err(ProgramError.invalidArgument()); }
	const x = try accounts<ResortBeginAccounts>();
	const _authorized = try authorized(x.config, x.authority);
	const world = x.world.data();
	const placedPets = world.placed as uint64;
	if (given.count != placedPets) { return failed(HibernalError.OutOfOrder); }
	const resort = x.resort.data();
	resort.rotation = resort.rotation + 1;
	resort.count = placedPets;
	resort.assigned = 0;
	resort.measure = given.measure;
	resort.cleared = 0;
	for (let index = 0; index < RESORT_BITMAP_BYTES; index++) { resort.bitmap[index] = 0; }
	world.resorting = 1;
	world.rotation = resort.rotation;
	return Result.ok(resort.rotation);
}

export function resortClear(): Result<uint64, ProgramError> {
	const x = try accounts<ResortClearAccounts>();
	const _authorized = try authorized(x.config, x.authority);
	const world = x.world.data();
	const _resorting = try resorting(world);
	const resort = x.resort.data();
	const block = x.block.data();
	if (block.rotation == resort.rotation) { return failed(HibernalError.OutOfOrder); }
	if (accountCount() - CLEARED_MEMBERS_FROM != (block.filled as int32)) { return failed(HibernalError.NotAMember); }
	let members: Ptr<PetAccount>[10] = [];
	let given = 0;
	for (let seat = 0; seat < SEATS; seat++) {
		if (block.members[seat].isZero()) { continue; }
		const member = try mutable<PetAccount>(CLEARED_MEMBERS_FROM + given);
		if (member.key() != block.members[seat]) { return failed(HibernalError.NotAMember); }
		members[seat] = member.data();
		given += 1;
	}
	for (let index = 0; index < LISTINGS; index++) {
		if (block.listed[index] == 0) { continue; }
		const listing = block.listings[index];
		const seller = listing.seller as int32;
		if (seller >= SEATS) { return failed(HibernalError.NotAMember); }
		if (block.members[seller].isZero()) {
			block.listed[index] = 0;
			continue;
		}
		const back = members[seller].pet.boughtBack(listing, world.global);
		if (!back.ok) { return failed(HibernalError.TreasuryShort); }
		members[seller].pet = back.value.pet;
		world.global = back.value.global;
		block.listed[index] = 0;
	}
	for (let seat = 0; seat < SEATS; seat++) {
		block.grudges[seat].robber = 0;
		block.grudges[seat].epoch = 0;
		block.members[seat] = Pubkey.zero();
	}
	block.filled = 0;
	block.rotation = resort.rotation;
	block.minStrength = NO_STRENGTH;
	block.maxStrength = 0;
	resort.cleared = resort.cleared + 1;
	return Result.ok(resort.cleared as uint64);
}

export function resortAssign(): Result<uint64, ProgramError> {
	const given = try args<ResortAssignArgs>();
	const x = try accounts<ResortAssignAccounts>();
	const _authorized = try authorized(x.config, x.authority);
	const config = x.config.data();
	const resort = x.resort.data();
	const block = x.block.data();
	let previous: Readonly<Ptr<Block>> = block;
	if (block.id > 0) { previous = (try owned<Block>(PREVIOUS_BLOCK_AT)).data(); }
	if (resort.cleared != config.blocks) { return failed(HibernalError.Unfinished); }
	if (block.rotation != resort.rotation || given.offset != (block.filled as uint64)) {
		return failed(HibernalError.OutOfOrder);
	}
	if (block.id > 0) {
		const ready = previous.id + 1 == block.id && previous.rotation == resort.rotation &&
			(previous.filled as int32) == SEATS;
		if (!ready) { return failed(HibernalError.OutOfOrder); }
	}
	const count = accountCount() - ASSIGNED_PETS_FROM;
	if (count <= 0 || (block.filled as int32) + count > SEATS) { return failed(HibernalError.BlockFull); }
	const measure = resort.measure as StrengthMeasure;
	for (let index = 0; index < count; index++) {
		const holder = try mutable<PetAccount>(ASSIGNED_PETS_FROM + index);
		const record = holder.data();
		if (record.pet.blockId == NO_BLOCK) { return failed(HibernalError.NotPlaced); }
		if (record.ordinal >= config.pets) { return failed(HibernalError.NotAMember); }
		const ordinal = record.ordinal as int32;
		const cell = ordinal / 8;
		const bit = (1 as uint8) << ((ordinal % 8) as uint8);
		if ((resort.bitmap[cell] & bit) != 0) { return failed(HibernalError.AlreadyAssigned); }
		resort.bitmap[cell] = resort.bitmap[cell] | bit;
		const seat = (block.filled as int32) + index;
		const pet = placed(record.pet, block.id, seat);
		record.pet = pet;
		const strength = strengthIn(pet, measure, shuffleDraw(record.ordinal, resort.rotation));
		if (strength < block.minStrength) { block.minStrength = strength; }
		if (strength > block.maxStrength) { block.maxStrength = strength; }
		block.members[seat] = holder.key();
	}
	block.filled = block.filled + (count as uint8);
	resort.assigned = resort.assigned + (count as uint64);
	if (block.id > 0 && previous.minStrength < block.maxStrength) { return failed(HibernalError.OutOfOrder); }
	return Result.ok(block.filled as uint64);
}

export function resortFinish(): Result<uint64, ProgramError> {
	const x = try accounts<ResortFinishAccounts>();
	const _authorized = try authorized(x.config, x.authority);
	const world = x.world.data();
	const _resorting = try resorting(world);
	const resort = x.resort.data();
	if (resort.assigned != resort.count) { return failed(HibernalError.Unfinished); }
	world.resorting = 0;
	world.resortedEpoch = world.epoch;
	return Result.ok(resort.assigned);
}

export function delegateResort(): Result<uint64, ProgramError> {
	const x = try accounts<DelegateResortAccounts>();
	if (x.config.data().authority != x.authority.key()) { return failed(HibernalError.NotAuthority); }
	if (x.ownerProgram.key() != programId()) { return Result.err(ProgramError.incorrectProgramId()); }
	if (x.delegationProgram.key() != DELEGATION_PROGRAM_ID) { return Result.err(ProgramError.incorrectProgramId()); }
	const holder = x.resort.asAccount();
	let bump: uint8 = 0;
	if (holder.lamports() == 0) {
		const made = try createPda<Resort>(x.authority, x.resort, ["resort"]);
		made.account.data().bump = made.bump;
		bump = made.bump;
	} else {
		const found = try findProgramAddress(["resort"]);
		if (found.key != holder.key()) { return Result.err(ProgramError.constraintSeeds()); }
		bump = found.bump;
	}
	const validator = x.config.data().validator;
	const config = validator.isZero() ? DelegationConfig.anyValidator() : DelegationConfig.onValidator(validator);
	const delegation: DelegationAccounts = {
		payer: x.authority.asAccount(),
		delegated: holder,
		ownerProgram: x.ownerProgram,
		buffer: x.buffer.asAccount(),
		delegationRecord: x.delegationRecord.asAccount(),
		delegationMetadata: x.delegationMetadata.asAccount(),
		systemProgram: x.systemProgram.asAccount(),
	};
	return delegate(delegation, ["resort"], bump, config);
}
