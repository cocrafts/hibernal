import {
	Account,
	External,
	Mutable,
	Owned,
	Program,
	ProgramError,
	DELEGATION_PROGRAM_ID,
	Pubkey,
	System,
	Writable,
	WritableSigner,
	clock,
	createPda,
	instructionData,
	leBytes,
	pdaWithBump,
	programAddress,
	programId,
	unchecked,
} from "std/solana";
import { accounts } from "std/solana/macro";
import {
	DelegationAccounts,
	DelegationConfig,
	delegate,
	isUndelegateCallback,
	onValidator,
	undelegate,
} from "std/solana/magicblock";
import {
	Mint,
	TokenAccount,
	expectTokenMint,
	expectTokenOwner,
	groupMemberPointer,
	tokenGroupMember,
} from "std/solana/token";
import { BlockSlot, GlobalConfig, Pet, Region, born, genesis } from "../rules/index";
import {
	Block,
	Config,
	HibernalError,
	MAX_PETS,
	NO_BLOCK,
	NO_SEAT,
	Paid,
	Phase,
	PetAccount,
	SEATS,
	World,
	dayOf,
	hibernalError,
} from "./layout";

const REGIONS: uint8 = 3;
const PERSONAS: uint8 = 3;
const APPEARANCE_OFFSET_BASIS: uint64 = 2166136261;
const APPEARANCE_PRIME: uint64 = 16777619;

export struct ClaimAccounts {
	owner: WritableSigner;
	config: Mutable<Config>;
	mint: External<Mint>;
	held: External<TokenAccount>;
	pet: Writable;
	paid: Writable;
	systemProgram: Program<System>;
}

export struct DelegatePetAccounts {
	payer: WritableSigner;
	config: Owned<Config>;
	delegated: Mutable<PetAccount>;
	ownerProgram: Account;
	buffer: Writable;
	delegationRecord: Writable;
	delegationMetadata: Writable;
	delegationProgram: Account;
	systemProgram: Program<System>;
}

export struct DelegateBlockAccounts {
	payer: WritableSigner;
	config: Owned<Config>;
	delegated: Mutable<Block>;
	ownerProgram: Account;
	buffer: Writable;
	delegationRecord: Writable;
	delegationMetadata: Writable;
	delegationProgram: Account;
	systemProgram: Program<System>;
}

export struct DelegateWorldAccounts {
	payer: WritableSigner;
	config: Owned<Config>;
	delegated: Mutable<World>;
	ownerProgram: Account;
	buffer: Writable;
	delegationRecord: Writable;
	delegationMetadata: Writable;
	delegationProgram: Account;
	systemProgram: Program<System>;
}

export struct UndelegationAccounts {
	delegated: Writable;
	buffer: Account;
	payer: Writable;
	systemProgram: Program<System>;
}

export struct PlaceAccounts {
	authority: WritableSigner;
	config: Owned<Config>;
	world: Mutable<World>;
	block: Mutable<Block>;
	pet: Mutable<PetAccount>;
}

export function appearanceOf(mint: Pubkey): uint32 {
	let hash = APPEARANCE_OFFSET_BASIS;
	for (let index = 0; index < 32; index++) {
		hash = ((hash ^ (mint.bytes[index] as uint64)) * APPEARANCE_PRIME) & 0xffffffff;
	}
	return hash as uint32;
}

function configIn(config: Owned<Config>): Result<Readonly<Ptr<Config>>, ProgramError> {
	const stored = config.data();
	const derived = programAddress(["config", [stored.bump]]);
	if (!derived.ok || derived.value != config.key()) { return Result.err(ProgramError.constraintSeeds()); }
	return Result.ok(stored);
}

function admitted(mint: External<Mint>, group: Pubkey): Result<uint64, ProgramError> {
	const mintAccount = mint.asAccount();
	const pointer = mintAccount.groupMemberPointer();
	const member = mintAccount.tokenGroupMember();
	if (!pointer.ok || !member.ok) { return Result.err(hibernalError(HibernalError.NotAdmitted)); }
	const memberAddress = pointer.value.memberAddress;
	if (memberAddress == null) { return Result.err(hibernalError(HibernalError.NotAdmitted)); }
	if (memberAddress != mintAccount.key() || member.value.mint != mintAccount.key() || member.value.group != group) {
		return Result.err(hibernalError(HibernalError.NotAdmitted));
	}
	return Result.ok(member.value.memberNumber);
}

