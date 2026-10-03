import {
	Account,
	Mutable,
	Owned,
	Program,
	ProgramError,
	Pubkey,
	System,
	Token,
	Writable,
	WritableSigner,
	createPda,
	Bytes,
	pdaWithBump,
	programId,
	readArgs,
} from "std/solana";
import { accounts, args } from "std/solana/macro";
import { DelegationAccounts, DelegationConfig, anyValidator, delegate, delegationProgram, onValidator } from "std/solana/magicblock";
import { createMintPda } from "std/solana/token";
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
	blockSeeds,
	configSeeds,
	hibernalError,
	mintSeeds,
	policySeeds,
	vrfPayerSeeds,
	worldSeeds,
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
	const _verified = try pdaWithBump(config, configSeeds(), stored.bump);
	if (stored.authority != authority) { return Result.err(hibernalError(HibernalError.NotAuthority)); }
	return Result.ok(stored);
}

export function initialize(): Result<uint64, ProgramError> {
	const a = try args<InitializeArgs>();
	const x = try accounts<InitializeAccounts>();
	if (a.secondsPerDay < (ACTS_PER_EPOCH as uint64) || a.slotMillis == 0 || a.turnGapSlots == 0) {
		return Result.err(hibernalError(HibernalError.BadClock));
	}
	const madeConfig = try createPda<Config>(x.authority, x.config, configSeeds());
	const madePolicy = try createPda<Policy>(x.authority, x.policy, policySeeds());
	const madeWorld = try createPda<World>(x.authority, x.world, worldSeeds());
	const mint = x.mint as Account;
	const mintBump = try createMintPda(x.authority, x.mint, mintSeeds(), Pubkey.tokenProgram(), HBRN_DECIMALS, mint.key(), null);
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
	const _verified = try pdaWithBump(x.policy, policySeeds(), policy.bump);
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
	const made = try createPda<Block>(x.authority, x.block, blockSeeds(a.id));
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
	if (x.delegationProgram.key() != Pubkey.delegationProgram()) { return Result.err(ProgramError.incorrectProgramId()); }
	const holder = x.vrfPayer as Account;
	let bump: uint8 = 0;
	if (holder.lamports() == 0) {
		const made = try createPda<VrfPayer>(x.authority, x.vrfPayer, vrfPayerSeeds());
		made.account.data().bump = made.bump;
		bump = made.bump;
	} else {
		const found = try vrfPayerSeeds().findProgramAddress(programId());
		if (found.key != holder.key()) { return Result.err(ProgramError.constraintSeeds()); }
		bump = found.bump;
	}
	const validator = x.config.data().validator;
	const config = validator.isZero() ? DelegationConfig.anyValidator() : DelegationConfig.onValidator(validator);
	const delegation: DelegationAccounts = {
		payer: x.authority as Account,
		delegated: holder,
		ownerProgram: x.ownerProgram,
		buffer: x.buffer as Account,
		delegationRecord: x.delegationRecord as Account,
		delegationMetadata: x.delegationMetadata as Account,
		systemProgram: x.systemProgram as Account,
	};
	return delegate(delegation, vrfPayerSeeds(), bump, config);
}
