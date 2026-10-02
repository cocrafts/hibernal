import { Color, rgba } from "@metascript/void/src/void2d/types";
import { Ui, box, pressable, held } from "../ui/ui";
import { Kit, subId, frame, iconTinted, say, INK, EMBER, EMBER_HOT, ALERT_RED, DISABLED_INK, WHITE } from "./kit";
import { FrameLook } from "./frame";

const HALF: float32 = 0.5;
const DOCK_X: float32 = 16.0;
const DOCK_Y: float32 = 728.0;
const DOCK_WIDTH: float32 = 328.0;
const DOCK_HEIGHT: float32 = 56.0;
const RESTING_ICON: Color = rgba(0.85, 0.85, 0.85, 0.9);
const PAGE_DOT: Color = rgba(0.30, 0.28, 0.27, 1.0);

export enum DockTab {
	Home,
	Pet,
	Block,
	Shop,
	Digest,
}

export enum DockError {
	NotTapped,
}

export const DOCK_TABS: DockTab[] = [DockTab.Home, DockTab.Pet, DockTab.Block, DockTab.Shop, DockTab.Digest];

function dockIcon(tab: DockTab): string {
	return match (tab) {
		DockTab.Home => "home",
		DockTab.Pet => "pet",
		DockTab.Block => "block",
		DockTab.Shop => "shop",
		DockTab.Digest => "digest",
	};
}

function dockName(tab: DockTab): string {
	return match (tab) {
		DockTab.Home => "HOME",
		DockTab.Pet => "PET",
		DockTab.Block => "BLOCK",
		DockTab.Shop => "SHOP",
		DockTab.Digest => "DIGEST",
	};
}

// The floating dock: the active tab is ember with an underline, Digest carries an unread dot.
export function dock(ui: Ui, kit: Kit, id: int32, active: DockTab, digestUnread: boolean, seed: int32): Result<DockTab, DockError> {
	frame(kit, id, DOCK_X, DOCK_Y, DOCK_WIDTH, DOCK_HEIGHT, seed, FrameLook.Normal);
	const slot: float32 = (DOCK_WIDTH - 16.0) / (DOCK_TABS.length as float32);
	let tapped: Result<DockTab, DockError> = Result.err(DockError.NotTapped);
	for (let position: int32 = 0; position < DOCK_TABS.length; position += 1) {
		const tab: DockTab = DOCK_TABS[position];
		const slotX: float32 = DOCK_X + 8.0 + slot * (position as float32);
		const centreX: float32 = slotX + slot * HALF;
		const tabId: int32 = subId(id, position);
		if (pressable(ui, tabId, slotX, DOCK_Y, slot, DOCK_HEIGHT)) {
			tapped = Result.ok(tab);
		}
		const down: boolean = held(ui, tabId, slotX, DOCK_Y, slot, DOCK_HEIGHT);
		const on: boolean = tab == active;
		iconTinted(kit, tabId, dockIcon(tab), centreX - 11.0, DOCK_Y + 9.0 + (down ? 1.0 : 0.0), 22.0,
			on || down ? WHITE : RESTING_ICON);
		say(ui, kit, tabId, dockName(tab), slotX, DOCK_Y + 35.0, slot, 8.0, on ? EMBER_HOT : INK, 0.5);
		if (on) {
			box(ui, centreX - 18.0, DOCK_Y + 46.0, 36.0, 2.0, 0.0, EMBER);
			box(ui, centreX - 18.0, DOCK_Y + 46.0, 36.0, 1.0, 0.0, EMBER_HOT);
		}
		if (tab == DockTab.Digest && digestUnread) {
			box(ui, centreX + 9.0, DOCK_Y + 7.0, 6.0, 6.0, 0.0, ALERT_RED);
			box(ui, centreX + 10.0, DOCK_Y + 8.0, 2.0, 2.0, 0.0, rgba(1.0, 0.6, 0.5, 1.0));
		}
	}
	return tapped;
}

// "<  SLOT 4 - 1 OF 9 (THREAT)  >" over a dot per page. Returns the page, new when stepped.
export function pager(ui: Ui, kit: Kit, id: int32, x: float32, y: float32, width: float32, label: string, page: int32,
	count: int32): int32 {
	const hasPrevious: boolean = page > 0;
	const hasNext: boolean = page < count - 1;
	let next: int32 = page;
	if (pressable(ui, subId(id, 0), x, y - 8.0, 48.0, 40.0) && hasPrevious) {
		next = page - 1;
	}
	if (pressable(ui, subId(id, 1), x + width - 48.0, y - 8.0, 48.0, 40.0) && hasNext) {
		next = page + 1;
	}
	say(ui, kit, subId(id, 2), "<", x + 12.0, y + 4.0, 16.0, 16.0, hasPrevious ? EMBER_HOT : DISABLED_INK, 0.0);
	say(ui, kit, subId(id, 3), ">", x + width - 24.0, y + 4.0, 16.0, 16.0, hasNext ? EMBER_HOT : DISABLED_INK, 0.0);
	say(ui, kit, subId(id, 4), label, x + 40.0, y + 8.0, width - 80.0, 8.0, INK, 0.5);
	const span: float32 = (count as float32) * 10.0 - 4.0;
	for (let dot: int32 = 0; dot < count; dot += 1) {
		const dotX: float32 = x + (width - span) * HALF + (dot as float32) * 10.0;
		if (dot == page) {
			box(ui, dotX - 1.0, y + 23.0, 8.0, 8.0, 0.0, EMBER_HOT);
		} else {
			box(ui, dotX, y + 24.0, 6.0, 6.0, 0.0, PAGE_DOT);
		}
	}
	return next;
}
