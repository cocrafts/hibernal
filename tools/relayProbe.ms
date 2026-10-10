import {
	Account,
	Discriminator,
	Instruction,
	Mutable,
	Program,
	ProgramError,
	Pubkey,
	Seeds,
	System,
	Writable,
	WritableSigner,
	accountDiscriminator,
	clock,
	createPda,
	failWith,
	instructionDiscriminator,
	programId,
	pubkeyOf,
	readArgs,
	selectInstruction,
	transfer,
} from "std/solana";
import { accounts, args, instruction } from "std/solana/macro";
import { DelegationAccounts, DelegationConfig, delegate, magicProgram } from "std/solana/magicblock";

const HYDRA_CREATE: uint8 = 0;
const HYDRA_CANCEL: uint8 = 2;
const SCHEDULED_ACCOUNTS: uint8 = 6;
const SCHEDULED_DATA_BYTES: uint64 = 16;
const WRITABLE_ROLE: uint8 = 2;
const READONLY_ROLE: uint8 = 0;
const CREATE_DATA_BYTES: uint64 = 101 + 3 + 32 + 33 * 6 + 16;

export enum Op {
	OpenRelay,
	Hop,
}

export enum RelayError {
	WrongCrank,
	WrongProgram,
}

export struct Relay {
	chain: uint64;
	hops: uint64;
	maxHops: uint64;
	gapSlots: uint64;
	computeUnits: uint64;
	dueSlot: uint64;
	lateTotal: uint64;
	lateMax: uint64;
	firstSlot: uint64;
	lastSlot: uint64;
	bump: uint8;
	cancelsPrevious: boolean;
	pad: uint8[6];
}

export function discriminator(this typeof Relay): Discriminator {
	return @comptime { return accountDiscriminator("Relay"); };
}

export struct OpenRelayArgs {
	chain: uint64;
	maxHops: uint64;
	gapSlots: uint64;
	computeUnits: uint64;
	sponsorLamports: uint64;
	validator: Pubkey;
	cancelsPrevious: boolean;
}

export struct HopArgs {
	hop: uint64;
}

export struct OpenRelayAccounts {
	authority: WritableSigner;
	relay: Writable;
	ownerProgram: Account;
	buffer: Writable;
	delegationRecord: Writable;
	delegationMetadata: Writable;
	delegationProgram: Account;
	systemProgram: Program<System>;
}

export struct HopAccounts {
	relay: Mutable<Relay>;
	previousCrank: Account;
	nextCrank: Account;
	magicVault: Writable;
	magicProgram: Account;
	hydraProgram: Account;
}

function hydraProgram(this typeof Pubkey): Pubkey {
	return @comptime { return pubkeyOf("eHyd5BU8QffvHi4GnXwxrK4WpS7pM2x9UGKHBWii7mf"); };
}

function magicVault(this typeof Pubkey): Pubkey {
	return @comptime { return pubkeyOf("MagicVau1t999999999999999999999999999999999"); };
}

function hopDiscriminator(): Discriminator {
	return @comptime { return instructionDiscriminator("Hop"); };
}

export converter relayError(error: RelayError): ProgramError {
	return ProgramError.userError(error as uint32);
}

export function relaySeeds(chain: uint64): Seeds {
	return Seeds.empty(2).addText("relay").addU64(chain);
}

function crankSeed(chain: uint64, hop: uint64): Pubkey {
	let seed = Pubkey.zero();
	for (let index = 0; index < 8; index++) {
		const shift = (index * 8) as uint64;
		seed.bytes[index] = ((chain >> shift) & 0xff) as uint8;
		seed.bytes[8 + index] = ((hop >> shift) & 0xff) as uint8;
	}
	return seed;
}

function crankAddress(chain: uint64, hop: uint64): Result<Pubkey, ProgramError> {
	const found = try Seeds.empty(2)
		.addText("crank")
		.addPubkey(crankSeed(chain, hop))
		.findProgramAddress(Pubkey.hydraProgram());
	return Result.ok(found.key);
}

export function openRelay(): Result<uint64, ProgramError> {
	const x = try accounts<OpenRelayAccounts>();
	const a = try args<OpenRelayArgs>();
	if (x.ownerProgram.key() != programId()) { return Result.err(ProgramError.incorrectProgramId()); }
	const made = try createPda<Relay>(x.authority, x.relay, relaySeeds(a.chain));
	const relay = made.account.data();
	relay.chain = a.chain;
	relay.maxHops = a.maxHops;
	relay.gapSlots = a.gapSlots;
	relay.computeUnits = a.computeUnits;
	relay.bump = made.bump;
	relay.cancelsPrevious = a.cancelsPrevious;
	const holder = x.relay as Account;
	const _funded = try transfer(x.authority as Account, holder, a.sponsorLamports, Seeds.none());
	const delegation: DelegationAccounts = {
		payer: x.authority as Account,
		delegated: holder,
		ownerProgram: x.ownerProgram,
		buffer: x.buffer as Account,
		delegationRecord: x.delegationRecord as Account,
		delegationMetadata: x.delegationMetadata as Account,
		systemProgram: x.systemProgram as Account,
	};
	const config = DelegationConfig.onValidator(a.validator);
	return delegate(delegation, relaySeeds(a.chain), made.bump, config);
}

