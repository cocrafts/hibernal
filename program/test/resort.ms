import { Pubkey, decode, encode, failWith, instructionDiscriminator, SYSTEM_PROGRAM_ID } from "std/solana";
import { HostAccount, run } from "std/solana/host";
import { BlockSlot, GlobalConfig, Item, ItemSkill, Pet, Region, TalentGrade, TalentKind, born, genesis, minted, sellPrice } from "../../rules/index";
import { Block, Config, HibernalError, MAX_PETS, PetAccount, RESORT_BITMAP_BYTES, Resort, World, hibernalError } from "../layout";
import { resortAssign, resortBegin, resortClear, resortFinish } from "../resort";

const COMBAT: uint8 = 2;

function keyOf(seed: uint8): Pubkey {
	let key = Pubkey.zero();
	key.bytes[0] = seed;
	key.bytes[1] = 0x5a;
	return key;
}

function programKey(): Pubkey { return keyOf(200); }
function authorityKey(): Pubkey { return keyOf(201); }

function pushU64(bytes: uint8[], value: uint64): void {
	for (let shift: uint64 = 0; shift < 64; shift += 8) {
		bytes.push(((value >> shift) & 255) as uint8);
	}
}

function zeros(count: int32): uint8[] {
	const bytes: uint8[] = [];
	for (let i = 0; i < count; i++) { bytes.push(0); }
	return bytes;
}

function holder(key: Pubkey, size: int32): HostAccount {
	return {
		key: key,
		owner: programKey(),
		lamports: 1000000,
		data: zeros(8 + size),
		signer: false,
		writable: true,
		executable: false,
	};
}

function authority(): HostAccount {
	return {
		key: authorityKey(),
		owner: SYSTEM_PROGRAM_ID,
		lamports: 1000000000,
		data: [],
		signer: true,
		writable: false,
		executable: false,
	};
}

function stamped(account: HostAccount, word: uint64): HostAccount {
	const data = account.data;
	for (let i: uint64 = 0; i < 8; i++) { data[i as int32] = ((word >> (i * 8)) & 255) as uint8; }
	return { ...account, data: data };
}

function headed(name: string): uint8[] {
	const tag = instructionDiscriminator(name);
	const bytes: uint8[] = [];
	for (let i = 0; i < 8; i++) { bytes.push(tag.bytes[i]); }
	return bytes;
}

function codeOf(error: HibernalError): uint64 {
	return hibernalError(error).code;
}

function bytesOf<T>(value: T): uint8[] {
	const encoded = encode(value);
	if (!encoded.ok) { unreachable; }
	return encoded.value;
}

function valueOf<T>(account: HostAccount): T {
	const decoded = decode<T>(account.data);
	if (!decoded.ok) { unreachable; }
	return decoded.value;
}

function worldHolder(placedPets: uint32, treasury: uint64): HostAccount {
	const blank = stamped(holder(keyOf(151), sizeof(World) as int32), World.discriminator().word());
	let world = valueOf<World>(blank);
	world.placed = placedPets;
	world.global.itemReserve = treasury;
	return { ...blank, data: bytesOf<World>(world) };
}

function beginEntry(): void {
	const result = resortBegin();
	if (!result.ok) { failWith(result.error); }
}

function clearEntry(): void {
	const result = resortClear();
	if (!result.ok) { failWith(result.error); }
}

function assignEntry(): void {
	const result = resortAssign();
	if (!result.ok) { failWith(result.error); }
}

function finishEntry(): void {
	const result = resortFinish();
	if (!result.ok) { failWith(result.error); }
}

function readOnly(account: HostAccount): HostAccount {
	return { ...account, writable: false };
}

function petHolder(ordinal: uint32, blockId: uint32, slot: uint8, might: uint16, alive: boolean): HostAccount {
	const blank = stamped(holder(keyOf(ordinal as uint8), sizeof(PetAccount) as int32), PetAccount.discriminator().word());
	const hatched = Pet.born(blockId, slot as BlockSlot, Region.Worker, 0, GlobalConfig.genesis(0));
	const record: PetAccount = {
		...valueOf<PetAccount>(blank),
		ordinal: ordinal,
		pet: { ...hatched.pet, might: might, alive: alive, grudgeSlot: 4, rage: 2 },
	};
	return { ...blank, data: bytesOf<PetAccount>(record) };
}

function blockHolder(id: uint32, first: int32): HostAccount {
	return blockHolderFreeing(id, first, 255);
}

function blockHolderFreeing(id: uint32, first: int32, freed: uint8): HostAccount {
	const blank = stamped(holder(keyOf(100 + (id as uint8)), sizeof(Block) as int32), Block.discriminator().word());
	let block = valueOf<Block>(blank);
	block.id = id;
	block.filled = 10;
	for (let seat = 0; seat < 10; seat++) { block.members[seat] = state[PETS + first + seat].key; }
	if ((freed as int32) < 10) {
		block.members[freed as int32] = Pubkey.zero();
		block.filled = block.filled - 1;
	}
	block.grudges[3].robber = 7;
	block.grudges[3].epoch = 5;
	return { ...blank, data: bytesOf<Block>(block) };
}

