// Tilt: how far the phone is tipped from the way it is being held, for the camera's parallax.
//
// The shell pushes the phone's rotation (tilt.c). Each frame its rotation against a base that
// follows it over TILT_RECENTER_SECONDS, in the phone's own axes, gives two angles in radians,
// smoothed over TILT_SMOOTH_SECONDS and limited softly to TILT_MAX_*:
// - yaw: tipped left or right, about the screen's vertical axis or about its normal (a steering
//   wheel turn, which is how a phone held out in front is tipped sideways). With the phone held
//   leaning back, both are the same way round, so they add.
// - pitch: tipped up or down, about the screen's horizontal axis.
// The angles come from the relative rotation, not Euler angles, which lock with the phone upright.

@include("./tilt.h");
@compile("./tilt.c");

extern function tiltTake(): int32;
extern function tiltW(): float32;
extern function tiltX(): float32;
extern function tiltY(): float32;
extern function tiltZ(): float32;

export const TILT_GAIN: float32 = 1.0;
export const TILT_MAX_YAW: float32 = 0.21;
export const TILT_MAX_PITCH: float32 = 0.105;
export const TILT_YAW_SIGN: float32 = 1.0;
export const TILT_PITCH_SIGN: float32 = 1.0;
export const TILT_RECENTER_SECONDS: float32 = 3.0;
export const TILT_SMOOTH_SECONDS: float32 = 0.03;
const LONGEST_STEP_SECONDS: float32 = 0.25;

export struct Tilt {
	yaw: float32;
	pitch: float32;
}

struct Rotation {
	w: float32;
	x: float32;
	y: float32;
	z: float32;
}

const NO_TILT: Tilt = { yaw: 0.0, pitch: 0.0 };

let hasBase: boolean = false;
let base: Rotation = { w: 1.0, x: 0.0, y: 0.0, z: 0.0 };
let smoothed: Tilt = NO_TILT;
let lastAt: float64 = -1.0;

// The rotation from `a` to `b` in `a`'s own axes: conjugate(a) * b.
function between(a: Rotation, b: Rotation): Rotation {
	return {
		w: a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z,
		x: a.w * b.x - a.x * b.w - a.y * b.z + a.z * b.y,
		y: a.w * b.y + a.x * b.z - a.y * b.w - a.z * b.x,
		z: a.w * b.z - a.x * b.y + a.y * b.x - a.z * b.w,
	};
}

// `towards` moved `share` of the way from `from`, on `from`'s side of the sphere, normalised.
function blended(from: Rotation, towards: Rotation, share: float32): Rotation {
	const sameSide: float32 = from.w * towards.w + from.x * towards.x + from.y * towards.y + from.z * towards.z;
	const sign: float32 = sameSide < 0.0 ? (-1.0 as float32) : (1.0 as float32);
	const w: float32 = from.w + (towards.w * sign - from.w) * share;
	const x: float32 = from.x + (towards.x * sign - from.x) * share;
	const y: float32 = from.y + (towards.y * sign - from.y) * share;
	const z: float32 = from.z + (towards.z * sign - from.z) * share;
	const length: float32 = Math.sqrt(w * w + x * x + y * y + z * z) as float32;
	return { w: w / length, x: x / length, y: y / length, z: z / length };
}

function approach(seconds: float32, step: float32): float32 {
	return (1.0 - Math.exp(-step / seconds)) as float32;
}

function limited(angle: float32, most: float32): float32 {
	return (most * Math.tanh(angle / most)) as float32;
}

// Twice the angle of the rotation's part about one of its axes, the short way round.
function twist(axis: float32, w: float32): float32 {
	const side: float32 = w < 0.0 ? (-1.0 as float32) : (1.0 as float32);
	return 2.0 * (Math.atan2(axis * side, w * side) as float32);
}

export function readTilt(): Tilt {
	const now: float64 = performance.now() / 1000.0;
	const step: float32 = lastAt < 0.0 ? (0.0 as float32) : (Math.min(now - lastAt, LONGEST_STEP_SECONDS as float64) as float32);
	lastAt = now;
	if (tiltTake() == 0) { return NO_TILT; }
	const current: Rotation = { w: tiltW(), x: tiltX(), y: tiltY(), z: tiltZ() };
	if (!hasBase) {
		base = current;
		hasBase = true;
	}
	const relative: Rotation = between(base, current);
	const target: Tilt = {
		yaw: limited(TILT_YAW_SIGN * TILT_GAIN * (twist(relative.y, relative.w) + twist(relative.z, relative.w)), TILT_MAX_YAW),
		pitch: limited(TILT_PITCH_SIGN * TILT_GAIN * twist(relative.x, relative.w), TILT_MAX_PITCH),
	};
	const follow: float32 = approach(TILT_SMOOTH_SECONDS, step);
	smoothed = {
		yaw: smoothed.yaw + (target.yaw - smoothed.yaw) * follow,
		pitch: smoothed.pitch + (target.pitch - smoothed.pitch) * follow,
	};
	base = blended(base, current, approach(TILT_RECENTER_SECONDS, step));
	return smoothed;
}
