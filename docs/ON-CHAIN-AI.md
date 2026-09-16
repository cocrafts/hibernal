# ON-CHAIN-AI — Hibernal

> The pet brain as a trained integer policy that runs inside `act(pet)` in the MagicBlock Ephemeral Rollup. Design context: `GAME-DESIGN.md` §12–§13 and `BRIEF.md` §3.10; chain surface: `SOLANA.md`; plan packages S1, S3, S4 in `ROADMAP.md`.
>
> Tags: **Measured** = run and observed · **Documented** = read in vendor docs, not run by us · **Decided** · **Open**.

---

## 0. Summary

- The brain on chain is a small integer MLP. The heuristic `rules/brain.ms` never runs on chain; it is the behavior-cloning teacher off chain.
- The goal is believable behavior, not strength: pets with recognizable personas that react to what happens to them and never do something visibly stupid.
- Budget: about 5–10k parameters across four policies, int8, 6–8 KB in one `["policy"]` account. 50k parameters is the ceiling, not the target.
- Training runs on native `rules/` built as a C library, driven from Python and PyTorch. No Rust.

## 1. Why the heuristic cannot run on chain — Measured

`fight()` from `rules/` in LiteSVM (`program/out/fightProbe.so` through `tools/chain/fightLiteSvm.mjs`, 2026-09-16):

| Matchup | Rounds | `fight` CU | Instruction CU |
|---|---|---|---|
| (80,50) vs (50,80), seed 42 | 6 | 16,504 | 18,237 |
| (50,50) vs (50,50), seed 7 | 6 | 16,862 | 18,595 |
| (200,200) vs (160,80) | 2 | 5,547 | 7,280 |

- `scoreTarget` runs 400 fights per target: about 6.6M CU for one target.
- The "16–32 samples" fallback in `GAME-DESIGN.md` §12 does not fit either: 16 samples × 9 targets is about 2.4M CU.
- Monte Carlo odds stay client-side (`BRIEF.md` §3.6 odds UI) and in the teacher.

## 2. Compute budget

**Documented** (MagicBlock "Runtime Limits"): the ER runs the same SVM limits as L1, 200,000 CU per instruction by default and 1,400,000 CU per transaction with `SetComputeUnitLimit`. Only the transaction size grows, 1,232 bytes on L1 against 64 KB in the ER.

**Measured** (2026-09-16): an int8 dense forward pass on sBPF v3 costs about 12 CU per weight. Probe: `no_std` Rust, `-O3`, LTO, weights in `.rodata`, ReLU and shift requantization, LiteSVM with a 1.4M limit.

| Weights executed | CU |
|---|---|
| 0 | 267 |
| 2,560 | 32,971 |
| 10,240 | 127,112 |
| 36,864 | 449,243 |
| 73,728 | 894,524 |
| 294,912 | exceeds 1,400,000 |

- Rust `-O3` is the floor. MetaScript-generated C for the same loop is unmeasured.
- The fight settles in the VRF callback `consume_fight`, a separate transaction, so the budget of `act` belongs to the brain and its bookkeeping.
- Executed weights, not stored weights, are what cost CU: a network scored once per candidate target costs its size times the number of candidates.
- Working limit: about 40–50k executed weights per `act`, leaving room for account parsing, tick and writes, and for MetaScript codegen overhead.

## 3. Size and rent — Measured

Rent-exempt minimum from `solana rent`, identical on devnet and mainnet on 2026-09-16: `(bytes + 128) × 5,080` lamports, about 0.0051 SOL per KB. Rent is a deposit, returned when the account or program is closed.

| Bytes | SOL |
|---|---|
| 4,500 | 0.0235 |
| 20,000 | 0.1023 |
| 50,000 | 0.2547 |
| 204,800 | 1.0410 |
| 1,048,576 | 5.3274 |
| 5,242,880 | 26.634 |

- A deployed program pays for its ProgramData account, sized to the `.so` plus 45 bytes (`--max-len` defaults to the program length). `fightProbe.so` at 69 KB is 0.35 SOL.
- A deploy writes into a buffer account of the same size first, so it needs about twice the rent up front; the buffer is closed afterwards. Every upgrade does the same, and a larger `.so` extends ProgramData.
- Weights inside the `.so` or in a separate account cost the same per byte. The separate `["policy"]` account wins because new weights do not redeploy the program.

| Parameters | int8 | Rent |
|---|---|---|
| 5k | ~5.7 KB `[estimate]` | ~0.030 SOL |
| 50k | ~52 KB `[estimate]` | ~0.27 SOL |

Estimates count 1 byte per weight, a 4-byte bias per neuron and per-layer shifts.

## 4. Model shape — Decided, sizes `[strawman]`

