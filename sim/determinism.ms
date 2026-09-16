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
} from "../rules/index";

struct Digest {
	value: uint64;
}

function absorb(this digest: Digest, input: uint64): Digest {
	return { value: splitmix(digest.value ^ input) };
}

function digestFights(count: int32): uint64 {
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

function digestTree(): uint64 {
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

function digestEconomy(): uint64 {
	let digest: Digest = { value: 2 };
	for (let epoch: uint64 = 0; epoch < 400; epoch++) {
		const rewardPerWorkPower = settleGlobal(0, 0, epoch, 1234, epoch * 7);
		digest = digest.absorb(rewardPerWorkPower ^
			pendingReward(34, rewardPerWorkPower, rewardPerWorkPower / 3) ^
			(xpToReach((epoch % 25) as int32) as uint64) ^
			foodCost(((epoch % 3) as int32) as Food, (epoch % 50) as int32));
	}
	return digest.value;
}

function digestOdds(): uint64 {
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

function main(): int32 {
	console.log("fights   " + String(digestFights(20000)));
	console.log("tree     " + String(digestTree()));
	console.log("economy  " + String(digestEconomy()));
	console.log("odds     " + String(digestOdds()));
	return 0;
}
process.exit(main());
