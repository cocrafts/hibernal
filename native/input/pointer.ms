// Pointer input: the MetaScript side of hudPointer.c.
//
// Hosts push raw touch and mouse events into a C queue; once per frame, takePointerEvents()
// hands the whole batch over, in the order they happened. Coordinates are surface pixels,
// origin top-left. What was touched is not known here: the UI hit-tests (native/ui/ui.ms).

@include("./hudPointer.h");
@compile("./hudPointer.c");

extern function hudPointerTake(): int32;
extern function hudPointerPhase(i: int32): int32;
extern function hudPointerId(i: int32): int32;
extern function hudPointerX(i: int32): float32;
extern function hudPointerY(i: int32): float32;

export enum PointerPhase { Down, Move, Up, Cancel }

export struct PointerEvent {
	phase: PointerPhase;
	id: int32;
	x: float32;
	y: float32;
}

function phaseOf(raw: int32): PointerPhase {
	return match (raw) {
		0 => PointerPhase.Down,
		1 => PointerPhase.Move,
		2 => PointerPhase.Up,
		_ => PointerPhase.Cancel,
	};
}

export function takePointerEvents(): PointerEvent[] {
	const n: int32 = hudPointerTake();
	const events: PointerEvent[] = [];
	for (let i: int32 = 0; i < n; i += 1) {
		events.push({ phase: phaseOf(hudPointerPhase(i)), id: hudPointerId(i), x: hudPointerX(i), y: hudPointerY(i) });
	}
	return events;
}
