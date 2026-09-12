# Hibernal

Tamagotchi that permanently dies, one per Seeker Genesis Token, fully on Solana L1. Everything is MetaScript end to end: on-chain program, native core, sim. Design: `docs/BRIEF.md`. Plan and package status: `docs/ROADMAP.md`. Renderer: `docs/RENDERER-BRIEF.md`.

## Layout

```
rules/     game rules, integer only, compiled 3 ways (native, js, --os=solana)
sim/       harnesses on rules/ (msc run)
tools/     probes and chain harnesses
program/   on-chain program (--os=solana)
native/    renderer, hud, brain → libhibernal.so
android/   Kotlin shell
docs/      briefs and roadmap
```

## Commands

```bash
msc test rules/index.ms                              # rules suite
msc run sim/curve.ms                                 # combat curve vs BRIEF §6.7
msc run sim/determinism.ms                           # digests; must match the js build:
msc build sim/determinism.ms --target=js --output=out/det.js && node out/det.js
msc build tools/rulesProbe.ms --os=solana --output=out/rulesProbe.so
```

## Naming

- **camelCase for file names and identifiers** whenever the language allows: `pwinMc.ms`, `rulesProbe.ms`, `accSnapshot`, `fightsOutToday`. Snake_case only where the other side dictates it (Solana account field names in docs, C symbols in shims).
- Constants stay `UPPER_SNAKE`. Struct and enum names `PascalCase`.
- `yield` is reserved, so the stat is `yield_`.

## Rules for `rules/`

- Integer only: `int32`, `int64`, `uint64`. No floats, no strings, no arrays, no allocation. It has to run on chain.
- Every rule change is measured, not argued: rerun `sim/curve.ms` and `msc test rules/index.ms`, and update the numbers in `docs/BRIEF.md` §3.6 / §6.
- Constants that are tuning knobs live at the top of their file as `export const`.

## MetaScript traps hit in this repo (msc 0.2.54)

- The test assertion keyword is `assert`, not `expect` as `LANG-TEST.md` says.
- `|=`, `&=` do not parse. Write `a = a | b`.
- A struct literal cannot be assigned to an existing variable or `out` param: bind it to a typed `const` first, then assign.
- Under `--os=solana`: module-scope `const` (exported or not) fails the link (`relocation refers to a symbol in a discarded section`); `enum` members are fine. `String(uint64)` and `process.exit()` abort on chain. Tracked as R12 / R13 in the roadmap.
- Nothing calls `main()` for you. End entry files with `process.exit(main());` on host, bare `main();` for the chain build.

## Git

Never commit without asking. When asked, use `/split-commit`.
