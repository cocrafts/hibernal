# void patches

The HUD and the campfire scene need two things void does not have. Until Neon is ready
(ROADMAP N1) they live here as patches, so the void repo stays untouched:
`scripts/fetchVoid.sh` clones void at `BASE`, applies these patches into `vendor/void/`
(git-ignored), runs void's `setup.sh`, clones yoga beside it, and `build.ms` points
`@metascript/void` there. `scripts/buildAndroid.sh` runs it on first use.

```
BASE      = ea4b6205c4840eb7d97a64e8efcbe5e93d218de6   (metascriptlang/void main, 2026-09-24)
YOGA_BASE = 10279de1bd3bc55728df4f30d11eae36a2e471dc   (metascriptlang/yoga main, imported by void as ../yoga)
```

| Patch | What | Why it cannot live in hibernal |
|---|---|---|
| `0001-sokolHooks.patch` | `sg_desc` buffer/image/view pools at 1024 (the scene is 64 meshes; the kit makes a texture per frame size, seed and look); `skipNextCommit` + `loadNextPass` so the HUD's 2D pass draws over the 3D frame instead of clearing it | `sg_desc` and the frame's pass actions are set inside void's bridge |
| `0002-rampPrograms.patch` | `LitRamp` and `BillboardRamp` programs (colour by ramp lookup, fire falloff, depth fog, the walker's shadow and grass push, a fire shadow map) and a glow post pass. Most of its size is the regenerated `shader3d.glsl.h` | `Program` is a closed enum in `gpu3d.ms`; a game cannot add a shader program from outside |

What used to be patched and now lives in hibernal: the touch UI (`native/ui/ui.ms`, the stand-in
for Neon) and the pointer queue the Android JNI pushes into (`native/input/`).

## Moving to void main (not done)

void main moved 584 commits past `BASE` (checked at `2be9cf5`, 2026-10-02): `void3d` lost
`pass.ms` and `target.ms` and has a new renderer, scene and split shaders; `void2d` changed
`node`, `render` and `textLayout`. What was found while trying:

- **Compiler.** void main needs msc 0.2.55 (`BitSet`, `distinct` types, `sink` parameters). The
  public releases stop at 0.2.50, and neither 0.2.50 nor a 0.2.54 source build can bootstrap
  compiler main (its std uses `sink`, its src imports `std/fs/watch`). The port waits on a 0.2.55
  binary or the bootstrap chain.
- **0001's 2D-over-3D hooks go away.** void main exposes the pieces: `prepareFrame` +
  `drawToScreen` on the pixel-art renderer and `prepare` + `drawScreen` on `Scene2D`, so the entry
  can open one screen pass, draw the 3D blit, then the HUD, then commit.
- **0001's pools probably stay**, unless sokol's defaults hold the kit; not measured on main.
- **0002 stays, or the look changes.** `Program` is still closed on main (`programMap.ms` swaps
  whole programs). Either void gains an extension point for game programs, or the campfire moves
  to void's own pixel-art preset (the `campfireScene.ms` example on main), which changes the look.
- **The HUD's calls into void2d change** (seen compiling against main): node constructors take an
  argument, `TextStyle.align` is an `Align` enum, a few `Scene2D` calls take more arguments.

Then `BASE` moves to void main, the patches shrink to what is left, and this folder goes when
nothing is.
