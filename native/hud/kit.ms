// Immediate mode like ui.ms: beginKit after beginUi, then the widgets, then endKit before endUi.
// Sprites are kept by widget id and hidden in a frame that does not draw them.

import { makeImage as makeImageBytes, makeView } from "@metascript/void/src/sokol/gpu";
import { makeImage, makeTextureView } from "@metascript/void/src/void3d/gpu3d";
import { Node2D, group, sprite, addChildAt, addChild } from "@metascript/void/src/void2d/node";
import { Color, rgba, tile } from "@metascript/void/src/void2d/types";
import { addFont, faceFor } from "@metascript/void/src/void2d/labelText";
import { TextLayout, TextStyle } from "@metascript/void/src/void2d/textLayout";
import { loadImageSync, imageWidth, imageHeight, freeImage } from "@metascript/void/src/assets/image";
import { Ui, text } from "../ui/ui";
import {
	KIT_DIRECTORY,
	REFERENCE_SCALE,
	MARGIN,
	FrameLook,
	FrameParts,
	Pixels,
	loadFrameParts,
	spliceFrame,
	badgeFor,
} from "./frame";

export const INK: Color = rgba(0.824, 0.831, 0.824, 1.0);
export const INK_MUTED: Color = rgba(0.608, 0.588, 0.592, 1.0);
export const EMBER: Color = rgba(0.784, 0.365, 0.157, 1.0);
export const EMBER_HOT: Color = rgba(0.969, 0.549, 0.227, 1.0);
export const EMBER_PRESSED: Color = rgba(1.0, 0.75, 0.45, 1.0);
export const ASH_DEEP: Color = rgba(0.047, 0.051, 0.063, 1.0);
export const ALERT_RED: Color = rgba(0.784, 0.239, 0.184, 1.0);
export const GROWTH_GREEN: Color = rgba(0.478, 0.663, 0.294, 1.0);
export const DISABLED_INK: Color = rgba(0.45, 0.43, 0.42, 1.0);
export const WHITE: Color = rgba(1.0, 1.0, 1.0, 1.0);
export const DIMMED: Color = rgba(0.45, 0.45, 0.45, 0.8);
export const SCREEN_WIDTH: float32 = 360.0;
export const SCREEN_HEIGHT: float32 = 800.0;
const SUB_ID_BASE: int32 = 1000000;
const FONT_PATH: string = "assets/fonts/Silkscreen-Regular.ttf";

// On Android files only open during init, while the asset root is the working directory, so
// every icon loads in createKit.
export const ICON_NAMES: string[] = ["heart", "bag", "lock", "warning", "winter", "growth", "insured", "gear",
	"home", "pet", "block", "shop", "digest", "crackedHeart", "shield", "fading", "rage", "skull", "wallet",
	"copy", "back", "send", "worked", "ate", "levelUp", "gearBought", "gearSold", "fightWon", "fightLost", "gift",
	"nodeSmallAllocated", "nodeSmallReachable", "nodeSmallLocked", "nodeNotableAllocated", "nodeNotableReachable",
	"nodeNotableLocked", "nodeKeystoneAllocated", "nodeKeystoneReachable", "nodeKeystoneLocked", "recenter"];

export interface Texture {
	view: uint32;
	width: int32;
	height: int32;
}

export interface KeptSprite {
	key: string;
	node: Node2D;
	used: boolean;
}

export interface NamedTexture {
	name: string;
	texture: Texture;
}

// Built once per process and shared by every Kit: a frame or icon texture is never made twice.
export interface KitTextures {
	font: int32;
	parts: FrameParts;
	frames: NamedTexture[];
	icons: NamedTexture[];
	badges: Texture[];
	white: Texture;
}

export interface Kit {
	backs: Node2D;
	backsTop: Node2D;
	frames: Node2D;
	icons: Node2D;
	framesTop: Node2D;
	iconsTop: Node2D;
	sprites: KeptSprite[];
	textures: KitTextures;
	overlay: boolean;
}

export interface TextSize {
	width: float32;
	height: float32;
}

export enum LookupError {
	Missing,
}

const sharedTextures: KitTextures[] = [];

function textureOf(image: Pixels): Texture {
	return { view: makeTextureView(makeImage(image.pixels, image.width, image.height)), width: image.width, height: image.height };
}

function loadIcon(name: string): Texture {
	const pixels = loadImageSync(KIT_DIRECTORY + "icons/" + name + ".png", 4);
	const width: int32 = imageWidth();
	const height: int32 = imageHeight();
	const view: uint32 = makeView(makeImageBytes(pixels, width, height));
	freeImage(pixels);
	return { view: view, width: width, height: height };
}

