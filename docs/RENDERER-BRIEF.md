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
| **Bubble** | Bubbles API (via notification) | Floating pet over other apps **without** `SYSTEM_ALERT_WINDOW`. |
| **Quick Settings tile** | `TileService` | Cheap. ~30 min of work. |

**Tier 1 — requires user to grant in Settings (launch scope, not built yet: debt):**
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

**Quick Settings tile:** hearts at a glance, tap to open. Low cost; launch scope.

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
| 8+ | Variants, day/night, Winter palette, harvest objects in scene (launch scope; debt until built). |

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

## 11. On-device integration measurement

The single-Home build with passive owner identity compiled 99 modules with the installed
compiler and the Void pin/patches documented in `native/voidPatches/README.md`.
The debug APK built and installed on Seeker without force-stopping the wallpaper.
The restored scene rendered at 60–61 fps in the sampled `VoidRender` log. The
skill ring opened/closed without leaving Home; the diary scrolled to older events
and back. The former menu target no longer navigates. The inline shop and system
wallpaper preview still opened and closed without changing the chosen wallpaper.

Real MWA connect/disconnect completed directly on Home. The user also confirmed
both actions on Seeker. The bridge is
`android/app/src/main/java/app/hibernal/WalletBridge.kt`; the app has no Settings or
other routed screens. Wallet authorization and the selected game owner are separate:
disconnect clears authorization but retains the read-only owner identity.
Game values and diary events remain stand-ins; no Claim or transaction was exercised.

The first wallet APK used a stale worktree and reverted the Pet/log baseline.
A HUD APK deploys the whole core and art, not just its UI: reconcile the current
scene, assets and shader changes before installing a side-worktree build.
All six restored campfire assets matched main and the packaged APK byte-for-byte.
The extracted device `assets/campfire/walker.glb` matched the current black Pet's
SHA256 `406047e2054450ebafb15ac96f3b8cf6639f03356e5dce0628400b4f905c8673`.

The build uses official MWA 2.2.0: 2.1.1's duplicate library namespace is rejected
by AGP 9.3. The corrected release requires compile SDK 37 and Kotlin 2.4.10;
the app's target/minimum SDK are unchanged. No namespace validation is disabled.

## 12. Passive owner and onboarding boundary

Seeker smoke: a real wallet selection committed the selected 32-byte public key.
Disconnect retained exactly those bytes. Package/process restart restored
`OWNER REMEMBERED` without a wallet request; a truncated one-byte cache instead
displayed `OWNER CACHE UNREADABLE. SELECT WALLET AGAIN.`. The original public key
was restored and the app restarted successfully. Native owner-store smoke also
verified disconnect retention, invalid-input failure and non-torn concurrent reads.

A remembered public key is a read-only selection, not proof that a Pet exists or
permission to sign. It must not drive a successful onboarding/Claim state by itself.
The checked host account codec and transaction client remain upstream prerequisites
(`~/metascript/.inbox/compiler/2026-09-29-std-solana-asks-from-hibernal.md`, rows 1/9);
the program port is blocked at
`~/metascript/.inbox/compiler/2026-10-06-inline-generic-try-unlowered-in-second-module.md`.
Do not decode current shared layouts against the old devnet fixture or add a second
handwritten decoder. The selected Seeker wallet had zero Token-2022 accounts at
confirmed devnet slot 508177187 in a read-only `getTokenAccountsByOwner` lookup;
test admission provisioning is required before a real devnet Claim.

## 13. Retained Seeker constraints

Earlier device records (2026-10-05 release build; not remeasured after the current
scene/MWA changes) reported Home 4.19 ms, shop 4.82 ms with the 3-px HUD shader,
and cold start 0.78 s. Do not use them as a current performance gate.

- The recorded Seeker `SET_WALLPAPER_COMPONENT` permission is
  `signature|privileged`; use the system picker for home/lock/both.
- Never use `adb shell am force-stop app.hibernal` for this workflow: the earlier
  run cleared the live wallpaper (`Wallpaper uninstalled, removing`).
  Package replacement with `adb install -r` preserved it in the current smoke.
- The wallpaper engine reported itself visible on app touches. Surface selection
  must continue preferring the in-app target; see `VoidRenderer.bindLatest`.
