// Immediate mode like ui.ms: beginKit after beginUi, then the widgets, then endKit before endUi.
// Sprites are kept by widget id and hidden in a frame that does not draw them.

import { makeImage as makeImageBytes, makeView } from "@metascript/void/src/sokol/gpu";
import { makeImage } from "@metascript/void/src/void3d/gpu3d";
import { makeTextureView } from "@metascript/void/src/gpu/door";
import {
	NodeRef,
	group,
	sprite,
	addChildAt,
	addChild,
	local,
	content,
	setTile,
	setSize,
	setPosition,
	setColor,
	setVisible,
	setFont,
} from "@metascript/void/src/void2d/node";
import { Color, rgba, tile } from "@metascript/void/src/void2d/types";
import { FontId, FontError, addFont } from "@metascript/void/src/void2d/font";
import { TextLayout, TextStyle, Align } from "@metascript/void/src/void2d/textLayout";
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
export const INK_BRIGHT: Color = rgba(0.92, 0.96, 1.0, 1.0);
export const HOLO_BLUE: Color = rgba(0.45, 0.78, 1.0, 1.0);
export const HOLO_GREEN: Color = rgba(0.5, 1.0, 0.55, 1.0);
export const DIMMED: Color = rgba(0.45, 0.45, 0.45, 0.8);
export const SCREEN_WIDTH: float32 = 360.0;
export const SCREEN_HEIGHT: float32 = 800.0;
// Material's 48 dp minimum touch target: 44 design units on the Seeker (360 units over 1200 px
// at 480 dpi).
export const TOUCH_HEIGHT: float32 = 44.0;
// Rows stacked in a column, so their tap areas meet without overlapping: 33 dp.
export const STACKED_ROW_HEIGHT: float32 = 30.0;
const SUB_ID_BASE: int32 = 1000000;
const FONT_PATH: string = "assets/fonts/Silkscreen-Regular.ttf";
const PIECE_DIRECTORY: string = "assets/hud/pieces/";
// art/hud/cutHud.py cuts the pieces at the Seeker's pixels per design unit.
const PIECE_DENSITY: float32 = 1200.0 / 360.0;

// On Android files only open during init, while the asset root is the working directory, so
// every icon loads in createKit.
export const ICON_NAMES: string[] = ["heart", "bag", "lock", "warning", "winter", "growth", "insured", "gear",
	"home", "pet", "block", "shop", "digest", "crackedHeart", "shield", "fading", "rage", "skull", "wallet",
	"copy", "back", "send", "worked", "ate", "levelUp", "gearBought", "gearSold", "fightWon", "fightLost", "gift",
	"nodeSmallAllocated", "nodeSmallReachable", "nodeSmallLocked", "nodeNotableAllocated", "nodeNotableReachable",
	"nodeNotableLocked", "nodeKeystoneAllocated", "nodeKeystoneReachable", "nodeKeystoneLocked", "recenter"];