function createTextures(): KitTextures {
	const parts: FrameParts = loadFrameParts();
	const icons: NamedTexture[] = [];
	for (const name of ICON_NAMES) {
		icons.push({ name: name, texture: loadIcon(name) });
	}
	const badges: Texture[] = [];
	for (const badge of parts.badges) {
		badges.push(textureOf(badge));
	}
	const whitePixels: uint32[] = [0xFFFFFFFF as uint32, 0xFFFFFFFF as uint32, 0xFFFFFFFF as uint32, 0xFFFFFFFF as uint32];
	return {
		font: addFont(FONT_PATH),
		parts: parts,
		frames: [],
		icons: icons,
		badges: badges,
		white: { view: makeTextureView(makeImage(whitePixels, 2, 2)), width: 2, height: 2 },
	};
}

// ui.sc.root holds [boxes, texts, boxesTop, textsTop]; the kit's layers go round them so the
// order is backs, frames, boxes, icons, texts, then the same again for the overlay.
export function createKit(ui: Ui): Kit {
	if ((sharedTextures.length as int32) == 0) {
		sharedTextures.push(createTextures());
	}
	const kit: Kit = {
		backs: group(),
		backsTop: group(),
		frames: group(),
		icons: group(),
		framesTop: group(),
		iconsTop: group(),
		sprites: [],
		textures: sharedTextures[0],
		overlay: false,
	};
	ui.sc.root.addChildAt(kit.frames, 0);
	ui.sc.root.addChildAt(kit.icons, 2);
	ui.sc.root.addChildAt(kit.framesTop, 4);
	ui.sc.root.addChildAt(kit.iconsTop, 6);
	ui.sc.root.addChildAt(kit.backs, 0);
	ui.sc.root.addChildAt(kit.backsTop, 5);
	return kit;
}

// A widget that draws more than one thing derives ids from the caller's id; ids below
// SUB_ID_BASE stay free for callers.
export function subId(id: int32, part: int32): int32 {
	return SUB_ID_BASE + id * 16 + part;
}

export function beginKit(kit: Kit): void {
	for (const kept of kit.sprites) {
		kept.used = false;
	}
}

export function endKit(kit: Kit): void {
	for (const kept of kit.sprites) {
		kept.node.visible = kept.used;
	}
}

export function beginKitOverlay(kit: Kit): void {
	kit.overlay = true;
}

export function endKitOverlay(kit: Kit): void {
	kit.overlay = false;
}

function keptSprite(kit: Kit, key: string): Result<KeptSprite, LookupError> {
	for (const kept of kit.sprites) {
		if (kept.key == key) {
			return Result.ok(kept);
		}
	}
	return Result.err(LookupError.Missing);
}

function layerFor(kit: Kit, layer: Node2D): Node2D {
	if (!kit.overlay || layer === kit.backs || layer === kit.backsTop) {
		return layer;
	}
	return layer === kit.frames ? kit.framesTop : kit.iconsTop;
}

function newSprite(kit: Kit, layer: Node2D, key: string, view: uint32, width: float32, height: float32): KeptSprite {
	const kept: KeptSprite = { key: key, node: sprite(tile(view, width, height)), used: true };
	layerFor(kit, layer).addChild(kept.node);
	kit.sprites.push(kept);
	return kept;
}

function place(kit: Kit, layer: Node2D, key: string, view: uint32, x: float32, y: float32, width: float32, height: float32,
	tint: Color): void {
	const found: Result<KeptSprite, LookupError> = keptSprite(kit, key);
	const kept: KeptSprite = found.ok ? found.value : newSprite(kit, layer, key, view, width, height);
	kept.node.sheet = tile(view, width, height);
	kept.node.w = width;
	kept.node.h = height;
	kept.node.x = x;
	kept.node.y = y;
	kept.node.color = tint;
	kept.used = true;
}

// Below every frame, box, icon and label: a screen's backdrop over the 3D scene, which a ui box
// cannot be because it would cover the screen's own frames.
export function fill(kit: Kit, id: int32, x: float32, y: float32, width: float32, height: float32, color: Color): void {
	place(kit, kit.overlay ? kit.backsTop : kit.backs, "back" + id.toString(), kit.textures.white.view, x, y, width, height,
		color);
}

function lookName(look: FrameLook): string {
	return match (look) {
		FrameLook.Normal => "normal",
		FrameLook.Alert => "alert",
		FrameLook.Disabled => "disabled",
	};
}

