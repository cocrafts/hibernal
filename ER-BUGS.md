# MagicBlock ER bugs that block running the game

Found running the 50,000-pet localnet (`docs/OPERATIONS.md` §9). The ER is `magicblock-validator` built from `/Users/le/projects/magicblock-validator` at `e66d9147` (v0.16.0), config written by `tools/chain/localnet.sh`. Devnet and mainnet run on MagicBlock's own ER, whose config we do not see.

| # | Bug | Status |
|---|---|---|
| 1 | The account index stops at `MDB_MAP_FULL` while it holds free pages | open; localnet index raised to 2 GiB to keep the world running |

## 1. The account index stops at `MDB_MAP_FULL` while it holds free pages

The ER keeps its account index in LMDB (`magicblock-accounts-db/src/index`, environment opened in `utils.rs` `create_lmdb_env` with `NO_SYNC | WRITE_MAP | NO_MEM_INIT | NO_READAHEAD`, map size `[accountsdb] index-size`). When the map is full, every index update fails, and the ER stops serving the game.

Measured on the fresh 50,000-pet world of 2026-10-06 (program `6pCHTsy…`, `index-size` 134,217,728, 16 KiB pages, so 8,192 pages):

- By 10:11Z (day 3, started 08:47Z) pages used were 8,191 of 8,192 while the live data was 1,166 pages (14%, `mdb_stat -e -f`).
- At 10:41:41Z (day 4) every index update failed: `ERROR magicblock_accounts_db::error: error=lmdb index error: MDB_MAP_FULL: Environment mapsize limit reached msg=Index update failed`. In the same second, evictions failed (`Failed to submit eviction transaction … TransactionError(CommitCancelled)`) and clones failed (`Failed to clone regular account … TransactionError(ProgramAccountNotFound)`), which a client sees as JSON-RPC -32003. 4,085,186 clone failures followed. The cranker sent nothing, ops could not fund the VRF payer, and all 5,000 block chains stopped.
- At 13:56Z the ER still failed with `MDB_MAP_FULL`. `mdb_stat` at that time: 8,189 pages used, 6,879 on the free list (388 entries), 17 reader slots and none holding a snapshot (`mdb_stat -r`), sub-databases `accounts-idx` 81,624 entries (418 pages), `owners-idx` 81,624 (573 pages), `programs-idx` 81,624 (1 page), `deallocations-idx` 17,942 (1 page). Full output: `out/localnet/archiveWorld20261006b/indexAtStall.txt`, the ER log `out/localnet/archiveWorld20261006b/er.log` (1.8 GB).

So LMDB had free pages and no reader pinning them, and still refused to grow the index. The cause is not found. Suspects, none measured:

- `AccountOffsetFinder` (`index/utils.rs`) keeps a `RoTransaction` open for its own lifetime. A finder kept for a long time pins the snapshot it opened, so pages freed after it cannot be reused. It does not explain the stall after 13:56Z, when no reader held a snapshot, unless the stall had become permanent by then.
- One write transaction that needs more pages than the free list hands back (`WRITE_MAP`, eviction batches).

Not measured: whether the first world of the same day (stopped at 08:40Z) met the same error. Its ER log is 72 KB and holds none of these lines, so it logged less, or did not reach the limit. Also not measured: how fast pages used grow with a 2 GiB index (the sentinel records it from the rebuilt world on).

Workaround in place: `tools/chain/localnet.sh` sets `index-size` to 2 GiB, which only delays the limit if the free list is never reused. `tools/chain/sentinel.mjs` alarms when pages used pass `ER_INDEX_PERCENT` (70%).

Next: reproduce in `magicblock-accounts-db` with a small map (insert and remove accounts in a loop the way clones and evictions do) and see whether `MDB_MAP_FULL` comes while `mdb_stat -f` shows free pages. That work belongs to a session started in the validator checkout, with this entry as its brief.
