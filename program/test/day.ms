import { VRF_PROGRAM_ID } from "std/solana/vrf";
import { MAGIC_PROGRAM_ID } from "std/solana/magicblock";
import { ACTS_PER_EPOCH, BLOCK_SLOTS, BlockSlot, Pet, checkPolicy, movedTo, withDeath } from "../../rules/index";
import { HostAccount, HostRun, invocations, run, setClock } from "std/solana/host";
import { Pubkey, SYSTEM_PROGRAM_ID } from "std/solana";

import { actorAt, beginEpoch, endEpoch, inRound } from "../../sim/world";
import { GRUDGE_EPOCHS as SIM_GRUDGE_EPOCHS } from "../../sim/world";
import { engineVersion } from "../../sim/digests";
import { digestOf } from "../../tools/actBench";
import { Block, HibernalError, NO_BLOCK, Phase, PetAccount, World as WorldAccount, hibernalError } from "../layout";
import { GRUDGE_EPOCHS, SEED_RETRY_SECONDS, seededDiscriminator } from "../day";
import { hydraProgram, magicVault } from "../hydra";
import { entry } from "../main";
import { FIRST_DUE_SLOT, PET_OFFSET, TEST_DAY, TEST_DAYS, WORLD_SEED, at, blockOf, bytesAt, crankKey, currentSeq, dueClock, executable, globalOf, instructionBytes, keyOf, owned, petsOf, plain, policyAct, policyBytes, programKey, TURN_PET, returned, roundStartAccounts, roundStartReturned, seededAccounts, seededData, stepData, turnAccounts, withDiscriminator, withNextCrank, worldBeforeDay } from "./dayWorld";

const CANCEL: uint8 = 2;

function passed(outcome: HostRun): boolean {
	return outcome.result == 0 && outcome.fault == "";
}

function refusedWith(outcome: HostRun, error: HibernalError): boolean {
	return outcome.result == hibernalError(error).code;
}

function worldOfData(data: uint8[]): WorldAccount {
	const scratch: WorldAccount[] = [{
		global: { genesisTimestamp: 0, rewardPerWorkPower: 0, rewardEpoch: 0, totalWorkPower: 0, recycledPending: 0, treasury: 0, itemReserve: 0, emitted: 0, livingPets: 0, floorSlots: 0 },
		epoch: 0, resortEvery: 0, rotation: 0, resortedEpoch: 0, bump: 0, resorting: 0, pad: 0, unplaced: 0, placed: 0, pad2: 0, secondsPerDay: 0,
	}];
	const target = scratch[0] as Ptr<void> as Ptr<uint8>;
	for (let position = 0; position < (sizeof WorldAccount as int32); position++) { target[position] = data[8 + position]; }
	return scratch[0];
}

function withWorld(data: uint8[], world: WorldAccount): uint8[] {
	const copy: uint8[] = [];
	for (const value of data) { copy.push(value); }
	const worlds: WorldAccount[] = [world];
	const source = worlds[0] as Ptr<void> as Ptr<uint8>;
	for (let position = 0; position < (sizeof WorldAccount as int32); position++) { copy[8 + position] = source[position]; }
	return copy;
}

function withResorting(data: uint8[]): uint8[] {
	return withWorld(data, { ...worldOfData(data), resorting: 1 });
}

function withPet(data: uint8[], pet: Pet): uint8[] {
	const copy: uint8[] = [];
	for (const value of data) { copy.push(value); }
	const pets: Pet[] = [pet];
	const source = pets[0] as Ptr<void> as Ptr<uint8>;
	for (let position = 0; position < (sizeof Pet as int32); position++) { copy[8 + PET_OFFSET + position] = source[position]; }
	return copy;
}

function withBlock(step: HostAccount[], block: Block): void {
	const blocks: Block[] = [block];
	step[3] = { ...step[3], data: withDiscriminator(Block.discriminator(), bytesAt(blocks[0] as Ptr<void>, sizeof Block as int32)) };
}

function sameBytes(left: uint8[], right: uint8[]): boolean {
	if (left.length != right.length) { return false; }
	for (let position = 0; position < left.length; position++) {
		if (left[position] != right[position]) { return false; }
	}
	return true;
}

