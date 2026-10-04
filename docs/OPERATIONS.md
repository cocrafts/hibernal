# OPERATIONS — running the game on L1 + MagicBlock

How the online game is brought up and kept running with the developer machine off. `LAUNCH.md` owns the release order and the gates. `SOLANA.md` §7 items 19–21 own the measurements behind the day flow. This file owns the run order, the services, what each one fixes when something breaks, and what it costs.

## 1. What runs where

| Piece | Where | Started by |
|---|---|---|
| Hibernal program (one id; the ER executes the same bytecode on delegated accounts) | L1 | `tools/chain/deploy.mjs` |
| Config, Policy, World, VrfPayer; Pet + Paid per pet; Block per 10 pets | L1, and World/VrfPayer/Pet/Block delegated to the ER | `tools/chain/ops.mjs STAGE=bootstrap`, `tools/chain/players.mjs`, `ops.mjs STAGE=blocks` |
| The day: one Hydra one-shot crank per block at a time, each step scheduling the next | ER | `StartBlock` once per block (by `ops.mjs`), then the chain itself |
| VRF oracle | MagicBlock on devnet/mainnet; `localnet.sh` on localnet | — |
| `tools/chain/gameCranker.mjs` (MagicBlock's `hydra-cranker` as a backup) | ops host | supervised process (§3) |
| `ops.mjs STAGE=run` | ops host | supervised process (§3) |

## 2. Bring-up

Localnet (mirror of devnet-as, `SOLANA.md` §7 item 20):

```bash
tools/chain/localnet.sh up                     # L1 + ER v0.16.0 + VRF oracle + hydra-cranker, ~1.5–2.5 min
source out/localnet/env.sh
node tools/chain/deploy.mjs out/localnet/hibernal.so <program keypair> <new buffer keypair>
SECONDS_PER_DAY=1200 STAGGER_SECONDS=30 STAGE=bootstrap node tools/chain/ops.mjs <program> train/checkpoints/p29s5.policy
PROGRAM=<program> FIRST=0 COUNT=<n> STAGE=keys|admit|fund|claim node tools/chain/players.mjs
PROGRAM=<program> STAGE=export PETS_FILE=out/localnet/players.json node tools/chain/players.mjs
PETS_FILE=out/localnet/players.json STAGE=run node tools/chain/ops.mjs <program> train/checkpoints/p29s5.policy
```

Devnet: the same commands with `source out/devnet/env.sh`:
- `NET_DIR=out/devnet`;
- MagicBlock's queue `5hBR571…` and validator `MAS1Dt9…`;
- the DevAdmission group, and `GROUP_KEYPAIR=out/devGroupMint.json` for `players.mjs`;
- a cranker started against `https://devnet-as.magicblock.app` with `--base-rpc-url https://rpc.magicblock.app/devnet`.

The localnet keeps every slot. With 50,000 pets the L1 ledger reached 31 GB and the ER storage 20 GB in about 20 hours. On 2026-10-03 at 20:04Z the disk filled: L1 died, and the ER, the devnet ops loop and the owner lane failed their writes. `localnet.sh` does not cap either store yet.

`Config.secondsPerDay` sets the length of a game day: 86,400 on mainnet, compressed on localnet and devnet. It is fixed at `Initialize`, which refuses a day shorter than four seconds, a zero slot time and a zero turn gap.

## 3. Services and what they repair

| Service | Does | If it stops |
|---|---|---|
| `gameCranker.mjs` (§11); `hydra-cranker` under `tools/chain/cranker.sh` as a backup (restart every 5 min and on exit, `WORKAROUND.md`) | fires each due crank (one trigger per step) | pets stop; restarted, it fires every overdue crank at once and the block catches up (measured: 6 min down, a round 2.4 min late, caught up in 6 s) |
| `ops.mjs STAGE=run`, every `TICK_SECONDS` | places claimed pets into Idle blocks (creating blocks as needed, and delegating every created block that is not delegated yet, including one an interrupted run left behind); `StartBlock` for new blocks; `Sweep` of spent cranks (returns their rent to the vrf-payer); watchdog; re-sort when every block is Idle; tops up the vrf-payer from its delegated funder; writes `opsStatus.json` | new pets wait unplaced, spent cranks keep their rent and fill the cranker's cache, a broken chain stays broken. Measured on devnet (500 pets): down 5 h 50 min after a full disk, the vrf-payer ran dry with 463 spent cranks unswept and every chain stalled; restarted, it swept and topped up in about 25 s and the overdue blocks went from 33 to 1 within a minute |
| VRF oracle | answers each round's request | the block's first turn re-schedules itself every 1.5 s and requests again after 30 s; the round starts when an answer arrives (measured: oracle down 2.5 min across a round start, the round ran 2 s after it came back, the day-end turn 7 s after) |

The watchdog resumes a block whose live crank is gone and whose due slot is more than `WATCHDOG_SLOTS` past. `StartBlock` refuses a chain that is still alive (`RESUME_GRACE_SLOTS` = 3,000).

## 4. Rules a change to the day flow must keep

From `SOLANA.md` §7 items 20–21:
- every step creates exactly one next crank, at the address `Hydra PDA("crank", blockId ‖ seq ‖ programId[0..16])`;
- no step fails in normal operation (early, stale, re-sorting, waiting for a seed: all re-schedule);
- a crank is never cancelled in its own trigger;
- a transaction never cancels and creates cranks together (the ER v0.16.0 notification bug);
- every account a template marks writable exists after the step.

## 5. Costs measured

| Item | Who pays | Amount |
|---|---|---|
| A pet (PetAccount + Paid + delegation records + fees) | the player | 5,333,840 lamports on devnet |
| A block (4,896 bytes + delegation records) | the game | 0.025522 SOL rent + 0.002164 records = 0.0277 SOL, i.e. 0.0028 SOL per pet |
| The program (453,520-byte file; `deploy.mjs` `HEADROOM` 1.2 gives 544,221 bytes of program data) | the game, once, as rent | 2.7653 SOL; with `HEADROOM=1` 2.3047 SOL. The deploy buffer needs the same again, refunded when the deploy ends |
| Bootstrap accounts: Config 304 B, Policy 4,792 B, World + records, HBRN mint, vrf-payer + records | the game, once | 0.0022 + 0.0250 + 0.0034 + 0.0011 + 0.0029 SOL; the Resort account (~10 KB) is about 0.05 SOL by size, not measured |
| A crank in flight (RoundStart 13 accounts / Turn 24 accounts) | the vrf-payer, returned by `Sweep` | ~20.5k / ~32.1k lamports |
| A commit of a pet (CommitPet, paid by the vrf-payer with the validator's fee vault) | the game | free for the first 25 commits a delegation, then 100,000 lamports |
| ER transactions, VRF on the ephemeral queue | — | 0 (MagicBlock's pricing page; the devnet cranker's 0.01 SOL did not move over thousands of triggers) |

Rent is the same on mainnet and devnet (`solana rent` on both, 2026-10-03): about 5,080 lamports per byte.

## 6. Economy measured on the localnet

Twenty pets in two blocks, `secondsPerDay` 1,200, program built 2026-10-03 (`ops.mjs STAGE=status`, world account).
- The reward index `rewardPerWorkPower` reached 3,829,589,280 after two days. The rule (`rules/life.ms` `settle`, `rules/emission.ms`) gives 3,820,297,776 with the day-2 work power; the gap is the work power changing between the two days.
- With 20 living pets under the 500-slot floor, the denominator is their work power (142,874) plus 480 empty slots × `BOT_WEIGHT` 10,609. The pets earn 2.7% of the day's 100,000 HBRN, about 136 HBRN an average pet a day. The other 97% goes to the virtual wild pets and is never minted.
- From 500 living pets on, the floor no longer applies and the whole emission goes to the pets (about 2 HBRN a pet a day at 50,000).
- A pet's gift to its owner (`giftOwed`) needs bonding above `GIFT_BONDING` (60) and a burrow above its food reserve. After two days of devoted owners, every pet still owed 0, so claim-to-L1 has run in host tests and the earlier devnet probe but not end to end on this program.

## 7. Re-sort on the relay flow

`FORCE_RESORT=1 STAGE=resort node tools/chain/ops.mjs <program>` begins only when every block is Idle. While `World.resorting` is set, every `RoundStart` re-schedules itself 30 s later. Twenty pets were re-sorted by combat strength in 0.65 s. The next round ran in both blocks with their new members: 12 triggers and no cranker warning.

## 8. Open: commits as the ER's backup

The ER holds the only current copy of World, Blocks and Pets. L1 sees a pet only when its owner runs `CommitPet` to claim. MagicBlock's ER keeps a ledger, but if it lost state, the game would fall back to the last commit, which for most accounts is the delegation itself. A commit service would bound the loss to its cadence. Fees: the first 25 commits a delegation are free, then 100,000 lamports per account per commit. The cadence is the person's call.

## 9. Scale measured on the localnet

50,000 players with their own keys, program `BZFbLX…`, `secondsPerDay` 1,800, `staggerSeconds` 300, one `hydra-cranker` 0.2.0, shared machine at load ~30, 2026-10-03:

| Stage | Time |
|---|---|
| admission mints (`players.mjs admit`) | ~850 players/s |
| claim + delegate, signed by each player | 50,000 in 378 s (132/s), 25,000 transactions, 0 failed |
| 5,000 blocks created and delegated (`ops.mjs`, 4 a transaction) | ~15 min |
| 50,000 pets placed (10 a transaction) | 51 s |
| 5,000 `StartBlock` | 10 s |
| first round of all 5,000 blocks, started together (dawn, reveal, 10 acts each) | 110 s: 32,780 triggers (peak ~570/s), 5,000 VRF answers, 0 cranker warnings, 0 resumes |
| `Sweep` of the 35,000 spent cranks | 4 ops ticks |

The vrf-payer held 1.287 SOL in the ER for this world's cranks in flight.

## 10. Measured limits of one cranker

- **The cache leaks closed cranks** (`hydra-cranker` 0.2.0 `cache.rs` `apply_update` evicts on an empty-data notification, which the ER never sends for an account leaving Hydra).
  - Every swept crank stays cached with `remaining` 0 and is scanned every slot.
  - After a 50,000-pet re-sort the cranker sat at 90% CPU firing 14–40 triggers/s. Each block had deferred its round about 34 times during the 17-minute re-sort, so about 170,000 cranks had been created and swept.
  - A restart cached only the 5,006 live cranks and fired about 485 triggers/s at 14% CPU. `cranker.sh` restarts it every 5 min: during a catch-up the rate fell from ~426 to ~100 triggers/s within five minutes as closed cranks piled up in the cache.
- **Every crank due at once is the worst case.** The cranker sends one trigger at a time, about 500/s on this machine. A world where all blocks are behind catches up at that rate; spread blocks (`staggerSeconds`) so a round asks for far less.
- **The 50,000-pet re-sort** took 17.5 min (`FORCE_RESORT=1 STAGE=resort`). Blocks defer their round while it runs: every 120 s plus their own stagger, so they come back spread over the stagger window instead of all at once.
- **Parked cranks after a restart under load are already spent.**
  - When the cranker's cache misses a crank's post-trigger update, it fires the crank again. Hydra answers `NotYetExecutable` (0x1), because the one-shot interval of 10⁹ slots pushed the next execution away; after ten such answers the cranker parks the crank.
  - Measured: 70 parks right after a restart during the 50k catch-up. Every one was a crank whose step had already run; the block's chain went on through its next crank.

## 11. The game's own cranker

`PROGRAMS=<program>[,…] CRANKER=<keypair> node tools/chain/gameCranker.mjs`, with `ER_RPC`, `ER_WS` and `BASE_RPC` from the env file.
- It reads every Block once and then follows their `crankSeq`/`dueSlot` through `programSubscribe`, filtered on the Block discriminator. Every 60 s it resyncs.
- It fires the due ones: it reads their cranks in batches of 100, builds `[SetComputeUnitLimit, Hydra Trigger, the stored template]` exactly as `hydra-cranker` does (`fire.rs`), and sends without preflight with up to 512 in flight.
- It re-reads a block when its crank is already spent but the block has not moved yet (a missed notification), and retries a step whose block has not moved after 300 slots, backing off up to 3,000.
- It keeps no cache of Hydra accounts, so it has nothing to leak. Hydra stays the on-chain schedule: anyone's cranker can still fire the game.

Measured on the localnet with 5,000 blocks (50,000 pets) on one shared machine:
- After `hydra-cranker` was stopped across a round start, it cleared the backlog at 670–723 triggers/s with 0 failed sends.
- In a normal round, ~100 triggers/s, worst lag 1,050 slots (10.5 s), typically 0.2–4.5 s, 83 retries, 0 failed sends, at 30% of a core. `hydra-cranker` 0.2.0 gave 30–66 s lag and fell to ~100 triggers/s within five minutes of churn.
- Over 72 minutes across days 4–6 (2026-10-03 08:21–09:34Z, machine load ~34): 347,000 triggers, median lag 3 s, p95 2 min. Three stalls reached 84 s to 4.3 min (08:48–08:51Z, 09:11–09:15Z, 09:49Z): in flight sat near 500, and retries grew by 28,000 in four minutes. Not explained yet; the ER may be slow, or the cranker may be the cause.
