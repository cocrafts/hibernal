# SOLANA — Hibernal's on-chain build

> Scope: only what Hibernal's program needs from Solana, MagicBlock Ephemeral Rollups (ER) and the MetaScript compiler. Design decisions live in `GAME-DESIGN.md` §4 (randomness) and §12 (brain on chain); the game spec in `BRIEF.md` §5.1. Everything here targets the hackathon build.
>
> Tags: **Measured** = run and observed · **Documented** = read in MagicBlock docs or source, not yet run by us · **Unknown** = must be probed.

---

## 1. Target shape

- One program written in MetaScript, built with `msc build --os=solana`.
- **Pinocchio-shaped** (BRIEF §5.1): accounts are fixed-size structs read and written in place; 1-byte `kind` + 1-byte `version` head; instruction data = 1-byte opcode + fixed args; no Borsh, no Anchor, no IDL. `rules/layout.ms` is shared by program and client.
- Game state is delegated to MagicBlock's Ephemeral Rollup. The brain is an instruction (`act`) triggered by the ER's native crank. Dice come from MagicBlock VRF inside the ER.

### Accounts

| Account | Seeds | Lives |
|---|---|---|
| `GlobalConfig` | `["config"]` | delegated to ER |
| `Block` | `["block", id]` | delegated to ER |
| `Pet` | `["pet", admission_mint]` | delegated to ER |
| `FightPending` | `["fight", attacker, counter]` | ER, open between request and VRF callback |
| MagicBlock session token | owned by `KeyspM2ssCJbqUhQ4k7sveSiY4WjnYsrXkC8oDbwde5` | L1, read only (owners who drive their pet themselves) |
| Policy weights | program-derived, `["policy"]` | L1, read by `act`; updated by the config authority (`BRIEF.md` D15) |

### Instructions by layer

| Instruction | Layer | Signer | Needs |
|---|---|---|---|
| `init_config`, `update_config` | L1 | authority | R2, R3 |
| `claim` | L1 | owner | R2, R3, SGT TLV read, System `create_account` (R6) |
| `delegate_pet`, `delegate_block`, `delegate_config` | L1 | payer | R6 → delegation program |
| `undelegate` callback | L1 | delegation program (CPI) | fixed discriminator, System `create_account` signed by PDA (R6) |
| `buy_growth`, `buy_insurance`, `buy_skin`, `feed` | L1 | owner | Token-2022 `transfer_checked` (R6); interaction with a delegated `Pet` is **Unknown** (§7) |
| `close_dead_pet` | L1 | anyone | R2, realloc/close helper |
| `schedule_act` | ER | payer | R6 → magic program `ScheduleTask` |
| `act` | ER | crank (validator) | R2, R12, brain inference |
| `tick`, `eat`, `harvest_claim`, `allocate` | ER | crank or owner | R2, R12 |
| `level_up` | ER | crank or owner | R2, R12; at level 10 also a VRF request (R6) |
| `attack` | ER | crank or owner | R2, R12, VRF request (R6), opens `FightPending` |
| `consume_fight`, `consume_talent` | ER | VRF program identity | R2, R12, callback signer check |
| `commit` | ER | payer | R6 → magic program |

---

## 2. What MetaScript does on Solana today — Measured

From the MetaScript Solana meetup demo (LiteSVM and a local validator, 2026-09-09) and this repo's probe (2026-09-12):

| Program | Result |
|---|---|
| `hello.ms` (log only) | 108 CU, `.so` 1,840 bytes; Anchor 1.2.0 equivalent 346 CU, 49,280 bytes |
| `math.ms` | 4,037 CU: calls, recursion, `for` loops, mutable locals, struct by value, int32/int64 arithmetic all run on chain |
| `fib(15)` / `fib(18)` / `fib(20)` | 20,220 / 85,320 CU / over the 200k default budget |
| `tools/rulesProbe.ms` | links with `--os=solana` since R12 scalars landed (17 KB `.so` on `cce059c8`, 2026-09-24) |

- Pipeline: MetaScript → C → LLVM bitcode → `llvm-link` → `sbpf-linker` → sBPF **v3** ELF (`e_machine=247, e_flags=3`). `cargo-build-sbf` defaults to v0, which agave 4.2.2 refuses to deploy; Rust control programs must pass `--arch v3`.
- `@comptime` results are free on chain but must be locals, not module constants (R12).
- The `time.h` / `assert.h` errors printed during a Solana build come from unused runtime files and do not stop the output.

**Fails today:**

| Construct | Symptom |
|---|---|
| module `const` of struct, `T[N]` or string type | compile error `FREESTANDING E02` at the binding; `.rodata` for aggregates waits on SOLANA-BUGS #6 (fix committed on `wt/solana-const-fold-2`, waits merge-train) |
| `console.log(number)`, template literals, string `+` | `exceeded max BPF to BPF call depth` |
| `String(uint64)` | same |
| `process.exit()` | `ProgramFailedToComplete` |
| reading accounts, PDAs, CPI | not implemented (R2, R3, R6) |

