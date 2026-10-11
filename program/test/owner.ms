import { ProgramError, Pubkey, accountDiscriminator, decode, encode, instructionDiscriminator, SYSTEM_PROGRAM_ID, findProgramAddressOf } from "std/solana";
import { HostAccount, run, setClock } from "std/solana/host";
import { BlockSlot, GlobalConfig, Pet, Region, born } from "../../rules/index";
import { HibernalError, PetAccount, World, hibernalError } from "../layout";
import { entry } from "../main";
import { sessionKeysProgram } from "../owner";

function keyOf(seed: uint8): Pubkey {
	let key = Pubkey.zero();
	key.bytes[0] = seed;
	key.bytes[1] = 0x5a;
	return key;
}

function programKey(): Pubkey { return keyOf(200); }

const owner = keyOf(1);
const stranger = keyOf(2);
const mint = keyOf(3);

function petBytes(record: PetAccount): uint8[] {
	const encoded = encode(record);
	if (!encoded.ok) { unreachable; }
	return encoded.value;
}

function petRecordOf(data: uint8[]): PetAccount {
	const decoded = decode<PetAccount>(data);
	if (!decoded.ok) { unreachable; }
	return decoded.value;
}

function petKey(): Pubkey {
	const found = findProgramAddressOf(programKey(), ["pet", mint]);
	return found.ok ? found.value.key : Pubkey.zero();
}

function petBump(): uint8 {
	const found = findProgramAddressOf(programKey(), ["pet", mint]);
	return found.ok ? found.value.bump : 0;
}

function newborn(): Pet {
	return Pet.born(0, BlockSlot.First, Region.Worker, 1, GlobalConfig.genesis(0)).pet;
}

function record(pet: Pet): PetAccount {
	return {
		owner: owner,
		mint: mint,
		ordinal: 0,
		persona: 0,
		bump: petBump(),
		pad: 0,
		claimedEpoch: 1,
		diedEpoch: 0,
		pet: pet,
	};
}

function petHolder(pet: Pet): HostAccount {
	return {
		key: petKey(),
		owner: programKey(),
		lamports: 1000000,
		data: petBytes(record(pet)),
		signer: false,
		writable: true,
		executable: false,
	};
}

function worldHolder(genesis: uint64, secondsPerDay: uint64): HostAccount {
	const encoded = encode<World>({
		global: GlobalConfig.genesis(genesis),
		epoch: 0,
		resortEvery: 0,
		rotation: 0,
		resortedEpoch: 0,
		bump: 0,
		resorting: 0,
		pad: 0,
		unplaced: 0,
		placed: 0,
		pad2: 0,
		secondsPerDay: secondsPerDay,
	});
	if (!encoded.ok) { unreachable; }
	return {
		key: keyOf(60),
		owner: programKey(),
		lamports: 1,
		data: encoded.value,
		signer: false,
		writable: false,
		executable: false,
	};
}

function realDay(): HostAccount {
	return worldHolder(0, 86_400);
}

function signerOf(key: Pubkey): HostAccount {
	return {
		key: key,
		owner: SYSTEM_PROGRAM_ID,
		lamports: 1000000000,
		data: [],
		signer: true,
		writable: false,
		executable: false,
	};
}

function instructionData(name: string): uint8[] {
	const discriminator = instructionDiscriminator(name);
	const bytes: uint8[] = [];
	for (let i = 0; i < 8; i++) { bytes.push(discriminator.bytes[i]); }
	return bytes;
}

function petOf(holder: HostAccount): Pet {
	return petRecordOf(holder.data).pet;
}

function code(error: HibernalError): uint64 {
	return hibernalError(error).code;
}

function noon(seconds: int64): void {
	setClock({ slot: 1, epochStartTimestamp: 0, epoch: 1, leaderScheduleEpoch: 1, unixTimestamp: seconds });
}

const sessionSigner = keyOf(4);
const ROUND_SECONDS: int64 = 21_600;