export const PIECE_NAMES: string[] = ["panel", "xpFrame", "slot", "plusSlot", "levelPlate", "endCap", "tab", "hatch", "dot",
	"sword", "pistol", "shotgun", "core", "rifle", "statFrame", "statBadge", "statFillRedEnd", "statFillRedBody",
	"statFillBlueEnd", "statFillBlueBody", "statFillGreenEnd", "statFillGreenBody", "statFillOrangeEnd", "statFillOrangeBody",
	"gearIconHeadForage", "gearIconHeadMight", "gearIconHeadGrit", "gearIconBodyForage", "gearIconBodyMight",
	"gearIconBodyGrit", "gearIconHandsForage", "gearIconHandsMight", "gearIconHandsGrit", "gearIconFeetForage",
	"gearIconFeetMight", "gearIconFeetGrit", "statHeart", "statGift", "statGrowth", "medkit", "battery", "ammo", "shield", "drone", "shopSword", "shopPistol",
	"shopShotgun", "shopCore", "shopMedkit", "shopBattery", "shopAmmo", "shopShield", "shopDrone", "toggleOff", "toggleOn",
	"toggleHeld", "toggleDisabled", "bannerStart", "bannerBody", "bannerEnd", "plusSlotOrange",
	"bannerStartOrange", "bannerBodyOrange", "bannerEndOrange",
	"onboardingCreate", "onboardingName", "onboardingPrevious", "onboardingNext",
	"onboardingHologram", "onboardingWallet", "onboardingHologramDead", "onboardingNameDead", "itemCard", "shopStrip",
	"ownerShopBuy", "ownerShopCancel", "ownerShopCard", "ownerShopCardDim", "ownerShopCardInCart",
	"ownerShopCardLocked", "ownerShopCart", "ownerShopCartIcon", "ownerShopClose", "ownerShopCoin",
	"ownerShopComingSoon", "ownerShopCornerBottomLeft", "ownerShopCornerBottomRight", "ownerShopCornerTopLeft",
	"ownerShopCornerTopRight", "ownerShopDeadBar", "ownerShopDeadCap", "ownerShopErrorBar", "ownerShopErrorCap",
	"ownerShopFoodIcon0", "ownerShopFoodIcon1", "ownerShopFoodIcon2", "ownerShopFork", "ownerShopGrowthIcon0",
	"ownerShopGrowthIcon1", "ownerShopGrowthIcon2", "ownerShopHeader", "ownerShopHelix", "ownerShopInsurance",
	"ownerShopInsuranceIcon", "ownerShopMinus", "ownerShopOkBar", "ownerShopOkCap", "ownerShopSectionBar",
	"ownerShopShield", "ownerShopShirt", "ownerShopTitle", "ownerShopTruck", "ownerShopWarningBar",
	"ownerShopWarningCap",
];

export interface Texture {
	view: uint32;
	width: int32;
	height: int32;
}

export interface KeptSprite {
	key: string;
	node: NodeRef;
	used: boolean;
}

export interface NamedTexture {
	name: string;
	texture: Texture;
}

// Built once per process and shared by every Kit: a frame or icon texture is never made twice.
export interface KitTextures {
	font: FontId;
	parts: FrameParts;
	frames: NamedTexture[];
	icons: NamedTexture[];
	pieces: NamedTexture[];
	badges: Texture[];
	white: Texture;
}

export interface Kit {
	backs: NodeRef;
	backsTop: NodeRef;
	frames: NodeRef;
	icons: NodeRef;
	framesTop: NodeRef;
	iconsTop: NodeRef;
	sprites: KeptSprite[];
	textures: KitTextures;
	overlay: boolean;
	// Multiplies every tint's alpha: below 1 while a press's look draws (pressedLook).
	fade: float32;
	presses: PressFade[];
	// performance.now() seconds at the last beginKit, and the time since the one before.
	frameAt: float64;
	frameSeconds: float32;
}

export interface PressFade {
	id: int32;
	level: float32;
}

export interface TextSize {
	width: float32;
	height: float32;
}

export enum LookupError {
	Missing,
}

export enum PieceLayer {
	Frames,
	Icons,
}

const sharedTextures: KitTextures[] = [];

function textureOf(image: Pixels): Texture {
	return { view: makeTextureView(makeImage(image.pixels, image.width, image.height)), width: image.width, height: image.height };
}

function loadIcon(name: string): Texture {
	return loadTexture(KIT_DIRECTORY + "icons/" + name + ".png");
}