- The earlier `std/https` probe returned `getSlot` HTTP 200 in 986 ms on Seeker,
  using a native library plus C entry because Android console linking lacked
  `main`. Fetch blocks: future RPC work must stay off the render thread.
- MetaScript `console.log` was not visible in Android logcat in that record;
  do not mistake missing log lines for an unexecuted path. Use the actual surface.
- Silkscreen 6-px text was fuzzy after the HUD shader; the recorded crisp sizes
  were 8 and 16. Preserve the small inline text approach rather than new sub-pages.

## 14. First onboarding preview — 2026-10-07

This plain-background prototype was superseded by the supplied-art candidate in §15.

The person accepted distinct onboarding and campfire states, then requested a bare
preview; they will supply the design. Name-table and lineage display guards live in
`native/hud/petNames.ms`; the preview lives in `native/hud/onboarding.ms`.
No on-chain name field, existing-Pet discovery, Claim or game-ready transition is
implemented by this preview. Its selected name is session-only, not saved to chain.

Measured on dirty `wt/hud` HEAD `cc58294`, base tree
`9bdf70e27fb9829ba971d76d4c7c7f3e203647aa`, installed binary/support `8506eaf03`:
`msc test native/hud/petNames.ms` passed 15 files / 301 tests (3 local guards);
`bash scripts/buildAndroid.sh` printed `Built 95 module(s)` and produced APK SHA256
`b03aa2c306ad70290f260c92215bd03ab2da8c4de5cbde5226e485d1919a9203`.
The first test entry through the rendering widget could not resolve build.ms package
deps; pure name/picker guards were tested separately, rendering through the APK.

Installed with `adb install -r` on Seeker `SM02G40619100815` (1200×2670).
Actual taps showed Leo I → Nix I → Leo I → Luna I; disabled Create left the
onboarding screenshot pixel-identical and did not open a wallet. Home wallpaper
still displayed the current black Pet/campfire; returning to the app restored
onboarding without campfire. Remembered owner remained visible. No wallet signing
or transaction occurred. Evidence: `/tmp/hibernalOnboardingFinal.png`,
`/tmp/hibernalOnboardingPickerChecks.png`, `/tmp/hibernalOnboardingWallpaperRetained.png`.
This proves only the preview and surface split, not first-open discovery or creation;
wallpaper Pet and numbers remain stand-ins. Campfire assets matched current main;
vendor shader differences were additive unlit programs, alongside prior Readonly
migration. Full performance/battery and live-chain flows were not measured.

## 15. Supplied-art onboarding overlay candidate — 2026-10-07

The person clarified that onboarding should overlay the current Campfire environment,
without rendering a Pet. Supplied reference and transparent components are preserved
in `art/hud/onboardingMockup.png` and `art/hud/onboardingSheet.png`; reconstruction is
`python3 art/hud/cutOnboarding.py`. Source sheet SHA256:
`ecf5f82cb36ec270379d7023a79b3d8a94cefd17d57122d1f6ba4cdbcacda2d6`.
The sheet's hologram touches neighbouring frames and has maximum alpha 254, not 255;
cut validation preserves its translucency rather than forcing opacity. Six output
hashes matched across two runs; all 86 pre-existing HUD/Campfire assets were unchanged.
Current main's Campfire assets also matched before installation. The white Pet in the
reference is not used. No new Back navigation or decorative version number is wired.

Dirty HEAD/base tree and compiler are unchanged from §14. Name/picker guards passed
15 files / 301 tests; Android build printed `Built 95 module(s)`. Installed APK SHA256:
`56feb0f29484b8982d2e558050c24bf989fe53943fb1d174a79591a7de99e98c`.
First `adb install -r` succeeded while Seeker was asleep with keyguard `showing=true`.
The person subsequently unlocked; §16 owns the later surface/picker proof. No agent
PIN/biometric interaction, wallet signing, transaction, chain-layout change, commit
or land occurred.

## 16. Raw UI trial and overlay device check — 2026-10-07