function appendScheduledHop(
	create: Instruction,
	relay: Pubkey,
	previousCrank: Pubkey,
	previousWritable: boolean,
	afterCrank: Pubkey,
	afterWritable: boolean,
	hop: uint64,
): void {
	create.appendU8(SCHEDULED_ACCOUNTS);
	create.appendU8(SCHEDULED_DATA_BYTES as uint8);
	create.appendU8(0);
	create.appendPubkey(programId());
	create.appendU8(WRITABLE_ROLE);
	create.appendPubkey(relay);
	create.appendU8(previousWritable ? WRITABLE_ROLE : READONLY_ROLE);
	create.appendPubkey(previousCrank);
	create.appendU8(afterWritable ? WRITABLE_ROLE : READONLY_ROLE);
	create.appendPubkey(afterCrank);
	create.appendU8(WRITABLE_ROLE);
	create.appendPubkey(Pubkey.magicVault());
	create.appendU8(READONLY_ROLE);
	create.appendPubkey(Pubkey.magicProgram());
	create.appendU8(READONLY_ROLE);
	create.appendPubkey(Pubkey.hydraProgram());
	create.appendU64(hopDiscriminator().word());
	create.appendU64(hop);
}

function cancelCrank(x: HopAccounts, chain: uint64, bump: uint8): Result<uint64, ProgramError> {
	const holder = x.relay as Account;
	const cancel = Instruction.forProgram(Pubkey.hydraProgram(), 5, 1);
	cancel.addWritableSigner(holder);
	cancel.addWritable(x.previousCrank);
	cancel.addWritable(holder);
	cancel.addWritable(x.magicVault as Account);
	cancel.addReadonly(x.magicProgram);
	cancel.appendU8(HYDRA_CANCEL);
	return cancel.invokeSigned(relaySeeds(chain).withBump(bump));
}

export function hop(): Result<uint64, ProgramError> {
	const x = try accounts<HopAccounts>();
	const a = try args<HopArgs>();
	if (x.hydraProgram.key() != Pubkey.hydraProgram()) { return Result.err(relayError(RelayError.WrongProgram)); }
	const relay = x.relay.data();
	if (a.hop != relay.hops) { return Result.ok(relay.hops); }
	const now = clock().slot;
	if (relay.hops == 0) { relay.firstSlot = now; }
	if (relay.hops > 0 && now > relay.dueSlot) {
		const late = now - relay.dueSlot;
		relay.lateTotal = relay.lateTotal + late;
		relay.lateMax = Math.max(relay.lateMax, late);
	}
	relay.hops = relay.hops + 1;
	relay.lastSlot = now;
	if (relay.cancelsPrevious && a.hop >= 2) {
		const previousCrank = try crankAddress(relay.chain, a.hop - 1);
		if (previousCrank != x.previousCrank.key()) { return Result.err(relayError(RelayError.WrongCrank)); }
		const _cancelled = try cancelCrank(x, relay.chain, relay.bump);
	}
	if (relay.hops >= relay.maxHops) { return Result.ok(relay.hops); }
	const nextCrank = try crankAddress(relay.chain, relay.hops);
	if (nextCrank != x.nextCrank.key()) { return Result.err(relayError(RelayError.WrongCrank)); }
	const afterCrank = try crankAddress(relay.chain, relay.hops + 1);
	const ownCrank = try crankAddress(relay.chain, a.hop);
	const holder = x.relay as Account;
	relay.dueSlot = now + relay.gapSlots;
	const create = Instruction.forProgram(Pubkey.hydraProgram(), 4, CREATE_DATA_BYTES);
	create.addWritableSigner(holder);
	create.addWritable(x.nextCrank);
	create.addWritable(x.magicVault as Account);
	create.addReadonly(x.magicProgram);
	create.appendU8(HYDRA_CREATE);
	create.appendPubkey(crankSeed(relay.chain, relay.hops));
	create.appendPubkey(holder.key());
	create.appendU64(relay.dueSlot);
	create.appendU64(relay.gapSlots);
	create.appendU64(1);
	create.appendU64(0);
	create.appendU32(relay.computeUnits as uint32);
	const previousWritable = relay.cancelsPrevious && relay.hops >= 2;
	const afterWritable = relay.hops + 1 < relay.maxHops;
	appendScheduledHop(
		create,
		holder.key(),
		ownCrank,
		previousWritable,
		afterCrank,
		afterWritable,
		relay.hops,
	);
	const _created = try create.invokeSigned(relaySeeds(relay.chain).withBump(relay.bump));
	return Result.ok(relay.hops);
}

export function dispatch(): Result<uint64, ProgramError> {
	return match (try instruction<Op>()) {
		Op.OpenRelay => openRelay(),
		Op.Hop => hop(),
	};
}

export function entry(): void {
	const result = dispatch();
	if (!result.ok) { failWith(result.error); }
}

when (!testBuild) {
	entry();
}