---

## 3. Compiler gaps Hibernal depends on

Work items live in the recompiler repo; ids match `ROADMAP.md`.

| Id | What | Why Hibernal needs it | ER probe | Est. |
|---|---|---|---|---|
| **R2** | Parse the entrypoint buffer into typed, zero-copy `AccountInfo` views (`std/solana/entrypoint.ms`); reference: C SDK `sol_deserialize` | every instruction reads and writes `Pet`, `Block`, `GlobalConfig` | **yes, first** | 2 d |
| **R12** | Module constants must not become discarded `.data` globals: fold scalar constants, emit `static const` into `.rodata` | `rules/` shares constants across files. Scalars fold since `8be46044..e5f0ec68` (installed `cce059c8`): `rulesProbe` and `fightProbe` link. Aggregates in `.rodata` open behind SOLANA-BUGS #6 (fix committed on `wt/solana-const-fold-2`, waits merge-train) | **yes, first** | 0.5–1 d |
| **R3** | Syscalls: `sol_create_program_address`, `sol_try_find_program_address`, `sol_sha256`, `sol_get_clock_sysvar`, `sol_log_64_` | verify PDAs, sign as PDA in CPI, epoch from clock, log numbers without strings | yes | 1 d |
| **R6** | CPI through `sol_invoke_signed_c`: build `SolInstruction` / `SolAccountMeta` / `SolAccountInfo` / `SolSignerSeeds` in C ABI without heap, behind a flattened shim | delegation, commit, undelegate, VRF, crank, System, Token-2022: **no ER without it** | **yes, decisive** | 2–3 d |
| R5 | Error ABI: `u64` return codes, `panic` → log + abort, `ProgramError` | clean failure codes the client and tests can match | after | 0.5 d |
| R4 | Division/modulo by non-constant; forbid string building under `--os=solana` | combat and emission divide by runtime values | after | 1–2 d |
| R13 | Refuse `String(uint64)`, `process.exit()` at compile time on Solana | turn on-chain aborts into build errors | after | 0.5 d |
| R11 | Verify integer overflow behavior; `checked_*` ops if it wraps | balances, hearts, counters (BRIEF §5.7) | after | 1 d |
| R1 | Heap arena at `0x300000000` | only if the program needs dynamic memory; the Pinocchio-shaped design aims to need none | only if needed | 2 d |

Order that exposes risk fastest: **R2 + R12 → R3 → R6**.

---

## 4. MagicBlock integration surface — Documented

There is no MagicBlock SDK for MetaScript. Everything below is instruction layouts and account lists, to be reproduced from MagicBlock's **native Rust** (non-Anchor) example and the SDK source. Program ids and queue addresses must be copied from the SDK constants, not from prose.

| Piece | Where it runs | Program side | Source of truth |
|---|---|---|---|
| **Delegate** | L1 | CPI to the delegation program (`DELeGGvXpWV2fqJUhqcF5ZSYMS4JTLjteaAMARRSaeSh`) with the PDA signing by its seeds. Accounts: payer, system program, PDA, owner program, delegation buffer, delegation record, delegation metadata, delegation program. Config: `commit_frequency_ms`, validator. | native Rust example `process_delegate`, `delegate_account` in the SDK |
| **Commit** | ER | CPI to the magic program. Accounts: payer (signer), delegated accounts, magic program, magic context. | `commit_accounts` |
| **Commit and undelegate** | ER | same accounts, `commit_and_undelegate_accounts` | SDK |
| **Undelegate callback** | L1 | instruction with discriminator `[196, 28, 41, 206, 48, 37, 51, 167]`, args: PDA seeds. Accounts: delegated PDA, delegation buffer, payer, system program. Re-creates the PDA owned by our program from the buffer. Called by the delegation program, never by us. | `undelegate_account` |
| **VRF** | ER | request: CPI to the VRF program with a `caller_seed` and the callback instruction, against the **delegated (ephemeral) oracle queue**; callback: our instruction must require the `VRF_PROGRAM_IDENTITY` signer and match a stored pending request. Output is 32 bytes. | VRF technical details, best practices |
| **Crank** | ER | CPI to the magic program with `ScheduleTask { task_id, execution_interval_millis, iterations, instructions }` (bincode). Executions are signed by the ER validator and cost no transaction fee; `act` can require that signer. Accounts must be delegated. | crank implementation guide |

