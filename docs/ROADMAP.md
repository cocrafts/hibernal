# ROADMAP — Hibernal, all-in MetaScript (D31)

> Companion to `BRIEF.md` (game + architecture) and `RENDERER-BRIEF.md` (renderer + Android surfaces). This file answers three questions: **what can start today**, **what is blocked and on which repo**, and **what unblocks what**, so work can be split across people and across the three repos (`hibernal`, `recompiler`, `void`, plus `neon`).
>
> Status legend: **READY** = no upstream blocker, start now · **BLOCKED:R / V / N** = waiting on recompiler / void / neon work · **BLOCKED:dep** = waiting on another package in this file · **OPT** = optional, cut first.
> Estimates are person-days for someone who knows the stack. Last updated 2026-09-12.

---

## 1. The two unproven toolchains (read first)

Everything sits on two paths that have never run end to end. They are deliberately spiked separately on day 1 so a failure points at exactly one thing.

| Path | Evidence today | What "proven" means |
|---|---|---|
| `msc build --os=solana` | sBPF ELF builds and runs in LiteSVM (`talks/solana-meetup/demo`, 108 CU hello). No entrypoint parsing, no heap on the Solana heap region. | A program reads two accounts, mutates one, returns an error code, in LiteSVM. (**R1 + R2**) |
| `msc build --os=android --app=lib` | Target exists in the compiler; **never executed**. No NDK detection, no JNI. | `libhibernal.so` loads on the Seeker and Kotlin calls `fight()` through JNI. (**R9 + A1**) |

Tripwires: **day 1** both spikes; **day 4** `tick + eat + level_up` in LiteSVM (P1). A missed tripwire buys exactly one dated C shim for the blocking item (BRIEF D31), nothing else changes.

---

## 2. Dependency graph

```mermaid
flowchart LR
  subgraph R[recompiler]
    R1[R1 heap @0x300000000<br/>elide RC, no-op dtors]
    R2[R2 entrypoint +<br/>AccountInfo views]
    R3[R3 syscalls: log64, sha256,<br/>PDA, clock, slothashes]
    R4[R4 codegen: non-const div,<br/>ban string building]
    R5[R5 error ABI]
    R6[R6 CPI + flattened shim<br/>System, Token-2022]
    R7[R7 LiteSVM harness JS]
    R8[R8 Solana subset +<br/>regression tests]
    R9[R9 android .so via NDK,<br/>JNI export pattern]
    R10[R10 std/http+tls under NDK]
    R11[R11 checked arithmetic]
  end
  subgraph V[void]
    V1[V1 depth attach + EGL depth]
    V2[V2 pipeline/pass bridge]
    V3[V3 math3d]
    V4[V4 glTF subset loader]
    V5[V5 3D layout + toon/normal/<br/>outline/palette shaders]
    V6[V6 Android embed hardening]
    V7[V7 text on Android]
  end
  subgraph N[neon]
    N1[N1 void host on Android:<br/>input + text]
  end
  subgraph P[program]
    P0[P0 rules/: layout, fight,<br/>emission, tree, brain]
    P1[P1 config, pet, tick, eat,<br/>harvest_claim, level_up]
    P2[P2 claim + SGT TLV, block,<br/>free-list, grace, close]
    P3[P3 session-token verify]
    P4[P4 attack, FightRecord,<br/>death, allocate]
    P5[P5 SKR shop CPI]
    P6[P6 VRF]
    P7[P7 update_config, timelock]
    P8[P8 guard.ms + adversarial]
    P9[P9 differential fuzz]
    P10[P10 devnet deploy]
  end
  subgraph A[native core + shell]
    A0[A0 Kotlin shell skeleton]
    A1[A1 spike: .so + JNI on Seeker]
    A2[A2 spike: EGL triangle in<br/>wallpaper, FBO blit]
    A3[A3 render passes on device]
    A4[A4 camera, lights, first pet]
    A5[A5 RPC + tx + ed25519 sign]
    A6[A6 brain loop + WorkManager<br/>+ session key]
    A7[A7 MWA: claim, session, SKR]
    A8[A8 HUD screens]
    A9[A9 widget]
    A10[A10 lifecycle + battery]
    A11[A11 variants, day/night,<br/>Winter, harvest objects]
  end
  subgraph T[art / sim / submission]
    T1[T1 Blender generator]
    S1[S1 sim harness]
    S2[S2 tuning runs]
    X1[X1 verify hackathon rules]
    X2[X2 demo video]
    X3[X3 deck]
    X4[X4 dApp Store]
  end

  R1 --> R2 --> P1
  R3 --> P1
  R4 --> P1
  R5 --> P1
  R11 --> P8
  R2 --> R6
  R3 --> R6
  R6 --> P5
  R6 --> P6
  R7 --> P1
  R7 --> P9
  P0 --> P1
  P0 --> S1 --> S2
  P1 --> P2 --> P4
  P1 --> P3
  P1 --> P7
  P1 --> P8
  P2 --> P10
  P4 --> P6
  P4 --> P9
  P0 --> P9

  R9 --> A1
  R9 --> A2
  A0 --> A2
  P0 --> A1
  R9 --> R10 --> A5
  A2 --> A3
  V1 --> A3
  V2 --> A3
  V5 --> A3
  V1 --> V5
  V2 --> V5
  V3 --> A4
  V4 --> A4
  T1 --> A4
  A3 --> A4
  A3 --> A10
  V6 --> A10
  A5 --> A6
  P3 --> A6
  A7 --> A6
  A0 --> A7
  P10 --> A7
  A3 --> A8
  A5 --> A8
  N1 --> A8
  V7 --> N1
  A2 --> V7
  A2 --> V6
  A6 --> A9
  A4 --> A11
  S2 --> P10

  A6 --> X2
  A10 --> X2
  A8 --> X2
  P10 --> X2
  X2 --> X3
  X2 --> X4
```