function configHolder(pets: uint32, blocks: uint32): HostAccount {
	const blank = stamped(holder(keyOf(150), sizeof(Config) as int32), Config.discriminator().word());
	const config: Config = { ...valueOf<Config>(blank), authority: authorityKey(), pets: pets, blocks: blocks };
	return readOnly({ ...blank, data: bytesOf<Config>(config) });
}

const CONFIG: int32 = 0;
const WORLD: int32 = 1;
const RESORT: int32 = 2;
const BLOCKS: int32 = 3;
const PETS: int32 = 5;
const FIXTURE_TREASURY: uint64 = 1000000000000;

let state: HostAccount[] = [];

function fixture(): void {
	state = [
		authority(),
		stamped(holder(keyOf(151), sizeof(World) as int32), World.discriminator().word()),
		stamped(holder(keyOf(152), sizeof(Resort) as int32), Resort.discriminator().word()),
		authority(),
		authority(),
	];
	for (let index = 0; index < 20; index++) {
		const blockId = (index / 10) as uint32;
		const strong = index >= 10;
		const might = strong ? 300 + (index as uint16) : 20 + (index as uint16);
		state.push(petHolder(index as uint32, blockId, (index % 10) as uint8, might, index != 4));
	}
	state[CONFIG] = configHolder(20, 2);
	state[WORLD] = worldHolder(20, FIXTURE_TREASURY);
	state[BLOCKS] = blockHolder(0, 0);
	state[BLOCKS + 1] = blockHolder(1, 10);
}

function begun(): uint64 {
	return begunWith(20);
}

function begunWith(count: uint64): uint64 {
	const data = headed("ResortBegin");
	data.push(COMBAT);
	pushU64(data, count);
	const accounts: HostAccount[] = [authority(), state[CONFIG], state[WORLD], state[RESORT]];
	const outcome = run(programKey(), accounts, data, beginEntry);
	state[WORLD] = accounts[2];
	state[RESORT] = accounts[3];
	return outcome.result;
}

function cleared(block: int32): uint64 {
	return clearedWithout(block, -1);
}

function clearedWithout(block: int32, freed: int32): uint64 {
	const accounts: HostAccount[] = [authority(), state[CONFIG], state[WORLD], state[RESORT], state[BLOCKS + block]];
	const first = PETS + block * 10;
	const seats: int32[] = [];
	for (let seat = 0; seat < 10; seat++) {
		if (seat == freed) { continue; }
		seats.push(seat);
		accounts.push(state[first + seat]);
	}
	const outcome = run(programKey(), accounts, headed("ResortClear"), clearEntry);
	state[WORLD] = accounts[2];
	state[RESORT] = accounts[3];
	state[BLOCKS + block] = accounts[4];
	for (let index = 0; index < seats.length; index++) { state[first + seats[index]] = accounts[5 + index]; }
	return outcome.result;
}

function noPreviousBlock(): HostAccount {
	return { ...authority(), key: programKey(), signer: false };
}

function assigned(block: int32, previous: int32, offset: uint64, pets: int32[]): uint64 {
	const data = headed("ResortAssign");
	pushU64(data, offset);
	const accounts: HostAccount[] = [
		authority(),
		state[CONFIG],
		state[RESORT],
		state[BLOCKS + block],
		block == 0 ? noPreviousBlock() : readOnly(state[BLOCKS + previous]),
	];
	for (const pet of pets) { accounts.push(state[PETS + pet]); }
	const outcome = run(programKey(), accounts, data, assignEntry);
	state[RESORT] = accounts[2];
	state[BLOCKS + block] = accounts[3];
	for (let index = 0; index < pets.length; index++) { state[PETS + pets[index]] = accounts[5 + index]; }
	return outcome.result;
}

function finished(): uint64 {
	const accounts: HostAccount[] = [authority(), state[CONFIG], state[WORLD], readOnly(state[RESORT])];
	const outcome = run(programKey(), accounts, headed("ResortFinish"), finishEntry);
	state[WORLD] = accounts[2];
	return outcome.result;
}

function range(from: int32, to: int32): int32[] {
	const values: int32[] = [];
	for (let value = from; value < to; value++) { values.push(value); }
	return values;
}

function listFromSeatTwo(): void {
	const seller = valueOf<PetAccount>(state[PETS + 2]);
	let block = valueOf<Block>(state[BLOCKS]);
	const item = Item.minted(TalentGrade.Epic, TalentKind.Might, ItemSkill.None, 1);
	block.listed[0] = 1;
	block.listings[0] = { item: item, price: 50, seller: 2, sellerBorn: seller.pet.bornEpoch, listedEpoch: 1 };
	state[BLOCKS] = { ...state[BLOCKS], data: bytesOf<Block>(block) };
}