| Policy | Runs when | Network | Parameters | Runs per `act` | CU at 12/weight |
|---|---|---|---|---|---|
| Economy | every `act` | 32 → 32 → 8 actions | ~1.3k | 1 | ~16k |
| Fight | attacks left | 24 → 32 → 16 → 4 stake levels, shared per target | ~1.3k | × 9 targets | ~140k |
| Tree | `pointsUnspent > 0` | 24 → 32 → 1, per open adjacent node | ~0.8k | × ~6 nodes | ~60k |
| Social | every `act` | 24 → 32 → 6, per block-mate | ~1k | × 9 pets | ~110k |

- About 4.4k parameters in total; all four in one `act` is about 330k CU.
- Keep the `["policy"]` account at or below 10,240 bytes so the program creates it in one CPI.
- No recurrent state. Each `act` is an independent transaction; what a pet should remember (grudges, who robbed it) is a feature read from `Block` (`relationships`, `FightRecord`s).
- Features carry the hard parts, computed by `rules/`: win chance from an odds table, expected value, days of food left, distance to the next keystone.
- Guardrails sit outside the network: the legal-action mask comes from `rules/`, and the survival floor (auto-eat, D22) runs before the policy. The network only picks a style inside that space.
- Grow a policy only when the sim shows a visible mistake the guardrails do not stop.

## 5. Training pipeline — Decided

Recipe from Under Realm (`~/metacraft/urg/ai/CLAUDE.md`, `~/metacraft/urg/engine/docs/AI-TRAINING.md`): behavior cloning of the heuristic, then PPO against heuristic personas, then self-play against a pool of snapshots. The teacher can be any size; the shipped student is distilled and trained quantization-aware to int8.

| Layer | Language | Where |
|---|---|---|
| Rules, legal actions, observation, reward, teacher actions | MetaScript | `rules/`, `sim/` |
| Batched environment with a C ABI | MetaScript, `msc build --app=lib` | `sim/env/ffi.ms` |
| Network, PPO, optimizer, checkpoints | Python, PyTorch, uv | `train/` |
| int8 export and inference | MetaScript | `rules/policy.ms`, evaluated in `sim/` |

Carried over from Under Realm, each one a documented failure there:

- Legality comes from `rules/`, never from a bot's move list.
- Actions are identified by id (target slot, node id), not by list position.
- One FFI call steps the whole batch. Under Realm measured 91% of iteration time in bridge overhead at batch size 1.
- An engine version is stamped into every checkpoint; a mismatch refuses to load.
- Evaluation runs only through the MetaScript integer inference. Two policy paths cost Under Realm 10–20 percentage points between training and deployment.

"Feel" is measured with behavior metrics, not win rate:

- pets that starve with money in the burrow: 0;
- persona recognizable from action logs;
- revenge rate after being robbed;
- attacks taken at very low win chance.

## 6. Closed game loop — Open

Built in this order; balance and exact numbers come later (`BRIEF.md` §6, ROADMAP S2).

| # | Package | Status |
|---|---|---|
| 1 | C-ABI export from `msc build --app=lib` (§7) | done: `@exportName` landed (`86c6afaf`, `734b5b14`) and installed from recompiler `cc7ea0b7` on 2026-09-16 (suite 3708/3708; Hibernal tests and digests unchanged by the new compiler) |
| 2 | `rules/`: fixed action list, legal mask, apply functions for tick, bank, eat, allocate and attack settlement, minimal XP leveling | done 2026-09-16, below |
| 3 | `sim/world.ms`: 20 blocks × 10 pets, 4 `act` rounds per epoch, heir takes a dead pet's slot, 120-epoch episodes | ready |
| 4 | `sim/env/ffi.ms`: `reset(seed, envCount)`, `observe` into a flat `int32` buffer with the legal mask, `step(actions)` returning reward and done, teacher actions for behavior cloning | after 1–3 |
| 5 | `train/`: behavior cloning, PPO, self-play pool, int8 export | after 4 |
| 6 | `rules/policy.ms`: int8 inference, evaluated in the sim, then ROADMAP S4 on chain | after 5 |

Defaults `[strawman]`: 4 `act` rounds per epoch, 120-epoch episodes, reward from the change in harvest plus burrow with penalties for lost hearts and death, persona as an input.

### Package 2: actions, masks and apply functions — Measured

`rules/level.ms`, `rules/life.ms`, `rules/actions.ms`. Every apply function is pure and returns `Result<…, enum error>`; every legal mask is built by running the apply function, so a masked action always applies.

