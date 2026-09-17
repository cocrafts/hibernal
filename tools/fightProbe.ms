import { Combatant, Outcome, fight } from "../rules/index";
import {
	Account,
	Bytes,
	ProgramError,
	Pubkey,
	Seeds,
	account,
	accountCount,
	signerAccount,
	instructionData,
	programId,
	createProgramAccount,
	failWith,
	logComputeUnits,
	clock,
} from "std/solana";
import {
	DelegationAccounts,
	DelegationConfig,
	anyValidator,
	onValidator,
	delegate,
	commit,
	commitAndUndelegate,
	undelegate,
	isUndelegateCallback,
	scheduleTask,
} from "std/solana/magicblock";
import { RandomnessRequest, requestRandomness, verifyVrfCallback } from "std/solana/vrf";

struct Matchup {
	attacker: Combatant;
	defender: Combatant;
}

function arenaSeeds(owner: Account): Seeds {
	return Seeds.empty(2).addText("arena").addAccountKey(owner);
}

function verifiedArenaBump(owner: Account, arena: Account): Result<uint8, ProgramError> {
	const expected = try arenaSeeds(owner).findProgramAddress(programId());
	if (!expected.key.equals(arena.key())) { return Result.err(ProgramError.invalidSeeds()); }
	return Result.ok(expected.bump);
}

function ownedArena(index: int32): Result<Account, ProgramError> {
	const arena = try account(index);
	if (!arena.isOwnedBy(programId())) { return Result.err(ProgramError.illegalOwner()); }
	return Result.ok(arena);
}

function readMatchup(data: Bytes, offset: uint64): Result<Matchup, ProgramError> {
	const attackerMight = try data.readU32(offset);
	const attackerGrit = try data.readU32(offset + 4);
	const attackerHearts = try data.readU32(offset + 8);
	const defenderMight = try data.readU32(offset + 12);
	const defenderGrit = try data.readU32(offset + 16);
	const defenderHearts = try data.readU32(offset + 20);
	const matchup: Matchup = {
		attacker: Combatant.plain(attackerMight as int32, attackerGrit as int32, attackerHearts as int32),
		defender: Combatant.plain(defenderMight as int32, defenderGrit as int32, defenderHearts as int32),
	};
	return Result.ok(matchup);
}

function outcomeByte(outcome: Outcome): uint8 {
	return match (outcome) {
		Outcome.AttackerWins => 1,
		Outcome.DefenderWins => 0,
	};
}

function nonNegative(value: int32): uint32 {
	if (value < 0) { return 0; }
	return value as uint32;
}

function recordFight(arena: Account, matchup: Matchup, seed: uint64, mode: uint8): Result<uint64, ProgramError> {
	logComputeUnits();
	const result = matchup.attacker.fight(matchup.defender, seed);
	logComputeUnits();
	const stored = arena.data();
	const fights = try stored.readU64(0);
	const _count = try stored.writeU64(0, fights + 1);
	const _seed = try stored.writeU64(8, seed);
	const _outcome = try stored.writeU8(16, outcomeByte(result.outcome));
	const _rounds = try stored.writeU32(20, nonNegative(result.rounds));
	const _attackerHp = try stored.writeU32(24, nonNegative(result.attackerHp));
	const _defenderHp = try stored.writeU32(28, nonNegative(result.defenderHp));
	const _mode = try stored.writeU8(40, mode);
	return Result.ok(fights + 1);
}

function initializeArena(): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const arena = try account(1);
	const bump = try verifiedArenaBump(payer, arena);
	if (arena.lamports() == 0) {
		const _created = try createProgramAccount(payer, arena, 64, programId(), arenaSeeds(payer).withBump(bump));
	}
	arena.data().fillWith(0);
	return Result.ok(0);
}

function fightDirect(data: Bytes): Result<uint64, ProgramError> {
	const _payer = try signerAccount(0);
	const arena = try ownedArena(1);
	const matchup = try readMatchup(data, 8);
	const seed = try data.readU64(32);
	return recordFight(arena, matchup, seed, 0);
}

