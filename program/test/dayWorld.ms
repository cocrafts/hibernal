import { VRF_PROGRAM_ID, VRF_EPHEMERAL_QUEUE_ID } from "std/solana/vrf";
import { MAGIC_PROGRAM_ID } from "std/solana/magicblock";
import { readLines } from "std/fs";
import { Clock, Discriminator, Pubkey, instructionDiscriminator, SYSTEM_PROGRAM_ID, SLOTHASHES_ID, findProgramAddressOf } from "std/solana";
import { HostAccount } from "std/solana/host";

import { ACTS_PER_EPOCH, BLOCK_SLOTS, EPOCH_SECONDS, EconomyAction, GlobalConfig, Pet } from "../../rules/index";
import { World, actorAt, applyAttack, applyEconomy, applyNode, beginEpoch, endEpoch, inRound, staggered } from "../../sim/world";
import { OwnerKind } from "../../sim/owner";
import { act } from "../../sim/teacher";
import { Head, actionCount, largestActionCount, legalInto, observationSize, observeInto, zeros } from "../../sim/env/observe";
import { Scratch, bestLegal, create, logitsInto } from "../../sim/env/actor";
import { engineVersion } from "../../sim/digests";
import { ALLOCATE_HOLD, ATTACK_HOLD } from "../../rules/index";
import { Block, Config, Phase, PetAccount, Policy, VrfPayer, World as WorldAccount } from "../layout";
import { hydraProgram, magicVault } from "../hydra";

export const WORLD_SEED: uint64 = 9001;
export const PET_OFFSET: int32 = 120;
export const TEST_DAY: uint64 = 36;
export const TEST_DAYS: uint64 = 85;
export const TURN_PET: int32 = 14;
export const TURN_CRANK: int32 = 10;
export const ROUND_CRANK: int32 = 9;
export const FIRST_DUE_SLOT: uint64 = 1000;

export function keyOf(seed: uint8): Pubkey {
	let key = Pubkey.zero();
	key.bytes[0] = seed;
	key.bytes[1] = 0x5a;
	return key;
}

export function programKey(): Pubkey { return keyOf(200); }

export function bytesAt(address: Ptr<void>, count: int32): uint8[] {
	const source = address as Ptr<uint8>;
	const bytes: uint8[] = [];
	for (let position = 0; position < count; position++) { bytes.push(source[position]); }
	return bytes;
}

export function withDiscriminator(discriminator: Discriminator, body: uint8[]): uint8[] {
	const bytes: uint8[] = [];
	for (let position = 0; position < 8; position++) { bytes.push(discriminator.bytes[position]); }
	for (const value of body) { bytes.push(value); }
	return bytes;
}

export function owned(key: Pubkey, data: uint8[]): HostAccount {
	return { key: key, owner: programKey(), lamports: 1000000000, data: data, signer: false, writable: true, executable: false };
}

export function plain(key: Pubkey, writable: boolean, signer: boolean): HostAccount {
	return { key: key, owner: SYSTEM_PROGRAM_ID, lamports: 1000000000, data: [], signer: signer, writable: writable, executable: false };
}

export function executable(key: Pubkey): HostAccount {
	return { key: key, owner: keyOf(0), lamports: 1, data: [], signer: false, writable: false, executable: true };
}

export function policyBytes(): uint8[] {
	const lines = readLines("out/actProbe/policy.txt");
	const policy: uint8[] = [];
	if (!lines.ok) { return policy; }
	for (const text of lines.value) {
		if (text.length > 0) { policy.push(parseInt(text) as uint8); }
	}
	return policy;
}

export function quietWorld(): World {
	const world = World.staggered(1, WORLD_SEED);
	const owners = world.owners;
	for (let index = 0; index < owners.length; index++) { owners[index] = OwnerKind.Absent; }
	return { ...world, resort: { ...world.resort, wildDefenders: false } };
}

export function worldBeforeDay(day: uint64): World {
	let world = quietWorld();
	for (let previous: uint64 = 1; previous < day; previous++) {
		world = world.beginEpoch(previous);
		for (let round = 0; round < ACTS_PER_EPOCH; round++) {
			world = world.inRound(round);
			for (let turn = 0; turn < world.pets.length; turn++) { world = world.act(world.actorAt(turn)); }
		}
		world = world.endEpoch();
	}
	return world;
}

