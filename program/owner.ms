import {
	Account,
	Discriminator,
	Mutable,
	Owned,
	ProgramError,
	Pubkey,
	Signer,
	accountDiscriminator,
	clock,
	programId,
	pubkeyOf,
	findProgramAddressOf,
	pdaWithBump,
} from "std/solana";
import { accounts } from "std/solana";
import {
	OwnerError,
	engagedAt,
	ownerBanked,
} from "../rules/index";
import {
	HibernalError,
	PetAccount,
	World,
	gameSecondsAt,
	hibernalError,
} from "./layout";

export const SESSION_TOKEN_SIZE: uint64 = 144;
export const SESSION_AUTHORITY: uint64 = 8;
export const SESSION_TARGET_PROGRAM: uint64 = 40;
export const SESSION_SIGNER: uint64 = 72;
export const SESSION_VALID_UNTIL: uint64 = 136;

export struct SessionAccounts {
	signer: Signer;
	pet: Mutable<PetAccount>;
	world: Owned<World>;
	session: Account;
}

export function sessionKeysProgram(this typeof Pubkey): Pubkey {
	return @comptime { return pubkeyOf("KeyspM2ssCJbqUhQ4k7sveSiY4WjnYsrXkC8oDbwde5"); };
}

function sessionTokenKind(): Discriminator {
	return @comptime { return accountDiscriminator("SessionTokenV2"); };
}

export function ownerFailure(error: OwnerError): ProgramError {
	const mapped: HibernalError = match (error) {
		OwnerError.Dead => HibernalError.Dead,
		OwnerError.Refused => HibernalError.Refused,
		OwnerError.EngagedOut => HibernalError.EngagedOut,
		OwnerError.EngagedThisRound => HibernalError.EngagedThisRound,
		OwnerError.NoSuchTier => HibernalError.Illegal,
		OwnerError.EmptyHarvest => HibernalError.EmptyHarvest,
		OwnerError.CoolingDown => HibernalError.CoolingDown,
		OwnerError.SlotsFull => HibernalError.SlotsFull,
	};
	return hibernalError(mapped);
}

function sessionOf(session: Account, signer: Pubkey, owner: Pubkey, now: int64): Result<uint64, ProgramError> {
	if (!session.isOwnedBy(Pubkey.sessionKeysProgram()) || session.dataLength() < SESSION_TOKEN_SIZE) {
		return Result.err(hibernalError(HibernalError.NotTheOwner));
	}
	const data = session.data();
	const kind = try data.readU64(0);
	const authority = try data.readPubkey(SESSION_AUTHORITY);
	const target = try data.readPubkey(SESSION_TARGET_PROGRAM);
	const sessionSigner = try data.readPubkey(SESSION_SIGNER);
	const validUntil = try data.readU64(SESSION_VALID_UNTIL);
	if (kind != sessionTokenKind().word() || authority != owner || target != programId() || sessionSigner != signer) {
		return Result.err(hibernalError(HibernalError.NotTheOwner));
	}
	if (now >= validUntil as int64) { return Result.err(hibernalError(HibernalError.SessionExpired)); }
	const program = programId();
	const found = try findProgramAddressOf(Pubkey.sessionKeysProgram(), ["session_token_v2", program, signer, owner]);
	if (found.key != session.key()) { return Result.err(hibernalError(HibernalError.NotTheOwner)); }
	return Result.ok(0);
}

function ownerOrSession(x: SessionAccounts, unix: int64): Result<Ptr<PetAccount>, ProgramError> {
	const record = x.pet.data();
	const _seeds = try pdaWithBump(x.pet, ["pet", record.mint], record.bump);
	if (x.signer.key() != record.owner) {
		const _session = try sessionOf(x.session, x.signer.key(), record.owner, unix);
	}
	return Result.ok(record);
}

export function engage(): Result<uint64, ProgramError> {
	const x = try accounts<SessionAccounts>();
	const unix = clock().unixTimestamp;
	const record = try ownerOrSession(x, unix);
	const world = x.world.data();
	const now = gameSecondsAt(world.global.genesisTimestamp, world.secondsPerDay, unix);
	const engaged = record.pet.engagedAt(now);
	if (!engaged.ok) { return Result.err(ownerFailure(engaged.error)); }
	record.pet = engaged.value;
	return Result.ok(0);
}

export function bank(): Result<uint64, ProgramError> {
	const x = try accounts<SessionAccounts>();
	const unix = clock().unixTimestamp;
	const record = try ownerOrSession(x, unix);
	const world = x.world.data();
	const now = gameSecondsAt(world.global.genesisTimestamp, world.secondsPerDay, unix);
	const banked = record.pet.ownerBanked(now);
	if (!banked.ok) { return Result.err(ownerFailure(banked.error)); }
	record.pet = banked.value;
	return Result.ok(0);
}

