import { ProgramError, Pubkey, Seeds, failWith, instructionDiscriminator, selectInstruction } from "std/solana";
import { instruction } from "std/solana/macro";
import { HostAccount, HostInvocation, invocations, run, setClock } from "std/solana/host";
import { delegationProgram } from "std/solana/magicblock";
import { EPOCH_SECONDS, POLICY_FORMAT, POLICY_MAGIC } from "../../rules/index";
import {
	HibernalError,
	NO_BLOCK,
	NO_SEAT,
	Op,
	POLICY_BYTES,
	SEATS,
	blockSeeds,
	configSeeds,
	hibernalError,
	mintSeeds,
	paidSeeds,
	petSeeds,
	policySeeds,
	worldSeeds,
} from "../layout";
import { createBlock, initialize, writePolicy } from "../admin";
import { claim, delegateBlock, delegatePet, delegateWorld, place, processUndelegation } from "../admission";

function dispatched(): Result<uint64, ProgramError> {
	return match (try instruction<Op>()) {
		Op.Initialize => initialize(),
		Op.WritePolicy => writePolicy(),
		Op.CreateBlock => createBlock(),
		Op.Claim => claim(),
		Op.DelegatePet => delegatePet(),
		Op.DelegateBlock => delegateBlock(),
		Op.DelegateWorld => delegateWorld(),
		Op.ProcessUndelegation => processUndelegation(),
		Op.Place => place(),
		_ => Result.err(ProgramError.instructionFallbackNotFound()),
	};
}

function entry(): void {
	const result = dispatched();
	if (!result.ok) { failWith(result.error); }
}

const ENGINE: uint64 = 0x8000000000000007;
const GENESIS: uint64 = 1_700_000_000;
const CONFIG_BYTES: int32 = 8 + 232;

function keyOf(seed: uint8, salt: uint8): Pubkey {
	let key = Pubkey.zero();
	key.bytes[0] = seed;
	key.bytes[1] = salt;
	key.bytes[2] = 0x5a;
	return key;
}

function programKey(): Pubkey { return keyOf(200, 1); }

function pushU8(bytes: uint8[], value: uint8): void { bytes.push(value); }

function pushU32(bytes: uint8[], value: uint32): void {
	for (let shift: uint32 = 0; shift < 32; shift += 8) {
		bytes.push(((value >> shift) & 255) as uint8);
	}
}

function pushU16(bytes: uint8[], value: uint16): void {
	bytes.push((value & 255) as uint8);
	bytes.push(((value >> 8) & 255) as uint8);
}

function pushU64(bytes: uint8[], value: uint64): void {
	for (let shift: uint64 = 0; shift < 64; shift += 8) {
		bytes.push(((value >> shift) & 255) as uint8);
	}
}

function pushKey(bytes: uint8[], key: Pubkey): void {
	for (let i = 0; i < 32; i++) { bytes.push(key.bytes[i]); }
}

function zeros(bytes: uint8[], count: int32): void {
	for (let i = 0; i < count; i++) { bytes.push(0); }
}

function u32At(data: uint8[], offset: int32): uint32 {
	let value: uint32 = 0;
	for (let i = 3; i >= 0; i--) { value = (value << 8) | (data[offset + i] as uint32); }
	return value;
}

function u64At(data: uint8[], offset: int32): uint64 {
	let value: uint64 = 0;
	for (let i = 7; i >= 0; i--) { value = (value << 8) | (data[offset + i] as uint64); }
	return value;
}

function keyAt(data: uint8[], offset: int32): Pubkey {
	let key = Pubkey.zero();
	for (let i = 0; i < 32; i++) { key.bytes[i] = data[offset + i]; }
	return key;
}

function contains(data: uint8[], key: Pubkey): boolean {
	for (let start = 0; start + 32 <= data.length; start++) {
		let same = true;
		for (let i = 0; i < 32; i++) {
			if (data[start + i] != key.bytes[i]) {
				same = false;
				break;
			}
		}
		if (same) { return true; }
	}
	return false;
}

