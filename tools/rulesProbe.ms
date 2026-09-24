import {
	Combatant,
	Stats,
	Tree,
	Outcome,
	Region,
	Mod,
	fight,
	emissionFor,
	EMISSION_START,
	allocate,
	KEYSTONE_GLASS_CANNON,
} from "../rules/index";

function fightHolds(): boolean {
	const result = Combatant.plain(0, 50, 5).fight(Combatant.plain(80, 50, 5), 42);
	return result.outcome == Outcome.DefenderWins && result.rounds >= 1;
}

function treeHolds(): boolean {
	const path = Tree.empty()
		.withNode(1)
		.withNode(22)
		.withNode(23)
		.withNode(32)
		.withNode(33)
		.withNode(34)
		.withNode(35);
	const grown = path.allocate(KEYSTONE_GLASS_CANNON, Region.Fighter);
	if (!grown.ok) { return false; }
	const derived = Stats.fromTree(grown.value);
	return derived.might == 96 &&
		derived.maxHearts == 10 &&
		derived.lootBps == 5500 &&
		derived.mods.has(Mod.GlassCannon);
}

function emissionHolds(): boolean {
	return emissionFor(90) == EMISSION_START * 3 / 4;
}

function main(): int32 {
	const allHold = fightHolds() && treeHolds() && emissionHolds();
	console.log(allHold ? "rules ok" : "rules BAD");
	return 0;
}
main();
