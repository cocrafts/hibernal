import { Discriminator, ProgramError, Pubkey, instructionDiscriminator, unchecked, SYSTEM_PROGRAM_ID, TOKEN_PROGRAM_ID, DELEGATION_PROGRAM_ID, findProgramAddressOf, ProgramAddress } from "std/solana";
import { HostAccount, invocations, run, setClock } from "std/solana/host";
import { BlockSlot, GlobalConfig, Insurance, OwnerItem, Pet, Region, born, ownerSlots } from "../../rules/index";
import { Config, HibernalError, Ledger, PetAccount, ShopItem, World, hibernalError } from "../layout";

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
const mint = keyOf(3);
const skrMint = keyOf(4);
const treasury = keyOf(5);
const source = keyOf(6);
const validator = keyOf(7);

const stagedPets: PetAccount[] = [];
const seenPets: PetAccount[] = [];
const stagedConfigs: Config[] = [];
const stagedWorlds: World[] = [];
const stagedLedgers: Ledger[] = [];
const seenLedgers: Ledger[] = [];

function overlay(): uint64 {
	const holder = unchecked(0);
	return holder.ok ? holder.value.data().address + 8 : 0;
}

function stagePetEntry(): void {
	const at = overlay() as Ptr<PetAccount>;
	at[] = stagedPets[stagedPets.length - 1];
}

function seePetEntry(): void {
	const at = overlay() as Ptr<PetAccount>;
	seenPets.push(at[]);
}

function stageConfigEntry(): void {
	const at = overlay() as Ptr<Config>;
	at[] = stagedConfigs[stagedConfigs.length - 1];
}

function stageWorldEntry(): void {
	const at = overlay() as Ptr<World>;
	at[] = stagedWorlds[stagedWorlds.length - 1];
}

function stageLedgerEntry(): void {
	const at = overlay() as Ptr<Ledger>;
	at[] = stagedLedgers[stagedLedgers.length - 1];
}

function seeLedgerEntry(): void {
	const at = overlay() as Ptr<Ledger>;
	seenLedgers.push(at[]);
}

function blankData(tag: Discriminator, size: uint64): uint8[] {
	const bytes: uint8[] = [];
	for (let i = 0; i < 8; i++) { bytes.push(tag.bytes[i]); }
	for (let offset: uint64 = 0; offset < size; offset++) { bytes.push(0); }
	return bytes;
}

function scratch(data: uint8[]): HostAccount[] {
	return [{
		key: keyOf(250),
		owner: programKey(),
		lamports: 1,
		data: data,
		signer: false,
		writable: true,
		executable: false,
	}];
}

function staged(tag: Discriminator, size: uint64, stage: () => void): uint8[] {
	const holder = scratch(blankData(tag, size));
	run(programKey(), holder, [], stage);
	return holder[0].data;
}

function petRecordOf(data: uint8[]): PetAccount {
	run(programKey(), scratch(data), [], seePetEntry);
	return seenPets[seenPets.length - 1];
}

function ledgerOf(data: uint8[]): Ledger {
	run(programKey(), scratch(data), [], seeLedgerEntry);
	return seenLedgers[seenLedgers.length - 1];
}

function address(found: Result<ProgramAddress, ProgramError>): Pubkey {
	return found.ok ? found.value.key : Pubkey.zero();
}

function bumpOf(found: Result<ProgramAddress, ProgramError>): uint8 {
	return found.ok ? found.value.bump : 0;
}

function petKey(): Pubkey { return address(findProgramAddressOf(programKey(), ["pet", mint])); }

function account(key: Pubkey, programOwner: Pubkey, data: uint8[], lamports: uint64): HostAccount {
	return { key: key, owner: programOwner, lamports: lamports, data: data, signer: false, writable: true, executable: false };
}

function executable(key: Pubkey): HostAccount {
	return { ...account(key, keyOf(0), [], 1), writable: false, executable: true };
}

function signerOf(key: Pubkey): HostAccount {
	return { ...account(key, SYSTEM_PROGRAM_ID, [], 10_000_000_000), signer: true };
}

