import { Discriminator, ProgramError, Pubkey, instructionDiscriminator, unchecked } from "std/solana";
import { HostAccount, invocations, run, setClock } from "std/solana/host";
import { delegationProgram, magicContext, magicProgram } from "std/solana/magicblock";
import { BlockSlot, GlobalConfig, Pet, Region, born } from "../../rules/index";
import {
	Config,
	HibernalError,
	Paid,
	PetAccount,
	configSeeds,
	hibernalError,
	mintSeeds,
	paidSeeds,
	petSeeds,
} from "../layout";
import { entry } from "../main";

function keyOf(seed: uint8): Pubkey {
	let key = Pubkey.zero();
	key.bytes[0] = seed;
	key.bytes[1] = 0x5a;
	return key;
}

function programKey(): Pubkey { return keyOf(200); }

const owner = keyOf(1);
const stranger = keyOf(2);
const admission = keyOf(3);
const DAY: int64 = 86_400;
const CAP: uint64 = 10_000_000;

const stagedPets: PetAccount[] = [];
const stagedConfigs: Config[] = [];
const seenLedgers: Paid[] = [];

function overlay(): uint64 {
	const holder = unchecked(0);
	return holder.ok ? holder.value.data().address + 8 : 0;
}

function stagePetEntry(): void {
	const at = overlay() as Ptr<PetAccount>;
	at[] = stagedPets[stagedPets.length - 1];
}

function stageConfigEntry(): void {
	const at = overlay() as Ptr<Config>;
	at[] = stagedConfigs[stagedConfigs.length - 1];
}

function seeLedgerEntry(): void {
	const at = overlay() as Ptr<Paid>;
	seenLedgers.push(at[]);
}

function blankData(tag: Discriminator, size: uint64): uint8[] {
	const bytes: uint8[] = [];
	for (let i = 0; i < 8; i++) { bytes.push(tag.bytes[i]); }
	for (let offset: uint64 = 0; offset < size; offset++) { bytes.push(0); }
	return bytes;
}

function holderOf(key: Pubkey, owner: Pubkey, data: uint8[]): HostAccount {
	return {
		key: key,
		owner: owner,
		lamports: 1000000,
		data: data,
		signer: false,
		writable: true,
		executable: false,
	};
}

function scratch(data: uint8[]): HostAccount[] {
	return [holderOf(keyOf(250), programKey(), data)];
}

struct Address {
	key: Pubkey;
	bump: uint8;
}

function petAddress(): Address {
	const found = petSeeds(admission).findProgramAddress(programKey());
	if (!found.ok) { return { key: Pubkey.zero(), bump: 0 }; }
	return { key: found.value.key, bump: found.value.bump };
}

function mintAddress(): Address {
	const found = mintSeeds().findProgramAddress(programKey());
	if (!found.ok) { return { key: Pubkey.zero(), bump: 0 }; }
	return { key: found.value.key, bump: found.value.bump };
}

function paidAddress(): Pubkey {
	const found = paidSeeds(admission).findProgramAddress(programKey());
	return found.ok ? found.value.key : Pubkey.zero();
}

function configAddress(): Pubkey {
	const found = configSeeds().findProgramAddress(programKey());
	return found.ok ? found.value.key : Pubkey.zero();
}

function petHolder(gifted: uint64, holderOwner: Pubkey): HostAccount {
	const pet: Pet = { ...Pet.born(0, BlockSlot.First, Region.Worker, 1, GlobalConfig.genesis(0)).pet, giftOwed: gifted };
	const record: PetAccount = {
		owner: owner,
		mint: admission,
		ordinal: 0,
		persona: 0,
		bump: petAddress().bump,
		pad: 0,
		claimedEpoch: 1,
		diedEpoch: 0,
		pet: pet,
	};
	stagedPets.push(record);
	const holder = scratch(blankData(PetAccount.discriminator(), sizeof(PetAccount) as uint64));
	run(programKey(), holder, [], stagePetEntry);
	return holderOf(petAddress().key, holderOwner, holder[0].data);
}

