# PROJECT BRIEF — Hibernal (working title) · token $HBRN

> Purpose of this document: give every contributor full context, every decision already made, and the specs needed to scaffold and build the hackathon MVP. Treat the **Decisions** section as settled unless explicitly reopened. Treat numbers marked `[strawman]` as tunable defaults, not requirements.
>
> **Rev 4 (2026-09-14).** Brain on chain and game state in the MagicBlock Ephemeral Rollup (D18, D19, D21 rewritten), VRF inside the ER for every draw with no slot-hash fallback (D25), XP leveling without a `$HBRN` fee (D6), 64-node ring tree (D13), and the systems D32–D37: lifespan and lineage, hidden talent, reward weight `work_power²` with a 500-slot floor, items, pet-owned money and bonding, wild pets. Details, measurements and open numbers live in `GAME-DESIGN.md`; the on-chain surface in `SOLANA.md`.
>
> **Rev 3 (2026-09-12).** All-in MetaScript (D31) supersedes D20/D30's Anchor + Kotlin split; §5 and §8 rewritten. Art direction (D14 rev) and renderer brief alignment (D30) from the same day. Adds D18–D29 from the design sessions of Sept 10–11: autonomous pet, session-key signing, Anchor program, accumulator emission, multi-round combat with onchain replay records, L1-only. Rev 1 is archived alongside this file's history.

---

## 0. One-liner

**A Tamagotchi that can permanently die, one per Seeker phone, that lives its own life: it works, eats, fights its neighbors and spends its own money, while its owner can only feed it, buff it, talk to it and watch the replays. A pet that loves its owner shares its earnings.** Its economy runs on a fair-launched token that pets earn by working and fighting.

Pitch framing (for deck, not for code): *"Bitcoin mining on your phone, but the miner is a pet with a will of its own."* Number of Seekers = number of pets. The app helps Solana Mobile sell phones.

---

## 1. Context

