// The Android shell, seen from the core: whether this frame draws in the app or as the live
// wallpaper, where the system wallpaper is set, and the request to open its picker (hostLink.c).

@include("./hostLink.h");
@compile("./hostLink.c");

extern function hostInApp(): int32;
extern function hostWallpaperPlaces(): int32;
extern function hostRequestWallpaperPicker(): void;

export enum WallpaperPlace { Off, Home, Lock, HomeAndLock }

export function inApp(): boolean {
	return hostInApp() != 0;
}

// A match statement until ~/metascript/.inbox/compiler/2026-10-05-unreachable-arm-of-a-match-expression-fails-codegen.md
// lands: an `unreachable` arm of `return match` does not build.
export function wallpaperPlace(): WallpaperPlace {
	const places: int32 = hostWallpaperPlaces();
	match (places) {
		0 => { return WallpaperPlace.Off; },
		1 => { return WallpaperPlace.Home; },
		2 => { return WallpaperPlace.Lock; },
		3 => { return WallpaperPlace.HomeAndLock; },
		_ => {},
	};
	console.log("host: wallpaper places " + places.toString() + " is not two bits");
	unreachable;
}

export function requestWallpaperPicker(): void {
	hostRequestWallpaperPicker();
}
