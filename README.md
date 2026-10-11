# Hibernal

A Tamagotchi-like pet with a life of its own, one per Seeker. It works, eats, fights its neighbours and spends its own money, decided by a trained neural network that runs on chain. Its owner cares for it but cannot control it. Death is permanent: the owner sees it mourned, and can hatch the next generation, which keeps the same name and inherits what the dead pet left behind.

Built for CLOCK IN, the Solana Mobile hackathon. The game is one language, [MetaScript](https://metascriptlang.org), end to end: the Solana program, the rules it shares with the phone, the phone's renderer and HUD, the simulator and the training environment, about 34,000 lines. The program runs on [Project Geass](https://geass.metascriptlang.org), MetaScript's Solana toolkit and our Colosseum submission. Around that core: Kotlin for the Android shell and wallet, JavaScript for chain operations, Python for training.

**[Demo video](https://www.youtube.com/watch?v=mqqPngghPBg) · [APK](TODO-APK-LINK) · [Pitch deck](https://metascript-talk.pages.dev/clockIn) · [Verify it on devnet](#verify-it-in-two-minutes)**

[![The pet on the lock screen, as the live wallpaper, and in the game](docs/media/presence.jpg)](https://www.youtube.com/watch?v=mqqPngghPBg)

*Real screen recordings from a Seeker: the lock screen, the live wallpaper, and the game.*

## Care, not control

Each pet is born with a persona fixed by its mint: Cautious, Greedy or Vengeful. Each one weighs risk differently; a Cautious pet attacks only at a 70% win chance or better, a Vengeful one at 45% (`rules/brain.ms` `Persona.of`). Its days are its own: work for a harvest, eat, mint and trade gear with other pets, grow a 64-node skill ring, and rob a neighbour or defend against one.

The world remembers. A pet robbed twice by the same neighbour within three days grows angrier: +10% might and grit against that robber per stack, up to three (`rules/layout.ms` `enragedAgainst`). A hidden talent is drawn by VRF at level 10, so nobody can read it from the mint. A pet that dies of old age leaves its heir 70% of its money and its two best items. A pet that starves or is beaten loses everything: half goes to the treasury, half to a block-mate the round's VRF picks. Each generation also nudges the odds of a rarer talent (`program/day.ms` `heirOf`, `rules/talent.ms`).

The owner's part is care:
- Feeding, growth and insurance, bought with SKR.
- Gifts to claim. A pet with a strong bond sends its owner up to 5% of its day's income in `$HBRN`; a neglected one refuses the owner's food (`rules/owner.ms`).
- Watching: the neighbours' faces, the odds of each fight, the activity log.
- Mourning. The death screen names the cause: old age, starved, or beaten by a named neighbour (`native/hud/mourning.ms`). The owner hatches the heir when ready; the dead pet's estate waits for it.

## Part of the phone

<table><tr>
<td align="center"><a href="https://www.youtube.com/watch?v=mqqPngghPBg"><img src="docs/media/lockScreen.webp" width="240" alt="The pet walking on the lock screen"></a><br><sub>Lock screen</sub></td>
<td align="center"><a href="https://www.youtube.com/watch?v=mqqPngghPBg"><img src="docs/media/wallpaper.webp" width="240" alt="The pet as the live wallpaper behind the home screen"></a><br><sub>Live wallpaper</sub></td>
<td align="center"><a href="https://www.youtube.com/watch?v=mqqPngghPBg"><img src="docs/media/inGame.webp" width="240" alt="The pet in the game with its HUD"></a><br><sub>In the game</sub></td>
</tr></table>

| | What it does | Where |
|---|---|---|
| Lock screen and wallpaper | The same native scene runs in the app (60 fps), as the live wallpaper (30 fps) and on the lock screen, without the HUD. It stops drawing when it is not visible | `VoidWallpaperService.kt`, `VoidRenderer.kt`, `native/androidEntry.ms` |
| Native renderer | Written in MetaScript and compiled to one `.so`, with no web view and no game engine. Low-poly 3D lit in colour ramps and snapped to a shared 5-pixel grid, so it reads as real pixel art | `native/`, `scripts/buildAndroid.sh`, `docs/RENDERER-BRIEF.md` |
| Tilt | Tilting the phone looks into the pet's world. It uses the game rotation vector, so a compass recalibration never swings the camera | `TiltSensor.kt` |
| Notifications without a server | The phone checks on the pet itself every 30 minutes: robbed by a neighbour, levelled up, insurance saved it, a gift is ready, an order arrived, it died | `PetWatch.kt` |
| Seeker Genesis Token | One pet per Seeker. The program checks the token's group membership on chain. On devnet, an admission service turns a mainnet SGT into a devnet ticket | `program/admission.ms`, `tools/chain/admissionService.mjs`, `TokenAdmission.kt` |
| Mobile Wallet Adapter | Summon, buy and claim. Each transaction is built on the phone, simulated, sized to the compute it used, and pinned to this program. Its meaning is checked again after the wallet returns it. Orange buttons are the only ones that ask for a signature | `OwnerPreflight.kt`, `OwnerTransaction.kt`, `WalletBridge.kt`, `docs/UI-KIT.md` |
| Same odds as the chain | The HUD computes each fight's win chance with the rules code the program runs | `native/hud/neighbours.ms` |
| Small footprint | Only the `INTERNET` and `POST_NOTIFICATIONS` permissions; no foreground service and no boot receiver | `AndroidManifest.xml` |

The Kotlin shell is in `android/app/src/main/java/app/hibernal/`, with its JVM tests beside it in `android/app/src/test/`. The files in `art/hud/*Mockup.png` are design references, not app screenshots.

## SKR buys care

SKR is how an owner keeps a mortal pet alive. It never buys power.

- **Insurance buys a second life.** When an insured pet would die, it gets back up with 30% of its hearts, and half its money goes to the treasury (`rules/owner.ms` `revived`). One policy is armed at a time.
- **Food** feeds the pet before its own pantry. An owner can save a pet that cannot afford to eat.
- **Growth** speeds up levelling by at most ×1.2. Whales get +20% progress, never +20% strength (`docs/BRIEF.md` D6).
- **Skins** are in the program; the app shows them as coming soon.

The pet answers. An SKR purchase raises its bond by 15, more than twice a feeding (+6). A strong bond makes the pet gift its owner `$HBRN` from its own income. So SKR in becomes care, care becomes a bond, and the pet decides to give back. The owner never takes the pet's money.

**Every life pays for itself.** Claiming a pet and hatching each new generation cost 0.02 SOL, paid into the program's SOL fund (`program/admission.ms` `claim`, `program/shop.ms` `payRebirth`; D43). A seat and its cranks cost the game about 0.003 SOL plus 0.00016 SOL a day per block of ten, so a life of 90 game days is paid for several times over, and a pet nobody hatches again costs nothing more. The authority withdraws the fund (`withdrawFund`); SKR purchases are revenue on top.

The purchase crosses both layers. It is paid in SKR on L1 through MWA and counted in the pet's ledger account there. The ER then loads it into the pet's two owner slots, and the pet uses it by rule at dawn (`program/shop.ms` `buy`, `load`; D41, D42). All SKR goes to a token account owned by the program's revenue PDA, and there is no team token allocation: the studio earns only while the game is played (D5). On devnet SKR is a stand-in mint, and admission gifts each new owner 200 test SKR.

## The game, on chain

The brain is a small int8 neural network trained off chain. Its 4,763 bytes sit in one program account, sealed once and refused if it was built for other rules (`program/admin.ms`). The program runs it inside its `turn` instruction in a MagicBlock Ephemeral Rollup, where each `turn` acts for two pets (`program/day.ms`, `program/brain.ms`, `rules/policy.ms`).

The day runs itself:

1. **A Hydra crank starts each round** (`RoundStart`). Every step creates the crank for the next step, signed and paid by the program's own `vrf-payer` PDA. A step that must wait reschedules itself instead of failing.
2. **MagicBlock VRF returns the round's seed** (`Seeded`). Every random outcome comes from it: turn order, fights, talents, the lucky heir of a beaten pet.
3. **`Turn` steps run the brain for the pets.** About 190k CU per two acting pets on devnet; the busiest act measured is 979,194 CU of the 1.4M limit.

Anyone can fire the cranks. On devnet the team runs `tools/chain/gameCranker.mjs`, which cleared backlogs at 670–723 triggers/s with no failed sends in the localnet measurements (`docs/OPERATIONS.md`).

**One copy of the rules.** `rules/` is integer-only MetaScript that compiles to native code for the simulator and training, to JavaScript for determinism checks, and to SBF for the program. The phone imports the same rules. The trained network is checked to be exactly the one that ships: PyTorch and the int8 export differ in 0 of 63,833 logits (`train/checkExact.py`), and the chain's outputs match the host checksum. `tools/chain/dayLiteSvm.mjs` replays a game day on the SBF binary with 0 bytes differing from the simulator.

**A brain chosen for drama.** Training is behaviour cloning from a scripted teacher, then PPO with a different reward per persona: a Cautious pet pays twice for a lost stake and three times for death (`sim/env/batch.ms` `RewardWeights.of`). The deployed policy, `p31s5`, was chosen on 2026-10-06 because its fights read as play.
- Across every policy we trained, 0 illegal actions.
- 51.9 fights per pet.
- A pet's persona can be told from its action log 72% of the time.
- It ends 31.5% richer than the teacher in mixed worlds.

`docs/ON-CHAIN-AI.md` records every model and measurement.

**The program is MetaScript, and it still speaks Anchor.** It is built on [Project Geass](https://geass.metascriptlang.org), MetaScript's Solana toolkit (`std/solana`). It uses 8-byte discriminators, Borsh arguments and errors from 6000, and it emits an Anchor IDL, so explorers and other clients read it as usual. On the same escrow program, the build sizes measured were: Anchor 230,120 bytes, native Rust 120,976, MetaScript std/solana 72,616 (`docs/SOLANA.md`).

**Money paths are guarded and tested.**
- `$HBRN` is minted only by the program, with a daily claim cap and a check against the 21M cap on the mint's real supply.
- Claims check the owner, mint, token program, destination and ledger PDA, and host tests refuse forged and swapped accounts (`program/payout.ms`, `program/test/payout.ms`).
- Emission halves every 90 days ("Winter") and lands on exactly 21M on day 2,258. Nothing is burned; the treasury pays 1% of its balance back to the pets each day (`rules/emission.ms`, D4, D40).

## Verify it in two minutes

The devnet world was reset on 2026-10-11 with 24-hour game days, the mainnet length. It holds 509 simulated owners, each with its own key, in 51 blocks, plus the real owners who join.

| | |
|---|---|
| Program | [`Cq4iAp7YLg6U31rk5ZHJUhXzkcK1Qa6YScft7n3DGhsX`](https://explorer.solana.com/address/Cq4iAp7YLg6U31rk5ZHJUhXzkcK1Qa6YScft7n3DGhsX?cluster=devnet), ELF SHA-256 `c709080c300d694dacff814962c0342f7e89254da3d97faaafef5248fa172d0b` |
| Brain (policy account) | [`GqPgHYWY1VBaVkgP8uwyAQLtiV8WHyhzBfNQ12UgHiUv`](https://explorer.solana.com/address/GqPgHYWY1VBaVkgP8uwyAQLtiV8WHyhzBfNQ12UgHiUv?cluster=devnet). The 4,763 bytes from byte 24 equal `train/checkpoints/p31s5.policy` (SHA-256 `e86d99a3151dcbf9adbd0438ce079012d8a936f424c837fa493c3bb0c2973f5a`) |
| `$HBRN` mint | [`7KcCG84jZHfxSToBPfs6p7kQUtK9UtqHKDQUpJCb4dRw`](https://explorer.solana.com/address/7KcCG84jZHfxSToBPfs6p7kQUtK9UtqHKDQUpJCb4dRw?cluster=devnet) |
| One round of block 50, in the ER | [`RoundStart`](https://explorer.solana.com/tx/3qVKWAhvZ4f5uzMLgTiFDk4Q4ADEodgYaff72C6Fq4JZcyv3Z9RkdJcVHB7h3cZLAN9xw8LnVP9vqZKeq3ebMPY4?cluster=custom&customUrl=https%3A%2F%2Fdevnet-as.magicblock.app) → [VRF callback](https://explorer.solana.com/tx/YEjgJ4oMixxJZ56Hj4fCQWWCMxiV4bnHAr2RQrX52RDFSLUbMTmDqJhbd7gisSb7T7iUoWcu4fbHVzax83Ku3P8?cluster=custom&customUrl=https%3A%2F%2Fdevnet-as.magicblock.app) → [dawn `Turn`](https://explorer.solana.com/tx/3EDmXpvCwurUfPN79DLZt87KVMRfUcmvroizETGuzWasoVvZvSu8RpZzERmscqUXepgE1yok2u1YsJumBCmw9KjQ?cluster=custom&customUrl=https%3A%2F%2Fdevnet-as.magicblock.app) → [`Turn` with the brain, 190k CU](https://explorer.solana.com/tx/2AAXfzftx3jxUM26FY4k3etVGdMsPrJwwQpCD3ceQEWH7oA2ugmUkRkAU3y4XLFhex5toK69EQ21HF41xfEQJTYZ?cluster=custom&customUrl=https%3A%2F%2Fdevnet-as.magicblock.app) |
| L1 RPC / ER RPC | `https://rpc.magicblock.app/devnet` / `https://devnet-as.magicblock.app` |

The ER may drop old transactions. A block's recent ones are listed by `getSignaturesForAddress` on the ER RPC for block 50, `GUdcC2Z1ywsjs9rSX14vpHBZnPPr9Dw8Cg4VuW2DGGZc`.

## Built to run

- **50,000 owners on a localnet that mirrors devnet.** MagicBlock's ER built from source, plus their VRF oracle and Hydra. 50,000 owner-signed claims in 378 s with 0 failures; the first round of all 5,000 blocks in 110 s (32,780 triggers, 5,000 VRF answers). The world was carried to game day 8 with 43,788 pets alive (`docs/OPERATIONS.md`, 2026-10-03 to 10-06, earlier builds of the program).
- **A world that heals itself.** `tools/chain/ops.mjs` places pets, sweeps spent cranks, resumes stalled blocks and loads purchases. A watchdog checks the services and posts outages to Discord. Measured recoveries: the cranker down for 6 minutes caught up in 6 s; the VRF payer run dry recovered in about 25 s.
- **Upstream bugs traced to their cause.** For example, the ER's RPC slot freezing ([magicblock-validator#1783](https://github.com/magicblock-labs/magicblock-validator/issues/1783)), reproduced in isolation and worked around in our cranker. `ER-BUGS.md` lists the rest. MetaScript toolchain bugs we hit went upstream to the compiler, each with its smallest repro, and the program now builds on the released toolchain with none of them worked around.
- **Tests at every layer:**
  - `rules/` and `sim/` suites;
  - 55 program tests on the host with VRF and Hydra stubs;
  - LiteSVM harnesses for the SBF binary;
  - `idlCheck.mjs`, which checks every client instruction's account flags against the IDL;
  - JVM tests for the phone's chain client.

## Trust model and known limits

- One deploy key is the upgrade authority and the config authority. On devnet the admission service holds it, because `CommitPet`, which moves an owner's gift to L1, accepts the owner or that authority. Mainnet needs a separate service key, a multisig, and rate limits on `/admit`.
- `$HBRN` claims on L1 trust what the ER committed; the daily and supply caps bound the damage.
- Known in the deployed program and not yet fixed:
  - `turn` takes no signer. A caller who sends the due step with some pets' accounts missing makes those pets skip it. `loadedPets` in `program/day.ms` should refuse instead.
  - `initialize` does not check the upgrade authority. That matters only on a fresh deploy.
- Each app open is meant to count as an `engage`, which raises the bond by 3 and is signed by a session key with no wallet prompt. It is built in the program and measured on devnet (`docs/OPERATIONS.md`), but the app does not send it yet.
- Wild pets that fill empty seats with the brain run in the simulator only. On devnet, simulated owners fill the world instead.

## Roadmap

1. Invite Seeker owners into a small devnet cohort and measure who comes back.
2. Security and recovery before real money: separate keys, a multisig, the fixes above, and recovery drills.
3. Mainnet with the real SGT and SKR, then the Solana dApp Store.

`docs/LAUNCH.md` and `docs/ROADMAP.md` hold the gates.

## Build

Install MetaScript: `curl -fsSL https://metascriptlang.org/install.sh | sh`. The deployed ELF was built from this tree's `program/` on 2026-10-10 with that day's `msc` v0.3.2 and std/solana. This tree builds and passes its host tests with the std/solana released on 2026-10-11, which also refuses one account passed twice where either is writable, as Anchor does.

```bash
msc test rules/index.ms                                   # game rules
msc test sim/env/ffi.ms                                   # rules, world, teacher, observation, actor
msc test program/test/day.ms                              # the program's day on the host (also admission, owner, payout, resort, shop)
msc build program/main.ms --os=solana --output=out/hibernal.so
msc run program/idl.cms                                   # Anchor IDL on the last line
scripts/buildAndroid.sh release                           # APK; needs Android NDK 28, see the script header
cd train && uv run python bc.py && uv run python ppo.py && uv run python evaluate.py --policy ppo
```

To deploy and run a world, use `tools/chain/deploy.mjs`, then `STAGE=bootstrap node tools/chain/ops.mjs <program> train/checkpoints/p31s5.policy`; `docs/OPERATIONS.md` has the details.

## Repository

```
rules/     game rules, integer only, compiled native, JS and SBF
program/   the on-chain program, brain included
sim/       simulator and the batched training environment
train/     PyTorch training: behaviour cloning, PPO, evaluation
native/    renderer and HUD, MetaScript
android/   Kotlin shell: MWA, wallpaper, notifications, tilt
tools/     probes, chain clients and the devnet operations lanes
docs/      design and measurements
```

- `docs/BRIEF.md`: the game and every settled decision.
- `docs/GAME-DESIGN.md`: the same decisions with their measurements.
- `docs/ON-CHAIN-AI.md`: the brain.
- `docs/SOLANA.md`: the chain surface and the ER measurements.
- `docs/OPERATIONS.md`: running a world.
- `docs/RENDERER-BRIEF.md` and `docs/UI-KIT.md`: the renderer and the HUD.
