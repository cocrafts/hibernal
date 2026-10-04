// A frame starts from a whole frame of the style reference (art/ui-kit/sheets/styleReference.png,
// exported by art/ui-kit/tools/exportKitParts.py) and is resized by cutting out or repeating
// plank spans at the darkest rim joints, so the cut never shows; the interior is then repainted
// as dark planks. The seed picks the base and the cuts: every panel differs, the same seed gives
// the same frame. Same decisions as the Python prototype kitbashFrame.py spliceFrame.

import { readFile } from "std/fs";

export const KIT_DIRECTORY: string = "assets/hud/kit/";
export const REFERENCE_SCALE: float32 = 1.9333333;
export const MARGIN: int32 = 4;
const RIM_DEPTH: int32 = 21;
const CORNER: int32 = 30;
const BASES: int32 = 3;
const LUMINANCE_RED: float32 = 0.2126;
const LUMINANCE_GREEN: float32 = 0.7152;
const LUMINANCE_BLUE: float32 = 0.0722;
const EMBER_RATIO: float32 = 1.6;

export enum FrameLook {
	Normal,
	Alert,
	Disabled,
}

export enum PixelsError {
	Unreadable,
	Truncated,
}

export interface Pixels {
	width: int32;
	height: int32;
	pixels: uint32[];
}

export interface FrameParts {
	bases: Pixels[];
	badges: Pixels[];
	rows: uint32[];
}

export interface SeededRandom {
	state: uint32;
}

function littleEndianWord(bytes: uint8[], at: int32): uint32 {
	return (bytes[at] as uint32)
		| ((bytes[at + 1] as uint32) << 8)
		| ((bytes[at + 2] as uint32) << 16)
		| ((bytes[at + 3] as uint32) << 24);
}

export function loadPixels(path: string): Result<Pixels, PixelsError> {
	const file = readFile(path);
	if (!file.ok) {
		return Result.err(PixelsError.Unreadable);
	}
	const bytes: uint8[] = file.value.asBytes();
	if ((bytes.length as int32) < 8) {
		return Result.err(PixelsError.Truncated);
	}
	const width: int32 = littleEndianWord(bytes, 0) as int32;
	const height: int32 = littleEndianWord(bytes, 4) as int32;
	if ((bytes.length as int32) < 8 + width * height * 4) {
		return Result.err(PixelsError.Truncated);
	}
	const pixels: uint32[] = [];
	for (let index: int32 = 0; index < width * height; index += 1) {
		pixels.push(littleEndianWord(bytes, 8 + index * 4));
	}
	return Result.ok({ width: width, height: height, pixels: pixels });
}

function loadedOrEmpty(path: string): Pixels {
	const loaded: Result<Pixels, PixelsError> = loadPixels(path);
	if (!loaded.ok) {
		console.log("hud: cannot read " + path);
		return { width: 0, height: 0, pixels: [] };
	}
	return loaded.value;
}

export function loadFrameParts(): FrameParts {
	const bases: Pixels[] = [];
	const badges: Pixels[] = [];
	for (let index: int32 = 0; index < BASES; index += 1) {
		bases.push(loadedOrEmpty(KIT_DIRECTORY + "frame" + index.toString() + ".rgba"));
		badges.push(loadedOrEmpty(KIT_DIRECTORY + "badge" + index.toString() + ".rgba"));
	}
	return { bases: bases, badges: badges, rows: loadedOrEmpty(KIT_DIRECTORY + "rows.rgba").pixels };
}

function smaller(first: int32, second: int32): int32 { return first < second ? first : second; }
function larger(first: int32, second: int32): int32 { return first > second ? first : second; }

function red(color: uint32): int32 { return (color & 255) as int32; }
function green(color: uint32): int32 { return ((color >> 8) & 255) as int32; }
function blue(color: uint32): int32 { return ((color >> 16) & 255) as int32; }
function alpha(color: uint32): int32 { return ((color >> 24) & 255) as int32; }

function clampedChannel(value: int32): uint32 {
	return match (value) {
		_ when value < 0 => 0 as uint32,
		_ when value > 255 => 255 as uint32,
		_ => value as uint32,
	};
}

function packed(redPart: int32, greenPart: int32, bluePart: int32, alphaPart: int32): uint32 {
	return clampedChannel(redPart)
		| (clampedChannel(greenPart) << 8)
		| (clampedChannel(bluePart) << 16)
		| ((alphaPart as uint32) << 24);
}

function luminance(color: uint32): float32 {
	return LUMINANCE_RED * (red(color) as float32)
		+ LUMINANCE_GREEN * (green(color) as float32)
		+ LUMINANCE_BLUE * (blue(color) as float32);
}

function isEmber(color: uint32): boolean {
	return red(color) > 120 && (red(color) as float32) > EMBER_RATIO * (green(color) as float32);
}

function pixelAt(image: Pixels, x: int32, y: int32): uint32 {
	return image.pixels[y * image.width + x];
}

