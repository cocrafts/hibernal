import {
	Account,
	Clock,
	Instruction,
	ProgramError,
	Pubkey,
	Seeds,
	programId,
	pubkeyOf,
} from "std/solana";
import { magicProgram } from "std/solana/magicblock";

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
	const found = try Seeds.empty(2)
		.addText("crank")
		.addPubkey(crankSeed(blockId, seq))
		.findProgramAddress(Pubkey.hydraProgram());
	return Result.ok(found.key);
}

export function dueSlotFor(now: Clock, targetUnix: int64, slotMillis: uint64): uint64 {
	if (targetUnix <= now.unixTimestamp) { return now.slot + 1; }
	const waitMillis = ((targetUnix - now.unixTimestamp) as uint64) * 1000;
	return now.slot + waitMillis / slotMillis;
}

export function checkedCrankAccounts(accounts: CrankAccounts, expected: Pubkey): Result<uint64, ProgramError> {
	if (accounts.hydraProgram.key() != Pubkey.hydraProgram()) { return Result.err(ProgramError.incorrectProgramId()); }
	if (accounts.magicProgram.key() != Pubkey.magicProgram()) { return Result.err(ProgramError.incorrectProgramId()); }
	if (accounts.magicVault.key() != Pubkey.magicVault()) { return Result.err(ProgramError.invalidArgument()); }
	if (accounts.crank.key() != expected) { return Result.err(ProgramError.invalidSeeds()); }
	return Result.ok(0);
}

export function createCrank(
	accounts: CrankAccounts,
	sponsorSigner: Seeds,
	seed: Pubkey,
	dueSlot: uint64,
	metas: Span<ScheduledMeta>,
	discriminator: uint64,
	seq: uint64,
): Result<uint64, ProgramError> {
	const metaCount = metas.length as uint64;
	const create = Instruction.forProgram(
		Pubkey.hydraProgram(),
		4,
		CREATE_HEADER_BYTES + ROLE_AND_KEY_BYTES * metaCount + 16,
	);
	create.addWritableSigner(accounts.sponsor);
	create.addWritable(accounts.crank);
	create.addWritable(accounts.magicVault);
	create.addReadonly(accounts.magicProgram);
	create.appendU8(HYDRA_CREATE);
	create.appendPubkey(seed);
	create.appendPubkey(accounts.sponsor.key());
	create.appendU64(dueSlot);
	create.appendU64(ONE_SHOT_INTERVAL_SLOTS);
	create.appendU64(1);
	create.appendU64(0);
	create.appendU32(CRANK_COMPUTE_UNITS);
	create.appendU8(metaCount as uint8);
	create.appendU8(16);
	create.appendU8(0);
	create.appendPubkey(programId());
	for (const meta of metas) {
		create.appendU8(meta.writable ? WRITABLE_ROLE : READONLY_ROLE);
		create.appendPubkey(meta.key);
	}
	create.appendU64(discriminator);
	create.appendU64(seq);
	return create.invokeSigned(sponsorSigner);
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
	sponsorSigner: Seeds,
	crank: Account,
	magicVault: Account,
	magicProgram: Account,
): Result<uint64, ProgramError> {
	const cancel = Instruction.forProgram(Pubkey.hydraProgram(), 5, 1);
	cancel.addWritableSigner(sponsor);
	cancel.addWritable(crank);
	cancel.addWritable(sponsor);
	cancel.addWritable(magicVault);
	cancel.addReadonly(magicProgram);
	cancel.appendU8(HYDRA_CANCEL);
	return cancel.invokeSigned(sponsorSigner);
}
