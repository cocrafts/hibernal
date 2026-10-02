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
	createProgramAccount,
	instructionData,
	pdaWithBump,
	programId,
	readArgs,
} from "std/solana";
import { accounts, args } from "std/solana/macro";
import { DelegationAccounts, DelegationConfig, anyValidator, delegate, delegationProgram, onValidator } from "std/solana/magicblock";
import { initializeMint2 } from "std/solana/token";
import { GlobalConfig, PolicyError, checkPolicy, genesis } from "../rules/index";
import {
	Block,
	Config,
	CreateBlockArgs,
	HibernalError,
	InitializeArgs,
	POLICY_BYTES,
	Phase,
	Policy,
	VrfPayer,
	World,
	WritePolicyArgs,
	blockSeeds,
	configSeeds,
	hibernalError,
	mintSeeds,
	policySeeds,
	vrfPayerSeeds,
	worldSeeds,
} from "./layout";

const MINT_BYTES: uint64 = 82;
const HBRN_DECIMALS: uint8 = 6;
const POLICY_CHUNK_START: uint64 = 17;

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
	const madeConfig = try createPda<Config>(x.authority, x.config, configSeeds());
	const madePolicy = try createPda<Policy>(x.authority, x.policy, policySeeds());
	const madeWorld = try createPda<World>(x.authority, x.world, worldSeeds());
	const mint = x.mint as Account;
	const mintAddress = try mintSeeds().findProgramAddress(programId());
	if (mintAddress.key != mint.key()) { return Result.err(ProgramError.constraintSeeds()); }
	const _created = try createProgramAccount(
		x.authority as Account,
		mint,
		MINT_BYTES,
		Pubkey.tokenProgram(),
		mintSeeds().withBump(mintAddress.bump),
	);
	const _initialized = try initializeMint2(Pubkey.tokenProgram(), mint, HBRN_DECIMALS, mint.key(), null);
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
	config.bump = madeConfig.bump;
	config.mintBump = mintAddress.bump;
	config.policyBump = madePolicy.bump;
	config.worldBump = madeWorld.bump;
	const policy = madePolicy.account.data();
	policy.engine = a.engine;
	policy.bump = madePolicy.bump;
	const world = madeWorld.account.data();
	world.global = GlobalConfig.genesis(a.genesisTimestamp);
	world.resortEvery = a.resortEvery;
	world.bump = madeWorld.bump;
	return Result.ok(0);
}

export function writePolicy(): Result<uint64, ProgramError> {
	const a = try args<WritePolicyArgs>();
	const x = try accounts<WritePolicyAccounts>();
	const config = try authorized(x.config, x.authority.key());
	const policy = x.policy.data();
	const _verified = try pdaWithBump(x.policy, policySeeds(), policy.bump);
	if (policy.sealed != 0) { return Result.err(hibernalError(HibernalError.PolicySealed)); }
	const total = POLICY_BYTES as uint32;
	if (a.offset != policy.written || a.length > total - a.offset) {
		return Result.err(hibernalError(HibernalError.PolicyOutOfRange));
	}
	if (a.seal && a.offset + a.length != total) { return Result.err(hibernalError(HibernalError.PolicyUnsealed)); }
	const chunk = try instructionData().range(POLICY_CHUNK_START, a.length as uint64);
	for (let index: uint32 = 0; index < a.length; index++) {
		policy.bytes[(a.offset + index) as int32] = try chunk.readU8(index as uint64);
	}
	policy.written = a.offset + a.length;
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
	block.phase = Phase.Dawn as uint8;
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
