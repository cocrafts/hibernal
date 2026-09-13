# PROJECT BRIEF — Hibernal (working title) · token $HBRN

> Purpose of this document: give every contributor full context, every decision already made, and the specs needed to scaffold and build the hackathon MVP. Treat the **Decisions** section as settled unless explicitly reopened. Treat numbers marked `[strawman]` as tunable defaults, not requirements.
>
> **Rev 3 (2026-09-12).** All-in MetaScript (D31) supersedes D20/D30's Anchor + Kotlin split; §5 and §8 rewritten. Art direction (D14 rev) and renderer brief alignment (D30) from the same day. Adds D18–D29 from the design sessions of Sept 10–11: autonomous pet, session-key signing, Anchor program, accumulator emission, multi-round combat with onchain replay records, L1-only. Rev 1 is archived alongside this file's history.

---

## 0. One-liner

**A Tamagotchi that can permanently die, one per Seeker phone, that lives its own life: it works, eats, fights its neighbors and spends its own money, while its owner can only feed it, buff it, and watch the replays.** Its economy runs on a fair-launched token that pets earn by working and fighting.

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
- **Transaction V1 activated Sept 9, 2026** — 3.3× max tx size, better multisig/ZK. We use it for the **"one signature morning"** bundle (tick + eat + harvest_claim + level_up + allocate in one tx). Mention in deck.
- Token ops ~95–98% cheaper in CU; 100M CU block limit. Onchain tick per pet is cheap.

### 1.5 Device
- Seeker: MediaTek Dimensity 7300, 8GB RAM, 128GB, Android 15, 4500mAh
- Realistic background budget for on-device inference: ~1–1.5GB → 0.6B–2B param model at Q4. Gemini Nano/AICore **not available** on this chip.