function delegateArena(): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const systemProgram = try account(1);
	const arena = try account(2);
	const ownerProgram = try account(3);
	const buffer = try account(4);
	const delegationRecord = try account(5);
	const delegationMetadata = try account(6);
	const bump = try verifiedArenaBump(payer, arena);
	let config = DelegationConfig.anyValidator();
	if (accountCount() > 8) {
		const validator = try account(8);
		config = DelegationConfig.onValidator(validator.key());
	}
	const accounts: DelegationAccounts = {
		payer: payer,
		delegated: arena,
		ownerProgram: ownerProgram,
		buffer: buffer,
		delegationRecord: delegationRecord,
		delegationMetadata: delegationMetadata,
		systemProgram: systemProgram,
	};
	return delegate(accounts, arenaSeeds(payer), bump, config);
}

function commitArena(andUndelegate: boolean): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const arena = try account(1);
	const magicContext = try account(3);
	if (andUndelegate) { return commitAndUndelegate(payer, arena, magicContext); }
	return commit(payer, arena, magicContext);
}

function requestFight(data: Bytes): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const arena = try ownedArena(1);
	const oracleQueue = try account(2);
	const programIdentity = try account(3);
	const slotHashes = try account(5);
	const systemProgram = try account(6);
	const clientSeed = try data.readU8(32);
	const callbackArguments = try data.range(8, 24);
	const callerSeed: Pubkey = { word0: clientSeed as uint64, word1: clock().slot, word2: 0, word3: 0 };
	const request: RandomnessRequest = {
		payer: payer,
		programIdentity: programIdentity,
		oracleQueue: oracleQueue,
		systemProgram: systemProgram,
		slotHashes: slotHashes,
	};
	const callbackDiscriminator: uint64 = 6;
	return requestRandomness(request, callerSeed, callbackDiscriminator, arena, callbackArguments);
}

function fightCallback(data: Bytes): Result<uint64, ProgramError> {
	const identity = try account(0);
	const _verified = try verifyVrfCallback(identity);
	const arena = try ownedArena(1);
	const seed = try data.readU64(8);
	const matchup = try readMatchup(data, 40);
	return recordFight(arena, matchup, seed, 1);
}

function scheduleCrankFights(data: Bytes): Result<uint64, ProgramError> {
	const payer = try signerAccount(0);
	const arena = try ownedArena(1);
	const taskId = try data.readU64(8);
	const intervalMillis = try data.readU64(16);
	const iterations = try data.readU64(24);
	const crankData = try data.range(32, 8);
	return scheduleTask(payer, taskId, intervalMillis, iterations, arena, crankData, programId());
}

function crankFight(): Result<uint64, ProgramError> {
	const arena = try ownedArena(0);
	const matchup: Matchup = { attacker: Combatant.plain(80, 50, 5), defender: Combatant.plain(50, 80, 5) };
	return recordFight(arena, matchup, clock().slot, 2);
}

function undelegateArena(data: Bytes): Result<uint64, ProgramError> {
	const delegated = try account(0);
	const buffer = try account(1);
	const payer = try account(2);
	return undelegate(delegated, buffer, payer, programId(), data);
}

function dispatch(): Result<uint64, ProgramError> {
	const data = instructionData();
	if (isUndelegateCallback(data)) { return undelegateArena(data); }
	const discriminator = try data.readU64(0);
	return match (discriminator) {
		0 => initializeArena(),
		1 => fightDirect(data),
		2 => delegateArena(),
		3 => commitArena(true),
		4 => commitArena(false),
		5 => requestFight(data),
		6 => fightCallback(data),
		7 => scheduleCrankFights(data),
		8 => crankFight(),
		_ => Result.err(ProgramError.invalidInstructionData()),
	};
}

function main(): void {
	const outcome = dispatch();
	if (!outcome.ok) { failWith(outcome.error); }
}

main();
