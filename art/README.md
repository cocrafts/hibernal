# art

Offline sources for the 3D assets. Nothing here ships; `assets/` holds what the renderer loads. Spec: `docs/RENDERER-BRIEF.md` §4.4, roadmap task T1.

```
generator/   parametric Blender generator (Python): (bodyType, build, age, rarity, palette) → glTF
source/      hand-made .blend files: burrow, campfire, props, harvest objects
reference/   concept images to match (sceneDay.png, sceneNight.png)
palettes/    palette sources for the LUT (day, night, Winter, Fading)
```

Export rules:

- glTF 2.0, position + normal + vertex colour only. No textures, no UVs, no normal maps.
- ≤500 tris per pet, ≤200 per prop or environment piece.
- Animations (9, T1) baked as keyframes.
- Pet variants come from the generator, not from hand-modelled one-offs.
- Exports go to `assets/` and must be reproducible from the files here.
- File names in camelCase: `campfire.blend`, `petGenerator.py`.