function roundStarted(step: HostAccount[], day: uint64): HostRun {
	setClock(dueClock(step, day));
	const round = roundStartAccounts(step);
	const outcome = run(programKey(), round, stepData("RoundStart", currentSeq(step)), entry);
	roundStartReturned(step, round);
	return outcome;
}

function seededWith(step: HostAccount[], request: uint64): HostRun {
	const seeded = seededAccounts(step);
	const outcome = run(programKey(), seeded, seededData(WORLD_SEED, request), entry);
	returned(step, seeded);
	return outcome;
}

function seatedPets(step: HostAccount[]): Pet[] {
	const pets = petsOf(step);
	for (let seat = 0; seat < BLOCK_SLOTS; seat++) {
		if (pets[seat].blockId == NO_BLOCK) { pets[seat] = { ...pets[seat], blockId: blockOf(step).id, slot: seat as uint8 }; }
	}
	return pets;
}

function heirsPlaced(step: HostAccount[]): boolean {
	for (let seat = 0; seat < BLOCK_SLOTS; seat++) {
		const pet = petsOf(step)[seat];
		if (!pet.alive || pet.blockId != NO_BLOCK) { continue; }
		let block = blockOf(step);
		let first = 0;
		while (first < BLOCK_SLOTS && !block.members[first].isZero()) { first += 1; }
		if (first != seat) { return false; }
		block.members[seat] = step[TURN_PET + seat].key;
		block.filled = block.filled + 1;
		withBlock(step, block);
		const world = worldOfData(step[2].data);
		step[2] = { ...step[2], data: withWorld(step[2].data, { ...world, placed: world.placed + 1 }) };
		step[TURN_PET + seat] = { ...step[TURN_PET + seat], data: withPet(step[TURN_PET + seat].data, pet.movedTo(block.id, seat as BlockSlot)) };
	}
	return true;
}

function turned(step: HostAccount[], day: uint64): HostRun {
	withNextCrank(step);
	setClock(dueClock(step, day));
	return run(programKey(), step, stepData("Turn", currentSeq(step)), entry);
}

function startAccounts(step: HostAccount[], signer: Pubkey): HostAccount[] {
	const block = blockOf(step);
	return [
		plain(signer, false, true),
		step[1],
		{ ...step[2], writable: false },
		step[3],
		step[0],
		plain(crankKey(block.id, block.crankSeq), true, false),
		plain(Pubkey.magicVault(), true, false),
		executable(MAGIC_PROGRAM_ID),
		executable(Pubkey.hydraProgram()),
	];
}

function crankData(authority: Pubkey, remaining: uint64): uint8[] {
	const data: uint8[] = [];
	for (let position = 0; position < 32; position++) { data.push(authority.bytes[position]); }
	for (let position = 32; position < 80; position++) { data.push(0); }
	for (let shift: uint64 = 0; shift < 64; shift += 8) { data.push(((remaining >> shift) & 255) as uint8); }
	for (let position = 88; position < 140; position++) { data.push(0); }
	return data;
}

function crankHolder(key: Pubkey, owner: Pubkey, data: uint8[]): HostAccount {
	return { key: key, owner: owner, lamports: 0, data: data, signer: false, writable: true, executable: false };
}

function cancelsOf(key: Pubkey): int32 {
	let count = 0;
	for (const call of invocations()) {
		if (call.program == Pubkey.hydraProgram() && call.data.length > 0 && call.data[0] == CANCEL && call.accounts[1].key == key) { count += 1; }
	}
	return count;
}

test "the program keeps the sim's grudge window and the pet record keeps its pet at a fixed offset" {
	assert GRUDGE_EPOCHS == SIM_GRUDGE_EPOCHS;
	assert (sizeof PetAccount as int32) == PET_OFFSET + (sizeof Pet as int32);
	const expectedSeededDiscriminator: uint64 = 17358739751253998038;
	assert seededDiscriminator() == expectedSeededDiscriminator;
}