### 1.6 Infra evaluated and rejected (keep for deck Q&A)
- **MagicBlock Ephemeral Rollups** for game state: not needed. Game does 4–7 tx/pet/day on a 24h epoch; ER pays off only when actions ≫ commits. Delegated accounts freeze on L1, which fights the SKR purchase flow and cross-region blocks. Roadmap only, for real-time Hunt.
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
| D5 | Revenue = **100% of SKR spend** (treasury) + **protocol fees in $HBRN** (5% fight rake, 10% of upgrade and food spend, 2% in-game trade fee). No token allocation. | Fees flow only when the game works; allocation pays before it does. |
| D6 | **SKR buys multipliers (capped ×1.20), $HBRN buys levels (unbounded) and food.** SKR = owner's money. $HBRN = pet's earned money. | Whales get +20% *progress*, never +20% *power*. Power comes from the pet's own choices. |
| D7 | Epoch = **24h, boundary 00:00 UTC**, **lazy settlement** (no crank/cron). `EPOCH_SECONDS` is a program config (short for demo). | 7am VN, 4pm US-West, 9am EU. Demo video needs multiple cycles. |
| D8 | Fights: **anyone can attack, target is chosen (not random), block-only.** Full information UI with win odds shown. | Onchain is public anyway; design for full info. Fighter plays a probability game, not a slot machine. |
| D9 | **Loot is harvest, not savings.** Claimed tokens ("burrow") are unstealable. | Fixes the "Worker is a blood bag" problem. Claiming daily = safety. |
| D10 | **Fights don't kill; hunger kills.** Defender loses hearts only when harvest is empty ("bite"). Attacker loses a heart on any loss. | Death is slow, visible, avoidable. Attacking is risky. |
| D11 | **No biting a pet with power < 50% of yours.** Newborn shield 3 epochs. **Max 1 bite per target per epoch** `[strawman]`. | Anti-griefing. Fighters kill peers, not kids. A coordinated block cannot kill a healthy pet in 2 days. |
| D12 | **Blocks of 10, fixed, assigned by claim order via free-list.** Not chosen, not rotated. Death frees the slot (7-day grace for same SGT). Winter merges blocks with <5 living. | Persistent neighbors enable reading, revenge, inheritance, lineage. Costs nothing onchain. |
| D13 | Skill tree is **PoE-style**: shared web, 3 start regions, adjacency-constrained, small/notable/keystone nodes, **no respec** except 3-point refund each Winter. | Build = route to keystones. Hybrids emerge from pathing. |
| D14 | **Pixel-art look produced from low-poly 3D** (t3ssel8r technique: tiny orthographic render target, quantized lighting, screen-space outlines, nearest upscale). Reads as pixel art, but lights move. **Home scene = the pet sitting by a campfire in the snow**; the fire is the hearts meter. Narration via templates first; on-device LLM optional, timeboxed. *(rev 1 said flat 2D.)* | Visibly not NOMI's glossy 3D, and the campfire gives dynamic light that static sprites cannot. Never let the model block the demo. |
| D15 | Program upgrade authority under **7-day timelock** (not burned). | Fair-launch credibility + keeps D2's door and emission tuning open, transparently. |
| D17 | Run the hackathon build with **$HBRN as non-transferable points** on the same program logic; enable real emission only after retention data exists. | Design the economy while nothing is at stake. (Deck says this explicitly — it's a credibility point.) |
| **D18** | **The pet is autonomous.** A "brain" on the owner's phone decides every game action: work, eat, claim, level, allocate, whom to attack. The owner never issues game actions. Owner influence = SKR items (growth capped ×1.20, food, insurance, skins) and soft signals the brain weighs (e.g. a "grudge" on a neighbor). Brain v1 is a **heuristic policy with explicit EV math**; an LLM is an optional layer that picks among legal actions. The program is the referee: it enforces every rule, the brain only chooses. Server-side inference is allowed; **a server never holds keys.** | The pitch is agency, not a dashboard. Deterministic onchain rules keep the demo safe from a flaky model. |
| **D19** | **Session-key signing via MagicBlock Session Keys.** Owner signs once through Seed Vault to create a session (validity `[strawman 7d, their max]`, top-up 0.01 SOL for fees). Pet instructions accept **owner OR valid session key**. Claim, SKR purchases, session create/revoke require the owner. Post-hackathon: protocol fee payer (relayer) so users need no SOL. | No daily popups. Zero backend. Keys stay on the device. Anchor crate `session-keys` provides `#[session_auth_or]`. |
| ~~D20~~ | ~~Program in Anchor (Rust); rules module in MetaScript compiled to JS.~~ **Superseded by D31.** | — |
| **D21** | **Fully onchain on Solana L1.** No Ephemeral Rollup, no off-chain state DB. Fight records live onchain (D25). Reads via RPC account subscriptions; no indexer for MVP. | See §1.6. Cost is ~0.00005 SOL/pet/day. |
| **D22** | **$HBRN buys food.** `eat(tier)` costs $HBRN from burrow, restores hearts; spend splits 60/30/10 like upgrades. **Auto-eat floor at tick**: if hearts would fall below `min_hearts` `[strawman 2]` and burrow can afford tier 1, tick eats. **Newborn hunger is halved** for 3 epochs. SKR Food remains as emergency heal. | A zero-SKR pet that works can live indefinitely. The fear is not starving; it is being unable to work or raid. |
| **D23** | **Emission via a global reward accumulator** (MasterChef pattern). `EpochState` removed. `reward_per_work_power` updates lazily on any global touch; each pet stores `reward_debt`. **Growth multiplier is paid by extra mint** on top of the pet's share, never by diluting others. | No per-epoch accounts, no snapshot approximation, a 5-day sleeper settles with one multiplication. |
| **D24** | **Hackathon mode: all $HBRN balances are `u64` fields** (pet burrow, protocol, recycled pot). No mint, no ATAs, no Token-2022 CPI in the game loop. Real mint arrives with real launch. | Removes the largest CPI surface from the 14-day build; D17 already made the balances non-transferable. |
| **D25** | **Combat is a deterministic multi-round duel**, pure integer math, `fight(seed, attacker, defender) → outcome`. The rounds *are* the resolution, not a dramatization. Each Block keeps a **ring buffer of the last 32 `FightRecord`s** (seed + stat snapshots + result); the client replays them round by round. **Win odds are computed client-side by Monte Carlo** over the shared module. **Seed from MagicBlock VRF** (two-step: request → callback), fallback to slot hashes if VRF fee or latency is unacceptable. | RPG feel and honest replays for zero extra rent. Skill-tree notables map onto crit/dodge/first-strike. |
| **D26** | **Loot may exceed stake**: `loot = min(k × S, harvest_d) × (1 − grit_d/100)`, `k` `[strawman 1.5]`. The rev-1 invariant "attacker never takes more than staked" is **dropped**. Attacks per epoch may scale with might `[strawman 1 + might/10]`, pending §10 Q7. | With loot ≤ stake and 5% rake, every fight between peers has negative EV and the autonomous brain would never attack. |
| **D27** | **Block stays 10.** A **District** (10 blocks = 100 pets) is a read-only layer: leaderboard, titles, and the scope of **Hunt** (post-hackathon). | 100-pet blocks would zero out inheritance and kill neighbor memory; the district gives strong pets prey without breaking the social unit. |
| **D28** | **Rent:** claimer pays Pet account rent (~0.0024 SOL, refundable when a dead pet is closed after grace). Protocol pays Block rent (~0.017 SOL per 10 pets). Owner tops up the session key. | Protocol capital at 20k pets ≈ 34 SOL, all recoverable. Users already sign the claim tx. |
| **D29** | Names: token **$HBRN**, project working title **Hibernal**, event **Winter**. Final project name is §10 Q1. | — |
| ~~D30~~ | ~~Client in Kotlin + Compose with a hand-written GLES 3.0 renderer.~~ **Superseded by D31**; the surfaces (Live Wallpaper primary, widget, in-app SurfaceView) and the no-engine renderer recipe from `RENDERER-BRIEF.md` stand. | — |
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
| `hearts`, `max_hearts` | u8 | Base max 5. 0 = dead. |
| `forage`, `might`, `grit` | u16 | Derived from tree bitmap; cached. Base 5 each; start region +3 to its stat. |
| `level`, `points_unspent` | u16, u8 | 1 point per level. |
| `tree_bitmap` | u64 | Allocated nodes (24 for the hackathon, ≤ 64). Adjacency is computed in `rules/tree.ms`, no table. |
| `harvest` | u64 | Unclaimed earnings. **Lootable.** |
| `burrow` | u64 | Claimed $HBRN (D24). **Not lootable.** Pays food and levels. |
| `reward_snapshot` | u64 | Value of `reward_per_work_power` at last settlement (D23). Replaces `reward_debt`: `pending = work_power × (reward_per_work_power − reward_snapshot) / REWARD_SCALE` never exceeds the emission of the interval, so no u128 is needed. |
| `born_epoch`, `last_tick_epoch` | u64 | Age, lazy tick. |
| `fights_out_today`, `fights_in_today`, `bites_in_today`, `fight_day` | u8, u8, u8, u64 | Reset by epoch. |
| `growth_multiplier_bps`, `growth_multiplier_expiry` | u16, u64 | SKR buffs. Clamped ≤ 12000. |
| `min_hearts` | u8 | Auto-eat floor set by the brain (D22). |
| `insurance` | enum {None, Armed, Used} | Once per pet. |
| `scars`, `lineage_generation` | u8, u16 | Cosmetic/prestige. |
| `power` | derived | `forage + might + grit` |
| `work_power` | derived | `10 + forage × 3` `[strawman — sim must make Worker ≈ 3× base, see §6]` |

Session authorization lives in the MagicBlock Session Token PDA, not in `Pet`. Brain state (grudges, policy knobs) is client-side only.

Estimated size ~220 bytes → rent ≈ 0.0024 SOL.

### 3.2 Claim
1. Signer holds exactly 1 token of a mint whose Token Group Member points to a group in `admission_groups` (SGT group: `GT22s89nU4iWFkNXj1Bw6uYhJJWDRPpShHt4Bk8f99Te`, mint authority `GT2zuHVaZQYZSyQMgJPLzvkmyztfyXg2NJunqFp4p3A4`). Verify via Token-2022 group member extension, not metadata strings.
2. Sign-in-with-Solana message to prove wallet control (client side; program checks signer). **Owner signature required** (no session).
3. PDA `[b"pet", admission_mint]` must not exist **or** must have `alive == false`.
4. On (re)claim: if a slot is in grace for this mint → reuse it (heir stays home); else pop lowest free slot; if none, open a new block (protocol fee payer funds Block rent, D28).
5. Choose start region (Worker/Fighter/Survivor). Irreversible.
6. Newborn shield: `born_epoch + 3` epochs — cannot be attacked; hunger halved (D22).
7. Client immediately creates a session (D19) so the brain can act from epoch 0.

### 3.3 Epoch, emission and lazy settlement (D23)
- `epoch = floor((now - genesis_timestamp) / EPOCH_SECONDS)`
- Emission for epoch `e`: `E(e) = max(E0 × 0.75^floor(e / 90), E_floor)` `[strawman: E0 = 100_000/day, E_floor = 0.05 × E0]`
- `GlobalConfig` holds `reward_per_work_power: u64` (fixed-point, `REWARD_SCALE = 1e5`), `reward_epoch: u64`, `total_work_power: u64`, `recycled_pending: u64`. With `E0 = 1e11` base units/day and `total_work_power ≥ 10`, `acc` stays below 2^63 for ~1,800 epochs and `work_power × Δacc` is bounded by the interval's emission × 1e5.
- **Global settle** (runs first in any instruction that writes global): for each epoch from `reward_epoch` to current: `reward_per_work_power += (E(e) + recycled) × REWARD_SCALE / total_work_power`, where `recycled_pending` is spent entirely on the first settled epoch. Integer loop, no accounts (`rules/emission.ms: settleGlobal`).
- **Pet tick** (called on any pet instruction; permissionless `tick(pet)` also exists so neighbors can force-settle a sleeper):
  1. `pending = work_power × (reward_per_work_power − reward_snapshot) / REWARD_SCALE`; `harvest += pending + growthBonus(pending, multiplier)`; the bonus part is extra mint (D23). `reward_snapshot = reward_per_work_power`.
  2. For each missed epoch in `(last_tick_epoch, current]`: hunger step — newborn pets skip every other step; if `hearts − 1 < min_hearts` and `burrow ≥ food_cost(1)` → auto-eat tier 1 (D22), else `hearts -= 1`. `hearts == 0` → death (§3.7), stop.
  3. Reset daily fight counters if `fight_day != epoch`.
- **Write discipline:** a plain tick must not write `GlobalConfig` unless `reward_epoch` advanced or `total_work_power` changed (allocate, death). Global is the one hot account; keep it read-mostly.
- Dead-but-unticked pets remain in `total_work_power` until ticked. Inheritance (§3.7) is the incentive for neighbors to tick them. Document the small dilution.

### 3.4 Economy flows ($HBRN)
| Flow | Split |
|---|---|
| Epoch emission → pot | 100% to pot |
| Upgrade spend (level-up) | 60% → next epochs' pots (`recycled`) · 30% burn · 10% protocol |
| Food spend (`eat`) | 60% recycled · 30% burn · 10% protocol |
| Fight stake settlement | 95% winner · 5% protocol |
| In-game item trade *(post-hackathon)* | 98% seller · 2% protocol |
| Starvation death (pet's harvest + burrow) | 50% → living pets in block (equal split, credited to `harvest`) · 50% burn |
| Natural death w/ heir *(post-hackathon)* | 30% → heir · 20% block · 50% burn |
| Insurance revive | 50% of wallet burned |

Level cost `[strawman]`: `cost(L) = 100 × 1.12^L`. Food cost `[strawman]`: `food_cost(tier) = {8, 15, 21} × (1 + level/20)`. Tune against §6 invariants.

### 3.5 SKR layer (owner's money) — **100% to treasury**, **owner signature required**
| Item | Effect | Constraint |
|---|---|---|
| Food (3 tiers) | +1 / +2 / +3 hearts | No other effect. Bypasses the pet's budget. |
| Growth drug (3 tiers, 24h) | `growth_multiplier` +5% / +10% / +15% | Stacked total clamped at **1.20**. Multiplies *harvest* only. Paid by extra mint (D23). |
| Insurance | On reaching 0 hearts: revive with 3 hearts, burn 50% of wallet, +1 scar | **Once per pet.** |
| Skins | Cosmetic | 0% stat effect. |

SKR **never** buys: $HBRN from protocol, levels/points/power, a second revive, or a game action.

### 3.6 Fights (D25, D26)
- **Who:** any living pet not under newborn shield, unless Pacifist keystone. Initiated by the brain, signed by session key.
- **Target:** chosen, same block only.
- **Limits:** `attacks_per_epoch = 1 + might/10` `[strawman; rev 1 was flat 3]`; 3 incoming/epoch (first-come); max 1 attack per (attacker, target) per epoch; max 1 bite per target per epoch (D11).
- **Stake:** attacker posts `S` from burrow, `S ≤ target.harvest / k` so that `k × S ≤ harvest` (if `target.harvest == 0`, `S` = minimum bite stake `[strawman: 5]`).
- **Resolution:** `attack(target, S)` locks stake and requests VRF; `resolve_fight(randomness)` callback runs `fight(seed, snapshot_a, snapshot_d)` and settles. Fallback build: single-step using slot hashes.
- **Combat function** (all integer; implemented in `rules/fight.ms`, constants measured against §6.7 with `sim/curve.ms`, 4,000 runs per cell, rev 4):

  | Quantity | Rule |
  |---|---|
  | Fight HP | `100 + 4 × grit` (separate from hearts); Glass Cannon halves it |
  | Round | **simultaneous**: attacker and defender each strike once, then HP is checked |
  | Hit | `might × DAMAGE × roll/100`, `DAMAGE = 3`, `roll ∈ [20, 180]` uniform |
  | Dodge | `min(30, grit/2)` %, Thick Hide +10 |
  | Crit | `5 + might/4` %, ×2; Scavenger +15 vs a target with fewer hearts |
  | Max rounds | 8 |
  | Outcome | one comparison in every case: attacker wins iff `hpA/hpA0 > hpD/hpD0` (cross-multiplied). Covers KO, mutual KO (less overkill wins) and the round cap. Exact tie → defender. |
  | RNG | splitmix64, `seed = fightSeed(entropy, attacker_slot, defender_slot, epoch, fights_out_today)`; draw `i` uses `splitmix(seed + i)` |

  Measured curve (attacker p_win): equal stats 0.49–0.51 at might 5/8/20 · 2× might 0.96 · 0.5× might 0.009 · 2× grit 0.78 · 0.5× grit 0.33 · Fighter start vs Worker start 0.94. Equal fights at might 5 run 7.4 rounds on average, so the HP% comparison decides most of them; at might 20 they end in 3.1.

  Notables hook in via a `mods` bitmask (Thick Hide +dodge and −50% loot on the first 3 incoming fights, Scavenger +crit, Glass Cannon ×2 damage / half Fight HP, Pacifist −70% incoming loot and cannot attack, Cannibal on the death path).
- **Attacker wins:** `loot = min(k × S, harvest_d) × (1 − grit_d/100)`; `harvest_d -= loot`; `burrow_a += loot × 0.95`; protocol 5%. If `harvest_d` was 0 before the fight **and** `power_d ≥ 0.5 × power_a` **and** `bites_in_today_d == 0` → **bite:** `hearts_d -= 1`.
- **Attacker loses:** `S × 0.95 → burrow_d`; protocol 5%; `hearts_a -= 1`.
- **Record:** append `FightRecord` to the Block ring buffer (§3.8); emit an event with the same payload.
- **Odds UI:** client runs `fight` over 2,000 random seeds with both snapshots → p_win, expected loot, round distribution. The brain uses the same routine for EV.
- **Hunt** *(post-hackathon)*: district-scope target, loot ×1.3, no odds preview. **Bounty**, **Auto-policy UI** *(post-hackathon)*.

### 3.7 Death
- Trigger: `hearts == 0` after tick or bite.
- Starvation/fight death: harvest + burrow → 50% split equally among living block-mates (credited to their `harvest`, lootable — inheritance must be claimed too), 50% burned. `alive = false`. Slot enters 7-epoch grace for the same admission mint. `total_work_power -= work_power`.
- Insurance `Armed` intercepts death once.
- `close_dead_pet` after grace refunds rent to the original claimer (D28).
- Aging *(post-hackathon)*: after epoch 80 of life, all three stats −2%/epoch. Natural death path with heir bonus.

### 3.8 Blocks
- `Block { id, slots: [Option<Pubkey>; 10], living_count, grace: [(mint, until_epoch); 10], fights: [FightRecord; 32], fight_head: u8 }` ≈ 2.3 KB → rent ≈ 0.017 SOL.
- `FightRecord { epoch: u64, seed: u64, attacker_slot: u8, defender_slot: u8, a: Combatant, d: Combatant, stake: u64, loot: u64, outcome: u8, rounds: u8 }`, `Combatant { might: u16, grit: u16, hearts: u8, mods: u16 }` ≈ 48 bytes.
- `GlobalConfig.free_slots`: bounded vector of `(block_id, slot)`; lowest first.
- Claim assignment: grace match → else pop free → else new block.
- Winter merge *(post-hackathon)*: at each Winter, blocks with `living_count < 5` are merged pairwise.
- **District** = blocks `[10k, 10k+9]`: client-side aggregation for leaderboard and titles; Hunt scope later (D27).
- **The campfire scene is the home screen** (§5.6); neighbor cards open from the distant fires. Each neighbor card: stats, hearts, level, age (+ "Fading" badge past epoch 80), harvest, burrow size, **Monte-Carlo p_win if my pet attacks**, max loot, 24h fight log with replay buttons.

### 3.9 Skill tree (PoE-style)
- No node table in the program: `rules/tree.ms` computes kind, stat delta, mods and neighbours arithmetically from the node id (`u64` bitmap, `N ≤ 64`). Hackathon: **~24 nodes** — 3 start nodes, 5 small + 1 notable per region, 3 keystones at center/borders (36 is the post-hackathon target).
- `allocate(node_id)`: require `points_unspent > 0`, node not set, and at least one adjacent node set (or node is the chosen start). Set bit; recompute cached stats; settle pet first (D23), then update `total_work_power`.
- Node kinds:
  - **Small:** +1 Forage / +1 Might / +1 Grit / +1 max_hearts
  - **Notable** (examples): *Scavenger* +crit vs targets with fewer hearts; *Thick Hide* +dodge, first 3 incoming fights/day yield 50% loot; *Overtime* Forage ×1.5 on days with no fights in/out; *Nightwatch* one chosen neighbor gets +50% of your Grit
  - **Keystone** (rule-changing, always with a cost): *Glass Cannon* damage ×2, max_hearts = 2 · *Hibernate* no upkeep after ≥3 idle epochs, Forage 0 while idle, −2 hearts on wake · *Cannibal* killing blow → 50% of victim's wallet to you instead of block · *Pacifist* cannot attack, incoming loot −70%, Forage +30% · *Tithe* 10% Forage → block pot, +1 max_hearts per living neighbor · *Bloodline* heir gets 60% (post-hackathon), max level −20%
- Keystones sit far from starts and on region borders → cross-region pathing costs levels.
- **Respec:** none, except **one refund of up to 3 points per Winter** (post-hackathon).

### 3.10 The brain (D18)
- Runs on the owner's Seeker as a WorkManager periodic job `[strawman: every 2h, plus on charger connect]`, and on app open.
- Loop: fetch Block + Global + own Pet → run shared rules module → produce a plan → sign with session key → send. Plan order: tick, eat if `hearts ≤ min_hearts + 1` and affordable, harvest_claim, level_up while affordable and `cost(L) ≤ burrow × reserve_ratio`, allocate toward a chosen keystone route, then up to `attacks_per_epoch` attacks where `EV(target) > 0` and `p_win ≥ p_min`.
- Policy knobs are client-side (persona presets: Cautious / Greedy / Vengeful) and can be biased by owner soft signals (grudge, "stay home today"). They never bypass program rules.
- LLM layer (optional, timeboxed): receives the legal action set and the EV table, returns a choice plus a one-line reason for the digest. Any invalid output → heuristic choice.

---

## 4. Tokenomics summary (for deck + program constants)

- **Supply:** defined by schedule. `Σ E(e)` over all epochs. With `[strawman]` E0 = 100k/day, ×0.75 per 90 epochs, floor 5%: ≈ 36M before floor + floor tail, plus growth-multiplier extra mint (≤ 20% of shares that bought it).
- **No pre-mine, no team allocation, no investor allocation, no airdrop.** One entry path: claim a pet and play.
- **Protocol income:** 5% fight rake · 10% of upgrade and food spend · 2% in-game trades — in $HBRN. **100% of SKR spend** in SKR.
- **Sinks:** 30% of upgrade and food spend burned · 50% of every death burned · insurance burn.
- **Governance:** emission schedule, recycle ratio, `admission_groups`, `EPOCH_SECONDS`, `k`, combat constants live in `GlobalConfig`; program upgrade authority = 7-day timelock. Publish the address.
- **Hackathon mode (D17, D24):** $HBRN exists only as `u64` balances inside program accounts. Real launch deploys a mint with the identical schedule; hackathon balances do **not** carry over (say so in deck).

---

## 5. Technical architecture (D31)

### 5.0 Layers
| Layer | Built with | Output |
|---|---|---|
| Onchain program | MetaScript, `msc build --os=solana` | `hibernal.so` deployed to devnet |
| Shared rules + layouts | MetaScript `rules/` | compiled three ways: solana, android, js |
| Native core | MetaScript, `msc build --os=android --app=lib` | `libhibernal.so`: renderer, HUD, brain, RPC, signing |
| Android shell | Kotlin, ~300–500 lines | WallpaperService, Activity, Worker, widget, MWA calls → JNI |
| Sim | MetaScript, `msc run` (js or native) | invariant checks, tuning |
| Tooling | `tools/`: LiteSVM harness (from the meetup demo), devnet scripts | — |

### 5.1 Onchain — MetaScript program
**Design: Pinocchio-shaped.** Accounts are fixed-size structs read and written in place (zero-copy) over the account buffer. No Borsh, no Anchor discriminator, no IDL: a 1-byte `kind` tag + 1-byte `version` head each account, and the same `rules/layout.ms` file is compiled into the program and the client. Instruction data = 1-byte opcode + fixed args.

**Accounts** (as in rev 2): `GlobalConfig` `[b"config"]` · `Block` `[b"block", id]` · `Pet` `[b"pet", admission_mint]` · `FightPending` `[b"fight", attacker, counter]` (only on the VRF path) · MagicBlock Session Token PDA, read as a fixed layout and verified (owner program `KeyspM2ssCJbqUhQ4k7sveSiY4WjnYsrXkC8oDbwde5`, `authority == pet.owner`, `target_program == self`, not expired).

**Instructions** (unchanged list): `init_config`, `update_config`, `claim`, `tick`, `harvest_claim`, `eat`, `level_up`, `allocate`, `attack` (+ `resolve_fight` on the VRF path), `feed`, `buy_growth`, `buy_insurance`, `buy_skin`, `close_dead_pet`. Signer rule per D19.

**SGT verification** reads the mint account's Token-2022 TLV extensions directly (no CPI): `GroupMemberPointer` / `TokenGroupMember.group == admission_group`, `mint_authority == expected`.

**SKR purchases**: CPI `transfer_checked` to Token-2022 via `sol_invoke_signed`. If CPI lands late in the backend list, the dated-TODO shim is instruction introspection (client puts the SKR transfer in the same tx; program checks it through the Instructions sysvar).

**Randomness**: ship `SlotHashes` first. MagicBlock VRF (request CPI + callback) is added once CPI is in (item 6 below); the manipulation surface of the fallback is documented.

**Solana backend work list (in the `recompiler` repo), in the order the game needs it:**
1. **Heap**: arena at Solana's heap region `0x300000000` (32 KB, request more via ComputeBudget); stop discarding `.bss`/`.data` or stop needing them; refcount ops elided under `--gc=manual`, destructors no-op.
2. **Entrypoint**: parse `(program_id, accounts[], data)` from the input buffer into typed `AccountInfo` views (`std/solana/entrypoint.ms`); the C SDK's `sol_deserialize` is the reference and may be the first implementation behind a shim.
3. **Syscalls**: `sol_log_`, `sol_log_64_`, `sol_sha256`, `sol_create_program_address`, `sol_try_find_program_address`, `sol_get_clock_sysvar`; `SlotHashes` by reading the sysvar account.
4. **Codegen fixes**: division/modulo by non-constant, call-depth blowups from string formatting (forbid string building in solana mode; log numbers via `sol_log_64_`).
5. **Error ABI**: `u64` return codes from entrypoint, `panic` → log + abort, a `ProgramError` enum.
6. **CPI**: `sol_invoke_signed_c` with flattened `SolInstruction`/`SolAccountMeta` shim; helpers for System `create_account` and Token-2022 `transfer_checked`.
7. **Tests**: extend the demo's LiteSVM harness to multi-account, multi-instruction scenarios; a `msc test` target that builds solana + runs the harness.
8. **Realloc / account close** helpers (for `close_dead_pet` rent refund).

Everything below the ABI (clang → ld.lld → sBPF v3 ELF, DCE, comptime) already works and stays as is.

### 5.2 Client — one native core, thin Kotlin shell
- **`libhibernal.so`** exports a small C ABI: `hib_init(window, w, h, flags)`, `hib_resize`, `hib_frame(dt)`, `hib_touch(x, y, kind)`, `hib_set_visible`, `hib_destroy`, `hib_brain_tick()` (returns unsigned tx bytes when the owner must sign, sends session-signed txs itself), `hib_state_json()` for the widget.
- **Kotlin shell**: `HibernalWallpaperService` (forwards `Surface` + lifecycle + touch), `MainActivity` with a `SurfaceView` (same `hib_*` calls, `flags = IN_APP` turns the HUD on), `BrainWorker` (WorkManager, calls `hib_brain_tick`, hands owner-signature requests to MWA), `HibernalWidget` (Glance, reads `hib_state_json`), MWA `clientlib-ktx` for claim, session creation and SKR purchases. No Compose screens beyond what MWA needs.
- **Signing**: session key = ed25519 keypair from `std/crypto`, stored in an encrypted file under a Keystore-wrapped key; used natively. Owner signatures via MWA in the shell.
- **RPC**: JSON-RPC over `std/http` + `std/tls`; `getMultipleAccounts` for the block, `sendTransaction`, `getLatestBlockhash`; base58/base64 and legacy/v0 message serialization in `native/rpc/`. Subscriptions are optional; in-app polls every few seconds, the wallpaper reads a local state cache.
- **Demo mode** as before: devnet, `EPOCH_SECONDS = 600`, `max_hearts = 3` on recording day.

### 5.3 Reads / indexing
`getMultipleAccounts` on the 10 Pet accounts + Block + GlobalConfig covers the home scene; district leaderboard via `getProgramAccounts` with a `kind` filter. No indexer, no backend.

### 5.4 Single source of rules
`rules/` (`units.ms`, `stats.ms`, `layout.ms`, `fight.ms`, `emission.ms`, `tree.ms`, `brain.ms`, `winOdds.ms`) is compiled into the program, the native core and the sim from the same files. No ports, no golden vectors. A determinism test runs identical seeds through the js and native builds and asserts identical `FightRecord`s; the program build is checked in LiteSVM against the same seeds. Rules stay integer-only.

### 5.5 Narration
Template morning digest generated natively from the state cache and FightRecords, shown in the HUD. On-device LLM is roadmap (RENDERER-BRIEF §8 already spent those days).

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
- signer: owner **or** session token whose account is owned by the MagicBlock session program, `authority == pet.owner`, `target_program == program_id`, `expires_at > clock`
- PDAs re-derived from seeds + stored bump; never trust a client-supplied address
- **duplicate accounts rejected** (attacker == target, pet == neighbor, block passed twice)
- CPI targets hardcoded (Token-2022, System, session program); no program id from instruction data
- **checked arithmetic on every balance, heart and counter op**; the C backend's overflow behavior is verified in the day-1 spike and, if it wraps silently, a `checked_*` set is mandatory in the Solana subset
- closed accounts: data zeroed, lamports moved, `kind` set to 0
- newborn shield, 50% power rule, per-epoch caps, `stake ≤ harvest/k`, `S ≥ min_bite` enforced in the program, never only in the brain

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
  native/      renderer, hud, brain, rpc, signing, jni shim (.c) → libhibernal.so
  android/     Kotlin shell (gradle)
  sim/         msc run sim
  tools/       LiteSVM harness, devnet scripts, vector dumps
  docs/        BRIEF.md, RENDERER-BRIEF.md, ROADMAP.md
```
Compiler and library work lands in the `recompiler` and `void` repos; this repo pins their commits.


---

## 6. Tuning invariants (what the numbers must satisfy)
1. A well-played pet with **zero SKR** reaches "prime" (~L30) in ~30–40 epochs, and **never starves while it works and claims daily.**
2. A maxed pet's food bill ≈ **60–70%** of its expected daily harvest → 3 idle days is dangerous at any power.
3. *(rev 1: top-decile power ≥ 5× median, net income ≤ 3× median.)* **Reopened — see §10 Q7.** Until decided, sim reports both ratios without asserting.
4. A pet born at epoch 60 can reach top-quartile of the *current* generation by epoch 120 (requires aging, post-hackathon).
5. Worker beats Survivor on expected income iff daily successful-raid probability `q < 0.67` (given Worker harvest ≈ 3× base, Survivor ≈ 1×). `work_power` weights must actually produce ≈ 3×.
6. Fighter EV vs a claimed (harvest = 0) target must be **negative** (bite stake risk + heart risk, no loot).
7. **Combat curve**: equal stats → attacker p_win 0.45–0.55; 2× might → ≥ 0.85; 0.5× might → ≤ 0.20. **Met by rev 4 of §3.6** (0.50 / 0.96 / 0.009). Open: whether 0.009 is too crushing for the underdog; `ROLL_LO/HI` widen it (10–190 gives 0.018 at the cost of 2× dropping to 0.94).
8. Fight EV between peers with non-empty harvest must be **positive for the stronger side** at `k` chosen, so the brain actually attacks.

Write the offchain simulator early (`sim/`, TypeScript on the shared module) — seed 200 pets across 20 blocks with mixed builds and brain personas, run 120 epochs, check invariants. Use it to pick `E0`, `cost(L)`, `food_cost`, `k`, combat constants and stat weights before hardcoding.

---

## 7. Scope

### 7.1 Hackathon MVP (must ship)
- Claim gated by SGT (admission_groups config with SGT only populated)
- Session creation via MagicBlock Session Keys (tx built natively, owner-signed via MWA); all pet actions signed natively by the session key
- Brain v1 heuristic on WorkManager: eat, claim, level, allocate, attack by EV
- Hearts, hunger, `eat` with $HBRN, auto-eat floor, newborn slow hunger, starvation death, 50/50 inheritance to block
- 3 stats, level-up with exponential cost and 60/30/10 split
- **~24-node** PoE-style tree with adjacency rule and 3 keystones (cut from 36, RENDERER-BRIEF §8)
- Accumulator emission, lazy tick, harvest/burrow as u64
- Fights: multi-round `fight()`, slot-hash seed (VRF if CPI lands), FightRecord ring buffer, in-scene replay, Monte-Carlo odds, bite rule, newborn shield, no-bite-under-50%, 1 bite/target/epoch
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
- Aging & natural death, heirs & lineage, Bloodline keystone
- Winter: emission step, block merge, 3-point refund, season titles
- District leaderboard, Hunt, Bounty, Move, item trading
- Owner-facing auto-policy editor; LLM brain if not done in timebox
- Protocol fee payer (gasless for users)
- Real $HBRN launch (transferable mint, DEX liquidity from player activity only)
- Ephemeral Rollup for real-time Hunt if it ever needs sub-second play
- Recompiler: Solana backend polish (realloc helpers, `noalloc` check, static CU tooling), `std/solana` published as a package

### 7.3 Explicitly not doing
- Glossy realtime 3D à la NOMI; the 3D pipeline exists only to produce the pixel look (D14). No free camera, no cosmetics that break the pixel grid.
- GPS / sensor-driven behavior
- Prediction markets, yield, perps, anything trading-shaped
- Any pre-mine, allocation, or airdrop
- Server-held keys; off-chain game state
- Owner-issued game actions (the owner never presses "attack")

---

## 8. Build plan — 14 days + 2 weeks buffer to Oct 8 (D31)

Two tracks in parallel from day 1: **chain** (recompiler Solana backend + program + rules + sim) and **device** (void + native core + Kotlin shell). Both start with toolchain spikes, because the two unproven toolchains are the real risk and they must fail separately, never together.

| Day | Chain track | Device track |
|---|---|---|
| 1 | **Spike:** arena at `0x300000000`, entrypoint parsing two accounts, write a counter in LiteSVM. | **Spike:** `msc build --os=android --app=lib` through the NDK, JNI calls `fight()` from Kotlin **on the Seeker**; EGL triangle into a 360×800 FBO blitted nearest inside a WallpaperService via void's bridge. |
| 2–3 | Backend items 3–5. Program: `GlobalConfig`, `Pet`, `tick` (accumulator), `eat`, `harvest_claim`, `level_up`. `rules/` first pass, sim skeleton, combat-curve sweep. | Depth + passes + pipeline bridge (void items 1–2). Math module. Camera snap. |
| 4 | **Tripwire:** `claim`-less `tick` + `eat` + `level_up` running in LiteSVM from MetaScript. Missed → the blocking item gets a dated shim, nothing else changes. | Outline + palette passes. Blender generator script starts. |
| 5–6 | `claim` with SGT TLV parse, `Block` + free-list + grace, session-token verification, `close_dead_pet`. LiteSVM scenario tests. | glTF loader, first pet on screen, lights, idle animation, touch. Native RPC: `getMultipleAccounts`, blockhash, tx serialization, ed25519 signing, `sendTransaction` against devnet. |
| 7–8 | `attack` (slot-hash seed), `fight()` in program, `FightRecord` ring buffer, death + inheritance, `allocate` + 24-node tree. CPI item 6 → SKR shop instructions. **Devnet deploy.** | Brain loop (`hib_brain_tick`) end to end with session key; Kotlin shell: Worker, MWA claim + session creation. Lifecycle hardening (preview, context loss, visibility). |
| 9–10 | Determinism test js vs native vs LiteSVM. Sim run: invariants §6. Tune `LOOT_PER_STAKE_BPS`, `DAMAGE`, `EMISSION_START`, `levelCost`. | HUD in Neon-on-void: campfire home with neighbor fires + Monte-Carlo odds, My Pet, Tree, Replay, Shop, Digest. Widget. |
| 11–12 | VRF request/callback if CPI is solid; else document fallback. `update_config`, timelock authority. | Variants, day/night, Winter palette, harvest objects. Battery measurement. |
| 13 | Demo video (10-min epochs; opens on unlock with the pet on the lock screen). Deck. | |
| 14 | README, architecture doc, commit hygiene. dApp Store submission. | |
| **Buffer wk 1** | Whatever slipped, in the same order. Compiler fixes that were shimmed get done properly and the shims removed. | |
| **Buffer wk 2** | Polish, second demo cut, dApp Store review feedback. | |

Commit daily in this repo and in the compiler/void repos with meaningful messages; this repo pins their commits.


---

## 9. Submission checklist
- [ ] Android APK, installs on Seeker, signs via Seed Vault/MWA for claim and SKR, via session key for pet actions
- [ ] Live wallpaper survives lock/unlock/rotate/launcher-switch/preview; pet visible on the lock screen (RENDERER-BRIEF §9)
- [ ] Repo public, clean history, README with architecture + how to run devnet demo, pinned recompiler/void commits and a "what we built in the compiler for this" section
- [ ] Demo video ≤ 3 min: opens on unlocking the phone with the pet already there, then a full life cycle in demo mode including one fight replay
- [ ] Deck: problem (retention) · one-per-Seeker scarcity · autonomous pet with its own money · permadeath · block/hawk-dove · replayable RPG fights · PoE tree · fair-launch tokenomics incl. **why no token yet** · SKR role · session keys + VRF · Transaction V1 "one signature morning" · roadmap (§7.2) · team
- [ ] SKR track write-up: SKR as the currency owners spend to keep characters alive; growth-mult cap design; Seed Vault for money, session key for play
- [ ] Determinism green: js, native and LiteSVM builds of `rules/` agree on 10k seeds
- [ ] Differential fuzz + invariants green on the pinned compiler; UBSan clean
- [ ] dApp Store listing submitted with time for review
- [ ] Verified CLOCK IN eligibility, submission rules and sponsor list (§1.1)

---

## 10. Open questions (decide day 1 unless noted)
1. Project name. "Hibernal" is the working title; token is **$HBRN** (settled). Alternatives floated: Warren, Burrow, Holt.
2. ~~Client stack~~ — **settled: all-in MetaScript with a thin Kotlin shell (D31).**
3. `EMISSION_START`, `levelCost`, `foodCost`, `LOOT_PER_STAKE_BPS`, `DAMAGE` and other combat constants — run `sim/` first.
4. Devnet SGT: no real SGT on devnet → add a `DevAdmission` group to `admission_groups` on devnet only, minted by a dev keypair. Never on mainnet.
5. Whether inheritance credits to `harvest` (lootable, must be claimed) or directly to burrow. Default: harvest.
6. Minimum bite stake value.
7. **What kind of gap between strong and weak pets do we want** — fight dominance, income, or survival? Each has a different knob (combat curve, `k` and attacks-per-epoch, hunger scaling). Decides whether invariant 3 is relaxed and whether `attacks_per_epoch` scales with might.
8. MagicBlock VRF fee and callback latency on devnet — if unacceptable, ship the slot-hash fallback and say so.
9. Session validity max (their program) — if 7 days, the app needs a "renew session" nudge in the digest and on the widget.
10. **Team size.** The chain track and the device track (§8) each need a full-time person for the first week. Solo means serializing them: chain days 1–4 first (it gates everything), then device; the buffer weeks absorb the rest. Cut order if needed: VRF → widget → HUD polish; never the wallpaper.
12. Does `std/http` + `std/tls` link and run under the NDK build? Verify in the day-1 device spike; fallback is routing RPC through the Kotlin shell (OkHttp) for the hackathon.
13. Neon-on-void on Android: text and input have only been exercised headless. If it is not solid by day 9, the HUD is drawn directly with void 2D calls (imperative), Neon later.
11. Does the Seeker lock screen render the live wallpaper (RENDERER-BRIEF §10 Q1)? Load-bearing for the demo opener; verify on device day 1.

---

## 11. Glossary
- **SGT** — Seeker Genesis Token, one per Seeker device, Token-2022, transferable only within Seed Vault Wallet; mint address stable.
- **$HBRN** — the project token; hackathon: non-transferable `u64` points.
- **Brain** — the on-device agent that decides the pet's actions and signs with the session key.
- **Session key** — a device-held keypair the owner authorizes once; signs pet actions without popups.
- **Block** — fixed group of 10 pet slots; the social unit.
- **District** — 10 blocks; leaderboard and Hunt scope.
- **Harvest** — unclaimed earnings; lootable.
- **Burrow** — claimed $HBRN inside the pet account; safe; pays food and levels.
- **Eat** — the pet spends $HBRN on food to restore hearts. Auto-eat is the tick-time floor.
- **Campfire** — the home scene's fire; its size is the hearts meter.
- **Fight HP** — per-duel stamina from grit; separate from hearts.
- **FightRecord** — seed + stat snapshots + result stored in the Block; replayed client-side.
- **Bite** — heart damage inflicted when a winning attacker finds an empty harvest.
- **Winter** — the ×0.75 emission step every 90 epochs; also the seasonal ritual (merge, refund, titles).
- **Pot** — the epoch's distributable tokens (emission + recycled spend), realized through the accumulator.
- **reward_per_work_power** — cumulative reward per unit of work power since genesis.
- **growth_multiplier** — SKR-purchased multiplier on harvest, clamped at 1.20, paid by extra mint.
