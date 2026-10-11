# MagicBlock ER bugs that block running the game

Found running the 50,000-pet localnet (`docs/OPERATIONS.md` §9). The ER is `magicblock-validator` built from source at `e66d9147` (v0.16.0), config written by `tools/chain/localnet.sh`. Devnet and mainnet run on MagicBlock's own ER, whose config we do not see.

| # | Bug | Status |
|---|---|---|
| 1 | The account index stops at `MDB_MAP_FULL` while it holds free pages | open; localnet index raised to 2 GiB to keep the world running |
| 2 | RPC bank clock freezes while snapshot archive numbers keep advancing | upstream [magicblock-validator#1783](https://github.com/magicblock-labs/magicblock-validator/issues/1783); cranker workaround recovered the world 2026-10-09 |

## 1. The account index stops at `MDB_MAP_FULL` while it holds free pages

The ER keeps its account index in LMDB (`magicblock-accounts-db/src/index`, environment opened in `utils.rs` `create_lmdb_env` with `NO_SYNC | WRITE_MAP | NO_MEM_INIT | NO_READAHEAD`, map size `[accountsdb] index-size`). When the map is full, every index update fails, and the ER stops serving the game.

Measured on the fresh 50,000-pet world of 2026-10-06 (program `6pCHTsy…`, `index-size` 134,217,728, 16 KiB pages, so 8,192 pages):

- By 10:11Z (day 3, started 08:47Z) pages used were 8,191 of 8,192 while the live data was 1,166 pages (14%, `mdb_stat -e -f`).
- At 10:41:41Z (day 4) every index update failed: `ERROR magicblock_accounts_db::error: error=lmdb index error: MDB_MAP_FULL: Environment mapsize limit reached msg=Index update failed`. In the same second, evictions failed (`Failed to submit eviction transaction … TransactionError(CommitCancelled)`) and clones failed (`Failed to clone regular account … TransactionError(ProgramAccountNotFound)`), which a client sees as JSON-RPC -32003. 4,085,186 clone failures followed. The cranker sent nothing, ops could not fund the VRF payer, and all 5,000 block chains stopped.
- At 13:56Z the ER still failed with `MDB_MAP_FULL`. `mdb_stat` at that time: 8,189 pages used, 6,879 on the free list (388 entries), 17 reader slots and none holding a snapshot (`mdb_stat -r`), sub-databases `accounts-idx` 81,624 entries (418 pages), `owners-idx` 81,624 (573 pages), `programs-idx` 81,624 (1 page), `deallocations-idx` 17,942 (1 page). Full output: `out/localnet/archiveWorld20261006b/indexAtStall.txt`, the ER log `out/localnet/archiveWorld20261006b/er.log` (1.8 GB).

So LMDB had free pages and no reader pinning them, and still refused to grow the index. The cause is not found. Suspects, none measured:

- `AccountOffsetFinder` (`index/utils.rs`) keeps a `RoTransaction` open for its own lifetime. A finder kept for a long time pins the snapshot it opened, so pages freed after it cannot be reused. It does not explain the stall after 13:56Z, when no reader held a snapshot, unless the stall had become permanent by then.
- One write transaction that needs more pages than the free list hands back (`WRITE_MAP`, eviction batches).

Not measured: whether the first world of the same day (stopped at 08:40Z) met the same error. Its ER log is 72 KB and holds none of these lines, so it logged less, or did not reach the limit.

Third-world observation, 2026-10-06, same program and validator, `index-size` 2 GiB, Hibernal tree `cd0c708d59589141ae2491d2423b19b65f40048a`: `out/localnet/run20261006c/watch.jsonl` recorded three healthy samples from 14:41:44.947Z to 15:01:45.185Z, all at epoch 1 with 50,000 placed and living pets. Pages used rose 2,704 → 5,066 of 131,072; live pages 1,009 → 1,341; free pages 1,695 → 3,725. Endpoint slope: 7,085 pages/hour, or 110.7 MiB/hour at 16 KiB/page, over only 20 minutes. This is an early-window measurement, not a sustained growth rate or a forecast of time to exhaustion; reuse and the day-8 gate are not yet proved.

The same watch reached `EPOCH8` at 18:11:47.270Z: 50,000 placed, 43,788 living, healthy sentinel, index 12,169/131,072 pages (9%), live 1,549 and free 10,620. Across 22 samples spanning 3.50065 hours, pages used grew by 9,465: endpoint-average 2,704 pages/hour or 42.25 MiB/hour, not the initial 110.7 MiB/hour. Two samples alarmed on stale ops status during the day-7 re-sort, not on the index; both recovered by the endpoint. This proves survival to this gate, not an LMDB root fix or multi-real-day endurance.

Workaround in place: `tools/chain/localnet.sh` sets `index-size` to 2 GiB, which only delays the limit if the free list is never reused. `tools/chain/sentinel.mjs` alarms when pages used pass `ER_INDEX_PERCENT` (70%).

Next: reproduce in `magicblock-accounts-db` with a small map (insert and remove accounts in a loop the way clones and evictions do) and see whether `MDB_MAP_FULL` comes while `mdb_stat -f` shows free pages. That work belongs to a session started in the validator checkout, with this entry as its brief.

## 2. RPC bank clock freezes while snapshot archive numbers keep advancing

Third world, same validator/program as above, observed 2026-10-07 evening UTC:

- Sentinel first alarm: **13:40:22.679Z**, ER slot **8,414,055** frozen for75seconds. At17:28:47.986Z it reported13,781seconds frozen; L1 slot170,006 was progressing.
- Read-only curl to local ER `http://127.0.0.1:17799` independently returned8,414,055 for default, processed, confirmed and finalized `getSlot`. Processed `getBlockHeight`, `getEpochInfo.absoluteSlot`/blockHeight, and `getLatestBlockhash.context.slot` all agreed. **getHealth still returned `ok`**. L1 processed getSlot was172,417. This is not only a commitment-default discrepancy or an endpoint reachability failure.
- World epoch46,5,000 blocksIdle,50,000 pets placed,38,784living; last re-sort epoch42. Cranker sends0/s and no in-flight transactions. Ops watchdog reportedstuck0/resumed0/maxOverdue0 while using the same frozen ERslot: it does **not** prove maintenance recovery.
- Validator process4094 was alive. The ER log continued snapshot archives through `snapshot-000009864000.tar.gz` at17:40:34.532144Z, plus ledger compaction at17:30. Therefore do not describe the entire validator process as stopped, or infer the archive suffix is the RPC-visible bank slot without tracing it.
- Sentinel index12% (15,942/131,072pages,1,540live/14,402free), disk56GiB. The copied current ERlog has no MDB_MAP_FULL or panic sighting; DLP scan RPC timeouts at15:11/15:16/15:26/15:31 are later than the initial freeze and not a demonstrated cause. Bug#1 is not established as this stall's root.

Evidence frozen under `/tmp/hibernalErStall20261008a/`: sentinel/opsJSON, ERlog, per-commitment RPC replies and bank/health replies. These are diagnostic reads only; no signing, funding, restart/reset, kill or validator/std implementation edit. This world uses the historical private build, not the goal's gated-upstream build; neither elapsed uptime nor these diagnostics count as48-hour upstream endurance.

Cause, 2026-10-09: `magicblock-aperture/src/processor.rs:169` (`EventProcessor::run`) matches only `Ok(latest)` from the block broadcast (capacity 32). A `Lagged` disables the block arm until an account update or transaction status ends the `select!`, and by then the receiver is usually behind again. A standalone tokio copy of the loop (`/tmp/mbLaggedRepro`) stays frozen with no traffic or one transaction every 3 blocks and recovers at one per block; handling `Lagged` recovers in every case. Same code in v1.0.0; on 2026-10-09 the mainnet ERs `as`/`eu` reported 0.16.0 `e66d914` and `devnet-as` reported 1.0.0 `cc32775`. Filed as magicblock-validator#1783.

Recovery, 2026-10-09: `gameCranker.mjs` sends 4 compute-budget-only transactions, signed with the frozen blockhash, when the ER slot has not moved for `FREEZE_SECONDS` (10). The restarted cranker sent one burst at 06:34:20.765Z and the ER slot moved from 8,414,055 to 23,167,590 by 06:37:51Z, the bank having advanced about 14.7M slots while the RPC was frozen. The sentinel cleared its ER alarm at 06:34:33.913Z; no second burst was needed. Remove the workaround once a fixed release runs on the ERs we use.
