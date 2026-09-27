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

- Rust `-O3` is the floor. MetaScript-generated C for `rules/policy.ms` costs 21–27 CU per weight on msc 0.2.55 since policy format 7 (package 6, §6), about 2× the floor.
- The fight settles in the VRF callback `consume_fight`, a separate transaction, so the budget of `act` belongs to the brain and its bookkeeping.
- Executed weights, not stored weights, are what cost CU: a network scored once per candidate target costs its size times the number of candidates.
- Working limit: about 40–50k executed weights per `act` at the Rust rate. At the measured MetaScript rate that is 1.2–1.5M CU, the whole transaction; the current policy executes at most 20,192 weights (590k CU), and account parsing, observation, tick and writes are unmeasured.

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
| 3 | `sim/world.ms`: 20 blocks × 10 pets, 4 `act` rounds per epoch, heir takes a dead pet's slot, 120-epoch episodes | done 2026-09-17, below |
| 4 | `sim/env/`: observation, batched env with a C ABI, teacher actions; `train/`: behavior cloning, PPO, snapshot pool; `rules/policy.ms`: int8 inference used for every evaluation | done 2026-09-17, below: the pipeline runs end to end, the policy is not tuned |
| 5 | `sim/env/feel.ms`: feel metrics counted in MetaScript; reward terms per persona; PFSP pool weighting; three seeds | done 2026-09-17, below: loss aversion makes the Cautious persona, PFSP and a revenge bonus measured no gain |
| 5b | A world that lives and dies: lifespan and heirs (`BRIEF.md` §3.7), keystones per persona, grudge as a target feature, staggered claims; BC and PPO re-measured on it | done 2026-09-23, below: the numbers of packages 4 and 5 are on older engines and superseded |
| 6 | `rules/policy.ms` and the observation on chain (ROADMAP S4), CU measured in LiteSVM | inference done 2026-09-26 and run in the MagicBlock ER on devnet 2026-09-27, below: every head in one `act` costs 590k CU, chain logits equal host; the observation waits on the account layout |

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
- Compiler bug found on the way, JS backend: `pet.tickTo(global, epoch)` with a `uint64` `for` counter throws `Cannot mix BigInt`. Traced to two defects, `AI-BUGS.md` #3 and #4.

### Package 3: the world and the teacher — Measured

`sim/world.ms` holds the state (`Pet[]`, `GlobalConfig`, death and level-milestone epochs per slot) and the steps: `beginEpoch` (tick every living pet, hatch an heir into a slot whose pet died at least `GRACE_EPOCHS` ago, lineage +1), one `act` as three head steps `applyEconomy` → `applyNode` → `applyAttack`, and `endEpoch` (bury, split the wallet to block-mates). `sim/teacher.ms` is the heuristic teacher on top of `brain.ms` personas (slot ÷ 3 picks Cautious, Greedy, Vengeful) and `playEpisode(blocks, epochs, seed)`.

- Each head gets its own mask on the state the previous head left, exactly as the four policies run inside `act`. A single joint mask per `act` was measured wrong: eating lowers the burrow and turns an attack the joint mask allowed into `Broke`. The env in package 4 therefore exposes three observe/step pairs per `act`, not one.
- A rejected action counts in `stats.illegal` and applies nothing. The teacher runs 200 pets × 120 epochs with `illegal == 0`.
- Teacher stake: `chooseStake` (continuous) → the highest `StakeLevel` whose price fits the budget; odds from `winChanceAgainst` with 64 runs (`TEACHER_ODDS_RUNS`), attack only above the persona threshold and with positive expected value.
- Measured (`msc run sim/episode.ms`, seed 7, 26 s native): 1,892 fights, 82% attacker wins, 0 deaths, median level 10 on day 6 and 20 on day 29 (`GAME-DESIGN.md` §6 targets 6–7 and 30), wealth p90 ×1.17 and top ×1.22 of the median (flat: no talent, no items yet).
- Checks: `msc test sim/teacher.ms` 348/348; `sim/determinism.ms` gained a fifth digest `world` (2 blocks × 30 epochs), identical on native and `--target=js`; the `uint64` dot-call bug is avoided by an `int32` day counter cast at the call.
- Not yet: owner scripts (feed, talk, SKR), talent, items, bonding; each lands as a rule group plus a teacher rule plus a digest change.

### Package 4: observation, batched env, training pipeline — Measured

`rules/logarithm.ms`, `rules/oddsTable.ms` (+ generated `rules/oddsTableColumns.ms`), `rules/policy.ms`; `sim/env/observe.ms`, `batch.ms`, `actor.ms`, `ffi.ms` (+ `buffer.c`); `sim/digests.ms`; `tools/oddsTableGen.ms`, `sim/oddsError.ms`; `train/` (uv, numpy 2.4, torch 2.14).

**Odds table.** The proposed grid over `might_a/might_d × grit_a/grit_d` was measured first: mean error 580 bps on the stats reachable today, because fight HP is `800 + 7 × grit` and mods are outside the key. The table is keyed on *pressure* instead: expected damage per round (roll mean, Glass Cannon, crit, dodge, haste, bleed, armor) minus the target's lifesteal, over the target's fight HP, in bps. Key = `log2(pressure_a / pressure_d)` in eighths of an octave (41 columns, ±2.5 octaves, linear interpolation) × `log2(pressure_a + pressure_d)` in half octaves (8 rows). One `uint64` per column, one byte per cell at 50 bps: 41 `match` arms, no array, no allocation.

| Lookup, against 2,000-run Monte Carlo on reachable stats (4,000 pairs) | mean | p90 | max |
|---|---|---|---|
| table, mods sampled | 188 bps | 380 | 780 |
| table, no mods | 261 bps | 470 | 810 |
| the teacher's own 64-run Monte Carlo (binomial noise) | ~500 bps | | |

- Generated by `msc build tools/oddsTableGen.ms --release --output=out/oddsTableGen && out/oddsTableGen > rules/oddsTableColumns.ms`: 400,000 pairs × 200 fights in 31 s (2.6M fights/s). Regenerate when `rules/fight.ms` changes; `rules/oddsTable.ms` has a test that fails above 300 bps.
- `log2Times32` (`rules/logarithm.ms`) is the shared fixed-point log: msb by binary search, 5 fraction bits by squaring. Money features are quarter octaves of a thousandth of a token.
- Full-stat combatants (speed, armor, accuracy, lifesteal, bleed all random) key worse, about 550 bps. None of those stats is reachable in the 24-node tree; re-measure with the 64-node tree.

**Observation** (`sim/env/observe.ms`). Every feature is an integer in −127..127, scaled where it is computed, so training and the chain read the same numbers. Self block 32 (hearts, meals afforded, log harvest and burrow, level, points, region, persona, attacks left, age, shield, round, stats, mods, small-meal cost, living mates, hunger tomorrow, richest attackable harvest, threat = best table win chance of any mate that may attack me). Node head: 25 candidates × 16 (hold flag, own region, nodes it opens, notable, keystone, cost, stat deltas from `Stats.fromTree`, mods gained). Attack head: 11 candidates × 12 (present, hold flag, table win chance, expected value at each of the four stake levels, harvest, shield, fights in, attacked today, hearts). Legal masks are one 0/1 per action id.