function account(key: Pubkey, owner: Pubkey, data: uint8[], lamports: uint64): HostAccount {
	return { key: key, owner: owner, lamports: lamports, data: data, signer: false, writable: true, executable: false };
}

function wallet(key: Pubkey): HostAccount {
	return { ...account(key, Pubkey.systemProgram(), [], 10_000_000_000), signer: true };
}

function executable(key: Pubkey): HostAccount {
	return { ...account(key, keyOf(0, 0), [], 1), writable: false, executable: true };
}

function blank(key: Pubkey): HostAccount {
	return account(key, Pubkey.systemProgram(), [], 0);
}

function readonly(holder: HostAccount): HostAccount {
	return { ...holder, writable: false, signer: false };
}

function configKey(): Pubkey {
	const found = configSeeds().findProgramAddress(programKey());
	return found.ok ? found.value.key : Pubkey.zero();
}

function policyKey(): Pubkey {
	const found = policySeeds().findProgramAddress(programKey());
	return found.ok ? found.value.key : Pubkey.zero();
}

function worldKey(): Pubkey {
	const found = worldSeeds().findProgramAddress(programKey());
	return found.ok ? found.value.key : Pubkey.zero();
}

function mintKey(): Pubkey {
	const found = mintSeeds().findProgramAddress(programKey());
	return found.ok ? found.value.key : Pubkey.zero();
}

function blockKey(id: uint32): Pubkey {
	const found = blockSeeds(id).findProgramAddress(programKey());
	return found.ok ? found.value.key : Pubkey.zero();
}

function petKey(mint: Pubkey): Pubkey {
	const found = petSeeds(mint).findProgramAddress(programKey());
	return found.ok ? found.value.key : Pubkey.zero();
}

function paidKey(mint: Pubkey): Pubkey {
	const found = paidSeeds(mint).findProgramAddress(programKey());
	return found.ok ? found.value.key : Pubkey.zero();
}

function bufferKey(delegated: Pubkey): Pubkey {
	const found = Seeds.empty(2).addText("buffer").addPubkey(delegated).findProgramAddress(programKey());
	return found.ok ? found.value.key : Pubkey.zero();
}

function instructionBytes(name: string): uint8[] {
	const discriminator = instructionDiscriminator(name);
	const bytes: uint8[] = [];
	for (let i = 0; i < 8; i++) { bytes.push(discriminator.bytes[i]); }
	return bytes;
}

const authority = keyOf(1, 0);
const stranger = keyOf(2, 0);
const owner = keyOf(3, 0);
const group = keyOf(4, 0);
const otherGroup = keyOf(5, 0);
const validator = keyOf(6, 0);

function initializeData(engine: uint64): uint8[] {
	const bytes = instructionBytes("Initialize");
	pushKey(bytes, group);
	pushU64(bytes, engine);
	pushU64(bytes, GENESIS);
	pushU64(bytes, 10_000_000);
	pushU64(bytes, 7);
	pushKey(bytes, validator);
	pushKey(bytes, keyOf(7, 0));
	pushKey(bytes, keyOf(8, 0));
	return bytes;
}

function policyBlob(engine: uint64): uint8[] {
	const bytes: uint8[] = [];
	pushU32(bytes, POLICY_MAGIC as uint32);
	pushU32(bytes, POLICY_FORMAT as uint32);
	pushU64(bytes, engine);
	zeros(bytes, POLICY_BYTES - 16);
	return bytes;
}

function writeData(blob: uint8[], offset: int32, length: int32, seal: boolean): uint8[] {
	const bytes = instructionBytes("WritePolicy");
	pushU32(bytes, offset as uint32);
	pushU8(bytes, seal ? 1 : 0);
	pushU32(bytes, length as uint32);
	for (let i = 0; i < length; i++) { bytes.push(blob[offset + i]); }
	return bytes;
}

function blockData(id: uint32): uint8[] {
	const bytes = instructionBytes("CreateBlock");
	pushU32(bytes, id);
	return bytes;
}