export function claim(): Result<uint64, ProgramError> {
	const x = try accounts<ClaimAccounts>();
	const config = x.config.data();
	const _config = try pdaWithBump(x.config, ["config"], config.bump);
	const mintKey = x.mint.key();
	const _member = try admitted(x.mint, config.admissionGroup);
	const held = try x.held.read();
	const _heldMint = try expectTokenMint(held, mintKey);
	const _heldBy = try expectTokenOwner(held, x.owner.key());
	if (held.amount != 1) { return Result.err(hibernalError(HibernalError.NotAdmitted)); }
	if (config.pets >= (MAX_PETS as uint32)) { return Result.err(hibernalError(HibernalError.PetCap)); }
	const madePet = try createPda<PetAccount>(x.owner, x.pet, ["pet", mintKey]);
	const madePaid = try createPda<Paid>(x.owner, x.paid, ["paid", mintKey]);
	const epoch = dayOf(config, clock().unixTimestamp);
	const region = (mintKey.bytes[0] % REGIONS) as int32;
	const hatched = Pet.born(NO_BLOCK, BlockSlot.First, region as Region, epoch, GlobalConfig.genesis(config.genesisTimestamp));
	const record = madePet.account.data();
	record.owner = x.owner.key();
	record.mint = mintKey;
	record.ordinal = config.pets;
	record.persona = mintKey.bytes[1] % PERSONAS;
	record.appearance = appearanceOf(mintKey);
	record.bump = madePet.bump;
	record.claimedEpoch = epoch;
	record.pet = { ...hatched.pet, blockId: NO_BLOCK, slot: NO_SEAT, alive: false };
	const paid = madePaid.account.data();
	paid.mint = mintKey;
	paid.bump = madePaid.bump;
	config.pets = config.pets + 1;
	return Result.ok(record.ordinal as uint64);
}


export function delegationPrograms(request: DelegationAccounts, delegationProgram: Account): Result<uint64, ProgramError> {
	if (request.ownerProgram.key() != programId()) { return Result.err(ProgramError.invalidProgramId()); }
	if (delegationProgram.key() != DELEGATION_PROGRAM_ID) { return Result.err(ProgramError.invalidProgramId()); }
	return Result.ok(0);
}

export function delegatedAt(request: DelegationAccounts, derived: Result<Pubkey, ProgramError>): Result<uint64, ProgramError> {
	if (!derived.ok || derived.value != request.delegated.key()) { return Result.err(ProgramError.constraintSeeds()); }
	return Result.ok(0);
}

export function validatorOf(config: Readonly<Ptr<Config>>): Result<DelegationConfig, ProgramError> {
	if (config.validator.isZero()) { return Result.err(ProgramError.invalidArgument()); }
	return Result.ok(DelegationConfig.onValidator(config.validator));
}

export function delegatePet(): Result<uint64, ProgramError> {
	const x = try accounts<DelegatePetAccounts>();
	const config = try configIn(x.config);
	const record = x.delegated.data();
	if (x.payer.key() != record.owner && x.payer.key() != config.authority) {
		return Result.err(hibernalError(HibernalError.NotTheOwner));
	}
	const request: DelegationAccounts = {
		payer: x.payer.asAccount(),
		delegated: x.delegated.asAccount(),
		ownerProgram: x.ownerProgram,
		buffer: x.buffer.asAccount(),
		delegationRecord: x.delegationRecord.asAccount(),
		delegationMetadata: x.delegationMetadata.asAccount(),
		systemProgram: x.systemProgram.asAccount(),
	};
	const _programs = try delegationPrograms(request, x.delegationProgram);
	const _address = try delegatedAt(request, programAddress(["pet", record.mint, [record.bump]]));
	return delegate(request, ["pet", record.mint], record.bump, try validatorOf(config));
}