test "ten days of a block on the program match the sim acting with the same policy and seed" {
	const policy = policyBytes();
	assert checkPolicy(policy, engineVersion()).ok;
	let world = worldBeforeDay(TEST_DAY);
	const fightsBefore = world.stats.fights;
	const deathsBefore = world.stats.deaths;
	const heirsBefore = world.stats.heirs;
	const salesBefore = world.stats.sales;
	const step = turnAccounts(world, TEST_DAY, policy);
	for (let day = TEST_DAY; day < TEST_DAY + TEST_DAYS; day++) {
		for (let round = 0; round < ACTS_PER_EPOCH; round++) {
			assert passed(roundStarted(step, day));
			assert blockOf(step).phase == (Phase.Seeding as uint8);
			assert passed(seededWith(step, blockOf(step).pendingRequest));
			assert blockOf(step).phase == (Phase.Acting as uint8);
			if (day == TEST_DAY && round == 0) {
				assert passed(turned(step, day));
				assert blockOf(step).dawnedEpoch == day && blockOf(step).cursor == 0;
				world = world.beginEpoch(day);
			} else if (round > 0) {
				world = world.inRound(round);
			}
			assert digestOf(petsOf(step), globalOf(step)) == digestOf(world.pets, world.global);
			for (let turn = 0; turn < BLOCK_SLOTS; turn += 2) {
				assert passed(turned(step, day));
				world = world.policyAct(world.actorAt(turn), policy);
				if (turn + 1 < BLOCK_SLOTS) { world = world.policyAct(world.actorAt(turn + 1), policy); }
				assert digestOf(petsOf(step), globalOf(step)) == digestOf(world.pets, world.global);
			}
			if (round < ACTS_PER_EPOCH - 1) {
				assert blockOf(step).phase == (Phase.Idle as uint8) && blockOf(step).round == (round + 1) as uint8;
			}
		}
		assert blockOf(step).phase == (Phase.Acting as uint8) && blockOf(step).cursor == BLOCK_SLOTS as uint8;
		assert blockOf(step).round == (ACTS_PER_EPOCH - 1) as uint8;
		assert passed(turned(step, day));
		world = world.endEpoch();
		world = world.beginEpoch(day + 1);
		assert digestOf(seatedPets(step), globalOf(step)) == digestOf(world.pets, world.global);
		assert heirsPlaced(step);
		assert digestOf(seatedPets(step), globalOf(step)) == digestOf(world.pets, world.global);
		for (const pet of petsOf(step)) { assert !pet.alive || pet.blockId != NO_BLOCK; }
		const ended = blockOf(step);
		assert ended.phase == (Phase.Idle as uint8) && ended.epoch == day + 1 && ended.round == 0;
		assert ended.dawnedEpoch == day + 1;
	}
	const fights = world.stats.fights - fightsBefore;
	console.log(`days ${TEST_DAY}..${TEST_DAY + TEST_DAYS - 1}: ${fights} fights, ${world.stats.deaths - deathsBefore} deaths, ${world.stats.heirs - heirsBefore} heirs, ${world.stats.sales - salesBefore} sales, block fight head ${blockOf(step).fightHead}, cranks ${blockOf(step).crankSeq}`);
	assert fights > 0 && (blockOf(step).fightHead as int32) == fights % 32;
}

test "a pet starved by dusk is lost: half its wallet to one living mate, half to the treasury, its seat freed" {
	const policy = policyBytes();
	let world = worldBeforeDay(TEST_DAY);
	const victim = world.pets[3];
	assert victim.alive;
	world.pets[3] = { ...victim, alive: false, hearts: 0, harvest: 600, burrow: 401 };
	world = { ...world, global: world.global.withDeath(victim.stats().rewardWeight()) };
	const heirsBefore = world.stats.heirs;
	const step = turnAccounts(world, TEST_DAY, policy);
	const placedBefore = worldOfData(step[2].data).placed;
	for (let round = 0; round < ACTS_PER_EPOCH; round++) {
		assert passed(roundStarted(step, TEST_DAY));
		assert passed(seededWith(step, blockOf(step).pendingRequest));
		if (round == 0) {
			assert passed(turned(step, TEST_DAY));
			world = world.beginEpoch(TEST_DAY);
		} else {
			world = world.inRound(round);
		}
		for (let turn = 0; turn < BLOCK_SLOTS; turn += 2) {
			assert passed(turned(step, TEST_DAY));
			world = world.policyAct(world.actorAt(turn), policy);
			if (turn + 1 < BLOCK_SLOTS) { world = world.policyAct(world.actorAt(turn + 1), policy); }
		}
	}
	assert passed(turned(step, TEST_DAY));
	world = world.endEpoch().beginEpoch(TEST_DAY + 1);
	assert digestOf(seatedPets(step), globalOf(step)) == digestOf(world.pets, world.global);
	const lost = petsOf(step)[3];
	assert !lost.alive && lost.blockId == NO_BLOCK && lost.harvest == 0 && lost.burrow == 0;
	assert blockOf(step).members[3].isZero() && blockOf(step).filled == (BLOCK_SLOTS - 1) as uint8;
	assert worldOfData(step[2].data).placed == placedBefore - 1;
	assert world.stats.heirs == heirsBefore && world.deathEpochs[3] == TEST_DAY;
}

