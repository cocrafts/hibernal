import {
	TREE_NODES,
	Combatant,
	Stats,
	Tree,
	Food,
	splitmix,
	fight,
	settleGlobal,
	pendingReward,
	xpToReach,
	foodCost,
	oddsAgainst,
	modsFromMask,
	HEIRLOOM_SLOTS,
	Gear,
	GearSlot,
	Item,
	Talent,
	rolledGrade,
	rolledStat,
	rolledSkill,
	minted,
	wornBy,
	with,
	heirlooms,
	totalBonusBps,
	rolled,
	lineageNudgeBps,
} from "../rules/index";
import { ACTS_PER_EPOCH, World } from "./world";
import { playEpisode } from "./teacher";
import { Head, observationSize, actionCount, observeInto, legalInto, zeros } from "./env/observe";

struct Digest {
	value: uint64;
}

function absorb(this digest: Digest, input: uint64): Digest {
	return { value: splitmix(digest.value ^ input) };
}

export function digestFights(count: int32): uint64 {
	let digest: Digest = { value: 0x9e3779b97f4a7c15 };
	for (let index = 0; index < count; index++) {
		const seed = splitmix(index as uint64);
		const attacker: Combatant = {
			might: (1 + ((seed >> 8) % 40) as int32) * 10,
			grit: (((seed >> 16) % 40) as int32) * 10,
			speed: 30 + ((seed >> 12) % 60) as int32,
			armor: ((seed >> 20) % 50) as int32,
			accuracy: ((seed >> 28) % 50) as int32,
			lifesteal: ((seed >> 36) % 40) as int32,
			bleed: ((seed >> 44) % 40) as int32,
			hearts: 1 + ((seed >> 24) % 5) as int32,
			mods: modsFromMask(((seed >> 32) % 64) as int32),
		};
		const defender: Combatant = {
			might: (1 + ((seed >> 40) % 40) as int32) * 10,
			grit: (((seed >> 48) % 40) as int32) * 10,
			speed: 30 + ((seed >> 52) % 60) as int32,
			armor: ((seed >> 2) % 50) as int32,
			accuracy: ((seed >> 10) % 50) as int32,
			lifesteal: ((seed >> 18) % 40) as int32,
			bleed: ((seed >> 26) % 40) as int32,
			hearts: 1 + ((seed >> 56) % 5) as int32,
			mods: modsFromMask(((seed >> 4) % 64) as int32),
		};
		const result = attacker.fight(defender, seed);
		digest = digest.absorb(((result.outcome as int32) as uint64) ^
			((result.rounds as uint64) << 8) ^
			((result.attackerHp as uint64) << 16) ^
			((result.defenderHp as uint64) << 32));
	}
	return digest.value;
}

export function digestTree(): uint64 {
	let digest: Digest = { value: 1 };
	let tree = Tree.empty();
	for (let id = 0; id < TREE_NODES; id++) {
		tree = tree.withNode(id);
		const derived = Stats.fromTree(tree);
		digest = digest.absorb((derived.forage as uint64) ^
			((derived.might as uint64) << 8) ^
			((derived.grit as uint64) << 16) ^
			((derived.maxHearts as uint64) << 24) ^
			(((derived.mods as uint32) as uint64) << 32));
	}
	return digest.value;
}

export function digestEconomy(): uint64 {
	let digest: Digest = { value: 2 };
	for (let epoch: uint64 = 0; epoch < 400; epoch++) {
		const settled = settleGlobal(0, 0, epoch, 1000, 1234, epoch * 7, 0, epoch * 11);
		const rewardPerWorkPower = settled.rewardPerWorkPower;
		digest = digest.absorb(rewardPerWorkPower ^
			settled.emitted ^
			settled.treasury ^
			pendingReward(34, rewardPerWorkPower, rewardPerWorkPower / 3) ^
			(xpToReach((epoch % 25) as int32) as uint64) ^
			foodCost(((epoch % 3) as int32) as Food, (epoch % 50) as int32));
	}
	return digest.value;
}

export function digestOdds(): uint64 {
	const attacker: Combatant = {
		...Combatant.plain(90, 60, 5),
		speed: 60,
		armor: 20,
		mods: modsFromMask(2),
	};
	const defender: Combatant = {
		...Combatant.plain(70, 90, 3),
		accuracy: 30,
		bleed: 20,
		mods: modsFromMask(4),
	};
	const odds = attacker.oddsAgainst(defender, 99, 2000);
	const packed = (odds.winChanceBps as uint64) ^ ((odds.averageRoundsTimes100 as uint64) << 20);
	const digest: Digest = { value: 0 };
	return digest.absorb(packed).value;
}

export function digestWorld(): uint64 {
	const world = playEpisode(2, 30, 11);
	let digest: Digest = { value: 3 };
	for (let index = 0; index < world.pets.length; index++) {
		const pet = world.pets[index];
		digest = digest.absorb(pet.harvest ^ (pet.burrow << 1) ^ ((pet.xp as uint64) << 40));
		digest = digest.absorb((pet.hearts as uint64) ^ ((pet.level as uint64) << 8) ^ pet.tree.bits);
	}
	return digest.absorb((world.stats.fights as uint64) ^ ((world.stats.wins as uint64) << 16) ^ world.global.treasury ^ world.global.itemReserve ^ world.global.emitted).value;
}

export function digestObserve(): uint64 {
	const world = playEpisode(2, 12, 13).beginEpoch(13).inRound(ACTS_PER_EPOCH - 1);
	let digest: Digest = { value: 4 };
	for (let ordinal = 0; ordinal <= (Head.Attack as int32); ordinal++) {
		const head = ordinal as Head;
		const features = zeros(observationSize(head));
		const legal = zeros(actionCount(head));
		for (let index = 0; index < world.pets.length; index++) {
			world.observeInto(index, head, features, 0);
			world.legalInto(index, head, legal, 0);
			for (const feature of features) { digest = digest.absorb((feature + 128) as uint64); }
			for (const allowed of legal) { digest = digest.absorb(allowed as uint64); }
		}
	}
	return digest.value;
}

export function digestLineage(): uint64 {
	let digest: Digest = { value: 6 };
	for (let seed: uint64 = 0; seed < 400; seed++) {
		let gear = Gear.bare();
		for (let ordinal = 0; ordinal <= (GearSlot.Feet as int32); ordinal++) {
			const draw = splitmix(seed * 4 + (ordinal as uint64));
			const grade = rolledGrade(draw);
			const level = ((seed % 20) as int32) + 1;
			const item = Item.minted(grade, rolledStat(draw), rolledSkill(draw, grade), level);
			gear = gear.with(ordinal as GearSlot, item.wornBy((draw % 90) as int32));
		}
		const [kept, proceeds] = gear.heirlooms(HEIRLOOM_SLOTS);
		const talent = Talent.rolled(seed, lineageNudgeBps((seed % 7) as int32));
		digest = digest.absorb(proceeds ^
			((kept.totalBonusBps() as uint64) << 32) ^
			((talent.multiplierBps as uint64) << 48) ^
			((talent.kind as int32) as uint64));
	}
	return digest.value;
}

export const ENGINE_FIGHTS: int32 = 20000;

export function engineVersion(): uint64 {
	const digest: Digest = { value: 5 };
	return digest
		.absorb(digestFights(ENGINE_FIGHTS))
		.absorb(digestTree())
		.absorb(digestEconomy())
		.absorb(digestOdds())
		.absorb(digestWorld())
		.absorb(digestObserve())
		.absorb(digestLineage())
		.value;
}
