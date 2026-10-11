import {
	Account,
	External,
	ExternalMutable,
	Mutable,
	Owned,
	Program,
	ProgramError,
	Pubkey,
	InstructionAccount,
	Signer,
	System,
	Token,
	Writable,
	WritableSigner,
	createPda,
	Bytes,
	DELEGATION_PROGRAM_ID,
	TOKEN_2022_PROGRAM_ID,
	TOKEN_PROGRAM_ID,
	findProgramAddress,
	invoke,
	leBytes,
	minimumBalance,
	pdaWithBump,
	programId,
	pubkeyOf,
	putBool,
	putU16,
	putU8,
	signed,
	transfer,
} from "std/solana";
import { accounts, args } from "std/solana";
import { DelegationAccounts, DelegationConfig, anyValidator, delegate, onValidator } from "std/solana/magicblock";
import { Mint, TokenAccount, associatedTokenAddress, createMintPda, transferTokens } from "std/solana/token";
import { ACTS_PER_EPOCH, GlobalConfig, PolicyError, checkPolicy, genesis } from "../rules/index";
import {
	Block,
	Config,
	CreateBlockArgs,
	HibernalError,
	InitializeArgs,
	NEVER_DAWNED,
	POLICY_BYTES,
	Phase,
	Policy,
	VrfPayer,
	World,
	hibernalError,
	WithdrawRevenueArgs,
} from "./layout";

const HBRN_DECIMALS: uint8 = 6;

export struct InitializeAccounts {
	authority: WritableSigner;
	config: Writable;
	policy: Writable;
	world: Writable;
	mint: Writable;
	tokenProgram: Program<Token>;
	systemProgram: Program<System>;
}

export struct WithdrawRevenueAccounts {
	authority: Signer;
	config: Mutable<Config>;
	revenue: Account;
	treasury: ExternalMutable<TokenAccount>;
	skrMint: External<Mint>;
	destination: ExternalMutable<TokenAccount>;
	tokenProgram: Account;
}

export struct WithdrawFundAccounts {
	authority: Signer;
	config: Mutable<Config>;
	fund: Writable;
	destination: Writable;
	systemProgram: Program<System>;
}

export struct WritePolicyAccounts {
	authority: WritableSigner;
	config: Mutable<Config>;
	policy: Mutable<Policy>;
}

export struct CreateBlockAccounts {
	authority: WritableSigner;
	config: Mutable<Config>;
	block: Writable;
	systemProgram: Program<System>;
}

export struct DelegateVrfPayerAccounts {
	authority: WritableSigner;
	config: Owned<Config>;
	vrfPayer: Writable;
	ownerProgram: Account;
	buffer: Writable;
	delegationRecord: Writable;
	delegationMetadata: Writable;
	delegationProgram: Account;
	systemProgram: Program<System>;
}

export function authorized(config: Mutable<Config>, authority: Pubkey): Result<Ptr<Config>, ProgramError> {
	const stored = config.data();
	const _verified = try pdaWithBump(config, ["config"], stored.bump);
	if (stored.authority != authority) { return Result.err(hibernalError(HibernalError.NotAuthority)); }
	return Result.ok(stored);
}

function revenueVault(skrMint: Pubkey, tokenProgram: Pubkey): Result<Pubkey, ProgramError> {
	const revenue = try findProgramAddress(["revenue"]);
	const vault = try associatedTokenAddress(revenue.key, skrMint, tokenProgram);
	return Result.ok(vault.key);
}

function heldByProgram(treasury: Pubkey, skrMint: Pubkey): Result<boolean, ProgramError> {
	const classic = try revenueVault(skrMint, TOKEN_PROGRAM_ID);
	const extended = try revenueVault(skrMint, TOKEN_2022_PROGRAM_ID);
	return Result.ok(treasury == classic || treasury == extended);
}