**Batched env** (`sim/env/batch.ms`, C ABI in `ffi.ms`, 20 `hibernal_*` symbols). A row is one block of one world; all blocks step the same turn and head together, so one episode is 120 × 4 × 10 × 3 = 14,400 calls whatever the batch width. `World.inRound` draws every block's turn order afresh each round from the world seed, and `hibernal_actors` tells Python which slot acts in each row, so a rollout still follows one pet per trajectory. The order was fixed at 0 → 9 before engine `8940418975996108247`: the income the tick pays at dawn waited unbanked until the pet's own first turn, and PPO learned to rob the same later seat every day. 98.8% of its round-0 attacks hit a later seat, seat 6 was robbed before its first turn on 57–66% of days, and it held 93 of the 97 starved pets across PPO seeds 5–7 and the teacher (engine `1490032922165168608`, 16 worlds each). With the drawn order the three seeds starve no pet in 16 worlds each. Blocks only meet through commutative sums in `GlobalConfig`; the one order-dependent input was the fight seed (`world.draws`), now `fightSeed(mix(seed, block), attacker, defender, epoch, round)` as on chain. That moved the `world` digest once. A test plays the teacher through the batch, block-parallel, and compares every pet and the global state with `playEpisode`: equal.

- Each (world, slot) has a controller: the learner (Python), the teacher, or one of 8 loaded int8 policies run by `rules/policy.ms` inside the env. Rows the learner does not control come back with an empty mask.
- Reward `[strawman]`: change in `score = (harvest + burrow + gear resale value) in thousandths of a token + 20,000 × hearts`, a dead pet scores −500,000 flat. Gear counts at the price `SellItem` would fetch (2026-09-25); without it, selling gear raised the score at once while the income it gave up stayed invisible. Potential-based on purpose: "−20 per heart lost" alone was checked on paper and punishes eating (the floor at 2 hearts never loses a heart; a fed pet loses one every day). Weights come from `RewardWeights.of(persona)`, all three equal for now. `done`: 1 died, 2 truncated at the end of the episode, then every world reopens with a new seed.
- Engine version = digest of the six `sim/determinism.ms` digests (`fights`, `tree`, `economy`, `odds`, `world`, new `observe`). It is returned by `hibernal_engine_version`, written into every policy blob and checkpoint; `hibernal_load_policy` answers −5 (`WrongEngine`) and `checkpoint.load` raises on a mismatch. Measured by loading a blob with a zeroed version.

| 1,280 rows (64 worlds), release build | economy | node | attack |
|---|---|---|---|
| observe + mask, young world | 1.7 ms | 3.9 ms | 3.8 ms |
| observe + mask, grown world | 5.5 ms | 7.8 ms | 11.9 ms |
| step | 0.3 ms | 0.3 ms | 0.5 ms |
| teacher actions (64-run odds) | 0.7 ms | 1.2 ms | 21 ms |

- 360k row-steps/s with a hold policy, 77k with the teacher; a ctypes call is under 1% of a step (Under Realm: 91% at batch 1). A full teacher episode through the FFI: 14,400 calls, 0 illegal, 0 teacher actions outside the mask, 12,800 truncated rows, 54.7k `$HBRN` per pet. `msc build sim/episode.ms --release` plays 200 pets × 120 epochs in 1.4 s (26 s in debug).
- The library keeps module state; Python calls `MsMain()` once after `dlopen`.

**One policy path** (`rules/policy.ms`, `train/hibernalTrain/model.py`). Layers are `int8` weights, `int32` biases and a shift; hidden activations clamp to 0..127; the blob is 3,839 bytes (16-byte header with magic, format, engine version) and reads through `Span<uint8>` with caller-owned scratch, no allocation. Shapes as §4: economy 32 → 32 → 5, node (8 self + 16 candidate) → 32 → 1, attack (12 self + 12 candidate) → 32 → 16 → 4 with hold as an eleventh candidate; which self features each head gathers is read from the library (`hibernal_self_input`), not retyped in Python. The PyTorch forward is the same arithmetic with straight-through gradients (weights rounded to 1/128, activations floored to 1/128), so the network that trains is the network that ships: 124,702 legal logits compared over an episode with weights scaled ×3 to force clamping, 0 differ. Evaluation (`train/evaluate.py`) only loads the blob and lets the env play it.

- Current shape (engine `14428871617754506317`, 2026-09-25): 40 self features (the 32 above with hunger tomorrow replaced by pantry hearts, plus Relentless and Berserker flags, bonding, gear bonus, weakest item bonus, mints afforded, hunger share of max hearts, food buys left); economy head 40 → 32 → 9 (Rest, Bank, Buy×3, Eat×3, Mint), decoded through the portion-size fold (`foldPortionSizes`); node and attack heads unchanged; blob 4,463 bytes, `POLICY_FORMAT` 2.

**Behavior cloning** (`train/bc.py`, 16 worlds = 1.5M economy, 51k node, 40k attack decisions with more than one legal action, 4,000 steps per head, 3 min):

| Head | Held-out accuracy | Macro recall |
|---|---|---|
| Economy | 99.7% | 0.99 |
| Node | 87.5% | 0.86 |
| Attack | 65.8% | 0.33 |

- Attack accuracy is bounded: the teacher ranks targets with a 64-run odds estimate the student cannot see. Behavior is what counts: played by the int8 inference, 4 worlds each, the cloned policy has 0 illegal actions, 0 deaths, level 20, 9.3 fights per pet at 84% attacker wins (teacher 9.5 at 83%).
- In a world of one policy the mean score is fixed by emission (54,742 for both), so strength is read in mixed worlds, five slots each per block: clone 53,358 vs teacher 56,126 `$HBRN` per pet (−4.9%).
- `bc.py --studentRounds` (default 2): after cloning the teacher's own play, the clone plays whole episodes (argmax over `hibernal_policy_logits` and the legal mask, the choice the env makes) while the teacher labels every state it reaches, and every head retrains on the union. On the states the clone reached, its node head had agreed with the teacher 32% of the time and its Vengeful pets took Cannibal in 3 lives against the teacher's 641; after one round 97% and 640 (engine `8940418975996108247`). It does not teach buying a Small or Medium portion when Large is out of reach: the teacher does that in about 200 of 3.7M economy decisions, so the clone and PPO still rest instead.

**PPO and the snapshot pool** (`train/ppo.py`, `hibernalTrain/rollout.py`). One rollout is one full episode of 8 worlds (160 rows, 14,400 calls, 10–18 s); every pet is its own trajectory of 1,440 decisions (GAE, γ 0.999, λ 0.95, a float critic on the self block that never ships). Only decisions with more than one legal action enter the policy loss (about 450k economy, 16k node, 14k attack per rollout); a reward that lands on a dead pet's row is folded into its last live decision. A quarter of the worlds are pure self-play; in the rest the odd slots of every block are played inside the env by the teacher or by a pool of up to six int8 snapshots of the learner, so opponents share a block with the learner. All numbers below are argmax play through `rules/policy.ms`, 4 worlds per row, 0 illegal actions and 0 deaths everywhere:

