# RENDERER & ANDROID SURFACE BRIEF — Hibernal

> Scope of this document: how the pet is rendered and where it appears on the device. This is a companion to `BRIEF.md` (game design, economy, onchain program). Read that first for context; this one is self-contained for the rendering/Android work.
>
> Target device: **Solana Seeker** — MediaTek Dimensity 7300, 8GB RAM, Android 15, 1080×2400, 4500mAh.

---

## 1. Goal

The pet must be **visible and alive outside the app**. The app is where you manage it; the home screen and lock screen are where you *live with* it.

Art direction: **t3ssel8r-style** — simple low-poly 3D geometry, real lighting, rendered at low resolution and upscaled with nearest-neighbour so the output reads as pixel art. Not 2D sprites. Not high-poly 3D.

Non-goal: photorealism, high tri counts, 3D character animation rigs beyond simple idle/walk cycles.

---

## 2. Platform reality (researched, do not re-litigate)

### 2.1 What Solana Mobile gives us
- **No privileged OS layer for third-party devs.** Solana Mobile Stack = wallet adapter + Seed Vault + dApp Store. Seed Vault is a system service for *signing only*, not an OS extension point.
- **dApp Store Publisher Policy is permissive.** It restricts illegal/harmful/deceptive content and explicitly does not restrict crypto functionality. It contains no clause restricting overlay or sensitive permissions the way Google Play does.

### 2.2 What Android 15 gives us

**Tier 0 — no dangerous permissions required (build these):**

| Surface | API | Notes |
|---|---|---|
| **Live Wallpaper** | `WallpaperService` | **Primary surface.** Full-screen, appears on home **and** lock screen. Receives `onTouchEvent`. Auto-pauses via `onVisibilityChanged` → near-zero battery when not visible. |
| **App Widget** | Jetpack Glance | Hearts, unclaimed harvest, Winter countdown, one-tap Claim. Updated via WorkManager. |
| **Ongoing notification** | Foreground service + custom RemoteViews | Closest thing Android has to a taskbar. Sprite + hearts + feed action. |
| **Bubble** | Bubbles API (via notification) | Floating pet over other apps **without** `SYSTEM_ALERT_WINDOW`. Optional. |
| **Quick Settings tile** | `TileService` | Cheap. ~30 min of work. |

**Tier 1 — requires user to grant in Settings (defer to post-hackathon):**
- `SYSTEM_ALERT_WINDOW` — Shimeji-style pet wandering over all apps. Caveats: Android 15 only lets an app with SAW start a foreground service while an overlay is visible; Android 15 "Restricted settings" may block sensitive permissions for apps from unrecognised installers — **untested whether the dApp Store counts as a recognised installer. Test on device before relying on this.**
- Accessibility Service — would let the pet react to which app you're using. **Do not build.** Highest-trust-cost permission on Android; reads as spyware; heavily gated.

**Not available:**
- **Lock screen widgets** — returned on Pixel with Android 16 QPR1/QPR2, then AOSP. Seeker ships Android 15. Assume unavailable; verify on device.
- **Always-On Display** — no third-party API. No path.

### 2.3 Conclusion
**Live Wallpaper is the primary surface.** It is the only Tier-0 API that puts a live, lit, interactive 3D pet on both the home screen and the lock screen with no permission prompt and no review risk. Widget + ongoing notification are the supporting surfaces.

---

## 3. Rendering approach

### 3.1 Why this style is cheap, not expensive
Render to an offscreen FBO at **320×711** (1/3.375 of 1080×2400), then blit to the full-size surface with `GL_NEAREST`. That is **~8.7% of the fragment work** of native resolution. A few-hundred-triangle scene at that resolution runs comfortably at 30fps on a Dimensity 7300 with headroom to spare.

Because the output is pixelated, the meshes do not need to be good: 200–500 tris, flat or vertex colours, no UV unwrap, no normal maps. Art budget shifts from modelling to shader work.

### 3.2 Pipeline
```
[geometry pass]  → FBO 320×711, MRT or separate passes:
                     - colour  (RGBA8)
                     - depth   (DEPTH24)
                     - normal  (RGB10_A2 or RGBA8)
[post pass 1]    → edge detection on depth + normal → outline mask
[post pass 2]    → palette quantization (LUT texture) + outline composite
[blit]           → full-res surface, GL_NEAREST, with subpixel offset applied
```

### 3.3 The four techniques that define the style
These are the non-obvious parts. Get them right or the whole look fails.