The person requested disabling UI pixelation temporarily. `native/hud/hudPost.ms`
`HUD_PIXEL=0` selects the raw premultiplied copy branch in `hudPost.glsl`; restore 3
for the prior averaging/grading path. Campfire's shaders and source art were unchanged.
Raw trial built 95 modules on installed `8506eaf03`; APK SHA256
`fab85fadbce9cc796e13c23c9f6ccbb0b16cee1cdddd163ba2292491c29660e2`.
Installed/observed on unlocked Seeker: crisp supplied art, picker Nix I → Leo I →
Luna I, disabled Create retained MainActivity without opening the wallet, remembered
owner retained. Home wallpaper showed the existing Pet; returning to onboarding hid
it again. The user's pre-update Finn selection was restored. Evidence:
`/tmp/hibernalOnboardingRawUiFinal.png`, `/tmp/hibernalOverlayPickerChecks.png`,
`/tmp/hibernalOverlayWallpaperPet.png`. SDK authorization success was not repeated;
its request path was unchanged. This is not a pixel-exact benchmark: process/name,
fire clock and possible device tilt differed between captures, as well as the UI
copy/grading path. No full performance/battery or live-chain verdict.

## 17. Breathing model / centered wallet / Summon candidate — 2026-10-07

Later requests: put a breathing or turning 3D model on the hologram; omit first-life I;
center the whole wallet area; use dynamic `SUMMON <NAME>`. The existing black asset is
used only as a model preview, not a created Pet. Native pose/placement lives in
`campfireScene.ms` `setPetPreview`/`placePetPreview`; source positioning is owned by
`onboarding.ms`. No roaming/grass footprint effects in model preview. Wallpaper
retains the original roaming pose. Source assets/cuts remained byte-identical.

`msc test native/hud/petNames.ms` passed 15 files / 301 tests after the first-life change.
A headless probe `/tmp/hibernalPreviewRayProbe.ms` tested the existing camera ray →
project/blit roundtrip for both framebuffer row orders: 15 files / 299 tests passed.
Initial APK `7a319aae09176edd20ef77cfe0b5cd3f45e783c3a51ef5b689ec423dc1c4ecd1`
was observed on unlocked Seeker with the 3D model, Leo without I and centered remembered
owner/address/connect. Feet extended below the ring; the layout anchor was subsequently
raised by about 18 design units. Evidence: `/tmp/hibernalBreathingPetFirst.png`.

Calibrated APK `3a71e00d6015c841d45e8c775d45d4e10f81932886226050110a27e770e383a7`
built 95 modules and was installed. Later unlocked-device captures observed Polar →
Chill → Polar with matching disabled Summon labels, centered connected-wallet area
and eight breathing frames. Evidence: `/tmp/hibernalSummonLeoFinal.png`,
`/tmp/hibernalSummonNix.png`, `/tmp/hibernalPetBreathingSheet.png`; those first two
filenames do not name their actual selected names. The person identified a real defect:
HUD/hologram was composited over the model. Raising the anchor did not fix that order.
Raw UI trial remains active; later lineage still uses Roman numerals. No Claim,
signing, chain name field or commit/land.

## 18. Foreground model and self-depth correction — 2026-10-07

On dirty `wt/hud` over base tree `9bdf70e27fb9829ba971d76d4c7c7f3e203647aa`,
`bash scripts/buildAndroid.sh` built 95 modules. Foreground APK
`edc4cf99d92bf0aee0ef084b030c868bfcab54f6823cf974f8da73dec41ca6ef` was installed
with `adb install -r` under the shared Seeker lease, 20:30:18–20:30:38 +07.
Captures show the model above the hologram, Nix/SUMMON NIX → Leo/SUMMON LEO,
disabled tap retaining MainActivity, centered remembered owner, breathing and normal
wallpaper roaming followed by return to the preview. Evidence:
`/tmp/hibernalPetForegroundPrevious.png`, `/tmp/hibernalPetForegroundDisabled.png`,
`/tmp/hibernalPetForegroundSheet.png`, `/tmp/hibernalPetForegroundWallpaper.png`,
`/tmp/hibernalPetForegroundReturned.png`. The first cold-start capture was black;
subsequent images, not that first image, establish rendering. No wallet signing test.

