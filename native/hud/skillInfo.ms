// What a tree node does, in the words the tooltip shows: its name, its effect and its cost, read
// from rules/ (the node's kind, family, bonus and the mod it grants through Stats.fromTree).

import { Region, Stats, Mod, START_BONUS } from "../../rules/stats";
import {
	NodeKind,
	NodeRole,
	Family,
	KEYSTONE_COST,
	KEYSTONE_GLASS_CANNON,
	KEYSTONE_TYCOON,
	KEYSTONE_CANNIBAL,
	KEYSTONE_BERSERKER,
	KEYSTONE_PACIFIST,
	KEYSTONE_BULWARK,
	TYCOON_FORAGE_BPS,
	TYCOON_HEARTS_BPS,
	BULWARK_HEARTS_BPS,
	BULWARK_MIGHT_BPS,
	roleOf,
	nodeKind,
	nodeFamily,
	nodeBonusBps,
	fromTree,
} from "../../rules/tree";
import { SCAVENGER_CRIT, THICK_HIDE_DODGE, THICK_HIDE_FIGHTS, PACIFIST_LOOT_CUT_BPS, CANNIBAL_WALLET_BPS } from "../../rules/fight";
import { BERSERKER_APPETITE_BPS } from "../../rules/life";

export struct SkillInfo {
	name: string;
	lines: string[];
}

enum ModError {
	None,
}

function info(name: string, lines: string[]): SkillInfo {
	return { name: name, lines: lines };
}

function regionName(region: int32): string {
	return match (region as Region) {
		Region.Worker => "WORKER",
		Region.Fighter => "FIGHTER",
		Region.Survivor => "SURVIVOR",
	};
}

function startStat(region: int32): string {
	return match (region as Region) {
		Region.Worker => "FORAGE",
		Region.Fighter => "MIGHT",
		Region.Survivor => "GRIT",
	};
}

function familyName(family: Family): string {
	return match (family) {
		Family.Forage => "FORAGE",
		Family.Food => "HEARTS PER MEAL",
		Family.Experience => "XP",
		Family.Might => "MIGHT",
		Family.Loot => "LOOT",
		Family.Attacks => "MIGHT",
		Family.Grit => "GRIT",
		Family.Hearts => "MAX HEARTS",
		Family.BiteGuard => "BITE GUARD",
	};
}

function percent(bps: int32): string {
	return (bps / 100).toString() + "%";
}

function times(bps: int32): string {
	const tenths: int32 = bps / 1000;
	return "X" + (tenths / 10).toString() + (tenths % 10 == 0 ? "" : "." + (tenths % 10).toString());
}

function modName(mod: Mod): string {
	return match (mod) {
		Mod.Overtime => "OVERTIME",
		Mod.Scavenger => "SCAVENGER",
		Mod.ThickHide => "THICK HIDE",
		Mod.Pacifist => "PACIFIST",
		Mod.GlassCannon => "GLASS CANNON",
		Mod.Cannibal => "CANNIBAL",
		Mod.Relentless => "RELENTLESS",
		Mod.Berserker => "BERSERKER",
	};
}

function modLines(mod: Mod): string[] {
	return match (mod) {
		Mod.Overtime => [],
		Mod.Scavenger => ["CRIT +" + SCAVENGER_CRIT.toString() + " VS FEWER HEARTS"],
		Mod.ThickHide => ["DODGE +" + THICK_HIDE_DODGE.toString(), "HALF LOOT TAKEN IN THE FIRST", THICK_HIDE_FIGHTS.toString()
			+ " FIGHTS A DAY"],
		Mod.Pacifist => ["CANNOT ATTACK", "LOOT TAKEN FROM IT -" + percent(PACIFIST_LOOT_CUT_BPS)],
		Mod.GlassCannon => ["DAMAGE X2", "HALF FIGHT HP"],
		Mod.Cannibal => ["A KILLING BLOW TAKES " + percent(CANNIBAL_WALLET_BPS), "OF THE VICTIM'S WALLET"],
		Mod.Relentless => ["+1 ATTACK A DAY"],
		Mod.Berserker => ["MIGHT GROWS AS HEARTS FALL", "X2 AT 0 HEARTS", "APPETITE +" + percent(BERSERKER_APPETITE_BPS)],
	};
}

// The mod a node grants on its own, if any.
function grantedMod(id: int32): Result<Mod, ModError> {
	const mods = Stats.fromTree({ bits: (1 as uint64) << (id as uint64) }).mods;
	for (let ordinal: int32 = 0; ordinal <= (Mod.Berserker as int32); ordinal += 1) {
		if (mods.has(ordinal as Mod)) { return Result.ok(ordinal as Mod); }
	}
	return Result.err(ModError.None);
}

function keystoneInfo(id: int32): SkillInfo {
	const cost: string = "COSTS " + KEYSTONE_COST.toString() + " POINTS";
	if (id == KEYSTONE_TYCOON) {
		return info("TYCOON", ["FORAGE " + times(TYCOON_FORAGE_BPS), "MAX HEARTS " + times(TYCOON_HEARTS_BPS), cost]);
	}
	if (id == KEYSTONE_BULWARK) {
		return info("BULWARK", ["MAX HEARTS " + times(BULWARK_HEARTS_BPS), "MIGHT " + times(BULWARK_MIGHT_BPS),
			"MEALS RESTORE TWICE", cost]);
	}
	const mod: Result<Mod, ModError> = grantedMod(id);
	if (!mod.ok) {
		console.log("skillInfo: keystone " + id.toString() + " grants no mod");
		unreachable;
	}
	const lines: string[] = modLines(mod.value);
	lines.push(cost);
	return info(modName(mod.value), lines);
}

export function skillInfo(id: int32): SkillInfo {
	return match (roleOf(id)) {
		NodeRole.Start => info(regionName(id) + " START", ["+" + START_BONUS.toString() + " " + startStat(id), "A PET BEGINS HERE"]),
		NodeRole.Gate => info("GATE", ["+" + percent(nodeBonusBps(id)) + " " + familyName(nodeFamily(id)), "JOINS THE THREE PATHS"]),
		NodeRole.Keystone => keystoneInfo(id),
		_ => smallOrNotable(id),
	};
}

function smallOrNotable(id: int32): SkillInfo {
	const bonus: string = "+" + percent(nodeBonusBps(id)) + " " + familyName(nodeFamily(id));
	if (nodeKind(id) != NodeKind.Notable) {
		return info(familyName(nodeFamily(id)), [bonus]);
	}
	const mod: Result<Mod, ModError> = grantedMod(id);
	if (!mod.ok) {
		return info("NOTABLE", [bonus]);
	}
	const lines: string[] = [bonus];
	for (const line of modLines(mod.value)) { lines.push(line); }
	return info(modName(mod.value), lines);
}
