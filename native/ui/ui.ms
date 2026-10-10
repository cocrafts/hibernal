// Void UI — a small immediate-mode layer over void2d, for touch HUDs.
//
// Every frame the app calls beginUi, then one function per widget, then endUi. The same call
// that draws a widget also answers whether it was pressed, so where a thing is drawn and where
// it can be touched never drift apart (the Dear ImGui idea). Hit-testing is ours: the OS only
// reports pointer positions on the surface (src/input/pointer.ms).
//
// Layout is in design units: a fixed 360×800 portrait canvas, letterboxed into the surface.
// Pointer pixels are mapped back through the same letterbox before any hit-test.
//
// void2d is retained (a Node2D tree), so the immediate API sits on top of it: each box is a
// rect node reused in call order and each text a label node kept by widget id, both updated in
// place (void2d repaints only what changed) and hidden in a frame that does not draw them.
//
// Only the first finger down is tracked. Ids are the caller's: one id per widget, never 0.

import { add, setScaleMode, prepare } from "@metascript/void/src/void2d/scene";
import { drawTarget } from "@metascript/void/src/void2d/draw";
import { RenderTarget } from "@metascript/void/src/gpu/target";
import { hudTarget, sizeHudTarget, drawHudPost } from "../hud/hudPost";
import {
	Scene2D,
	NodeRef,
	group,
	rect,
	label,
	addChild,
	setText,
	setTextStyle,
	textStyle,
	setColor,
	setPosition,
	setSize,
	setVisible,
	setBoxStyle,
} from "@metascript/void/src/void2d/node";
import { BoxStyle, uniformRadii, uniformBorders } from "@metascript/void/src/void2d/boxStyle";
import { Color, rgba, ScaleMode } from "@metascript/void/src/void2d/types";
import { Align } from "@metascript/void/src/void2d/textLayout";
import { DEFAULT_FONT, fontFace } from "@metascript/void/src/void2d/font";
import { fbWidth, fbHeight, dpiScale } from "@metascript/void/src/sokol/gpu";
import { PointerPhase, takePointerEvents } from "../input/pointer";

export const DESIGN_W: float32 = 360.0;
export const DESIGN_H: float32 = 800.0;
const NO_POINTER: int32 = -1 as int32;
const NO_WIDGET: int32 = 0 as int32;

export struct BoxShape {
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	radius: float32;
	color: Color;
	style: BoxStyle | null;
}

// nodes[0, shown) were visible at the last endUi; shapes[k] is what nodes[k] holds.
export interface BoxLayer {
	group: NodeRef;
	nodes: NodeRef[];
	shapes: BoxShape[];
	used: int32;
	shown: int32;
}

export interface Ui {
	sc: Scene2D;
	// The HUD's own pixels, which hudPost.ms lays over the scene.
	target: RenderTarget;
	boxes: BoxLayer;
	texts: NodeRef;
	labelIds: int32[];
	labelNodes: NodeRef[];
	labelUsed: boolean[];
	labelShown: boolean[];
	pointerId: int32;
	// The tracked pointer, in design units. `pressed` / `released` hold for the one frame in
	// which the pointer went down / up, with where it happened; both can hold in the same
	// frame when a tap was shorter than a frame.
	down: boolean;
	x: float32;
	y: float32;
	pressed: boolean;
	pressX: float32;
	pressY: float32;
	released: boolean;
	releaseX: float32;
	releaseY: float32;
	// The widget that took the current press. A press belongs to the widget it started on,
	// so sliding onto another widget and lifting there does not press that one.
	activeId: int32;
	// Overlay layer (sheets, modals): drawn above everything else, and while `blockBase` is
	// set only overlay widgets take touches. The kit adds its own layers in the same order.
	boxesTop: BoxLayer;
	textsTop: NodeRef;
	overlay: boolean;
	blockBase: boolean;
	// A second finger, for pinch: tracked while the first one is down. It never presses a
	// widget; gestures read it (down2, x2, y2).
	secondId: int32;
	down2: boolean;
	// Base-layer widgets only take presses that start between clipTop and clipBottom (a
	// scrolling area sets them; overlay widgets ignore them).
	clipTop: float32;
	clipBottom: float32;
	x2: float32;
	y2: float32;
}