| Policy | Mixed world, policy vs teacher, `$HBRN` per pet | Own world: fights per pet, attacker wins |
|---|---|---|
| Teacher | | 9.5, 83% |
| Cloned | 53,358 vs 56,126 (−4.9%) | 9.3, 84% |
| PPO, 16 rollouts, lr 3e-4, 2 passes | 53,743 vs 55,756 (−3.6%) | 9.6, 81% |
| PPO, 30 rollouts, lr 1e-3, 4 passes, at least 16 minibatches per head (10 min) | 55,952 vs 53,547 (+4.5%) | 5.7, 71% |

- The first run took 4 gradient steps per rollout on the attack head (14k samples in 8,192-sample minibatches) and barely moved; sizing minibatches per head fixed that. In training the learner's share went 53,402 → 55,297 while its opponents fell 56,076 → 54,195.
- The stronger policy fights 40% less and wins less often per fight. Whether that reads as a persona or as a flat "attack only when it pays" pet is a feel question, not a strength one: it is the first thing the §5 metrics have to answer in package 5.
- Not tuned: 30 rollouts, one seed, equal reward weights for the three personas.

Compiler findings on msc 0.2.54, worked around in place; the first two are written up with bounded triggers in `AI-BUGS.md`:

- `value < 0 || value > (high)` parses as a generic call `value<…>(high)`: a C compile error, and on JS a build that throws at run time while `msc check` passes; written as `>= && <=`.
- An extension named like a prelude method (`has`, `isEmpty`, `size`) is lost behind a barrel unless its module is the first `export *` (`Property 'has' does not exist on type 'Tree'`; `touches` and `withNode` next to it resolve); `sim/env/observe.ms` imports `{ has, touches }` from `rules/tree` directly.
- `Math.abs` returns `float64`; integer code uses `Math.max(a - b, b - a)`. A left shift of a negative `int32` panics in debug; `rules/policy.ms` assembles little-endian words by multiplication.

Not in package 4: reward weights per persona, the feel metrics of §5 (starving with money, revenge rate, attacks at low win chance), sampling on chain (§8.4; evaluation is argmax), PFSP weighting of the pool, the social head, CU of `observe` + `policy` in LiteSVM.

### Package 5: feel metrics, reward per persona, pool weighting — Measured

`sim/env/feel.ms`, hooks in `sim/env/batch.ms`, two more C symbols in `ffi.ms` (`hibernal_feel`, `hibernal_reward`, 19 in all); `train/hibernalTrain/feel.py`, `train/evaluate.py` rewritten, `train/ppo.py` (`--reward`, `--pool`, `--alternate`, `--threads`). `msc test sim/env/ffi.ms` 380/380; the six digests and the engine version are unchanged on native and `--target=js`: the reward lives in `batch.ms`, which `sim/digests.ms` does not import, so every package 4 checkpoint still loads.

**Feel counters** (§5). 20 counters per (world, pet), counted where the rules are: `momentOf` keeps the acting pet and its target as they were before the action, `note` reads the world after it. Attacks, wins, table win chance, stake level and share of the burrow, attacks under 40% and under the persona's own threshold (`Persona.of`), robbed and avenged (an attack on the last robber within 3 epochs; the grudge is sim state, `Pet` is untouched), meals and hearts when eating, hearts held per day, banks, and deaths sorted by what the pet could still have eaten (`Larder`: nothing, harvest it never banked, a full small meal in the burrow). Python only divides and prints; "persona told from one pet's log" is a nearest-centroid guess over eight per-pet ratios, balanced recall, chance 0.33.

**The even/odd split was biased.** Even slots hold one Fighter start, odd slots two, so "cloned −4.9%" in package 4 was the seat, not the policy. `evaluate.py` now plays four groups (policy world, teacher world, policy on even slots, policy on odd slots) and reads strength from the wealth counter, not from the reward: cloned −0.1%, package 4 PPO +7.0% (57,155 vs 53,400 `$HBRN` per pet). `ppo.py --alternate` trains on both seats.

Baseline, own worlds, 16 worlds per run, 0 deaths and 0 illegal actions everywhere:

| | Teacher | Cloned | PPO package 4 |
|---|---|---|---|
| Starved with a meal in the burrow / with unbanked harvest | 0 / 0 | 0 / 0 | 0 / 0 |
| Attacks under 40% table win chance | ≤ 0.6% | 0 | 0 |
| Cautious attacks under its own 70% | 8.5% | 6.5% | 23.5% |
| Avenged within 3 epochs, Cautious / Greedy / Vengeful | 0.2 / 4.9 / 4.7% | 0.1 / 3.9 / 5.6% | 0.5 / 30.0 / 14.5% |
| Fights per pet, Cautious / Greedy / Vengeful | 6.9 / 10.6 / 11.7 | 7.0 / 10.1 / 11.6 | 3.4 / 7.1 / 7.5 |
| Hearts held per day | 3.4 / 3.2 / 3.2 | 3.4 / 3.2 / 3.2 | 2.4 / 2.2 / 2.2 |
| Persona told from one pet's log | 0.75 | 0.71 | 0.66 (0.59 mixed) |

- The teacher has no grudge logic, so its 0.2–5% is what chance looks like. Greedy and Vengeful are one behaviour in the teacher too (recall about 0.4 for Greedy): their thresholds are 50% and 45% and nothing else differs in play.
- The package 4 PPO pet stopped eating (6 meals per pet against 17) and lives on the floor's auto-meal: the potential-based reward is indifferent between 2 and 4 hearts held.

**Reward terms** (`RewardWeights`, `shaping` in `batch.ms`). On top of the change in score: `comfort` pays every spare heart above the pet's floor once a day; `lossAversion` charges a lost stake a second time. Weights are set per persona at run time (`hibernal_reward`, `ppo.py --reward cautious.comfort=5000,…`), so variants train in parallel on one library; the measured set is the default in `RewardWeights.of`: Cautious death 1,500,000, comfort 5,000, loss aversion 10,000 bps; Greedy and Vengeful comfort 1,000, no loss aversion. `RewardWeights.flat()` is the package 4 reward.

Three seeds (5, 6, 7) from the same clone, 30 rollouts, lr 1e-3, 4 passes, `--alternate`, mean ± standard deviation:

| Reward | Mixed world vs teacher | Cautious under its own 70% | Persona told, own / mixed | Hearts held C / G / V |
|---|---|---|---|---|
| flat (package 4) | +4.7 ± 3.7% | 19.8 ± 16.7% | 0.79 ± 0.05 / 0.69 ± 0.08 | 2.4 / 2.3 / 2.3 |
| **comfort 5,000 / 1,000 / 1,000 + Cautious loss aversion** | **+7.07 ± 0.12%** | 1.7 ± 2.9% | 0.83 ± 0.04 / 0.79 ± 0.03 | 2.6 / 2.4 / 2.3 |
| comfort × 2, same loss aversion | +6.93 ± 0.15% | 0.1 ± 0.1% | 0.83 ± 0.07 / 0.81 ± 0.04 | 2.6 / 2.4 / 2.3 |
| comfort × 4, same loss aversion | +4.80 ± 0.96% | 15.8 ± 5.5% | 0.77 ± 0.08 / 0.74 ± 0.05 | 5.6 / 3.4 / 3.2 |
| as the bold row, prioritized pool | +6.83 ± 0.25% | 0.0 ± 0.0% | 0.84 ± 0.06 / 0.77 ± 0.01 | 2.5 / 2.3 / 2.2 |

