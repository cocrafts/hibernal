import {
	Account,
	External,
	Mutable,
	Owned,
	Program,
	ProgramError,
	Pubkey,
	Seeds,
	System,
	Writable,
	WritableSigner,
	clock,
	createPda,
	instructionData,
	pdaWithBump,
	programId,
	readArgs,
	unchecked,
} from "std/solana";
import { accounts } from "std/solana/macro";
import {
	DelegationAccounts,
	DelegationConfig,
	delegate,
	delegationProgram,
	isUndelegateCallback,
	onValidator,
	undelegate,
} from "std/solana/magicblock";
import {
	ExtensionType,
	Mint,
	TokenAccount,
	expectTokenMint,
	expectTokenOwner,
	mintExtension,
} from "std/solana/token";
import { BlockSlot, GlobalConfig, Pet, Region, born, epochOf, genesis } from "../rules/index";
import {
	Block,
	Config,
	HibernalError,
	NO_BLOCK,
	NO_SEAT,
	Paid,
	PetAccount,
	SEATS,
	World,
	blockSeeds,
	configSeeds,
	hibernalError,
	paidSeeds,
	petSeeds,
	worldSeeds,
} from "./layout";

const REGIONS: uint8 = 3;
const PERSONAS: uint8 = 3;

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

function configIn(config: Owned<Config>): Result<Readonly<Ptr<Config>>, ProgramError> {
	const stored = config.data();
	const derived = configSeeds().withBump(stored.bump).createProgramAddress(programId());
	if (!derived.ok || derived.value != config.key()) { return Result.err(ProgramError.constraintSeeds()); }
	return Result.ok(stored);
}

function admitted(mint: External<Mint>, group: Pubkey): Result<uint64, ProgramError> {
	const mintAccount = mint as Account;
	const pointer = mintAccount.mintExtension(ExtensionType.GroupMemberPointer);
	if (!pointer.ok) { return Result.err(hibernalError(HibernalError.NotAdmitted)); }
	const member = mintAccount.mintExtension(ExtensionType.TokenGroupMember);
	if (!member.ok) { return Result.err(hibernalError(HibernalError.NotAdmitted)); }
	const memberAddress = try pointer.value.readPubkey(32);
	const memberMint = try member.value.readPubkey(0);
	const memberGroup = try member.value.readPubkey(32);
	if (memberAddress != mintAccount.key() || memberMint != mintAccount.key() || memberGroup != group) {
		return Result.err(hibernalError(HibernalError.NotAdmitted));
	}
	return member.value.readU64(64);
}

export function claim(): Result<uint64, ProgramError> {
	const x = try accounts<ClaimAccounts>();
	const config = x.config.data();
	const _config = try pdaWithBump(x.config, configSeeds(), config.bump);
	const mintKey = x.mint.key();
	const _member = try admitted(x.mint, config.admissionGroup);
	const held = try x.held.read();
	const _heldMint = try expectTokenMint(held, mintKey);
	const _heldBy = try expectTokenOwner(held, x.owner.key());
	if (held.amount != 1) { return Result.err(hibernalError(HibernalError.NotAdmitted)); }
	const madePet = try createPda<PetAccount>(x.owner, x.pet, petSeeds(mintKey));
	const madePaid = try createPda<Paid>(x.owner, x.paid, paidSeeds(mintKey));
	const epoch = epochOf(clock().unixTimestamp as uint64, config.genesisTimestamp);
	const region = (mintKey.bytes[0] % REGIONS) as int32;
	const hatched = Pet.born(NO_BLOCK, BlockSlot.First, region as Region, epoch, GlobalConfig.genesis(config.genesisTimestamp));
	const record = madePet.account.data();
	record.owner = x.owner.key();
	record.mint = mintKey;
	record.ordinal = config.pets;
	record.persona = mintKey.bytes[1] % PERSONAS;
	record.bump = madePet.bump;
	record.claimedEpoch = epoch;
	record.pet = { ...hatched.pet, blockId: NO_BLOCK, slot: NO_SEAT, alive: false };
	const paid = madePaid.account.data();
	paid.mint = mintKey;
	paid.bump = madePaid.bump;
	config.pets = config.pets + 1;
	return Result.ok(record.ordinal as uint64);
}