function frameTexture(kit: Kit, width: float32, height: float32, seed: int32, look: FrameLook): Texture {
	const name: string = (width as int32).toString() + "x" + (height as int32).toString() + ":" + seed.toString() + lookName(look);
	for (const named of kit.textures.frames) {
		if (named.name == name) {
			return named.texture;
		}
	}
	const texture: Texture = textureOf(spliceFrame(kit.textures.parts, width, height, seed, look));
	kit.textures.frames.push({ name: name, texture: texture });
	return texture;
}

// The rim reaches a little outside the design rectangle.
export function frame(kit: Kit, id: int32, x: float32, y: float32, width: float32, height: float32, seed: int32,
	look: FrameLook): void {
	const texture: Texture = frameTexture(kit, width, height, seed, look);
	const margin: float32 = (MARGIN as float32) / REFERENCE_SCALE;
	place(kit, kit.frames, "frame" + id.toString(), texture.view, x - margin, y - margin,
		(texture.width as float32) / REFERENCE_SCALE, (texture.height as float32) / REFERENCE_SCALE, WHITE);
}

// A card flip: the frame for (width, height) drawn `squeeze` (0..1) as wide, centred, from the
// same cached texture.
export function frameSqueezed(kit: Kit, id: int32, x: float32, y: float32, width: float32, height: float32, seed: int32,
	look: FrameLook, squeeze: float32): void {
	frame(kit, id, x, y, width, height, seed, look);
	const found: Result<KeptSprite, LookupError> = keptSprite(kit, "frame" + id.toString());
	if (!found.ok) {
		return;
	}
	const node: Node2D = found.value.node;
	const full: float32 = node.w;
	node.w = full * squeeze;
	node.x = node.x + (full - node.w) * 0.5;
}

// The badge art is drawn for a 40-unit square and scales with `size`.
export function badgeFrame(kit: Kit, id: int32, x: float32, y: float32, size: float32, seed: int32): void {
	const texture: Texture = kit.textures.badges[badgeFor(kit.textures.parts, seed)];
	const scale: float32 = size / ((texture.width - 2 * MARGIN) as float32);
	const margin: float32 = (MARGIN as float32) * scale;
	const side: float32 = (texture.width as float32) * scale;
	place(kit, kit.frames, "frame" + id.toString(), texture.view, x - margin, y - margin, side, side, WHITE);
}

function iconTexture(kit: Kit, name: string): Texture {
	for (const named of kit.textures.icons) {
		if (named.name == name) {
			return named.texture;
		}
	}
	const texture: Texture = loadIcon(name);
	kit.textures.icons.push({ name: name, texture: texture });
	return texture;
}

export function icon(kit: Kit, id: int32, name: string, x: float32, y: float32, size: float32): void {
	iconTinted(kit, id, name, x, y, size, WHITE);
}

// Fitted with its aspect kept and centred in the size x size square.
export function iconTinted(kit: Kit, id: int32, name: string, x: float32, y: float32, size: float32, tint: Color): void {
	const texture: Texture = iconTexture(kit, name);
	const textureWidth: float32 = texture.width as float32;
	const textureHeight: float32 = texture.height as float32;
	const scale: float32 = size / (textureWidth > textureHeight ? textureWidth : textureHeight);
	const width: float32 = textureWidth * scale;
	const height: float32 = textureHeight * scale;
	place(kit, kit.icons, "icon" + id.toString() + name, texture.view, x + (size - width) * 0.5, y + (size - height) * 0.5,
		width, height, tint);
}

function textStyle(kit: Kit, size: float32, maxWidth: float32): TextStyle {
	return { face: faceFor(kit.textures.font), size: size, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: maxWidth, align: 0.0 };
}

export function measure(kit: Kit, line: string, size: float32): TextSize {
	const laid: TextLayout = TextLayout.layout(line, textStyle(kit, size, 0.0));
	return { width: laid.width, height: laid.lineHeight };
}

export function measureWrapped(kit: Kit, line: string, size: float32, maxWidth: float32): TextSize {
	const laid: TextLayout = TextLayout.layout(line, textStyle(kit, size, maxWidth));
	return { width: laid.width, height: laid.height };
}

// ui.text in Silkscreen; sizes 8 and 16 stay crisp.
export function say(ui: Ui, kit: Kit, id: int32, line: string, x: float32, y: float32, width: float32, size: float32,
	color: Color, align: float32): void {
	text(ui, id, line, x, y, width, size, color, align);
	for (let index: int32 = 0; index < ui.labelIds.length; index += 1) {
		if (ui.labelIds[index] === id) {
			ui.labelNodes[index].fontId = kit.textures.font;
		}
	}
}