function blank(key: Pubkey): HostAccount {
	return account(key, SYSTEM_PROGRAM_ID, [], 0);
}

function newborn(): Pet {
	return Pet.born(0, BlockSlot.First, Region.Worker, 1, GlobalConfig.genesis(0)).pet;
}

function petRecord(pet: Pet): PetAccount {
	return {
		owner: owner,
		mint: mint,
		ordinal: 0,
		persona: 0,
		bump: bumpOf(findProgramAddressOf(programKey(), ["pet", mint])),
		pad: 0,
		claimedEpoch: 1,
		diedEpoch: 0,
		pet: pet,
	};
}

function petHolder(pet: Pet, programOwner: Pubkey): HostAccount {
	stagedPets.push(petRecord(pet));
	return account(petKey(), programOwner, staged(PetAccount.discriminator(), sizeof(PetAccount) as uint64, stagePetEntry), 1_000_000);
}

function configHolder(): HostAccount {
	stagedConfigs.push({
		authority: keyOf(9),
		admissionGroup: keyOf(10),
		hbrnMint: keyOf(11),
		engine: 0,
		genesisTimestamp: 0,
		claimCapPerDay: 0,
		blocks: 1,
		pets: 1,
		bump: bumpOf(findProgramAddressOf(programKey(), ["config"])),
		mintBump: 0,
		policyBump: 0,
		worldBump: 0,
		pad: 0,
		validator: validator,
		skrMint: skrMint,
		treasury: treasury,
		vrfQueue: Pubkey.zero(),
		secondsPerDay: 86_400,
		staggerSeconds: 0,
		slotMillis: 10,
		turnGapSlots: 100,
	});
	const data = staged(Config.discriminator(), sizeof(Config) as uint64, stageConfigEntry);
	return { ...account(address(findProgramAddressOf(programKey(), ["config"])), programKey(), data, 1_000_000), writable: false };
}

function worldHolder(): HostAccount {
	stagedWorlds.push({
		global: GlobalConfig.genesis(0),
		epoch: 0,
		resortEvery: 0,
		rotation: 0,
		resortedEpoch: 0,
		bump: bumpOf(findProgramAddressOf(programKey(), ["world"])),
		resorting: 0,
		pad: 0,
		unplaced: 0,
		placed: 0,
		pad2: 0,
		secondsPerDay: 86_400,
	});
	const data = staged(World.discriminator(), sizeof(World) as uint64, stageWorldEntry);
	return { ...account(address(findProgramAddressOf(programKey(), ["world"])), programKey(), data, 1_000_000), writable: false };
}

function pushU64(bytes: uint8[], value: uint64): void {
	for (let shift: uint64 = 0; shift < 64; shift += 8) { bytes.push(((value >> shift) & 255) as uint8); }
}

function pushKey(bytes: uint8[], key: Pubkey): void {
	for (let i = 0; i < 32; i++) { bytes.push(key.bytes[i]); }
}

function zeros(bytes: uint8[], count: int32): void {
	for (let i = 0; i < count; i++) { bytes.push(0); }
}

function mintHolder(): HostAccount {
	const data: uint8[] = [];
	zeros(data, 36);
	pushU64(data, 1_000_000_000_000);
	data.push(6);
	data.push(1);
	zeros(data, 36);
	return account(skrMint, TOKEN_PROGRAM_ID, data, 1_461_600);
}

function tokenHolder(key: Pubkey, wallet: Pubkey, amount: uint64): HostAccount {
	const data: uint8[] = [];
	pushKey(data, skrMint);
	pushKey(data, wallet);
	pushU64(data, amount);
	zeros(data, 36);
	data.push(1);
	zeros(data, 56);
	return account(key, TOKEN_PROGRAM_ID, data, 2_039_280);
}

function amountOf(holder: HostAccount): uint64 {
	let value: uint64 = 0;
	for (let i = 71; i >= 64; i--) { value = (value << 8) | (holder.data[i] as uint64); }
	return value;
}

