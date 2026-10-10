import { GearSlot, Item, isEmpty } from "../../rules/items";
import { TalentKind } from "../../rules/talent";

const STATS: int32 = 3;
// gearIcon<Slot><Stat>.png from art/hud/cutGearIcons.py, slot by slot in GearSlot order, stats in TalentKind order.
const GEAR_ICON_NAMES: string[] = [
	"gearIconHeadForage", "gearIconHeadMight", "gearIconHeadGrit",
	"gearIconBodyForage", "gearIconBodyMight", "gearIconBodyGrit",
	"gearIconHandsForage", "gearIconHandsMight", "gearIconHandsGrit",
	"gearIconFeetForage", "gearIconFeetMight", "gearIconFeetGrit",
];

export enum NoGearIcon {
	Empty,
}

// The same slot and stat always draw the same icon; rarity, skill, wear and level are drawn elsewhere.
export function gearIcon(slot: GearSlot, item: Item): Result<string, NoGearIcon> {
	if (item.isEmpty()) { return Result.err(NoGearIcon.Empty); }
	const stat: int32 = (item.stat as int32) - (TalentKind.Forage as int32);
	if (stat < 0 || stat >= STATS) {
		console.log("gearIcon: worn item with stat " + item.stat.toString() + "; the read should have refused it");
		unreachable;
	}
	return Result.ok(GEAR_ICON_NAMES[(slot as int32) * STATS + stat]);
}

test "each slot and stat has its own icon, and an empty slot has none" {
	const slots: GearSlot[] = [GearSlot.Head, GearSlot.Body, GearSlot.Hands, GearSlot.Feet];
	const stats: TalentKind[] = [TalentKind.Forage, TalentKind.Might, TalentKind.Grit];
	const seen: string[] = [];
	for (const slot of slots) {
		for (const stat of stats) {
			const item: Item = { rarity: 1, stat: stat as uint8, wear: 0, skill: 0, level: 1 };
			const icon = gearIcon(slot, item);
			assert icon.ok;
			for (const other of seen) { assert other != icon.value; }
			seen.push(icon.value);
		}
	}
	assert seen.length == GEAR_ICON_NAMES.length;
	assert !gearIcon(GearSlot.Head, { rarity: 0, stat: 0, wear: 0, skill: 0, level: 0 }).ok;
}