export function policyChoice(this world: World, index: int32, head: Head, scratch: Scratch, policy: uint8[]): int32 {
	const observations = zeros(observationSize(head));
	const legal = zeros(actionCount(head));
	const logits = zeros(largestActionCount());
	world.observeInto(index, head, observations, 0);
	world.legalInto(index, head, legal, 0);
	scratch.logitsInto(policy, head, observations, 0, legal, 0, logits, 0);
	const hold = match (head) {
		Head.Economy => EconomyAction.Rest as int32,
		Head.Node => ALLOCATE_HOLD,
		Head.Attack => ATTACK_HOLD,
	};
	return bestLegal(head, logits, 0, legal, 0, hold);
}

export function policyAct(this world: World, index: int32, policy: uint8[]): World {
	if (!world.pets[index].alive) { return world; }
	const scratch = Scratch.create();
	const economy = world.policyChoice(index, Head.Economy, scratch, policy);
	const afterEconomy = world.applyEconomy(index, economy as EconomyAction);
	const node = afterEconomy.policyChoice(index, Head.Node, scratch, policy);
	const afterNode = afterEconomy.applyNode(index, node);
	const attack = afterNode.policyChoice(index, Head.Attack, scratch, policy);
	return afterNode.applyAttack(index, attack);
}

export function policyAddress(): Pubkey {
	const found = findProgramAddressOf(programKey(), ["policy"]);
	return found.ok ? found.value.key : Pubkey.zero();
}

function policyBump(): uint8 {
	const found = findProgramAddressOf(programKey(), ["policy"]);
	return found.ok ? found.value.bump : 0;
}

export function configData(): uint8[] {
	const configs: Config[] = [{
		authority: keyOf(1),
		admissionGroup: keyOf(2),
		hbrnMint: keyOf(3),
		engine: engineVersion(),
		genesisTimestamp: 0,
		claimCapPerDay: 10000000,
		blocks: 1,
		pets: 10,
		bump: 255,
		mintBump: 255,
		policyBump: policyBump(),
		worldBump: 255,
		pad: 0,
		validator: Pubkey.zero(),
		skrMint: Pubkey.zero(),
		treasury: Pubkey.zero(),
		vrfQueue: VRF_EPHEMERAL_QUEUE_ID,
		secondsPerDay: EPOCH_SECONDS,
		staggerSeconds: 0,
		slotMillis: 10,
		turnGapSlots: 100,
	}];
	return withDiscriminator(Config.discriminator(), bytesAt(configs[0] as Ptr<void>, sizeof Config as int32));
}

export function policyData(policy: uint8[]): uint8[] {
	const held: Policy[] = [{ engine: engineVersion(), written: policy.length as uint32, sealed: 1, bump: 255, pad: 0, bytes: [] }];
	let bytes = held[0].bytes;
	for (let position = 0; position < policy.length; position++) { bytes[position] = policy[position]; }
	held[0] = { ...held[0], bytes: bytes };
	return withDiscriminator(Policy.discriminator(), bytesAt(held[0] as Ptr<void>, sizeof Policy as int32));
}

export function worldData(world: World, epoch: uint64): uint8[] {
	const held: WorldAccount[] = [{
		global: world.global,
		epoch: epoch,
		resortEvery: 0,
		rotation: 0,
		resortedEpoch: 0,
		bump: 255,
		resorting: 0,
		pad: 0,
		unplaced: 0,
		placed: 10,
		pad2: 0,
		secondsPerDay: EPOCH_SECONDS,
	}];
	return withDiscriminator(WorldAccount.discriminator(), bytesAt(held[0] as Ptr<void>, sizeof WorldAccount as int32));
}

