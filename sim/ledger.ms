import { ACTS_PER_EPOCH, EMISSION_CAP, HBRN_UNIT, pendingReward } from "../rules/index";
import { World, WORLD_BLOCKS } from "./world";
import { act } from "./teacher";

const LEDGER_EPOCHS: int32 = 400;
const REPORT_EVERY: int32 = 10;

export struct Ledger {
	held: uint64;
	pets: uint64;
	unsettled: uint64;
	absent: uint64;
}

export function ledger(this world: World): Ledger {
	let pets: uint64 = 0;
	let unsettled: uint64 = 0;
	let absent: uint64 = 0;
	for (let index = 0; index < world.pets.length; index++) {
		const pet = world.pets[index];
		pets = pets + pet.harvest + pet.burrow + pet.giftOwed;
		if (pet.alive) {
			const weight = pet.stats().rewardWeight();
			unsettled = unsettled + pendingReward(weight, world.global.rewardPerWorkPower, pet.rewardSnapshot);
		}
		if (pet.wild) {
			const real = world.absent[index];
			absent = absent + real.harvest + real.burrow + real.giftOwed;
		}
	}
	const global = world.global;
	const kept = global.recycledPending + global.treasury + global.itemReserve;
	const held = pets + unsettled + absent + kept;
	return { held: held, pets: pets, unsettled: unsettled, absent: absent };
}

function signed(value: uint64): int64 {
	return value as int64;
}

function main(): int32 {
	let world = World.staggered(WORLD_BLOCKS, 7);
	for (let day = 1; day <= LEDGER_EPOCHS; day++) {
		world = world.beginEpoch(day as uint64);
		for (let round = 0; round < ACTS_PER_EPOCH; round++) {
			world = world.inRound(round);
			for (let turn = 0; turn < world.pets.length; turn++) {
				world = world.act(world.actorAt(turn));
			}
		}
		world = world.endEpoch();
		if (day % REPORT_EVERY != 0 && day != 1) { continue; }
		const book = world.ledger();
		const global = world.global;
		const drift = signed(book.held) - signed(global.emitted);
		const unallocated = EMISSION_CAP - global.emitted;
		console.log(
			`day ${day} living ${world.living()} emitted ${global.emitted / HBRN_UNIT} ` +
			`unallocated ${unallocated / HBRN_UNIT} treasury ${global.treasury / HBRN_UNIT} ` +
			`items ${global.itemReserve / HBRN_UNIT} ` +
			`pets ${book.pets / HBRN_UNIT} unsettled ${book.unsettled / HBRN_UNIT} ` +
			`absent ${book.absent / HBRN_UNIT} pot ${global.recycledPending / HBRN_UNIT} ` +
			`drift ${drift} base units`,
		);
	}
	return 0;
}

process.exit(main());