test "twenty pets re-sort into two blocks, strongest first, each pet on its new seat" {
	fixture();
	assert begun() == 0;
	assert valueOf<World>(state[WORLD]).resorting == 1;
	assert cleared(0) == 0;
	assert cleared(1) == 0;
	assert valueOf<Block>(state[BLOCKS]).grudges[3].robber == 0;
	assert assigned(0, 0, 0, range(10, 15)) == 0;
	assert assigned(0, 0, 5, range(15, 20)) == 0;
	assert assigned(1, 0, 0, range(0, 10)) == 0;
	assert finished() == 0;
	const strong = valueOf<Block>(state[BLOCKS]);
	assert strong.filled == 10 && strong.rotation == 1;
	for (let seat = 0; seat < 10; seat++) { assert strong.members[seat].bytes[0] == (10 + seat) as uint8; }
	const weak = valueOf<Block>(state[BLOCKS + 1]);
	assert weak.minStrength == 0 && weak.maxStrength < strong.minStrength;
	const moved = valueOf<PetAccount>(state[PETS + 12]).pet;
	assert moved.blockId == 0 && moved.slot == 2 && moved.rage == 0;
	const stayed = valueOf<PetAccount>(state[PETS + 3]).pet;
	assert stayed.blockId == 1 && stayed.slot == 3;
	assert valueOf<World>(state[WORLD]).resorting == 0;
}

test "a block with a seat freed by a death clears its remaining pets and leaves no stale member" {
	fixture();
	state[BLOCKS + 1] = blockHolderFreeing(1, 10, 4);
	state[WORLD] = worldHolder(19, FIXTURE_TREASURY);
	assert valueOf<Block>(state[BLOCKS + 1]).filled == 9;
	assert begunWith(19) == 0;
	assert cleared(0) == 0;
	assert cleared(1) == codeOf(HibernalError.NotAMember);
	assert clearedWithout(1, 4) == 0;
	assert assigned(0, 0, 0, [10, 11, 12, 13, 15]) == 0;
	assert assigned(0, 0, 5, [16, 17, 18, 19, 9]) == 0;
	assert assigned(1, 0, 0, range(0, 9)) == 0;
	assert finished() == 0;
	const weak = valueOf<Block>(state[BLOCKS + 1]);
	assert weak.filled == 9 && weak.members[9].bytes[0] == 0;
}

test "a block may not be stronger than the block before it" {
	fixture();
	assert begun() == 0;
	assert cleared(0) == 0 && cleared(1) == 0;
	assert assigned(0, 0, 0, range(0, 10)) == 0;
	assert assigned(1, 0, 0, range(10, 15)) == codeOf(HibernalError.OutOfOrder);
}

test "a pet is assigned once a rotation and a block fills in order" {
	fixture();
	assert begun() == 0;
	assert assigned(0, 0, 0, range(10, 15)) == codeOf(HibernalError.Unfinished);
	assert cleared(0) == 0 && cleared(1) == 0;
	assert cleared(0) == codeOf(HibernalError.OutOfOrder);
	assert assigned(0, 0, 0, range(10, 15)) == 0;
	assert assigned(0, 0, 5, [12, 15, 16, 17, 18]) == codeOf(HibernalError.AlreadyAssigned);
	assert assigned(0, 0, 3, range(15, 20)) == codeOf(HibernalError.OutOfOrder);
	assert assigned(1, 0, 0, range(0, 5)) == codeOf(HibernalError.OutOfOrder);
}

test "finishing early is refused and a listing goes back to its seller" {
	fixture();
	listFromSeatTwo();
	const before = valueOf<PetAccount>(state[PETS + 2]).pet.burrow;
	assert begun() == 0;
	assert begun() == codeOf(HibernalError.Resorting);
	assert cleared(0) == 0;
	assert valueOf<Block>(state[BLOCKS]).listed[0] == 0;
	const price = Item.minted(TalentGrade.Epic, TalentKind.Might, ItemSkill.None, 1).sellPrice();
	assert price > 0 && valueOf<PetAccount>(state[PETS + 2]).pet.burrow == before + price;
	assert valueOf<World>(state[WORLD]).global.itemReserve == FIXTURE_TREASURY - price;
	assert finished() == codeOf(HibernalError.Unfinished);
}

const RESORT_BITMAP: int32 = 8 + 32;

test "the last pet under the cap is assigned through the last bitmap cell" {
	fixture();
	const last = (MAX_PETS - 1) as uint32;
	state[PETS + 10] = petHolder(last, 1, 0, 310, true);
	state[CONFIG] = configHolder(MAX_PETS as uint32, 2);
	state[BLOCKS + 1] = blockHolder(1, 10);
	assert RESORT_BITMAP_BYTES * 8 == MAX_PETS;
	assert begun() == 0;
	assert cleared(0) == 0 && cleared(1) == 0;
	assert assigned(0, 0, 0, range(10, 15)) == 0;
	const cell = RESORT_BITMAP_BYTES - 1;
	assert state[RESORT].data[RESORT_BITMAP + cell] == 0x80;
	assert RESORT_BITMAP + RESORT_BITMAP_BYTES <= 8 + (sizeof(Resort) as int32) && state[RESORT].data.length == 8 + (sizeof(Resort) as int32);
	assert assigned(0, 0, 5, [10, 15, 16, 17, 18]) == codeOf(HibernalError.AlreadyAssigned);
}
