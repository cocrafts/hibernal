# void patches

The HUD and the campfire scene need two things void does not have. Until Neon is ready
(ROADMAP N1) they live here as patches, so the void repo stays untouched:
`scripts/fetchVoid.sh` clones void at `BASE`, applies these patches into `vendor/void/`
(git-ignored), runs void's `setup.sh` and `scripts/regen-shaders.sh`, clones yoga beside it,
and `build.ms` points `@metascript/void` there. `scripts/buildAndroid.sh` runs it on first use.

```
BASE      = a0bab020f1dadd4faec178b3bd15fe53278e6ea2   (metascriptlang/void main, 2026-10-05)
YOGA_BASE = ce52e2ecd8b148410ce4c08669fd74d483ab99df   (metascriptlang/yoga main, imported by void as ../yoga)
```

| Patch | What | Why it cannot live in hibernal |
|---|---|---|
| `0001-sokolPools.patch` | `sg_desc` buffer, image and view pools at 1024 on Android: the scene is 64 meshes, the kit makes a texture per frame size, seed and look | `sg_desc` is set inside void's `bridgeAndroid.c` |
| `0002-rampPrograms.patch` | `LitRamp` and `BillboardRamp` (`src/void3d/ramp3d.glsl`: colour by ramp lookup, fire falloff, the walker's shadow and grass push, wind, a fire shadow map) drawn by the pixel-art preset as themselves, and the fog glow in the preset's post pass (`setGlow`) | `Program` is a closed enum in `gpu3d.ms`: M20's door registers programs from outside, but `Material` and `ProgramMap` only name void3d's own (docs/VOID3D.md "M20 as built") |

The patches carry `.glsl` only. `fetchVoid.sh` regenerates every `.glsl.h` with void's pinned
sokol-shdc; on `BASE` that leaves all of void's committed headers byte-identical and changes
only `pixelArt3d.glsl.h` and the new `ramp3d.glsl.h`.

## What the move to void main changed

- **The 2D-over-3D hooks are gone.** The old 0001 skipped the 3D commit and kept its image for
  the HUD's pass. void main splits a frame instead: `campfireScene.ms` `frameLab` runs
  `prepareFrame`, the HUD's `Scene2D.prepare` (`ui.ms` `endUi`), then one screen pass with
  `drawToScreen` and the HUD's `drawScreen`, then one `commit`. Every path commits, because
  a view frame that returns without `commit()` aborts (void docs/EMBED.md).
- **`BillboardRamp` draws on the Particle layout**: `root` and `shape` per instance, the corner
  from the vertex index, through the patch's `GpuMesh.particles`. The 8-float records in
  `assets/campfire/*.f32` are what it reads, unchanged. The flame draws with it too, emissive.
- **The toon comparison switches are gone** (`LAB_RAMP 0`, `LAB_SHADER 0`). They drew the
  scene with void's toon programs plus the wind, flat walls and wrap the old 0002 added to
  them; on main those programs moved to `pixelArt3d.glsl` and light in linear space (VOID3D.md
  M26), so the additions were not carried.
- **The walker's vertex colours are no longer re-encoded**: void main's glTF loader writes
  `COLOR_0` gamma-encoded (VOID3D.md M26).
- **Not measured on main:** whether sokol's default pools would now hold the scene and the kit.