- Loss aversion is what makes the Cautious pet: it attacks 2.8 times per pet at 88% mean table odds (flat: 3.7 at 81%), and the run-to-run spread of the whole policy collapses with it. A single seed is not evidence here: the flat reward gave +0.4%, +2.7% and +7.0% on three single runs, and 5% to 37% Cautious attacks under threshold.
- Comfort does not move hearts held until × 4, and there it costs two points of strength and the Cautious discipline. Pets still live one heart above the floor; nothing in §5 calls that a failure, but it reads as a hungry pet. Open.
- A risk-seeking Vengeful (loss aversion −2,500 bps, one seed) fought 8.1 times per pet against 7.2 and was no easier to tell from Greedy (0.76 / 0.70). Not kept.
- 0 deaths, 0 illegal actions, 0 attacks under 40% in every evaluated world of every run; a few pets die while sampling in training.

**Pool weighting** (`ppo.py --pool prioritized`). Opponent drawn with weight `(1 − p)² + 0.05`, `p` a running share of worlds where the learner's seats end richer than the snapshot's; the most beaten snapshot is the one replaced. No gain at 30 rollouts (table): seven snapshots in a run leave nothing to prioritize. Re-measure on runs of a few hundred rollouts.

**Revenge, measured negative.** A policy cannot avenge what it cannot see, so a branch moved the grudge into `World` and added a thirteenth target feature (attack input 25, blob 3,871 bytes, only the `observe` digest and the engine version move; clone retrained to the same accuracy). One seed each: no bonus 17.1% avenged by Vengeful pets in their own world (5.7% mixed), 100 `$HBRN` for a won revenge 16.7% (10.0%), 300 `$HBRN` 20.8% (11.1%), 100 `$HBRN` for any strike back 15.9% (10.9%). Inside the seed noise. The robber is usually the stronger pet and every policy stakes the whole cap, so a revenge is a bad bet that a bonus of one loot does not fix. Not merged (it would cost a `Pet` field on chain for nothing); the patch is `out/feel/grudge.worktree.patch`. What it needs first is a denominator that counts only revenges that were legal and affordable, and a stake head that uses the lower levels.

Not in package 5: a persona signal that separates Greedy from Vengeful, hearts held above the floor, long self-play, sampling on chain (§8.4), the social head, CU in LiteSVM.

### Package 5b: a world that lives and dies — Measured, superseded by 5c

`rules/` gained lifespan, decline and the heir package (`BRIEF.md` §3.7) and Glass Cannon keeps its hearts (§3.9). In `sim/`: each persona's teacher takes only its own keystone (`sim/teacher.ms`), the grudge moved into `World.robberOf` with the thirteenth target feature above (so it did merge, in the Vengeful teacher's quarter-stake strike back), and `World.staggered` claims the 200 first pets over days 1–30. Engine `13955993101127523059`.

Why the earlier numbers are superseded: before the keystone change every teacher pet took the Pacifist keystone, and on seed 7 all 200 were Pacifist by day 20 with 0 fights on days 20–120, so every number of packages 4 and 5 came from days 3–20. The world before `World.staggered` hatched all 200 pets on day 0, killed them together on day 90, stood empty on days 90–96 and hatched 200 heirs on day 97. Every checkpoint trained before this engine refuses to load.

Measured on tree `49edc902` (commit `6b32f90`), default `RewardWeights.of`, all runs in this worktree:

```bash
cd train && uv run python bc.py --envs 16 --steps 4000
uv run python evaluate.py --policy teacher        # and --policy bc, v5, v6, v7
uv run python ppo.py --learningRate 1e-3 --passes 4 --iterations 30 --threads 2 --seed $seed --alternate --pool uniform --name v$seed
```

**Lifecycle**, 4 worlds of one controller each, seed 9001, per-epoch `hibernal_stats` (throwaway probe, not kept). The episode resets inside day 120, so the probe sees days 1–119:

| Controller | Fights per world | Fights per day, days 1–30 / 31–60 / 61–90 / 91–119 | Days without a fight | Natural deaths per world | Heirs per world | Empty days | Illegal |
|---|---|---|---|---|---|---|---|
| Teacher | 14,152 | 65 / 177 / 138 / 92 | 1–6 | 194, days 91–119, ≤ 7 a day | 154, days 97–119, ≤ 7 a day | 0 | 0 |
| Cloned | 13,974 | 66 / 177 / 134 / 88 | 1–6 | same | same | 0 | 0 |
| PPO seed 5 / 6 / 7 | 12,416 / 12,432 / 11,704 | 65 / 173 / 102 / 74 · 62 / 175 / 103 / 74 · 58 / 170 / 97 / 64 | 1–6 · 1–6 · 1–7 | same | same | 0 | 0 |

- Days 1–6 have no fight by design, not by a bug: `World.staggered` gives slot 0 of the 20 blocks days 1–3 and slot 1 days 4–6, so until day 7 no block holds two pets outside the 3-epoch newborn shield (`BRIEF.md` §3.2). The first fights come on day 7 (7 of them, then 14, 20, 34). The "fights every day" condition does not hold for days 1–6, and it is not special-cased.
- Deaths and heirs do not depend on the controller: every pet ages out (no starved and no bitten death anywhere), and the heir comes back after the 7-epoch grace.

**Behavior cloning**, 16 worlds (1.24M economy, 1.02M node, 381k attack decisions with more than one legal action; collection 222 s, 7 min in all):

| Head | Held-out accuracy | Macro recall |
|---|---|---|
| Economy | 98.6% | 0.96 |
| Node | 98.8% | 0.78 |
| Attack | 88.8% | 0.51 |

**Strength**, `evaluate.py`, 16 worlds per run (4 per group), wealth counter:

| Policy | Own world, `$HBRN` per pet | Mixed world, both seats, vs teacher |
|---|---|---|
| Teacher | 53,665 | −0.8% (teacher against itself: 53,461 vs 53,895; the seat noise) |
| Cloned | 55,717 | −4.5% |
| PPO seeds 5 / 6 / 7 | 56,956 / 56,845 / 57,119 | +68.1 / +62.3 / +65.1% |
| PPO mean ± sample standard deviation | +6.2 ± 0.3% over the teacher | +65.2 ± 2.9% |

- The mixed gap is the learner preying on the teacher, not a richer economy: in mixed worlds each teacher Greedy pet is robbed 127–131 times against 83 in its own world, and the teacher Cautious pet takes 20–22% of its attacks under its own 70% table odds against 5% in its own world.
- Reproducible: seed 5 trained twice gives the same `v5.policy` byte for byte (sha1 `ac9c01fd…`) and the same evaluation table; evaluation of a fixed blob is deterministic (the teacher rows are identical across all five evaluation runs).