export function createUi(clearColor: Color): Ui {
	// Load the default font now: on Android and iOS only init runs inside the asset root, so
	// a font first touched by a frame's text() would not be found.
	const _face: int32 = fontFace(DEFAULT_FONT);
	const sc: Scene2D = Scene2D.create(clearColor);
	sc.setScaleMode(ScaleMode.LetterBox, DESIGN_W, DESIGN_H);
	const boxes: BoxLayer = { group: sc.group(), nodes: [], shapes: [], used: 0, shown: 0 };
	const texts: NodeRef = sc.group();
	const boxesTop: BoxLayer = { group: sc.group(), nodes: [], shapes: [], used: 0, shown: 0 };
	const textsTop: NodeRef = sc.group();
	sc.add(boxes.group);
	sc.add(texts);
	sc.add(boxesTop.group);
	sc.add(textsTop);
	return {
		sc: sc, target: hudTarget(), boxes: boxes, texts: texts, labelIds: [], labelNodes: [], labelUsed: [], labelShown: [],
		pointerId: NO_POINTER, down: false, x: 0.0, y: 0.0,
		pressed: false, pressX: 0.0, pressY: 0.0, released: false, releaseX: 0.0, releaseY: 0.0,
		activeId: NO_WIDGET,
		boxesTop: boxesTop, textsTop: textsTop, overlay: false, blockBase: false,
		secondId: NO_POINTER, down2: false, x2: 0.0, y2: 0.0, clipTop: 0.0, clipBottom: DESIGN_H,
	};
}

// The letterbox of sceneViewMatrix (ScaleMode.LetterBox), inverted: surface pixels → design.
function designScale(): float32 {
	const wf: float32 = (fbWidth() as float32) / dpiScale();
	const hf: float32 = (fbHeight() as float32) / dpiScale();
	return wf / DESIGN_W < hf / DESIGN_H ? wf / DESIGN_W : hf / DESIGN_H;
}

export function toDesignX(px: float32): float32 {
	const r: float32 = designScale();
	const wf: float32 = (fbWidth() as float32) / dpiScale();
	const offset: float32 = (wf - DESIGN_W * r) * 0.5;
	return (px / dpiScale() - offset) / r;
}

export function toDesignY(py: float32): float32 {
	const r: float32 = designScale();
	const hf: float32 = (fbHeight() as float32) / dpiScale();
	const offset: float32 = (hf - DESIGN_H * r) * 0.5;
	return (py / dpiScale() - offset) / r;
}

// The top of the walking Pet in design units, and the scene's pixel, so what the HUD draws over
// the Pet can sit on the scene's pixel grid.
export struct PetHead {
	x: float32;
	y: float32;
	texel: float32;
}

export enum PetHeadHidden {
	NotDrawn,
}

// Design units → surface pixels: where a native overlay (a Kotlin EditText over a sheet) has
// to sit, and how a scripted test places its touches.
export function designToSurfaceX(x: float32): float32 {
	const r: float32 = designScale();
	const wf: float32 = (fbWidth() as float32) / dpiScale();
	const offset: float32 = (wf - DESIGN_W * r) * 0.5;
	return (x * r + offset) * dpiScale();
}

export function designToSurfaceY(y: float32): float32 {
	const r: float32 = designScale();
	const hf: float32 = (fbHeight() as float32) / dpiScale();
	const offset: float32 = (hf - DESIGN_H * r) * 0.5;
	return (y * r + offset) * dpiScale();
}