function instructionData(name: string): uint8[] {
	const discriminator = instructionDiscriminator(name);
	const bytes: uint8[] = [];
	for (let i = 0; i < 8; i++) { bytes.push(discriminator.bytes[i]); }
	return bytes;
}

function buyData(item: ShopItem, tier: uint8): uint8[] {
	const bytes = instructionData("Buy");
	bytes.push(item as uint8);
	bytes.push(tier);
	return bytes;
}

function ledgerKey(): Pubkey { return address(findProgramAddressOf(programKey(), ["ledger", mint])); }

function buyAccounts(buyer: Pubkey, skr: uint64): HostAccount[] {
	return [
		signerOf(buyer),
		configHolder(),
		petHolder(newborn(), DELEGATION_PROGRAM_ID),
		blank(ledgerKey()),
		{ ...mintHolder(), writable: false },
		tokenHolder(source, buyer, skr),
		tokenHolder(treasury, keyOf(12), 0),
		executable(TOKEN_PROGRAM_ID),
		executable(SYSTEM_PROGRAM_ID),
	];
}

function ledgerHolder(bought: uint32[], skin: uint8, ledgerMint: Pubkey): HostAccount {
	stagedLedgers.push({
		mint: ledgerMint,
		bought: [bought[0], bought[1], bought[2], bought[3], bought[4], bought[5], bought[6]],
		skin: skin,
		bump: bumpOf(findProgramAddressOf(programKey(), ["ledger", ledgerMint])),
		pad: 0,
	});
	const key = address(findProgramAddressOf(programKey(), ["ledger", ledgerMint]));
	const data = staged(Ledger.discriminator(), sizeof(Ledger) as uint64, stageLedgerEntry);
	return { ...account(key, programKey(), data, 1_000_000), writable: false };
}

function code(error: HibernalError): uint64 {
	return hibernalError(error).code;
}

function noon(seconds: int64): void {
	setClock({ slot: 1, epochStartTimestamp: 0, epoch: 1, leaderScheduleEpoch: 1, unixTimestamp: seconds });
}

test "buying food moves the price in SKR to the treasury and counts it in the pet's ledger" {
	const accounts = buyAccounts(owner, 20_000_000);
	assert run(programKey(), accounts, buyData(ShopItem.Food, 2), entry).result == 0;
	assert amountOf(accounts[5]) == 17_000_000;
	assert amountOf(accounts[6]) == 3_000_000;
	assert accounts[3].owner == programKey();
	assert ledgerOf(accounts[3].data).bought[2] == 1;
	assert run(programKey(), accounts, buyData(ShopItem.Growth, 1), entry).result == 0;
	assert run(programKey(), accounts, buyData(ShopItem.Food, 2), entry).result == 0;
	const ledger = ledgerOf(accounts[3].data);
	assert ledger.bought[2] == 2 && ledger.bought[4] == 1 && ledger.mint == mint;
	assert run(programKey(), accounts, buyData(ShopItem.Skin, 1), entry).result == 0;
	assert ledgerOf(accounts[3].data).skin == 2;
}

test "only the pet's owner can buy for it, and only with enough SKR" {
	const stolen = buyAccounts(stranger, 10_000_000);
	assert run(programKey(), stolen, buyData(ShopItem.Food, 0), entry).result == ProgramError.constraintHasOne().code;
	const poor = buyAccounts(owner, 500_000);
	assert run(programKey(), poor, buyData(ShopItem.Food, 0), entry).result != 0;
	assert amountOf(poor[6]) == 0;
	const unknown = buyAccounts(owner, 10_000_000);
	assert run(programKey(), unknown, buyData(ShopItem.Food, 3), entry).result == code(HibernalError.NoSuchFood);
	const bogus = instructionData("Buy");
	bogus.push(9);
	bogus.push(0);
	assert run(programKey(), unknown, bogus, entry).result == code(HibernalError.NoSuchItem);
}