The person rejected the apparent viewing angle. Direct screen drawing is insufficient:
`vendor/void/src/sokol/bridgeAndroid.c` requests no EGL depth buffer and declares
`SG_PIXELFORMAT_NONE`; rear limbs overpaint nearer parts without self-depth.
Preview correction reuses `campfireScene.ms` `preparePetPreview` with transparent color
and depth attachments, then raw alpha composition above HUD; `hudPost.ms`
`drawHudPost` keeps this copy independent of the temporary HUD grading setting.
No asset recoloring, camera yaw/pitch change or vendor bridge edit was made during
this correction, so the next comparison isolates self-depth/compositing rather than
mixing an arbitrary camera adjustment into it. The two full-frame attachments cost
about 25.6 MB at 1200×2670; crop only if measured memory/frame cost requires it.

Corrected candidate `7a19f840f46cb379772644c31c5d71fbb2afc55b939998bdb8898b646c37e43a`
built 95 modules with installed binary/support `0d83c4867`; log
`/tmp/hibernalPetDepthBuild.log`. Its queued lease check at 22:28:35 +07 reported
`Seeker locked; no PIN/biometric interaction.` and released the lease without install
or input. At that checkpoint candidate self-depth and final viewing-angle acceptance remained
open; the next day's device proof is recorded below. On this toolchain, name tests passed 15 files / 301 tests;
expanded headless camera probe passed 15 files / 300 tests including full-frame overlay
and both row orders. These CPU checks do not establish GPU self-occlusion. Source
assets/cuts remained byte-identical; no transaction, commit or land.

## 19. Self-depth and approved subtle-turn device proof — 2026-10-08

After user restored Seeker access, normally leased run 10:17:12–10:17:35 +07 installed
7a19f840… with `adb install -r`. Captures show the red square lens and nearer parts
correctly occluding rear limbs, with the model still above hologram light. Camera
pose was unchanged: self-depth, not an arbitrary angle edit, fixed the overpainting.
Nix/SUMMON NIX → Leo/SUMMON LEO, disabled CTA retaining MainActivity, breathing,
centered remembered owner and wallpaper roaming/return were observed. Evidence:
`/tmp/hibernalDepthCheck.log`, `/tmp/hibernalPetDepthPrevious.png`,
`/tmp/hibernalPetDepthReturned.png`, `/tmp/hibernalPetDepthSheet.png`,
`/tmp/hibernalPetDepthWallpaper.png`. Startup check waited for actual HUD rendering;
its first not-ready assertion was a polling observation, not failed final rendering.

The person then approved ±10° yaw oscillation over 7 seconds, keeping 3.5-second
breathing and a visible red lens rather than a 360° spin. `placePetPreview` owns the
motion. Build 161b29c… was not installed separately; subsequent passive-owner APK
`6eb0dd9a56dab1e878facbb56d22894193e89d641a28e91b65dbc228cbb4156e` includes it,
built 95 modules with installed c0949e9f2 and was exercised 11:08:35–11:09:03 +07.
Twelve frames show left/right turning, breathing, lens visibility and correct depth
above the ring. Evidence: `/tmp/hibernalPetTurnSheet.png`,
`/tmp/hibernalPetTurn.gif`, `/tmp/hibernalPassiveOwnerApp.png`.
Passive identity proof and integration blockers belong to `APP-INTEGRATION.md`.
No signing, transaction, force-stop, PIN/biometric, commit or land. This is a model
preview, not a created Pet or a live-chain visual; full performance/battery gate
and final design acceptance are not implied.

## 20. Coherent pixel-art candidate — 2026-10-08

