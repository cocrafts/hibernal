import { Account, Clock, ProgramError, Pubkey, programId } from "std/solana";
import { MAGIC_PROGRAM_ID } from "std/solana/magicblock";
import { CrankAccounts, HYDRA_PROGRAM_ID, MAGIC_VAULT_ID, crankAddress } from "std/solana/hydra";

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

export function blockCrankAddress(sponsor: Pubkey, blockId: uint32, seq: uint64): Result<Pubkey, ProgramError> {
	return crankAddress(sponsor, crankSeed(blockId, seq));
}

export function dueSlotFor(now: Clock, targetUnix: int64, slotMillis: uint64): uint64 {
	if (targetUnix <= now.unixTimestamp) { return now.slot + 1; }
	const waitMillis = ((targetUnix - now.unixTimestamp) as uint64) * 1000;
	return now.slot + waitMillis / slotMillis;
}

export function checkedCrankAccounts(accounts: CrankAccounts, hydraProgram: Account, expected: Pubkey): Result<uint64, ProgramError> {
	if (hydraProgram.key() != HYDRA_PROGRAM_ID) { return Result.err(ProgramError.incorrectProgramId()); }
	if (accounts.magicProgram.key() != MAGIC_PROGRAM_ID) { return Result.err(ProgramError.incorrectProgramId()); }
	if (accounts.magicVault.key() != MAGIC_VAULT_ID) { return Result.err(ProgramError.invalidArgument()); }
	if (accounts.crank.key() != expected) { return Result.err(ProgramError.invalidSeeds()); }
	return Result.ok(0);
}
