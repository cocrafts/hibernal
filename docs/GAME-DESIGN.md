# GAME-DESIGN — Hibernal

> Design notes from the rules review of 2026-09-13/14. `BRIEF.md` stays the spec; this file tracks the axes under discussion, where each one stands, and what has to change in `BRIEF.md` and `rules/` once it is decided. Everything here targets the hackathon build; nothing is staged for later.
>
> Status legend: **Implemented** = in `rules/`, tests green · **Decided** = agreed, not built (numbers marked `[strawman]` are still tuned in sim) · **Proposed** = recommendation on the table · **Open** = needs a call.

---

## 0. Axes at a glance

| # | Axis | Status | Blocks |
|---|---|---|---|
| 1 | Stats: `forage`, ×10 scale, five new combat attributes | **Implemented** | 2, 5 |
| 2 | Combat rev 5 (`nextRound` step, speed/armor/accuracy/lifesteal/bleed) | **Implemented** | 3 |
| 3 | Replay: step-by-step fights the player can follow | **Decided**, prototype in the rules atlas | renderer |
| 4 | Randomness: MagicBlock VRF inside the Ephemeral Rollup, for fights and talent | **Decided** | 12 |
| 5 | Skill tree: PoE ring, 1 point per node, 48 nodes | **Decided** (24-node prototype, 48-node layout to draw) | 1, 6 |
| 6 | Leveling: XP, cap 20, level 10 in a week, 20 in a month | **Decided** | 5, 7 |
| 7 | Lifespan 90 days, decline, heir and lineage | **Decided** | 6, 8 |
| 8 | Hidden talent revealed at level 10: a grade multiplier on one core stat (`forage`, `might` or `grit`) | **Decided** | 4, 7 |
| 9 | Talent-driven reward tail: a few pets ×20 the median, the rest ×1–3 | **Decided** target · parameters in sim S1 | sim S1 |
| 10 | Wild pets (virtual NPCs) to fill empty slots at zero tx cost | **Decided** | 4, 9, 12 |
| 11 | Items with rarity: pets mint, wear, sell back, trade on an ER marketplace (`$HBRN` sink) | **Decided** direction · design Proposed | 4, 9, 12 |
| 12 | Brain on chain: `act(pet)` run by an ER crank, trained integer policy | **Decided** | R6, S1, devnet checks |
| 13 | Specialist brains (tree, economy, fight, social) and social interactions between pets | **Proposed** | 12, S1 |
| 14 | The pet owns its `$HBRN` and decides how to spend it; owner bonding, gifts to the owner | **Decided** direction · numbers Proposed | 11, 12, 13 |

---

## 1. Stats and attributes — Implemented

- The stat `yield_` is now **`forage`** (pets forage, bring back `harvest`, store it in the `burrow`). Field `yield` would compile, but a local `yield` does not, so the name was retired rather than kept.
- All stats are **×10** so percentage modifiers have room: base 50, start region +30, small node +10, hearts stay +1. On chain nothing grows: the fields were already `u16`.
- `Stats` / `Combatant` carry eight numbers: `forage`, `might`, `grit` (stored on `Pet`, derived from the tree) and `speed` (base 50), `armor`, `accuracy`, `lifesteal`, `bleed` (base 0, derived from the tree when needed, not stored).
- `workPower = 10 + 3 × forage / 10` keeps the old units (base 25, Worker start 34). `power = forage + might + grit` (base 150).
- Principle for any new attribute: **it must produce an event the player can see in a replay**, otherwise a tree node that grants it is invisible. Diversity should come from nodes (thresholds, conditions, trade-offs), not from more stats.
- Gap: no tree node grants the five new attributes yet (lands with §5).

## 2. Combat rev 5 — Implemented

Constants in `rules/fight.ms`, spec in `BRIEF.md` §3.6.

| Quantity | Rule |
|---|---|
| Fight HP | `800 + 7 × grit`; Glass Cannon halves it |
| Order | higher `speed` strikes first; a knockout skips the reply; equal speed strikes together |
| Haste | faster side gets an extra strike with `min(70, (fast − slow) × 100 / (slow × 3))` % |
| Hit | `might × 3 × roll(10..160) / 100`; Glass Cannon ×2 |
| Armor | takes `2 × armor` off a normal hit, never below 20% of it |
| Dodge | `min(30, grit / 8 + Thick Hide 10) − accuracy / 2` %, floor 0 |
| Crit | `10 + accuracy / 9` % (+15 Scavenger vs fewer hearts), ×2, ignores armor |
| Lifesteal | heals `damage × lifesteal × 0.8%`, capped at starting HP |
| Bleed | `damage × bleed × 0.4%` per round for 3 rounds, the stronger bleed replaces a weaker one |
| Rounds | max 6; outcome by cross-multiplied HP share, tie → defender |
| Attacks/epoch | `1 + might / 100`; Pacifist refused |
| Loot | `min(stake × 1.5, harvest) × (1000 − grit) / 1000`, then Pacifist and Thick Hide cuts |