export function seededRandom(seed: int32): SeededRandom {
	const state: uint32 = ((seed as uint32) * 2654435761) ^ 0x9E3779B9;
	return { state: state == 0 ? 1 as uint32 : state };
}

export function nextBelow(random: SeededRandom, bound: int32): int32 {
	let state: uint32 = random.state;
	state = state ^ (state << 13);
	state = state ^ (state >> 17);
	state = state ^ (state << 5);
	random.state = state;
	if (bound <= 0) {
		return 0;
	}
	return (state % (bound as uint32)) as int32;
}

// Low score = a dark plank joint, where a cut hides.
function rimScores(image: Pixels, alongX: boolean): float32[] {
	const length: int32 = alongX ? image.width : image.height;
	const deepest: int32 = MARGIN + (RIM_DEPTH * 2) / 3;
	const scores: float32[] = [];
	for (let position: int32 = 0; position < length; position += 1) {
		let sum: float32 = 0.0;
		let count: int32 = 0;
		for (let depth: int32 = MARGIN; depth < deepest; depth += 1) {
			const near: uint32 = alongX ? pixelAt(image, position, depth) : pixelAt(image, depth, position);
			const far: uint32 = alongX
				? pixelAt(image, position, image.height - 1 - depth)
				: pixelAt(image, image.width - 1 - depth, position);
			sum += alpha(near) > 0 ? luminance(near) : 0.0;
			sum += alpha(far) > 0 ? luminance(far) : 0.0;
			count += 2;
		}
		scores.push(sum / (count as float32));
	}
	return scores;
}

function firstCuttable(): int32 { return CORNER + MARGIN + 4; }
function lastCuttable(length: int32): int32 { return length - CORNER - MARGIN - 4; }

// The darkest joints between the corners, darkest first, at least four.
function darkJoints(image: Pixels, alongX: boolean): int32[] {
	const length: int32 = alongX ? image.width : image.height;
	const scores: float32[] = rimScores(image, alongX);
	const first: int32 = firstCuttable();
	const last: int32 = lastCuttable(length);
	const positions: int32[] = [];
	for (let position: int32 = first; position < last; position += 1) {
		positions.push(position);
	}
	for (let sorted: int32 = 1; sorted < positions.length; sorted += 1) {
		const moving: int32 = positions[sorted];
		let slot: int32 = sorted - 1;
		while (slot >= 0 && scores[positions[slot]] > scores[moving]) {
			positions[slot + 1] = positions[slot];
			slot -= 1;
		}
		positions[slot + 1] = moving;
	}
	const keep: int32 = larger((last - first) / 6, 4);
	const joints: int32[] = [];
	for (let index: int32 = 0; index < positions.length && index < keep; index += 1) {
		joints.push(positions[index]);
	}
	if ((joints.length as int32) == 0) {
		joints.push(length / 2);
	}
	return joints;
}

function copySpan(source: Pixels, target: Pixels, alongX: boolean, from: int32, to: int32, into: int32): void {
	if (alongX) {
		for (let y: int32 = 0; y < source.height; y += 1) {
			for (let x: int32 = from; x < to; x += 1) {
				target.pixels[y * target.width + into + x - from] = pixelAt(source, x, y);
			}
		}
		return;
	}
	for (let y: int32 = from; y < to; y += 1) {
		for (let x: int32 = 0; x < source.width; x += 1) {
			target.pixels[(into + y - from) * target.width + x] = pixelAt(source, x, y);
		}
	}
}

function blank(width: int32, height: int32): Pixels {
	const pixels: uint32[] = [];
	for (let index: int32 = 0; index < width * height; index += 1) {
		pixels.push(0 as uint32);
	}
	return { width: width, height: height, pixels: pixels };
}

function shortened(image: Pixels, target: int32, alongX: boolean, joints: int32[], random: SeededRandom): Pixels {
	const length: int32 = alongX ? image.width : image.height;
	const cut: int32 = length - target;
	let start: int32 = joints[nextBelow(random, joints.length as int32)];
	start = larger(smaller(start, lastCuttable(length) - cut), firstCuttable());
	let end: int32 = start + cut;
	if (end > length) {
		end = length;
		start = length - cut;
	}
	const result: Pixels = alongX ? blank(target, image.height) : blank(image.width, target);
	copySpan(image, result, alongX, 0, start, 0);
	copySpan(image, result, alongX, end, length, start);
	return result;
}

// Repeats the span between the outermost dark joints until long enough.
function lengthened(image: Pixels, target: int32, alongX: boolean, joints: int32[], random: SeededRandom): Pixels {
	const length: int32 = alongX ? image.width : image.height;
	let spanStart: int32 = joints[0];
	let spanEnd: int32 = joints[0];
	for (const joint of joints) {
		spanStart = smaller(spanStart, joint);
		spanEnd = larger(spanEnd, joint);
	}
	if (spanEnd - spanStart < 12) {
		spanStart = firstCuttable();
		spanEnd = lastCuttable(length);
	}
	const cut: int32 = joints[nextBelow(random, joints.length as int32)];
	const result: Pixels = alongX ? blank(target, image.height) : blank(image.width, target);
	copySpan(image, result, alongX, 0, cut, 0);
	let into: int32 = cut;
	let missing: int32 = target - length;
	while (missing > 0) {
		const span: int32 = smaller(missing, spanEnd - spanStart);
		copySpan(image, result, alongX, spanStart, spanStart + span, into);
		into += span;
		missing -= span;
	}
	copySpan(image, result, alongX, cut, length, into);
	return result;
}