export function blockData(world: World, day: uint64): uint8[] {
	let block: Block = {
		id: 0, filled: 10, phase: Phase.Idle as uint8, round: 0, cursor: 0, epoch: day, roundSeed: 0,
		requests: 0, pendingRequest: 0, requestedAt: 0, rotation: 0, minStrength: 0, maxStrength: 0,
		crankSeq: 1, dueSlot: FIRST_DUE_SLOT, dawnedEpoch: day - 1, fightHead: 0, bump: 255,
		turns: [], started: 1, pad: [], members: [], grudges: [], fights: [], listings: [], listed: [], relationships: [], pad2: 0,
	};
	let members = block.members;
	let grudges = block.grudges;
	for (let seat = 0; seat < BLOCK_SLOTS; seat++) {
		members[seat] = keyOf((10 + seat) as uint8);
		grudges[seat] = { robber: world.grudges[seat].robber as uint8, pad: [], epoch: world.grudges[seat].epoch };
	}
	let listings = block.listings;
	let listed = block.listed;
	for (let position = 0; position < world.market.length; position++) {
		listings[position] = world.market[position];
		listed[position] = 1;
	}
	block = { ...block, members: members, grudges: grudges, listings: listings, listed: listed };
	const blocks: Block[] = [block];
	return withDiscriminator(Block.discriminator(), bytesAt(blocks[0] as Ptr<void>, sizeof Block as int32));
}

export function petData(world: World, seat: int32): uint8[] {
	const records: PetAccount[] = [{
		owner: keyOf(100),
		mint: keyOf((40 + seat) as uint8),
		ordinal: seat as uint32,
		persona: world.personas[seat] as uint8,
		bump: 255,
		pad: 0,
		claimedEpoch: 1,
		diedEpoch: world.deathEpochs[seat],
		pet: world.pets[seat],
	}];
	return withDiscriminator(PetAccount.discriminator(), bytesAt(records[0] as Ptr<void>, sizeof PetAccount as int32));
}

export function vrfIdentity(): Pubkey {
	const found = findProgramAddressOf(VRF_PROGRAM_ID, ["identity", programKey()]);
	return found.ok ? found.value.key : Pubkey.zero();
}

export function programIdentity(): Pubkey {
	const found = findProgramAddressOf(programKey(), ["identity"]);
	return found.ok ? found.value.key : Pubkey.zero();
}

export function vrfPayerAccount(): HostAccount {
	const found = findProgramAddressOf(programKey(), ["vrf-payer"]);
	const payers: VrfPayer[] = [{ bump: found.ok ? found.value.bump : 0, pad: [] }];
	const key = found.ok ? found.value.key : Pubkey.zero();
	return owned(key, withDiscriminator(VrfPayer.discriminator(), bytesAt(payers[0] as Ptr<void>, sizeof VrfPayer as int32)));
}

export function crankKey(blockId: uint32, seq: uint64): Pubkey {
	let seed = Pubkey.zero();
	const program = programKey();
	const block = blockId as uint64;
	for (let index = 0; index < 8; index++) {
		const shift = (index * 8) as uint64;
		seed.bytes[index] = ((block >> shift) & 0xff) as uint8;
		seed.bytes[8 + index] = ((seq >> shift) & 0xff) as uint8;
	}
	for (let index = 0; index < 16; index++) { seed.bytes[16 + index] = program.bytes[index]; }
	const found = findProgramAddressOf(Pubkey.hydraProgram(), ["crank", seed]);
	return found.ok ? found.value.key : Pubkey.zero();
}

export function turnAccounts(world: World, day: uint64, policy: uint8[]): HostAccount[] {
	const held: HostAccount[] = [
		vrfPayerAccount(),
		{ ...owned(keyOf(5), configData()), writable: false },
		owned(keyOf(6), worldData(world, day - 1)),
		owned(keyOf(7), blockData(world, day)),
		{ ...owned(policyAddress(), policyData(policy)), writable: false },
		plain(programIdentity(), false, false),
		plain(VRF_EPHEMERAL_QUEUE_ID, true, false),
		plain(SLOTHASHES_ID, false, false),
		executable(SYSTEM_PROGRAM_ID),
		executable(VRF_PROGRAM_ID),
		plain(crankKey(0, 1), true, false),
		plain(Pubkey.magicVault(), true, false),
		executable(MAGIC_PROGRAM_ID),
		executable(Pubkey.hydraProgram()),
	];
	for (let seat = 0; seat < BLOCK_SLOTS; seat++) {
		held.push(owned(keyOf((10 + seat) as uint8), petData(world, seat)));
	}
	return held;
}