function sessionKey(signer: Pubkey, authority: Pubkey): Pubkey {
	const found = findProgramAddressOf(Pubkey.sessionKeysProgram(), ["session_token_v2", programKey(), signer, authority]);
	return found.ok ? found.value.key : Pubkey.zero();
}

function sessionHolder(target: Pubkey, signer: Pubkey, validUntil: uint64): HostAccount {
	const kind = accountDiscriminator("SessionTokenV2");
	const bytes: uint8[] = [];
	for (let i = 0; i < 8; i++) { bytes.push(kind.bytes[i]); }
	for (let i = 0; i < 32; i++) { bytes.push(owner.bytes[i]); }
	for (let i = 0; i < 32; i++) { bytes.push(target.bytes[i]); }
	for (let i = 0; i < 32; i++) { bytes.push(signer.bytes[i]); }
	for (let i = 0; i < 32; i++) { bytes.push(owner.bytes[i]); }
	for (let i = 0; i < 8; i++) { bytes.push(((validUntil >> ((i * 8) as uint64)) & 0xff) as uint8); }
	return {
		key: sessionKey(signer, owner),
		owner: Pubkey.sessionKeysProgram(),
		lamports: 1000000,
		data: bytes,
		signer: false,
		writable: false,
		executable: false,
	};
}

function noSession(): HostAccount {
	return { ...signerOf(programKey()), signer: false };
}

test "only the pet's owner or its session key can engage or bank" {
	noon(10);
	const accounts = [signerOf(stranger), petHolder({ ...newborn(), hearts: 1 }), realDay(), noSession()];
	assert run(programKey(), accounts, instructionData("Engage"), entry).result == code(HibernalError.NotTheOwner);
	const unsigned: HostAccount[] = [{ ...signerOf(owner), signer: false }, petHolder(newborn()), realDay(), noSession()];
	assert run(programKey(), unsigned, instructionData("Engage"), entry).result ==
		ProgramError.accountNotSigner().code;
	const banking = [signerOf(stranger), petHolder({ ...newborn(), harvest: 1000 }), realDay(), noSession()];
	assert run(programKey(), banking, instructionData("Bank"), entry).result == code(HibernalError.NotTheOwner);
}

test "engaging bonds once a round, three times a day" {
	const accounts = [signerOf(owner), petHolder(newborn()), realDay(), noSession()];
	noon(10);
	assert run(programKey(), accounts, instructionData("Engage"), entry).result == 0;
	noon(ROUND_SECONDS - 1);
	assert run(programKey(), accounts, instructionData("Engage"), entry).result == code(HibernalError.EngagedThisRound);
	noon(ROUND_SECONDS);
	assert run(programKey(), accounts, instructionData("Engage"), entry).result == 0;
	noon(3 * ROUND_SECONDS);
	assert run(programKey(), accounts, instructionData("Engage"), entry).result == 0;
	const engaged = petOf(accounts[1]);
	assert engaged.engagedToday == 3 && engaged.engagedRound == 3;
	noon(4 * ROUND_SECONDS - 1);
	assert run(programKey(), accounts, instructionData("Engage"), entry).result == code(HibernalError.EngagedOut);
}