function admissionMint(key: Pubkey, inGroup: Pubkey): HostAccount {
	const data: uint8[] = [];
	pushU32(data, 1);
	pushKey(data, keyOf(9, 9));
	pushU64(data, 1);
	data.push(0);
	data.push(1);
	pushU32(data, 0);
	zeros(data, 32);
	zeros(data, 165 - 82);
	data.push(1);
	pushU16(data, 22);
	pushU16(data, 64);
	pushKey(data, keyOf(9, 9));
	pushKey(data, key);
	pushU16(data, 23);
	pushU16(data, 72);
	pushKey(data, key);
	pushKey(data, inGroup);
	pushU64(data, 42);
	return account(key, Pubkey.token2022Program(), data, 4_000_000);
}

function heldAccount(key: Pubkey, mint: Pubkey, holder: Pubkey, amount: uint64): HostAccount {
	const data: uint8[] = [];
	pushKey(data, mint);
	pushKey(data, holder);
	pushU64(data, amount);
	zeros(data, 36);
	data.push(1);
	zeros(data, 12);
	pushU64(data, 0);
	zeros(data, 36);
	return account(key, Pubkey.token2022Program(), data, 2_039_280);
}

function claimAccounts(made: HostAccount[], claimer: Pubkey, mint: HostAccount, held: HostAccount): HostAccount[] {
	return [
		wallet(claimer),
		made[1],
		readonly(mint),
		readonly(held),
		blank(petKey(mint.key)),
		blank(paidKey(mint.key)),
		executable(Pubkey.systemProgram()),
	];
}

function admissionMintKey(index: uint8): Pubkey { return keyOf(100 + index, 7); }


function initialized(): HostAccount[] {
	const made = [
		wallet(authority),
		blank(configKey()),
		blank(policyKey()),
		blank(worldKey()),
		blank(mintKey()),
		executable(Pubkey.tokenProgram()),
		executable(Pubkey.systemProgram()),
	];
	const _ran = run(programKey(), made, initializeData(ENGINE), entry);
	return made;
}

function written(made: HostAccount[], signer: Pubkey, data: uint8[]): uint64 {
	const accounts = [wallet(signer), made[1], made[2]];
	const result = run(programKey(), accounts, data, entry).result;
	made[1] = accounts[1];
	made[2] = accounts[2];
	return result;
}

function blockCreated(made: HostAccount[], signer: Pubkey, id: uint32, target: Pubkey): HostAccount[] {
	const accounts = [wallet(signer), made[1], blank(target), executable(Pubkey.systemProgram())];
	const result = run(programKey(), accounts, blockData(id), entry).result;
	made[1] = accounts[1];
	return [accounts[2], { ...accounts[2], lamports: result }];
}

function claimRan(made: HostAccount[], accounts: HostAccount[]): uint64 {
	const result = run(programKey(), accounts, instructionBytes("Claim"), entry).result;
	made[1] = accounts[1];
	return result;
}

function claimed(made: HostAccount[], index: uint8): HostAccount[] {
	const mint = admissionMint(admissionMintKey(index), group);
	const held = heldAccount(keyOf(150 + index, 7), mint.key, owner, 1);
	const accounts = claimAccounts(made, owner, mint, held);
	const _result = claimRan(made, accounts);
	return accounts;
}

function now(epoch: uint64): void {
	setClock({
		slot: 1,
		epochStartTimestamp: GENESIS as int64,
		epoch: 0,
		leaderScheduleEpoch: 0,
		unixTimestamp: (GENESIS + epoch * EPOCH_SECONDS + 5) as int64,
	});
}

const PET_RECORD: int32 = 8;
const PET_ORDINAL: int32 = PET_RECORD + 64;
const PET_BLOCK: int32 = PET_RECORD + 88;
const PET_SLOT: int32 = PET_BLOCK + 4;
const PET_ALIVE: int32 = PET_BLOCK + 5;
const WORLD_LIVING: int32 = 8 + 56;
const WORLD_PLACED: int32 = 8 + 104;
const WORLD_RESORTING: int32 = 8 + 97;
const CONFIG_BLOCKS: int32 = 8 + 120;
const CONFIG_PETS: int32 = 8 + 124;
const POLICY_WRITTEN: int32 = 8 + 8;
const POLICY_SEALED: int32 = 8 + 12;
const POLICY_BLOB: int32 = 8 + 16;
const BLOCK_FILLED: int32 = 8 + 4;