**Critical path (chain):** R1 → R2 → P1 → P2 → P4 → P10 → A7 → A6 → X2.
**Critical path (device):** R9 → A2 → A3 → A4 → A10 → X2.
They merge only at the demo. Nothing on the device path waits on the program until A6/A7.

---

## 3. Work packages

### 3.1 READY today (no upstream blocker)
| ID | Package | Est. | Notes |
|---|---|---|---|
| ~~**P0**~~ | `rules/`: `layout.ms`, `rng.ms`, `fight.ms`, `emission.ms`, `tree.ms`, `brain.ms`, `pwinMc.ms` | 3 | **Done 2026-09-12** (first pass): 26 tests green under `msc test rules/index.ms`; `sim/determinism.ms` gives identical digests on native and js; `sim/curve.ms` meets §6.7. Not yet on chain: see R12. Feeds P1, A1, S1, P9. |
| **S1** | Sim harness in MetaScript on `rules/`: 200 pets, 20 blocks, 120 epochs, invariants §6 | 1.5 | Unblocked. `sim/curve.ms` and `sim/determinism.ms` are the seed. |
| **A0** | Kotlin shell skeleton: gradle, `WallpaperService`, Activity + SurfaceView, `System.loadLibrary`, JNI stubs | 1 | Pure Kotlin. |
| **T1** | Blender parametric generator → glTF (positions, normals, vertex colors), 3 region variants, 9 animations as baked keyframes | 3 | Offline. Feeds A4. |
| **R7** | Extend the demo's LiteSVM JS harness: multi-account setup, clock control, state dump, seed replay | 1 | Feeds P1 and P9. |
| **R4** | Codegen: division/modulo by non-constant; ban string building under `--os=solana` | 1–2 | Compiler. |
| **R5** | Error ABI: `u64` return, `panic` → log + abort, `ProgramError` | 0.5 | Compiler. |
| **R11** | Verify u64 overflow behavior on the C backend; add `checked_*` ops if it wraps | 1 | Compiler; security prerequisite for P8. |
| **V3** | `std/math3d`: vec3, mat4 (ortho, lookAt, normal matrix), quat | 1 | Pure MetaScript. |
| **V4** | glTF subset loader (~200 lines) | 1 | Pure MetaScript + file IO. |
| **X1** | Verify CLOCK IN eligibility, submission rules, tracks and sponsor list in a browser | 0.2 | — |

