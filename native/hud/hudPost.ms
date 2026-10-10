// The HUD's last pass: the HUD drawn into a target at framebuffer size (ui.ms endUi, before the
// screen pass), then averaged over HUD_PIXEL-square cells and graded towards the campfire scene
// by hudPost.glsl while it is laid over the scene (drawHudPost, inside the screen pass).

@include("./hudPost.h");
@compile("./hudPost.c");

import {
	VertexLayout,
	doorLayout,
	applyPipeline,
	applyBindings,
	applyUniforms,
	draw,
} from "@metascript/void/src/void3d/gpu3d";
import {
	GPU3D_BINDING_VERTEX_BUFFER,
	GPU3D_BINDING_VIEW,
	GPU3D_BINDING_SAMPLER,
	GPU3D_BINDING_LENGTH,
} from "../../vendor/void/src/void3d/gpu3d.h";
import { makeScreenTriangle, screenState } from "@metascript/void/src/void3d/screenFx";
import { PipelineCache, empty, pipelineFor } from "@metascript/void/src/gpu/pipeline";
import { RenderState, Blend, FilterMode, Wrap, withBlend } from "@metascript/void/src/gpu/state";
import {
	RenderTarget,
	Sampler,
	SWAPCHAIN_LAYOUT,
	allocate,
	unallocated,
	resize,
	asTexture,
	create,
	asHandle,
} from "@metascript/void/src/gpu/target";
import { PixelFormat, contextGeneration } from "@metascript/void/src/gpu/door";
import { fbWidth, fbHeight } from "@metascript/void/src/sokol/gpu";
import { LowResView } from "@metascript/void/src/void3d/blit";

extern function hudPostRegister(fullscreenLayout: int32): int32;

// Measured on the Seeker (2026-10-05) against the campfire scene: luminance 67-72 against 51,
// saturation 184-199 against 125. A 5 pixel cell, the scene's own, left the HUD's text unreadable.
export const HUD_PIXEL: float32 = 0.0;
export const HUD_BRIGHTNESS: float32 = 0.85;
export const HUD_SATURATION: float32 = 0.65;
export const HUD_TINT_SHARE: float32 = 0.0;
export const HUD_TINT_R: float32 = 1.0;
export const HUD_TINT_G: float32 = 1.0;
export const HUD_TINT_B: float32 = 1.0;
const HUD_POST_PARAMS: int32 = 12;
const PARAMS_SLOT: int32 = 0;
const NO_GENERATION: int32 = -1;

let program: int32 = hudPostRegister(doorLayout(VertexLayout.Fullscreen));
let cache: PipelineCache = PipelineCache.empty();
let triangle: uint32 = 0;
let sampler: Sampler = Sampler.create(FilterMode.Linear, Wrap.Clamp);
let madeIn: int32 = NO_GENERATION;
let params: Vec<float32> = [
	HUD_PIXEL, 0.0, 0.0, 0.0,
	HUD_BRIGHTNESS, HUD_SATURATION, HUD_TINT_SHARE, 0.0,
	HUD_TINT_R, HUD_TINT_G, HUD_TINT_B, 0.0,
];
let bindings: Vec<uint32> = new Array(GPU3D_BINDING_LENGTH);

// A new GPU context (the wallpaper and the app take turns) invalidates the triangle and sampler.
function adopt(): void {
	if (madeIn == contextGeneration()) { return; }
	triangle = makeScreenTriangle();
	sampler = Sampler.create(FilterMode.Linear, Wrap.Clamp);
	madeIn = contextGeneration();
}

export function hudTarget(): RenderTarget {
	return RenderTarget.unallocated(PixelFormat.Rgba8, true);
}

// The target at the framebuffer's size; resize reallocates it in a new GPU context.
export function sizeHudTarget(target: RenderTarget): void {
	target.resize(fbWidth(), fbHeight());
}

export function drawHudPost(target: RenderTarget): void {
	params[0] = HUD_PIXEL;
	params[1] = 0.0;
	params[2] = 0.0;
	params[3] = 0.0;
	drawComposite(target, target);
}

export function drawPixelPet(target: RenderTarget, coverage: RenderTarget, view: LowResView): void {
	params[0] = view.scale as float32;
	params[1] = 1.0;
	params[2] = view.offsetX;
	params[3] = view.offsetY;
	drawComposite(target, coverage);
}

function drawComposite(target: RenderTarget, coverage: RenderTarget): void {
	adopt();
	const state: RenderState = screenState().withBlend(Blend.One, Blend.OneMinusSourceAlpha);
	const pipeline: uint32 = pipelineFor(cache, program, doorLayout(VertexLayout.Fullscreen), false, state, SWAPCHAIN_LAYOUT);
	for (let i: int32 = 0; i < GPU3D_BINDING_LENGTH; i += 1) { bindings[i] = 0; }
	bindings[GPU3D_BINDING_VERTEX_BUFFER] = triangle;
	bindings[GPU3D_BINDING_VIEW] = target.asTexture();
	bindings[GPU3D_BINDING_VIEW + 1] = coverage.asTexture();
	bindings[GPU3D_BINDING_SAMPLER] = sampler.asHandle();
	applyPipeline(pipeline);
	applyBindings(bindings);
	applyUniforms(PARAMS_SLOT, params);
	draw(0, 3, 1);
}