- Endpoints (devnet): Solana `https://api.devnet.solana.com` · ER `https://devnet.magicblock.app` · Magic Router `https://devnet-router.magicblock.app`.
- Fees (Documented): ER transactions 0 · session fee 0.0003 SOL on undelegation · commit fee 0.0001 SOL after the first · VRF inside ER free, on L1 0.0005–0.0008 SOL.
- Who pays a commit, measured 2026-09-28 on devnet with the payout probe (§7 item 11, pet `rJF6XuNVQYC2Bvwo3KMLHUBghvy4TTHZpxExum2a6QH`): the ER validator `MAS1Dt9…` signs every L1 transaction that writes the committed state and pays its fee, 14,600 lamports a commit and 24,200 for commit-and-undelegate; our program only asks for the commit inside the ER, fee 0. MagicBlock's fees are settled once, when the account leaves the ER, out of the delegation record and metadata rent that whoever delegated paid (2,118,360 lamports on devnet): three commits and the undelegation kept 500,000 (= 300,000 + 2 × 100,000; 450,000 to the validator's fee vault, 50,000 to the protocol's) and returned 1,618,360 to the game's payer. In magicblock-labs/delegation-program `fb6668c` (`process_delegation_cleanup`, `src/processor/fast/undelegate.rs`) the settlement is `min(300,000 + 100,000 × (commits − 1), deposit)`, no debt beyond the deposit. The ER caps the other side: without a delegated fee payer an account commits at most 10 times a delegation. Measured (`node tools/chain/payoutDevnet.mjs <program> commits 25`): commits 1–10 landed, the 11th failed with `0xA0000000` "sponsored commit limit exceeded … current commit nonce 10 reached the limit of 10", a commit-and-undelegate still ran, and the settlement kept 1,300,000 of the 2,118,360 deposit (300,000 + 10 × 100,000). MagicBlock's page "Fees, Commits, and Refunds" (docs.magicblock.gg, checked against source 2026-08-20) gives the same rules and the longer path: a delegated fee payer plus the validator's `magic_fee_vault` lifts the 10-commit stop, commits 1–25 carry no live fee, and from commit 26 each commit costs 100,000 lamports per committed account, taken at once from the fee payer, on top of the deposit settlement; the payer is topped up with `lamportsDelegatedTransferIx` (300,000 lamports a top-up). Either way an account kept on the ER costs about 0.0001 SOL a commit after its first few, so the commit cadence is a running cost. The fee-payer path and the mainnet build are not measured.
- Documented oracle queues (same on mainnet and devnet): base layer `Cuj97ggrhhidhbu39TijNVqE74xvKJ69gDervRUXAxGh`, ephemeral `5hBR571xnXppuCPveTrctfTU7tJLSN94nq7kv7FRK5Tc`. Verify against the SDK before use.

---

## 5. Probe plan

Run the steps in order; each has one pass criterion. Steps 1 and 2 can start in parallel. Compiler changes happen in a private worktree of the recompiler, never in the shared tree.

| # | Probe | Pass when | Proves |
|---|---|---|---|
| 1 | **Rust control**: deploy MagicBlock's native Rust counter (built `--arch v3`) to devnet; delegate → increment on ER → commit → commit and undelegate | counter value is back on L1 after the undelegate callback | wallet, endpoints, validator choice and our client flow work; later failures are ours |
| 2 | **MetaScript reads and writes an account** (R2) | a MetaScript program parses the input and writes 8 bytes into an account it owns, in LiteSVM, then on devnet | entrypoint parsing and zero-copy writes |
| 3 | **MetaScript signs as a PDA** (R3, R6) | `invoke_signed` creates a PDA through System `create_account` | the CPI ABI and PDA signing, **the decisive step** |
| 4 | **MetaScript delegates** (R6) | the MetaScript counter goes through the same cycle as step 1 | the whole ER lifecycle from MetaScript |
| 5 | **Real rules in the program** (R12) | `fight()` from `rules/` runs inside `act` on ER; CU recorded | rules link on chain; combat fits the compute budget |
| 6 | **VRF and crank** (R6) | a fight resolves from a VRF callback in ER; `act` runs from a crank on schedule | the brain-on-chain loop end to end |

## 6. Decision gate and fallback

If step 3 or 4 does not pass inside the agreed timebox, do not rewrite everything in Rust at once:

1. **Rust shell + MetaScript rules**: a Rust program (native, `--arch v3`) owns entrypoint, accounts, delegation, commit, VRF and crank; `rules/` is built to C by MetaScript and linked into it through FFI. The rules stay single-source and still compile to JS for the client and sim.
2. **Full Rust** only if linking the generated C into `cargo build-sbf` also fails.

## 7. Unknowns to measure on devnet

