// Design units the finger travels sideways, and more than it travels up or down, to turn a page.
const SWIPE_MIN: float32 = 48.0;
// A second tap this soon and this near the first is a double tap.
const DOUBLE_TAP_SECONDS: float64 = 0.35;
const DOUBLE_TAP_REACH: float32 = 40.0;
const NO_TAP: float64 = -1.0;

export enum Gesture {
	None,
	// The finger moved right to left: the next page, as `>`.
	SwipeLeft,
	SwipeRight,
	DoubleTap,
}

export interface Taps {
	lastAt: float64;
	lastX: float32;
	lastY: float32;
}

export function noTaps(): Taps {
	return { lastAt: NO_TAP, lastX: 0.0, lastY: 0.0 };
}

// One finished press, from where it went down to where it came up at `now` seconds.
export function gestureOf(taps: Taps, pressX: float32, pressY: float32, releaseX: float32, releaseY: float32,
	now: float64): Gesture {
	const sideways: float32 = releaseX - pressX;
	if (Math.abs(sideways) >= SWIPE_MIN && Math.abs(sideways) > Math.abs(releaseY - pressY)) {
		taps.lastAt = NO_TAP;
		return sideways < 0.0 ? Gesture.SwipeLeft : Gesture.SwipeRight;
	}
	const near: boolean = Math.abs(releaseX - taps.lastX) <= DOUBLE_TAP_REACH && Math.abs(releaseY - taps.lastY) <= DOUBLE_TAP_REACH;
	if (taps.lastAt != NO_TAP && now - taps.lastAt <= DOUBLE_TAP_SECONDS && near) {
		taps.lastAt = NO_TAP;
		return Gesture.DoubleTap;
	}
	taps.lastAt = now;
	taps.lastX = releaseX;
	taps.lastY = releaseY;
	return Gesture.None;
}

test "a sideways drag turns the page, a quick second tap in place is a double tap" {
	const taps = noTaps();
	assert gestureOf(taps, 200.0, 400.0, 100.0, 420.0, 1.0) == Gesture.SwipeLeft;
	assert gestureOf(taps, 100.0, 400.0, 200.0, 380.0, 2.0) == Gesture.SwipeRight;
	assert gestureOf(taps, 100.0, 400.0, 160.0, 500.0, 3.0) == Gesture.None;
	assert gestureOf(taps, 150.0, 400.0, 150.0, 400.0, 10.0) == Gesture.None;
	assert gestureOf(taps, 155.0, 405.0, 155.0, 405.0, 10.2) == Gesture.DoubleTap;
	assert gestureOf(taps, 150.0, 400.0, 150.0, 400.0, 10.3) == Gesture.None;
	assert gestureOf(taps, 150.0, 400.0, 150.0, 400.0, 11.0) == Gesture.None;
	assert gestureOf(taps, 150.0, 400.0, 150.0, 400.0, 20.0) == Gesture.None;
	assert gestureOf(taps, 260.0, 400.0, 260.0, 400.0, 20.1) == Gesture.None;
}