function configHolder(mint: Pubkey): HostAccount {
	const config: Config = {
		authority: keyOf(9),
		admissionGroup: keyOf(8),
		hbrnMint: mint,
		engine: 1,
		genesisTimestamp: 0,
		claimCapPerDay: CAP,
		blocks: 0,
		pets: 0,
		bump: 0,
		mintBump: mintAddress().bump,
		policyBump: 0,
		worldBump: 0,
		pad: 0,
		validator: Pubkey.zero(),
		skrMint: Pubkey.zero(),
		treasury: Pubkey.zero(),
	};
	stagedConfigs.push(config);
	const staged = scratch(blankData(Config.discriminator(), sizeof(Config) as uint64));
	run(programKey(), staged, [], stageConfigEntry);
	return { ...holderOf(configAddress(), programKey(), staged[0].data), writable: false };
}

function pushKey(bytes: uint8[], key: Pubkey): void {
	for (let i = 0; i < 32; i++) { bytes.push(key.bytes[i]); }
}

function zeros(bytes: uint8[], count: int32): void {
	for (let i = 0; i < count; i++) { bytes.push(0); }
}

function mintHolder(key: Pubkey): HostAccount {
	const data: uint8[] = [1, 0, 0, 0];
	pushKey(data, key);
	zeros(data, 8);
	data.push(6);
	data.push(1);
	zeros(data, 36);
	return holderOf(key, Pubkey.tokenProgram(), data);
}

function tokenHolder(key: Pubkey, wallet: Pubkey, mint: Pubkey): HostAccount {
	const data: uint8[] = [];
	pushKey(data, mint);
	pushKey(data, wallet);
	zeros(data, 8);
	zeros(data, 36);
	data.push(1);
	zeros(data, 56);
	return holderOf(key, Pubkey.tokenProgram(), data);
}

function executable(key: Pubkey): HostAccount {
	return { ...holderOf(key, keyOf(0), []), writable: false, executable: true, lamports: 1 };
}

function wallet(key: Pubkey): HostAccount {
	return { ...holderOf(key, Pubkey.systemProgram(), []), signer: true, lamports: 10000000000 };
}

function blank(key: Pubkey): HostAccount {
	return { ...holderOf(key, Pubkey.systemProgram(), []), lamports: 0 };
}

function claimAccounts(gifted: uint64, petOwner: Pubkey): HostAccount[] {
	const mint = mintAddress().key;
	return [
		wallet(owner),
		configHolder(mint),
		petHolder(gifted, petOwner),
		blank(paidAddress()),
		mintHolder(mint),
		tokenHolder(keyOf(20), owner, mint),
		executable(Pubkey.tokenProgram()),
		executable(Pubkey.systemProgram()),
	];
}

function instructionData(name: string): uint8[] {
	const discriminator = instructionDiscriminator(name);
	const bytes: uint8[] = [];
	for (let i = 0; i < 8; i++) { bytes.push(discriminator.bytes[i]); }
	return bytes;
}

function u64At(data: uint8[], offset: int32): uint64 {
	let value: uint64 = 0;
	for (let i = offset + 7; i >= offset; i--) {
		const byte: uint64 = data[i] as uint64;
		value = (value << 8) | byte;
	}
	return value;
}

function ledgerOf(holder: HostAccount): Paid {
	run(programKey(), scratch(holder.data), [], seeLedgerEntry);
	return seenLedgers[seenLedgers.length - 1];
}

function code(error: HibernalError): uint64 {
	return hibernalError(error).code;
}

function dayClock(day: int64): void {
	setClock({ slot: 1, epochStartTimestamp: 0, epoch: 1, leaderScheduleEpoch: 1, unixTimestamp: day * DAY + 100 });
}

const claim = instructionData("ClaimReward");