User rejected HUD cell averaging: reference `/Users/le/Desktop/Screenshot 2026-09-21 at 18.42.29.png`
calls for scene-wide pixel-art rendering, not a mosaic filter. Research anchors:
[David Holland](https://www.davidhol.land/articles/3d-pixel-art-rendering/) (camera snap/remainder,
convex edge highlights) and [ProPixelizer](https://sites.google.com/view/propixelizer/user-guide)
(render-time grid alignment and the limits of perspective/rotating geometry).
Implementation pointers: `pixelGrid.ms` `snapAnchor`, `campfireScene.ms` `prepareLab`,
`hudPost.ms` `drawPixelPet`, and vendor patch `0004-pixelEdges.patch`.

Measured on dirty `wt/hud` over tree `9bdf70e27fb9829ba971d76d4c7c7f3e203647aa`, msc 0.3.2:
`msc test native/scene/pixelGrid.ms` passed 299 tests/15 files;
`msc test vendor/void/src/void3d/pixelEdgeGeometry.ms --tests-in-dir` passed 2 tests;
`msc test vendor/void/src/test/rendererCheck.ms --tests-in-dir` passed 22 tests.
Source-extracted `toonBand` C probe passed finite/monotonic output, six values over [0,1],
and black/white/HDR endpoints. All four vendor patches replayed byte-identically from their pin.
Patch 0004 SHA256: `1069ee8280d19197e734b064deb08cbd9f208335101a8ef4047ccc07f1f87186`.
First outline build refused stale 192-byte shader parameters against the new 256-byte ABI;
regenerating the vendor header corrected it. `scripts/regenShaders.sh` now owns that regeneration.

`bash scripts/buildAndroid.sh` built 98 modules; final APK SHA256
`898a03300497fcef8b207f870731d5d7fd43750dd23ad3ba5efbec9874874391` was installed with
`adb install -r` under the shared Seeker lease. Six app frames show a visible lens, subtle turning,
breathing and self-occlusion above the hologram; all five consecutive Pet crops differ.
In every frame, sampled Pet-face and Campfire regions have RGB transitions only at x mod 5 = 0,
y mod 5 = 4: both obey the same 5-pixel grid phase, rather than independent pixel grids.
App → launcher/wallpaper → app return retained rendering and the truthful NoPet/zero-admission
footer. Bounded fatal/validation log was empty. Evidence: `/tmp/hibernalPixelUpgrade/`
`finalApp0.png` through `finalApp5.png`, `finalMotionSheet.png`, `finalWallpaper.png`,
`finalReturn.png`, `finalBuild.log` and `finalDeviceErrors.log`; final render source snapshots
were byte-identical to captured build inputs. Black source asset was not recolored.

This verifies the candidate, not visual parity with the reference or a zero-shimmer guarantee.
Camera rotation and model deformation still change raster coverage; no exhaustive tilt sweep,
GPU-time or battery measurement was performed. Convex geometry reconstruction is orthographic;
perspective normal-edge highlights are inactive. Final art acceptance remains the person's.
Client integration/signing evidence belongs to `APP-INTEGRATION.md`; no transaction or commit
was performed by this render lane.

## 21. Texel magnification rather than added detail — 2026-10-08

User clarified the target with [this video](https://www.youtube.com/watch?v=KPoeNZZ6H4s):
onboarding zoom must enlarge pixel cells with the Pet. Retrieved frames around 6:38 show
Unity Game View `Scale 3x`; the linked 2:14 region shows a motion graph, not a camera-zoom
implementation. No inference about the author's internal renderer is required for this contract.
`pixelGrid.ms` `magnified` and `campfireScene.ms` `PET_PREVIEW_ZOOM` own the correction.

`msc test native/scene/pixelGrid.ms` passed 300 tests/15 files, including integer 1×/2×/3×
grids, unchanged origin and coarse boundaries aligned to the parent grid. Android build passed
98 modules. APK `04c2558fcb9a8ebeaddcd045ad062f3cc70a3cf32ec8ed48f0dc7b1bb222625d` was
installed under the Seeker lease. App, another motion frame and app-return captures each have
Pet-face RGB transitions only at x mod 10 = 5, y mod 10 = 9; sampled Campfire transitions remain
x mod 5 = 0, y mod 5 = 4. Preview texels therefore double in screen size while remaining nested
on the scene grid; this supersedes §20's fixed-5px preview candidate, not its shader evidence.
Pet remains above the ring, with lens visible; wallpaper/return and truthful NoPet footer were
observed, bounded fatal/validation log empty. Evidence: `/tmp/hibernalPixelUpgrade/zoom`
`{App,App2,Wallpaper,Return}.png`, `zoomBuild.log`, `zoomTests.log`, `zoomDeviceErrors.log`.
Captured source inputs remained byte-identical after the build. No source asset, chain action,
transaction or commit changed in this correction. Visual acceptance still belongs to the person.

## 22. Smaller preview texels and continuous turn — 2026-10-09

User requested 70% of §21's preview texel size, then rejected the strong-specular/bloom
trial and requested slow continuous rotation instead. `pixelGrid.ms` `withScale` and
`campfireScene.ms` `PET_PREVIEW_PIXEL_PERCENT` / `PET_TURN_SECONDS` own the result.
The preview retains the scene grid origin but 7px cells no longer nest every boundary on
Campfire's 5px grid. Both remain integer-size nearest-neighbor cells; Pet's screen-space
size is preserved by matching camera world-per-texel to its selected grid size.

The rejected trial overexposed the face instead of producing the desired leg reflection.
Its lower white light, increased sheen, custom bloom shader/alpha plumbing and patch 0005
were removed. Vendor shader and renderer files are byte-identical to their pre-trial
snapshots; only the four documented vendor patches remain. The original Pet sheen and
upper white preview light remain. Full rotation visibly exposes bright reflective leg
faces without the rejected bloom; the earlier narrow rocking motion did not show them
through a full turn. User also observed this reflection after the rotation change.

On dirty base tree `9bdf70e27fb9829ba971d76d4c7c7f3e203647aa`, grid tests passed
301 tests/15 files; final Android build passed 99 modules. APK
`e8295f76e04e85ec37b6bac34f433116bbec444cadd019e86c4f1d717646bb78` was installed on
leased Seeker; pulled installed APK hash matches. Nine captures spanning more than a
30-second turn show front, side and back views, moving leg highlights and continued
breathing. Wallpaper and app-return were captured; bounded fatal/validation log empty.
Evidence: `/tmp/hibernalPixelUpgrade/spinSheet.png`, `spin{0..8}.png`,
`spinCaptureTimes.log`, `spinWallpaper.png`, `spinReturn.png`, `spinBuild.log`.
The preceding 7px build's three app/return captures had RGB boundaries exclusively at
x mod 7 = 2, y mod 7 = 5. No GPU-time/battery measurements or reference-parity claim.

## 23. Canonical skill-tree presentation and rejected blur — 2026-10-09

The artifact is visual inspiration, not a gameplay migration. Keep the IDs, links,
prices and effects consumed by simulation/brain; source tracing does not certify a
historical trained checkpoint. `native/hud/skillLayout.ms`, `character.ms` and
`skillInfo.ms` own geometry, selection and rule-derived information. Six dashed
concentric guides are decorative, not extra links or escalating costs. A connected
node is not necessarily allocatable; the preview never enables allocation/signing.

The user rejected a dark rectangular tree backdrop. Replacing it with hard shadows
was also insufficient: the user requested progressively softer and broader shadows.
The wide-blur candidate produced severe lag reported by the user. It applied analytic
Gaussian shadows separately to every sampled link dot; widening each shadow expands
many overlapping GPU quads. This identifies an integration overdraw hazard, not a
measured defect in Void's blur implementation. Void exposes both analytic box shadows
and layer filters; the Android whole-layer filter path was not verified here.

The user then explicitly said “vậy thôi, bỏ blur đi”. All node/link shadow passes were
removed; no backdrop was reinstated. An unbuilt rotated-capsule optimization was also
removed rather than silently continuing the rejected effect. Retain decorative guides,
persistent tap selection and the fixed information panel. Do not reintroduce blur
without a new request and real-consumer performance evidence.

On dirty HEAD `cc582942d6c96e6751e926454311448a0ce3ddbe`, geometry/selection checks
passed 320 native and 83 JS tests; the Home type check passed 142 modules. The no-blur
recovery APK built 106 modules and its pulled installed hash matched
`d655e4006d1832b6dbd6f593cdf461d005bcac9350f3216ffca1db3a6db9d458`.
Seeker captures show dashed guides, no shadow cloud and successful node selection.
Earlier captures verified rule-derived node 17/59 information and identical fixed-panel
pixels after waiting and closing/reopening. These are UI-preview proofs, not chain
readiness. SurfaceFlinger supplied no usable presentation samples and a temporary
callback counter supplied no log output: no FPS, GPU-time, battery or fully-resolved-lag
claim. Later client changes require their own integrated consumer verification.