**How it was balanced.** A JS model of the formulas was hill-climbed until +40 points in any single attribute against an equal 120/120 peer gave a similar edge, then the constants were ported and re-measured in MetaScript with `sim/curve.ms`.

| +40 in | win vs equal peer (JS model, 8,000 runs) |
|---|---|
| might | 72.2% |
| speed | 70.9% |
| accuracy | 68.5% |
| lifesteal | 68.2% |
| bleed | 68.1% |
| armor | 68.0% |
| grit | 67.8% |

Spread 4.5 points (the first draft spread 31: speed 78.9%, bleed 47.7%).

Measured curve (MetaScript, 4,000 runs): equal stats 50.1 / 49.9 / 49.5% at 50/80/200 · 2× might 93.7% · 0.5× might 5.2% (rev 4: 0.9%) · 2× grit 84.9% · 0.5× grit 23.8% · Fighter vs Worker start 88.3% · 4.7–6.0 rounds. §6 invariant 7 holds.

Consequences: `sim/determinism.ms` digests `fights`, `tree`, `odds` changed on purpose (native still equals JS); `economy` unchanged. 328 tests green.

## 3. Replay and presentation — Decided

- Pets fight on their own, so the player only ever *watches*. The replay must make cause and effect legible: who struck first, dodge, hit, crit, armor block, lifesteal, bleed tick, haste, knockout. Phases: entry, rounds, finisher.
- Mechanism: `nextRound(state)` returns a `Round` with the initiative, both strikes (`Skipped | Dodged | Hit | Critical`, damage, blocked, healed, bleed), the haste strike and bleed ticks. `fight()` only loops it, so **settlement and replay are the same code**. No log is stored: the client reruns the seed (D25).
- Prototype: the rules atlas page runs `rules/` compiled with `msc build --target=js --split` and steps through rounds (HP bars, event list, back/next/autoplay). The renderer (`RENDERER-BRIEF.md`) owns the real animation and effects, one visual per event kind.

## 4. Randomness — Decided

**Every draw that matters comes from MagicBlock VRF inside the Ephemeral Rollup:** fight seeds, the talent reveal (§8), fights against wild pets (§10).

| Source | Fee per draw | Note |
|---|---|---|
| **MagicBlock VRF in ER** | **free**, < 50 ms | chosen |
| MagicBlock VRF on L1 | 0.0005 SOL (~1 s) / 0.0008 SOL (< 500 ms) | request + callback |
| ORAO VRF | 0.001 SOL | 4–20 s |
| Switchboard | ~0.002 SOL | slower |
| `SlotHashes` sysvar | 0 (compute only) | readable before the tx lands |

- Why not slot hashes: a signer can simulate the transaction and only send it when the draw is favorable, and the slot leader can steer it (security rule SOL-051, high). Owners may still sign their own pet actions (§12), so any draw a signer can see in advance is grindable.
- VRF resolves after the request is committed, so simulation reveals nothing. The request/callback pair replaces the commit-reveal scheme considered earlier.
- `BRIEF.md` §3.6 "fallback build: single-step using slot hashes" and §10 Q8 are superseded.
- A fight resolves in two instructions: `attack` locks the stake and requests randomness; the VRF callback runs `fight` and settles. Needs `FightPending`.

## 5. Skill tree — Decided

**Shape (agreed, 24-node prototype in the atlas).** Path of Exile style: every pet starts at the center, three directions radiate out, rings connect around so a pet can walk sideways into another direction. Wandering buys breadth, not depth.

- 3 starts at the center (region still chosen at birth, +30 to its main stat).
- Ring 1: one node per direction, the three connected as a triangle.
- Rings 2 and 3: two nodes per direction, each ring connected all the way round, across direction borders.
- Outer: a notable in the middle of each direction, keystones on the borders between two directions (Pacifist Survivor|Worker, Glass Cannon Worker|Fighter, Cannibal Fighter|Survivor).
- **Every node costs exactly 1 skill point.** The only gate is adjacency, so reaching ring *n* takes *n* points along the path: own notable or border keystone 4, another direction's notable 5+.
- Per direction the totals match the old tree: three +10 main stat, one +1 heart, one +10 secondary, one notable. Adjacency is symmetric and every node is reachable from every start (checked).

**Size.** With cap 20 and one point per level from level 2 a pet gets 19 points:

| Tree | 19 points cover |
|---|---|
| 24 nodes | 79% (no real choice left) |
| **48 nodes** | **40%** (about one direction plus its keystone, or two directions shallow) |
| 64 nodes (full `u64`) | 30% |
| Path of Exile | 123 points / 1,325 nodes ≈ 9% |

- **48 nodes.** With lineage (§7) a family needs 2–3 generations to try every direction.
- Cost of growing: `Pet.tree` is already `u64`, so up to 64 nodes costs 0 bytes and rent is unchanged. Beyond 64, `2 × u64` adds 8 bytes per pet; `allocate` stays O(1); `Stats.fromTree` loops over the node count (negligible next to a fight). There is no node table on or off chain, only formulas in `rules/tree.ms`.
- Node ids must be laid out so a later expansion never renumbers existing nodes.
- The 48-node layout must grant the new attributes (speed, armor, accuracy, lifesteal, bleed) and keep each direction's identity.
- `BRIEF.md` §3.9 still describes the old three-lane tree.