export function withNextCrank(step: HostAccount[]): void {
	const block = blockOf(step);
	step[TURN_CRANK] = plain(crankKey(block.id, block.crankSeq), true, false);
}

export function roundStartAccounts(step: HostAccount[]): HostAccount[] {
	const block = blockOf(step);
	return [
		step[0],
		step[1],
		{ ...step[2], writable: false },
		step[3],
		step[5],
		step[6],
		step[7],
		step[8],
		step[9],
		plain(crankKey(block.id, block.crankSeq), true, false),
		step[11],
		step[12],
		step[13],
	];
}

export function roundStartReturned(step: HostAccount[], round: HostAccount[]): void {
	step[0] = round[0];
	step[3] = round[3];
}

export function seededAccounts(step: HostAccount[]): HostAccount[] {
	return [plain(vrfIdentity(), false, true), step[3]];
}

export function returned(step: HostAccount[], seeded: HostAccount[]): void {
	step[3] = seeded[1];
}

export function stepData(name: string, seq: uint64): uint8[] {
	const bytes = instructionBytes(name);
	pushU64(bytes, seq);
	return bytes;
}

export function currentSeq(step: HostAccount[]): uint64 {
	return blockOf(step).crankSeq - 1;
}

export function dueClock(step: HostAccount[], day: uint64): Clock {
	const due = at(day);
	return { ...due, slot: blockOf(step).dueSlot };
}

export function instructionBytes(name: string): uint8[] {
	const discriminator = instructionDiscriminator(name);
	const bytes: uint8[] = [];
	for (let position = 0; position < 8; position++) { bytes.push(discriminator.bytes[position]); }
	return bytes;
}

export function pushU64(bytes: uint8[], value: uint64): void {
	for (let shift: uint64 = 0; shift < 64; shift += 8) { bytes.push(((value >> shift) & 255) as uint8); }
}

export function seededData(seed: uint64, request: uint64): uint8[] {
	const bytes = instructionBytes("Seeded");
	pushU64(bytes, seed);
	for (let position = 8; position < 32; position++) { bytes.push(0); }
	pushU64(bytes, request);
	return bytes;
}

export function petsOf(step: HostAccount[]): Pet[] {
	const pets: Pet[] = [];
	for (let seat = 0; seat < BLOCK_SLOTS; seat++) {
		pets.push(petOfData(step[TURN_PET + seat].data));
	}
	return pets;
}

export function petOfData(data: uint8[]): Pet {
	const scratch = quietWorld();
	const holder: Pet[] = [scratch.pets[0]];
	const target = holder[0] as Ptr<void> as Ptr<uint8>;
	for (let position = 0; position < (sizeof Pet as int32); position++) {
		target[position] = data[8 + PET_OFFSET + position];
	}
	return holder[0];
}

export function globalOf(step: HostAccount[]): GlobalConfig {
	const scratch = quietWorld();
	const holder: GlobalConfig[] = [scratch.global];
	const target = holder[0] as Ptr<void> as Ptr<uint8>;
	for (let position = 0; position < (sizeof GlobalConfig as int32); position++) {
		target[position] = step[2].data[8 + position];
	}
	return holder[0];
}

export function blockOf(step: HostAccount[]): Block {
	const scratch: Block[] = [{
		id: 0, filled: 0, phase: 0, round: 0, cursor: 0, epoch: 0, roundSeed: 0,
		requests: 0, pendingRequest: 0, requestedAt: 0, rotation: 0, minStrength: 0, maxStrength: 0,
		crankSeq: 0, dueSlot: 0, dawnedEpoch: 0, fightHead: 0, bump: 0,
		turns: [], started: 0, pad: [], members: [], grudges: [], fights: [], listings: [], listed: [], relationships: [], pad2: 0,
	}];
	const target = scratch[0] as Ptr<void> as Ptr<uint8>;
	for (let position = 0; position < (sizeof Block as int32); position++) { target[position] = step[3].data[8 + position]; }
	return scratch[0];
}

export function at(day: uint64): Clock {
	return { slot: FIRST_DUE_SLOT, epochStartTimestamp: 0, epoch: 1, leaderScheduleEpoch: 1, unixTimestamp: (day * EPOCH_SECONDS + 600) as int64 };
}