function resized(image: Pixels, target: int32, alongX: boolean, random: SeededRandom): Pixels {
	const length: int32 = alongX ? image.width : image.height;
	const joints: int32[] = darkJoints(image, alongX);
	return match (target) {
		_ when target == length => image,
		_ when target < length => shortened(image, target, alongX, joints, random),
		_ => lengthened(image, target, alongX, joints, random),
	};
}

export function referenceSize(design: float32): int32 {
	const half: float32 = 0.5;
	return ((design * REFERENCE_SCALE + half) as int32) + 2 * MARGIN;
}

function plankRow(rows: uint32[], row: int32): uint32 {
	const count: int32 = rows.length as int32;
	return rows[((row % count) + count) % count];
}

export function spliceFrame(parts: FrameParts, width: float32, height: float32, seed: int32, look: FrameLook): Pixels {
	const random: SeededRandom = seededRandom(seed);
	const base: Pixels = parts.bases[nextBelow(random, BASES)];
	const targetWidth: int32 = referenceSize(width);
	const targetHeight: int32 = referenceSize(height);
	const image: Pixels = resized(resized(base, targetWidth, true, random), targetHeight, false, random);
	const inset: int32 = MARGIN + RIM_DEPTH - 2;
	for (let y: int32 = inset; y < image.height - inset; y += 1) {
		const plank: uint32 = plankRow(parts.rows, y - inset);
		for (let x: int32 = inset; x < image.width - inset; x += 1) {
			image.pixels[y * image.width + x] = plank;
		}
	}
	// The source panel's text and widgets just inside the rim are painted over.
	for (let y: int32 = MARGIN + 8; y < image.height - MARGIN - 8; y += 1) {
		for (let x: int32 = MARGIN + 8; x < image.width - MARGIN - 8; x += 1) {
			if (x >= inset && x < image.width - inset && y >= inset && y < image.height - inset) {
				continue;
			}
			const color: uint32 = pixelAt(image, x, y);
			const depth: int32 = smaller(smaller(x, y), smaller(image.width - 1 - x, image.height - 1 - y));
			if (alpha(color) > 0 && luminance(color) > 44.0 && !isEmber(color) && depth > MARGIN + 11) {
				image.pixels[y * image.width + x] = plankRow(parts.rows, y - inset);
			}
		}
	}
	addGrain(image, parts.rows, inset, (targetWidth * targetHeight) / 900, random);
	tint(image, look, inset);
	return image;
}

function addGrain(image: Pixels, rows: uint32[], inset: int32, streaks: int32, random: SeededRandom): void {
	const across: int32 = image.width - 2 * inset - 30;
	const down: int32 = image.height - 2 * inset - 1;
	if (across <= 0 || down <= 0) {
		return;
	}
	for (let streak: int32 = 0; streak < streaks; streak += 1) {
		const startX: int32 = inset + nextBelow(random, across);
		const y: int32 = inset + nextBelow(random, down);
		const length: int32 = 8 + nextBelow(random, 23);
		const plank: uint32 = plankRow(rows, y - inset + 3);
		for (let x: int32 = startX; x < startX + length && x < image.width - inset; x += 1) {
			image.pixels[y * image.width + x] = plank;
		}
	}
}

function tinted(color: uint32, look: FrameLook, inside: boolean): uint32 {
	const redPart: int32 = red(color);
	const greenPart: int32 = green(color);
	const bluePart: int32 = blue(color);
	const grey: int32 = luminance(color) as int32;
	return match (look) {
		FrameLook.Normal => color,
		FrameLook.Alert => inside
			? packed(redPart + 10, greenPart, bluePart, alpha(color))
			: packed((redPart * 13) / 10 + 12, (greenPart * 8) / 10, (bluePart * 3) / 4, alpha(color)),
		FrameLook.Disabled => packed(grey + 4, grey + 2, grey, alpha(color)),
	};
}

function tint(image: Pixels, look: FrameLook, inset: int32): void {
	if (look == FrameLook.Normal) {
		return;
	}
	for (let y: int32 = 0; y < image.height; y += 1) {
		for (let x: int32 = 0; x < image.width; x += 1) {
			const color: uint32 = pixelAt(image, x, y);
			if (alpha(color) == 0) {
				continue;
			}
			const inside: boolean = x >= inset && x < image.width - inset && y >= inset && y < image.height - inset;
			image.pixels[y * image.width + x] = tinted(color, look, inside);
		}
	}
}

export function badgeFor(parts: FrameParts, seed: int32): int32 {
	return nextBelow(seededRandom(seed), BASES);
}