export function delegated(
	request: DelegationAccounts,
	delegationProgram: Account,
	seeds: Seeds,
	bump: uint8,
	config: Readonly<Ptr<Config>>,
): Result<uint64, ProgramError> {
	if (request.ownerProgram.key() != programId()) { return Result.err(ProgramError.invalidProgramId()); }
	if (delegationProgram.key() != Pubkey.delegationProgram()) { return Result.err(ProgramError.invalidProgramId()); }
	const derived = seeds.withBump(bump).createProgramAddress(programId());
	if (!derived.ok || derived.value != request.delegated.key()) { return Result.err(ProgramError.constraintSeeds()); }
	if (config.validator.isZero()) { return Result.err(ProgramError.invalidArgument()); }
	return delegate(request, seeds, bump, DelegationConfig.onValidator(config.validator));
}

export function delegatePet(): Result<uint64, ProgramError> {
	const x = try accounts<DelegatePetAccounts>();
	const config = try configIn(x.config);
	const record = x.delegated.data();
	if (x.payer.key() != record.owner && x.payer.key() != config.authority) {
		return Result.err(hibernalError(HibernalError.NotTheOwner));
	}
	const request: DelegationAccounts = {
		payer: x.payer as Account,
		delegated: x.delegated as Account,
		ownerProgram: x.ownerProgram,
		buffer: x.buffer as Account,
		delegationRecord: x.delegationRecord as Account,
		delegationMetadata: x.delegationMetadata as Account,
		systemProgram: x.systemProgram as Account,
	};
	return delegated(request, x.delegationProgram, petSeeds(record.mint), record.bump, config);
}

export function delegateBlock(): Result<uint64, ProgramError> {
	const x = try accounts<DelegateBlockAccounts>();
	const config = try configIn(x.config);
	if (x.payer.key() != config.authority) { return Result.err(hibernalError(HibernalError.NotAuthority)); }
	const block = x.delegated.data();
	const request: DelegationAccounts = {
		payer: x.payer as Account,
		delegated: x.delegated as Account,
		ownerProgram: x.ownerProgram,
		buffer: x.buffer as Account,
		delegationRecord: x.delegationRecord as Account,
		delegationMetadata: x.delegationMetadata as Account,
		systemProgram: x.systemProgram as Account,
	};
	return delegated(request, x.delegationProgram, blockSeeds(block.id), block.bump, config);
}

export function delegateWorld(): Result<uint64, ProgramError> {
	const x = try accounts<DelegateWorldAccounts>();
	const config = try configIn(x.config);
	if (x.payer.key() != config.authority) { return Result.err(hibernalError(HibernalError.NotAuthority)); }
	const world = x.delegated.data();
	const request: DelegationAccounts = {
		payer: x.payer as Account,
		delegated: x.delegated as Account,
		ownerProgram: x.ownerProgram,
		buffer: x.buffer as Account,
		delegationRecord: x.delegationRecord as Account,
		delegationMetadata: x.delegationMetadata as Account,
		systemProgram: x.systemProgram as Account,
	};
	return delegated(request, x.delegationProgram, worldSeeds(), world.bump, config);
}

export function processUndelegation(): Result<uint64, ProgramError> {
	const data = instructionData();
	if (!isUndelegateCallback(data)) { return Result.err(ProgramError.instructionFallbackNotFound()); }
	const x = try accounts<UndelegationAccounts>();
	return undelegate(x.delegated as Account, x.buffer, x.payer as Account, programId(), data);
}

export function place(): Result<uint64, ProgramError> {
	const x = try accounts<PlaceAccounts>();
	const config = try configIn(x.config);
	if (x.authority.key() != config.authority) { return Result.err(hibernalError(HibernalError.NotAuthority)); }
	const world = x.world.data();
	const _world = try pdaWithBump(x.world, worldSeeds(), world.bump);
	const block = x.block.data();
	const _block = try pdaWithBump(x.block, blockSeeds(block.id), block.bump);
	const record = x.pet.data();
	const _pet = try pdaWithBump(x.pet, petSeeds(record.mint), record.bump);
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
	const epoch = epochOf(clock().unixTimestamp as uint64, config.genesisTimestamp);
	const hatched = Pet.born(block.id, seat as BlockSlot, record.pet.startRegion(), epoch, world.global);
	record.pet = hatched.pet;
	world.global = hatched.global;
	block.members[seat] = x.pet.key();
	block.filled = block.filled + 1;
	world.placed = world.placed + 1;
	return Result.ok(seat as uint64);
}