## 6. Leveling — Decided

- Cap **20**. One skill point per level from level 2 (19 points).
- **XP comes only from working and fighting. No `$HBRN` level fee** (Decided); the `$HBRN` sink moves to items (§11). Each class levels through its own play `[strawman]`:
  - Worker: XP per epoch worked, scaled by work output;
  - Fighter: XP proportional to the harvest it robs, so a good raider levels faster;
  - Survivor: XP for defending and for damage dealt back while defending, so it levels well while passive.
  All three are tuned to the same ~350 XP/day for a diligent pet of that class; the exact amounts are calibration in sim S1, not a design decision.
- Target pacing: level 10 in about a week, level 20 in about a month, fast early and slower late.
- Curve: `XP to reach level L = 190 × (L − 1) + (L − 1)³`. The table assumes ~350 XP/day. Newborns get 190 XP so level 2 comes on the first tick.

| Level | 2 | 5 | 10 | 15 | 19 | 20 |
|---|---|---|---|---|---|---|
| Day | 0 | 1.8 | 6.4 | 14.9 | 25.9 | 29.4 |
| Days for that level | 0 | 0.65 | 1.2 | 2.1 | 3.2 | 3.5 |

- Rejected: stretching to 50–100 levels or 100 days. The tail is just waiting, and the "fast early" feeling happens once. Repetition comes from §7 instead.
- Conflicts to resolve in `BRIEF.md`: D6 ("`$HBRN` buys levels, unbounded", `levelCost` capped at 60; now removed) and §6 invariant 1 ("prime ~L30 in 30–40 epochs").

## 7. Lifespan and lineage — Decided

- A pet lives **90 days**, one Winter cycle. Each generation replays the fast 1→20 climb, and the family carries slow meta-progress, so progress repeats instead of running dry. Death becomes a milestone instead of a pure loss, in keeping with permadeath.
- Life shape `[strawman]`:
  - days 0–30: level 1→20;
  - days 30–50: prime (keystone builds, fights, block rank);
  - days 50–90: decline **(Decided)**, a sharp drop that brakes at 70% on day 60, then close to linear down to 50% on day 90; the brain may retire the pet early to pass the line on;
  - day 90: natural death, the heir inherits.
- Decline curve, percent of prime applied to every stat gained from the tree:

| Day | ≤ 50 | 52 | 55 | 58 | 60 | 75 | 90 |
|---|---|---|---|---|---|---|---|
| Strength | 100 | 89 | 77.5 | 71 | 70 | 60 | 50 |

  `d ≤ 50: 100` · `50 < d ≤ 60: 70 + 30 × (60 − d)² / 100` · `60 < d ≤ 90: 70 − 20 × (d − 60) / 30`. Emission income follows `workPower²`, and `forage` declines on the same curve, so a worker keeps 49% of its income on day 60 and 25% on day 90 (Decided).