### 3.2 BLOCKED on recompiler (R)
| ID | Package | Est. | Blocks |
|---|---|---|---|
| **R1** | Solana heap: arena at `0x300000000`, `.bss/.data` handling, RC ops elided under `--gc=manual`, no-op destructors | 2 | R2, everything in P |
| **R2** | Entrypoint: parse input into typed `AccountInfo` views (`std/solana/entrypoint.ms`); C SDK `sol_deserialize` is the reference | 2 | P1, R6 |
| **R3** | Syscalls: `sol_log_64_`, `sol_sha256`, `sol_create_program_address`, `sol_try_find_program_address`, `sol_get_clock_sysvar`; SlotHashes via sysvar account | 1 | P1, R6 |
| **R6** | CPI: `sol_invoke_signed_c` behind a flattened shim; helpers for System `create_account`, Token-2022 `transfer_checked` | 2–3 | P5, P6 |
| **R8** | Solana subset definition + one `--os=solana` regression test per construct | ongoing | P8 |
| **R9** | Android: NDK toolchain wiring (`--cc` wrapper or detection), `arm64-v8a`, `--app=lib` → `.so`, JNI export pattern (C shim with `JNIEXPORT` calling MetaScript symbols) | 1–3 | A1, A2, R10 |
| **R10** | `std/http` + `std/tls` link and run under NDK | 0.5–2 | A5 (fallback: OkHttp in the shell) |
| **R12** | Module-scope `const` under `--os=solana`: emitted as a C global that the contract link discards (`ld.lld: relocation refers to a symbol in a discarded section: K__…`), exported or not; `enum` members are fine. Fold to literals or emit `static const`. Measured 2026-09-12 on `tools/rulesProbe.ms`. | 0.5–1 | P1 (rules/ on chain), A1 |
| **R13** | Runtime calls that abort on chain, measured 2026-09-12 in LiteSVM: `String(uint64)` → `exceeded max BPF to BPF call depth`; `process.exit()` → `ProgramFailedToComplete`. Refuse them at compile time under `--os=solana` (extends R4/R5). | 0.5 | R8 |

### 3.3 BLOCKED on void (V)
| ID | Package | Est. | Blocks |
|---|---|---|---|
| **V1** | `EGL_DEPTH_SIZE 24` in `bridgeAndroid.c`, depth attachments on offscreen passes | 1 | V5, A3 |
| **V2** | Pipeline/pass creation reachable from MetaScript (flattened-descriptor bridge) or the fixed set of 4 pipelines in C | 1–2 | V5, A3 |
| **V5** | 3D vertex layout (pos, normal, color), color+depth pass, normal pass, outline pass, palette-LUT pass, nearest blit; sokol-shdc sources | 2–3 | A3 |
| **V6** | Android embed hardening: context loss, preview + live concurrently, visibility stop, no allocation in frame | 1–2 | A10 |
| **V7** | Text batcher verified on Android GLES3 | 0.5 | N1 |

### 3.4 BLOCKED on neon (N)
| ID | Package | Est. | Blocks |
|---|---|---|---|
| **N1** | Neon void host on Android: touch input routing, text, layout at 360×800 | 2 | A8. **Fallback:** draw the HUD imperatively with void 2D calls; Neon later. |

### 3.5 Program packages (BLOCKED:dep on R1–R5 unless noted)
| ID | Package | Est. | Depends on |
|---|---|---|---|
| **P1** | `init_config`, `GlobalConfig`, `Pet`, `tick` (accumulator + hunger + auto-eat), `eat`, `harvest_claim`, `level_up` | 3 | R1 R2 R3 R4 R5 R7 P0 |
| **P2** | `claim` (SGT TLV parse, DevAdmission on devnet), `Block`, free-list, grace, `close_dead_pet` | 3 | P1 |
| **P3** | Session-token verification (MagicBlock PDA layout) | 0.5 | P1 |
| **P4** | `attack` (SlotHashes seed), `fight()` in program, `FightRecord` ring buffer, death + inheritance, `allocate` | 3 | P2 P0 |
| **P5** | SKR shop: `feed`, `buy_growth`, `buy_insurance`, `buy_skin` via Token-2022 CPI | 1 | R6 P1 |
| **P6** | VRF request + `resolve_fight` callback, `FightPending` | 1.5 | R6 P4 · **OPT** |
| **P7** | `update_config`, timelock authority | 0.5 | P1 |
| **P8** | `guard.ms` + adversarial LiteSVM tests (wrong owner, missing signer, fake session token, duplicate accounts, overflow inputs, shield, caps) | 2 | P1 R11 |
| **P9** | Differential fuzz: JS model vs LiteSVM `.so`, invariants, UBSan host build | 2 | P4 P0 R7 |
| **P10** | Devnet deploy, DevAdmission group, demo config (`EPOCH_SECONDS=600`, `max_hearts=3`) | 0.5 | P2 S2 |

