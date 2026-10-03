import { Discriminator, ProgramError, Pubkey, Seeds, instructionDiscriminator, unchecked } from "std/solana";
import { HostAccount, invocations, run, setClock } from "std/solana/host";
import { BlockSlot, GROWTH_CAP_BPS, GlobalConfig, Insurance, Pet, Region, born } from "../../rules/index";
import {
	Config,
	HibernalError,
	PetAccount,
	Receipt,
	ShopItem,
	World,
	configSeeds,
	hibernalError,
	petSeeds,
	receiptSeeds,
	worldSeeds,
} from "../layout";
import { delegationProgram } from "std/solana/magicblock";
import { INSURANCE_NONCE_BASE } from "../shop";
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
const stagedReceipts: Receipt[] = [];
const seenReceipts: Receipt[] = [];

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

function stageReceiptEntry(): void {
	const at = overlay() as Ptr<Receipt>;
	at[] = stagedReceipts[stagedReceipts.length - 1];
}

function seeReceiptEntry(): void {
	const at = overlay() as Ptr<Receipt>;
	seenReceipts.push(at[]);
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

function receiptOf(data: uint8[]): Receipt {
	run(programKey(), scratch(data), [], seeReceiptEntry);
	return seenReceipts[seenReceipts.length - 1];
}

function address(seeds: Seeds): Pubkey {
	const found = seeds.findProgramAddress(programKey());
	return found.ok ? found.value.key : Pubkey.zero();
}

function bumpOf(seeds: Seeds): uint8 {
	const found = seeds.findProgramAddress(programKey());
	return found.ok ? found.value.bump : 0;
}

function petKey(): Pubkey { return address(petSeeds(mint)); }

function account(key: Pubkey, programOwner: Pubkey, data: uint8[], lamports: uint64): HostAccount {
	return { key: key, owner: programOwner, lamports: lamports, data: data, signer: false, writable: true, executable: false };
}

function executable(key: Pubkey): HostAccount {
	return { ...account(key, keyOf(0), [], 1), writable: false, executable: true };
}

function signerOf(key: Pubkey): HostAccount {
	return { ...account(key, Pubkey.systemProgram(), [], 10_000_000_000), signer: true };
}

function blank(key: Pubkey): HostAccount {
	return account(key, Pubkey.systemProgram(), [], 0);
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
		bump: bumpOf(petSeeds(mint)),
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
		bump: bumpOf(configSeeds()),
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
	return { ...account(address(configSeeds()), programKey(), data, 1_000_000), writable: false };
}

function worldHolder(): HostAccount {
	stagedWorlds.push({
		global: GlobalConfig.genesis(0),
		epoch: 0,
		resortEvery: 0,
		rotation: 0,
		resortedEpoch: 0,
		bump: bumpOf(worldSeeds()),
		resorting: 0,
		pad: 0,
		unplaced: 0,
		placed: 0,
		pad2: 0,
		secondsPerDay: 86_400,
	});
	const data = staged(World.discriminator(), sizeof(World) as uint64, stageWorldEntry);
	return { ...account(address(worldSeeds()), programKey(), data, 1_000_000), writable: false };
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
	return account(skrMint, Pubkey.tokenProgram(), data, 1_461_600);
}

function tokenHolder(key: Pubkey, wallet: Pubkey, amount: uint64): HostAccount {
	const data: uint8[] = [];
	pushKey(data, skrMint);
	pushKey(data, wallet);
	pushU64(data, amount);
	zeros(data, 36);
	data.push(1);
	zeros(data, 56);
	return account(key, Pubkey.tokenProgram(), data, 2_039_280);
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

function buyData(item: ShopItem, tier: uint8, nonce: uint64): uint8[] {
	const bytes = instructionData("Buy");
	bytes.push(item as uint8);
	bytes.push(tier);
	pushU64(bytes, nonce);
	return bytes;
}

function bufferKey(delegated: Pubkey): Pubkey {
	return address(Seeds.empty(2).addText("buffer").addPubkey(delegated));
}

function buyAccounts(buyer: Pubkey, receipt: Pubkey, skr: uint64): HostAccount[] {
	return [
		signerOf(buyer),
		configHolder(),
		petHolder(newborn(), Pubkey.delegationProgram()),
		{ ...mintHolder(), writable: false },
		tokenHolder(source, buyer, skr),
		tokenHolder(treasury, keyOf(12), 0),
		blank(receipt),
		executable(programKey()),
		blank(bufferKey(receipt)),
		blank(keyOf(13)),
		blank(keyOf(14)),
		executable(Pubkey.delegationProgram()),
		executable(Pubkey.tokenProgram()),
		executable(Pubkey.systemProgram()),
	];
}

function receiptHolder(item: ShopItem, tier: uint8, nonce: uint64, pet: Pubkey): HostAccount {
	stagedReceipts.push({
		pet: pet,
		owner: owner,
		nonce: nonce,
		price: 1,
		item: item as uint8,
		tier: tier,
		consumed: 0,
		bump: bumpOf(receiptSeeds(pet, nonce)),
		pad: 0,
	});
	const key = address(receiptSeeds(pet, nonce));
	return account(key, programKey(), staged(Receipt.discriminator(), sizeof(Receipt) as uint64, stageReceiptEntry), 1_000_000);
}

function code(error: HibernalError): uint64 {
	return hibernalError(error).code;
}

function noon(seconds: int64): void {
	setClock({ slot: 1, epochStartTimestamp: 0, epoch: 1, leaderScheduleEpoch: 1, unixTimestamp: seconds });
}

test "buying food moves the price in SKR to the treasury and delegates a receipt for the pet" {
	const receipt = address(receiptSeeds(petKey(), 7));
	const accounts = buyAccounts(owner, receipt, 10_000_000);
	const before = invocations().length;
	assert run(programKey(), accounts, buyData(ShopItem.Food, 2, 7), entry).result == 0;
	assert amountOf(accounts[4]) == 7_000_000;
	assert amountOf(accounts[5]) == 3_000_000;
	assert accounts[6].owner == Pubkey.delegationProgram();
	assert invocations().length > before;
	const delegation = invocations()[invocations().length - 1];
	assert delegation.program == Pubkey.delegationProgram();
	let listsReceipt = false;
	for (const meta of delegation.accounts) { listsReceipt = listsReceipt || meta.key == receipt; }
	assert listsReceipt;
}

test "only the pet's owner can buy for it, and only with enough SKR" {
	const receipt = address(receiptSeeds(petKey(), 8));
	const stolen = buyAccounts(stranger, receipt, 10_000_000);
	assert run(programKey(), stolen, buyData(ShopItem.Food, 0, 8), entry).result == ProgramError.constraintHasOne().code;
	const poor = buyAccounts(owner, receipt, 500_000);
	assert run(programKey(), poor, buyData(ShopItem.Food, 0, 8), entry).result != 0;
	assert amountOf(poor[5]) == 0;
	const unknown = buyAccounts(owner, receipt, 10_000_000);
	assert run(programKey(), unknown, buyData(ShopItem.Food, 3, 8), entry).result == code(HibernalError.NoSuchFood);
	const bogus = instructionData("Buy");
	bogus.push(9);
	bogus.push(0);
	pushU64(bogus, 8);
	assert run(programKey(), unknown, bogus, entry).result == code(HibernalError.NoSuchItem);
}

test "insurance is bought once per generation, whatever nonce the client sends" {
	const receipt = address(receiptSeeds(petKey(), INSURANCE_NONCE_BASE));
	const accounts = buyAccounts(owner, receipt, 100_000_000);
	assert run(programKey(), accounts, buyData(ShopItem.Insurance, 0, 1), entry).result == 0;
	assert amountOf(accounts[5]) == 20_000_000;
	assert run(programKey(), accounts, buyData(ShopItem.Insurance, 0, 2), entry).result == code(HibernalError.AlreadyBought);
	assert amountOf(accounts[5]) == 20_000_000;
	const forged = buyAccounts(owner, receipt, 100_000_000);
	assert run(programKey(), forged, buyData(ShopItem.Food, 0, INSURANCE_NONCE_BASE + 3), entry).result ==
		code(HibernalError.WrongReceipt);
}

test "a food receipt feeds the pet once and is then spent" {
	const hungry: Pet = { ...newborn(), hearts: 1 };
	const accounts = [receiptHolder(ShopItem.Food, 2, 7, petKey()), petHolder(hungry, programKey()), worldHolder()];
	assert run(programKey(), accounts, instructionData("Consume"), entry).result == 0;
	const fed = petRecordOf(accounts[1].data).pet;
	assert fed.hearts > 1 && fed.ownerFedToday == 1 && fed.bonding > 0;
	assert receiptOf(accounts[0].data).consumed == 1;
	assert run(programKey(), accounts, instructionData("Consume"), entry).result == code(HibernalError.AlreadyConsumed);
}

test "growth and insurance receipts apply the owner rules, a receipt only fits its own pet" {
	noon(3 * 86_400);
	const growing = [receiptHolder(ShopItem.Growth, 2, 9, petKey()), petHolder(newborn(), programKey()), worldHolder()];
	assert run(programKey(), growing, instructionData("Consume"), entry).result == 0;
	const grown = petRecordOf(growing[1].data).pet;
	assert grown.growthMultiplierBps as int32 == GROWTH_CAP_BPS - 500 && grown.growthMultiplierExpiry == 4;
	const armed = [receiptHolder(ShopItem.Insurance, 0, INSURANCE_NONCE_BASE, petKey()), petHolder(newborn(), programKey()), worldHolder()];
	assert run(programKey(), armed, instructionData("Consume"), entry).result == 0;
	assert petRecordOf(armed[1].data).pet.insurance == (Insurance.Armed as uint8);
	const twice = [receiptHolder(ShopItem.Insurance, 0, INSURANCE_NONCE_BASE + 1, petKey()), armed[1], worldHolder()];
	assert run(programKey(), twice, instructionData("Consume"), entry).result == code(HibernalError.Insured);
	const other = [receiptHolder(ShopItem.Food, 0, 10, keyOf(77)), petHolder({ ...newborn(), hearts: 1 }, programKey()), worldHolder()];
	assert run(programKey(), other, instructionData("Consume"), entry).result == ProgramError.constraintHasOne().code;
}