test "a session key engages without the owner's wallet until it expires" {
	noon(1_000);
	const live = [signerOf(sessionSigner), petHolder(newborn()), realDay(), sessionHolder(programKey(), sessionSigner, 2_000)];
	assert run(programKey(), live, instructionData("Engage"), entry).result == 0;
	assert petOf(live[1]).engagedToday == 1;
	const expired = [signerOf(sessionSigner), petHolder(newborn()), realDay(), sessionHolder(programKey(), sessionSigner, 1_000)];
	assert run(programKey(), expired, instructionData("Engage"), entry).result == code(HibernalError.SessionExpired);
	const otherProgram = [signerOf(sessionSigner), petHolder(newborn()), realDay(), sessionHolder(keyOf(9), sessionSigner, 2_000)];
	assert run(programKey(), otherProgram, instructionData("Engage"), entry).result == code(HibernalError.NotTheOwner);
	const borrowed = [signerOf(stranger), petHolder(newborn()), realDay(), sessionHolder(programKey(), sessionSigner, 2_000)];
	assert run(programKey(), borrowed, instructionData("Engage"), entry).result == code(HibernalError.NotTheOwner);
	const forged: HostAccount = { ...sessionHolder(programKey(), sessionSigner, 2_000), owner: programKey() };
	const unowned = [signerOf(sessionSigner), petHolder(newborn()), realDay(), forged];
	assert run(programKey(), unowned, instructionData("Engage"), entry).result == code(HibernalError.NotTheOwner);
	const misplaced: HostAccount = { ...sessionHolder(programKey(), sessionSigner, 2_000), key: keyOf(61) };
	const elsewhere = [signerOf(sessionSigner), petHolder(newborn()), realDay(), misplaced];
	assert run(programKey(), elsewhere, instructionData("Engage"), entry).result == code(HibernalError.NotTheOwner);
}

test "banking moves half the harvest to the burrow, then cools down" {
	noon(1_000_000);
	const rich: Pet = { ...newborn(), harvest: 1000, burrow: 0 };
	const accounts = [signerOf(owner), petHolder(rich), realDay(), noSession()];
	assert run(programKey(), accounts, instructionData("Bank"), entry).result == 0;
	const banked = petOf(accounts[1]);
	assert banked.harvest == 500 && banked.burrow == 500 && banked.ownerBankReadyAt == 1_028_800;
	assert run(programKey(), accounts, instructionData("Bank"), entry).result == code(HibernalError.CoolingDown);
	const empty = [signerOf(owner), petHolder({ ...newborn(), harvest: 0 }), realDay(), noSession()];
	assert run(programKey(), empty, instructionData("Bank"), entry).result == code(HibernalError.EmptyHarvest);
}

test "a session key banks without the owner's wallet" {
	noon(1_000_000);
	const rich: Pet = { ...newborn(), harvest: 1000, burrow: 0 };
	const accounts = [signerOf(sessionSigner), petHolder(rich), realDay(), sessionHolder(programKey(), sessionSigner, 2_000_000)];
	assert run(programKey(), accounts, instructionData("Bank"), entry).result == 0;
	assert petOf(accounts[1]).burrow == 500;
	const borrowed = [signerOf(stranger), petHolder(rich), realDay(), sessionHolder(programKey(), sessionSigner, 2_000_000)];
	assert run(programKey(), borrowed, instructionData("Bank"), entry).result == code(HibernalError.NotTheOwner);
}

test "a dead pet cannot be engaged" {
	const accounts = [signerOf(owner), petHolder({ ...newborn(), alive: false, hearts: 0 }), realDay(), noSession()];
	assert run(programKey(), accounts, instructionData("Engage"), entry).result == code(HibernalError.Dead);
}

test "on a compressed day the bank cooldown runs in game time: 8 game hours are 400 wall seconds at 1,200 s a day" {
	const genesis: uint64 = 1_700_000_000;
	const rich: Pet = { ...newborn(), harvest: 1000, burrow: 0 };
	const accounts = [signerOf(owner), petHolder(rich), worldHolder(genesis, 1_200), noSession()];
	noon((genesis + 1_000) as int64);
	assert run(programKey(), accounts, instructionData("Bank"), entry).result == 0;
	assert petOf(accounts[1]).ownerBankReadyAt == 100_800;
	noon((genesis + 1_399) as int64);
	assert run(programKey(), accounts, instructionData("Bank"), entry).result == code(HibernalError.CoolingDown);
	noon((genesis + 1_400) as int64);
	assert run(programKey(), accounts, instructionData("Bank"), entry).result == 0;
	const twice = petOf(accounts[1]);
	assert twice.ownerBankReadyAt == 129_600 && twice.harvest == 250 && twice.burrow == 750;
}