export function beginUi(ui: Ui): void {
	ui.pressed = false;
	ui.released = false;
	for (const e of takePointerEvents()) {
		const ex: float32 = toDesignX(e.x);
		const ey: float32 = toDesignY(e.y);
		match (e.phase) {
			PointerPhase.Down => {
				if (ui.pointerId === NO_POINTER) {
					ui.pointerId = e.id;
					ui.down = true;
					ui.pressed = true;
					ui.pressX = ex;
					ui.pressY = ey;
					ui.x = ex;
					ui.y = ey;
				} else if (ui.secondId === NO_POINTER && e.id !== ui.pointerId) {
					ui.secondId = e.id;
					ui.down2 = true;
					ui.x2 = ex;
					ui.y2 = ey;
				}
			},
			PointerPhase.Move => {
				if (e.id === ui.pointerId) {
					ui.x = ex;
					ui.y = ey;
				} else if (e.id === ui.secondId) {
					ui.x2 = ex;
					ui.y2 = ey;
				}
			},
			PointerPhase.Up => {
				if (e.id === ui.pointerId) {
					ui.pointerId = NO_POINTER;
					ui.down = false;
					ui.released = true;
					ui.releaseX = ex;
					ui.releaseY = ey;
					ui.x = ex;
					ui.y = ey;
				} else if (e.id === ui.secondId) {
					ui.secondId = NO_POINTER;
					ui.down2 = false;
				}
			},
			PointerPhase.Cancel => {
				if (e.id === ui.pointerId) {
					ui.pointerId = NO_POINTER;
					ui.down = false;
					ui.activeId = NO_WIDGET;
				}
				if (e.id === ui.secondId) {
					ui.secondId = NO_POINTER;
					ui.down2 = false;
				}
			},
		};
	}
	ui.boxes.used = 0;
	ui.boxesTop.used = 0;
	ui.overlay = false;
	ui.clipTop = 0.0;
	ui.clipBottom = DESIGN_H;
	for (let i: int32 = 0; i < ui.labelUsed.length; i += 1) { ui.labelUsed[i] = false; }
}

const TRANSPARENT: Color = rgba(0.0, 0.0, 0.0, 0.0);
let prepared: Ui[] = [];

// Paints the frame into the HUD's target with no pass open; drawUi lays it over the screen pass
// the caller opens.
export function endUi(ui: Ui): void {
	// A press released over nothing that claimed it ends here.
	if (ui.released) { ui.activeId = NO_WIDGET; }
	for (let i: int32 = 0; i < ui.labelNodes.length; i += 1) {
		if (ui.labelUsed[i] != ui.labelShown[i]) {
			ui.labelNodes[i].setVisible(ui.labelUsed[i]);
			ui.labelShown[i] = ui.labelUsed[i];
		}
	}
	hideUnused(ui.boxes);
	hideUnused(ui.boxesTop);
	const dpi: float32 = dpiScale();
	ui.sc.prepare((fbWidth() as float32) / dpi, (fbHeight() as float32) / dpi, dpi);
	sizeHudTarget(ui.target);
	ui.sc.context.drawTarget(ui.target, TRANSPARENT);
	prepared.push(ui);
}

export function drawUi(): void {
	for (const ui of prepared) { drawHudPost(ui.target); }
	prepared.length = 0;
}

function alignOf(align: float32): Align {
	if (align == 0.0) { return Align.Left; }
	if (align == 0.5) { return Align.Center; }
	if (align == 1.0) { return Align.Right; }
	console.log("ui: text align " + align.toString() + " is not 0, 0.5 or 1");
	unreachable;
}

function inside(px: float32, py: float32, x: float32, y: float32, w: float32, h: float32): boolean {
	return px >= x && px < x + w && py >= y && py < y + h;
}

// Everything drawn between beginOverlay and endOverlay goes on the overlay layer.
export function beginOverlay(ui: Ui): void { ui.overlay = true; }
export function endOverlay(ui: Ui): void { ui.overlay = false; }

export function box(ui: Ui, x: float32, y: float32, w: float32, h: float32,
	radius: float32, color: Color, style: BoxStyle | null = null): void {
	placeBox(ui.sc, ui.overlay ? ui.boxesTop : ui.boxes, x, y, w, h, radius, color, style);
}