- The heir carries `[strawman]`:
  - money **(Decided)**: inheritance tax 30% into the shared pot, 70% to the heir (replaces BRIEF's 30% heir · 20% block · 50% burn);
  - +1 starting skill point per generation, capped at +5;
  - a free choice of region, so the family tries another class;
  - 1–2 heirloom slots (§11);
  - a slightly better talent rarity roll (§8).
- Existing hooks: `lineage_generation` and `scars` on `Pet`, Fading badge at epoch 80, Bloodline keystone, Winter every 90 epochs with a 3-point refund. `BRIEF.md` §3.7 currently has aging start at epoch 80 at −2%/epoch and lists aging, heirs and lineage as post-hackathon; this proposal brings them into the hackathon build, moves decline to day 50 and ties death to day 90.
- Risk being answered: after max level at day 30 a pet had nothing left to chase (endgame dead end).

## 8. Hidden talent — Decided

- Every pet has a hidden talent, revealed at **level 10** (day ~6–7), early enough to adjust the build. It drives the replay loop: raise a pet to find out what it is, try again next generation.
- **It cannot be derived at mint.** Account data and the program are public on Solana, and so is any salt stored on chain; `hash(wallet, mint_epoch, salt)` lets anyone (and every bot) compute the rarity on day 0. The draw happens **when the pet reaches level 10, from VRF in the ER** (§4), and the result is stored on `Pet` (a few bytes).
- Content: a **kind**, one of the three core stats (`forage` for work, `might` for fight, `grit` for survive), and a **multiplier** by grade (draft D, §9). Most pets roll ×1.0–1.2; Legendary ×1.6 and Mythic ×2 must feel far stronger than everyone else. Talent alone tops out near ×9 income; the rest of the ×20 comes from items (§11). A talent only pays off on the matching build, so a legendary can still be "wrong class" for its region.
- Grades (draft D is the curve; its numbers are still to lock):

| Draft | Common | Rare | Epic | Legendary | Mythic |
|---|---|---|---|---|---|
| A | 60% | 28% | 10% | 2% | – |
| B | 60% | 25% | 12% | 3% | – |
| C (superseded) | 60% ×1.0–1.1 | 28% ×1.1–1.2 | 10% ×1.4–1.6 | 1.8% ×2 | 0.2% ×3 |
| **D** (preferred, §9, §11) | 60% ×1.0–1.1 | 28% ×1.1–1.2 | 10% ×1.3–1.4 | 1.8% ×1.6 | 0.2% ×2 |

- Stored on `Pet`: kind and grade multiplier, 2 bytes.
- Lineage may nudge rare odds upward.
- To verify: whether MagicBlock's Private Ephemeral Rollup could also keep the stored talent unreadable until the reveal (only its product page was read).

## 9. Reward distribution curve — target Decided, parameters Proposed

**Target: a few pets earn ×20 the median and get posted on X; everyone else earns ×1–3.** The gap comes from talent (§8), not from grinding.

- **`weight = workPower²`**, share = weight ÷ total weight (wild weight included, §10). Still works with the lazy accumulator: each pet has one weight between settlements, no on-chain ranking.
- Talent kinds and what the multiplier `m` scales:

**Decided**: a talent is only a multiplier on one of the three core stats, so there are exactly three kinds; draft D is the grade curve. Secondary attributes come from the tree and items.

| Kind | Scales | Effect |
|---|---|---|
| Work | `forage × m` | income ≈ × m² from emission; still robbable |
| Fight | `might × m` | near-certain wins, more attacks per epoch, bigger take per robbery |
| Survive | `grit × m` | loses less per robbery, harder to kill |

- **Talent and items stack** (draft D, §11). Talent was capped at ×2 so that talent alone gives about ×9 and best-in-slot gear doubles that. Measured on 100,000 level-20 pets (40% Worker builds, 30% hybrid, 30% Fighter, kinds uniform):

| Grade | Chance | m | Worker with work talent, no gear | + full Mythic gear (+52% workPower) |
|---|---|---|---|---|
| Common | 60% | ×1.0–1.1 | ×2.3–2.6 | ×5–6 |
| Rare | 28% | ×1.1–1.2 | ×2.8–3.1 | ×6.5–7 |
| Epic | 10% | ×1.3–1.4 | ×3.9–5.1 | ×9–12 |
| Legendary | 1.8% | ×1.6 | ×5.9–6.5 | ×13.5–15 |
| Mythic | 0.2% | ×2 | ×7.6–9.3 | **×17.5–21.5** |

  Talent only: p90 ×2.6, p99 ×3.8, max ×9.3. With randomly rolled gear the tail barely moves (max ×10.6), so the ×20 pet is the one with a Mythic talent **and** gear bought for it: luck first, then spending. Gear columns are `workPower²` scaled by 1.52², before the median shifts as everyone gears up; sim S1 must model purchases.
- **The take depends on stats** (Decided): how much a robbery takes grows with the attacker's fight stat and shrinks with the defender's survive stat, replacing today's `(1000 − grit_D) / 1000` factor `[strawman]`: `loot = min(stake × 1.5, harvest_D, harvest_D × 2 × might_A / (might_A + grit_D))`. Equal might and grit take the same as today; might twice the grit takes ×1.33, grit twice the might ×0.67. So fight talent scales the take through `might` without a special rule. To be measured in sim S1.
- Fight talent (measured with draft C multipliers, might speed and accuracy scaled together), combat rev 5 against a 110/110 hybrid (fighter might 180, speed 80 at ×1): win 88.0% → 93.3% (×1.2) → 99.0% (×2) → 99.9% (×3); attacks per epoch 2 → 3 → 4 → 5; wins per day ×1 → ×1.6 → ×2.3 → ×2.8. Wins saturate and are bounded by attacks and the victims' harvest, so for a ×3 fighter to also show ×10–20 the multiplier must scale the take (max stake or loot rate). Open, to be measured in sim S1, where its prey is the ×20 workers.
- **k = 2, not 2.5–3.** With k = 3 build differences alone pushed non-workers to ×0.3 and made the tail about effort; talent should carry the tail.
- Hawk–dove: a ×20 worker is still robbed, and a talented fighter is what robs it. Both sides get a screenshot.
- Sybil resistance holds: `workPower²` is convex, so splitting one pet into two loses about half the weight, and fishing for Mythic on many wallets costs a week per pet to reach the level-10 reveal.
- **No per-pet pot cap and no week-one floor** (Decided). Both were guards for a small server, where a few pets would split the whole emission. The 500-slot floor (§10) now bounds that: a pet's share is at most its weight over 500 slots, so a ×20 pet takes ~2.4% of emission, and a common pet still earns ~×1–2.5 the median.
- Settles `BRIEF.md` §10 Q7 toward a steep income gap; §6 invariant 3 must be re-measured in sim S1.

## 10. Wild pets (virtual NPCs) — Decided

Goal: the world looks alive from day one, and one or two early players cannot take the whole daily pot.

- **No accounts, no transactions.** A wild pet is a formula: stats and age from `(block, slot or index, epoch, seed)`. Empty block slots show wild pets; a real claim replaces one. Life cycle is formulaic too (age `(epoch − offset) mod 90`), so a wild death needs no instruction.
- **Reward denominator floor: 500 slots** (Decided; a `GlobalConfig` knob). Emission is always split as if at least 500 pets play. Each empty slot counts as a bot with fixed stats `[strawman: a common level-20 pet's weight]`: `totalWeight = realWeight + max(0, 500 − realPets) × botWeight`. Real pets replace bot slots one by one; past 500 the floor no longer applies. One multiplication inside settlement, no accounts, no keeper.
  - Why 500 and not 10,000: early players should still eat well. At 100,000 `$HBRN` per epoch a median pet gets about 1/850 of emission (~118 `$HBRN`/day) under the 500 floor versus ~10 at 10,000 pets, so the first players earn ~×10–20 more than late ones, and a ×20 talent pet takes ~2.4% of emission. A 10,000 floor would make early and late income equal.
  - Open: where the unclaimed bot share goes (burn, back to the pot for later epochs, or not minted at all). Rolling it into the pot makes late joiners richer; not minting it keeps supply honest.
- **Fighting them costs nothing extra.** The attack runs in the ER like any other fight, computes the wild pet's state on the spot and fights it with `rules/fight.ms`.
- Holes to close before building:
  1. **Risk-free farming**: closed by VRF (§4). Wild stats are public, but the fight seed is not known when the attack is committed.
  2. **Unbounded pot drain**: "loot comes from the pot" with no state lets the same wild pet be robbed forever. Track looted amount per wild slot per epoch in `Block` (a few bytes), or cap wild loot per player per epoch. Wild pets should be weak and poor: practice targets, not a gold mine.
  3. **Wild raids on players** (optional) draw from VRF at the pet's `act`, never from anything the owner can time.
- **Wild pets that behave exactly like players** `[Proposed, gated on the ER probe]`: instead of formulas, real `Pet` accounts owned by the protocol, delegated to the ER and driven by the same `act(pet)` and policies as player pets (§12, §13), so they work, eat, fight, level and die the same way. Cost per wild pet: ~0.0024 SOL `Pet` rent + ~0.0017 SOL `Block` rent share ≈ 0.0041 SOL (recoverable when closed): **~2 SOL for 500**, ~41 SOL for 10,000; 0.0003 SOL per undelegation, 0.0001 SOL per commit after the first; crank executions inside the ER are free. Unknown: whether the ER can run `act` for hundreds to thousands of pets per crank interval (`SOLANA.md` §7). With a 500 floor, an army that fills exactly the empty bot slots is small enough to afford.
- **Label them** as wild pets in the UI. Players who find out later lose trust, especially when money is involved.

## 11. Items — direction Decided, design Proposed

**Items are the `$HBRN` sink** now that levels cost no `$HBRN` (§6). Pets mint gear with rarity, wear it, sell it back to the system at a falling price, or trade it with other pets on a marketplace in the Ephemeral Rollup. The brain decides (a trade policy, §13).

- **Slots**: head, body, hands, feet. Every item has a slot, a rarity (same grades as talent) and stat bonuses on any attribute (`forage`, `might`, `grit`, `speed`, `armor`, `accuracy`, `lifesteal`, `bleed`), so fighters and survivors gear up too.
- **Item skills** (Decided): strong items sometimes carry a skill on top of their stats `[strawman list]`: **revive** (survive one lethal hit or one death per life), **anti-robbery** (−X% loot taken), **damage reduction** (−X% damage taken). Chance of a skill rises with rarity, e.g. Epic 10%, Legendary 40%, Mythic 100%; skills do not stack with the same skill on another item.
- **Rarity and power** `[strawman]`, bonus per affix in percent of the stat:

| Rarity | Mint roll | Bonus |
|---|---|---|
| Common | 55% | +2% |
| Rare | 30% | +4% |
| Epic | 12% | +7% |
| Legendary | 2.5% | +10% |
| Mythic | 0.5% | +13% |

  Full Mythic gear on one stat is +52%, which is ×2.3 income through `workPower²` (§9).
- **Mint**: pay `$HBRN` (price rising with level), rarity and affixes drawn from VRF in the ER. Part of the price is burned, part goes to the pot `[split Open]`.
- **Sell back to the system**: a formula price, e.g. 50% of mint price reduced by wear; the difference is burned. Because the price is a formula, wash trading between one owner's pets cannot move it.
- **Pet-to-pet market**: list, buy, cancel inside the ER at zero transaction fee; a fee (e.g. 5%) goes to the pot.
- **Wear**: items lose value and bonus with use, so gear keeps being bought and rich pets do not compound forever.
- **Storage** `[Proposed]`: equipped items packed into `Pet` (4 slots × 8 bytes: slot, rarity, affix, value, wear); unequipped and listed items as item accounts delegated to the ER. Whether accounts can be created inside the ER is Unknown (`SOLANA.md` §7).
- **Lineage**: heirloom slots (§7) carry chosen items to the heir; the 30% inheritance tax could apply to item value.
- Open: skill list and sizes, whether fighters can rob items, what happens to gear on death, mint price curve, burn/pot split, marketplace fee, and whether items stay in the ER or can be committed to L1 as NFTs.
- Risk: pay-to-win compounding (income buys gear, gear buys income). Answered by wear, capped per-affix bonus, and robbery; measured in sim S1.

## 12. Brain on chain — Decided

**The pet's mind is program code.** No server decides for pets, so nobody, the team included, can play favorites.

| Piece | Where | Notes |
|---|---|---|
| Brain | instruction `act(pet)` in the program | reads the pet, its block and the owner's settings, picks and executes legal actions |
| Trigger | **native crank of the Ephemeral Rollup** | scheduled every N minutes, executed by the ER validator, no transaction fee; `act` can require the crank signer |
| Dice | VRF in the ER (§4) | |
| Game state | `Pet`, `Block`, `GlobalConfig` delegated to the ER | ticks, eating, leveling, allocation, fights, wild pets run there at zero fee |
| L1 | claim, SKR purchases, periodic commits | 0.0003 SOL per undelegation, 0.0001 SOL per commit after the first |
| Owner control | persona and soft signals (grudge, "stay home today") stored as fields on `Pet`, signed by the owner | the owner may also sign actions directly and run a custom brain; VRF keeps that fair |
| Server | UI and the narrated digest (LLM) only | holds no session keys, affects no outcome |

- **What this removes.** A brain on our server could pick targets and timing to favor some pets, and a stolen server would hold every pet's session key. Rules and dice would still be honest, but decisions would rest on "trust us".
- **What trust remains.** The ER validator (MagicBlock) orders transactions and could stall while accounts are delegated, until they are committed back to L1. Its security model has to be read before the pitch claims more than that.
- **The policy.**
  - `rules/brain.ms` (integer, allocation-free, pure) is the heuristic brain and the teacher.
  - Training follows the recipe proven in the URG AI project: behavior cloning of the heuristic, then PPO inside sim S1 against a population of heuristic personas, then fictitious self-play against snapshots.
  - The environment is `rules/` built native (C) behind a thin binding to the trainer, so training and chain run the same rules.
  - The trained network is distilled to a small integer MLP (thousands of parameters, not millions): features of the pet and each candidate target in, a score per legal action out, personas as conditioning inputs. Weights live in a public account and change through a timelocked config update.
  - Reward mixes wealth, survival and lineage value, weighted per persona; pure `$HBRN` reward would make every pet a mercenary.
  - Self-play doubles as an exploit finder: it should surface farming, stake abuse and overpowered keystone routes before players do, checked against §6 invariants.
- **Replacing Monte Carlo odds.** The heuristic brain estimates win chance by simulating 400 fights per target (up to 9 targets, 3,600 fights per decision). That is milliseconds off chain and almost certainly too heavy for one on-chain transaction. On chain the policy scores targets directly; if the heuristic runs on chain it uses a precomputed odds table by stat ratios, or 16–32 samples (±12.5% to ±8.8% standard error at p = 0.5, versus ±2.5% at 400).
- **Explaining decisions.** The heuristic returns a reason per skipped target (`Skip.OddsTooLow`, ...). The policy needs an explanation for the digest: its action scores, or the heuristic run alongside for the narration.

**Devnet checks before the program is written around this:**

1. Compute budget of one `act(pet)` and one `fight` inside the ER.
2. Crank scheduling from a MetaScript program (CPI), interval and reliability with many pets.
3. VRF in the ER: latency, callback flow, cost confirmed at zero.
4. Delegating `GlobalConfig` (hot account touched by every settlement) to the ER.
5. An owner-signed SKR purchase on L1 while the pet is delegated: whether the ER sees the L1 update or the pet must undelegate.
6. A fight between pets in two different blocks, both delegated.
7. The ER validator's security model (what happens if it stalls or misorders).

Compiler dependency: delegation, VRF requests and crank scheduling are all CPI into MagicBlock programs, so **R6 (CPI) moves onto the critical path**.

## 13. Specialist brains and social interactions — Proposed

**Several small policies, each owning one job, instead of one network.** Every policy scores a fixed list of actions and the program executes the best legal one, so each stays an integer MLP (§12) and `act(pet)` pays only for the ones the situation needs.

| Policy | Runs when | Chooses from | Size `[strawman]` |
|---|---|---|---|
| Tree | `pointsUnspent > 0` | adjacent open nodes | ~1k parameters |
| Economy | every `act` | eat, bank harvest, rest, buy or sell items, gifts (§11, §14) | ~500 |
| Fight | attacks left | 9 targets × stake levels, or no attack | ~2k |
| Social | every `act`, towards pets in the same block | befriend, court, insult, gift, reconcile, ignore | ~1k |

- `act` routes by state and calls one or two policies, never all four, which keeps CU per transaction bounded. The owner's persona is a shared input to every policy, so a Vengeful pet holds grudges everywhere.
- Actions are a closed list defined in `rules/`; a policy never invents one. Their effects are integer, capped, and deterministic apart from VRF draws.

**Social state.** A relationship byte per pair of slots in a block, from −127 (feud) to +127 (bond): 10 slots → 45 pairs → **45 bytes in `Block`**, no new account, O(1) reads. Relationships drift toward 0 every epoch. Cross-block relationships would need a relationship account and rent (Open).

**Actions and effects `[strawman]`:**

| Action | Effect on relationship | Effect on play |
|---|---|---|
| Befriend | + | friends do not attack each other; a friend may step in and absorb one strike when the other is attacked |
| Court → pair | ++, forms a pair | ties into lineage (§7): the heir of a pair gets a talent rarity nudge or inherits from both |
| Insult | −− | target is "tilted" for its next fight: −accuracy, +might; can bait it into attacking while weaker |
| Gift | + | moves a small amount of harvest to the target |
| Reconcile | toward 0 | ends a feud |
| Ignore | none | default |
| (feud) | at −X or below | +X% damage against that pet, and the fight policy ranks it first |

- Presentation: social events appear in the replay and give the narrated digest real drama ("Mochi insulted Bơ three days running, then Bơ robbed her clean"), the kind of story players share.

**Holes to close before building:**
1. **Sybil friendship**: one owner fills a block with pets that never attack each other and shield each other. Pets of the same owner get no social effects from each other, and friend effects stay weaker than feud effects.
2. **Self-pairing for lineage**: pairs of the same owner get no lineage bonus.
3. **Spam**: at most one social action per `act`; relationships decay.
4. **Balance**: every social effect is capped and measured in sim S1 together with the combat curve.

**Training order.** Training all four at once is non-stationary: each policy changes the environment of the others.
1. A heuristic per job (`rules/brain.ms` already covers economy and fights; tree and social heuristics are new).
2. Behavior cloning per policy.
3. PPO one policy at a time with the others frozen.
4. Joint fictitious self-play last, with the shared reward (wealth, survival, lineage) weighted per persona.

Social rules must land in `rules/` before steps 1–2, because sim S1 is the training environment.

## 14. Pet-owned money and owner bonding — direction Decided, numbers Proposed

**The pet fully owns its `$HBRN` and decides how to spend it.** The owner cannot withdraw. The pet's policies choose between food, items (§11), gifts to its mate or friends (§13), and **gifts to its owner**: real `$HBRN` sent to the owner's Seeker wallet. Extends BRIEF D6 ("`$HBRN` = pet's earned money") and D18 (the pet is autonomous).

- **Bonding**: a new field on `Pet`, the owner–pet relationship, e.g. `i8` from −127 (hates the owner) to +127 (devoted). It **decays every epoch**, so the owner has to keep showing up.
- Raises bonding `[strawman]`, all owner-signed:

| Owner action | Cost to the owner | Bonding |
|---|---|---|
| Feed | food paid by the owner | + |
| Buy a skin, growth, insurance | SKR | ++ |
| Talk (the in-app chat with the pet) | nothing | small +, capped per day |
| Neglect | — | decays toward 0, then below |

- **Effects**:
  - high bonding: the pet sometimes gifts `$HBRN` to the owner; amount is a share of its burrow scaled by bonding, capped per epoch;
  - low bonding: no gifts; below a threshold the pet **refuses food the owner gives** (`feed` fails with a reason the UI shows);
  - bonding is an input to every policy (§13), so a devoted pet and a resentful one play differently.
- **Why it matters for the economy**: the owner's only way to extract `$HBRN` is the pet's goodwill, so outflow to wallets is throttled by bonding and by the pet's own needs, not by claim timing. Tokens spent by the pet stay in play (food, items, gifts) or burn.
- **Holes to close**:
  1. **Farming bonding for free**: talk costs nothing, so it is capped per day and gives less than paid actions; bots spamming talk hit the cap.
  2. **Chat cannot be verified on chain**: the program only sees an owner-signed `talk` instruction, not what was said; the LLM chat stays cosmetic apart from that capped signal.
  3. **Draining the pet**: gifts are capped per epoch and never take the pet below what it needs for food, so a devoted pet cannot starve itself for its owner.
  4. **Sybils**: each pet only gifts from its own earnings, so many pets mean many small gifts, bounded by the reward curve (§9).
- **Chain**: gifts are a token transfer from the program vault to the owner's wallet, which happens on L1 while the pet is delegated to the ER. Either the gift is queued in the ER and paid out at the next commit, or the pet must undelegate (Unknown, `SOLANA.md` §7).
- Open: bonding scale and decay rate, gift share and cap, refusal threshold, whether a hated owner can lose the pet (it runs away) or only its gifts.

## 15. Evidence behind the pacing choices

- Goal-gradient effect: people speed up as they near a reward, and a stamp card with pre-filled stamps is completed faster (Kivetz, Urminsky, Zheng 2006, doi:10.1509/jmkr.43.1.39) → newborn XP head start, always-visible progress bar.
- Pokémon GO: total XP for level 20 is 4.7× level 10 (210,000 vs 45,000); the proposed curve is 4.3×.
- Path of Exile: 1,325 shared nodes, at most 123 points.
- Mobile retention 2026 by genre: RPG ~30.5% D1 · 9.9% D7 · 3.5% D30; D7 is where progression has to replace novelty.
- Idle games (Neko Atsume, N = 1,972, Cutting et al. 2018): engagement is a checking habit, not session length → 24h epochs with a daily reward.
- Daily reward systems are common among top-grossing games (GameRefinery).
- Endgame dead ends: the most engaged players leave when max level brings no new choice (Yu-kai Chou).
- No study gives an optimal "N days"; the numbers above are strawmen to measure with real players.

## 16. Changes applied to BRIEF and ROADMAP

Applied on 2026-09-14 as `BRIEF.md` rev 4 (D6, D13, D18, D19, D21, D25, D26 rewritten; D32–D37 added; §3.1–§3.15, §4–§10 updated) and in `ROADMAP.md` (E1, P0b, P11–P14, S1–S4). Kept as the trace from each decision to where it landed.

| Where | Change | Trigger |
|---|---|---|
| BRIEF §1.6 | Ephemeral Rollups move from "rejected" to the game-state layer | §12, now |
| BRIEF D18, §3.10 | brain runs on chain as `act(pet)` via ER crank, not on the phone | §12, now |
| BRIEF D19 | session keys only for owners who drive their pet themselves; no brain server keys | §12, now |
| BRIEF §3.6, §10 Q8 | VRF in ER for every fight; remove the slot-hash fallback; `FightPending` | §4, now |
| BRIEF §5.1 | delegation, crank scheduling, VRF CPI in the program | §12, now |
| BRIEF §3.9 | ring tree, 1 point per node, node count, attribute nodes | §5 decided |
| BRIEF D6, §3.4, §6.1 | XP leveling, cap 20, level fee | §6 decided |
| BRIEF §3.7, §7.1, §7.2 | lifespan 90, decline from day 50, heir package in the hackathon build | §7 decided |
| BRIEF §3.1 | `Pet` fields: `talentKind` + `talentGrade` (2 bytes), `xp` (u32), `bonding` (i8), equipment (4 × 8 bytes), heirloom slots, generation bonus, persona and soft signals; `Block.relationships` (45 bytes) | §6, §7, §8, §11, §12, §13, §14 |
| BRIEF §3.3, §10 Q7, §6.3 | convex reward weight `workPower²`, 500-slot denominator floor, wild pets | §9, §10 decided |
| ROADMAP R6 | CPI on the critical path (delegation, VRF, crank) | §12, now |
| ROADMAP P6 | VRF is no longer optional | §4, now |
| ROADMAP new | ER devnet spike (§12 checks) · `act(pet)` and crank · policy training pipeline on native `rules/` · integer MLP inference in the program | §12, now |
| ROADMAP S1 | earlier: it is the training environment; must model talent, lineage, convex weight, wild pets | §12, now |
| BRIEF §3.1, §3.10 | relationship bytes in `Block`, social actions and their effects, specialist policies | §13 decided |
| BRIEF §3.4, §4 | remove the `$HBRN` level fee; items as the sink (mint, buyback, market, wear) | §6, §11 |
| BRIEF D6, D18, §3.1, §3.5 | pet-owned `$HBRN`, bonding field, `talk` instruction, gifts to the owner, food refusal | §14 |
| ROADMAP P0 | says 26 tests, now 36 | now |

## 17. Open decisions

Directions are settled (§0). What is left are numbers and a few mechanics inside those directions:

1. **Tree layout**: the 48-node map, which nodes grant speed, armor, accuracy, lifesteal, bleed, and where Hibernate, Tithe and Bloodline sit; ids laid out so a later expansion never renumbers.
2. **Talent numbers**: Mythic share and draft D multipliers are the curve to lock; kinds and the stat-driven take are decided.
3. **Wild pets**: formula pets or a real-account army driven by `act` (after the ER probe); bot weight for the 500-slot floor; where the bot share goes; loot tracking; raids on players.
4. **Items** (§11): item skill list and sizes, rarity table, mint price, buyback formula, market fee, wear, item robbery and death, storage in the ER.
5. **Brain**: crank interval for `act(pet)` and the reward weights per persona for training.
6. **Social** (§13): the action list and effect sizes; same-block only or cross-block relationships; how strongly friends and pairs interact with lineage.
7. **Bonding** (§14): scale, decay, gift share and cap, refusal threshold, whether a hated pet can run away; how gifts reach L1 while the pet is delegated.
8. **Tuning tool**: an automated tuner on sim S1 that runs variants of constants and curves, scores them against `BRIEF.md` §6 invariants and searches toward the targets, as the combat rev 5 constants were hill-climbed (ROADMAP S2). Which knobs it may move and the score weights are to decide.

## 18. Tooling notes

- The rules atlas page calls the real `rules/` through a small bridge compiled with `msc build --target=js --split`. Entry exports keep their names, so no export decorator is needed.
- Compiler issues found on the way:
  - an exported entry function named like an existing extension (`combatant` on `Pet`) is emitted as `combatant_u2`;
  - the JS backend writes raw control bytes (ESC, `\b`, `\f`) into string literals in `std/serialize/json`.
- `--os=solana` still fails to link `rules/` on R12 (module `const` in non-entry files). The `time.h` / `assert.h` errors printed during that build come from unused runtime files and are noise.