export function initialize(): Result<uint64, ProgramError> {
	const a = try args<InitializeArgs>();
	const x = try accounts<InitializeAccounts>();
	if (a.secondsPerDay < (ACTS_PER_EPOCH as uint64) || a.slotMillis == 0 || a.turnGapSlots == 0) {
		return Result.err(hibernalError(HibernalError.BadClock));
	}
	if (!(try heldByProgram(a.treasury, a.skrMint))) {
		return Result.err(hibernalError(HibernalError.WrongTreasury));
	}
	if (a.hatchFeeLamports != 0 && a.hatchFeeLamports < minimumBalance(0)) {
		return Result.err(hibernalError(HibernalError.HatchFeeTooSmall));
	}
	const madeConfig = try createPda<Config>(x.authority, x.config, ["config"]);
	const madePolicy = try createPda<Policy>(x.authority, x.policy, ["policy"]);
	const madeWorld = try createPda<World>(x.authority, x.world, ["world"]);
	const mint = x.mint.asAccount();
	const mintBump = try createMintPda(x.authority, x.mint, ["mint"], TOKEN_PROGRAM_ID, HBRN_DECIMALS, mint.key(), null);
	const config = madeConfig.account.data();
	config.authority = x.authority.key();
	config.admissionGroup = a.admissionGroup;
	config.hbrnMint = mint.key();
	config.engine = a.engine;
	config.genesisTimestamp = a.genesisTimestamp;
	config.claimCapPerDay = a.claimCapPerDay;
	config.validator = a.validator;
	config.skrMint = a.skrMint;
	config.treasury = a.treasury;
	config.vrfQueue = a.vrfQueue;
	config.secondsPerDay = a.secondsPerDay;
	config.staggerSeconds = a.staggerSeconds;
	config.slotMillis = a.slotMillis;
	config.turnGapSlots = a.turnGapSlots;
	config.hatchFeeLamports = a.hatchFeeLamports;
	config.bump = madeConfig.bump;
	config.mintBump = mintBump;
	config.policyBump = madePolicy.bump;
	config.worldBump = madeWorld.bump;
	const policy = madePolicy.account.data();
	policy.engine = a.engine;
	policy.bump = madePolicy.bump;
	const world = madeWorld.account.data();
	world.global = GlobalConfig.genesis(a.genesisTimestamp);
	world.resortEvery = a.resortEvery;
	world.secondsPerDay = a.secondsPerDay;
	world.bump = madeWorld.bump;
	return Result.ok(0);
}

export struct WritePolicyArgs {
	offset: uint32;
	seal: boolean;
	chunk: Bytes;
}

export function writePolicy(): Result<uint64, ProgramError> {
	const a = try args<WritePolicyArgs>();
	const x = try accounts<WritePolicyAccounts>();
	const config = try authorized(x.config, x.authority.key());
	const policy = x.policy.data();
	const _verified = try pdaWithBump(x.policy, ["policy"], policy.bump);
	if (policy.sealed != 0) { return Result.err(hibernalError(HibernalError.PolicySealed)); }
	const total = POLICY_BYTES as uint32;
	const length = a.chunk.length as uint32;
	if (a.offset != policy.written || length > total - a.offset) {
		return Result.err(hibernalError(HibernalError.PolicyOutOfRange));
	}
	if (a.seal && a.offset + length != total) { return Result.err(hibernalError(HibernalError.PolicyUnsealed)); }
	for (let index: uint32 = 0; index < length; index++) {
		policy.bytes[(a.offset + index) as int32] = try a.chunk.readU8(index as uint64);
	}
	policy.written = a.offset + length;
	if (!a.seal) { return Result.ok(policy.written as uint64); }
	if (policy.engine != config.engine) { return Result.err(hibernalError(HibernalError.EngineMismatch)); }
	const checked = checkPolicy(policy.bytes, config.engine);
	if (!checked.ok) {
		const failure: HibernalError = match (checked.error) {
			PolicyError.WrongEngine => HibernalError.EngineMismatch,
			_ => HibernalError.Rules,
		};
		return Result.err(hibernalError(failure));
	}
	policy.sealed = 1;
	return Result.ok(policy.written as uint64);
}

export function createBlock(): Result<uint64, ProgramError> {
	const a = try args<CreateBlockArgs>();
	const x = try accounts<CreateBlockAccounts>();
	const config = try authorized(x.config, x.authority.key());
	if (a.id != config.blocks) { return Result.err(hibernalError(HibernalError.OutOfOrder)); }
	const made = try createPda<Block>(x.authority, x.block, ["block", leBytes(a.id as uint64)]);
	const block = made.account.data();
	block.id = a.id;
	block.bump = made.bump;
	block.phase = Phase.Idle as uint8;
	block.dawnedEpoch = NEVER_DAWNED;
	config.blocks = config.blocks + 1;
	return Result.ok(a.id as uint64);
}