test "a pet's gift mints HBRN to its owner and opens the ledger" {
	dayClock(20000);
	const accounts = claimAccounts(5_000_000, programKey());
	assert run(programKey(), accounts, claim, entry).result == 0;
	assert u64At(accounts[5].data, 64) == 5_000_000;
	assert u64At(accounts[4].data, 36) == 5_000_000;
	assert accounts[3].owner == programKey();
	const ledger = ledgerOf(accounts[3]);
	assert ledger.total == 5_000_000 && ledger.today == 5_000_000 && ledger.day == 20000;
	assert ledger.mint == admission;
	assert run(programKey(), accounts, claim, entry).result == code(HibernalError.NothingOwed);
}

test "a delegated pet's committed gift mints HBRN the same way" {
	dayClock(20000);
	const accounts = claimAccounts(1_000, Pubkey.delegationProgram());
	assert run(programKey(), accounts, claim, entry).result == 0;
	assert u64At(accounts[5].data, 64) == 1_000;
	assert ledgerOf(accounts[3]).total == 1_000;
	assert run(programKey(), accounts, claim, entry).result == code(HibernalError.NothingOwed);
}

test "a day's claims stop at the cap and resume the next day" {
	dayClock(20000);
	const accounts = claimAccounts(25_000_000, programKey());
	assert run(programKey(), accounts, claim, entry).result == 0;
	assert u64At(accounts[5].data, 64) == CAP;
	assert run(programKey(), accounts, claim, entry).result == code(HibernalError.OverCap);
	dayClock(20001);
	assert run(programKey(), accounts, claim, entry).result == 0;
	assert u64At(accounts[5].data, 64) == 2 * CAP;
	const ledger = ledgerOf(accounts[3]);
	assert ledger.total == 2 * CAP && ledger.today == CAP && ledger.day == 20001;
}

test "a claim is refused for a stranger, a foreign mint, another owner's wallet and a forged pet" {
	dayClock(20000);
	const strangers = claimAccounts(1_000, programKey());
	strangers[0] = wallet(stranger);
	assert run(programKey(), strangers, claim, entry).result == ProgramError.constraintHasOne().code;
	const foreign = claimAccounts(1_000, programKey());
	foreign[4] = mintHolder(keyOf(30));
	foreign[5] = tokenHolder(keyOf(20), owner, keyOf(30));
	assert run(programKey(), foreign, claim, entry).result == ProgramError.constraintAddress().code;
	const elsewhere = claimAccounts(1_000, programKey());
	elsewhere[5] = tokenHolder(keyOf(21), stranger, mintAddress().key);
	assert run(programKey(), elsewhere, claim, entry).result == ProgramError.constraintTokenOwner().code;
	const alien = claimAccounts(1_000, keyOf(77));
	assert run(programKey(), alien, claim, entry).result == ProgramError.accountOwnedByWrongProgram().code;
	const moved = claimAccounts(1_000, programKey());
	moved[2] = { ...moved[2], key: keyOf(40) };
	assert run(programKey(), moved, claim, entry).result == ProgramError.constraintSeeds().code;
	const movedDelegated = claimAccounts(1_000, Pubkey.delegationProgram());
	movedDelegated[2] = { ...movedDelegated[2], key: keyOf(40) };
	assert run(programKey(), movedDelegated, claim, entry).result == ProgramError.constraintSeeds().code;
}

test "the owner commits a pet through the magic program" {
	const accounts: HostAccount[] = [
		wallet(owner),
		petHolder(0, programKey()),
		holderOf(Pubkey.magicContext(), programKey(), []),
		executable(Pubkey.magicProgram()),
	];
	const commit = instructionData("CommitPet");
	assert run(programKey(), accounts, commit, entry).result == 0;
	const sent = invocations();
	const last = sent[sent.length - 1];
	assert last.program == Pubkey.magicProgram();
	assert last.accounts[0].key == owner && last.accounts[0].signer;
	assert last.accounts[2].key == petAddress().key && last.accounts[2].writable;
	const strangers = [wallet(stranger), accounts[1], accounts[2], accounts[3]];
	assert run(programKey(), strangers, commit, entry).result == ProgramError.constraintHasOne().code;
	const wrongContext = [accounts[0], accounts[1], holderOf(keyOf(41), programKey(), []), accounts[3]];
	assert run(programKey(), wrongContext, commit, entry).result == ProgramError.constraintAddress().code;
}
