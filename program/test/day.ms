import { ACTS_PER_EPOCH, BLOCK_SLOTS, Pet, checkPolicy } from "../../rules/index";
import { HostRun, run, setClock } from "std/solana/host";
import { actorAt, beginEpoch, endEpoch, inRound } from "../../sim/world";
import { GRUDGE_EPOCHS as SIM_GRUDGE_EPOCHS } from "../../sim/world";
import { engineVersion } from "../../sim/digests";
import { digestOf } from "../../tools/actBench";
import { Phase, PetAccount, World as WorldAccount } from "../layout";
import { GRUDGE_EPOCHS, SEED_RETRY_SECONDS, seededDiscriminator } from "../day";
import { entry } from "../main";
import {
	PET_OFFSET,
	TEST_DAY,
	TEST_DAYS,
	WORLD_SEED,
	at,
	blockOf,
	globalOf,
	instructionBytes,
	petsOf,
	policyAct,
	policyBytes,
	programKey,
	returned,
	seededAccounts,
	seededData,
	stepAccounts,
	worldBeforeDay,
} from "./dayWorld";

function passed(outcome: HostRun): boolean {
	return outcome.result == 0 && outcome.fault == "";
}

function withResorting(data: uint8[]): uint8[] {
	const copy: uint8[] = [];
	for (const value of data) { copy.push(value); }
	const scratch: WorldAccount[] = [{
		global: { genesisTimestamp: 0, rewardPerWorkPower: 0, rewardEpoch: 0, totalWorkPower: 0, recycledPending: 0, protocolPending: 0, burned: 0, livingPets: 0, floorSlots: 0 },
		epoch: 0, resortEvery: 0, rotation: 0, resortedEpoch: 0, bump: 0, resorting: 0, pad: 0, unplaced: 0,
	}];
	const target = scratch[0] as Ptr<void> as Ptr<uint8>;
	for (let position = 0; position < (sizeof WorldAccount as int32); position++) { target[position] = copy[8 + position]; }
	scratch[0] = { ...scratch[0], resorting: 1 };
	const source = scratch[0] as Ptr<void> as Ptr<uint8>;
	for (let position = 0; position < (sizeof WorldAccount as int32); position++) { copy[8 + position] = source[position]; }
	return copy;
}

test "the program keeps the sim's grudge window and the pet record keeps its pet at a fixed offset" {
	assert GRUDGE_EPOCHS == SIM_GRUDGE_EPOCHS;
	assert (sizeof PetAccount as int32) >= PET_OFFSET + (sizeof Pet as int32);
	assert seededDiscriminator() != 0;
}

test "ten days of a block on the program match the sim acting with the same policy and seed" {
	const policy = policyBytes();
	assert checkPolicy(policy, engineVersion()).ok;
	let world = worldBeforeDay(TEST_DAY);
	const fightsBefore = world.stats.fights;
	const deathsBefore = world.stats.deaths;
	const heirsBefore = world.stats.heirs;
	const salesBefore = world.stats.sales;
	const step = stepAccounts(world, TEST_DAY - 1, policy);
	let request: uint64 = 0;
	for (let day = TEST_DAY; day < TEST_DAY + TEST_DAYS; day++) {
		setClock(at(day));
		const dawn = run(programKey(), step, instructionBytes("Step"), entry);
		assert passed(dawn);
		world = world.beginEpoch(day);
		for (let round = 0; round < ACTS_PER_EPOCH; round++) {
			request += 1;
			const seeded = seededAccounts(step);
			const callback = run(programKey(), seeded, seededData(WORLD_SEED, request), entry);
			assert passed(callback);
			returned(step, seeded);
			world = world.inRound(round);
			assert digestOf(petsOf(step), globalOf(step)) == digestOf(world.pets, world.global);
			for (let turn = 0; turn < BLOCK_SLOTS; turn++) {
				const acted = run(programKey(), step, instructionBytes("Step"), entry);
				assert passed(acted);
				world = world.policyAct(world.actorAt(turn), policy);
				assert digestOf(petsOf(step), globalOf(step)) == digestOf(world.pets, world.global);
			}
		}
		const dusk = run(programKey(), step, instructionBytes("Step"), entry);
		assert passed(dusk);
		world = world.endEpoch();
		assert digestOf(petsOf(step), globalOf(step)) == digestOf(world.pets, world.global);
	}
	const fights = world.stats.fights - fightsBefore;
	console.log(`days ${TEST_DAY}..${TEST_DAY + TEST_DAYS - 1}: ${fights} fights, ${world.stats.deaths - deathsBefore} deaths, ${world.stats.heirs - heirsBefore} heirs, ${world.stats.sales - salesBefore} sales, block fight head ${blockOf(step).fightHead}`);
	assert fights > 0 && (blockOf(step).fightHead as int32) == fights % 32;
}

test "a block refuses an early dawn, a second request, a stale or forged callback and acts while re-sorting" {
	const policy = policyBytes();
	const world = worldBeforeDay(TEST_DAY);
	const step = stepAccounts(world, TEST_DAY - 1, policy);
	setClock(at(TEST_DAY - 1));
	assert run(programKey(), step, instructionBytes("Step"), entry).result != 0;
	setClock(at(TEST_DAY));
	assert run(programKey(), step, instructionBytes("Step"), entry).result == 0;
	assert run(programKey(), step, instructionBytes("Step"), entry).result != 0;
	const stale = seededAccounts(step);
	assert run(programKey(), stale, seededData(WORLD_SEED, 2), entry).result != 0;
	const forged = seededAccounts(step);
	forged[0] = { ...forged[0], signer: false };
	assert run(programKey(), forged, seededData(WORLD_SEED, 1), entry).result != 0;
	const later = at(TEST_DAY);
	setClock({ ...later, unixTimestamp: later.unixTimestamp + SEED_RETRY_SECONDS });
	assert run(programKey(), step, instructionBytes("Step"), entry).result == 0;
	const superseded = seededAccounts(step);
	assert run(programKey(), superseded, seededData(WORLD_SEED, 1), entry).result != 0;
	const fresh = seededAccounts(step);
	assert run(programKey(), fresh, seededData(WORLD_SEED, 2), entry).result == 0;
	returned(step, fresh);
	assert blockOf(step).phase == (Phase.Acting as uint8);
	step[2] = { ...step[2], data: withResorting(step[2].data) };
	assert run(programKey(), step, instructionBytes("Step"), entry).result != 0;
}
