import {
	BLOCK_SLOTS,
	STAKE_LEVELS,
	ATTACK_HOLD,
	ALLOCATE_HOLD,
	HBRN_UNIT,
	Pet,
	StakeLevel,
	EconomyAction,
	nodeKind,
	winChanceFromTable,
	GearSlot,
	TalentGrade,
	TalentKind,
	at,
} from "../rules/index";
import { ACTS_PER_EPOCH, WORLD_BLOCKS, EPISODE_EPOCHS, World, blockStart } from "./world";
import { personaKindOf, teachEconomy, teachNode, teachAttack } from "./teacher";

export const DIARY_SEED: uint64 = 7;

export struct Diary {
	pets: int32[];
	lines: string[];
}

function money(amount: uint64): string {
	return `${amount / HBRN_UNIT}`;
}

function change(before: uint64, after: uint64): string {
	const delta = ((after as int64) - (before as int64)) / (HBRN_UNIT as int64);
	return delta >= 0 ? `+${delta}` : `${delta}`;
}

function nameOf(index: int32): string {
	return `#${index % BLOCK_SLOTS} ${personaKindOf(index).toString()}`;
}

function note(this diary: Diary, index: int32, text: string): void {
	const lines = diary.lines;
	for (let row = 0; row < diary.pets.length; row++) {
		if (diary.pets[row] == index) { lines[row] = lines[row] + " | " + text; }
	}
}

function morning(this pet: Pet, yesterday: Pet, day: int32): string {
	if (!pet.alive && pet.bornEpoch > (day as uint64)) { return `day ${day} unclaimed`; }
	if (!pet.alive) { return `day ${day} dead`; }
	let line = `day ${day} hearts ${pet.hearts}/${pet.maxHearts} level ${pet.level}`;
	line = line + ` harvest ${money(pet.harvest)} burrow ${money(pet.burrow)}`;
	if (pet.bornEpoch == (day as uint64) && pet.lineageGeneration == 0) {
		return line + " | claimed";
	}
	if (pet.bornEpoch == (day as uint64)) {
		return line + ` | heir born, generation ${pet.lineageGeneration}`;
	}
	if (!yesterday.alive) { return line; }
	line = line + ` | earned ${change(yesterday.harvest, pet.harvest)}`;
	const stored = yesterday.pantry.stored();
	const ateOvernight = stored > 0 && pet.hearts >= yesterday.hearts;
	if (ateOvernight) { line = line + " | ate from the pantry overnight"; }
	const spoiled = stored - (ateOvernight ? 1 : 0);
	if (spoiled > 0) { line = line + ` | ${spoiled} portions spoiled`; }
	return line;
}

function ownerNotes(this world: World, index: int32, yesterday: Pet, visitsBefore: int32): string {
	const pet = world.pets[index];
	if (!pet.alive) { return ""; }
	let notes = "";
	if (world.ownerLedgers[index].visits > visitsBefore) {
		notes = notes + ` | owner visited, bonding ${pet.bonding as int32}`;
	}
	if (pet.giftOwed > yesterday.giftOwed) {
		notes = notes + ` | gifted ${money(pet.giftOwed - yesterday.giftOwed)} to its owner`;
	}
	if (pet.bornEpoch == yesterday.bornEpoch && pet.scars > yesterday.scars) {
		notes = notes + " | insurance brought it back";
	}
	return notes;
}

function gearNote(before: Pet, after: Pet): string {
	const cost = money(before.burrow - after.burrow);
	for (let ordinal = 0; ordinal <= (GearSlot.Feet as int32); ordinal++) {
		const slot = ordinal as GearSlot;
		const item = after.gear.at(slot);
		if (item != before.gear.at(slot)) {
			const grade = ((item.rarity as int32) - 1) as TalentGrade;
			const stat = (item.stat as int32) as TalentKind;
			const gear = `${grade.toString()} ${stat.toString()} gear`;
			return `minted ${gear} for its ${slot.toString()}, net cost ${cost}`;
		}
	}
	return `minted and sold back a weaker roll, net cost ${cost}`;
}

function economyStep(this world: World, index: int32, diary: Diary): World {
	const before = world.pets[index];
	const action = world.teachEconomy(index, world.masksFor(index));
	const after = world.applyEconomy(index, action);
	const pet = after.pets[index];
	match (action) {
		EconomyAction.Rest => {},
		EconomyAction.Bank => { diary.note(index, `bank ${money(before.harvest)}`); },
		EconomyAction.Mint => { diary.note(index, gearNote(before, pet)); },
		_ => {
			const cost = money(before.burrow - pet.burrow);
			diary.note(index, `${action.toString()} hearts ${before.hearts}->${pet.hearts} cost ${cost}`);
		},
	}
	return after;
}