function loadTexture(path: string): Texture {
	const pixels = loadImageSync(path, 4);
	const width: int32 = imageWidth();
	const height: int32 = imageHeight();
	if (width <= 0 || height <= 0) {
		console.log("kit: " + path + " did not load");
		unreachable;
	}
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
	const pieces: NamedTexture[] = [];
	for (const name of PIECE_NAMES) {
		pieces.push({ name: name, texture: loadTexture(PIECE_DIRECTORY + name + ".png") });
	}
	const badges: Texture[] = [];
	for (const badge of parts.badges) {
		badges.push(textureOf(badge));
	}
	const whitePixels: uint32[] = [0xFFFFFFFF as uint32, 0xFFFFFFFF as uint32, 0xFFFFFFFF as uint32, 0xFFFFFFFF as uint32];
	const font: Result<FontId, FontError> = addFont(FONT_PATH);
	if (!font.ok) {
		console.log("kit: " + FONT_PATH + " did not load: " + font.error.toString());
		unreachable;
	}
	return {
		font: font.value,
		parts: parts,
		frames: [],
		icons: icons,
		pieces: pieces,
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
		backs: ui.sc.group(),
		backsTop: ui.sc.group(),
		frames: ui.sc.group(),
		icons: ui.sc.group(),
		framesTop: ui.sc.group(),
		iconsTop: ui.sc.group(),
		sprites: [],
		textures: sharedTextures[0],
		overlay: false,
		fade: 1.0,
		presses: [],
		frameAt: -1.0,
		frameSeconds: 0.0,
	};
	const root: NodeRef = ui.sc.refOf(ui.sc.root);
	root.addChildAt(kit.frames, 0);
	root.addChildAt(kit.icons, 2);
	root.addChildAt(kit.framesTop, 4);
	root.addChildAt(kit.iconsTop, 6);
	root.addChildAt(kit.backs, 0);
	root.addChildAt(kit.backsTop, 5);
	return kit;
}

// A widget that draws more than one thing derives ids from the caller's id; ids below
// SUB_ID_BASE stay free for callers.
export function subId(id: int32, part: int32): int32 {
	return SUB_ID_BASE + id * 16 + part;
}

export function beginKit(kit: Kit): void {
	const now: float64 = performance.now() / 1000.0;
	const passed: float64 = kit.frameAt < 0.0 ? 0.0 : now - kit.frameAt;
	kit.frameAt = now;
	kit.frameSeconds = Math.max(0.0, Math.min(passed, LONGEST_FADE_STEP)) as float32;
	for (const kept of kit.sprites) {
		kept.used = false;
	}
}