### 3.6 Native core + shell packages
| ID | Package | Est. | Depends on |
|---|---|---|---|
| **A1** | Spike: `libhibernal.so` via NDK, JNI calls `fight()` from Kotlin on the Seeker | 1 | R9 P0 |
| **A2** | Spike: EGL triangle into 360×800 FBO, nearest blit, inside `WallpaperService`; survives lock/unlock/picker | 1 | R9 A0 |
| **A3** | Render passes on device (color+depth, normal, outline, palette, blit) | 2 | A2 V1 V2 V5 |
| **A4** | Orthographic snapped camera, directional + campfire point light, toon ramp, first pet from T1, idle animation, touch | 2 | A3 V3 V4 T1 |
| **A5** | `native/rpc`: JSON-RPC, base58/base64, blockhash, legacy+v0 message serialization, ed25519 signing, `sendTransaction` (test against devnet memo/transfer before P10) | 2 | R9 R10 |
| **A6** | `hib_brain_tick`: fetch block, run `brain.ms`, sign with session key, send; `BrainWorker` on WorkManager; session key in Keystore-wrapped encrypted file | 2 | A5 P3 A7 |
| **A7** | MWA `clientlib-ktx`: connect, claim signing, `create_session` (built natively, owner-signed), SKR purchases | 1.5 | A0 P10 |
| **A8** | HUD: campfire home + neighbor fires + Monte-Carlo odds, My Pet, Tree, Replay, Shop, Digest, Settings | 3 | A3 A5 N1 (or fallback) |
| **A9** | Glance widget: hearts, harvest, Winter countdown, owner-signed emergency Claim | 1 | A6 · **OPT** |
| **A10** | Lifecycle hardening + battery measurement (Battery Historian, < 2%/h) | 1.5 | A3 V6 |
| **A11** | Variants, day/night palette, Winter snow, harvest objects, Fading desaturation | 2 | A4 |

### 3.7 Tuning and submission
| ID | Package | Est. | Depends on |
|---|---|---|---|
| **S2** | Tuning runs: `E0`, `cost(L)`, `food_cost`, `k`, `DMG`, combat curve (BRIEF §6 invariants 7–8) | 1.5 | S1 |
| **X2** | Demo video: unlock → pet on lock screen → claim → session → works → eats → levels → fight replay → neighbor starves → inheritance | 1 | A6 A8 A10 P10 |
| **X3** | Deck (BRIEF §9 outline) | 1 | X2 |
| **X4** | dApp Store submission, README, architecture doc, pinned commits | 1 | X2 |

---

## 4. Suggested split

**Two people:**
- **Chain lane:** R1 → R2 → R3/R4/R5 → P1 → P2/P3 → P4 → P8/P9 → R6 → P5 → P10 → (P6, P7). Pulls R7 and S1/S2 in the gaps.
- **Device lane:** A0 → R9 → A1/A2 → V1/V2 → V5 → A3 → V3/V4/T1 → A4 → A5 (R10) → A7 → A6 → A8 (V7/N1) → A10 → A11 → A9.

**Solo:** P0 + A0 + T1 (all READY) on day 0 while thinking; then chain lane through P2 (days 1–5, it gates the demo), then device lane through A6 (days 6–11), then A8/A10 in buffer week 1, polish in buffer week 2. Cut order: P6 → A9 → A11 → A8 polish. Never A2/A10 (the wallpaper is the opener).

**Third person / spare hours:** P0, S1, T1, R7, V3, V4, X1 are all independent and unblock the most.

---

## 5. Milestones and tripwires

| When | Milestone | Proves |
|---|---|---|
| Day 1 | A1 green on Seeker; A2 green; R1+R2 counter in LiteSVM | Both toolchains exist |
| Day 4 | P1 in LiteSVM from MetaScript | Program path is real |
| Day 6 | A5 sends a signed tx to devnet from native | Client path is real |
| Day 8 | P10 devnet deploy; A4 first pet lit by a fire | Halfway demo |
| Day 11 | A6 brain acts on devnet without a popup | The pitch works |
| Day 13 | X2 recorded | Ship |
| Buffer wk 1 | Shims replaced by compiler fixes; P9 fuzz green on pinned commit | Technical Depth story is honest |
| Buffer wk 2 | X4 submitted, review feedback handled | Done |
