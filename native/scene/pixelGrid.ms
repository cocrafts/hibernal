import {
	LowResView, ViewPoint, lowResView, withRemainder, texelAt, framebufferAt,
} from "../../vendor/void/src/void3d/blit";

export function magnified(this view: LowResView, factor: int32): LowResView {
	if (factor <= 0) {
		console.log("pixel grid: magnification must be a positive integer");
		unreachable;
	}
	return view.withScale(view.scale * factor);
}

export function withScale(this view: LowResView, scale: int32): LowResView {
	if (scale <= 0) {
		console.log("pixel grid: scale must be positive");
		unreachable;
	}
	return {
		...view,
		width: (view.width * view.scale + scale - 1) / scale,
		height: (view.height * view.scale + scale - 1) / scale,
		scale: scale,
	};
}

export function snapAnchor(this view: LowResView, x: float32, y: float32): ViewPoint {
	const texel: ViewPoint = view.texelAt(x, y);
	return view.framebufferAt(
		(Math.floor(texel.x) as float32) + 0.5,
		(Math.floor(texel.y) as float32) + 0.5,
	);
}

test "magnification enlarges texels rather than increasing model detail" {
	const base: LowResView = {
		width: 242, height: 536, scale: 5, offsetX: 5.25, offsetY: 7.5,
	};
	for (const factor of [1, 2, 3]) {
		const zoomed = base.magnified(factor);
		assert zoomed.scale == base.scale * factor;
		assert zoomed.width * factor >= base.width;
		assert zoomed.height * factor >= base.height;
		assert zoomed.offsetX == base.offsetX;
		assert zoomed.offsetY == base.offsetY;
		for (let texel: int32 = 0; texel < 40; texel += 1) {
			const boundary = zoomed.framebufferAt(texel as float32, texel as float32);
			const parent = base.texelAt(boundary.x, boundary.y);
			assert Math.abs(parent.x - (texel * factor)) < 0.0001;
			assert Math.abs(parent.y - (texel * factor)) < 0.0001;
		}
	}
}

test "seven-pixel preview preserves coverage and world footprint" {
	const base: LowResView = {
		width: 242, height: 536, scale: 5, offsetX: 5.25, offsetY: 7.5,
	};
	const preview = base.withScale(7);
	assert preview.scale == 7;
	assert preview.width * 7 >= base.width * 5;
	assert preview.width * 7 < base.width * 5 + 7;
	assert preview.height * 7 >= base.height * 5;
	assert preview.height * 7 < base.height * 5 + 7;
	assert preview.offsetX == base.offsetX && preview.offsetY == base.offsetY;
	const worldPerTexel: float32 = 0.125;
	const previewWorldPerTexel = worldPerTexel * (preview.scale as float32) / (base.scale as float32);
	assert Math.abs((preview.scale as float32) / previewWorldPerTexel
		- (base.scale as float32) / worldPerTexel) < 0.0001;
}

test "anchor stays on shifted pixel grid for both framebuffer origins" {
	const made = lowResView(1200, 2670, 240, 1, 1);
	assert made.ok;
	const base: LowResView = made.value;
	const positions: float32[] = [-13.0, 0.0, 615.25, 1200.0];
	for (let step: int32 = 0; step < 20; step += 1) {
		const shift: float32 = (step as float32) / 20.0;
		for (const topLeft of [false, true]) {
			const view = base.withRemainder(shift, 1.0 - shift, topLeft);
			for (const x of positions) {
				const anchor = view.snapAnchor(x, 1223.4);
				const texel = view.texelAt(anchor.x, anchor.y);
				assert Math.abs(texel.x - (Math.floor(texel.x) + 0.5)) < 0.0001;
				assert Math.abs(texel.y - (Math.floor(texel.y) + 0.5)) < 0.0001;
				assert Math.abs(anchor.x - x) <= (view.scale as float32) * 0.5 + 0.0001;
			}
		}
	}
}