test "a step refuses a stale seq and an early slot, a forged callback is refused and a stale one changes nothing" {
	const policy = policyBytes();
	const world = worldBeforeDay(TEST_DAY);
	const step = turnAccounts(world, TEST_DAY, policy);
	setClock(dueClock(step, TEST_DAY));
	const stale = roundStartAccounts(step);
	assert refusedWith(run(programKey(), stale, stepData("RoundStart", 5), entry), HibernalError.StaleStep);
	setClock({ ...dueClock(step, TEST_DAY), slot: FIRST_DUE_SLOT - 10 });
	const early = roundStartAccounts(step);
	assert refusedWith(run(programKey(), early, stepData("RoundStart", currentSeq(step)), entry), HibernalError.TooEarly);
	assert passed(roundStarted(step, TEST_DAY));
	const request = blockOf(step).pendingRequest;
	const forged = seededAccounts(step);
	forged[0] = { ...forged[0], signer: false };
	assert run(programKey(), forged, seededData(WORLD_SEED, request), entry).result != 0;
	const before = step[3].data;
	assert passed(seededWith(step, request + 1));
	assert sameBytes(step[3].data, before) && blockOf(step).phase == (Phase.Seeding as uint8);
}

test "a turn that finds no seed waits, asks again after the retry window and the newest callback wins" {
	const policy = policyBytes();
	const world = worldBeforeDay(TEST_DAY);
	const step = turnAccounts(world, TEST_DAY, policy);
	assert passed(roundStarted(step, TEST_DAY));
	const first = blockOf(step).pendingRequest;
	const crankBefore = blockOf(step).crankSeq;
	assert passed(turned(step, TEST_DAY));
	assert blockOf(step).phase == (Phase.Seeding as uint8) && blockOf(step).pendingRequest == first;
	assert blockOf(step).crankSeq == crankBefore + 1;
	withNextCrank(step);
	const later = dueClock(step, TEST_DAY);
	setClock({ ...later, unixTimestamp: later.unixTimestamp + SEED_RETRY_SECONDS });
	assert passed(run(programKey(), step, stepData("Turn", currentSeq(step)), entry));
	const second = blockOf(step).pendingRequest;
	assert second == first + 1 && blockOf(step).phase == (Phase.Seeding as uint8);
	assert passed(seededWith(step, first));
	assert blockOf(step).phase == (Phase.Seeding as uint8);
	assert passed(seededWith(step, second));
	assert blockOf(step).phase == (Phase.Acting as uint8);
}

test "while re-sorting a round start reschedules itself instead of asking for a seed" {
	const policy = policyBytes();
	const world = worldBeforeDay(TEST_DAY);
	const step = turnAccounts(world, TEST_DAY, policy);
	step[2] = { ...step[2], data: withResorting(step[2].data) };
	assert passed(roundStarted(step, TEST_DAY));
	assert blockOf(step).phase == (Phase.Idle as uint8) && blockOf(step).requests == 0 && blockOf(step).crankSeq == 2;
	const calls = invocations();
	assert calls[calls.length - 1].program == Pubkey.hydraProgram();
}

