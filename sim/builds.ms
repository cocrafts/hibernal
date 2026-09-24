import {
	HBRN_UNIT,
	TREE_NODES,
	KEYSTONE_GLASS_CANNON,
	Region,
	TalentKind,
	keystoneTouches,
	mixSeeds,
	splitmix,
	agedOut,
} from "../rules/index";
import {
	ACTS_PER_EPOCH,
	EPISODE_EPOCHS,
	NO_KEYSTONE,
	WORLD_BLOCKS,
	World,
	percentile,
} from "./world";
import { act } from "./teacher";

export const BUILD_SEEDS: int32 = 4;
export const RARE_PICK_PERCENT: int32 = 5;

struct Life {
	start: Region;
	target: int32;
	keystone: int32;
	level: int32;
	age: int32;
	aged: boolean;
	wealth: uint64;
	talentKind: TalentKind;
	talentBps: int32;
	tree: uint64;
}

function targetsFor(start: Region): int32[] {
	const targets: int32[] = [NO_KEYSTONE];
	for (let id = KEYSTONE_GLASS_CANNON; id < TREE_NODES; id++) {
		if (keystoneTouches(id, start)) { targets.push(id); }
	}
	return targets;
}

function withRandomBuilds(this world: World): World {
	const targets = world.buildTargets;
	for (let index = 0; index < world.pets.length; index++) {
		const options = targetsFor(world.pets[index].startRegion());
		const draw = splitmix(mixSeeds(world.seed, (index as uint64) + 7919));
		targets[index] = options[(draw % (options.length as uint64)) as int32];
	}
	return world;
}

function ownedKeystone(tree: uint64): int32 {
	for (let id = KEYSTONE_GLASS_CANNON; id < TREE_NODES; id++) {
		if (((tree >> (id as uint64)) & 1) == 1) { return id; }
	}
	return NO_KEYSTONE;
}

function recordDeaths(this world: World, lives: Life[], recordedBirth: uint64[]): void {
	for (let index = 0; index < world.pets.length; index++) {
		const pet = world.pets[index];
		const unclaimed = world.claimEpochs[index] != 0;
		if (pet.alive || unclaimed || recordedBirth[index] == pet.bornEpoch + 1) {
			continue;
		}
		recordedBirth[index] = pet.bornEpoch + 1;
		lives.push({
			start: pet.startRegion(),
			target: world.buildTargets[index],
			keystone: ownedKeystone(pet.tree.bits),
			level: pet.level as int32,
			age: (world.epoch - pet.bornEpoch) as int32,
			aged: pet.agedOut(),
			wealth: pet.harvest + pet.burrow,
			talentKind: (pet.talentKind as int32) as TalentKind,
			talentBps: pet.talentBps as int32,
			tree: pet.tree.bits,
		});
	}
}

function playLives(seed: uint64, lives: Life[]): void {
	let world = World.staggered(WORLD_BLOCKS, seed).withRandomBuilds();
	const recordedBirth: uint64[] = [];
	for (let index = 0; index < world.pets.length; index++) { recordedBirth.push(0); }
	for (let day = 1; day <= EPISODE_EPOCHS; day++) {
		world = world.beginEpoch(day as uint64);
		world.recordDeaths(lives, recordedBirth);
		for (let round = 0; round < ACTS_PER_EPOCH; round++) {
			world = world.inRound(round);
			for (let turn = 0; turn < world.pets.length; turn++) {
				world = world.act(world.actorAt(turn));
			}
		}
		world.recordDeaths(lives, recordedBirth);
		world = world.endEpoch();
	}
}

function sortedWealth(lives: Life[]): uint64[] {
	const sorted: uint64[] = [];
	for (const life of lives) {
		let position = sorted.length;
		sorted.push(life.wealth);
		while (position > 0 && sorted[position - 1] > life.wealth) {
			sorted[position] = sorted[position - 1];
			position -= 1;
		}
		sorted[position] = life.wealth;
	}
	return sorted;
}

function ratio(value: uint64, median: uint64): uint64 {
	return value * 100 / Math.max(median, 1 as uint64);
}

function targetName(target: int32): string {
	return target == NO_KEYSTONE ? "depth" : `keystone ${target}`;
}

function summarize(label: string, group: Life[], median: uint64): string {
	if (group.length == 0) { return `${label} | 0 lives`; }
	const sorted = sortedWealth(group);
	let early = 0;
	let levels = 0;
	for (const life of group) {
		if (!life.aged) { early += 1; }
		levels += life.level;
	}
	return `${label} | ${group.length} lives | early deaths ${early * 100 / group.length}%` +
		` | level ${levels / group.length}` +
		` | wealth p50 x${ratio(percentile(sorted, 50), median)}` +
		` p90 x${ratio(percentile(sorted, 90), median)} top x${ratio(percentile(sorted, 100), median)} (x100)`;
}

function gradeName(bps: int32): string {
	if (bps <= 11000) { return "common"; }
	if (bps <= 12000) { return "rare"; }
	if (bps <= 14000) { return "epic"; }
	if (bps <= 16000) { return "legendary"; }
	return "mythic";
}

function mainStat(start: Region): TalentKind {
	return match (start) {
		Region.Worker => TalentKind.Forage,
		Region.Fighter => TalentKind.Might,
		Region.Survivor => TalentKind.Grit,
	};
}

function main(): int32 {
	const lives: Life[] = [];
	for (let seed = 1; seed <= BUILD_SEEDS; seed++) { playLives(seed as uint64, lives); }
	const median = percentile(sortedWealth(lives), 50);
	console.log(`${lives.length} lives over ${BUILD_SEEDS} seeds · median wealth ${median / HBRN_UNIT} HBRN`);
	console.log(summarize("all", lives, median));
	for (let start = 0; start < 3; start++) {
		for (const target of targetsFor(start as Region)) {
			const group: Life[] = [];
			for (const life of lives) {
				if (life.start == (start as Region) && life.target == target) { group.push(life); }
			}
			console.log(summarize(`${(start as Region).toString()} ${targetName(target)}`, group, median));
		}
	}
	for (let id = KEYSTONE_GLASS_CANNON; id < TREE_NODES; id++) {
		const group: Life[] = [];
		for (const life of lives) {
			if (life.keystone == id) { group.push(life); }
		}
		console.log(summarize(`owns keystone ${id}`, group, median));
	}
	const grades = ["common", "rare", "epic", "legendary", "mythic"];
	for (const grade of grades) {
		const matched: Life[] = [];
		const other: Life[] = [];
		for (const life of lives) {
			if (life.talentKind == TalentKind.None || gradeName(life.talentBps) != grade) { continue; }
			if (life.talentKind == mainStat(life.start)) { matched.push(life); } else { other.push(life); }
		}
		console.log(summarize(`talent ${grade} on its start stat`, matched, median));
		console.log(summarize(`talent ${grade} off its start stat`, other, median));
	}
	let rare = "";
	for (let id = 3; id < TREE_NODES; id++) {
		let owners = 0;
		for (const life of lives) {
			if (((life.tree >> (id as uint64)) & 1) == 1) { owners += 1; }
		}
		const percent = owners * 100 / lives.length;
		if (percent < RARE_PICK_PERCENT) { rare = rare + ` ${id}(${percent}%)`; }
	}
	console.log(`nodes held by under ${RARE_PICK_PERCENT}% of lives:${rare}`);
	return 0;
}

process.exit(main());
