import { Pubkey, failWith, instructionData, instructionDiscriminator, mutable, readU8, readU16, readU32, unchecked, SYSTEM_PROGRAM_ID } from "std/solana";
import { HostAccount, run } from "std/solana/host";
import { BlockSlot, GlobalConfig, Item, ItemSkill, Pet, Region, TalentGrade, TalentKind, born, genesis, minted, sellPrice } from "../../rules/index";
import { Block, Config, HibernalError, MAX_PETS, PetAccount, RESORT_BITMAP_BYTES, Resort, World, hibernalError } from "../layout";
import { resortAssign, resortBegin, resortClear, resortFinish } from "../resort";

const COMBAT: uint8 = 2;

let peeked: uint64[] = [];

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

function pushU32(bytes: uint8[], value: uint32): void {
	for (let shift: uint32 = 0; shift < 32; shift += 8) {
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

function stagePetEntry(): void {
	const data = instructionData();
	const target = unchecked(0);
	if (!target.ok) { failWith(target.error); return; }
	const record = (target.value.data().address + 8) as Ptr<PetAccount>;
	const ordinal = data.readU32(0);
	const blockId = data.readU32(4);
	const slot = data.readU8(8);
	const might = data.readU16(9);
	const alive = data.readU8(11);
	if (!ordinal.ok || !blockId.ok || !slot.ok || !might.ok || !alive.ok) { return; }
	const hatched = Pet.born(blockId.value, slot.value as BlockSlot, Region.Worker, 0, GlobalConfig.genesis(0));
	record.ordinal = ordinal.value;
	record.pet = { ...hatched.pet, might: might.value, alive: alive.value != 0, grudgeSlot: 4, rage: 2 };
}

function stageBlockEntry(): void {
	const data = instructionData();
	const target = unchecked(0);
	if (!target.ok) { failWith(target.error); return; }
	const block = (target.value.data().address + 8) as Ptr<Block>;
	const id = data.readU32(0);
	const filled = data.readU8(4);
	const freed = data.readU8(5);
	if (!id.ok || !filled.ok || !freed.ok) { return; }
	block.id = id.value;
	block.filled = filled.value;
	for (let seat = 0; seat < (filled.value as int32); seat++) {
		const member = unchecked(1 + seat);
		if (member.ok) { block.members[seat] = member.value.key(); }
	}
	if ((freed.value as int32) < 10) {
		block.members[freed.value as int32] = Pubkey.zero();
		block.filled = block.filled - 1;
	}
	block.grudges[3].robber = 7;
	block.grudges[3].epoch = 5;
}

function listEntry(): void {
	const target = unchecked(0);
	const seller = unchecked(1);
	if (!target.ok || !seller.ok) { return; }
	const block = (target.value.data().address + 8) as Ptr<Block>;
	const pet = (seller.value.data().address + 8) as Ptr<PetAccount>;
	const item = Item.minted(TalentGrade.Epic, TalentKind.Might, ItemSkill.None, 1);
	block.listed[0] = 1;
	block.listings[0] = { item: item, price: 50, seller: 2, sellerBorn: pet.pet.bornEpoch, listedEpoch: 1 };
}

function stageConfigEntry(): void {
	const data = instructionData();
	const target = unchecked(0);
	const owner = unchecked(1);
	if (!target.ok || !owner.ok) { return; }
	const config = (target.value.data().address + 8) as Ptr<Config>;
	const pets = data.readU32(0);
	const blocks = data.readU32(4);
	if (!pets.ok || !blocks.ok) { return; }
	config.authority = owner.value.key();
	config.pets = pets.value;
	config.blocks = blocks.value;
}

function stageWorldEntry(): void {
	const data = instructionData();
	const target = unchecked(0);
	if (!target.ok) { return; }
	const world = (target.value.data().address + 8) as Ptr<World>;
	const placedPets = data.readU32(0);
	const treasury = data.readU64(4);
	if (!placedPets.ok || !treasury.ok) { return; }
	world.placed = placedPets.value;
	world.global.itemReserve = treasury.value;
}

function worldHolder(placedPets: uint32, treasury: uint64): HostAccount {
	const blank = stamped(holder(keyOf(151), sizeof(World) as int32), World.discriminator().word());
	const data: uint8[] = [];
	pushU32(data, placedPets);
	pushU64(data, treasury);
	return staged([blank], data, stageWorldEntry);
}

function peekBlockEntry(): void {
	const target = unchecked(0);
	if (!target.ok) { return; }
	const block = (target.value.data().address + 8) as Ptr<Block>;
	peeked = [block.filled as uint64, block.rotation, block.minStrength, block.maxStrength, block.grudges[3].robber as uint64];
	for (let seat = 0; seat < 10; seat++) { peeked.push(block.members[seat].bytes[0] as uint64); }
	peeked.push(block.listed[0] as uint64);
}

function peekPetEntry(): void {
	const target = unchecked(0);
	if (!target.ok) { return; }
	const record = (target.value.data().address + 8) as Ptr<PetAccount>;
	peeked = [record.pet.blockId as uint64, record.pet.slot as uint64, record.pet.burrow, record.pet.rage as uint64];
}

function peekWorldEntry(): void {
	const target = unchecked(0);
	if (!target.ok) { return; }
	const world = (target.value.data().address + 8) as Ptr<World>;
	peeked = [world.resorting as uint64, world.rotation, world.global.itemReserve];
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

function staged(accounts: HostAccount[], data: uint8[], entry: () => void): HostAccount {
	const outcome = run(programKey(), accounts, data, entry);
	if (outcome.result != 0) { return { ...accounts[0], lamports: 0 }; }
	return accounts[0];
}

function readOnly(account: HostAccount): HostAccount {
	return { ...account, writable: false };
}

function petHolder(ordinal: uint32, blockId: uint32, slot: uint8, might: uint16, alive: boolean): HostAccount {
	const blank = stamped(holder(keyOf(ordinal as uint8), sizeof(PetAccount) as int32), PetAccount.discriminator().word());
	const data: uint8[] = [];
	pushU32(data, ordinal);
	pushU32(data, blockId);
	data.push(slot);
	data.push((might & 255) as uint8);
	data.push((might >> 8) as uint8);
	data.push(alive ? 1 : 0);
	return staged([blank], data, stagePetEntry);
}

function blockHolder(id: uint32, first: int32): HostAccount {
	return blockHolderFreeing(id, first, 255);
}

function blockHolderFreeing(id: uint32, first: int32, freed: uint8): HostAccount {
	const blank = stamped(holder(keyOf(100 + (id as uint8)), sizeof(Block) as int32), Block.discriminator().word());
	const data: uint8[] = [];
	pushU32(data, id);
	data.push(10);
	data.push(freed);
	const accounts: HostAccount[] = [blank];
	for (let seat = 0; seat < 10; seat++) { accounts.push(state[PETS + first + seat]); }
	return staged(accounts, data, stageBlockEntry);
}

function configHolder(pets: uint32, blocks: uint32): HostAccount {
	const blank = stamped(holder(keyOf(150), sizeof(Config) as int32), Config.discriminator().word());
	const data: uint8[] = [];
	pushU32(data, pets);
	pushU32(data, blocks);
	return readOnly(staged([blank, authority()], data, stageConfigEntry));
}

function peek(account: HostAccount, entry: () => void): uint64[] {
	peeked = [];
	const outcome = run(programKey(), [account], [], entry);
	if (outcome.result != 0) { return []; }
	return peeked;
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

function assigned(block: int32, previous: int32, offset: uint64, pets: int32[]): uint64 {
	const data = headed("ResortAssign");
	pushU64(data, offset);
	const accounts: HostAccount[] = [
		authority(),
		state[CONFIG],
		state[RESORT],
		state[BLOCKS + block],
		readOnly(state[BLOCKS + previous]),
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

function listed(): uint64 {
	const accounts: HostAccount[] = [state[BLOCKS], state[PETS + 2]];
	const outcome = run(programKey(), accounts, [], listEntry);
	state[BLOCKS] = accounts[0];
	return outcome.result;
}

test "twenty pets re-sort into two blocks, strongest first, each pet on its new seat" {
	fixture();
	assert begun() == 0;
	assert peek(state[WORLD], peekWorldEntry)[0] == 1;
	assert cleared(0) == 0;
	assert cleared(1) == 0;
	assert peek(state[BLOCKS], peekBlockEntry)[4] == 0;
	assert assigned(0, 0, 0, range(10, 15)) == 0;
	assert assigned(0, 0, 5, range(15, 20)) == 0;
	assert assigned(1, 0, 0, range(0, 10)) == 0;
	assert finished() == 0;
	const strong = peek(state[BLOCKS], peekBlockEntry);
	assert strong[0] == 10 && strong[1] == 1;
	for (let seat = 0; seat < 10; seat++) { assert strong[5 + seat] == (10 + seat) as uint64; }
	const weak = peek(state[BLOCKS + 1], peekBlockEntry);
	assert weak[2] == 0 && weak[3] < strong[2];
	const moved = peek(state[PETS + 12], peekPetEntry);
	assert moved[0] == 0 && moved[1] == 2 && moved[3] == 0;
	const stayed = peek(state[PETS + 3], peekPetEntry);
	assert stayed[0] == 1 && stayed[1] == 3;
	assert peek(state[WORLD], peekWorldEntry)[0] == 0;
}

test "a block with a seat freed by a death clears its remaining pets and leaves no stale member" {
	fixture();
	state[BLOCKS + 1] = blockHolderFreeing(1, 10, 4);
	state[WORLD] = worldHolder(19, FIXTURE_TREASURY);
	assert peek(state[BLOCKS + 1], peekBlockEntry)[0] == 9;
	assert begunWith(19) == 0;
	assert cleared(0) == 0;
	assert cleared(1) == codeOf(HibernalError.NotAMember);
	assert clearedWithout(1, 4) == 0;
	assert assigned(0, 0, 0, [10, 11, 12, 13, 15]) == 0;
	assert assigned(0, 0, 5, [16, 17, 18, 19, 9]) == 0;
	assert assigned(1, 0, 0, range(0, 9)) == 0;
	assert finished() == 0;
	const weak = peek(state[BLOCKS + 1], peekBlockEntry);
	assert weak[0] == 9 && weak[5 + 9] == 0;
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
	assert listed() == 0;
	const before = peek(state[PETS + 2], peekPetEntry)[2];
	assert begun() == 0;
	assert begun() == codeOf(HibernalError.Resorting);
	assert cleared(0) == 0;
	assert peek(state[BLOCKS], peekBlockEntry)[15] == 0;
	const price = Item.minted(TalentGrade.Epic, TalentKind.Might, ItemSkill.None, 1).sellPrice();
	assert price > 0 && peek(state[PETS + 2], peekPetEntry)[2] == before + price;
	assert peek(state[WORLD], peekWorldEntry)[2] == FIXTURE_TREASURY - price;
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
