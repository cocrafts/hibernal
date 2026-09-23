# Hibernal

Tamagotchi that permanently dies, one per Seeker Genesis Token, on Solana L1 with game state and the pet brain in a MagicBlock Ephemeral Rollup. Everything is MetaScript end to end: on-chain program, native core, sim. Design: `docs/BRIEF.md` (spec) and `docs/GAME-DESIGN.md` (decisions, measurements, open numbers). Chain surface and ER probe: `docs/SOLANA.md`. Trained brain, budgets and training pipeline: `docs/ON-CHAIN-AI.md`. Plan and package status: `docs/ROADMAP.md`. Renderer: `docs/RENDERER-BRIEF.md`.

## Layout

```
rules/     game rules, integer only, compiled 3 ways (native, js, --os=solana)
sim/       harnesses on rules/ (msc run); sim/env/ is the batched training env with a C ABI
tools/     probes and chain harnesses
program/   on-chain program (--os=solana), brain included (act)
native/    renderer, hud, rpc → libhibernal.so
android/   Kotlin shell
train/     PyTorch training on the env library (uv): bc.py, ppo.py, evaluate.py
docs/      briefs and roadmap
```

## Commands

```bash
msc test rules/index.ms                              # rules suite
msc test sim/teacher.ms                              # rules + world + teacher suite
msc test sim/env/ffi.ms                              # everything above + observation, batch, actor
msc run sim/episode.ms                               # 200 pets × 120 epochs with the teacher
msc run sim/curve.ms                                 # combat curve vs BRIEF §6.7
msc run sim/determinism.ms                           # digests; must match the js build:
msc build sim/determinism.ms --target=js --output=out/det.js && node out/det.js
msc build tools/rulesProbe.ms --os=solana --output=out/rulesProbe.so
msc build sim/env/ffi.ms --app=lib --release --output=out/env/libhibernal.dylib   # train/ rebuilds it when stale
cd train && uv run python bc.py && uv run python ppo.py && uv run python evaluate.py --policy ppo
```

## Naming

- **camelCase for file names and identifiers** whenever the language allows: `winOdds.ms`, `rulesProbe.ms`, `rewardSnapshot`, `fightsOutToday`. Snake_case only where the other side dictates it (Solana account field names in docs, C symbols in shims).
- **Spell names out.** A reader should not have to ask what a name means: `winChanceBps` not `pwinBps`, `attackExpectedValue` not `attackEv`, `defenderHarvest` not `harvestD`, `winOdds.ms` not `pwinMc.ms`. Abbreviate only when the full name would be unreasonably long, and then only with terms `docs/BRIEF.md` already uses (`BPS`, `HP`, `HBRN`, `crit`).
- Constants stay `UPPER_SNAKE`. Struct and enum names `PascalCase`.

## Rules for `rules/`

- Integer only: `int32`, `int64`, `uint64`. No floats, no strings, no arrays, no allocation. It has to run on chain.
- Every rule change is measured, not argued: rerun `sim/curve.ms` and `msc test rules/index.ms`, and update the numbers in `docs/BRIEF.md` §3.6 / §6.
- Tuning knobs live at the top of their file as `export const`. Scalar module consts fold under `--os=solana` (R12). A struct, `T[N]` or string module const is `FREESTANDING E02` until `SOLANA-BUGS.md` #8, so knobs stay scalar.

## Code style

`~/metascript/docs/CODE-STYLE.md` is the style guide: `match` over if/else ladders, `Result<T, E>` over sentinels, `for..of` then indexed `for` then `while`, `struct`/`enum`/`BitSet` over classes and masks, sized integers with explicit `as`. It also lists every doc-vs-compiler discrepancy measured on msc 0.2.54. Read it before writing or reviewing `.ms`.

Repo-specific on top of it:

- `rules/` must satisfy the on-chain column of CODE-STYLE §11: no allocation, no module-scope `let`, no `String(uint64)` or `process.exit()` in code that reaches the chain (R13).
- `sim/determinism.ms` must print the same digests and engine version on native and `--target=js`; a rule change that moves a digest needs a reason in the commit.
- Host entry files end with `process.exit(main());`, chain builds with bare `main();`.

## Compiler boundary

A MetaScript or runtime limitation follows the workspace compiler boundary in `~/metascript/CLAUDE.md`, read it first: smallest repro on the installed `msc`, a card in `~/metascript/.inbox/compiler/`, the blocked work parked at a named site that points at the card. Nothing is edited, built or committed under `~/metascript/recompiler` or a worktree of it from here.

## Git

Never commit without asking. When asked, use `/split-commit`.