1. **Pixel-perfect camera + subpixel smoothing.** *The single most important item.* If the camera moves by less than one low-res pixel, the image shimmers badly. Fix: snap the camera to the low-res pixel grid, then apply the sub-pixel remainder as an offset in the final blit. Without this, nothing else matters.
2. **UV snapping** on any textured surface, same reason.
3. **Outlines via edge detection on depth + normal buffers** — not inverted-hull. Cheaper and crisper at low resolution.
4. **Palette quantization** as a post pass, forcing colours to a fixed LUT. This is what makes everything read as one coherent world — and it doubles as a *game mechanic*: swap palette for day/night, for Winter, for a Fading (aged) pet.

Do **not** add PS1-style vertex snapping/wobble — that is a different aesthetic.

### 3.4 Engine decision: **hand-written OpenGL ES 3.0, no game engine**

Rationale:
- `WallpaperService.Engine` hands you a raw `Surface`. Unity and Godot both require hacks to render into it — that is not their supported path, and time spent there is time not spent on shaders.
- `GLSurfaceView` is unusable here: it is bound to the View hierarchy, which a wallpaper does not have. EGL must be managed manually regardless of engine choice.
- The scene is tiny (hundreds of tris, one directional light, three post passes). Raw GLES is ~800–1200 lines total.
- One renderer serves **both** the live wallpaper and the in-app view — same GL code, different `Surface`. An engine would mean two visual codebases.
- Strong answer for the hackathon's **Technical Depth** criterion, which is judged from GitHub commit history.

**Rejected: WebGPU (Dawn / wgpu-native).** It would require bundling tens of MB into the APK, cross-compiling for arm64-v8a, bridging `ANativeWindow_fromSurface()` via JNI, and mapping wallpaper lifecycle onto WebGPU surface lifecycle with no prior art. It buys nothing for this scene — GLES and EGL are already on the device with zero bundle cost.

**Language: Kotlin + `android.opengl.GLES30`.** Do not drop to the NDK — this workload is not CPU-bound. The "low level" that matters here is the GL pipeline, not the language.

**MetaScript variant (optional, see §7):** the project owner also maintains MetaScript, a TypeScript superset compiling to native C. Since GL/EGL are C APIs, targeting them from MetaScript is a natural fit and doubles as a real on-device demo for that project. Treat this as an *optional second track*, never as the critical path.

---

## 4. Implementation spec

### 4.1 Live wallpaper skeleton
```
HibernalWallpaperService : WallpaperService
  └─ HibernalEngine : WallpaperService.Engine
       - onCreate(SurfaceHolder)
       - onSurfaceCreated / onSurfaceChanged / onSurfaceDestroyed
       - onVisibilityChanged(visible) → start/stop render loop
       - onOffsetsChanged(xOffset, ...) → parallax as user swipes pages
       - onTouchEvent(MotionEvent) → poke the pet
       - isPreview() → reduced-fidelity path (see below)
```

### 4.2 EGL management — the hard part
This, not the rendering, is where this work actually gets difficult.

- Create context manually: `eglGetDisplay` → `eglInitialize` → `eglChooseConfig` → `eglCreateContext` → `eglCreateWindowSurface(holder.surface)` → `eglMakeCurrent` → render → `eglSwapBuffers`.
- Run on a **dedicated render thread**, driven by `Choreographer` while visible, fully stopped when not.
- **Handle context loss.** Wallpaper engines are created and destroyed far more often than expected: launcher switch, rotation, entering the wallpaper picker, system memory pressure. All GL resources must be reconstructible from scratch.
- **Preview mode runs concurrently with the live instance.** `isPreview()` is true in the picker, and both engines are alive at once — two GL contexts on a mid-range device. In preview: reduce to 15fps and a simplified scene.
- **Hold no game state in the engine.** The engine is a pure renderer. All pet state comes from a local cache (Room/DataStore) populated from chain. Engine destruction must never lose anything.

### 4.3 Battery & thermal
- Render only when visible. Target **30fps**, not 60.
- When the screen is on but nothing is changing (pet idle, no animation in progress), drop to **~10fps** or render on demand.
- Never allocate in the render loop. Pre-allocate all buffers, matrices, and scratch arrays.
- Budget check on device: wallpaper visible and animating should stay under ~2% battery/hour. Measure with Battery Historian before shipping.

### 4.4 Assets
- Format: **glTF 2.0**, position + normal + vertex colour only. Write a minimal loader (~200 lines) for exactly the subset we export — do not pull in a general-purpose glTF library.
- Budget: **≤500 tris per pet**, ≤200 for props/environment.
- No textures on the pet. Colour comes from vertex colour + palette LUT.
- Variants (rarity, Worker/Fighter/Survivor silhouette, age, scars) come from a **parametric Blender generator script**, not from hand-modelled one-offs. One script taking `(body_type, build, age, rarity, palette)` and exporting glTF.