test "initialize creates config, policy, world and the HBRN mint it signs for" {
	now(0);
	const made = initialized();
	assert made[1].owner == programKey() && made[1].data.length == CONFIG_BYTES;
	assert keyAt(made[1].data, 8) == authority;
	assert keyAt(made[1].data, 8 + 32) == group;
	assert keyAt(made[1].data, 8 + 64) == mintKey();
	assert u64At(made[1].data, 8 + 96) == ENGINE;
	assert u64At(made[1].data, 8 + 104) == GENESIS;
	assert keyAt(made[1].data, 8 + 136) == validator;
	assert keyAt(made[1].data, 8 + 168) == keyOf(7, 0) && keyAt(made[1].data, 8 + 200) == keyOf(8, 0);
	assert made[2].owner == programKey() && made[3].owner == programKey();
	assert u64At(made[3].data, 8) == GENESIS;
	assert made[4].owner == Pubkey.tokenProgram() && made[4].data.length == 82;
	let mintInitialized = false;
	for (const call of invocations()) {
		if (call.program == Pubkey.tokenProgram() && call.data[0] == 20 && call.data[1] == 6) {
			mintInitialized = keyAt(call.data, 2) == mintKey();
		}
	}
	assert mintInitialized;
}

test "writePolicy fills the policy in order, seals it once and refuses everything after" {
	now(0);
	const made = initialized();
	const blob = policyBlob(ENGINE);
	assert written(made, stranger, writeData(blob, 0, 100, false)) == hibernalError(HibernalError.NotAuthority).code;
	assert written(made, authority, writeData(blob, 100, 100, false)) == hibernalError(HibernalError.PolicyOutOfRange).code;
	assert written(made, authority, writeData(blob, 0, 1000, true)) == hibernalError(HibernalError.PolicyUnsealed).code;
	assert u32At(made[2].data, POLICY_WRITTEN) == 0;
	let offset = 0;
	while (offset < POLICY_BYTES) {
		const length = Math.min(1000, POLICY_BYTES - offset);
		const last = offset + length == POLICY_BYTES;
		assert written(made, authority, writeData(blob, offset, length, last)) == 0;
		assert u32At(made[2].data, POLICY_WRITTEN) == (offset + length) as uint32;
		offset += length;
	}
	assert u32At(made[2].data, POLICY_WRITTEN) == POLICY_BYTES as uint32;
	assert made[2].data[POLICY_SEALED] == 1;
	assert made[2].data[POLICY_BLOB] == 0x48 && made[2].data[POLICY_BLOB + 4] == POLICY_FORMAT as uint8;
	assert written(made, authority, writeData(blob, 0, 10, false)) == hibernalError(HibernalError.PolicySealed).code;
}

test "writePolicy refuses to seal a policy built for another engine" {
	now(0);
	const made = initialized();
	const blob = policyBlob(ENGINE + 1);
	let offset = 0;
	let result: uint64 = 0;
	while (offset < POLICY_BYTES) {
		const length = Math.min(1000, POLICY_BYTES - offset);
		result = written(made, authority, writeData(blob, offset, length, offset + length == POLICY_BYTES));
		offset += length;
	}
	assert result == hibernalError(HibernalError.EngineMismatch).code;
	assert made[2].data[POLICY_SEALED] == 0;
}

test "createBlock numbers blocks in order and only for the authority" {
	now(0);
	const made = initialized();
	const first = blockCreated(made, authority, 0, blockKey(0));
	assert first[1].lamports == 0;
	assert first[0].owner == programKey();
	assert u32At(first[0].data, 8) == 0;
	assert u32At(made[1].data, CONFIG_BLOCKS) == 1;
	assert blockCreated(made, authority, 5, blockKey(5))[1].lamports == hibernalError(HibernalError.OutOfOrder).code;
	assert blockCreated(made, stranger, 1, blockKey(1))[1].lamports == hibernalError(HibernalError.NotAuthority).code;
	const second = blockCreated(made, authority, 1, blockKey(1));
	assert second[1].lamports == 0 && u32At(second[0].data, 8) == 1 && u32At(made[1].data, CONFIG_BLOCKS) == 2;
}

