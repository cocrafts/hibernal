import {
	Account,
	Clock,
	InstructionAccount,
	ProgramError,
	Pubkey,
	findProgramAddressOf,
	invokeSigned,
	programId,
	pubkeyOf,
	putPubkey,
	putU32,
	putU64,
	putU8,
} from "std/solana";
import { MAGIC_PROGRAM_ID } from "std/solana/magicblock";
import { SignerSeeds } from "std/solana/seed";

const HYDRA_CREATE: uint8 = 0;
const HYDRA_CANCEL: uint8 = 2;
const WRITABLE_ROLE: uint8 = 2;
const READONLY_ROLE: uint8 = 0;
const CREATE_HEADER_BYTES: uint64 = 1 + 32 + 32 + 8 * 4 + 4 + 3 + 32;
const ROLE_AND_KEY_BYTES: uint64 = 33;
const REMAINING_OFFSET: uint64 = 80;
export const CRANK_COMPUTE_UNITS: uint32 = 1_400_000;
export const ONE_SHOT_INTERVAL_SLOTS: uint64 = 1_000_000_000;
export const MAX_SCHEDULED_ACCOUNTS: int32 = 24;

export struct ScheduledMeta {
	key: Pubkey;
	writable: boolean;
}

export struct CrankAccounts {
	sponsor: Account;
	crank: Account;
	magicVault: Account;
	magicProgram: Account;
	hydraProgram: Account;
}

export function hydraProgram(this typeof Pubkey): Pubkey {
	return @comptime { return pubkeyOf("eHyd5BU8QffvHi4GnXwxrK4WpS7pM2x9UGKHBWii7mf"); };
}

export function magicVault(this typeof Pubkey): Pubkey {
	return @comptime { return pubkeyOf("MagicVau1t999999999999999999999999999999999"); };
}

export function crankSeed(blockId: uint32, seq: uint64): Pubkey {
	let seed = Pubkey.zero();
	const program = programId();
	const block = blockId as uint64;
	for (let index = 0; index < 8; index++) {
		const shift = (index * 8) as uint64;
		seed.bytes[index] = ((block >> shift) & 0xff) as uint8;
		seed.bytes[8 + index] = ((seq >> shift) & 0xff) as uint8;
	}
	for (let index = 0; index < 16; index++) { seed.bytes[16 + index] = program.bytes[index]; }
	return seed;
}

export function crankAddress(blockId: uint32, seq: uint64): Result<Pubkey, ProgramError> {
	const seed = crankSeed(blockId, seq);
	const found = try findProgramAddressOf(Pubkey.hydraProgram(), ["crank", seed]);
	return Result.ok(found.key);
}

export function dueSlotFor(now: Clock, targetUnix: int64, slotMillis: uint64): uint64 {
	if (targetUnix <= now.unixTimestamp) { return now.slot + 1; }
	const waitMillis = ((targetUnix - now.unixTimestamp) as uint64) * 1000;
	return now.slot + waitMillis / slotMillis;
}

export function checkedCrankAccounts(accounts: CrankAccounts, expected: Pubkey): Result<uint64, ProgramError> {
	if (accounts.hydraProgram.key() != Pubkey.hydraProgram()) { return Result.err(ProgramError.incorrectProgramId()); }
	if (accounts.magicProgram.key() != MAGIC_PROGRAM_ID) { return Result.err(ProgramError.incorrectProgramId()); }
	if (accounts.magicVault.key() != Pubkey.magicVault()) { return Result.err(ProgramError.invalidArgument()); }
	if (accounts.crank.key() != expected) { return Result.err(ProgramError.invalidSeeds()); }
	return Result.ok(0);
}

export function createCrank(
	accounts: CrankAccounts,
	seed: Pubkey,
	dueSlot: uint64,
	metas: Span<ScheduledMeta>,
	discriminator: uint64,
	seq: uint64,
	signers: Readonly<Span<SignerSeeds>> = [],
): Result<uint64, ProgramError> {
	let storage: uint8[944] = [];
	if (CREATE_HEADER_BYTES + ROLE_AND_KEY_BYTES * (metas.length as uint64) + 16 > storage.length as uint64) {
		return Result.err(ProgramError.invalidArgument());
	}
	let at = putU8(storage, 0, HYDRA_CREATE);
	at = putPubkey(storage, at, seed);
	at = putPubkey(storage, at, accounts.sponsor.key());
	at = putU64(storage, at, dueSlot);
	at = putU64(storage, at, ONE_SHOT_INTERVAL_SLOTS);
	at = putU64(storage, at, 1);
	at = putU64(storage, at, 0);
	at = putU32(storage, at, CRANK_COMPUTE_UNITS);
	at = putU8(storage, at, metas.length as uint8);
	at = putU8(storage, at, 16);
	at = putU8(storage, at, 0);
	at = putPubkey(storage, at, programId());
	for (const meta of metas) {
		at = putU8(storage, at, meta.writable ? WRITABLE_ROLE : READONLY_ROLE);
		at = putPubkey(storage, at, meta.key);
	}
	at = putU64(storage, at, discriminator);
	at = putU64(storage, at, seq);
	return invokeSigned(
		Pubkey.hydraProgram(),
		[
			InstructionAccount.writableSigner(accounts.sponsor),
			InstructionAccount.writable(accounts.crank),
			InstructionAccount.writable(accounts.magicVault),
			InstructionAccount.readonly(accounts.magicProgram),
		],
		storage,
		at,
		signers,
	);
}

export function spentCrankOf(crank: Account, sponsor: Pubkey): Result<boolean, ProgramError> {
	if (!crank.isOwnedBy(Pubkey.hydraProgram()) || crank.dataLength() < REMAINING_OFFSET + 8) { return Result.ok(false); }
	const data = crank.data();
	const authority = try data.readPubkey(0);
	const remaining = try data.readU64(REMAINING_OFFSET);
	return Result.ok(authority == sponsor && remaining == 0);
}

export function cancelCrank(
	sponsor: Account,
	crank: Account,
	magicVault: Account,
	magicProgram: Account,
	signers: Readonly<Span<SignerSeeds>> = [],
): Result<uint64, ProgramError> {
	let storage: uint8[1] = [];
	const length = putU8(storage, 0, HYDRA_CANCEL);
	return invokeSigned(
		Pubkey.hydraProgram(),
		[
			InstructionAccount.writableSigner(sponsor),
			InstructionAccount.writable(crank),
			InstructionAccount.writable(sponsor),
			InstructionAccount.writable(magicVault),
			InstructionAccount.readonly(magicProgram),
		],
		storage,
		length,
		signers,
	);
}
