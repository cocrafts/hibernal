import { readLines } from "std/fs";
import {
	BLOCK_SLOTS,
	Pet,
	EconomyAction,
	SelfFeature,
	FEATURE_ONE,
	checkPolicy,
} from "../../rules/index";
import { engineVersion } from "../digests";
import { World, actorAt, applyEconomy, applyNode, applyAttack } from "../world";
import { Batch, Done, withPolicy, assign, petOf, policyAction, step } from "./batch";
import {
	Head,
	observationSize,
	actionCount,
	observeInto,
	legalInto,
	zeros,
} from "./observe";

test "p31s5 acts legally on a spawned wild without changing its absent pet" {
	const loaded = readLines("out/actProbe/policy.txt");
	assert loaded.ok;
	if (loaded.ok) {
		const policy: uint8[] = [];
		for (const line of loaded.value) {
			if (line.length > 0) { policy.push(parseInt(line) as uint8); }
		}
		assert checkPolicy(policy, engineVersion()).ok;
		let batch = Batch.create(8, 1, 1, 12);
		assert batch.withPolicy(0, policy);
		const index = 7;
		let turn = 0;
		for (let candidate = 0; candidate < BLOCK_SLOTS; candidate++) {
			if (batch.worlds[0].actorAt(candidate) == index) { turn = candidate; }
		}
		batch = { ...batch, cursor: { ...batch.cursor, turn: turn } };
		assert batch.petOf(0) == index;
		assert batch.assign(0, index, 0);
		assert batch.worlds[0].pets[index].wild && batch.worlds[0].pets[index].alive;
		const absent = batch.worlds[0].absent[index];
		assert !absent.alive && !absent.wild;
		const actions = zeros(1);
		const rewards = zeros(1);
		const dones = zeros(1);
		let changed = false;
		for (let ordinal = 0; ordinal <= (Head.Attack as int32); ordinal++) {
			const head = ordinal as Head;
			const world = batch.worlds[0];
			const before = world.pets[index];
			const features = zeros(observationSize(head));
			const legal = zeros(actionCount(head));
			world.observeInto(index, head, features, 0);
			world.legalInto(index, head, legal, 0);
			assert features[SelfFeature.Hearts as int32] > 0;
			assert features[SelfFeature.Hearts as int32] ==
				(before.hearts as int32) * FEATURE_ONE / (before.maxHearts as int32);
			const selected = batch.policyAction(world, index, 0);
			assert legal[selected] == 1;
			const expectedPets: Pet[] = [];
			for (const pet of world.pets) { expectedPets.push(pet); }
			const copied: World = { ...world, pets: expectedPets };
			const expected = match (head) {
				Head.Economy => copied.applyEconomy(index, selected as EconomyAction),
				Head.Node => copied.applyNode(index, selected),
				Head.Attack => copied.applyAttack(index, selected),
			};
			actions[0] = -99;
			const stepped = batch.step(head, actions, rewards, dones);
			assert stepped.ok;
			if (stepped.ok) { batch = stepped.value; }
			assert batch.worlds[0].pets[index] == expected.pets[index];
			assert batch.worlds[0].global == expected.global;
			assert batch.worlds[0].stats.illegal == 0;
			assert batch.worlds[0].absent[index] == absent;
			assert batch.worlds[0].pets[index].wild;
			assert dones[0] == (Done.Running as int32);
			changed = changed || !(batch.worlds[0].pets[index] == before);
		}
		assert changed;
	}
}