export function delegateVrfPayer(): Result<uint64, ProgramError> {
	const x = try accounts<DelegateVrfPayerAccounts>();
	if (x.config.data().authority != x.authority.key()) { return Result.err(hibernalError(HibernalError.NotAuthority)); }
	if (x.ownerProgram.key() != programId()) { return Result.err(ProgramError.incorrectProgramId()); }
	if (x.delegationProgram.key() != DELEGATION_PROGRAM_ID) { return Result.err(ProgramError.incorrectProgramId()); }
	const holder = x.vrfPayer.asAccount();
	let bump: uint8 = 0;
	if (holder.lamports() == 0) {
		const made = try createPda<VrfPayer>(x.authority, x.vrfPayer, ["vrf-payer"]);
		made.account.data().bump = made.bump;
		bump = made.bump;
	} else {
		const found = try findProgramAddress(["vrf-payer"]);
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
	return delegate(delegation, ["vrf-payer"], bump, config);
}

export function withdrawRevenue(): Result<uint64, ProgramError> {
	const a = try args<WithdrawRevenueArgs>();
	const x = try accounts<WithdrawRevenueAccounts>();
	const config = try authorized(x.config, x.authority.key());
	if (x.treasury.key() != config.treasury || x.skrMint.key() != config.skrMint) {
		return Result.err(hibernalError(HibernalError.WrongTreasury));
	}
	const revenue = try findProgramAddress(["revenue"]);
	if (x.revenue.key() != revenue.key) { return Result.err(ProgramError.constraintSeeds()); }
	return signed(
		transferTokens(x.treasury, x.destination, x.skrMint, x.revenue, a.amount),
		["revenue", [revenue.bump]],
	);
}

export function withdrawFund(): Result<uint64, ProgramError> {
	const a = try args<WithdrawRevenueArgs>();
	const x = try accounts<WithdrawFundAccounts>();
	const _config = try authorized(x.config, x.authority.key());
	const fund = try findProgramAddress(["revenue"]);
	if (x.fund.key() != fund.key) { return Result.err(ProgramError.constraintSeeds()); }
	return signed(transfer(x.fund.asAccount(), x.destination.asAccount(), a.amount), ["revenue", [fund.bump]]);
}

const CREATE_METADATA_V3: uint8 = 33;
const METADATA_TEXTS: int32 = 3;

export function metadataProgram(this typeof Pubkey): Pubkey {
	return @comptime { return pubkeyOf("metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s"); };
}

export struct CreateHbrnMetadataAccounts {
	authority: WritableSigner;
	config: Mutable<Config>;
	mint: External<Mint>;
	metadata: Writable;
	metadataProgram: Account;
	systemProgram: Program<System>;
}

export struct CreateHbrnMetadataArgs {
	texts: Bytes;
}

function textsEnd(texts: Bytes): Result<uint64, ProgramError> {
	let read: uint64 = 0;
	for (let field = 0; field < METADATA_TEXTS; field++) {
		const length = try texts.readU32(read);
		read = read + 4 + (length as uint64);
	}
	if (read != texts.length) { return Result.err(hibernalError(HibernalError.BadMetadata)); }
	return Result.ok(read);
}

export function createHbrnMetadata(): Result<uint64, ProgramError> {
	const a = try args<CreateHbrnMetadataArgs>();
	const x = try accounts<CreateHbrnMetadataAccounts>();
	const config = try authorized(x.config, x.authority.key());
	if (x.mint.key() != config.hbrnMint) { return Result.err(hibernalError(HibernalError.WrongMint)); }
	if (x.metadataProgram.key() != Pubkey.metadataProgram()) { return Result.err(ProgramError.incorrectProgramId()); }
	const length = try textsEnd(a.texts);
	let storage: uint8[300] = [];
	let at = putU8(storage, 0, CREATE_METADATA_V3);
	for (let index: uint64 = 0; index < length; index++) {
		at = putU8(storage, at, try a.texts.readU8(index));
	}
	at = putU16(storage, at, 0);
	at = putU8(storage, at, 0);
	at = putU8(storage, at, 0);
	at = putU8(storage, at, 0);
	at = putBool(storage, at, true);
	at = putU8(storage, at, 0);
	if (at > (storage.length as uint64)) { return Result.err(hibernalError(HibernalError.BadMetadata)); }
	return signed(
		invoke(
			Pubkey.metadataProgram(),
			[
				InstructionAccount.writable(x.metadata.asAccount()),
				InstructionAccount.readonlySigner(x.mint.asAccount()),
				InstructionAccount.readonlySigner(x.mint.asAccount()),
				InstructionAccount.writableSigner(x.authority.asAccount()),
				InstructionAccount.readonly(x.authority.asAccount()),
				InstructionAccount.readonly(x.systemProgram.asAccount()),
			],
			storage,
			at,
		),
		["mint", [config.mintBump]],
	);
}