function nodeStep(this world: World, index: int32, diary: Diary): World {
	const node = world.teachNode(index, world.masksFor(index));
	if (node != ALLOCATE_HOLD) { diary.note(index, `node ${node} ${nodeKind(node).toString()}`); }
	return world.applyNode(index, node);
}

function attackStep(this world: World, index: int32, diary: Diary): World {
	const choice = world.teachAttack(index, world.masksFor(index));
	if (choice == ATTACK_HOLD) { return world; }
	const slot = choice / STAKE_LEVELS;
	const target = blockStart(index) + slot;
	const level = (choice % STAKE_LEVELS) as StakeLevel;
	const attacker = world.pets[index];
	const defender = world.defenderAt(target);
	const robber = world.robberOf(index);
	const revenge = robber.ok && (robber.value as int32) == slot ? " revenge" : "";
	const facing = defender.combatantFacing(attacker);
	const odds = attacker.combatantFacing(defender).winChanceFromTable(facing) / 100;
	const stake = attacker.stakeFor(defender, level, world.epoch);
	const staked = stake.ok ? money(stake.value) : "?";
	const won = world.stats.wins;
	const after = world.applyAttack(index, choice);
	const attackerAfter = after.pets[index];
	const defenderAfter = after.defenderAt(target);
	const wild = world.isWild(target);
	const targetName = wild ? `a wild ${defender.startRegion().toString()}` : nameOf(target);
	const terms = `${level.toString()} stake ${staked} odds ${odds}%${revenge}`;
	const opening = `attack ${targetName} ${terms}`;
	if (after.stats.wins > won) {
		const loot = money(defender.harvest - defenderAfter.harvest);
		diary.note(index, `${opening} -> won, took ${loot}`);
		if (wild) { return after; }
		const bitten = defenderAfter.hearts < defender.hearts ? ", bitten" : "";
		diary.note(target, `robbed by ${nameOf(index)} -${loot}${bitten}`);
		return after;
	}
	const hearts = `hearts ${attacker.hearts}->${attackerAfter.hearts}`;
	diary.note(index, `${opening} -> lost, burrow ${change(attacker.burrow, attackerAfter.burrow)} ${hearts}`);
	if (wild) { return after; }
	diary.note(target, `held off ${nameOf(index)}, burrow ${change(defender.burrow, defenderAfter.burrow)}`);
	return after;
}

function step(this world: World, index: int32, diary: Diary): World {
	if (!world.pets[index].alive) { return world; }
	return world.economyStep(index, diary).nodeStep(index, diary).attackStep(index, diary);
}

function main(): int32 {
	let world = World.staggered(WORLD_BLOCKS, DIARY_SEED);
	const diary: Diary = { pets: [1, 4, 7], lines: ["", "", ""] };
	const pages: string[] = [];
	for (let day = 1; day <= EPISODE_EPOCHS; day++) {
		const yesterday: Pet[] = [];
		const visitsBefore: int32[] = [];
		for (const index of diary.pets) {
			yesterday.push(world.pets[index]);
			visitsBefore.push(world.ownerLedgers[index].visits);
		}
		world = world.beginEpoch(day as uint64);
		const lines = diary.lines;
		for (let row = 0; row < diary.pets.length; row++) {
			const index = diary.pets[row];
			lines[row] = world.pets[index].morning(yesterday[row], day) +
				world.ownerNotes(index, yesterday[row], visitsBefore[row]);
		}
		for (let round = 0; round < ACTS_PER_EPOCH; round++) {
			world = world.inRound(round);
			for (let turn = 0; turn < world.pets.length; turn++) {
				world = world.step(world.actorAt(turn), diary);
			}
		}
		world = world.endEpoch();
		for (const line of diary.lines) { pages.push(line); }
	}
	for (let row = 0; row < diary.pets.length; row++) {
		const index = diary.pets[row];
		const pet = world.pets[index];
		const owner = world.owners[index].toString();
		const origin = `start ${pet.startRegion().toString()}, owner ${owner}`;
		console.log(`== ${nameOf(index)}, ${origin}, seed ${DIARY_SEED}`);
		for (let day = 0; day < EPISODE_EPOCHS; day++) {
			console.log(pages[day * diary.pets.length + row]);
		}
		console.log(`end: level ${pet.level} wealth ${money(pet.harvest + pet.burrow)} generation ${pet.lineageGeneration}`);
		console.log("");
	}
	return 0;
}

process.exit(main());
