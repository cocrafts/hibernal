import {
	Mod,
	NodeKind,
	NodeRole,
	Stats,
	TREE_NODES,
	Talent,
	Tree,
	built,
	empty,
	neighbors,
	nodeBonusBps,
	nodeCost,
	nodeFamily,
	nodeKind,
	roleOf,
	unrevealed,
	withNode,
} from "../../rules/index";

function modNames(id: int32): string {
	const mods = Stats.built(Tree.empty().withNode(id), 1, Talent.unrevealed()).mods;
	let names = "";
	for (let ordinal = 0; ordinal <= (Mod.Berserker as int32); ordinal++) {
		const mod = ordinal as Mod;
		if (!mods.has(mod)) { continue; }
		names = names.length == 0 ? mod.toString() : `${names},${mod.toString()}`;
	}
	return names;
}

function neighborList(id: int32): string {
	const bits = neighbors(id);
	let list = "";
	for (let other = 0; other < TREE_NODES; other++) {
		if ((bits & ((1 as uint64) << (other as uint64))) == 0) { continue; }
		list = list.length == 0 ? `${other}` : `${list},${other}`;
	}
	return list;
}

function main(): int32 {
	for (let id = 0; id < TREE_NODES; id++) {
		const role = roleOf(id).toString();
		const kind = nodeKind(id).toString();
		const family = nodeFamily(id).toString();
		console.log(`${id}\t${role}\t${kind}\t${family}\t${nodeBonusBps(id)}\t${nodeCost(id)}\t${modNames(id)}\t${neighborList(id)}`);
	}
	return 0;
}

process.exit(main());