test "claim admits a group member once and refuses mints outside the group" {
	now(3);
	const made = initialized();
	const accounts = claimed(made, 0);
	const pet = accounts[4];
	assert pet.owner == programKey();
	assert keyAt(pet.data, PET_RECORD) == owner;
	assert keyAt(pet.data, PET_RECORD + 32) == admissionMintKey(0);
	assert u32At(pet.data, PET_ORDINAL) == 0;
	assert u64At(pet.data, PET_RECORD + 72) == 3;
	assert u32At(pet.data, PET_BLOCK) == NO_BLOCK && pet.data[PET_SLOT] == NO_SEAT && pet.data[PET_ALIVE] == 0;
	assert accounts[5].owner == programKey() && keyAt(accounts[5].data, 8) == admissionMintKey(0);
	assert u32At(made[1].data, CONFIG_PETS) == 1;
	const second = claimed(made, 3);
	assert u32At(second[4].data, PET_ORDINAL) == 1 && u32At(made[1].data, CONFIG_PETS) == 2;
	const outsider = admissionMint(admissionMintKey(1), otherGroup);
	const refused = claimAccounts(made, owner, outsider, heldAccount(keyOf(151, 7), outsider.key, owner, 1));
	assert claimRan(made, refused) == hibernalError(HibernalError.NotAdmitted).code;
	const lent = admissionMint(admissionMintKey(2), group);
	const notHeld = claimAccounts(made, owner, lent, heldAccount(keyOf(152, 7), lent.key, stranger, 1));
	assert claimRan(made, notHeld) == ProgramError.constraintTokenOwner().code;
	const empty = claimAccounts(made, owner, lent, heldAccount(keyOf(152, 7), lent.key, owner, 0));
	assert claimRan(made, empty) == hibernalError(HibernalError.NotAdmitted).code;
	const legacy: HostAccount = { ...admissionMint(admissionMintKey(4), group), owner: Pubkey.tokenProgram() };
	const wrongProgram = claimAccounts(made, owner, legacy, heldAccount(keyOf(154, 7), legacy.key, owner, 1));
	assert claimRan(made, wrongProgram) != 0;
	assert u32At(made[1].data, CONFIG_PETS) == 2;
}

function delegation(payer: Pubkey, made: HostAccount[], delegated: HostAccount): HostAccount[] {
	return [
		wallet(payer),
		readonly(made[1]),
		delegated,
		executable(programKey()),
		blank(bufferKey(delegated.key)),
		blank(keyOf(60, 1)),
		blank(keyOf(61, 1)),
		executable(Pubkey.delegationProgram()),
		executable(Pubkey.systemProgram()),
	];
}

function delegationRequest(): HostInvocation | null {
	for (const call of invocations()) {
		if (call.program == Pubkey.delegationProgram()) { return call; }
	}
	return null;
}

test "delegatePet hands the pet to the delegation program for its owner and refuses a stranger" {
	now(1);
	const made = initialized();
	const accounts = claimed(made, 0);
	const refused = delegation(stranger, made, accounts[4]);
	assert run(programKey(), refused, instructionBytes("DelegatePet"), entry).result ==
		hibernalError(HibernalError.NotTheOwner).code;
	const delegated = delegation(owner, made, accounts[4]);
	assert run(programKey(), delegated, instructionBytes("DelegatePet"), entry).result == 0;
	assert delegated[2].owner == Pubkey.delegationProgram();
	const request = delegationRequest();
	assert request !== null;
	if (request !== null) {
		assert request.accounts[1].key == accounts[4].key && request.accounts[1].signer;
		assert keyAt(request.data, request.data.length - 32) == validator;
		assert request.data[request.data.length - 33] == 1;
	}
	assert delegated[4].lamports == 0;
}