test "loading moves paid items into the owner's two slots and leaves the rest waiting" {
	const accounts = [petHolder(newborn(), programKey()), ledgerHolder([0, 0, 3, 0, 1, 0, 0], 0, mint)];
	const load = instructionData("Load");
	assert run(programKey(), accounts, load, entry).result == 0;
	const record = petRecordOf(accounts[0].data);
	assert record.pet.ownerSlots().first == OwnerItem.LargeFood;
	assert record.pet.ownerSlots().second == OwnerItem.LargeFood;
	assert record.loaded[2] == 2 && record.loaded[4] == 0;
	assert run(programKey(), accounts, load, entry).result == 0;
	assert petRecordOf(accounts[0].data).loaded[2] == 2;
	stagedPets.push({ ...record, pet: record.pet.withSlots({ first: OwnerItem.None, second: OwnerItem.None }) });
	const eaten = [account(petKey(), programKey(), staged(PetAccount.discriminator(), sizeof(PetAccount) as uint64, stagePetEntry), 1_000_000), accounts[1]];
	assert run(programKey(), eaten, load, entry).result == 0;
	const refilled = petRecordOf(eaten[0].data);
	assert refilled.loaded[2] == 3 && refilled.loaded[4] == 1;
	assert refilled.pet.ownerSlots().first == OwnerItem.LargeFood;
	assert refilled.pet.ownerSlots().second == OwnerItem.MediumGrowth;
}

test "insurance from the ledger arms at once even when both slots are full, and the skin dresses the pet" {
	const accounts = [petHolder(newborn(), programKey()), ledgerHolder([2, 0, 0, 0, 0, 0, 1], 1, mint)];
	assert run(programKey(), accounts, instructionData("Load"), entry).result == 0;
	const record = petRecordOf(accounts[0].data);
	assert record.pet.insurance == (Insurance.Armed as uint8);
	assert record.loaded[6] == 1 && record.loaded[0] == 2;
	assert record.pet.ownerSlots().first == OwnerItem.SmallFood;
	assert record.pet.skin == 1;
}

test "a ledger only loads into its own pet" {
	const other = keyOf(77);
	const accounts = [petHolder(newborn(), programKey()), ledgerHolder([1, 0, 0, 0, 0, 0, 0], 0, other)];
	assert run(programKey(), accounts, instructionData("Load"), entry).result == ProgramError.constraintSeeds().code;
	assert petRecordOf(accounts[0].data).loaded[0] == 0;
}

function withdrawData(amount: uint64): uint8[] {
	const bytes = instructionData("WithdrawRevenue");
	pushU64(bytes, amount);
	return bytes;
}

function withdrawAccounts(signer: Pubkey, vaultOwner: Pubkey): HostAccount[] {
	const revenue = address(findProgramAddressOf(programKey(), ["revenue"]));
	return [
		signerOf(signer),
		{ ...configHolder(), writable: true },
		account(revenue, SYSTEM_PROGRAM_ID, [], 0),
		tokenHolder(treasury, vaultOwner, 50_000_000),
		{ ...mintHolder(), writable: false },
		tokenHolder(keyOf(12), keyOf(9), 0),
		executable(TOKEN_PROGRAM_ID),
	];
}

test "only the authority withdraws SKR revenue, and only out of the program's vault" {
	const accounts = withdrawAccounts(keyOf(9), address(findProgramAddressOf(programKey(), ["revenue"])));
	assert run(programKey(), accounts, withdrawData(20_000_000), entry).result == 0;
	assert amountOf(accounts[3]) == 30_000_000 && amountOf(accounts[5]) == 20_000_000;
	const strangers = withdrawAccounts(stranger, address(findProgramAddressOf(programKey(), ["revenue"])));
	assert run(programKey(), strangers, withdrawData(1), entry).result == code(HibernalError.NotAuthority);
	const elsewhere = withdrawAccounts(keyOf(9), address(findProgramAddressOf(programKey(), ["revenue"])));
	elsewhere[3] = tokenHolder(keyOf(13), address(findProgramAddressOf(programKey(), ["revenue"])), 50_000_000);
	assert run(programKey(), elsewhere, withdrawData(1), entry).result == code(HibernalError.WrongTreasury);
	assert amountOf(elsewhere[3]) == 50_000_000;
}