**Feel**, own worlds, 0 illegal actions, 0 attacks under 40% table odds for every learned policy, every pet aged out:

| | Teacher | Cloned | PPO, mean ± sd of seeds 5–7 |
|---|---|---|---|
| Starved: total / with harvest unbanked / with a meal in the burrow | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 in every seed |
| Bitten to death | 0 | 0 | 0 |
| Attacks under 40% table odds, C / G / V | 0.0 / 0.7 / 0.2% | 0 / 0 / 0 | 0 / 0 / 0 |
| Cautious attacks under its own 70% | 5.3% | 1.7% | 0.3 ± 0.3% |
| Fights per pet, C / G / V | 39.8 / 106.8 / 77.7 | 40.9 / 107.1 / 73.2 | 44.3 ± 3.0 / 77.8 ± 1.0 / 68.1 ± 3.2 |
| Mean table odds of its attacks, C / G / V | 86.6 / 68.9 / 75.6% | 86.8 / 67.7 / 64.7% | 92.0 / 88.5 / 87.7% |
| Meals per pet, C / G / V | 44.0 / 42.9 / 35.8 | 41.8 / 42.7 / 37.9 | 35.7 ± 5.3 / 28.9 ± 4.7 / 29.2 ± 4.3 |
| Hearts held per day, C / G / V | 5.78 / 4.95 / 4.98 | 5.79 / 4.71 / 4.74 | 4.91 ± 0.48 / 4.39 ± 0.59 / 4.50 ± 0.37 |
| Vengeful avenged within 3 epochs | 2.4% | 4.1% | 0.1 / 0.1 / 0.0% |
| Persona told from one pet's log, own / mixed | 0.95 / 0.96 | 1.00 / 0.98 | 0.79 ± 0.10 / 0.74 ± 0.11 (0.86, 0.68, 0.83 / 0.62, 0.77, 0.83) |

