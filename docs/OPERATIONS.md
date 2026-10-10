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

Wallets show a token's name, ticker and logo from its Metaplex metadata, not from the mint. On devnet `TOKEN_URI=https://hibernal.metascriptlang.org/tokens` makes `bootstrap` create it once for both mints: HBRN through `CreateHbrnMetadata` (the mint PDA signs as its own authority, the config authority keeps the update authority), SKR straight through Metaplex with the deploy wallet as mint authority. The admission service serves the JSON and logos from `tools/chain/tokens/`. Localnet has no Metaplex program, so it leaves `TOKEN_URI` unset.

After a deploy, the IDL is published for explorers and other-language clients as a canonical Codama IDL through Program Metadata (`ProgM6JCCvbYkfKqJYHePx4xxSUSqJp7rh8Lyv7nk7S`; `localnet.sh` clones it from devnet). `msc run program/idl.cms | sed -n '/^{/p' > out/idl/hibernal.json` writes the Anchor 0.1.0 IDL (the first line is the build's); `node tools/chain/idlCheck.mjs` requires every client-built instruction in `hibernal.mjs` to carry the IDL's writable, signer and address flags; `STAGE=publish KEYPAIR=<upgrade authority> node tools/codama/publish.mjs <program>` converts it (`out/idl/hibernal.codama.json`, the program id filled in) and writes it on L1, `STAGE=fetch` reads it back. The CLI derives its websocket only for port 8899, so the script hands it a throwaway Solana config with `BASE_WS` (default: the RPC port + 1). A write cut off half-way leaves a truncated metadata account and 4.9 KiB buffers (measured on the 2026-10-06 localnet): `program-metadata close idl <program>` and `close-buffer <address>` for each one `list-buffers` shows, then write again. On that localnet the canonical Codama IDL of `6pCHTsy…` holds 0.0367 SOL and reads back equal to `out/idl/hibernal.codama.json`. The Codama IDL carries no PDAs until `std/solana` emits seeds (`~/metascript/.inbox/compiler/2026-10-06-std-solana-idl-pda-seeds-for-codama.md`). `npm install` in `tools/codama` once; it is kept apart from `tools/chain/node_modules`, which the live lanes share.

Devnet: the same commands with `source out/devnet/env.sh`:
- `NET_DIR=out/devnet`;
- MagicBlock's queue `5hBR571…` and validator `MAS1Dt9…`;
- the DevAdmission group, and `GROUP_KEYPAIR=out/devGroupMint.json` for `players.mjs`;
- a cranker started against `https://devnet-as.magicblock.app` with `--base-rpc-url https://rpc.magicblock.app/devnet`.

On 2026-10-03 at 20:04Z the disk filled: the 50,000-pet localnet's L1 ledger reached 31 GB and ER storage 20 GB in about 20 hours. L1 died; the ER, devnet ops loop and owner lane failed their writes.

Recovery on 2026-10-04 uses `tools/chain/localnet.sh` `l1`/`er`: L1 retention is in shreds, not bytes; ER ledger size is a pruning threshold, not a strict disk quota. The ER v0.16.0 truncator checks every two minutes (`magicblock-ledger/src/ledger_truncator.rs`, checkout `/Users/le/projects/magicblock-validator`, running binary `e66d9147`). Smoke on Hibernal base tree `511868044a069d6e35ddf512af5f5533cab501ac` plus the storage-cap change: a separate real ER with a 512 KiB ledger threshold and 1,000-slot superblocks reached 1,190,133 bytes, then deleted slots 0–7,256 and compacted in 408 ms; after 13 snapshots only the latest two remained. `getFirstAvailableBlock` is mocked to 0 in this ER, so it cannot prove retention. L1 and ER RPC both served advancing slots after `localnet.sh up`; generated stores were 485 MB / 13 MB at the recovery check. Logs are not bounded by these ledger settings; the long 50k run still needs disk-growth observation.

L1 retention also executed on the 50k run: its real `getFirstAvailableBlock` returned 8,674 at current slot 11,831, so old blocks had been purged. Later `du -sh` reported 7.7 GiB for the L1 ledger (7.3 GiB RocksDB, 261 MiB accounts) and 2.2 GiB ER storage; `df` had 151 GiB free. These physical sizes are not the configured quota: RocksDB metadata/compaction and logs add space beyond retained shreds, and logs remain unbounded.

`Config.secondsPerDay` sets the length of a game day: 86,400 on mainnet, compressed on localnet and devnet. It is fixed at `Initialize`, which refuses a day shorter than four seconds, a zero slot time and a zero turn gap.

## 3. Services and what they repair

| Service | Does | If it stops |
|---|---|---|
| `gameCranker.mjs` (§11); `hydra-cranker` under `tools/chain/cranker.sh` as a backup (restart every 5 min and on exit, `WORKAROUND.md`) | fires each due crank (one trigger per step) | pets stop; restarted, it fires every overdue crank at once and the block catches up (measured: 6 min down, a round 2.4 min late, caught up in 6 s) |
| `ops.mjs STAGE=run`, every `TICK_SECONDS` | places claimed pets into Idle blocks (creating blocks as needed, and delegating every created block that is not delegated yet, including one an interrupted run left behind); `StartBlock` for new blocks; `Sweep` of spent cranks (returns their rent to the vrf-payer); watchdog; re-sort when every block is Idle; `Load` on the ER for every living pet whose L1 `Ledger` counts more purchases than it has loaded and that has an owner slot free, so an owner signs only the L1 `Buy`; tops up the vrf-payer from its delegated funder; writes `opsStatus.json` | new pets wait unplaced, bought items wait until the owner sends `Load`, spent cranks keep their rent and fill the cranker's cache, a broken chain stays broken. Measured on devnet (500 pets): down 5 h 50 min after a full disk, the vrf-payer ran dry with 463 spent cranks unswept and every chain stalled; restarted, it swept and topped up in about 25 s and the overdue blocks went from 33 to 1 within a minute |
| VRF oracle | answers each round's request | the block's first turn re-schedules itself every 1.5 s and requests again after 30 s; the round starts when an answer arrives (measured: oracle down 2.5 min across a round start, the round ran 2 s after it came back, the day-end turn 7 s after) |
| `sentinel.mjs <program>`, every `TICK_SECONDS`; separate from `ops` so it outlives it | alarms (stderr, `sentinelStatus.json`, `ALERT_COMMAND` on stdin) when the L1 or ER slot stops, a block is more than `LAG_SECONDS` past due, the VRF payer is below one crank per block, `OPS_STATUS` goes stale, the disk falls under `DISK_FREE_GIB`, or the localnet ER index (`ER_INDEX`, `mdb_stat`) passes `ER_INDEX_PERCENT` | nobody hears of a stall: on 2026-10-05 the localnet ER index filled at 20:25Z and the disk at 01:55Z, and the world sat dead for 6 h unnoticed. Run once against that world it raised all five within 30 s; against devnet, none |

The watchdog resumes a block whose live crank is gone and whose due slot is more than `WATCHDOG_SLOTS` past. `StartBlock` refuses a chain that is still alive (`RESUME_GRACE_SLOTS` = 3,000).

Startup recovery must reclaim locked rent before topping up an existing delegated payer. Measured on the restored 50k world, 2026-10-04: the old `ops.mjs` `run` order failed before its first tick (`insufficient lamports 708536960, need 1106512896`) while spent cranks held the rent. With startup `Sweep` before `bootstrap`, the same world recovered 37,658 exhausted cranks, topped up by 219,369,920 lamports and continued its ops loop; the next sweep recovered another 18,753. Source base tree `511868044a069d6e35ddf512af5f5533cab501ac` plus the startup-order fix. No program/backup-commit change.

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
- Recovery measurement on devnet, 2026-10-04 02:35Z, current program `9Z51nH…` (Hibernal base tree `511868044a069d6e35ddf512af5f5533cab501ac`): player 93's day-7 claim `2SsyoYkJ…` failed while creating the HBRN ATA, before Hibernal's claim instruction. System logged `insufficient lamports 989840, need 1488440`. After a 0.01 SOL test top-up, the same player's own key signed commit → L1 claim: destination balance, Paid total and mint supply each increased from 0 to 537,350 base units. Claim signature `5FXVPDrbaHwTeRLfSq939qpg7bw9VjLLZWY5a4Y9gUpYdhaSCWn4WyA7wE7Yf9eGv42CwGdrcRswNJvcVtCCRHD6`; raw evidence `out/devnet/claimRecovery93.json`.
- Whole-history lookup of the 262 recorded failures found 245 buys and one claim with insufficient SOL, one buy with a missing SKR source account (`Custom 3007`, source had zero pre-transaction lamports), and 15 timed-out signatures absent from both queried histories. No confirmed insufficient-SKR-balance failure was found. Evidence: `out/devnet/failureEvidence500.json`, `buyGrowth3007.json`. A 0.92341664 SOL test top-up restored 124 owners to 0.01 SOL (13 transactions, zero failed sends/statuses); this and player 93's extra 0.01 SOL are simulated-player funding, not publisher launch/operating costs.
- `behaviour.mjs` `onramp` previously logged success after a failed mint. A real localnet smoke with an unfunded isolated setup signer exited 0 and printed `1 owners hold at least 200 SKR` after `unconfirmed`; after the fix it exited 1 naming owner and signature, before owner actions. Devnet provisioning then completed for all 500 owners and their lane resumed. Localnet provisioning completed for all 50,000.
- The resumed 500-owner lane completed its configured 720 real minutes with exit 0, reaching day 16 (snapshot 15:04Z: 458 living pets, HBRN supply 45,415,390 base units; day 16 had 11 successful claims). This was not an error-free run: since restart, recorded buys included 123 growth, 155 food and 3 insurance `Custom 1` refusals, plus 4 food timeouts and one claim timeout. Continuation initially stopped on SKR provisioning: two MagicBlock RPC sends had no historical signature status; a fresh provisioning simulation succeeded and publisher wallet held 2.531201654 SOL. Solana's public RPC then hit HTTP 429 during confirmation polling. These transport observations do not establish that the on-chain program failed.

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

Recovery run, 2026-10-04, program `3x9K737Ebi9EuyGuSXdeioMjJcbXQHFNcecG1reCvr6x`, same 453,520-byte artifact and `p29s5` policy, source base tree `511868044a069d6e35ddf512af5f5533cab501ac` plus harness fixes:
- Bootstrap → admit → fund → owner-signed claim/delegate → export: 684.7 s total; admission transaction batches 93.6 s, claim/delegate batches 158.6 s, zero failed sends/statuses. Batch timings exclude key derivation and pre-stage RPC reads.
- 5,000 blocks created/delegated, 50,000 pets placed and 5,000 chains started in the following 821.5 s stage; snapshot at 02:56Z had zero unplaced pets. The game cranker and repaired ops loop run unattended.
- Owner lane: all 50,000 keys loaded and grouped; `BLOCK_PARALLEL=64`, `PARALLEL=8`, 1,800-second days, 300-second stagger. At the measured second dawn, 18,929 visits: bank/talk 18,929/18,929 each; insurance 11,584, growth 4,089, food 14 purchases and the same successful consume counts; zero unexpected owner failures. All 5,000 blocks were covered. First-day opens saw `EmptyHarvest`; second-day bank/talk succeeded after dawn. The lane is scheduled for 4,320 real minutes; three elapsed unattended days are not yet proved.
- Coupled boundary observation, 03:22:07–03:37:08Z, 91 samples every 10 s: world epoch 1 → 2, 50,000 living pets, zero unplaced pets, no watchdog resumes. ER `getSlot` latency median/p95/max 0.94/5.11/50.94 ms; sampled watchdog overdue was 0 (not a continuous cranker-lag measurement), maximum observed account-lock queue stayed 12. The prior 84 s–4.3 min stalls did not reproduce in this window; their cause is still unassigned. Raw ER processing histograms and ops/owner state: `out/localnet/recoveryBoundary.jsonl`.
- Long-run observer stopped after 1,130 samples (epoch 3 → 22) with `JSONDecodeError` while reading the owner status. Publishers had used truncate-and-write; `behaviour.mjs` `save` and `ops.mjs` `saveSnapshot` now publish by same-directory temporary file plus rename. With repaired ops running, 6,938 concurrent reads of the real ops/owner snapshots over 10 s decoded without failure. Observation resumed append-only with `out/localnet/recoveryObserver.py`; retained samples were not discarded. The restart is an observation gap, not a continuous three-day proof. At 13:40Z, ops reported epoch 22, 40,053 living pets and zero resumes; owner history already contained 1,145 `buy:insurance` refusals with `Custom 2006`, not yet diagnosed. Do not extrapolate the clean day-2 owner measurement to the whole run.

Fresh world on the new program, 2026-10-06 (program `6pCHTsycBJgDYs59SWUDMEQvoQptuP3t4a8PG365xPg6`, 471,496 bytes, brain `p31s5`, purchase ledger, engage, `secondsPerDay` 1,800, `staggerSeconds` 300; the day-41 world's evidence is in `out/localnet/archiveDay41/`):
- `players.mjs` keys 56 s, admit 130 s (910/s), fund 54 s, claim + delegate 207 s (410/s), 0 failed sends or statuses. `ops.mjs run`: 5,000 blocks created and delegated, 50,000 pets placed and chains started in about 20 minutes, 6,225 spent cranks swept in the first sweep.
- `behaviour.mjs` `STAGE=run` starts with the SKR onramp at `PARALLEL` (8): about 50 minutes for 50,000 owners. Run `STAGE=onramp PARALLEL=64` first: 355 s.
- Day 1 of 50,000 owners: 8,226 visits, each engaged; 16,901 app opens, 14,194 engaged, 2,707 refused `EngagedThisRound` (a block's round falls in the world round of its visit); 4,986 insurance and 1,801 growth bought on L1 and loaded on the ER; 0 unexpected failures.
- ER index: the ER does not reuse the free pages of its account index, so LMDB's "pages used" is the limit, not the live data. On the 2026-10-06 world it reached 8,191 of 8,192 pages (`index-size` 128 MiB, 16 KiB pages) on day 1 while the live data was near 1,177 pages (14%). On the fresh world of the same day, at 10:41:41Z on day 4, every index update failed with `MDB_MAP_FULL` while 6,879 pages were free and no reader held a snapshot: evictions failed (`CommitCancelled`), every clone failed (`ProgramAccountNotFound`, sent to clients as -32003), and all 5,000 block chains stopped. `sentinel.mjs` alarms on pages used against `ER_INDEX_PERCENT`; it alarmed on used − free before, which read 14% while the ER was at its limit.
- ER account cache: magicblock-validator `e66d914` monitors at most 5,000 accounts plus a secondary 20,000 (`magicblock-config/src/consts.rs` `DEFAULT_MAX_MONITORED_ACCOUNTS`, `DEFAULT_SECONDARY_MAX_MONITORED_ACCOUNTS`). 50,000 owner wallets and ledgers are cloned as they act, so the ER evicts and re-clones them. At 07:47:06Z on day 2 one eviction burst failed (`Failed to submit eviction transaction`, 3) and 30 clones with it (`Cloner error … CommitCancelled`): 28 owner `engage` sends failed, 18 as `CommitCancelled` and 10 as the RPC's `signature verification failure`. Owners' next actions went through. A client must sign again with a fresh blockhash and resend: the ER has already reserved the first signature, and neither failure wrote state (a clone failure is refused before execution; `CommitCancelled` is a failed account write). The ER reports the clone failure as JSON-RPC -32003, which `@solana/kit` names `signature verification failure`. `hibernal.mjs` `send` and `behaviour.mjs` `submit` do this up to `CLONE_ATTEMPTS` times; `behaviour.mjs` counts the resends per day as `cloneRetries`: on day 3 of the second world of 2026-10-06 (16,051 visits, 25,436 opens) the ER refused 50 sends this way and all 50 went through on a resend, with 0 unexpected owner failures.
- `tools/chain/sessionProbe.mjs <program> 0`: `create_session_v2` on L1 10,053 CU; `engage` signed only by the session key on the ER 11,976 CU, fee 0, `engaged_today` 0 → 1, the ER cloning the token from L1; a stranger holding the token refused 6006 `NotTheOwner`; `revoke_session_v2` closed the token.
- Third rebuild, 14:15–14:37Z, same program/artifact/policy with the ER index raised to 2 GiB (source tree `cd0c708d59589141ae2491d2423b19b65f40048a`): three watcher samples, 14:41:44.947–15:01:45.185Z, had 50,000 placed/living pets and no sentinel alarms. At 15:09:11Z the sentinel reported 5,000 blocks, zero overdue, fresh ops (23 s), and index pages used 5,066/131,072 (4%). The resumed session read owner status with no unexpected failures, 19,032 day-1 visits and 25,372 opens; day-2 owner actions had begun while the world snapshot still reported epoch 1. Direct `getSlot` probes returned L1 5,588 and ER 320,386. Index growth in the initial 20-minute window was 110.7 MiB/hour (`ER-BUGS.md` §1); neither sustained growth nor day 8 is proved. Evidence: `out/localnet/run20261006c/watch.jsonl`, `sentinelStatus.json`, `behaviourStatus50000.json`, `opsStatus.json`. The existing watcher remains running; a session-owned background waiter now reports its `EPOCH8` or `UNHEALTHY` result instead of requiring manual polling.
- Devnet onboarding prerequisite check, 2026-10-06, old program `9Z51nH…`, source tree `cd0c708d59589141ae2491d2423b19b65f40048a`: read-only `getAccountInfo` confirmed Config PDA `8dU4sJ24CJ2bBE5i3YUpzQ5BnjHkeNdnNHxbT3gaaDUp`, owner/discriminator checked, 304 bytes, admission group `6jXijzhCm1Njikk3vLTmrw1mjPzWrwKherDYvELgwCpR`. The running ops process uses `DISCOVER=registry PETS_FILE=out/devnet/players.json TICK_SECONDS=20 STAGE=run`; it therefore does not discover an unregistered Android wallet's new Claim through transaction history. `out/devnet/opsStatus.json` at 15:24:53.619Z reported all 50 blocks stuck, epoch 28, 413 living pets, worst live-crank overdue 8,683,454 slots. A direct ER `getSlot` returned 732,815,021, proving RPC response, not world progress. Cause not diagnosed; no service restart or transaction sent. HUD session received these blockers and the signer/readiness contracts from `program/admission.ms`, `program/day.ms` and `tools/chain/ops.mjs`; those current-source contracts are not a new binary-parity proof for old devnet.
- Devnet stall narrowed without sending: `lsof -a -p 27919 -d 1,2` identified the running cranker's `out/devnet/gameCranker.log`; reports from 15:25–15:27Z stayed at slot 724,052,272, sent 63,193 and notifications 39,630, zero in-flight, while the direct ER RPC slot above was 732,815,021. `tools/chain/gameCranker.mjs` `refreshBlockhash` initializes the scheduler slot from RPC only when it is zero; subsequent clock updates come from `watchBlocks`' slot notification stream. The stream catches only log errors, and `resyncLoop` refreshes blocks but not the clock. The observed scheduler clock is stale. Why notifications stopped and whether other conditions also block progress remain unmeasured; no restart or root repair applied.
- Read-only fixture compatibility check, 17:44:21Z: player 0 owner `6cdGipCgtME82TZyWw7PcU9r6GMZgHhaWTNBNxFMoqv`, mint `B9BgHeSaRBgAuwEGtjJ3KWGEWWMZJDqipvvj9Ri3EAha`, Pet PDA `HEpmfAPPSfju6YTDNrzsrJ4zYqBc9gE4ofHqkKan9fJF`. Direct `getAccountInfo` on L1 and ER returned matching PetAccount discriminators and 272-byte data; L1 owner was the delegation program, ER owner the old Hibernal program. Slots were L1 508,172,252 and ER 733,646,446. This old fixture cannot be read as the current 296-byte PetAccount payload plus discriminator. The 17:43:32Z ops snapshot still reported epoch 28 and 50 stuck blocks. Installed compiler binary/support advanced to `369dbc18a`, but the actual upstream port build still fails at the same four inline-generic `try` sites; no matching new deployment is available.
- Third-world watcher completed `EPOCH8` at 18:11:47.270Z: 50,000 placed, 43,788 living, sentinel healthy with no alarms, index 12,169/131,072 pages (9%); owner snapshot had `failures: []`. All 5,000 blocks were non-overdue at 18:12:14Z; ops at 18:12:18Z reported epoch 8, `resorting=0`, `resortedEpoch=7`, zero watchdog resumes. The ops log confirms 50,000 pets re-sorted into 5,000 blocks by combat at 18:01:44Z. Endpoint gate passed, but the run was not alarm-free: 17:51 and 18:01 watcher samples alarmed on stale ops status (417/1,014 s), and the ops log records 17 startup `start block` and 12 later `sweep` transactions refused with `UnsupportedProgramId`; their cause and per-signature recovery are not established here. Index endpoint-average growth over 22 samples/3.5 h was 42.25 MiB/hour, not a long-term forecast. Raw evidence remains in `out/localnet/run20261006c/`. This is eight accelerated game days, not the card's multiple real days or new-wallet Android proof.

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