export function endKit(kit: Kit): void {
	for (const kept of kit.sprites) {
		kept.node.setVisible(kept.used);
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

function layerFor(kit: Kit, layer: NodeRef): NodeRef {
	if (!kit.overlay || layer == kit.backs || layer == kit.backsTop) {
		return layer;
	}
	return layer == kit.frames ? kit.framesTop : kit.iconsTop;
}

function newSprite(kit: Kit, layer: NodeRef, key: string, view: uint32, width: float32, height: float32): KeptSprite {
	const kept: KeptSprite = { key: key, node: layer.scene.sprite(tile(view, width, height)), used: true };
	layerFor(kit, layer).addChild(kept.node);
	kit.sprites.push(kept);
	return kept;
}

function place(kit: Kit, layer: NodeRef, key: string, view: uint32, x: float32, y: float32, width: float32, height: float32,
	tint: Color): void {
	const found: Result<KeptSprite, LookupError> = keptSprite(kit, key);
	const kept: KeptSprite = found.ok ? found.value : newSprite(kit, layer, key, view, width, height);
	kept.node.setTile(tile(view, width, height));
	kept.node.setSize(width, height);
	kept.node.setPosition(x, y);
	kept.node.setColor(faded(tint, kit.fade));
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
	const node: NodeRef = found.value.node;
	const full: float32 = node.content().w;
	const narrowed: float32 = full * squeeze;
	node.setSize(narrowed, node.content().h);
	node.setPosition(node.local().x + (full - narrowed) * 0.5, node.local().y);
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

function pieceTexture(kit: Kit, name: string): Texture {
	for (const named of kit.textures.pieces) {
		if (named.name == name) {
			return named.texture;
		}
	}
	console.log("kit: no piece " + name + " in " + PIECE_DIRECTORY + " (PIECE_NAMES loads them in createKit)");
	unreachable;
}

export function pieceWidth(kit: Kit, name: string): float32 {
	return (pieceTexture(kit, name).width as float32) / PIECE_DENSITY;
}

export function pieceHeight(kit: Kit, name: string): float32 {
	return (pieceTexture(kit, name).height as float32) / PIECE_DENSITY;
}

// At its own size, top-left at (x, y).
export function piece(kit: Kit, id: int32, layer: PieceLayer, name: string, x: float32, y: float32): void {
	pieceSized(kit, id, layer, name, x, y, pieceWidth(kit, name), pieceHeight(kit, name));
}

export function pieceSized(kit: Kit, id: int32, layer: PieceLayer, name: string, x: float32, y: float32, width: float32,
	height: float32): void {
	const into: NodeRef = match (layer) {
		PieceLayer.Frames => kit.frames,
		PieceLayer.Icons => kit.icons,
	};
	place(kit, into, "piece" + id.toString(), pieceTexture(kit, name).view, x, y, width, height, WHITE);
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
	return { font: kit.textures.font, size: size, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: maxWidth, align: Align.Left };
}

export function measure(kit: Kit, line: string, size: float32): TextSize {
	const laid: TextLayout = TextLayout.layout(line, textStyle(kit, size, 0.0));
	return { width: laid.width, height: laid.lineHeight };
}

// Silkscreen draws its capitals 5 pixels tall on an 8-pixel em.
const CAP_HEIGHT_EM: float32 = 0.625;

// Centres the capitals, not the line box: Silkscreen is caps only, and its ascent leaves room above them.
export function capsCentredY(kit: Kit, line: string, size: float32, y: float32, height: float32): float32 {
	const laid: TextLayout = TextLayout.layout(line, textStyle(kit, size, 0.0));
	return y + (height + CAP_HEIGHT_EM * size) * 0.5 - laid.ascent;
}

export function measureWrapped(kit: Kit, line: string, size: float32, maxWidth: float32): TextSize {
	const laid: TextLayout = TextLayout.layout(line, textStyle(kit, size, maxWidth));
	return { width: laid.width, height: laid.height };
}

// ui.text in Silkscreen; sizes 8 and 16 stay crisp.
const PRESSED_FADE: float32 = 0.55;
// As TouchableOpacity: quick to fade under the finger, slower back on release.
const FADE_IN_SECONDS: float32 = 0.12;
const FADE_OUT_SECONDS: float32 = 0.25;
const LONGEST_FADE_STEP: float64 = 0.1;

function faded(colour: Color, fade: float32): Color {
	return fade < 1.0 ? rgba(colour.r, colour.g, colour.b, colour.a * fade) : colour;
}

function pressFade(kit: Kit, id: int32): PressFade {
	for (const press of kit.presses) {
		if (press.id == id) { return press; }
	}
	const press: PressFade = { id: id, level: 1.0 };
	kit.presses.push(press);
	return press;
}

// React Native's TouchableOpacity: what press `id` draws between pressedLook and plainLook fades out
// while the finger holds it and back in after, over FADE_IN_SECONDS and FADE_OUT_SECONDS.
export function pressedLook(kit: Kit, id: int32, down: boolean): void {
	const press: PressFade = pressFade(kit, id);
	const span: float32 = 1.0 - PRESSED_FADE;
	press.level = down
		? Math.max(PRESSED_FADE, press.level - span * kit.frameSeconds / FADE_IN_SECONDS)
		: Math.min(1.0, press.level + span * kit.frameSeconds / FADE_OUT_SECONDS);
	kit.fade = press.level;
}

export function plainLook(kit: Kit): void {
	kit.fade = 1.0;
}

export function say(ui: Ui, kit: Kit, id: int32, line: string, x: float32, y: float32, width: float32, size: float32,
	color: Color, align: float32): void {
	text(ui, id, line, x, y, width, size, faded(color, kit.fade), align);
	for (let index: int32 = 0; index < ui.labelIds.length; index += 1) {
		if (ui.labelIds[index] === id) {
			ui.labelNodes[index].setFont(kit.textures.font);
		}
	}
}