test "delegateBlock and delegateWorld are the authority's" {
	now(0);
	const made = initialized();
	const block = blockCreated(made, authority, 0, blockKey(0))[0];
	assert run(programKey(), delegation(stranger, made, block), instructionBytes("DelegateBlock"), entry).result ==
		hibernalError(HibernalError.NotAuthority).code;
	const blockDelegated = delegation(authority, made, block);
	assert run(programKey(), blockDelegated, instructionBytes("DelegateBlock"), entry).result == 0;
	assert blockDelegated[2].owner == Pubkey.delegationProgram();
	const worldDelegated = delegation(authority, made, made[3]);
	assert run(programKey(), worldDelegated, instructionBytes("DelegateWorld"), entry).result == 0;
	assert worldDelegated[2].owner == Pubkey.delegationProgram();
	const wrongKind = delegation(authority, made, made[2]);
	assert run(programKey(), wrongKind, instructionBytes("DelegateWorld"), entry).result ==
		ProgramError.accountDiscriminatorMismatch().code;
}

test "processUndelegation answers the delegation program's fixed discriminator" {
	const discriminator = instructionDiscriminator("ProcessUndelegation");
	const expected: uint8[] = [196, 28, 41, 206, 48, 37, 51, 167];
	for (let i = 0; i < 8; i++) { assert discriminator.bytes[i] == expected[i]; }
	const forged = [blank(keyOf(70, 1)), wallet(stranger), wallet(stranger), executable(Pubkey.systemProgram())];
	const data = instructionBytes("ProcessUndelegation");
	pushU32(data, 1);
	pushU32(data, 5);
	data.push(119);
	data.push(111);
	data.push(114);
	data.push(108);
	data.push(100);
	assert run(programKey(), forged, data, entry).result == ProgramError.invalidAccountOwner().code;
}

function placeRan(made: HostAccount[], signer: Pubkey, block: HostAccount[], pet: HostAccount[]): uint64 {
	const accounts = [wallet(signer), readonly(made[1]), made[3], block[0], pet[4]];
	const result = run(programKey(), accounts, instructionBytes("Place"), entry).result;
	made[3] = accounts[2];
	block[0] = accounts[3];
	pet[4] = accounts[4];
	return result;
}

test "place seats pets in order, births them into the world and stops at ten" {
	now(2);
	const made = initialized();
	const block = blockCreated(made, authority, 0, blockKey(0));
	const first = claimed(made, 0);
	assert placeRan(made, stranger, block, first) == hibernalError(HibernalError.NotAuthority).code;
	assert placeRan(made, authority, block, first) == 0;
	assert u32At(first[4].data, PET_BLOCK) == 0 && first[4].data[PET_SLOT] == 0 && first[4].data[PET_ALIVE] == 1;
	assert contains(block[0].data, first[4].key);
	assert block[0].data[BLOCK_FILLED] == 1;
	assert u32At(made[3].data, WORLD_LIVING) == 1;
	assert placeRan(made, authority, block, first) == hibernalError(HibernalError.AlreadyPlaced).code;
	for (let index: uint8 = 1; index < SEATS as uint8; index++) {
		const next = claimed(made, index);
		assert placeRan(made, authority, block, next) == 0;
		assert next[4].data[PET_SLOT] == index;
	}
	assert block[0].data[BLOCK_FILLED] == SEATS as uint8;
	assert u32At(made[3].data, WORLD_LIVING) == SEATS as uint32;
	assert u32At(made[3].data, WORLD_PLACED) == SEATS as uint32;
	const late = claimed(made, 20);
	assert placeRan(made, authority, block, late) == hibernalError(HibernalError.BlockFull).code;
	const spare = blockCreated(made, authority, 1, blockKey(1));
	made[3].data[WORLD_RESORTING] = 1;
	assert placeRan(made, authority, spare, late) == hibernalError(HibernalError.Resorting).code;
	made[3].data[WORLD_RESORTING] = 0;
	assert placeRan(made, authority, spare, late) == 0;
	assert u32At(late[4].data, PET_BLOCK) == 1 && u32At(made[3].data, WORLD_PLACED) == (SEATS + 1) as uint32;
}