test "the VRF request and the next crank are paid and signed by the program's payer PDA, on the configured queue only" {
	const policy = policyBytes();
	const world = worldBeforeDay(TEST_DAY);
	const impostor = turnAccounts(world, TEST_DAY, policy);
	impostor[0] = { ...impostor[0], key: keyOf(1) };
	assert roundStarted(impostor, TEST_DAY).result != 0;
	const elsewhere = turnAccounts(world, TEST_DAY, policy);
	elsewhere[6] = { ...elsewhere[6], key: keyOf(2) };
	assert roundStarted(elsewhere, TEST_DAY).result != 0;
	const step = turnAccounts(world, TEST_DAY, policy);
	assert !step[0].signer;
	assert passed(roundStarted(step, TEST_DAY));
	const calls = invocations();
	const request = calls[calls.length - 2];
	assert request.program == VRF_PROGRAM_ID;
	assert request.accounts[0].key == step[0].key && request.accounts[0].signer && request.accounts[0].writable;
	assert request.signers == 2;
	const created = calls[calls.length - 1];
	assert created.program == Pubkey.hydraProgram() && created.signers == 1;
	assert created.accounts[0].key == step[0].key && created.accounts[0].signer;
	assert created.accounts[1].key == crankKey(0, 1);
}

test "start block is the authority's, starts a fresh block at the current round and resumes only a dead chain" {
	const policy = policyBytes();
	const world = worldBeforeDay(TEST_DAY);
	const step = turnAccounts(world, TEST_DAY, policy);
	withBlock(step, { ...blockOf(step), started: 0, crankSeq: 0, dueSlot: 0, epoch: 0 });
	setClock(at(TEST_DAY));
	const stranger = startAccounts(step, keyOf(99));
	assert refusedWith(run(programKey(), stranger, stepData("StartBlock", 0), entry), HibernalError.NotAuthority);
	const fresh = startAccounts(step, keyOf(1));
	assert passed(run(programKey(), fresh, stepData("StartBlock", 0), entry));
	step[3] = fresh[3];
	assert blockOf(step).started == 1 && blockOf(step).epoch == TEST_DAY && blockOf(step).round == 0;
	assert blockOf(step).crankSeq == 1 && blockOf(step).phase == (Phase.Idle as uint8);
	const calls = invocations();
	assert calls[calls.length - 1].program == Pubkey.hydraProgram() && calls[calls.length - 1].accounts[1].key == crankKey(0, 0);
	setClock({ ...at(TEST_DAY), slot: blockOf(step).dueSlot + 100 });
	const alive = startAccounts(step, keyOf(1));
	assert refusedWith(run(programKey(), alive, stepData("StartBlock", 0), entry), HibernalError.ChainAlive);
	setClock({ ...at(TEST_DAY), slot: blockOf(step).dueSlot + 3001 });
	const resumed = startAccounts(step, keyOf(1));
	assert passed(run(programKey(), resumed, stepData("StartBlock", 0), entry));
	step[3] = resumed[3];
	assert blockOf(step).crankSeq == 2;
}

test "sweep cancels only spent cranks whose authority is the payer PDA" {
	const policy = policyBytes();
	const world = worldBeforeDay(TEST_DAY);
	const step = turnAccounts(world, TEST_DAY, policy);
	const payer = step[0].key;
	const spent = keyOf(150);
	const live = keyOf(151);
	const foreign = keyOf(152);
	const orphan = keyOf(153);
	const swept: HostAccount[] = [
		step[0],
		plain(Pubkey.magicVault(), true, false),
		executable(MAGIC_PROGRAM_ID),
		executable(Pubkey.hydraProgram()),
		crankHolder(spent, Pubkey.hydraProgram(), crankData(payer, 0)),
		crankHolder(live, Pubkey.hydraProgram(), crankData(payer, 1)),
		crankHolder(foreign, Pubkey.hydraProgram(), crankData(keyOf(9), 0)),
		crankHolder(orphan, SYSTEM_PROGRAM_ID, crankData(payer, 0)),
	];
	assert passed(run(programKey(), swept, stepData("Sweep", 0), entry));
	assert cancelsOf(spent) == 1 && cancelsOf(live) == 0 && cancelsOf(foreign) == 0 && cancelsOf(orphan) == 0;
}