function placeBox(sc: Scene2D, layer: BoxLayer, x: float32, y: float32, w: float32, h: float32,
	radius: float32, color: Color, style: BoxStyle | null = null): void {
	const k: int32 = layer.used;
	const shape: BoxShape = {
		x: x, y: y, w: w, h: h,
		radius: Math.max(0.0, Math.min(radius, Math.min(w, h) * 0.5)) as float32,
		color: color, style: style,
	};
	if (k == (layer.nodes.length as int32)) {
		const created: NodeRef = sc.rect(w, h, color);
		layer.group.addChild(created);
		layer.nodes.push(created);
		layer.shapes.push({ x: 0.0, y: 0.0, w: w, h: h, radius: 0.0, color: color, style: null });
	}
	const n: NodeRef = layer.nodes[k];
	const was: BoxShape = layer.shapes[k];
	if (was != shape) {
		if (was.radius != shape.radius || was.style != shape.style) {
			n.setBoxStyle(style == null
				? BoxStyle.create(uniformRadii(shape.radius), uniformBorders(0.0), color)
				: style);
		}
		n.setPosition(x, y);
		n.setSize(w, h);
		n.setColor(color);
		layer.shapes[k] = shape;
	}
	if (k >= layer.shown) { n.setVisible(true); }
	layer.used = k + 1;
}

function hideUnused(layer: BoxLayer): void {
	for (let i: int32 = layer.used; i < layer.shown; i += 1) {
		layer.nodes[i].setVisible(false);
	}
	layer.shown = layer.used;
}

// `align` places the text within `w`: 0 left, 0.5 centred, 1 right.
export function text(ui: Ui, id: int32, s: string, x: float32, y: float32, w: float32, size: float32, color: Color, align: float32): void {
	let at: int32 = -1 as int32;
	for (let i: int32 = 0; i < ui.labelIds.length; i += 1) {
		if (ui.labelIds[i] === id) { at = i; }
	}
	if (at < 0) {
		const n: NodeRef = ui.sc.label(s, size, color);
		if (ui.overlay) { ui.textsTop.addChild(n); } else { ui.texts.addChild(n); }
		ui.labelIds.push(id);
		ui.labelNodes.push(n);
		ui.labelUsed.push(true);
		ui.labelShown.push(true);
		at = (ui.labelNodes.length - 1) as int32;
	}
	const n: NodeRef = ui.labelNodes[at];
	n.setText(s);
	n.setTextStyle({ ...n.textStyle(), size: size, align: alignOf(align), maxWidth: w });
	n.setColor(color);
	n.setPosition(x, y);
	ui.labelUsed[at] = true;
}

// Held: the widget's own press, with the pointer still over it.
export function held(ui: Ui, id: int32, x: float32, y: float32, w: float32, h: float32): boolean {
	if (ui.blockBase && !ui.overlay) { return false; }
	return ui.activeId === id && ui.down && inside(ui.x, ui.y, x, y, w, h);
}

// Claims a press that starts inside the rectangle; true in the frame the press is released
// inside it again. Draws nothing: button() and custom widgets draw on top of it.
const DRAGGED: int32 = -2 as int32;

// The press became a drag (a scroll): no widget takes its release.
export function cancelPress(ui: Ui): void { ui.activeId = DRAGGED; }

export function pressable(ui: Ui, id: int32, x: float32, y: float32, w: float32, h: float32): boolean {
	if (ui.blockBase && !ui.overlay) { return false; }
	const clipped: boolean = !ui.overlay && (ui.pressY < ui.clipTop || ui.pressY >= ui.clipBottom);
	if (ui.pressed && !clipped && inside(ui.pressX, ui.pressY, x, y, w, h)) { ui.activeId = id; }
	if (ui.released && ui.activeId === id) {
		ui.activeId = NO_WIDGET;
		return inside(ui.releaseX, ui.releaseY, x, y, w, h);
	}
	return false;
}

export function button(ui: Ui, id: int32, x: float32, y: float32, w: float32, h: float32, caption: string, enabled: boolean): boolean {
	const clicked: boolean = pressable(ui, id, x, y, w, h) && enabled;
	let fill: Color = rgba(0.26, 0.29, 0.36, 1.0);
	if (!enabled) { fill = rgba(0.18, 0.19, 0.22, 1.0); }
	else if (held(ui, id, x, y, w, h)) { fill = rgba(0.42, 0.47, 0.58, 1.0); }
	placeBox(ui.sc, ui.boxes, x, y, w, h, 12.0, fill);
	const size: float32 = 18.0;
	let ink: Color = rgba(0.95, 0.96, 1.0, 1.0);
	if (!enabled) { ink = rgba(0.55, 0.57, 0.62, 1.0); }
	text(ui, id, caption, x, y + (h - size * 1.25) * 0.5, w, size, ink, 0.5);
	return clicked;
}
