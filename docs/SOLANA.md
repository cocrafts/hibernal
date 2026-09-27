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
| Policy weights | program-derived, `["policy"]` | L1, read by `act`; updated through timelocked config |

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
| module `const` of struct, `T[N]` or string type | compile error `FREESTANDING E02` at the binding; `.rodata` for aggregates waits on SOLANA-BUGS #8 |
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
| **R12** | Module constants must not become discarded `.data` globals: fold scalar constants, emit `static const` into `.rodata` | `rules/` shares constants across files. Scalars fold since `8be46044..e5f0ec68` (installed `cce059c8`): `rulesProbe` and `fightProbe` link. Aggregates in `.rodata` open behind SOLANA-BUGS #8 | **yes, first** | 0.5–1 d |
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
2. Crank scheduling from our program: interval accuracy and reliability with many pets. Measured for one account (2026-09-27, `tools/fightProbe.ms` + `tools/chain/fightDevnet.mjs`, program `3afnQ9cpoaDYbZnUnVE2etrtsvdyi6Tm95M9jCh9qcCc`): a `ScheduleTask` of 3 iterations at 1,000 ms ran 3 fights within 2.1 s; scheduling cost 2,295 CU. Many pets and hour-long intervals are unmeasured.
3. VRF in ER: latency, callback flow, fee confirmed at zero, how to delegate or select the ephemeral queue. Measured (2026-09-27, same probe): the request costs 14,483 CU on the ephemeral queue `5hBR571xnXppuCPveTrctfTU7tJLSN94nq7kv7FRK5Tc` and the callback lands 1.1 s later; the callback only accepts the VRF identity PDA scoped to our program as signer (`verifyVrfCallback`), and matching it to a stored pending request is the program's job. A fight settles in 5.5–16.9k CU in the ER; commit-and-undelegate costs 22.8k CU and the account is back on L1 46–59 s later. The fee is unmeasured.
4. Delegating `GlobalConfig`, the account every settlement touches. Measured with the act probe (2026-09-27): `GlobalConfig` delegated beside the ten pets, every `act` writes it in the ER and it commits back to L1 with the pets (item 9 for the lock).
5. An owner-signed SKR purchase on L1 while the `Pet` is delegated: whether the ER sees the L1 change or the pet must undelegate. Measured on a non-delegated account (2026-09-27, `tools/chain/policyDevnet.mjs` case C): the ER executes on an L1 rewrite from the next transaction, 0.27–0.28 s after L1 confirmed it, without undelegating. The ER cannot write that account, so an L1 purchase has to be a monotonic counter the delegated `Pet` records as consumed. Owner-signed instructions sent to the ER reach a delegated account directly (every ER transaction of these probes is wallet-signed). A Token-2022 transfer itself is unmeasured.
6. A fight between pets in two different blocks, all accounts delegated. Measured 2026-09-27 (`tools/chain/crossDevnet.mjs` on the fight probe `3afnQ9cpoaDYbZnUnVE2etrtsvdyi6Tm95M9jCh9qcCc`, two arenas of two wallets standing for two blocks' accounts; devnet ERs on magicblock-core 0.16.0, git `e66d914`), twice with the same results:
   - In one ER a block is only a set of accounts: one transaction writing both arenas lands in 79–107 ms (36,836 CU for two fights), and through the Magic Router in 309–369 ms.
   - Across two ERs (A delegated to devnet-as, B to devnet-eu), one transaction writing both fails in either ER with `InvalidWritableAccount` ("Account … was illegally used as writable", nothing written), and the router refuses it at send (`-32604`, "transaction contains accounts that were delegated to different ER nodes").
   - An ER reads an account delegated to another ER without an error but sees its last L1 commit: B at 8 fights in the EU ER read 7 in the Asia ER, through `getAccountInfo` and read-only inside a transaction alike.
   - Moving an account to another ER (commit-and-undelegate, back on L1 in 1.1–1.5 s; delegate, visible in the other ER 0.3–0.8 s later) took 2.5–5.6 s. Commit-and-undelegate returned accounts to L1 in 1.1–2.3 s in these runs, where the runs of items 1–3 took 33–174 s.
   - `BRIEF.md` D8 keeps fights inside a block; what crosses blocks is `GlobalConfig`, written by every `act` (item 4). On one ER nothing more is needed. On several ERs no transaction can span them: `GlobalConfig` would need one accumulator per ER, and a pet sees another ER's pets only as of their last commit.
   - `std/solana/vrf` `requestRandomness` names one callback account; a `consume_fight` that writes both pets, their block and `GlobalConfig` needs a list (std/solana, not built).
7. The ER validator's security model: what happens if it stalls or misorders before a commit.
8. SGT admission (§3.2 of `BRIEF.md`). Measured 2026-09-27 (`tools/claimProbe.ms`): the check reads the Token-2022 mint's `GroupMemberPointer` and `TokenGroupMember` TLV entries and the holder's token account, no CPI. On the bytes of a real mainnet SGT (`2qmVbZc7fGpyqL1cpy5VjM3NPBJ1sDJxYY24okXz8eXb`, member 121005) in LiteSVM (`tools/chain/claimLiteSvm.mjs`) the holder passes in 1,799 CU and a stranger's token account, an empty one, another group, a forged mint authority and the legacy token program are each refused with their own error. On devnet (`tools/chain/claimDevnet.mjs`, program `2U2yb7mmoWQrwjDxGMnDkMKDfVqM4S1LG7hZMGuQtC2t`) a member of a Token-2022 group made with `spl-token` (group `6jXijzhCm1Njikk3vLTmrw1mjPzWrwKherDYvELgwCpR`, a DevAdmission stand-in) passes in 1,427 CU and the same member claimed against the SGT group is refused. Read from the real SGT: supply 1, decimals 0, the holder's token account is frozen, and the issuer `GT2zuHVaZQYZSyQMgJPLzvkmyztfyXg2NJunqFp4p3A4` is mint authority, freeze authority and permanent delegate, so the issuer can move or burn a player's SGT.
8. Program size and deploy rent once CPI helpers and `rules/` are linked (expected tens of KB; the log-only program is 1.8 KB).
9. `act` throughput: how many pets the ER can run per crank interval, from hundreds (a wild-pet army filling the 500-slot floor) to thousands. Measured on the public devnet ER (`devnet-as`, 2026-09-27, `BURST=160 node tools/chain/actDevnet.mjs`): 160 acts of 418,009 CU sent at once, in four variants (the act's accounts writable or read-only, one fee payer or one per transaction), all landed with no failure within 0.27–0.88 s of the first send and 0.1–0.23 s of the last; the variant where every act writes `GlobalConfig` and the same ten pets under one fee payer took 0.23 s after its last send. The send rate of the harness bounds the result: at least ~700 conflicting acts a second. One act runs in well under a millisecond in the ER; the 90–150 ms of a single act is the round trip. The write lock on `GlobalConfig` does not limit throughput at this scale; a validator under other load, and more than one ER, are not measured.
10. Creating accounts inside the ER (item accounts for unequipped and listed items), or whether they must be created on L1 and delegated.
11. Paying an owner from the ER: a token transfer to a wallet on L1 while the pet is delegated (gifts), queued to the next commit or requiring undelegation.
12. Program upgrades: how fast the ER picks up new bytecode deployed on L1, and whether upgrading while accounts are delegated is safe when a layout `version` changes.
13. The client's read of ER state, and one account layout on SBF, arm64 and JS. Measured 2026-09-27 with the act probe (`tools/actHost.ms` writes the ten pets and `GlobalConfig` as the native arm64 build holds them after the act; `actLiteSvm.mjs` and `actDevnet.mjs` compare the accounts the program wrote against them, byte for byte, 1,984 bytes per scenario):
   - SBF writes the host's bytes: 0 bytes differ in LiteSVM and in the ER, for the typical and the busiest act, every field and padding byte of `Pet` (192 bytes) and `GlobalConfig` (64) included.
   - Every read path a client has returns them: `getMultipleAccounts` on the ER, the same through the Magic Router while the accounts are delegated, an ER websocket `accountSubscribe` on the actor's pet (notified 105–106 ms after the send, where polling saw the confirmation at 172–218 ms), and L1 after commit-and-undelegate (back 4.6–5.0 s after the first return): 0 bytes differ on each.
   - `sizeof` gives the same sizes on native arm64 and under `--target=js` (`Pet` 192, `GlobalConfig` 64, `FightRecord` 120), and the SBF probe accepts 192-byte pet accounts through its `sizeof` check. Reading account bytes into a struct under `--target=js` was not tried: the JS build has no byte view of a struct here, so a JS client needs a decoder derived from the struct (std/solana, not built).

## 8. Toolchain on the dev machine — Measured

- `solana-cli` 4.2.2 (Agave), `solana-test-validator`, `cargo-build-sbf`, `sbpf-linker`.
- LiteSVM JS harness from the meetup demo (`litesvm` 1.4, `@solana/kit` 8.2), to be extended for multi-account scenarios (ROADMAP R7).