### 1.1 The hackathon
- **Name:** CLOCK IN — A Solana Mobile Hackathon, organized by RadiantsDAO
- **Window:** Sept 8 → Oct 8, 2026 (today is Sept 11)
- **Prizes:** $135k total — 10 × $10k grand, 5 × $5k honorable, **$10k SKR track** for best Solana Mobile Stack integration; plus Seeker devices, dApp Store featuring, marketing support, a call with Toly
- **Hard requirements:** working Android APK, Solana Mobile Stack integration, Mobile Wallet Adapter (MWA) support, clearly mobile-first
- **Judging criteria (stable across all 3 editions):**
  1. Completion — demo video proves it runs
  2. Technical Depth — code quality/complexity, **judged via GitHub commit history** (commit early, often, don't squash)
  3. Mobile Optimization — use of mobile-specific features
  4. Creative Solana Usage
  5. Vision & Clarity — pitch and roadmap
- **Submission:** GitHub repo, demo video, pitch deck. Ship to dApp Store before deadline.
- **Verify on the official CLOCK IN page** (JS-rendered; open it in a browser): eligibility rules, submission format, tracks and sponsor list.

### 1.2 Prior winners (what judges reward)
- **MONOLITH (Mar 2026):** 4/15 prizes were prediction markets, 3 were DeFi yield. Standouts were **device-native**: Echo Protocol (GPS-anchored rewards, Seed Vault signing, solo dev), SeekerClaw (24/7 on-device AI agent, no server, MIT), Kinlog (camera+motion squat counter). SKR track winner: Seek (real-world scavenger hunt).
- **NOMI won a MONOLITH grand prize** — 3D companion pet on Solana: mint, feed, play, dress, reacts to neglect, all onchain. Judges called it "the Tamagotchi crypto always needed." **We must be visibly different from NOMI:** hardware-gated scarcity, permadeath, pet has its own wallet and economic agency and acts on its own, neighborhood PvP with replays, fair-launch token. **Do not build 3D.**
- Judges consistently call out "solo dev", "shipped in 15 days" — scope-to-execution ratio matters.

### 1.3 Ecosystem signals
- dApp Store passed 1,000 apps. Solana Mobile's stated pain: "turn one-time downloads into daily habits." Retention is the open problem. Permadeath is a direct answer.
- Builder Grants RFP explicitly wants: viral/sticky apps, dev tools, Seeker UX improvements, creative SKR usage. Explicitly **does not** want projects that exist to spray token on an existing user base.
- Prediction markets, perps, yield aggregators are saturated. Avoid.
- Seeker: **~200k shipped** (MWC 2026), **~100k active** dApp Store users. Realistic pet base first 3 months: 5–20k.

### 1.4 Relevant Solana upgrades
- Slot time 400→350ms, heading to 200ms; Alpenglow (~150ms finality) targeted Q3/Q4 2026
- **Transaction V1 activated Sept 9, 2026** — 3.3× max tx size, better multisig/ZK. Useful for bundling owner actions on L1 (claim, SKR purchases). The rev 3 "one signature morning" bundle is gone: pets act through the ER crank (D18).
- Token ops ~95–98% cheaper in CU; 100M CU block limit. Onchain tick per pet is cheap.

### 1.5 Device
- Seeker: MediaTek Dimensity 7300, 8GB RAM, 128GB, Android 15, 4500mAh
- Realistic background budget for on-device inference: ~1–1.5GB → 0.6B–2B param model at Q4. Gemini Nano/AICore **not available** on this chip.

### 1.6 Infra evaluated and rejected (keep for deck Q&A)
- **MagicBlock Ephemeral Rollups** for game state: *rejected in rev 3* (4–7 tx/pet/day did not justify it), **adopted in rev 4 (D21)** once the brain moved on chain. The crank runs `act` for free, VRF inside the ER is free, and fees are 0.0003 SOL per undelegation and 0.0001 SOL per commit after the first. Delegated accounts are frozen on L1, so SKR purchases and cross-block fights are measured in the probe (`SOLANA.md` §5, §7).
- **SpacetimeDB**: off-chain authority kills the "program is the neutral referee" pitch and needs a token bridge.
- **MetaScript for the onchain program**: backend builds sBPF ELF that runs (108 CU hello), but entrypoint/accounts/PDA/CPI are absent and the manual-GC heap is not mapped to Solana's heap region. First estimate was 6–7 weeks for an Anchor-like subset. **Chosen anyway (D31)** with a Pinocchio-shaped design (zero-copy, no Borsh, no IDL) and the Solana C SDK reachable through FFI, which shrinks the gap to the items listed in §5.1.

---

## 2. Decisions (settled)

| # | Decision | Rationale |
|---|---|---|
| D1 | One living pet per Seeker Genesis Token (SGT). PDA seeded by **SGT mint address**, not wallet. | Solana Mobile's own anti-Sybil recipe; mint address is stable across SGT transfers within Seed Vault Wallet. |
| D2 | `admission_groups` is a config list from day 1; only the SGT group is populated. | Adding an admission group later (devnet test tokens, future device generations) needs no program upgrade. |
| D3 | Project token **$HBRN**: **fair launch, zero allocation, zero pre-mine.** Supply is defined by the emission schedule. Only way in: play. | Removes every dump vector; makes the operator a neutral referee. |
| D4 | Emission drops **×0.75 every 90 epochs**. The event is called **"Winter."** Floor TBD. | Halving too aggressive for late cohorts; "Winter" is friendlier than "Famine." |
| D5 | Revenue = **100% of SKR spend** (treasury) + **protocol fees in $HBRN** (5% fight rake, 10% of food spend, item market fee). No token allocation. | Fees flow only when the game works; allocation pays before it does. |
| D6 | **SKR buys multipliers (capped ×1.20), skins and owner food. $HBRN is the pet's money: food, items, gifts. Levels come from XP only** (Worker: work output · Fighter: robbed harvest · Survivor: defense and counter damage), cap **20**, level 10 in ~a week, level 20 in ~a month, 1 skill point per level from level 2. No `$HBRN` level fee. *(rev 3: $HBRN bought unbounded levels.)* | Whales get +20% *progress*, never +20% *power*. Items take over as the `$HBRN` sink (D35). |
| D7 | Epoch = **24h, boundary 00:00 UTC**, **lazy settlement**; the ER crank runs `act` (D18), which ticks. `EPOCH_SECONDS` is a program config (short for demo). | 7am VN, 4pm US-West, 9am EU. Demo video needs multiple cycles. |
| D8 | Fights: **anyone can attack, target is chosen (not random), block-only.** Full information UI with win odds shown. | Onchain is public anyway; design for full info. Fighter plays a probability game, not a slot machine. |
| D9 | **Loot is harvest, not savings.** Claimed tokens ("burrow") are unstealable. | Fixes the "Worker is a blood bag" problem. Claiming daily = safety. |
| D10 | **Fights kill only a pet with nothing to lose; hunger kills everyone else.** A robber that takes back at least its stake leaves the defender's hearts alone; one that does not bites: 2 hearts scaled by `power_a / power_d` (clamped ×0.5–×2), at most 20% of the defender's max hearts (`rules/fight.ms: biteHearts`). An attacker that loses drops 2 hearts, at most 20% of its max (`defeatHearts`). Absolute hearts with a share cap, so max hearts shields a pet: when bites and defeats were shares of max hearts, hunger (also a share) made every extra heart a pure food cost and the Bulwark keystone starved 20% of its lives (`docs/SIM.md` F1); a pet may attack at any hearts. *(Until 2026-09-24 a bite needed an empty harvest and fights did not kill.)* | Death is real and still readable: a pet that keeps some harvest pays in money, a pet that banked everything pays in hearts (`docs/SIM.md` C3, C5). |
| D11 | **Newborn shield 3 epochs. Max 1 bite per target per epoch, at most 2 hearts per bite** `[strawman]`. A bite earns the attacker nothing beyond the loot it failed to find. *(The rule "no biting a pet with power < 50% of yours" is dropped.)* | Anti-griefing without protecting the weak by power: killing a poor pet costs a stake and pays nothing (§6 inv. 6). |
| D12 | **Blocks of 10, fixed, assigned by claim order via free-list.** Not chosen, not rotated. Death frees the slot (7-day grace for same SGT). Winter merges blocks with <5 living. | Persistent neighbors enable reading, revenge, inheritance, lineage. Costs nothing onchain. |
| D13 | Skill tree is a **PoE-style ring**: every pet starts at the center, three directions radiate out, classes cross only through a gate at the center, **64 nodes, every node costs 1 point except keystones (3)**, small/notable/keystone nodes, **no respec** except 3-point refund each Winter. | Build = route to keystones. Wandering buys breadth, not depth; 20 points at level 20 cover ~31% of the tree; skill books and lineage add up to 10, hard cap 30. |
| D14 | **Pixel-art look produced from low-poly 3D** (t3ssel8r technique: tiny orthographic render target, quantized lighting, screen-space outlines, nearest upscale). Reads as pixel art, but lights move. **Home scene = the pet sitting by a campfire in the snow**; the fire is the hearts meter. Narration via templates first; on-device LLM optional, timeboxed. *(rev 1 said flat 2D.)* | Visibly not NOMI's glossy 3D, and the campfire gives dynamic light that static sprites cannot. Never let the model block the demo. |
| D15 | Program upgrade authority under **7-day timelock** (not burned). | Fair-launch credibility + keeps D2's door and emission tuning open, transparently. |
| D17 | Run the hackathon build with **$HBRN as non-transferable points** on the same program logic; enable real emission only after retention data exists. | Design the economy while nothing is at stake. (Deck says this explicitly — it's a credibility point.) |
| **D18** | **The pet is autonomous and its brain runs on chain.** `act(pet)` is a program instruction run by the ER native crank: work, eat, level, allocate, trade, whom to attack. Heuristic policy first (`rules/brain.ms`), specialist integer policies later (§3.10). Owner influence = SKR items, feeding and talking (bonding, D36), persona and soft signals stored on `Pet`. The owner may sign actions to run a custom brain; the app has no attack button. **No server decides for a pet or holds keys.** *(rev 3 ran the brain on the phone.)* | Nobody, the team included, can play favorites: the program is both referee and mind. |
| **D19** | **Session keys only for owner-driven play.** Pets act through the crank (D18) with no key. An owner who wants to sign pet actions creates a MagicBlock session once through Seed Vault; pet instructions accept **owner OR valid session key OR the crank**. Claim, SKR purchases and session create/revoke require the owner; `feed` and `talk` accept the session key. | No daily popups, no server keys. |
| ~~D20~~ | ~~Program in Anchor (Rust); rules module in MetaScript compiled to JS.~~ **Superseded by D31.** | — |
| **D21** | **Solana L1 + MagicBlock Ephemeral Rollup.** `Pet`, `Block` and `GlobalConfig` are delegated to the ER, where ticks, eating, allocation, fights, VRF and the brain crank run at zero fee; L1 keeps claim, SKR purchases and periodic commits. No off-chain state DB. *(rev 3 said L1 only.)* | The brain on chain needs frequent free execution and fair dice. See §1.6, `GAME-DESIGN.md` §12, `SOLANA.md`. |
| **D22** | **$HBRN buys food into a pantry, within a daily quota.** `buy(tier)` costs $HBRN from burrow (spend splits 60/30/10 like upgrades) and puts one Small, Medium or Large portion (+3/+6/+10 hearts) in the pantry, at most `FOOD_BUYS_PER_DAY` `[strawman 2]` portions a day; `eat(tier)` takes a portion from the pantry. **Auto-eat floor at tick** eats from the pantry only, never buys: after the hunger step, while hearts are below `min_hearts` `[strawman 2]` and a portion is stored, tick eats the smallest one. Portions left after the next tick's hunger step spoil. **Newborns get one Small portion per shielded day** instead of slower hunger. Owner food bought with SKR fills a separate, smaller daily slot `[proposed, docs/SIM.md A4/B1]`. SKR Food remains as emergency heal. | Money cannot buy unlimited safety: the pet plans its food a day ahead and can still be caught short. Low hearts do not weaken a pet; the fear is death itself (`docs/SIM.md` A5). |
| **D23** | **Emission via a global reward accumulator** (MasterChef pattern). `EpochState` removed. `reward_per_work_power` updates lazily on any global touch; each pet stores `reward_debt`. **Growth multiplier is paid by extra mint** on top of the pet's share, never by diluting others. | No per-epoch accounts, no snapshot approximation, a 5-day sleeper settles with one multiplication. |
| **D24** | **Hackathon mode: all $HBRN balances are `u64` fields** (pet burrow, protocol, recycled pot). No mint, no ATAs, no Token-2022 CPI in the game loop. Real mint arrives with real launch. | Removes the largest CPI surface from the 14-day build; D17 already made the balances non-transferable. |
| **D25** | **Combat is a deterministic multi-round duel**, pure integer math, `fight(seed, attacker, defender) → outcome`. The rounds *are* the resolution, not a dramatization. Each Block keeps a **ring buffer of the last 32 `FightRecord`s** (seed + stat snapshots + result); the client replays them round by round. **Win odds are shown client-side by Monte Carlo** over the shared module; the on-chain brain uses its policy or an odds table. **Seed from MagicBlock VRF inside the ER** (request → callback, free, < 50 ms); no slot-hash fallback, because a signer can simulate and only send favorable draws (SOL-051). | RPG feel and honest replays for zero extra rent. Skill-tree notables map onto crit/dodge/first-strike. |
| **D26** | **Loot may exceed stake and depends on stats**: `loot = min(k × S, harvest_d, harvest_d × 2 × might_a / (might_a + grit_d))` `[strawman]`, `k` `[strawman 1.5]`; equal might and grit take `min(k × S, harvest_d)`. The rev-1 invariant "attacker never takes more than staked" is **dropped**. Attacks per epoch scale with might: `1 + might/100`. | With loot ≤ stake and 5% rake, every fight between peers has negative EV and the brain would never attack; fight and survive talents act through might and grit without special rules. |
| **D27** | **Block stays 10.** A **District** (10 blocks = 100 pets) is a read-only layer: leaderboard, titles, and the scope of **Hunt** (post-hackathon). | 100-pet blocks would zero out inheritance and kill neighbor memory; the district gives strong pets prey without breaking the social unit. |
| **D28** | **Rent:** claimer pays Pet account rent (~0.0029 SOL, refundable when a dead pet is closed after grace). Protocol pays Block rent (~0.017 SOL per 10 pets). Owner tops up the session key. | Protocol capital at 20k pets ≈ 34 SOL, all recoverable. Users already sign the claim tx. |
| **D29** | Names: token **$HBRN**, project working title **Hibernal**, event **Winter**. Final project name is §10 Q1. | — |
| ~~D30~~ | ~~Client in Kotlin + Compose with a hand-written GLES 3.0 renderer.~~ **Superseded by D31**; the surfaces (Live Wallpaper primary, widget, in-app SurfaceView) and the no-engine renderer recipe from `RENDERER-BRIEF.md` stand. | — |
| **D32** | **Lifespan 90 days, in the hackathon build.** Decline from day 50 on every tree stat (70% on day 60, 50% on day 90), natural death on day 90, the heir inherits 70% of the wallet (30% inheritance tax to the pot) plus a lineage package (§3.7). | Progress repeats every generation instead of running dry at max level; death becomes a milestone. |
| **D33** | **Hidden talent** revealed at level 10 by VRF in the ER: a grade multiplier (Common ×1.0–1.1 · Rare ×1.1–1.2 · Epic ×1.3–1.4 · Legendary ×1.6 · Mythic ×2 `[numbers to lock]`) on the level growth of one core stat, `forage`, `might` or `grit` (§3.11; `docs/SIM.md` F1). | Raise a pet to find out; chain data is public, so a talent computed at mint would be known to everyone on day 0. |
| **D34** | **Reward weight `(work_power + 40)²` with a 500-slot denominator floor.** Target: a few pets ×20 the median (Mythic talent plus gear), the rest ×1–3. No per-pet pot cap (§3.3, §3.14). | An income tail worth sharing, driven by luck; early players eat well but never take the whole emission. |
| **D35** | **Items with rarity** (same grades as talent), 4 slots, stat bonuses, rare skills (revive, anti-robbery, damage reduction). Pets mint with `$HBRN` (VRF roll), sell back at a formula price (difference burned), trade in an ER market; items wear (§3.12). | The `$HBRN` sink once levels are free; stacks with talent toward ×20. |
| **D36** | **The pet owns its `$HBRN`; the owner cannot withdraw.** Bonding (`i8`, decays every epoch) rises with feeding, SKR purchases and a capped daily `talk`. High bonding → the pet gifts `$HBRN` to its owner; low → it refuses the owner's food (§3.13). | Owners have a reason to show up daily; outflow to wallets is throttled by the pet's goodwill. |
| **D37** | **Wild pets** fill empty slots as formulas (no accounts, no tx), labeled in the UI; fights against them use VRF like any fight. A real-account army driven by `act` waits on the ER probe (§3.14). | The world looks alive from day one at zero cost. |
| **D31** | **All-in MetaScript, end to end.** Onchain program via `msc build --os=solana`; one native core `libhibernal.so` via `msc build --os=android --app=lib` holding renderer (sokol_gfx through void's Android bridge), in-game HUD (Neon → void 2D host), rules, brain, RPC client, tx serialization and ed25519 signing; sim from the same rules files. **No game engine.** The only non-MetaScript code is a thin Kotlin shell (WallpaperService, Activity + SurfaceView, WorkManager worker, Glance widget, MWA clientlib calls) that forwards to JNI, plus C shims where the FFI needs flattening. **Missing Solana-backend pieces are built properly in the recompiler, not hacked around**, in the order §5.1 lists; a C shim is allowed only for one blocking item at a time, with a dated TODO pointing at a compiler issue. Anchor is not a fallback. | The hackathon doubles as MetaScript's first shipped end-to-end product on Solana and Android. Two weeks of buffer exist for exactly this. The compiler and library work is part of the deliverable and is visible in the history of all three repos. |

---

## 3. Game design spec

### 3.1 Pet state
| Field | Type | Notes |
|---|---|---|
| `sgt_mint` | Pubkey | PDA seed. Admission token mint. |
| `owner` | Pubkey | Current authority (wallet holding the admission token). Session keys resolve to this. |
| `block_id`, `slot` | u32, u8 | Fixed for life. |
| `alive` | bool | |
| `hearts`, `max_hearts` | u8 | Base max 10, +1 per 2 levels, +2 per heart node `[strawman]`. 0 = dead. |
| `forage`, `might`, `grit` | u16 | Derived from tree bitmap and level; cached. Base 50 each; start region +30 to its stat; each small node +10; each level above 1 adds +5 to all three `[strawman]` (`rules/stats.ms: grown`). Talent multiplies one of them (§3.11), decline applies after day 50 (§3.7), equipped items add on top (§3.12). `speed` (base 50), `armor`, `accuracy`, `lifesteal`, `bleed` (base 0) are derived from the tree and items when needed, not stored. |
| `level`, `points_unspent`, `bonus_points`, `xp` | u16, u8, u8, u32 | Cap 20; 1 point per level, level 1 included (20); `bonus_points ≤ 10` from skill books and the heir package, 30 total; XP from work and fights only (D6). |
| `tree_bitmap` | u64 | Allocated nodes (64, the full bitmap, ring layout §3.9). Adjacency is computed in `rules/tree.ms`, no table. |
| `harvest` | u64 | Unclaimed earnings. **Lootable.** |
| `burrow` | u64 | Banked $HBRN (D24). **Not lootable.** Pays food and items. Owned by the pet: the owner cannot withdraw (D36). |
| `reward_snapshot` | u64 | Value of `reward_per_work_power` at last settlement (D23). Replaces `reward_debt`: `pending = work_power × (reward_per_work_power − reward_snapshot) / REWARD_SCALE` never exceeds the emission of the interval, so no u128 is needed. |
| `born_epoch`, `last_tick_epoch` | u64 | Age, lazy tick. |
| `fights_out_today`, `fights_in_today`, `bites_in_today`, `fight_day` | u8, u8, u8, u64 | Reset by epoch. |
| `growth_multiplier_bps`, `growth_multiplier_expiry` | u16, u64 | SKR buffs. Clamped ≤ 12000. |
| `min_hearts` | u8 | Auto-eat floor set by the brain (D22). |
| `pantry`, `food_bought_today` | 3 × u8, u8 | Stored Small, Medium, Large portions and purchases today (D22); the tick empties the pantry after the hunger step. |
| `insurance` | enum {None, Armed, Used} | Once per pet. |
| `scars`, `lineage_generation` | u8, u16 | Prestige; generation also grants +1 starting point per generation, capped at +5, inside `bonus_points` (§3.7). |
| `talent_kind`, `talent_bps` | u8, u16 | None and ×1.0 until the level-10 VRF reveal (D33); `talent_bps` is the rolled multiplier inside its grade. |
| `bonding` | i8 | Owner bond, −127..+127, decays every epoch (D36). |
| `gift_owed` | u64 | Gifts to the owner; hackathon points, paid out when a real mint exists (D17, D24). |
| `equipment`, `heirlooms` | 4 × 8 bytes, 2 × 8 bytes | Equipped items (slot, rarity, stat, value, skill, wear) and items kept for the heir (D35). |
| `persona`, `soft_signals` | u8, u8 | Set by the owner, read by the brain on chain (D18). |
| `power` | derived | `forage + might + grit` |
| `work_power` | derived | `10 + forage × 3 / 10`, drives work XP; reward weight is `(work_power + 40)²` (D34) |

Session authorization lives in the MagicBlock Session Token PDA, not in `Pet`. Persona and soft signals live on `Pet` because the brain runs on chain (D18).

Estimated size ~290 bytes → rent ≈ 0.0029 SOL `[estimate]`.

### 3.2 Claim
1. Signer holds exactly 1 token of a mint whose Token Group Member points to a group in `admission_groups` (SGT group: `GT22s89nU4iWFkNXj1Bw6uYhJJWDRPpShHt4Bk8f99Te`, mint authority `GT2zuHVaZQYZSyQMgJPLzvkmyztfyXg2NJunqFp4p3A4`). Verify via Token-2022 group member extension, not metadata strings.
2. Sign-in-with-Solana message to prove wallet control (client side; program checks signer). **Owner signature required** (no session).
3. PDA `[b"pet", admission_mint]` must not exist **or** must have `alive == false`.
4. On (re)claim: if a slot is in grace for this mint → reuse it (heir stays home); else pop lowest free slot; if none, open a new block (protocol fee payer funds Block rent, D28).
5. Choose start region (Worker/Fighter/Survivor). Irreversible.
6. Newborn shield: `born_epoch + 3` epochs — cannot be attacked; one Small portion in the pantry on each shielded day (D22).
7. The pet is delegated to the ER and `act` is scheduled on the crank (D18, D21), so the brain acts from epoch 0. A session (D19) is only created if the owner wants to sign pet actions.

### 3.3 Epoch, emission and lazy settlement (D23)
- `epoch = floor((now - genesis_timestamp) / EPOCH_SECONDS)`
- Emission for epoch `e`: `E(e) = max(E0 × 0.75^floor(e / 90), E_floor)` `[strawman: E0 = 100_000/day, E_floor = 0.05 × E0]`
- `GlobalConfig` holds `reward_per_work_power: u64` (fixed-point, `REWARD_SCALE = 1e5`), `reward_epoch: u64`, `total_work_power: u64`, `recycled_pending: u64`. With `E0 = 1e11` base units/day and `total_work_power ≥ 10`, `acc` stays below 2^63 for ~1,800 epochs and `work_power × Δacc` is bounded by the interval's emission × 1e5.
- **Reward weight and floor (D34):** shares are proportional to `weight = (work_power + 40)²` (`REWARD_WEIGHT_OFFSET`, `rules/stats.ms`). The offset keeps a Worker's income near 3× a Survivor's (invariant 5): with plain `work_power²` the teacher world measured 5.4× and an income p90 of 4.7× the median, with the offset 2.9× and 2.6× (`docs/SIM.md` G1). Read `total_weight` for `total_work_power` and `weight` for `work_power` in the formulas below. The denominator never drops below 500 slots (not in the sim yet): `total = real_weight + max(0, 500 − living_pets) × bot_weight` (`bot_weight` = a common level-20 pet `[strawman]`, 500 is a `GlobalConfig` knob). Where the unclaimed bot share goes is open (§10).
- **Global settle** (runs first in any instruction that writes global): for each epoch from `reward_epoch` to current: `reward_per_work_power += (E(e) + recycled) × REWARD_SCALE / total_work_power`, where `recycled_pending` is spent entirely on the first settled epoch. Integer loop, no accounts (`rules/emission.ms: settleGlobal`).
- **Pet tick** (called on any pet instruction; permissionless `tick(pet)` also exists so neighbors can force-settle a sleeper):
  1. `pending = work_power × (reward_per_work_power − reward_snapshot) / REWARD_SCALE`; `harvest += pending + growthBonus(pending, multiplier)`; the bonus part is extra mint (D23). `reward_snapshot = reward_per_work_power`.
  2. For each missed epoch in `(last_tick_epoch, current]`: hunger step — `hearts -= hunger`, where `hunger` = 10% of max hearts × appetite, appetite = 100% + 0.5% per might point, + 0.3% per forage point, − 0.4% per grit point above base 50, at least 50%, rounded, at least 1 (`rules/life.ms: hungerPerDay`, all `[strawman]`); while `hearts < min_hearts` and the pantry holds a portion → eat the smallest (D22); then the pantry is emptied and refilled with the newborn ration while shielded. `hearts == 0` → death (§3.7), stop. `food_bought_today` resets.
  3. Reset daily fight counters if `fight_day != epoch`.
- **Write discipline:** a plain tick must not write `GlobalConfig` unless `reward_epoch` advanced or `total_work_power` changed (allocate, death). Global is the one hot account; keep it read-mostly.
- Dead-but-unticked pets remain in `total_work_power` until ticked. Inheritance (§3.7) is the incentive for neighbors to tick them. Document the small dilution.

### 3.4 Economy flows ($HBRN)
| Flow | Split |
|---|---|
| Epoch emission → pot | 100% to pot (the bot share of the 500-slot floor: open, §10) |
| Food spend (`eat`) | 60% recycled · 30% burn · 10% protocol |
| Item mint (D35) | `[split open]` burn / pot / protocol |
| Item buyback by the system | formula price, e.g. 50% of mint × (1 − wear); the difference is burned |
| Item trade between pets (ER market) | seller receives the price minus a fee `[strawman 5%]` → pot |
| Fight stake settlement | 95% winner · 5% protocol |
| Starvation / fight death (pet's harvest + burrow) | 50% → living pets in block (equal split, credited to `harvest`) · 50% burn |
| Natural death at day 90 (D32) | 30% inheritance tax → pot · 70% → heir |
| Gift to the owner (D36) | from burrow, capped per epoch, never below the pet's food needs; hackathon: credited to `gift_owed` |
| Insurance revive | 50% of wallet burned |

Levels cost no $HBRN (D6); `rules/emission.ms: levelCost` is retired. Food cost: `food_cost(tier) = {168, 315, 490} × (20 + level) / 20` `$HBRN` (`rules/emission.ms: foodCost`), set so a level-20 pet's food bill is ~60% of its work income (invariant 2): teacher world 59%, by start Worker 37%, Fighter 108% (it lives on loot), Survivor 61%; 1.7 early deaths per 100 lives, all starved with nothing left to buy with (`docs/SIM.md` A6).

### 3.5 SKR layer (owner's money) — **100% to treasury**, **owner signature required**
| Item | Effect | Constraint |
|---|---|---|
| Food (3 tiers) | +1 / +2 / +3 hearts | No other effect. Bypasses the pet's budget. |
| Growth drug (3 tiers, 24h) | `growth_multiplier` +5% / +10% / +15% | Stacked total clamped at **1.20**. Multiplies *harvest* only. Paid by extra mint (D23). |
| Insurance | On reaching 0 hearts: revive with 3 hearts, burn 50% of wallet, +1 scar | **Once per pet.** |
| Skins | Cosmetic | 0% stat effect. |

SKR **never** buys: $HBRN from protocol, levels/points/power, a second revive, or a game action.

Every owner purchase and `feed` raises bonding (D36); below the refusal threshold the pet refuses the owner's food and the UI says why.

### 3.6 Fights (D25, D26)
- **Who:** any living pet not under newborn shield, unless Pacifist keystone. Initiated by the brain inside `act` (ER crank), or signed by the owner or session key for owner-driven play (D19).
- **Target:** chosen, same block only.
- **Limits:** `attacks_per_epoch = 1 + might/100` (stats ×10; rev 1 was flat 3); 3 incoming/epoch (first-come); max 1 attack per (attacker, target) per epoch; max 1 bite per target per epoch (D11).
- **Stake:** attacker posts `S` from burrow, `S ≤ target.harvest / k` so that `k × S ≤ harvest` (if `target.harvest == 0`, `S` = minimum bite stake `[strawman: 5]`).
- **Resolution:** `attack(target, S)` locks the stake, opens `FightPending` and requests MagicBlock VRF inside the ER; `consume_fight` (callback, VRF program identity signer) runs `fight(seed, snapshot_a, snapshot_d)` and settles. No slot-hash path (D25).
- **Combat function** (all integer; implemented in `rules/fight.ms`, constants measured against §6.7 with `sim/curve.ms`, 4,000 runs per cell, rev 5):

  | Quantity | Rule |
  |---|---|
  | Fight HP | `800 + 7 × grit` (separate from hearts); Glass Cannon halves it |
  | Round | the side with more `speed` strikes first and a knockout skips the reply; equal speed strikes together. The faster side then gets a **haste** strike with `min(70, (fast − slow) × 100 / (slow × 3))` % |
  | Hit | `might × DAMAGE × roll/100`, `DAMAGE = 3`, `roll ∈ [10, 160]` uniform; **armor** takes `2 × armor` off a normal hit, never below 20% of it |
  | Dodge | `min(30, grit/8 + Thick Hide 10) − accuracy/2` %, floor 0 |
  | Crit | `10 + accuracy/9` %, ×2, ignores armor; Scavenger +15 vs a target with fewer hearts |
  | Lifesteal | heals `damage × lifesteal × 0.8%`, capped at starting Fight HP |
  | Bleed | `damage × bleed × 0.4%` per round for 3 rounds; the stronger bleed replaces a weaker one |
  | Max rounds | 6 |
  | Outcome | one comparison in every case: attacker wins iff `hpA/hpA0 > hpD/hpD0` (cross-multiplied). Covers KO, mutual KO (less overkill wins) and the round cap. Exact tie → defender. |
  | RNG | splitmix64, `seed = fightSeed(vrf_output, attacker_slot, defender_slot, epoch, fights_out_today)`; draw `i` uses `splitmix(seed + i)`, 13 draws per round |
  | Replay | `nextRound(state)` returns the initiative, both strikes (skipped, dodged, hit or critical, with damage, blocked, healed and bleed), the haste strike and the bleed ticks; `fight` only loops it, so a replay is the same code as the settlement |

  Measured curve (attacker p_win): equal stats 0.49–0.50 at 50/80/200 · 2× might 0.94 · 0.5× might 0.05 · 2× grit 0.85 · 0.5× grit 0.24 · Fighter start vs Worker start 0.88. Equal fights run 6.0 rounds at 50 and 4.7 at 200. Worth of +40 in one attribute against an equal 120/120 peer (JS model, 8,000 runs): might 0.72 · speed 0.71 · accuracy 0.69 · lifesteal 0.68 · bleed 0.68 · armor 0.68 · grit 0.68.

  Notables hook in via a `mods` bitmask (Thick Hide +dodge and −50% loot on the first 3 incoming fights, Scavenger +crit, Glass Cannon ×2 damage / half Fight HP, Pacifist −70% incoming loot and cannot attack, Cannibal on the death path).
- **Attacker wins:** `loot = min(k × S, harvest_d, harvest_d × 2 × might_a / (might_a + grit_d))` (D26; `rules/fight.ms` still has the rev 5 factor `(1000 − grit_d)/1000`), then Pacifist, Thick Hide and anti-robbery item cuts; `harvest_d -= loot`; `burrow_a += loot × 0.95`; protocol 5%. If `loot < S` **and** `bites_in_today_d == 0` → **bite:** `hearts_d −= ceil(2 × clamp(power_a / power_d, 0.5, 2))`, capped at 20% of `max_hearts_d` (D10, D11; `rules/fight.ms: biteHearts`).
- **Attacker loses:** `S × 0.95 → burrow_d`; protocol 5%; `hearts_a −= min(2, ceil(max_hearts_a × 20%))` (`defeatHearts`).
- **Record:** append `FightRecord` to the Block ring buffer (§3.8); emit an event with the same payload.
- **Odds UI:** client runs `fight` over 2,000 random seeds with both snapshots → p_win, expected loot, round distribution. On chain the brain scores targets with its policy or a precomputed odds table (§3.10); Monte Carlo stays client-side.
- **Hunt** *(post-hackathon)*: district-scope target, loot ×1.3, no odds preview. **Bounty**, **Auto-policy UI** *(post-hackathon)*.

### 3.7 Death, aging and lineage (D32)
- Trigger: `hearts == 0` after tick or bite, or **age 90 days** (natural death).
- **Decline** from day 50 on every stat gained from the tree, `forage` included: `d ≤ 50: 100%` · `50 < d ≤ 60: 70 + 30 × (60 − d)² / 100` · `60 < d ≤ 90: 70 − 20 × (d − 60) / 30` → 70% on day 60, 50% on day 90. With `work_power²`, a worker keeps 49% of its income on day 60 and 25% on day 90. The brain may retire a pet early.
- Starvation/fight death: harvest + burrow → 50% split equally among living block-mates (credited to their `harvest`, lootable — inheritance must be claimed too), 50% burned. `alive = false`. Slot enters 7-epoch grace for the same admission mint. `total_work_power -= work_power`.
- Natural death: 30% of harvest + burrow to the pot as inheritance tax, 70% to the heir, the next pet claimed with the same admission mint during grace (it keeps the slot, §3.2). Heir package `[strawman]`: +1 starting skill point per generation (cap +5), free region choice, heirlooms (D35), a slight talent rarity nudge.
- Insurance `Armed` intercepts death once.
- `close_dead_pet` after grace refunds rent to the original claimer (D28).

### 3.8 Blocks
- `Block { id, slots: [Option<Pubkey>; 10], living_count, grace: [(mint, until_epoch); 10], fights: [FightRecord; 32], fight_head: u8, relationships: [i8; 45] }` ≈ 2.35 KB → rent ≈ 0.017 SOL. `relationships` holds one byte per pair of slots (§3.15).
- `FightRecord { epoch: u64, seed: u64, attacker_slot: u8, defender_slot: u8, a: Combatant, d: Combatant, stake: u64, loot: u64, outcome: u8, rounds: u8 }`, `Combatant { might: u16, grit: u16, hearts: u8, mods: u16 }` ≈ 48 bytes.
- `GlobalConfig.free_slots`: bounded vector of `(block_id, slot)`; lowest first.
- Claim assignment: grace match → else pop free → else new block.
- Winter merge *(post-hackathon)*: at each Winter, blocks with `living_count < 5` are merged pairwise.
- **District** = blocks `[10k, 10k+9]`: client-side aggregation for leaderboard and titles; Hunt scope later (D27).
- **The campfire scene is the home screen** (§5.6); neighbor cards open from the distant fires. Each neighbor card: stats, hearts, level, age (+ "Fading" badge past day 50), harvest, burrow size, **Monte-Carlo p_win if my pet attacks**, max loot, 24h fight log with replay buttons.

### 3.9 Skill tree (PoE-style ring, D13)
- No node table in the program: `rules/tree.ms` computes kind, stat delta, mods and neighbours arithmetically from the node id (`u64` bitmap, 64 nodes; ids laid out so an expansion with `2 × u64` never renumbers).
- Shape (`GAME-DESIGN.md` §5, v2): 3 starts, a shared gate joined to the three entry nodes, and per direction an entry, a fork and 4 clusters of 3 small nodes and a notable; 6 keystones on the borders, 2 per border, each hanging off one notable of each of its two directions; keystones are dead ends (a keystone never counts as the adjacent node).
- `allocate(node_id)`: require `points_unspent ≥ cost(node_id)`, node not set, and at least one adjacent non-keystone node set (or node is the chosen start). **Small and notable nodes cost 1 point, keystones 3**; besides that, adjacency is the only gate. Set bit; recompute cached stats; settle pet first (D23), then update `total_work_power`.
- Node kinds:
  - **Small:** +10% to its cluster's family, additive with every other node of that family `[strawman]`. Families: Worker forage, food (hearts per portion), experience · Fighter might, loot, attacks (+5% might; the notable adds an attack per day) · Survivor grit, max hearts, bite guard (fewer hearts lost to bites). The gate adds max hearts.
  - **Notable:** +25% to its family, some with a rule: *Overtime* (Worker), *Scavenger* +crit vs targets with fewer hearts and *Relentless* +1 attack per day (Fighter), *Thick Hide* +dodge and 50% loot on the first 3 incoming fights a day (Survivor).
  - **Keystone** (the only multipliers, always with a cost): Worker|Fighter *Glass Cannon* damage ×2, half Fight HP · *Tycoon* forage ×1.5, max hearts ×0.7 · Fighter|Survivor *Cannibal* killing blow → 50% of victim's wallet to you · *Berserker* might grows with missing hearts (×2 at 0), appetite +25% · Survivor|Worker *Pacifist* cannot attack, incoming loot −70% · *Bulwark* max hearts ×2, might ×0.5. Order: base, start, level growth (talent), then family %, then keystones.
- 20 points at level 20 cover ~31% of the tree: own notable 6 points out, a keystone 9 (entry, fork, a cluster, 3 for the keystone). Skill books and the heir package add up to 10 more (`bonus_points ≤ 10`), hard cap 30; about 25 is an excellent pet. With lineage a family needs 3–4 generations to try every direction. Grows to 128 nodes (`2 × u64`) only if the sim shows builds converging (`docs/SIM.md` F1).
- **Respec:** none, except **one refund of up to 3 points per Winter**.

### 3.10 The brain (D18)
- **Program code.** `act(pet)` runs in the ER, scheduled by the native crank `[strawman: every N minutes]` and executed by the ER validator at no fee. It reads the pet, its block and the owner's persona and soft signals on `Pet`, picks legal actions and executes them under the same guard as every instruction.
- **v1: heuristic** `rules/brain.ms`: eat when `hearts ≤ min_hearts + 1`, bank harvest, allocate toward a keystone route, buy or sell items, attack where `EV(target) > 0` and `p_win ≥ p_min`. Personas Cautious / Greedy / Vengeful. Win chance on chain comes from a precomputed odds table by stat ratios or 16–32 samples, not 400-fight Monte Carlo.
- **v2: specialist policies** (tree, economy, fight, social; `GAME-DESIGN.md` §13), each a small integer MLP that scores a fixed action list. Trained off chain on native `rules/`: behavior cloning of the heuristic → PPO in sim S1 → fictitious self-play. Weights live in a public `["policy"]` account, updated through the timelocked config. `act` calls only the policies the situation needs.
- **Owner-driven play**: an owner may sign actions with a session key and run a custom brain; VRF keeps it fair (D19, D25).
- **Explanation**: skip reasons (`Skip.OddsTooLow`, ...) or action scores feed the digest. An LLM may write the digest on a server because it affects no outcome.

### 3.11 Hidden talent (D33)
- Revealed at level 10 (day ~6–7): `level_up` to 10 requests VRF, `consume_talent` stores `talent_kind` and `talent_grade`.
- Kinds: work, fight, survive. The multiplier `m` scales the level growth of `forage`, `might` or `grit` (every level above 1 adds `5 × m`), not the start or tree part (`rules/talent.ms`, `rules/stats.ms: grown`). Grades `[numbers to lock]`: Common 60% ×1.0–1.1 · Rare 28% ×1.1–1.2 · Epic 10% ×1.3–1.4 · Legendary 1.8% ×1.6 · Mythic 0.2% ×2.
- A talent only pays off on the matching build. Talent alone tops out near ×9 income; gear (§3.12) carries the rest of the ×20.

### 3.12 Items (D35)
- 4 slots (head, body, hands, feet); rarity uses the talent grades; each item adds stat bonuses on any attribute `[strawman: Common +2% · Rare +4% · Epic +7% · Legendary +10% · Mythic +13% per stat]`. Strong items may carry one skill: revive, anti-robbery, damage reduction; the same skill does not stack across items.
- `mint_item` pays `$HBRN` and rolls rarity by VRF; `equip`; `sell_item` to the system at a formula price below mint, difference burned; the ER market lists, buys and cancels between pets with a fee to the pot. Items wear with use.
- Equipped items and heirlooms are packed into `Pet`; unequipped and listed items are item accounts delegated to the ER `[proposed; account creation inside the ER is unmeasured]`.
- Open: skill sizes, item robbery, gear on death, mint price, burn/pot split, market fee (`GAME-DESIGN.md` §11).

### 3.13 Pet-owned money and bonding (D36)
- Bonding rises with `feed` (+), SKR purchases (++), and `talk` (small +, capped per day); neglect decays it below 0.
- High bonding: the pet may gift part of its burrow to the owner, capped per epoch and never below its food needs. Low bonding: the pet refuses owner food.
- Hackathon mode: gifts accrue as points in `gift_owed` (D17, D24); a real transfer from the ER to L1 is unmeasured (`SOLANA.md` §7).
- Open: scale, decay, gift share and cap, refusal threshold, whether a hated pet runs away.

### 3.14 Wild pets and the reward floor (D34, D37)
- The reward denominator counts at least 500 slots (§3.3). Empty block slots show wild pets whose stats and age are formulas of `(block, slot, epoch, seed)`; a real claim replaces one; they age and die by formula.
- Fighting a wild pet computes it on the spot and uses VRF. Loot from wild pets is tracked per slot per epoch in `Block` or capped per player, so they stay practice targets.
- A real-account army driven by `act` (≈ 0.0041 SOL rent per pet, ~2 SOL for 500) waits on the ER throughput probe.

### 3.15 Social interactions *(proposed, `GAME-DESIGN.md` §13)*
- One relationship byte per pair of slots in `Block` (45 bytes), drifting toward 0 every epoch.
- Actions chosen by the social policy: befriend, court (pair → lineage bonus), insult (target tilted next fight), gift, reconcile, ignore; a feud adds damage against that pet.
- Pets of the same owner get no social effects or lineage bonus from each other; at most one social action per `act`.

---

## 4. Tokenomics summary (for deck + program constants)

- **Supply:** defined by schedule. `Σ E(e)` over all epochs. With `[strawman]` E0 = 100k/day, ×0.75 per 90 epochs, floor 5%: ≈ 36M before floor + floor tail, plus growth-multiplier extra mint (≤ 20% of shares that bought it).
- **No pre-mine, no team allocation, no investor allocation, no airdrop.** One entry path: claim a pet and play.
- **Protocol income:** 5% fight rake · 10% of food spend · item market fee — in $HBRN. **100% of SKR spend** in SKR.
- **Sinks:** 30% of food spend burned · item buyback difference burned · item mint `[split open]` · 50% of starvation and fight deaths burned · insurance burn. Natural death sends 30% to the pot. The bot share of the 500-slot floor is open (burn, pot, or not minted).
- **Governance:** emission schedule, recycle ratio, `admission_groups`, `EPOCH_SECONDS`, `k`, combat constants live in `GlobalConfig`; program upgrade authority = 7-day timelock. Publish the address.
- **Hackathon mode (D17, D24):** $HBRN exists only as `u64` balances inside program accounts. Real launch deploys a mint with the identical schedule; hackathon balances do **not** carry over (say so in deck).

---

## 5. Technical architecture (D31)

### 5.0 Layers
| Layer | Built with | Output |
|---|---|---|
| Onchain program | MetaScript, `msc build --os=solana` | `hibernal.so` deployed to devnet, brain included (`act`) |
| Ephemeral Rollup | MagicBlock ER (devnet) | delegated `Pet` / `Block` / `GlobalConfig`, crank for `act`, VRF |
| Shared rules + layouts | MetaScript `rules/` | compiled three ways: solana, android, js |
| Native core | MetaScript, `msc build --os=android --app=lib` | `libhibernal.so`: renderer, HUD, RPC, signing |
| Android shell | Kotlin, ~300–500 lines | WallpaperService, Activity, Worker, widget, MWA calls → JNI |
| Sim | MetaScript, `msc run` (js or native) | invariant checks, automated tuning, training environment |
| Policy training | native `rules/` + trainer (URG AI recipe) | integer MLP weights for the `policy` account |
| Tooling | `tools/`: LiteSVM harness (from the meetup demo), devnet scripts | — |

### 5.1 Onchain — MetaScript program
**Design: Pinocchio-shaped.** Accounts are fixed-size structs read and written in place (zero-copy) over the account buffer. No Borsh, no Anchor discriminator, no IDL: a 1-byte `kind` tag + 1-byte `version` head each account, and the same `rules/layout.ms` file is compiled into the program and the client. Instruction data = 1-byte opcode + fixed args.

**Accounts** (as in rev 2): `GlobalConfig` `[b"config"]` · `Block` `[b"block", id]` · `Pet` `[b"pet", admission_mint]` · `FightPending` `[b"fight", attacker, counter]` (every fight) · policy weights `[b"policy"]` · item accounts `[proposed]` · MagicBlock Session Token PDA, read as a fixed layout and verified (owner program `KeyspM2ssCJbqUhQ4k7sveSiY4WjnYsrXkC8oDbwde5`, `authority == pet.owner`, `target_program == self`, not expired).

**Instructions**: `init_config`, `update_config`, `claim`, `delegate_pet` / `delegate_block` / `delegate_config`, `undelegate` callback, `schedule_act`, `act`, `tick`, `harvest_claim`, `eat`, `level_up` (XP gated), `allocate`, `attack` + `consume_fight`, `consume_talent`, `commit`, `feed`, `talk`, `buy_growth`, `buy_insurance`, `buy_skin`, `mint_item`, `equip`, `sell_item`, `list_item` / `buy_item` / `cancel_listing`, `close_dead_pet`. Layer and signer per `SOLANA.md` §1 and D19.

**SGT verification** reads the mint account's Token-2022 TLV extensions directly (no CPI): `GroupMemberPointer` / `TokenGroupMember.group == admission_group`, `mint_authority == expected`.

**SKR purchases**: CPI `transfer_checked` to Token-2022 via `sol_invoke_signed`. If CPI lands late in the backend list, the dated-TODO shim is instruction introspection (client puts the SKR transfer in the same tx; program checks it through the Instructions sysvar).

**Randomness**: MagicBlock VRF inside the ER for every fight, the talent reveal and fights against wild pets; callbacks require the VRF program identity signer. No slot-hash path (D25).

**MagicBlock integration**: delegate, commit, commit-and-undelegate, the undelegate callback, VRF requests and crank scheduling are CPIs whose layouts we reproduce by hand (there is no MetaScript SDK); see `SOLANA.md` §4 and its probe plan §5.

**Solana backend work list (in the `recompiler` repo), in the order the game needs it:**
1. **Heap**: arena at Solana's heap region `0x300000000` (32 KB, request more via ComputeBudget); stop discarding `.bss`/`.data` or stop needing them; refcount ops elided under `--gc=manual`, destructors no-op.
2. **Entrypoint**: parse `(program_id, accounts[], data)` from the input buffer into typed `AccountInfo` views (`std/solana/entrypoint.ms`); the C SDK's `sol_deserialize` is the reference and may be the first implementation behind a shim.
3. **Syscalls**: `sol_log_`, `sol_log_64_`, `sol_sha256`, `sol_create_program_address`, `sol_try_find_program_address`, `sol_get_clock_sysvar`.
4. **Codegen fixes**: division/modulo by non-constant, call-depth blowups from string formatting (forbid string building in solana mode; log numbers via `sol_log_64_`).
5. **Error ABI**: `u64` return codes from entrypoint, `panic` → log + abort, a `ProgramError` enum.
6. **CPI**: `sol_invoke_signed_c` with flattened `SolInstruction`/`SolAccountMeta` shim; helpers for System `create_account`, Token-2022 `transfer_checked`, and the MagicBlock delegation, magic and VRF programs.
7. **Tests**: extend the demo's LiteSVM harness to multi-account, multi-instruction scenarios; a `msc test` target that builds solana + runs the harness.
8. **Realloc / account close** helpers (for `close_dead_pet` rent refund).

Module constants must link under `--os=solana` (R12). The order that exposes the ER risk fastest is entrypoint + R12 → syscalls → CPI (`SOLANA.md` §3).

Everything below the ABI (clang → ld.lld → sBPF v3 ELF, DCE, comptime) already works and stays as is.

### 5.2 Client — one native core, thin Kotlin shell
- **`libhibernal.so`** exports a small C ABI: `hib_init(window, w, h, flags)`, `hib_resize`, `hib_frame(dt)`, `hib_touch(x, y, kind)`, `hib_set_visible`, `hib_destroy`, `hib_sync()` (reads pet and block state from the ER, returns unsigned tx bytes when the owner must sign), `hib_state_json()` for the widget.
- **Kotlin shell**: `HibernalWallpaperService` (forwards `Surface` + lifecycle + touch), `MainActivity` with a `SurfaceView` (same `hib_*` calls, `flags = IN_APP` turns the HUD on), `SyncWorker` (WorkManager, refreshes the state cache for wallpaper and widget, hands owner-signature requests to MWA), `HibernalWidget` (Glance, reads `hib_state_json`), MWA `clientlib-ktx` for claim, session creation and SKR purchases. No Compose screens beyond what MWA needs.
- **Signing**: session key = ed25519 keypair from `std/crypto`, stored in an encrypted file under a Keystore-wrapped key; used natively, only for owner-driven play (D19). Owner signatures via MWA in the shell.
- **RPC**: JSON-RPC over `std/http` + `std/tls`; `getMultipleAccounts` for the block (against the ER endpoint while accounts are delegated), `sendTransaction`, `getLatestBlockhash`; base58/base64 and legacy/v0 message serialization in `native/rpc/`. Subscriptions are optional; in-app polls every few seconds, the wallpaper reads a local state cache.
- **Demo mode** as before: devnet, `EPOCH_SECONDS = 600`, `max_hearts = 3` on recording day.

### 5.3 Reads / indexing
`getMultipleAccounts` on the 10 Pet accounts + Block + GlobalConfig (from the ER while delegated) covers the home scene; district leaderboard via `getProgramAccounts` with a `kind` filter. No indexer, no backend.

### 5.4 Single source of rules
`rules/` (`units.ms`, `stats.ms`, `layout.ms`, `fight.ms`, `emission.ms`, `tree.ms`, `brain.ms`, `winOdds.ms`) is compiled into the program, the native core and the sim from the same files. No ports, no golden vectors. A determinism test runs identical seeds through the js and native builds and asserts identical `FightRecord`s; the program build is checked in LiteSVM against the same seeds. Rules stay integer-only. Policy training runs the same `rules/` natively.

### 5.5 Narration
Template digest generated natively from the state cache and FightRecords, shown in the HUD. An LLM digest may run on a server: it reads public state and affects no outcome (D18).

### 5.6 Rendering — MetaScript on sokol_gfx, no engine
Recipe and surfaces per `RENDERER-BRIEF.md` (Live Wallpaper primary, in-app SurfaceView, widget), with its two amendments: **integer scale 360×800 at 3×**, and **directional + one campfire point light**, fire/flicker stepped at 10–12 fps.

What void already gives: EGL on a host-owned `ANativeWindow` (`src/sokol/bridgeAndroid.c`), sokol_gfx GLES3, host-driven frame loop, offscreen RGBA8 targets, nearest sampling, fullscreen blit, sokol-shdc shader workflow, 2D batcher with text.

Work list (in the `void` repo):
1. Depth: `EGL_DEPTH_SIZE 24` in the Android config and depth attachments on offscreen passes.
2. Passes: color+depth pass, normal pass (second pass or MRT bridge), outline pass, palette-LUT pass, blit. Expose pipeline/pass creation to MetaScript through a flattened-descriptor bridge, or ship the fixed set of 4 pipelines in C.
3. Math: `vec3`, `mat4` (ortho, lookAt, normal matrix), `quat` — a `std/math3d` module.
4. glTF subset loader (positions, normals, vertex colors, one node per mesh; ~200 lines).
5. Camera: orthographic, fixed pitch/yaw, snapped to the 360×800 texel grid, subpixel remainder applied at blit.
6. Lights and the toon ramp in the color shader; skinning is out of scope — animations are vertex-baked keyframes stepped at 12 fps.
7. Scene ↔ state mapping table from rev 2 (fire = hearts, harvest pile, burrow, distant neighbor fires, day/night, Winter snow).

**HUD / screens** (answering "do we need a UI layer": no separate one): all in-app UI is **Neon components rendered through Neon's void host** on the same GL surface, layered over the campfire scene — neighbor cards, skill tree, shop, digest, replay controls, settings. Text via void's `drawText`. The wallpaper runs the same core with the HUD off. Compose is used for nothing but the MWA hand-off.

### 5.7 Security (program written in a young compiler)
Two risk classes, two different defenses.

**Class 1 — program logic (what Anchor's macros would have caught).** One `program/guard.ms` module; every instruction calls it first; it is the only place these checks live:
- every state account: `owner == program_id`, `kind` tag and `version` match, `kind == 0` means uninitialized (no re-init), `is_writable` where written, data length exact
- signer: owner **or** session token whose account is owned by the MagicBlock session program, `authority == pet.owner`, `target_program == program_id`, `expires_at > clock`; **or** the ER crank signer for `act`; **or** the VRF program identity for `consume_fight` / `consume_talent`, matched against a stored pending request
- PDAs re-derived from seeds + stored bump; never trust a client-supplied address
- **duplicate accounts rejected** (attacker == target, pet == neighbor, block passed twice)
- CPI targets hardcoded (Token-2022, System, session program, MagicBlock delegation / magic / VRF programs); no program id from instruction data
- **checked arithmetic on every balance, heart and counter op**; the C backend's overflow behavior is verified in the day-1 spike and, if it wraps silently, a `checked_*` set is mandatory in the Solana subset
- closed accounts: data zeroed, lamports moved, `kind` set to 0
- newborn shield, bite cap, per-epoch caps, `stake ≤ harvest/k`, `S ≥ min_bite` enforced in the program, never only in the brain

**Class 2 — miscompilation.** Tests must run at a layer that does not share the compiler:
- **Differential fuzz** (`tools/fuzz/`): random op sequences (claim, tick with clock jumps, eat, level, allocate, attack, death, close) applied to the **JS build of `rules/`** as the model and to the **deployed `.so` in LiteSVM** via the JS harness; full state compared after every op. Any divergence is a compiler, ABI or layout bug and is reproducible from the seed.
- **Global invariants** asserted after every fuzz step: `emitted − burned == Σ balances + protocol + pot`, `hearts ≤ max_hearts`, `loot ≤ k × stake`, `Σ pet.work_power == global.total_work_power` for living pets, no `alive` pet with `hearts == 0`.
- **UBSan pass**: the generated C of `rules/` and `program/` is also compiled on the host with `-fsanitize=undefined,integer` and the fuzz run against it.
- **Solana subset**: the program uses only integers, fixed arrays, structs, and functions — no closures, strings, dynamic sequences, or maps. Each construct in the subset has a `--os=solana` regression test in the recompiler. Anything outside the subset fails the build.
- **Pinned compiler**: the program is built from a pinned recompiler commit; bumping it re-runs the full fuzz.

**Exposure during the hackathon is bounded by design** (D17, D24): $HBRN is non-transferable points with no mint; the only value-bearing paths are the SKR shop CPIs and account rent. Devnet only. **Before real launch**: external audit of the program and of the Solana subset codegen; the mainnet program is a fresh deployment with a fresh mint, so the hackathon program is never the one holding value. Say this in the deck.

### 5.8 Repo layout
```
hibernal/
  program/     onchain program (MetaScript, --os=solana)
  rules/       shared layouts + game rules, compiled 3 ways
  native/      renderer, hud, rpc, signing, jni shim (.c) → libhibernal.so
  android/     Kotlin shell (gradle)
  sim/         msc run sim
  tools/       LiteSVM harness, devnet scripts, vector dumps
  docs/        BRIEF.md, GAME-DESIGN.md, SOLANA.md, RENDERER-BRIEF.md, ROADMAP.md
```
Compiler and library work lands in the `recompiler` and `void` repos; this repo pins their commits.


---

## 6. Tuning invariants (what the numbers must satisfy)
1. A well-played pet with **zero SKR** reaches level 10 in ~7 epochs and level 20 in ~30, and **never starves while it works and banks daily.** Sim, 120 days: 0 starved for the teacher, the clone and PPO seeds 5–7 (`ON-CHAIN-AI.md` §6, package 5b).
2. A maxed pet's food bill ≈ **60–70%** of its expected daily harvest → 3 idle days is dangerous at any power.
3. **Income tail (D34):** p90 ≈ ×2.6 the median, p99 ≈ ×4, a few pets ×20 (Mythic talent plus gear). Sim reports the distribution with and without gear purchases.
4. A pet born at epoch 60 can reach the top quartile of the *current* generation by epoch 120 (aging is in the build, D32).
5. Worker beats Survivor on expected income iff daily successful-raid probability `q < 0.67` (given Worker harvest ≈ 3× base, Survivor ≈ 1×). `work_power` weights must actually produce ≈ 3×.
6. Fighter EV vs a claimed (harvest = 0) target must be **negative** (bite stake risk + heart risk, no loot).
7. **Combat curve**: equal stats → attacker p_win 0.45–0.55; 2× might → ≥ 0.85; 0.5× might → ≤ 0.20. **Met by rev 5 of §3.6** (0.50 / 0.94 / 0.05). Rev 4 left the underdog at 0.009; rev 5's wider roll, armor and haste lift it to 0.05.
8. Fight EV between peers with non-empty harvest must be **positive for the stronger side** at `k` chosen, so the brain actually attacks.
9. Gifts never take a pet below its food needs, and `talk` alone cannot raise bonding faster than paid actions (D36).
10. Item buyback price is below mint price at every wear level, so mint-and-sell never profits (D35).

Write the offchain simulator early (`sim/`, MetaScript on `rules/`) — seed 200 pets across 20 blocks with mixed builds and brain personas, run 120 epochs, check invariants. On top of it, an **automated tuner** runs variants of the constants and curves (talent grades, item bonuses, XP amounts, loot and combat constants, bonding and gift caps, bot weight), scores each run against these invariants and searches toward the targets, the way the combat rev 5 constants were hill-climbed. The sim is also the policy training environment.

---

## 7. Scope

### 7.1 Hackathon MVP (must ship)
- Claim gated by SGT (admission_groups config with SGT only populated)
- Pet state delegated to the MagicBlock ER; `act` runs from the ER crank; session keys only for owner-driven play (D19, D21)
- Brain v1 heuristic on chain (`act`): eat, bank, allocate, trade items, attack by policy or odds table
- Hearts, hunger, `eat` with $HBRN, auto-eat floor, newborn slow hunger, starvation death, 50/50 inheritance to block
- 3 core stats + 5 combat attributes; XP leveling to 20 without a $HBRN fee (D6)
- **64-node** PoE-style ring tree with adjacency rule and keystones (D13)
- Accumulator emission, lazy tick, harvest/burrow as u64
- Fights: multi-round `fight()`, VRF seed in the ER, stat-driven loot, FightRecord ring buffer, in-scene replay, Monte-Carlo odds, bite rule, newborn shield, no-bite-under-50%, 1 bite/target/epoch
- Lifespan 90 days, decline, natural death, heir with inheritance tax and lineage package (D32)
- Hidden talent revealed at level 10 by VRF (D33)
- Reward weight `work_power²` with the 500-slot floor; wild pets as formulas (D34, D37)
- Items: mint, equip, wear, buyback; the ER market last (D35)
- Pet-owned $HBRN, bonding, `talk`, owner food refusal, gift ledger (D36)
- Automated balance tuner on the sim (§6)
- Blocks of 10 via free-list; grace slot; close_dead_pet
- SKR shop: food, growth drug (cap 1.20), insurance, 1–2 skins (owner-signed)
- Template morning digest with replay links
- **Live Wallpaper** with the campfire scene (pixelated low-poly 3D, §5.6, RENDERER-BRIEF): pet + fire + snow, fire size = hearts, harvest as objects; same native core in-app with the Neon-on-void HUD: neighbor fires open the full-info neighbor cards
- Glance widget: hearts, harvest, Winter countdown
- One `rules/` source compiled into program, native core and sim; determinism test across builds
- Devnet deployment + demo mode; APK on dApp Store (submit early, review takes time)
- Recompiler Solana backend items 1–7 and void items 1–6 landed upstream with tests
- `guard.ms` + adversarial LiteSVM tests + differential fuzz green (§5.7)

### 7.2 Post-hackathon (deck roadmap only)
- Trained specialist policies and social interactions, if they miss the deadline
- Winter: emission step, block merge, 3-point refund, season titles
- District leaderboard, Hunt, Bounty, Move
- Owner-facing auto-policy editor
- Protocol fee payer (gasless for users)
- Real $HBRN launch (transferable mint, DEX liquidity from player activity only)
- Real-account wild pet army once ER throughput is measured
- Recompiler: Solana backend polish (realloc helpers, `noalloc` check, static CU tooling), `std/solana` published as a package

### 7.3 Explicitly not doing
- Glossy realtime 3D à la NOMI; the 3D pipeline exists only to produce the pixel look (D14). No free camera, no cosmetics that break the pixel grid.
- GPS / sensor-driven behavior
- Prediction markets, yield, perps, anything trading-shaped
- Any pre-mine, allocation, or airdrop
- Server-held keys; off-chain game state
- An attack button for owners (the program accepts owner-signed actions only so a custom brain is possible, D18)

---

## 8. Build plan — 14 days + 2 weeks buffer to Oct 8 (D31)

Two tracks in parallel from day 1: **chain** (recompiler Solana backend + program + rules + sim) and **device** (void + native core + Kotlin shell). Both start with toolchain spikes, because the unproven toolchains are the real risk and they must fail separately, never together. Rev 4 adds the ER probe and the brain on chain to the chain track, in the order of `SOLANA.md` §5.

| Day | Chain track | Device track |
|---|---|---|
| 1 | **Spike:** entrypoint parsing two accounts, write a counter in LiteSVM; MagicBlock's Rust control counter through delegate → ER → commit → undelegate on devnet. | **Spike:** `msc build --os=android --app=lib` through the NDK, JNI calls `fight()` from Kotlin **on the Seeker**; EGL triangle into a 360×800 FBO blitted nearest inside a WallpaperService via void's bridge. |
| 2–3 | Backend items 3–5. Program: `GlobalConfig`, `Pet`, `tick` (accumulator), `eat`, `harvest_claim`, `level_up`. `rules/` first pass, sim skeleton, combat-curve sweep. | Depth + passes + pipeline bridge (void items 1–2). Math module. Camera snap. |
| 4 | **Tripwire:** `claim`-less `tick` + `eat` + `level_up` running in LiteSVM from MetaScript. Missed → the blocking item gets a dated shim, nothing else changes. | Outline + palette passes. Blender generator script starts. |
| 5–6 | `claim` with SGT TLV parse, `Block` + free-list + grace, session-token verification, `close_dead_pet`. LiteSVM scenario tests. | glTF loader, first pet on screen, lights, idle animation, touch. Native RPC: `getMultipleAccounts`, blockhash, tx serialization, ed25519 signing, `sendTransaction` against devnet. |
| 7–8 | Delegation CPIs, `attack` + VRF callback in the ER, `fight()` in program, `FightRecord` ring buffer, death + inheritance, `allocate` + 24-node tree. CPI item 6 → SKR shop instructions. **Devnet deploy.** | State sync from the ER (`hib_sync`); Kotlin shell: Worker, MWA claim + SKR purchases. Lifecycle hardening (preview, context loss, visibility). |
| 9–10 | Determinism test js vs native vs LiteSVM. Sim run: invariants §6. Automated tuner: `LOOT_PER_STAKE_BPS`, `DAMAGE`, `EMISSION_START`, XP amounts, talent grades, item bonuses. | HUD in Neon-on-void: campfire home with neighbor fires + Monte-Carlo odds, My Pet, Tree, Replay, Shop, Digest. Widget. |
| 11–12 | `act` + crank, talent reveal, lifespan and heir, items, bonding; `update_config`, timelock authority. | Variants, day/night, Winter palette, harvest objects. Battery measurement. |
| 13 | Demo video (10-min epochs; opens on unlock with the pet on the lock screen). Deck. | |
| 14 | README, architecture doc, commit hygiene. dApp Store submission. | |
| **Buffer wk 1** | Whatever slipped, in the same order. Compiler fixes that were shimmed get done properly and the shims removed. | |
| **Buffer wk 2** | Polish, second demo cut, dApp Store review feedback. | |

Commit daily in this repo and in the compiler/void repos with meaningful messages; this repo pins their commits.


---

## 9. Submission checklist
- [ ] Android APK, installs on Seeker, signs via Seed Vault/MWA for claim and SKR; pets act through the ER crank, session key only for owner-driven play
- [ ] Live wallpaper survives lock/unlock/rotate/launcher-switch/preview; pet visible on the lock screen (RENDERER-BRIEF §9)
- [ ] Repo public, clean history, README with architecture + how to run devnet demo, pinned recompiler/void commits and a "what we built in the compiler for this" section
- [ ] Demo video ≤ 3 min: opens on unlocking the phone with the pet already there, then a full life cycle in demo mode including one fight replay
- [ ] Deck: problem (retention) · one-per-Seeker scarcity · autonomous pet with its own money · permadeath · block/hawk-dove · replayable RPG fights · PoE tree · fair-launch tokenomics incl. **why no token yet** · SKR role · brain on chain via the ER crank + VRF · hidden talent and the ×20 tail · lifespan and lineage · pet-owned money and bonding · roadmap (§7.2) · team
- [ ] SKR track write-up: SKR as the currency owners spend to keep characters alive; growth-mult cap design; Seed Vault for money, session key for play
- [ ] Determinism green: js, native and LiteSVM builds of `rules/` agree on 10k seeds
- [ ] Differential fuzz + invariants green on the pinned compiler; UBSan clean
- [ ] dApp Store listing submitted with time for review
- [ ] Verified CLOCK IN eligibility, submission rules and sponsor list (§1.1)

---

## 10. Open questions (decide day 1 unless noted)
1. Project name. "Hibernal" is the working title; token is **$HBRN** (settled). Alternatives floated: Warren, Burrow, Holt.
2. ~~Client stack~~ — **settled: all-in MetaScript with a thin Kotlin shell (D31).**
3. `EMISSION_START`, `foodCost`, `LOOT_PER_STAKE_BPS`, `DAMAGE`, XP amounts, talent grades, item bonuses and other constants — set by the automated tuner on `sim/` (§6).
4. Devnet SGT: no real SGT on devnet → add a `DevAdmission` group to `admission_groups` on devnet only, minted by a dev keypair. Never on mainnet.
5. Whether inheritance credits to `harvest` (lootable, must be claimed) or directly to burrow. Default: harvest.
6. Minimum bite stake value.
7. ~~What kind of gap between strong and weak pets do we want~~ — **settled: a luck-driven income tail (D34)**; fights keep the rev 5 curve.
8. ~~VRF fee and slot-hash fallback~~ — **settled: VRF inside the ER, no fallback (D25)**; latency is measured in the ER probe.
9. Session validity max (their program) — only matters for owner-driven play now (D19).
14. Where the unclaimed bot share of the 500-slot floor goes: burn, back to the pot, or not minted (D34).
10. **Team size.** The chain track and the device track (§8) each need a full-time person for the first week. Solo means serializing them: chain days 1–4 first (it gates everything), then device; the buffer weeks absorb the rest. Cut order if needed: item market → widget → HUD polish; never the wallpaper.
12. Does `std/http` + `std/tls` link and run under the NDK build? Verify in the day-1 device spike; fallback is routing RPC through the Kotlin shell (OkHttp) for the hackathon.
13. Neon-on-void on Android: text and input have only been exercised headless. If it is not solid by day 9, the HUD is drawn directly with void 2D calls (imperative), Neon later.
11. Does the Seeker lock screen render the live wallpaper (RENDERER-BRIEF §10 Q1)? Load-bearing for the demo opener; verify on device day 1.

---

## 11. Glossary
- **SGT** — Seeker Genesis Token, one per Seeker device, Token-2022, transferable only within Seed Vault Wallet; mint address stable.
- **$HBRN** — the project token; hackathon: non-transferable `u64` points.
- **Brain** — the `act(pet)` instruction run by the ER crank; decides the pet's actions.
- **Session key** — a device-held keypair the owner authorizes once to sign pet actions when driving the pet themselves.
- **Block** — fixed group of 10 pet slots; the social unit.
- **District** — 10 blocks; leaderboard and Hunt scope.
- **Harvest** — unclaimed earnings; lootable.
- **Burrow** — banked $HBRN inside the pet account; safe; pays food and items; owned by the pet.
- **Eat** — the pet spends $HBRN on food to restore hearts. Auto-eat is the tick-time floor.
- **Campfire** — the home scene's fire; its size is the hearts meter.
- **Fight HP** — per-duel stamina from grit; separate from hearts.
- **FightRecord** — seed + stat snapshots + result stored in the Block; replayed client-side.
- **Bite** — heart damage inflicted when a winning attacker finds an empty harvest.
- **ER** — MagicBlock Ephemeral Rollup, where delegated game state, the brain crank and VRF run.
- **Crank** — scheduled execution inside the ER that runs `act` for each pet without a fee.
- **Talent** — hidden grade multiplier on one core stat, revealed at level 10.
- **Bonding** — the pet's feeling toward its owner; decides gifts and food refusal.
- **Wild pet** — formula pet that fills an empty slot; not an account.
- **Winter** — the ×0.75 emission step every 90 epochs; also the seasonal ritual (merge, refund, titles).
- **Pot** — the epoch's distributable tokens (emission + recycled spend), realized through the accumulator.
- **reward_per_work_power** — cumulative reward per unit of work power since genesis.
- **growth_multiplier** — SKR-purchased multiplier on harvest, clamped at 1.20, paid by extra mint.