### 4.5 What the wallpaper shows
- The pet in its burrow, idle animation, lit by a single directional light.
- Time of day drives light direction and palette.
- Hearts as a small discreet indicator.
- Unclaimed harvest visualised as physical objects accumulating in the scene (this is the passive "you have something to collect" signal).
- Winter changes the palette and the environment.
- A Fading pet (past day 80) desaturates.
- Tap the pet → reaction animation. Tap-and-hold → deep-link into the app.

---

## 5. Supporting surfaces

**App Widget (Glance):** hearts, unclaimed harvest, epochs until Winter, one-tap Claim that deep-links into the signing flow. Refresh via WorkManager, not a polling service.

**Ongoing notification:** optional, user-toggleable. Custom RemoteViews with the pet sprite (a pre-rendered still, not live GL), hearts, and a feed action. Note the Android 15 constraint if `SYSTEM_ALERT_WINDOW` is ever added: foreground service start is restricted while no overlay is visible.

**Quick Settings tile:** hearts at a glance, tap to open. Low cost, do it if time allows.

---

## 6. Day-1 spike (do this before anything else)

**Timebox: 4–6 hours. This de-risks the entire renderer track.**

Build a `WallpaperService` that:
1. Manually creates an EGL context on the wallpaper's `Surface`
2. Renders a rotating cube into an FBO at 320×711
3. Blits it to full screen with `GL_NEAREST`
4. Survives: lock/unlock, launcher switch, rotation, entering and leaving the wallpaper picker (with preview running concurrently)
5. Stops the render loop cleanly on `onVisibilityChanged(false)`

**If this works in one day → the approach is sound and the rest is execution.**
**If it takes more than one day → stop and reassess before going further.**

---

## 7. Optional second track: MetaScript

Only after §6 passes with a working Kotlin baseline.

- Target **GLES/EGL via C FFI**, not WebGPU.
- Success criteria for the spike: MetaScript output can call `eglCreateWindowSurface`, `glDrawArrays`, and receive an `ANativeWindow*` through JNI, compiled for arm64-v8a.
- **Hard rule: never let both risks stack.** Writing a first GL renderer inside a WallpaperService *and* dogfooding a compiler on a new target simultaneously means a failure gives no signal about which one broke. Kotlin baseline first, always shippable.
- If it does work, it is a strong independent demo: "renderer written in MetaScript, compiled to native C, running in an Android live wallpaper."

---

## 8. Schedule impact

This track costs roughly **3–4 days** more than 2D sprites. Take it from:
- On-device LLM narration — **cut entirely** (template-based morning digest ships instead)
- Skill tree — reduce from ~36 nodes to **~24** (still demonstrates adjacency + keystones)

Revised plan (see `BRIEF.md` §8 for the full 14 days):

| Day | Renderer track |
|---|---|
| 1 | §6 spike. Kotlin + GLES30 baseline in WallpaperService. |
| 2–3 | Pipeline: FBO, geometry pass, depth/normal buffers, blit. Pixel-perfect camera + subpixel offset. |
| 4 | Outline pass + palette quantization. Blender generator script in parallel. |
| 5 | glTF loader, first pet on screen, idle animation, touch. |
| 6 | Lifecycle hardening: preview mode, context loss, visibility, battery measurement. |
| 7 | Widget + notification. State cache wiring. |
| later | Variants, day/night, Winter palette, harvest objects in scene. |

---

## 9. Definition of done
- [ ] Live wallpaper installs, renders, and survives lock/unlock/rotate/launcher-switch/preview without a black screen
- [ ] < ~2% battery/hour while visible and animating; 0 measurable drain while not visible (verified in Battery Historian)
- [ ] Runs at 30fps on Seeker hardware (not just emulator)
- [ ] Same renderer code path used in-app and in the wallpaper
- [ ] Pet appears on the lock screen (verify on device — this is the demo money shot)
- [ ] Parametric generator produces ≥10 visually distinct pets at ≤500 tris, same palette, same world
- [ ] Widget shows live hearts/harvest and claims in one tap
- [ ] Demo video opens with: unlock the phone, pet is already there, no app opened

---

## 10. Open questions
1. Does the Seeker's launcher/lock screen render live wallpapers on the lock screen, or only a static frame? **Verify on device day 1** — this is load-bearing for the pitch.
2. Has Seeker received Android 16? If so, lock screen widgets become available and change §2.2.
3. Does the dApp Store count as a recognised installer for Android 15 Restricted settings? Determines whether `SYSTEM_ALERT_WINDOW` is viable later.
4. `GL_RGB10_A2` vs `GL_RGBA8` for the normal buffer on Mali/Dimensity — measure.