| Head | Action id | Legal mask |
|---|---|---|
| Economy | `EconomyAction`: `Rest`, `Bank`, `EatSmall`, `EatMedium`, `EatLarge` | `pet.legalEconomy(global)`: `BitSet<EconomyAction>` |
| Tree | node id `0..TREE_NODES−1`; `ALLOCATE_HOLD = TREE_NODES` | `pet.legalNodes(global)`: `NodeMask` |
| Fight | `attackChoice(BlockSlot, StakeLevel)` = slot × 4 + level; `ATTACK_HOLD = 40` | `attackHoldMask().attacksOn(attacker, defender, epoch)` once per block-mate: `attackable` runs the preconditions once per target and returns the stake cap, `stakeAt` prices the four levels |

- The hold action is part of every mask (`nodeHoldMask()`, `attackHoldMask()`, `EconomyAction.Rest`), so a head's logits are masked by one word and nothing else; a dead pet has an empty mask on every head. `allocateNode` checks points before adjacency, so a pet with nothing to spend refuses all 24 nodes on one compare each.

- One `act`: `tickTo` (settles the global accumulator, pays the reward, hunger with the auto-eat floor, work XP, fight-day reset) → `doEconomy` → `allocateNode` → `settleAttack`; `bury` splits a dead pet's wallet.
- `StakeLevel` is a quarter, half, three quarters or all of `maxStake(defender.harvest)`, never below `MIN_BITE_STAKE`.
- `Pet` gains `xp: uint32` and `slotsAttackedToday: BitSet<BlockSlot>` (max one attack per attacker and target per epoch, `BRIEF.md` §3.6). `levelCost` is gone (D6); keystones cost 3 points.
- XP `[strawman]`: newborn 190, work 7 × `workPower` per epoch, raid 3 per `$HBRN` looted capped at 500, defense 60 won and 20 lost; curve `190 × (L − 1) + (L − 1)³`, cap 20.
- Checks: `msc test rules/index.ms` 341/341; `sim/determinism.ms` native equals JS, `fights`, `tree` and `odds` unchanged, `economy` moved because `levelCost` left the digest. A 10-pet, 30-epoch loop with a naive policy (64 fights, 36 raids) prints the same digest on native and JS; its pets reach levels 16–20 by epoch 30.
- Not in package 2 (ROADMAP P0b): the 64-node tree, the D26 loot formula, talent, decline and natural death, items, bonding, social.
- Compiler bug found on the way, JS backend: a `uint64` `for` counter is emitted as a `Number`; arithmetic, free calls and struct literals wrap it in `BigInt()`, extension dot-call arguments do not, so `pet.tickTo(global, epoch)` throws `Cannot mix BigInt`. Repro `out/jsUint64/dotCall.ms`. `rules/` does not hit it; `sim/world.ms` will.

## 7. Blocker: C-ABI export from a MetaScript library — Measured

Repro: `out/ffiprobe/plainExport.ms`, installed `msc` 0.2.54 (binary dated 2026-09-15), `--app=lib`.

```ms
export function probe_plain(): int32 { return 7; }
export extern function probe_extern(): int32 { return 9; }
```

| Declaration | In the `.dylib` |
|---|---|
| `export function probe_plain` | `probe_plain__Z85sers...Oms_u0` (module-mangled) |
| `export extern function probe_extern` | nothing: no definition, no prototype in the emitted C |

- The parser keeps the body: the AST is a `FunctionDecl` with `fnFlags: extern`.
- The checker marks every `extern function` as a C import: `collectPass.ms` sets `SymbolFlag.ImportC` whenever `fnFlags` contains `extern`, with or without `export`, with or without a body, although its comment says export requires the `export` keyword.
- Codegen then treats it as a function implemented in C: `genFunctionDecl` emits at most a prototype and returns before the body (`declarations.ms:224`, `if (isExternFn) return;`). The same gate exists at `bf0b7fe` (2026-07-15); `2bc56930` (2026-07-31) only widened it to the raw flag and to methods.
- The emitted C for the repro has no prototype either, so an earlier step (dead-code elimination) also drops the symbol. Not pinned yet.
- Under Realm's `engine/out/release/ffi.a` (built 2026-07-24) holds no `urg_*` symbols either, only the module init functions. Whether its Rust crate ever linked a different build was not checked.

