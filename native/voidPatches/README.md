# void patches

The HUD and the campfire scene need local void changes. Until Neon is ready
(ROADMAP N1) they live here as patches, so the void repo stays untouched:
`scripts/fetchVoid.sh` clones void at `BASE`, applies these patches into `vendor/void/`
(git-ignored), runs void's `setup.sh` and `scripts/regen-shaders.sh`, clones yoga beside it,
and `build.ms` points `@metascript/void` there. `scripts/buildAndroid.sh` runs it on first use.

```
BASE      = 6c4daf28f034ca4506bb10e3922983112d085c4a   (metascriptlang/void main, 2026-10-05; 2D + 3D read-only Span migration)
YOGA_BASE = ce52e2ecd8b148410ce4c08669fd74d483ab99df   (metascriptlang/yoga main, imported by void as ../yoga)
```

This is the first upstream revision containing both Span migrations (`bbc2f84`, `6c4daf2`);
later render-target, scene-close and shader-header changes are deliberately excluded.
For a local fetch, run `VOID_URL=/Users/le/metascript/void bash scripts/fetchVoid.sh`.
Patch `0002` keeps upstream's unlit textured programs alongside the two ramp programs
(15 registered programs total); its `setGlow` input is a `Readonly<Span<float32>>`,
matching the upstream read-only upload APIs. Scene buffers that are filled or grown use
`let`; the sprite-ramp and walker-file readers use read-only spans. The current scene and
Pet assets are preserved separately from these compiler compatibility changes.

| Patch | What | Why it cannot live in hibernal |
|---|---|---|
| `0001-sokolPools.patch` | `sg_desc` buffer, image and view pools at 1024 on Android: the scene is 64 meshes, the kit makes a texture per frame size, seed and look | `sg_desc` is set inside void's `bridgeAndroid.c` |
| `0002-rampPrograms.patch` | `LitRamp` and `BillboardRamp` (`src/void3d/ramp3d.glsl`: ramp lighting, fire falloff, shadow and grass push), post glow (`setGlow`), and `PixelArtLit` body sheen/emissive lens | `Program` and pixel-art shaders are internal to void3d; the Pet's material behavior must travel with its scene/assets rather than reverting when the HUD APK is rebuilt |
| `0003-mutableContainers.patch` | Writable array bindings for containers mutated by 2D text/layout and 3D scene loaders; read-only text input spans | The upstream Span migration does not migrate these internal container owners; the installed compiler rejects mutations through `const` |
| `0004-pixelEdges.patch` | `pixelArt3d.glsl` and `pixelEdgeGeometry.ms` `writeEdgeGeometry`; measured in `docs/RENDERER-BRIEF.md` §20 | Scene/post shader contracts and their C uniform-size assertions live inside void3d; both must survive a clean vendor fetch |

The patches carry `.glsl` only. `fetchVoid.sh` regenerates every `.glsl.h` with void's pinned
sokol-shdc; on `BASE` that leaves all of void's committed headers byte-identical and changes
only `pixelArt3d.glsl.h` and the new `ramp3d.glsl.h`. Android builds also regenerate
`pixelArt3d.glsl.h` through `scripts/regenShaders.sh`, so shader edits cannot leave the
uniform ABI checked against a stale header.

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