1. Compute budget per transaction inside the ER, and the CU of one `act` and one `fight`. Measured for the brain alone (2026-09-27): the ER honours a 1.4M `SetComputeUnitLimit`, inference is 590,655 CU, and the ER reads a non-delegated L1 account (`ON-CHAIN-AI.md` §6 package 6). A whole `act` runs in the ER (2026-09-27): 515,971 CU typical and 739,640 busiest with the pets and `GlobalConfig` delegated, equal to LiteSVM, same choices and bytes, committed back to L1 intact (`ON-CHAIN-AI.md` §6 package 6); since the optimisations of package 6 (program `CwPgPyEN5KCBjMHMaBjCjZ4Ur4GcTrBknXcBQJQNkQeJ`, rules of `32cb82d`, policy format 7) 419,064 typical and 561,100 busiest, again equal to LiteSVM. The tick at dawn is not measured. A fight costs 5.5–16.9k (item 3).
2. Crank scheduling from our program: interval accuracy and reliability with many pets. Measured for one account (2026-09-27, `tools/fightProbe.ms` + `tools/chain/fightDevnet.mjs`, program `3afnQ9cpoaDYbZnUnVE2etrtsvdyi6Tm95M9jCh9qcCc`): a `ScheduleTask` of 3 iterations at 1,000 ms ran 3 fights within 2.1 s; scheduling cost 2,295 CU. Many pets and long intervals, measured 2026-09-27 on devnet-as (magicblock-core 0.16.0) with `tools/chain/crankDevnet.mjs`, one task per arena as one per pet (`std/solana` `scheduleTask` carries one account, so a task per block of ten is not expressible):
   - 50 tasks of 10 iterations at 2,000 ms, scheduled five to a transaction in 349 ms: 500 of 500 executions, none failed; each task's first run lands in the slot of its schedule transaction or the next (0–10 ms); a task's runs are 2,014–2,034 ms apart (1–3 slots late each time, so the lag adds up over iterations); up to 25 runs share a 10 ms slot.
   - A crank run is a transaction signed by the validator identity `MAS1Dt9…`, fee 0: a `Magic` instruction, then the `Crank111…` builtin calling the scheduled instruction by CPI. The scheduling wallet's balance in the ER did not move.
   - Its budget is fixed at 400,000 CU: our program starts with 399,700. The act scheduled as a task (a `ScheduleTask` sent straight from the client is accepted, 150 CU) ran out at 399,700 CU in both scenarios (`CRANK=1 node tools/chain/actDevnet.mjs`, "exceeded CUs meter"), where the same act sent with `SetComputeUnitLimit` costs 419,064 and 561,100. `ScheduleTask` has no compute-limit field.
   - Source of the ER on devnet (magicblock-validator `e66d914`, v0.16.0): a legacy run is `[noop, execute_task]` signed by the validator with no compute-limit instruction, and `execute_task` calls every task instruction by CPI under the authority's crank-signer PDA, so a task of a digest then the act still shares the 400k (8,124 + 391,576, measured). The `dev` branch (PR #1369, merged 2026-09-24, not released) forwards `ScheduleTask` to Hydra with `cu_limit: 0`, which is 400k again (next item, trigger without a limit).
   - Hydra in the ER (`eHyd5BU8QffvHi4GnXwxrK4WpS7pM2x9UGKHBWii7mf`), measured 2026-09-28 with `HYDRA=1 node tools/chain/actDevnet.mjs` on the busiest act: a wallet delegated to the ER as sponsor (System `assign` to the delegation program, then `Delegate` with empty seeds, as MagicBlock's cranker does for itself) creates a crank holding the act (14 accounts, `cu_limit` 1,400,000, tip 0) for 5,253 CU and 22,240 lamports of rent, (635 + 60) × 32. The act runs top level: a trigger without `SetComputeUnitLimit` has 400k and the act fails at 399,523; with it the act runs in 560,522 CU (559,895 of 1,399,373) and chooses what the sim chose. The ER build pays the cranker 0 (`consts::ephemeral::CRANKER_REWARD`), so the runs cost the sponsor and the cranker 0 lamports, and `Cancel` returned the rent in full.
   - Nobody runs Hydra cranks on devnet-as today: a due crank got 0 triggers in 60 s, and MagicBlock's `hydra-cranker` 0.2.0 (npm `@magicblock-labs/hydra-cranker-darwin-arm64`) found 0 cranks there at startup. Run by us with `--ephemeral`, it delegated its own wallet and fired all three runs of a 500-slot schedule at +27, +474 and +974 slots, each the whole busiest act. A wallet leaving the ER pays MagicBlock's undelegation fee, 300,000 lamports (sponsor and cranker, measured).
   - Five tasks at 1 h and 6 h intervals (`LONG`, three iterations each) all ran their first time in the slot of the schedule transaction; the three hourly tasks ran all three iterations at +3,600 s and +7,200 s, and the two 6 h tasks at +21,600 s and +43,200 s (block time, whole seconds), none failed (`node tools/chain/crankDevnet.mjs <program> observe`; `teardown` returned the 55 arenas and swept their wallets).
   - A day of the game through Hydra, 2026-09-28 00:12Z to 2026-09-29 00:22Z (`DAY=setup|watch|teardown node tools/chain/actDevnet.mjs`, program `DSWtbAe2hAM3kHznPgrS1HXsoMRRKAESJ8B7kiWvCj6r`, brain `p29s5`, our `hydra-cranker --ephemeral` on a Mac): ten pets and `GlobalConfig` delegated, one crank per pet holding the whole act (`cu_limit` 1,400,000), 5 runs every 2,160,000 ER slots (6 h at 10 ms), pets 6,000 slots apart in turn order. 50 of 50 acts ran, none failed: 17–36 slots after due (one at 85), 21,600 s between a pet's runs every time, 121,411–571,005 CU, fee 0, each choosing what the host chose (`tools/actHost.ms` `day.txt`), with 0 bytes differing from the host after every act (`out/actDayWatch.log` steps 0–29, `out/actDayWatch2.log` 29–49). Teardown: the ten `Cancel`s returned the cranks' 222,400 lamports of rent, the ER held the host's state after act 49 (0 bytes differing), the eleven written accounts were back on L1 3.8 s after the first return with the same digest and 0 bytes differing, and the sponsor wallet left the ER holding 19,700,000. Our cranker was restarted once (after run 3); its wallet's ER balance fell 305,000 lamports across that restart and is back on L1 with 19,390,000.
3. VRF in ER: latency, callback flow, fee confirmed at zero, how to delegate or select the ephemeral queue. Measured (2026-09-27, same probe): the request costs 14,483 CU on the ephemeral queue `5hBR571xnXppuCPveTrctfTU7tJLSN94nq7kv7FRK5Tc` and the callback lands 1.1 s later; the callback only accepts the VRF identity PDA scoped to our program as signer (`verifyVrfCallback`), and matching it to a stored pending request is the program's job. A fight settles in 5.5–16.9k CU in the ER; commit-and-undelegate costs 22.8k CU and the account is back on L1 46–59 s later. The fee is unmeasured.
4. Delegating `GlobalConfig`, the account every settlement touches. Measured with the act probe (2026-09-27): `GlobalConfig` delegated beside the ten pets, every `act` writes it in the ER and it commits back to L1 with the pets (item 9 for the lock).
5. An owner-signed SKR purchase on L1 while the `Pet` is delegated: whether the ER sees the L1 change or the pet must undelegate. Measured on a non-delegated account (2026-09-27, `tools/chain/policyDevnet.mjs` case C): the ER executes on an L1 rewrite from the next transaction, 0.27–0.28 s after L1 confirmed it, without undelegating. The ER cannot write that account, so an L1 purchase has to be a monotonic counter the delegated `Pet` records as consumed. Owner-signed instructions sent to the ER reach a delegated account directly (every ER transaction of these probes is wallet-signed). A wallet holding 0 lamports on L1 and in the ER signs and pays such a transaction: fee 0, the delegated pet written, the wallet still at 0 (2026-09-28, `node tools/chain/payoutDevnet.mjs <payout program> emptyWallet`), so an owner needs no SOL to play inside the ER. A Token-2022 transfer itself is unmeasured.
6. A fight between pets in two different blocks, all accounts delegated. Measured 2026-09-27 (`tools/chain/crossDevnet.mjs` on the fight probe `3afnQ9cpoaDYbZnUnVE2etrtsvdyi6Tm95M9jCh9qcCc`, two arenas of two wallets standing for two blocks' accounts; devnet ERs on magicblock-core 0.16.0, git `e66d914`), twice with the same results:
   - In one ER a block is only a set of accounts: one transaction writing both arenas lands in 79–107 ms (36,836 CU for two fights), and through the Magic Router in 309–369 ms.
   - Across two ERs (A delegated to devnet-as, B to devnet-eu), one transaction writing both fails in either ER with `InvalidWritableAccount` ("Account … was illegally used as writable", nothing written), and the router refuses it at send (`-32604`, "transaction contains accounts that were delegated to different ER nodes").
   - An ER reads an account delegated to another ER without an error but sees its last L1 commit: B at 8 fights in the EU ER read 7 in the Asia ER, through `getAccountInfo` and read-only inside a transaction alike.
   - Moving an account to another ER (commit-and-undelegate, back on L1 in 1.1–1.5 s; delegate, visible in the other ER 0.3–0.8 s later) took 2.5–5.6 s. Commit-and-undelegate returned accounts to L1 in 1.1–2.3 s in these runs, where the runs of items 1–3 took 33–174 s.
   - `BRIEF.md` D8 keeps fights inside a block; what crosses blocks is `GlobalConfig`, written by every `act` (item 4). On one ER nothing more is needed. On several ERs no transaction can span them: `GlobalConfig` would need one accumulator per ER, and a pet sees another ER's pets only as of their last commit.
   - `std/solana/vrf` `requestRandomness` names one callback account; a `consume_fight` that writes both pets, their block and `GlobalConfig` needs a list (std/solana, not built).
7. The ER validator's security model. Read 2026-09-28 in magicblock-labs/delegation-program `fb6668c`: L1 takes whatever state the delegation's validator signs. `process_commit_state_internal` (`src/processor/fast/commit_state.rs`) checks only that the signer is the delegation record's `authority`, that commits come in nonce order and that lamports are collateralised; `process_finalize` (`finalize.rs`) says "currently state is valid if committed from a whitelisted validator". Nothing re-executes the transactions and there is no fraud proof, so the validator we delegate to can write any bytes into our delegated accounts. For a stalled validator the source has an escape hatch: `RequestUndelegation`, then `UndelegateWithRollbackAfterTimeout` after 9,000 slots (`DEFAULT_UNDELEGATION_REQUEST_TIMEOUT_SLOTS`), which returns the last L1 state and loses newer ER state. It merged on 2026-07-08 (`ccd8e56`, PR #183), after the devnet and mainnet builds of item 14, and is not measured there. Misordering is not read.
8. SGT admission (§3.2 of `BRIEF.md`). Measured 2026-09-27 (`tools/claimProbe.ms`): the check reads the Token-2022 mint's `GroupMemberPointer` and `TokenGroupMember` TLV entries and the holder's token account, no CPI. On the bytes of a real mainnet SGT (`2qmVbZc7fGpyqL1cpy5VjM3NPBJ1sDJxYY24okXz8eXb`, member 121005) in LiteSVM (`tools/chain/claimLiteSvm.mjs`) the holder passes in 1,799 CU and a stranger's token account, an empty one, another group, a forged mint authority and the legacy token program are each refused with their own error. On devnet (`tools/chain/claimDevnet.mjs`, program `2U2yb7mmoWQrwjDxGMnDkMKDfVqM4S1LG7hZMGuQtC2t`) a member of a Token-2022 group made with `spl-token` (group `6jXijzhCm1Njikk3vLTmrw1mjPzWrwKherDYvELgwCpR`, a DevAdmission stand-in) passes in 1,427 CU and the same member claimed against the SGT group is refused. Read from the real SGT: supply 1, decimals 0, the holder's token account is frozen, and the issuer `GT2zuHVaZQYZSyQMgJPLzvkmyztfyXg2NJunqFp4p3A4` is mint authority, freeze authority and permanent delegate, so the issuer can move or burn a player's SGT.
8. Program size and deploy rent once CPI helpers and `rules/` are linked (expected tens of KB; the log-only program is 1.8 KB).
9. `act` throughput: how many pets the ER can run per crank interval, from hundreds (a wild-pet army filling the 500-slot floor) to thousands. Measured on the public devnet ER (`devnet-as`, 2026-09-27, `BURST=160 node tools/chain/actDevnet.mjs`): 160 acts of 418,009 CU sent at once, in four variants (the act's accounts writable or read-only, one fee payer or one per transaction), all landed with no failure within 0.27–0.88 s of the first send and 0.1–0.23 s of the last; the variant where every act writes `GlobalConfig` and the same ten pets under one fee payer took 0.23 s after its last send. The send rate of the harness bounds the result: at least ~700 conflicting acts a second. One act runs in well under a millisecond in the ER; the 90–150 ms of a single act is the round trip. The write lock on `GlobalConfig` does not limit throughput at this scale; a validator under other load, and more than one ER, are not measured.
10. Creating accounts inside the ER (item accounts for unequipped and listed items), or whether they must be created on L1 and delegated.
11. Paying an owner from the ER. Measured 2026-09-28 on devnet (`tools/payoutProbe.ms`, program `A3fNQk3emWU4deFW1gpKCxN9reNBdktDQdBzcXt34BWf`, `node tools/chain/payoutDevnet.mjs <program>`; L1 cases first in LiteSVM with `tools/chain/payoutLiteSvm.mjs`): the pet stays delegated and holds a monotonic `earned` counter that only ER instructions raise (393 CU, fee 0, signed by the game's payer, no owner or session key); `commit` without undelegating (22,793 CU, fee 0) shows it on L1 1.3 s later; the owner signs `claim` on L1 (10–12k CU, 5,000 lamports), which reads the delegated pet's committed bytes (the account is owned by the delegation program there, so the program checks its address against the pet PDA), pays `earned − paid` capped per day by an L1 ledger PDA the ER never touches, and mints to the owner's token account by the program's PDA signature. A claim before the commit paid 0, a second claim 0, 20,000,000 more paid 7,000,000 under a 10,000,000 daily cap, and the pet kept earning in the ER after each claim. LiteSVM also refused a stranger's claim, a swapped pet or ledger, a look-alike pet owned by another program, and a direct `MintTo` by anyone but the program. The owner's SOL paid its token account (1,488,440 lamports of rent) and 5,000 a claim; the pet's lamports did not move. A PDA has no private key, so a pet can never pay a fee itself.
12. Program upgrades: how fast the ER picks up new bytecode deployed on L1, and whether upgrading while accounts are delegated is safe when a layout `version` changes.
13. The client's read of ER state, and one account layout on SBF, arm64 and JS. Measured 2026-09-27 with the act probe (`tools/actHost.ms` writes the ten pets and `GlobalConfig` as the native arm64 build holds them after the act; `actLiteSvm.mjs` and `actDevnet.mjs` compare the accounts the program wrote against them, byte for byte, 1,984 bytes per scenario):
   - SBF writes the host's bytes: 0 bytes differ in LiteSVM and in the ER, for the typical and the busiest act, every field and padding byte of `Pet` (192 bytes) and `GlobalConfig` (64) included.
   - Every read path a client has returns them: `getMultipleAccounts` on the ER, the same through the Magic Router while the accounts are delegated, an ER websocket `accountSubscribe` on the actor's pet (notified 105–106 ms after the send, where polling saw the confirmation at 172–218 ms), and L1 after commit-and-undelegate (back 4.6–5.0 s after the first return): 0 bytes differ on each.
   - `sizeof` gives the same sizes on native arm64 and under `--target=js` (`Pet` 192, `GlobalConfig` 64, `FightRecord` 120), and the SBF probe accepts 192-byte pet accounts through its `sizeof` check. Reading account bytes into a struct under `--target=js` was not tried: the JS build has no byte view of a struct here, so a JS client needs a decoder derived from the struct (std/solana, not built).
14. Solana testnet as a stand-in for mainnet. Measured 2026-09-28: MagicBlock runs an unlisted testnet ER (`https://testnet.magicblock.app`, validator `MTAWuRvVFSB36x6rpHQwZMeM6dBSDupbiw6nBQ65mLR`) on the validator commit (`e66d914`) and Hydra build of devnet and mainnet, and the three L1s answer solana-core 4.3.0 with one feature set. The delegation program is a different build on each L1: testnet's ELF is 162 KB, deployed at slot 279,900,796 (about August 2024 at 0.4 s a slot); devnet's 459 KB at slot 458,511,904 (about February 2026); mainnet's 458 KB at slot 416,508,270 (about April 2026). The testnet build panics ("memory allocation failed, out of memory", 1.2–1.3k CU) on the delegate instruction our program sends by CPI and on the one MagicBlock's `hydra-cranker` sends for its wallet, so nothing can be delegated there. The act probe deployed on testnet (`7j7YrRQiLwYo6bw3EbTqv2Y2v29BLDaL9xTd5yDmpYmw`, 0.99 testnet SOL) runs on L1 only. The VRF program is absent from testnet L1.
15. The $HBRN mint (`BRIEF.md` D38, §10 Q15). Measured with item 11's probe on SPL Token (`Tokenkeg…`): the program creates the mint at its own PDA with the PDA as mint authority and no freeze authority (6,715 CU), and it is the only minter (LiteSVM: a direct `MintTo` fails with `OwnerMismatch`). Token-2022 has the same `InitializeMint2` and `MintTo` layouts and is not measured. Moving tokens inside the ER, delegating a token account, is not measured and is not needed by the claim path.
16. One `Block` account holding the ten pets and the rest of a block. Measured 2026-09-30 (`tools/blockProbe.ms`, installed msc `013853dd`; `node tools/chain/blockLiteSvm.mjs out/blockProbe.so <policy>`, then `node tools/chain/blockDevnet.mjs <program> <policy>` on devnet program `9reGKuAgiuTjXLsK9ZTGhHBb2eMd6Q1eBQw1jHaPtyrG`, brain `p29s5`, log `out/blockDevnet.log`). The probe's `Block` is a proposal to measure, not the frozen layout: an 8-byte head (kind, version, living count, fight head, id), `Pet[10]` 1,920, ten identities (admission mint, owner, persona, soft signals) 720, ten grace entries 400, the 32-record fight ring 3,840, one market listing per slot 400, 45 relationship bytes; 7,336 bytes, rent-exempt 0.0379 SOL on devnet and mainnet (LiteSVM's default rent says 0.0519). The ring, graces, listings and relationships hold filler the act does not read; the act's market view and persona still come from the context fixture.
   - The act runs on the pets in place in the account: 413,983 CU typical and 553,889 busiest on LiteSVM, against 416,320 / 556,226 for the same act on ten pet accounts built by the same compiler; the ER ran the busiest in 553,889 CU, fee 0, same choice. 0 of 7,336 Block bytes and 0 of 64 `GlobalConfig` bytes differ from the native host's, read from the ER and through the router.
   - Delegating the Block cost 28,526 CU on L1; the ER served it 355 ms later. `commit` without undelegating (22,814 CU, fee 0) put all 7,336 bytes on L1 2.6 s after the send, 0 differing; commit-and-undelegate of Block and `GlobalConfig` had both back on L1 in 3.5 s, 0 differing, rent untouched. Writing the Block from L1 took nine 900-byte transactions.
   - Claim from a slot: the owner signs on L1, the program reads the delegated Block's committed bytes, checks the slot's identity owner and its `paid` ledger PDA, and mints `giftOwed − paid` (item 11's cap). Devnet: 3,000,000 gifted in the ER, committed, claimed in 10,326 CU and 5,000 lamports, a second claim paid 0. LiteSVM also refused a stranger, the neighbour slot the owner does not own, the neighbour's ledger, another account passed as the Block, and a Block owned by another program.
17. Re-sorting blocks by strength (`BRIEF.md` D39), measured 2026-09-30 (`tools/resortProbe.ms`, `node tools/chain/resortLiteSvm.mjs out/resortProbe.so 200,1000,10000 combat`). Three steps on the delegated Blocks: `snapshot` writes each pet's strength and admission mint into a `Ladder` account (11.7k CU a block), a merge sort in place in bounded transactions, then `swap`s that the program checks against the Ladder (the pet moved into position q must hold the mint ranked q; a placed position cannot be moved again) and that rewrite the two `["pet", mint]` indexes; `finish` fails until every position is placed. LiteSVM, every slot ends on its rank's pet and every index points at it:

   | Pets | Transactions | CU | Swaps | `Ladder`, rent once |
   |---|---|---|---|---|
   | 200 | 33 | 3.7M | 191 | 19,257 B, 0.098 SOL |
   | 1,000 | 154 | 19.8M | 991 | 96,157 B, 0.49 SOL |
   | 10,000 | 1,474 | 209M | 9,990 | 961,282 B, 4.88 SOL |

   Swaps are 16–19k CU each and fill a transaction at about eight (the account limit). ER fees and wall time are not measured: on devnet the 19,257-byte `Ladder` could not be delegated, the delegation program's CPI fails with `InvalidRealloc` "Account data size realloc limited to 10240 in inner instructions". **Every delegated account stays at or under 10,240 bytes**: the Block (7,336) fits, the `Ladder` has to be split into pages. The probe accounts were closed afterwards and their 1.01 SOL of rent came back.
18. Pets in their own accounts, the Block as a lookup of who lives with whom (user, 2026-10-01). Measured 2026-10-01 (`tools/lookupProbe.ms`; `node tools/chain/lookupLiteSvm.mjs out/lookupProbe.so <policy> 1000,10000`; devnet `STAGE=all node tools/chain/lookupDevnet.mjs <program> <policy>`, program `9gvf6o8cmaw5UpFbC885a36DsuWbS8v3Sdo3LF3ksoCk`, log `out/lookupDevnet.log`). A pet is a 272-byte `["pet", mint]` account (identity 72 + `Pet` 192, 0.0020 SOL); a block is a member page (48 + 32 per member) plus its fight ring, listings and relationships. A pet that a re-sort moved is placed (`movedTo`, grudges dropped) the first time the program loads it, so a re-sort writes no pet.
   - Block of 10, the act reading the ten pet accounts the page lists: 424,576 CU typical and 564,482 busiest on LiteSVM, the devnet ER the same 424,576 in 135 ms, fee 0, same choice, 0 of 1,920 pet bytes and 0 of 64 `GlobalConfig` bytes differing from the host's; 15 accounts.
   - A transaction carries at most 64 accounts, with or without an address lookup table (`@solana/kit` refuses to build more; without a table 32 fit in 1,232 bytes). A block of 100 or 200 cannot hand every neighbour's account to one act.
   - Neighbours copied into mirror pages of the block (50 `Pet` in a 9,616-byte account): scoring 9 neighbours costs 579k CU busiest whatever the block size (7, 8, 10 accounts for 10, 100, 200); scoring all 99 costs 2,845,272 CU and all 198 5,137,699, over the 1.4M a transaction may use. The slope, 226k CU per nine more neighbours, leaves room for about 36 neighbours scored in one act. Only the actor's own pet and mirror entry are written.
   - Re-sort without a `Ladder`: the order is proposed off chain and each block is checked on chain as it is filled (a pet counted once in a bitmap by its ordinal, the block's weakest at least as strong as the previous block's strongest, `finish` refused until every pet is placed). LiteSVM: 1,000 pets 102 / 42 / 42 transactions for blocks of 10 / 100 / 200 (1.20M / 0.84M / 0.84M CU); 10,000 pets 1,002 / 402 / 402 transactions (12.2M / 8.5M / 8.3M CU), 25 pets a transaction, 57 through a lookup table. Refused: a stronger block after a weaker one (507), a pet placed twice (506), an early `finish` (508). Devnet ER, 200 pets in blocks of 10 sent one after another: 22 transactions, 276,636 CU, fees 0, 4.2 s, every member where the proposal put it. Rent: 0.0045 SOL a pet with its share of a block of 10, 0.0039 / 0.0040 for 100 / 200.
   - Not measured: re-creating the Hydra cranks after a re-sort (an act's account list changes when its block does; per crank 1,480 CU to cancel and 5,253–14,253 to create, fee 0, item 2), an ER lookup table, sending a re-sort's blocks in parallel. The 225 probe accounts were closed afterwards; the run cost 0.0686 SOL of L1 fees.

## 8. Toolchain on the dev machine — Measured

- `solana-cli` 4.2.2 (Agave), `solana-test-validator`, `cargo-build-sbf`, `sbpf-linker`.
- LiteSVM JS harness from the meetup demo (`litesvm` 1.4, `@solana/kit` 8.2), to be extended for multi-account scenarios (ROADMAP R7).