Nim's `exportc` (`pragmas.nim` `makeExternExport`: external name plus `sfExportc`) was ported only for the JS backend: `docs/NIM-REF-BK.md` records "MS maps Nim's exportc class onto `export`", and `jsSymbolName` (`src/codegen/js/expressions.ms`) keeps `Exported` symbols bare outside bundle mode. The C backend has no counterpart: `mangledFunctionName` bypasses mangling only for `nativeName` or `ImportC`, and `docs/NIM-REF.md` pins `extern` as `importc` with no body (fixed 2026-07-31, `2bc5693`). No branch or worktree carries a `SymbolFlag.ExportC` or an `exportc` decorator, and the intrinsic decorators are `emit`, `include`, `compile`, `link`, `passC`, `passL`, `import`, `comptime` and `builtin` (`src/checker/decoratorHelpers.ms`). `docs/FEATURES.md` still lists `@runtime("c_name")` as DONE ("codegen emits `c_name` unmangled"), but that is the legacy compiler: there `runtimeName` only redirected call sites to a C runtime function (`compiler-legacy/src/codegen/c/expressions.ms` `emitRuntimeCall`), an import like `importc`. The recompiler replaced it with the `from "c_name"` clause on `extern` declarations (`047604d8`, 2026-03-07); `@runtime` on an exported function now fails with `Decorators are not valid here` (`out/ffiprobe/runtimeExport.ms`). The existing escape hatches are raw `@emit` with `__attribute__((export_name(...)))` (`docs/BARE.md`, wasm) and the hardcoded Solana `entrypoint` wrapper (`src/codegen/c/index.ms:252`).

Void reaches the same goal the other way round: the exported names (`voidEmbedInit`, `voidEmbedFrame`) are C functions in `src/sokol/bridgeAndroid.c`, and the MetaScript entry calls `extern function voidEmbedRegister(init: () => void, frame: () => void)` once from `MsMain`, so C stores `msClosure` values and calls back into MetaScript. This works with the current compiler; the C side has to know each callback's signature.

### Fix: `@exportName` — Measured, landed 2026-09-16

`/trace-nim` against Nim `exportc` (`pragmas.nim` `setExternName` + `makeExternExport`; `ccgexprs.nim` generates every module-level `sfExportc` proc whether called or not). `extern` stays the import side. The export side is a directive named for what it does:

```ms
@exportName("probe_step")
export function probeStep(actions: unknown, observations: unknown, count: int32): int32 { ... }

@exportName
function env_unreferenced(): int32 { return 11; }
```

- The argument is the C symbol; bare `@exportName` keeps the MetaScript name (Nim's default `$1`).
- The name lives in a new `Symbol.exportName`, not in `nativeName`: about 30 compiler sites read `nativeName != ""` as "call through the extern ABI" (`emitNativeCall`, span flattening, `extensionMethodLower`), so reusing it would split the call ABI from the definition. `mangledFunctionName` returns `exportName` first, `genFunctionDecl` drops `static`, reachability roots the function in every module, and the export registry and prelude pack carry the name so importers call the pinned symbol.
- Rejected with a diagnostic: extern (import) functions, generic functions, bodyless signatures, class methods, classes and any argument other than one string literal.

Probes on the candidate (`--app=lib`, `nm -gU`, then Python `ctypes`):

| Case | Result |
|---|---|
| exported, pinned name | `T _env_version`, returns 3 |
| bare `@exportName`, never called | `T _env_unreferenced`, returns 11 |
| pinned in an imported module | `T _env_step`, returns 5 |
| pinned in an imported module, never called | `T _env_dep_unreferenced`, returns 13 |
| entry calls the imported pinned function | `env_calls_step` returns 6 |
| `probe_step` over `int32` buffers via `poke32`/`peek32` | total 10, observations `[3, 5, 7, 9]` |
| same file on `--target=js` | runs, prints 42; the JS name is not pinned |
| plain `export function` (neighbour) | still module-mangled, unchanged |

Regression pins: `src/test/fixedbugs/bug172ExportNamePinsCSymbol.ms` (calls the pinned symbol through an `extern` declaration, so a mangled or dead-code-eliminated definition fails to compile), `src/test/guard/exportNameOnExternRejected.ms` and corpus `778-exportNameSymbol` (`42|7|49`). All fail on the pre-fix binary with `Decorators are not valid here`. Not verified: `--os=solana`, where the build passes `-fvisibility=hidden`.

Landed as `86c6afaf` (compiler) and `734b5b14` (tests). Re-run at the landed tip: the seven `env_*`/`probe_*` rows above, `bug172`, the guard and corpus 778 on drc and orc, and `msc test src/index.ms` 3705/3705. The aggregate `msc test src/test/fixedbugs/index.ms` is red with `'new Box()' requires explicit type arguments` in `bug129`; the pre-fix compiler on the same aggregate without `bug172` fails the same way, so it predates this change.

## 8. Open questions

1. CU per weight for the MetaScript-generated inference loop, and the overhead of `act` without the brain.
2. Whether `act` inside the ER can read a non-delegated `["policy"]` account; the JIT cloning docs cover delegated accounts and programs. Fallback: delegate the policy PDA too.
3. Reward weights per persona (`GAME-DESIGN.md` §17.5).
4. Argmax or sampling on chain; sampling would draw from VRF like every other roll.