- With its own keystone each teacher persona is now told apart from one pet's log (Cautious and Greedy 1.00, Vengeful 0.85); in package 5 the teacher read 0.75 and Greedy was not separable from Vengeful. The clone copies it.
- PPO makes every persona pickier and more alike: all three attack at 88–92% table odds, Greedy fights 27% less than its teacher, and recall falls to 0.79 with one seed at 0.68. Cautious is the persona that loses its identity (recall 0.75, 0.50, 0.75).
- PPO strikes back almost never (0.0–0.1% of Vengeful pets' robberies), where the teacher's rule gives 2.4%.
- Food is not a pressure: nobody starves in any run, and pets hold 4–6 hearts on a floor of 2.

Not measured here: the reward-variant and pool rows of package 5 on this engine, runs longer than 30 rollouts, self-play.

### Package 5c: the game-design world — Measured, superseded by 5d

The rules now carry the game-design lane of `docs/SIM.md` (2026-09-24 and 25): pantry, quota and bites by stake, hearts that scale with max hearts, level growth and talent, tree v2, drawn turn order, D34 weight `(work_power + 40)²` with the reward floor, food ×7, late-level XP, the owner layer (bonding, owner food, growth, insurance, gifts), items with mint, wear, skills and `SellItem` (D35), wild pets on empty slots (D37), rage against a repeat robber, absolute bites. The numbers and the reasons for each knob live in `docs/SIM.md`; the rules as built in `BRIEF.md`. The policy blob is format 3, 4,499 bytes: 40 self features, economy head 40 → 32 → 10.

Training additions, each measured on this lane:

- `bc.py --studentRounds 2`: the clone plays whole episodes and the teacher labels what it reaches (package 4 note above).
- Decode folds in `rules/policy.ms`, applied the same way by the env, by PyTorch and later by `act`: an out-of-reach portion size folds into the next smaller one (`foldPortionSizes`), and an eat wish on an empty pantry of a pet that is not full folds into buying that portion (`foldEatIntoBuy`). Without the second fold PPO left a rich, hungry pet resting now and then — its top logit was the illegal eat — and 2 of 3 seeds starved one pet with money (engine `12482136861935123128`, 8 worlds). The fold only works when it is trained: applied at decode to those policies it removed the case but pets bought food whenever their eat logit led, spent 80% of income on food and starved 106–166 pets.
- `ppo.py --imitation w` (off by default): adds `w` × cross-entropy to the teacher's economy label on the states PPO reaches. At `w` = 0.5 without the eat fold it also reached 0 starved with money, but PPO fell to −27 / −8 / +12% against the teacher in mixed worlds and 2.1–4.0 early deaths per 100 lives.

Measured on engine `12482136861935123128`, commit `a516f20` (`~/metacraft/hibernal-train/step15`): `bc.py --envs 8 --steps 4000 --studentRounds 2`, then `ppo.py --learningRate 1e-3 --passes 4 --iterations 30 --threads 2 --alternate --pool uniform` seeds 5–7; `evaluate.py` (16 worlds, 4 per group) and `health.py` (8 worlds, every slot one controller):

| | Teacher | Clone | PPO seeds 5 / 6 / 7 |
|---|---|---|---|
| Illegal actions | 0 | 0 | 0 / 0 / 0 |
| Starved with food or money (evaluate, all groups; health) | 0; 0 | 0; 0 | 0 / 0 / 0; 0 / 0 / 0 |
| Early deaths per 100 lives (health) | 1.5 | 1.3 | 2.3 / 1.8 / 2.0 |
| Own-world wealth, `$HBRN` per pet | 24,511 | 24,279 | 35,470 / 35,425 / 35,415 |
| Mixed world against the teacher | +1.9% (seat noise) | −0.5% | +18.2 / +25.2 / +26.8% |
| Fights per pet | 55.6 | 55.5 | 59.3 / 58.3 / 69.0 |
| Food bill at level 20, % of work income | 56 | 57 | 33 / 33 / 32 |
| Item mints per life, % of income on items | 4.6, 9.7% | 3.9, 8.2% | 2.4 / 2.5 / 2.0, 4–5% |
| Start-region wealth, richest over poorest | 3.2 | 2.5 | 2.6 / 1.6 / 2.4 |
| Persona told from one log, with revenge | 0.86 | 0.91 | 0.63 / 0.67 / 0.61 |

- The learned pets eat far more cheaply than the teacher (a third of income against a half) and still die a little more often, mostly pets whose owner never visits (4.6–5.0 early deaths per 100 lives against 0 for devoted owners).
- Persona recall falls further under PPO than in 5b (0.61–0.67); the reward does not ask for it (`docs/SIM.md` D2).

### Package 5d: market, lineage and a brain that sees tonight — Measured, superseded by 5f

Rules added since 5c, each measured in `docs/SIM.md`: loot by D26 (attacker might against defender grit), the heir package (two heirlooms, a rarer talent roll per generation), a block market (`rules/market.ms`: `ListItem`, `BuyItem`, buyback after three days, 5% to the pot), hunger read from the pet's own stats so gear adds power without hunger, and a teacher that stops re-minting a worn item that still beats an average roll. The policy blob is format 5, 4,731 bytes: 45 self features, economy head 45 → 32 → 12.

Two starvations with money, found on the way and fixed at the root:

- PPO seed 6 on the market engine (step18) let a might-heavy Fighter with 19k `$HBRN` die at dawn: it lived on the owner's morning Large, never bought food, lost two hearts in a failed attack and the night's hunger took the rest before the owner came. The policy saw hearts and hunger as separate features. `DawnHearts` now gives the hearts the pet wakes up with, computed by the tick's own `nightMeals` (`sim/env/observe.ms`).
- The clone on that engine (step19) bought a Small portion where the teacher sells gear first, and sold one round too late. `bc.py --balance 0.5` weights each teacher label by (mean count / count)^0.5, so rare economy labels such as `SellItem` are learned (economy macro recall 0.864 → 0.955, held-out accuracy 0.973 → 0.946); that clone had 0 starved with money. It is the default now.

Measured on engine `17847782851134087884`, commit `52ce235` (`~/metacraft/hibernal-train/step20`): `bc.py --envs 8 --steps 4000 --studentRounds 2` (label balance not yet the default then), `ppo.py --learningRate 1e-3 --passes 4 --iterations 30 --threads 2 --alternate --pool uniform` seeds 5–7; `evaluate.py` (16 worlds) and `health.py` (8 worlds, every slot one controller):

| | Teacher | Clone | PPO seeds 5 / 6 / 7 |
|---|---|---|---|
| Illegal actions | 0 | 0 | 0 / 0 / 0 |
| Starved with food or money (evaluate, all groups; health) | 0; 0 | 0; 0 | 0 / 0 / 0; 0 / 0 / 0 |
| Early deaths per 100 lives (health; absent owners) | 1.75; 3.48 | 1.32; 3.28 | 1.53 / 1.59 / 2.15; 4.40 / 4.47 / 5.73 |
| Own-world wealth, `$HBRN` per pet | 25,777 | 26,147 | 34,156 / 36,806 / 36,330 |
| Mixed world against the teacher | +2.9% (seat noise) | 0.0% | +55.7 / +37.3 / +38.1% |
| Fights per pet | 54.4 | 53.0 | 49.4 / 51.2 / 53.4 |
| Food bill at level 20, % of work income | 52 | 53 | 36 / 37 / 37 |
| Item mints per life, % of income on items; on the market | 9.0, 17.9%; 10.3% | 7.6, 15.6%; 9.1% | 1.1–2.1, 1.9–4.1%; 0.8–1.4% |
| Wealth p90 / median | 1.66 | 1.56 | 2.06 / 1.98 / 2.32 |
| Start-region wealth, richest over poorest | 3.4 | 2.8 | 2.2 / 2.7 / 2.9 |
| Persona told from one log, with revenge | 0.84 | 0.85 | 0.71 / 0.69 / 0.68 |

- PPO barely buys gear, and is right to: a teacher that never mints or buys gear dies half as often and ends richer (`docs/SIM.md` I2). Item value is a design question.
- On the step19 engine, where gear still raised hunger, PPO drove poor neighbours to broke starvation (60–77 per ~2,900 lives): their whole daily income was robbed before their first bank, day after day (`docs/SIM.md` C6). On this engine it is 1.5–2.2 early deaths per 100 lives, still concentrated on pets whose owner never visits.

### Package 5f: owner bank, small gifts, and a brain that buys its own dinner — Measured

The user decided on 2026-09-26 (`docs/SIM.md`): death must be very bad (the reward's death penalty goes from 500 to 30k `$HBRN` of score, Cautious 90k; no pet's money is touched, I2); an owner who opens the app banks 50% of the harvest with an 8-hour cooldown, and the sim opens the app at dawn and at later rounds with 50% (devoted) or 10% (casual) odds (C6); a pet gifts its owner at most 5% of the day's income out of affection (B2); the food bill share is not a target and prices stay (H); earning is the Worker's talent, and a Worker build that only earns and dies to robbers made a build choice (F2); the brain learns survival by itself; persona recall ≥ 0.8 is reported, not gated (D2). Rules added on the way, each measured first: purchases spend the harvest before the burrow; a food purchase the wallet cannot cover even for a Small portion sells the weakest item; appetite stops at 300% (a might talent took single level-20 Fighters to 45–55% of their max hearts a day). Measured and removed at the user's word: a talent on might or grit multiplying the reward weight, and a last-turn survival reflex in `act`. A starvation counts against the brain when the pet ended its day with money for a Small portion; the old "food in the pantry" clause only caught pets that ate their last portion at night and still died. The policy blob is unchanged: format 6, 4,763 bytes.

Measured on engine `16948401298924711931`, commit `7ab5e6f` (`~/metacraft/hibernal-train/step29`; the starvation counter re-read at `ccbae26`, `step29b`): `bc.py --envs 8 --steps 4000 --studentRounds 2` (label balance 0.5), `ppo.py --learningRate 1e-3 --passes 4 --iterations 30 --threads 2 --alternate --pool uniform` seeds 5–7; `evaluate.py` (16 worlds) and `health.py` (8 worlds, every slot one controller):

| | Teacher | Clone | PPO seeds 5 / 6 / 7 |
|---|---|---|---|
| Illegal actions | 0 | 0 | 0 / 0 / 0 |
| Starved with money for a meal (evaluate, all groups; health) | 0; 0 | 0; 0 | 0 / 0 / 0; 0 / 0 / 0 |
| Early deaths per 100 lives (health; absent owners) | 2.10; 5.82 | 3.61; 8.59 | 3.77 / 4.68 / 4.15; 8.96 / 12.05 / 10.31 |
| Starved without money, per ~3,000 lives | 54 | 51 | 97 / 131 / 110 |
| Own-world wealth, `$HBRN` per pet | 31,851 | 31,730 | 39,367 / 40,274 / 41,414 |
| Mixed world against the teacher | −3.5% (seat noise) | +3.4% | +15.1 / +14.3 / +3.4% |
| Food bill at level 20, % of work income | 53 | 52 | 39 / 40 / 40 |
| % of income on mints; on the market | 8.9; 4.9 | 10.1; 6.1 | 6.3–7.6; 2.9–3.5 |
| Income p90 / p99 / top against the median | 3.5 / 4.6 / 6.5 | 3.6 / 4.9 / 7.5 | 2.7–3.2 / 4.0–4.4 / 5.6–6.4 |
| Start-region wealth, richest over poorest | 3.7 | 3.4 | 1.7 / 2.0 / 3.0 |
| Gift to a devoted owner, `$HBRN` a day | 36 | 37 | 31 |
| Persona told from one log, with revenge | 0.85 | 0.84 | 0.71 / 0.74 / 0.75 |

- Package 5e (step24, engine `2583165197786226676`) for comparison: PPO starved without money 122–135 per ~3,000 lives, early deaths 4.7–5.1 per 100, start-region wealth spread 3.9–4.1.
- The death penalty alone barely moved starvation (PPO seed 5 from `bc24`: 122 at 500, 146 / 145 / 113 at 10k / 30k / 100k; at 100k the critic's explained variance fell to 0.69). In PPO worlds the starved are Workers farmed by PPO robbers: robbed 0.6 times a day against 0.3 for the rest, half their income lost, still minting. The user counts that as competition, not a brain fault. Learned brains still let poor pets starve without money about twice as often as the teacher.
- On the way, every starvation with money (step26: one; step27: three) was a pet that knew it would not wake up (`DawnHearts` = 0) and did not buy: Fighters eating 45–55% of their hearts a day who lived on the owner's breakfast, and a bled Worker that kept fighting. With the food sale inside `buy`, the appetite ceiling and no reflex, step29 has none.
- Persona recall of the learned brains (0.71–0.75) sits under the 0.8 the user set; reported, not gated.

### Package 6: the policy on SBF — Measured (inference), observation open

`tools/policyProbe.ms` (`--os=solana`) runs `rules/policy.ms` unchanged over a policy blob that stays in account data (`Ptr<PolicyBlob>` over the account, never copied onto the 4 KB stack), on fixed synthetic inputs: `checkPolicy`, one economy pass, the attack head for 9 targets and the tree head for 6 candidate nodes. `tools/chain/policyLiteSvm.mjs` runs it in LiteSVM 1.4.1 under a 1.4M limit (`npm ci` in `tools/chain` first) and writes the blob for `tools/policyHost.ms`, which runs the same inference natively. Measured 2026-09-26 on msc 0.2.55, engine `16948401298924711931`, checkpoint `p29s5` (step29), compute-unit log cost subtracted:

| Section | Executed weights | CU | CU per weight |
|---|---|---|---|
| `checkPolicy` | – | 24 | – |
| Economy × 1 | 1,856 | 46,086 | 24.8 |
| Attack × 9 targets | 1,376 each | 360,724 (40,080 each) | 29.1 |
| Tree × 6 nodes | 992 each | 182,676 (30,446 each) | 30.7 |
| Every head | 20,192 | 589,510 | 29.2 |

- Chain logits equal host logits: checksum `0xbcdd5dac7cb68f98` for `p29s5` on both, `0x29d5ec3284ae60c3` for `bc29` (589,442 CU). The `.so` is 15,792 bytes.
- MetaScript-generated C costs about 2.5× the Rust `-O3` floor of §2; the cause is unmeasured.
- An `act` that runs every head needs `SetComputeUnitLimit` (590k against the 200k default, 42% of 1.4M). The attack head runs only while attacks are left and the tree head only with points unspent (§4); the economy head alone is ~46k. The social head of §4 is not in the policy.
- The probe's stack buffers are sized with literals that `buffersMatchPolicy` checks against `rules/policy.ms` at run time: on msc 0.2.55 a sized array whose dimension is a named `const` gets size 0 (`~/metascript/.inbox/compiler/2026-09-26-sized-array-dimension-from-a-named-const-is-zero.md`).
- In the MagicBlock ER on devnet (2026-09-27, `tools/chain/policyDevnet.mjs`, program `7a43D3oY82dxX66PuhERp8Zvu8gkAdtH3akDwkHA7uXD`, validator `MAS1Dt9qreoRMQ14YQuhg8UTZMMzDdKhmkZMECCzk57`): 590,655 CU per transaction and the host checksum, the same as LiteSVM, both with the policy account left on L1 and passed read-only (the ER clones it; 436–654 ms wall clock) and with it delegated (154–158 ms). Commit-and-undelegate costs 22,832 CU; the account is back on L1 after 33–46 s with its bytes intact. Weights can stay on L1 and be read from the ER, and a rewrite on L1 reaches it at once: after 46 bytes of the economy layer were flipped on L1, the next ER run (0.28 s later) used them (checksum `0x662e5ba1e8353f24`, equal to the host on the same bytes), and the restore took effect the same way without any ER read in between. New weights are an L1 write, no undelegation. The probe's `write` has no authority check; the program's must.
- The observation now lives in `rules/observe.ms` and reads `Pet` structs (`0cceb88`); `sim/env/observe.ms` builds its input from `World`, and the engine version did not move, so the trained brain sees the same numbers.
- A whole `act` does not fit (2026-09-27, `tools/actProbe.ms` + `tools/chain/actLiteSvm.mjs`, LiteSVM, the current `Pet` struct overlaid on account data, not the frozen layout). The probe replays two real moments of a sim episode and chooses the same actions as the sim. Measured on the typical one (day 40, round 2), before and after `d517e7b`: self features for the economy head 260k → 204k CU, economy head 120k → 111k, self features again for the tree head 260k → 204k and for the attack head 260k → 204k, the nine target rows 359k → 287k; the meter runs out before the attack head (~360k in the inference probe). Per single call after `d517e7b`: `Stats.built` 2.3–3.9k, `pet.stats()` 3.9–5.5k, a win chance from the table with the facing combatant 11.5–13.5k, `dawnHearts` 6.5–9.7k, `legalEconomy` 58–64k. The network is not the cost; `rules/` helpers that recompute stats from the tree, called dozens of times per `act` and the self block three times, are. `d517e7b` (the next allocated node by halving instead of bit by bit) took a fifth off with the engine unchanged. The tick at dawn is not measured: the probe has no tick instruction yet.
- A whole `act` fits since `0239848` (a pet stores its tree bonuses and reads them instead of rebuilding stats from the tree; guard test `b8846b3`) and the act skipping the tree head's observation when no node is open: typical 806k CU, the busiest moment (four open nodes, eight targets) 1.12M, both choosing what the sim chose and writing the same pets. Per call now: `pet.stats()` 1.5k (was 5.5k), `dawnHearts` 1.9k (9.7k); `-O3` with LTO (`--danger`) changes under 1%.
- Two costs of the target, measured in the probe: a signed division is a ~170 CU call to `__divdi3` on `sbpfv3` (platform-tools clang, any `-mcpu`) against ~3 CU unsigned, and `rules/` divides by constants everywhere (100 call sites in the act, 14 in `pressureBps`, which costs 3.4k per call); the platform `rustc` emits the same call, so Rust pays it too, and the linked `__divdi3` is a 158-instruction routine with no native divide. `rules/arithmetic.ms` (`560cca7`) divides through unsigned division with the sign restored, equal to signed division for every input (test on native and JS), and overloads `/` and `%` for `int32` and `int64` under `when (solana)`; every rules file that divides imports it (`d5d6c9f`), because an overload reaches only modules that import it directly. With it the act costs 545k CU typical and 796k at the busiest, same choices and bytes; card `~/metascript/.inbox/compiler/2026-09-27-solana-signed-division-is-a-170-cu-libcall.md` asks std to ship the overloads for every Solana program. The network's 29 CU per weight comes from a bounds check and an `int32` index widening on every `Span` read in `dense`, each kept inside the loop.
- The node and attack heads read 8 and 12 of the 46 self features and none of the threat block; they get `writeSelfForNodeAndAttack` (exactly those features, guard test `407ccd7`) instead of the whole self block (`1cd3f0b`): typical 545k → 516k, busiest 796k → 740k. A signed weight byte is `(raw ^ 128) - 128` instead of a branch (`426027c`): inference probe 589,510 → 548,394 CU (27.2 CU per weight, same checksum `0xbcdd5dac7cb68f98`), act 487k typical, 701k busiest, same choices and bytes.
- Policy format 7 stores a weight as the byte `w + 128` (`WEIGHT_ZERO_POINT`): `dense` reads it unsigned and subtracts `128 × Σ input` once per layer call, so the inner loop loses its two sign-extension instructions (18 a weight, 7 of them the bounds check). The exporter writes it (`train/hibernalTrain/model.py`); `p29s5` and `bc29` re-exported from their `.pt` equal the format-6 blobs with every weight byte XOR `0x80`. Inference probe 548,394 → 514,680 CU (economy 21.1, attack 25.4, node 27.0 CU per weight), checksums `0xbcdd5dac7cb68f98` (`p29s5`) and `0x29d5ec3284ae60c3` (`bc29`) unchanged on host and SBF, `train/checkExact.py` 0 of 63,833 logits differ; act 462,957 typical, 668,446 busiest, same choices and bytes.
- `Math.min`/`Math.max` are calls into another C file under `--os=solana`: the program links with `ld.lld` from separate objects, so nothing is inlined across modules, `--danger` included (the `int32` and `uint64` instances stay out of line in its `.so`). The activation clamp of `dense` is a function of `rules/policy.ms` instead: inference 514,680 → 495,241 CU (~30 CU per activated row), same checksums for `p29s5` and `bc29`; act 448,905 typical, 649,808 busiest, same choices and bytes. The bias read stays four checked byte reads (~35 instructions a row): the SBF backend turns four adjacent byte loads into one `ldxw` (platform-tools clang, C), but the bounds check between them prevents it, and reading them as OR-ed shifts measured 3.5k slower; it waits on the `Span` check card.
- Work the act repeated, removed with the same choices, bytes and engine (act typical / busiest, LiteSVM): a node counts the nodes it opens from its own neighbours instead of all 64 (`opensWith`, ~8k a candidate row; 448,905 / 617,529); the legal nodes are the tree's frontier as one bit mask (`Tree.allocatable`, `legalNodes` 14,116 → 1,226; 444,185 / 591,749); an odds key computes each side's expected strike once instead of twice (`winChanceFromTable` 2,267 → 1,659; 435,658 / 583,344); the attack observation builds the actor's combatant once per phase and each opponent's once (`attackableAs`, `enragedAgainst`; `writeSelf` 26.3k → 20.7k, `attackMask` 6.9k → 2.8k, `writeTarget` 4.7k → 3.8k; 419,064 / 567,623); the node head takes the act's legal mask (566,334); a candidate node adds its bonus to the tree's sums (`TreeSums`, `plusNode`, `finished`) instead of rebuilding the grown tree (`writeNode` 4,478 → 2,853; 419,064 / 561,100). `Stats.built` itself costs ~650 CU more on SBF since, the zeroing of the new `TreeSums` literal through the runtime's byte-loop `memset`. Guard tests compare each against the definition it replaces.
- Cross-module inlining, measured on a hand-made link of `3ae4847` (not what `msc` builds): `msc` links SBF objects with `ld.lld` one by one and adds no LTO for `--os=solana`, so every call into another module stays a call (`Math.min`/`Math.max`, the division overloads of `rules/arithmetic.ms`, every small rules helper). The same objects built with `--passC=-flto`, merged by `ld.lld -shared --entry entrypoint -u abort -u memcpy -u memset -u memmove -u memcmp --unresolved-symbols=ignore-all --plugin-opt=emit-llvm`, compiled by the platform-tools `clang -O2` and linked as `msc` links: act 435,658 → 281,945 typical, 583,344 → 371,168 busiest (−35%), same choices and bytes, `.so` 186,288 → 168,992 bytes. A direct LTO link fails: lld's LTO output is `EM_SBF`, the Rust `compiler_builtins` objects are `EM_BPF` (the SBF backend writes `EM_BPF` only with the `reloc-abs64` feature, which lld's LTO step does not set). This belongs to the compiler; the hand-written stand-ins in `rules/` (`activation`, the division overloads, hand shifts) stay until it lands, then go.
- In the MagicBlock ER on devnet again (2026-09-27, program `CwPgPyEN5KCBjMHMaBjCjZ4Ur4GcTrBknXcBQJQNkQeJ`, a new id because the probe's `.so` grew to 192,248 bytes; rules of `32cb82d`, `p29s5` in format 7): 419,064 CU typical and 561,100 busiest, equal to LiteSVM to the unit, 91–156 ms, same choices and bytes, committed back to L1 intact 112–174 s after the first return. Throughput with every act writing `GlobalConfig`: `docs/SOLANA.md` §7 item 9.
- Most of the rest outside the network is struct zeroing. Every struct literal in the generated C starts with `memset(&literal, 0, sizeof)`, and under `--os=solana` msc's runtime `memset` is a byte loop (~5 CU a byte) the SBF backend can neither inline nor turn into `sol_memset_`: `doEconomy(Rest)` costs 3,250 CU and `legalEconomy` 45k. Anza's model, measured on a patched copy of the toolchain (`__builtin_memset` inlined up to the backend's 10 stores, `sol_mem*_` syscalls above): `legalEconomy` 6.7k, act 516k → 470k typical and 740k → 683k busiest, no call slower. Card `~/metascript/.inbox/compiler/2026-09-27-solana-runtime-memset-is-a-byte-loop.md`. After it, `legalEconomy`'s trial of every action is ~6k.
- In the MagicBlock ER on devnet (2026-09-27, `tools/chain/actDevnet.mjs`, program `2iK2VJvEzwGsURN8CtPzy6qjycfhyLh2TZYy2anx7Af7`, rules of `1cd3f0b`, before the signed-byte change; policy, context and wilds left on L1 read-only, `GlobalConfig` and the ten pets delegated): a whole `act` with write-back costs 515,971 CU typical and 739,640 busiest, the LiteSVM numbers to the unit, in 88–102 ms wall clock (the first transaction 1.06 s while the ER cloned the L1 accounts). The ER chose what the sim chose and held the sim's bytes; after commit-and-undelegate of the eleven written accounts (one transaction each, back on L1 110–154 s after the first) L1 held the same bytes. The whole run cost 0.061 SOL on L1, rent of the fourteen accounts included.
- The tick at dawn is unmeasured on SBF: an instruction that ticks the actor and its neighbours does not link while `growthBonus` compares against module constants in `match` guards (card `2026-09-27-solana-module-const-in-a-match-guard-not-folded.md`).
- Open: the `dense` inner loop, ~20 instructions a weight against Rust's ~12, two of them bounds checks and two the `int32` index widening (card `2026-09-27-span-index-checks-stay-inside-hot-loops.md`). Splitting `act` into two transactions is the fallback and a design decision. Also open: what `act` does when a program upgrade moves the engine version and `checkPolicy` rejects the stored blob.

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
3. Reward weights per persona (`GAME-DESIGN.md` §17.5): first measured set in package 5; nothing yet separates Greedy from Vengeful, and nothing makes a pet hold more hearts than the floor without costing strength.
4. Argmax or sampling on chain; sampling would draw from VRF like every other roll.