export function delegateBlock(): Result<uint64, ProgramError> {
	const x = try accounts<DelegateBlockAccounts>();
	const config = try configIn(x.config);
	if (x.payer.key() != config.authority) { return Result.err(hibernalError(HibernalError.NotAuthority)); }
	const block = x.delegated.data();
	const request: DelegationAccounts = {
		payer: x.payer.asAccount(),
		delegated: x.delegated.asAccount(),
		ownerProgram: x.ownerProgram,
		buffer: x.buffer.asAccount(),
		delegationRecord: x.delegationRecord.asAccount(),
		delegationMetadata: x.delegationMetadata.asAccount(),
		systemProgram: x.systemProgram.asAccount(),
	};
	const _programs = try delegationPrograms(request, x.delegationProgram);
	const id = leBytes(block.id as uint64);
	const _address = try delegatedAt(request, programAddress(["block", id, [block.bump]]));
	return delegate(request, ["block", id], block.bump, try validatorOf(config));
}

export function delegateWorld(): Result<uint64, ProgramError> {
	const x = try accounts<DelegateWorldAccounts>();
	const config = try configIn(x.config);
	if (x.payer.key() != config.authority) { return Result.err(hibernalError(HibernalError.NotAuthority)); }
	const world = x.delegated.data();
	const request: DelegationAccounts = {
		payer: x.payer.asAccount(),
		delegated: x.delegated.asAccount(),
		ownerProgram: x.ownerProgram,
		buffer: x.buffer.asAccount(),
		delegationRecord: x.delegationRecord.asAccount(),
		delegationMetadata: x.delegationMetadata.asAccount(),
		systemProgram: x.systemProgram.asAccount(),
	};
	const _programs = try delegationPrograms(request, x.delegationProgram);
	const _address = try delegatedAt(request, programAddress(["world", [world.bump]]));
	return delegate(request, ["world"], world.bump, try validatorOf(config));
}

export function processUndelegation(): Result<uint64, ProgramError> {
	const data = instructionData();
	if (!isUndelegateCallback(data)) { return Result.err(ProgramError.instructionFallbackNotFound()); }
	const x = try accounts<UndelegationAccounts>();
	return undelegate(x.delegated.asAccount(), x.buffer, x.payer.asAccount(), programId(), data);
}

export function place(): Result<uint64, ProgramError> {
	const x = try accounts<PlaceAccounts>();
	const config = try configIn(x.config);
	if (x.authority.key() != config.authority) { return Result.err(hibernalError(HibernalError.NotAuthority)); }
	const world = x.world.data();
	const _world = try pdaWithBump(x.world, ["world"], world.bump);
	const block = x.block.data();
	const _block = try pdaWithBump(x.block, ["block", leBytes(block.id as uint64)], block.bump);
	const record = x.pet.data();
	const _pet = try pdaWithBump(x.pet, ["pet", record.mint], record.bump);
	if (record.pet.blockId != NO_BLOCK) { return Result.err(hibernalError(HibernalError.AlreadyPlaced)); }
	if (world.resorting != 0) { return Result.err(hibernalError(HibernalError.Resorting)); }
	let seat = -1;
	for (let index = 0; index < SEATS; index++) {
		if (block.members[index].isZero()) {
			seat = index;
			break;
		}
	}
	if (seat < 0) { return Result.err(hibernalError(HibernalError.BlockFull)); }
	if ((block.phase as Phase) != Phase.Idle) { return Result.err(hibernalError(HibernalError.NotIdle)); }
	const epoch = block.started != 0 ? block.epoch : dayOf(config, clock().unixTimestamp);
	const hatched = Pet.born(block.id, seat as BlockSlot, record.pet.startRegion(), epoch, world.global);
	record.pet = hatched.pet;
	world.global = hatched.global;
	block.members[seat] = x.pet.key();
	block.filled = block.filled + 1;
	world.placed = world.placed + 1;
	return Result.ok(seat as uint64);
}
