# Upstream integration audit

## Measurement — 2026-10-07

Application: `fc8f8f5`, tree `cd0c708d59589141ae2491d2423b19b65f40048a`.
Port: clean `b50e0b5`, tree `f1a2a8f16aeb4f9368ad9d251ecc21c931c5a8bc`, at
`/Users/le/metacraft/hibernal-wt-std-port`. HUD's dirty worktree was read only;
its committed tree was `9bdf70e27fb9829ba971d76d4c7c7f3e203647aa`, not a snapshot
of its uncommitted changes. Existing dirty operations/AI/ER notes were not changed.

Installed `msc --version`: v0.3.2. `~/.metascript/BUILD`: binary and support both
`8506eaf03`. Compiler main was `097316d5f`: installed does not mean latest main.
The release criterion is latest **gated and synced**, not an unverified branch HEAD.

Commands and logs in `/tmp/hibernalStdGate8506/`:

- `msc build /tmp/msRepro/programSystemTwoModules/main.ms --os=solana --output=/tmp/hibernalStdGate8506/repro.so`
  exited 1: second module's `program<System>` reaches C codegen with unlowered `try`.
- In the port worktree, `msc build program/main.ms --os=solana --output=/tmp/hibernalStdGate8506/hibernal.so`
  exited 1 with the same error in admission, shop, resort and payout. No usable
  upstream program artifact, CU/size verdict or full host-suite verdict follows.
- `msc run /tmp/hibernalStdGate8506/arithmeticParity.ms` and the JS build plus Node
  both exited 0, printing `arithmetic helper parity pairs 209`. The probe compared
  the application's four helpers with installed `std/solana/arithmetic`, including
  int64 minimum divided by 2 and its remainder by 3. This proves helper parity on
  C/JS, **not** operator visibility, chain cost or full-rule equivalence after migration.
  The first probe used `assert` outside a test and was refused; corrected to explicit
  nonzero exits before obtaining these results.
- `msc build /tmp/hibernalStdGate8506/arithmeticSbf.ms --os=solana --output=/tmp/hibernalStdGate8506/arithmeticSbf.so`
  exited 0 (8 modules), using std helpers on dynamic instruction operands. Build-only:
  the probe was not run on LiteSVM and gives no CU verdict.

The compiler blocker remains
`~/metascript/.inbox/compiler/2026-10-06-inline-generic-try-unlowered-in-second-module.md`.
This run appended its evidence. `pi-44846` explicitly does not own that transform;
no fixing owner is confirmed. `omp-33975` and HUD `omp-26989` message delivery failed
with ENOENT; neither is treated as notified.

Std owner `pi-42346` confirmed by message: six local std commits ending at
`a8c13b710` are not landed/gated/synced by that arc; installed `accountCodec.ms`
is absent. Its checked codec candidate is blocked on imported annotation and
transitive JS sized-local issues. RPC/transaction/MWA client is not delivered.
This audit is not a green std gate and does not authorize bypassing its loss guard.

Later on 2026-10-07, the std owner reported its separately confirmed scope: on-chain
SDK, portable codecs and Anchor-v2 reference examples; RPC/transaction/MWA and
full game/device operations are outside that iteration. Hydra, PDA-paid commit
and scratch allocator are not silently accepted into it. These requests remain
unaccepted/deferred dependencies of Hibernal's full-flow goal, not a promise from
that lane. Its permission for measured SDK-side workaround debt does not authorize
application substitutes here.

## Integration verdicts

These are migration decisions and blockers, not another definition of the layouts.
Shared definitions remain in `program/layout.ms` and `rules/`.

| Boundary / sites | Verdict and closure evidence required |
|---|---|
| Active program accounts, instruction dispatch/args, errors, PDA proofs, token/VRF/delegation CPIs: `program/main.ms`, `admin.ms`, `admission.ms`, `day.ms`, `shop.ms`, `resort.ms`, `layout.ms` | Use the existing upstream port, not another adapter. Type-check alone is insufficient: blocked by the compiler card above; require host and LiteSVM tests with actual upstream consumers. |
| Private compiler and outdated macro imports: `WORKAROUND.md`, `program/` | Retire only after upstream gate succeeds. No private build counts toward the new flow. Apply the remove rows in inbox note `2026-10-06-compiler-synced-31c88d4e8.md`; do not delete the private installation without permission. |
| Hydra wire/account handling: `program/hydra.ms` `createCrank`, `cancelCrank`, `spentCrankOf`; `tools/chain/hydra.mjs`; `gameCranker.mjs` `scheduledFrom`; `ops.mjs` exhausted-crank reads; `tools/relayProbe.ms` | Std-owned protocol surface missing, existing asks row 15. Includes trigger, sponsor delegation and checked schedule/account reads, not just Create/Cancel encoding. Blocked: request upstream API/tests; no new local byte helper. |
| PDA-paid commit: `program/payout.ms` `paidCommit`; `tools/wildProbe.ms` `magicCall` | Std-owned missing signer-seeds surface, asks row 12. Installed `magicblock.ms` `scheduleCommit` requires `payer.isSigner()` and has no signer parameter. `signed(...)` cannot repair a function without that parameter. Require signed commit/undelegate proof before replacing the wire code. |
| SessionTokenV2: `program/owner.ms` `sessionOf`; `tools/chain/hibernal.mjs` session methods; `sessionProbe.mjs` | Generic external-account verifier, PDA and session instruction codecs belong upstream; no installed session module. Game's engage count/round/owner policy remains application logic. Require authority/target/signer/expiry/PDA, revocation and malformed-account negative tests. |
| Chain scratch allocation: `program/day.ms` `loadedPets`, `deadWilds` | `msSolAlloc` runtime redeclaration remains a std/runtime gap, asks row 17. Installed `allocate(Account, space, ...)` is a System-account CPI, not scratch heap allocation. Do not substitute it. |
| Signed arithmetic: `rules/arithmetic.ms` and namespace imports throughout rules | Migrated to direct installed `std/solana/arithmetic` imports; application file now holds only regression tests, loaded under testBuild by `rules/index.ms`. See the migration gate below. Compiler card `2026-09-27-solana-signed-division-is-a-170-cu-libcall.md` still has an open runtime recommendation; this migration does not decide it. |
| Policy scalar readers: `rules/policy.ms` `signedByte`, `wordAt`, `engineVersionOf` | Portable allocation-free Span readers still need upstream closure (asks row 16). `littleEndian.ms` exports writers; host BorshReader owns `uint8[]`, not the required allocation-free view. Keep model-format validation and dense inference in rules; migrate only generic byte primitives. |
| Compiler buffers/type/equality scaffolding: `program/brain.ms` `buffersMatchRules`; `day.ms` `seededInstruction`; `rules/layout.ms` `fightOutcome`; `rules/actions.ms` split combat; sim equality imports | Sim equality imports removed after candidate and actual gates below. Other sites still require per-site probes. Existing sync notes say typed comptime, enum and generic deref fixes shipped; sized arrays were still blocked at that measurement. Do not infer their present behavior from a newer BUILD. Removing scaffolding must preserve digests, layout and SBF frame/CU. Split combat is not independently a safety failure. |
| Host staging/fixture codecs: `program/test/owner.ms`, `payout.ms`, `shop.ms`, `admission.ms`, `resort.ms`, `dayWorld.ms`; `tools/chain/*Fixture.mjs` | Shared checked encode/decode required for normal fixture construction and readback; codec not synced. Keep deliberate raw corrupt fixtures as adversarial inputs, not production decoders. Host emulator `std/solana/host` already owns execution; don't build a second emulator. |
| Application instruction/PDA/IDL-offset layer: `tools/chain/hibernal.mjs` `hibernal`, `fieldsOf`, `accountOffsets`, discriminator/scalar helpers; consumers `ops.mjs`, `behaviour.mjs`, `sentinel.mjs`, `hibernalDevnet.mjs`, `sessionProbe.mjs` | Std client/checked codecs missing, asks rows 1/9. IDL-derived offsets are still a second decoder, not the shared checked layout. Manual account lists/argument encoders must leave the active path. Preserve orchestration and clone-resign behavior above the upstream client. |
| RPC/transaction machinery: `hibernal.mjs` `sendOnce`, `players.mjs` batch submission, `behaviour.mjs` submit, `gameCranker.mjs` fire, `deploy.mjs`, `flowProbe.mjs` and chain harnesses | Uses installed `@solana/kit` rather than handwritten cryptography; still outside the requested std client contract. Blocked on upstream RPC/wire/signing adapter, including JS and native consumer support. Keep game batching, retry policy, status/alarms and recovery decisions; don't rewrite transaction construction locally. |
| SPL/system/loader admission codecs: `players.mjs` `admitInstructions`, `groupMaxSize`; `behaviour.mjs` token/ATA helpers; `deploy.mjs`; `hibernalDevnet.mjs` and legacy token fixtures | Require upstream client helpers for Token-2022 membership/TLV, ATA, funding and loader operations. App owns which owner/mint is provisioned and how many test tokens, not external wire formats. Official SDK/CLI is a verification control, not a newly invented std replacement. |
| Base58 duplicates: `hibernalDevnet.mjs` `decodeAddress`, `behaviour.mjs` `encoderBase58`, `ops.mjs` `base58Bytes` | Library-owned, not game logic. Existing kit codecs can serve as controls; final path must use upstream Pubkey/client. No handwritten encoder retained as fallback. |
| Older probes: ten `tools/{act,block,claim,fight,lookup,payout,policy,resort,counter,wild}Probe.ms`, their `*Devnet.mjs`/`*LiteSvm.mjs`, plus `relayProbe.ms` | Do not dismiss as dead: wild/relay may still be needed. Old account casts, dispatch/errors/PDA/token/commit/Hydra protocols inherit the migration/blocker rows above. Port retained probes; deletion requires the person's call. `dayLiteSvm.mjs` also duplicates discriminator/instruction/meta handling and belongs in client migration despite testing the current program. |
| Pure sim/training boundary: `sim/env/ffi.ms`, `tools/actHost.ms`, `policyHost.ms`, `actBench.ms`, `policyBench.ms`, `fightOracle.ms`, `oddsTableGen.ms`, `rulesProbe.ms`, `blockLayout.ms` | Keep C ABI buffers, brain/game fixtures and sim orchestration; they are not RPC account codecs. Any literal-sized brain buffers inherit the compiler row; a generic byte helper within a fixture inherits codec migration. |
| HUD app consumer in `hibernal-wt-hud`: `native/host/host.ms`, `hostLink.c/.h`, `android/.../WalletBridge.kt`, JNI bridge; `native/hud/signing.ms` | Read-only: remembered Pubkey uses std, wallet authorization uses official Android MWA library; platform/JNI/cache bridge is legitimate. No checked RPC account reader or transaction flow found in these paths. Timer-based signing is a UI stand-in, never device/chain proof. Codec/client delivery and fresh fixture remain prerequisites; HUD owns edits. |
| Game/platform code surrounding these sites | Keep rules/economy/persona, deterministic simulated-owner key derivation, pet/action selection, sort scheduling, cranker discovery/replay, storage alarms, shell lifecycle, wallpaper/renderer and JNI transport. These are not std/compiler implementations. Generated Codama conversion/publishing in `tools/codama/publish.mjs` is an existing external tool, not a handwritten account decoder. |

## Gates still open

The initial audit made no implementation changes; the independent arithmetic
migration below followed it. No commit, land, push, deploy, funding or world reset.
Wilds, 48-hour endurance, per-signature maintenance recovery, current
500-owner devnet and Seeker transactions are not proved by it. The existing watcher
ended at epoch 8 on the private-built world; it is not upstream endurance evidence.

All missing std surfaces are parked by the sites above against the existing asks
card `~/metascript/.inbox/compiler/2026-09-29-std-solana-asks-from-hibernal.md`;
its rows need owner acceptance and upstream delivery, not an app fallback. The
arithmetic migration can be gated independently while the program build waits.

## Arithmetic migration gate — 2026-10-07

Installed binary/support remained `8506eaf03`. Baseline rules/sim were frozen under
`/tmp/hibernalArithmeticMigration/baseline/` before editing. Application rules patch
SHA-256 (`git diff -- rules | shasum -a 256`):
`e57a2655cee011c585092de09b99dcd328213f18eac0dca1a5e42f2c9c4074d6` on the
application tree named above. No gameplay tuning or layout change.

`baselineGate.sh` and `migrationGate.sh` in `/tmp/hibernalArithmeticMigration/`
run the same commands against frozen and migrated sources respectively:
`msc test rules/index.ms`, `msc test sim/teacher.ms`, `msc test sim/env/ffi.ms`,
`msc run sim/curve.ms`, native determinism and JS build plus Node. All exit 0.
Rules **414 → 416**, teacher **434 → 436**, ffi **468 → 470** tests, zero failures;
the extra two are imported std arithmetic tests, with the application regression
retained. All eight digest lines are equal across baseline/migration and C/JS,
including engine `15072111084034916937`. All eleven combat-curve rows are identical;
there is no new BRIEF curve number to change.

Dynamic SBF controls in that directory were built with plain `msc build <entry>
--os=solana --output=<name>.so`. Run from `tools/chain`:
`node --input-type=module < /tmp/hibernalArithmeticMigration/operatorsLiteSvm.mjs`
and the same command with `fightLiteSvm.mjs`. Both exit 0.

- Operators: ten int64 cases and eight int32 cases, `/`, `%`, `/=`, `%=` per
  case, legacy vs std; every result equals JS BigInt truncating division/remainder.
  Valid signed/extreme inputs only, not zero divisors or MIN/-1. Int64 blocks:
  **597–1,187 → 557–573 CU**; int32 blocks **640–1,003 → 578–600 CU**. Each paired
  std case is cheaper, not just the aggregate range. Probes include read/log cost.
- Real `rules/fight.ms` consumer: nine dynamic seed/stat cases, legacy vs migrated
  rules. Outcome, rounds and both HP values equal in every pair; each std case
  cheaper. For seed 42, 80/80 might, 80 grit: **4,120 → 3,512 CU**. This is combat
  function proof, not a whole `act` CU measurement.

The operator harness first parsed the wrong log word; corrected to the last
`logU64` word. Its first int32 wire control also treated unsigned32 input as a
signed decode and panicked on the legacy program; both controls now read signed64
wire values and narrow in-range to int32. These were corrected test inputs/parsing,
not app or compiler workarounds. No full-program build, world, native Android or
Seeker transaction acceptance is implied. Upstream port remains separately blocked.

## Equality workaround removal — 2026-10-07

`2026-10-03-compiler-synced-59c3c6c4.md` identifies compiler pins corpus 663/664,
`bug626`/`bug627`, and names sim's Pantry imports to unpark. On installed `8506eaf03`,
a copied rules/sim candidate under `/tmp/hibernalEqualityRemoval/candidate/` without
the workaround imports passed `msc test <candidate>/sim/env/ffi.ms`: **470/470**.
The candidate retained `Gear` and `Item` where world tests actually use them and
`resaleValue` where batch uses it; it removed no game logic.

After applying the same import/comment removals at `sim/{world,teacher,env/batch}.ms`,
`msc test sim/teacher.ms`: **436/436**, `msc test sim/env/ffi.ms`: **470/470**.
Those suites already compare nested Pet values without requiring the nested types
to be imported at the consumer. Native and JS determinism exit 0; all eight digest
lines equal each other and the previous arithmetic gate. No new equality shim.
Logs and JS artifact are under `/tmp/hibernalEqualityRemoval/`. Combined rules/sim
patch SHA-256: `4dd97a006dc9a2aac2208e95a5f35cff1293d5208b0e1bded8bfcb560621fff5`.

HUD's current `pi-85461` acknowledged delivery: real discovery/Claim/live ER game
path is still absent, owner persistence/MWA authorization are tested, scene/diary
are previews. No funding/upgrade/Claim approval follows. SDK codec and transaction
surfaces, compatible deployment/admission/placement evidence are still prerequisites.

## Remaining boundary probes — 2026-10-07

Installed binary/support still `8506eaf03`. Probes/logs in
`/tmp/hibernalCompilerBoundaries/`:

- `msc run importedSize.ms` and JS build plus Node: **exit 1**, `imported size 0`
  for `int32[ECONOMY_INPUTS] = []` (expected 46). Recorded against existing compiler
  card `2026-09-26-sized-array-dimension-from-a-named-const-is-zero.md`.
- `literalSize.ms`: C **exit 0**, `literal size 4 total 7`; JS builds but Node
  **exits 1**, index 3 out of bounds, length 0. Recorded against existing compiler
  card `2026-09-29-js-sized-array-local-starts-empty.md`. No new shim or fallback;
  `program/brain.ms` literal sizes/guards cannot yet be removed safely.
- `neutralBoundaries.ms`: C/JS **exit 0**, Outcome width 1, byte/enum test records
  both size 8, typed/untyped Seeded discriminators both `17358739751253998038`.
- `msc build sbfBoundaries.ms --os=solana --output=sbfBoundaries.so` and, from
  `tools/chain`, `node --input-type=module < /tmp/hibernalCompilerBoundaries/sbfLiteSvm.mjs`:
  **exit 0**, same discriminator values checked against Node SHA-256, enum width 1,
  **464 CU**. This supports removing the typed-comptime/enum workaround only after
  actual consumer/layout/IDL gate; it is not that gate.

The std owner confirmed again: no separate accepted owner for deferred RPC/MWA,
Hydra, PDA-paid commit or scratch allocator was known. Its inline-try repair is
still scratch, not installed; it uncovered another inline/out-pointer variant.
Do not infer program acceptance from those peer-reported scratch tests. Merge-train
was asked for the current sized-array owner/queue, not to bypass a gate. Hibernal
has added evidence to the two existing compiler cards, not edited compiler/std.

Merge-train coordinator subsequently confirmed `wt/sized-arrays` landed on local
compiler main `097316d5f` after a green gate (2026-10-07 04:32). Current pins:
`src/test/lang/sizedArrayConstDimension.ms`, `sizedArrayLiteralCarriesSize.ms`.
Installed `8506eaf03` predates it. Sync is waiting for the person's word and the
coordinator's merge of origin/main; Hibernal has neither performed nor authorized
that sync. The coordinator reports a remaining module-level-let dimension refusal;
our function-local buffer probes must still be rerun on the actual synced build.

## Candidate SDK consumer acceptance — 2026-10-07

This is **not** a gated/synced release or a Hibernal land. Std owner asked for
candidate acceptance with `/Users/le/metascript/.wt/wt-std-solana/msc-stable`.
Compiler binary SHA-256 `669adbbdf20125bc677e7b60ef05bc38935232db381b20bb158d53d0e642ac14`;
SDK checkout HEAD `a8c13b710` plus dirty changes. `git diff HEAD -- std/solana`
SHA-256 `ef454abc4c0550b8abdc6e8dfdcc704027b979083afd3af81d324655ba5c8c1e`
was unchanged before/after these measurements. The installed BUILD remained `8506eaf03`.

Clean port `b50e0b5` was copied to `/tmp/hibernalSdkCandidate20261007a/`.
Only nine import targets changed from `std/solana/macro` to the public
`std/solana` barrel (seven handlers, main, admission test); no application substitute.
`publicBarrel.patch` SHA-256
`80144a260698a15fbd2359f9dfa8ae0f26f5b4e00d2e0aaa1df5dbfd2c74f406`.
At this measurement these import edits were temporary; the exact patch was later
applied to the port worktree as recorded below.

- Before import migration: candidate check failed with 22 cascading errors, including
  missing `accounts` export at its old owner. After it: `msc-stable check program/main.ms
  --os=solana` **0 type errors**, 98 modules; SBF build **exit 0**, 53 modules. The
  former unlowered `program<System>` error did not recur in this candidate variant.
- Host suites: admission **556**, day **592**, owner **559**, payout **559**, resort
  **526**, shop **559**, all zero failures. Increased counts include candidate std
  tests, not more game scenarios. The first day attempt omitted `tools/actBench.ms`;
  copied that dependency. The foreground retry timed out at 120 seconds with no
  SDK diagnostic; background retry finished green in **281,382 ms**, day tests
  **256,513 ms**. No host test was skipped or bypassed.
- Candidate IDL emits **27 instructions / 9 accounts**. Existing `idlCheck.mjs`
  checks **23 instruction discriminators/account metadata**, exit 0; argument
  ABI is not checked. The other four are built on chain. VRF/Hydra
  stubs build. Normal `dayFixture.ms` emitted a three-day fixture at
  `out/std/dayFixture.txt` in the application working directory; it was copied
  under the temporary consumer's `out/std/` for the isolated replay. This changed
  a generated test artifact, not program/world state or a release artifact.
- Candidate program ELF **360,448 bytes**, SHA-256
  `44f6b005c4642891ad0d7bca66b25cf23b705eb477e114c1cc632b55a7c554d5`, versus the
  recorded private gate's **471,496 bytes**. Different toolchains/SDKs, so this is
  an integration comparison, not an isolated compiler-performance attribution.
- `node tools/chain/dayLiteSvm.mjs <candidate ELF> <VRF stub> <Hydra stub> <fixture>`:
  **exit 0**, **88 instructions, 0 host/SBF byte differences**, 12 VRF requests and
  76 Hydra creates with PDA signatures. Worst sampled act-with-fight **806,886 CU**,
  versus recorded private gate **979,194 CU**. No wilds, re-sort or endurance claim.
- `msc-stable run /tmp/hibernalSdkCandidate20261007a/codecConsumer.ms`: **exit 0**.
  Candidate `std/solana/accountCodec` decode/encode uses the shared `PetAccount` from
  the port layout on an actual **304-byte** account taken from the SBF-compared
  fixture, exact roundtrip; rejects wrong owner, truncated length, invalid bool and
  discriminator. The bool corruption offset was derived by diffing two std-encoded
  values, not a field-numbered decoder. The initial test tried to mutate the
  read-only file span and was correctly refused; corrected by mutating an owned
  adversarial fixture copy, not a readonly cast.

Evidence/logs, binary, patch and codec probe remain in the temporary directory.
Std owner and new HUD peer received these actual results. HUD must still wait for
shipped/synced codec and RPC/transaction/MWA surfaces; this fixture is a local test
account, not fresh devnet/Seeker readiness. The candidate used b50's frozen rules,
not the later uncommitted arithmetic/equality changes: their combined upstream
acceptance gate remains to be run. No source edits in either program worktree,
compiler/std edits, install, commit, land, deploy, funding or world reset in this
candidate acceptance step.

## Combined candidate acceptance — 2026-10-07

`/tmp/hibernalSdkCombined20261007a/` combines the temporary port above with current
rules/sim: application HEAD `fc8f8f58`, tree `cd0c708d59589141ae2491d2423b19b65f40048a`,
`git diff -- rules sim` SHA-256
`4dd97a006dc9a2aac2208e95a5f35cff1293d5208b0e1bded8bfcb560621fff5`.
Port parent tree `f1a2a8f16aeb4f9368ad9d251ecc21c931c5a8bc` plus the same nine
public-barrel targets. Compiler binary hash unchanged from the preceding candidate;
296 candidate std/runtime files have equal before/after manifests, SHA-256
`df5dea9f51bdd80589faf78402be1f76a73487459ef68827e61c73681bc25969`.
This remains acceptance-only; installed upstream still `8506eaf03`.

`bash /tmp/hibernalSdkCombined20261007a/gateCombined.sh` records all **19 expected
commands exit 0** in `results.tsv`: rules **416**, teacher **436**, ffi **470**;
program admission **558**, owner **561**, payout **561**, resort **528**, shop
**561**, day **594**. Native/JS all eight digest lines match each other and the
prior arithmetic gate, engine **15072111084034916937**. All **11** curve rows
match the prior gate. Program check/build, IDL, both stubs and native fixture pass.

Same Node commands as above: IDL **23 discriminator/account-meta checks pass**
(argument ABI unverified by this gate), generated IDL object is
exactly equal to the b50 candidate. Day replay **88 instructions**, **zero
host/SBF byte differences**, 12 VRF/76 Hydra creates with PDA signing. The
three-day fixture hash is identical to b50:
`b087cbc727f5cf6b48facaff886ff33d52f7201853322a7bb5dd11152efec491`.
Worst sampled act-with-fight **772,573 CU** (b50 candidate **806,886**; recorded
private gate **979,194**); dawn **67,432**, dayEnd **66,472–67,538 CU**.

Combined ELF **367,920 bytes**, SHA-256
`713af8b20e992b0699fc041dd550d9374cdbeddf0ecf9e01d16a3aa4a3d100bc`.
That is **7,472 bytes larger** than b50 candidate, still **103,576 bytes smaller**
than the recorded private gate. `llvm-size` attributes the delta entirely to text
(**359,928 → 367,400**, data/bss both 0); these ELF files contain no function
symbols, so no per-function attribution is claimed. The code-size/CU comparison
covers the arithmetic migration bundle, not a single operator or isolated LLVM
change. No release/trade-off approval inferred from these candidate measurements.

The prior checked codec proof is reused: program layout and all relevant record
model sources are equal except arithmetic import targets, fixture bytes equal,
and compiler/support equal; the decoder/encoder neither consumes that arithmetic
nor a changed model. No named-dimension/JS-array workaround was removed, no ABI
or enum-storage change was included, and no actual program source, SDK install,
deployment or running world was changed in this combined probe.

## Public-barrel imports applied — 2026-10-07

Applied the exact nine-target patch to `hibernal-wt-std-port` at b50; worktree
program sources compare equal to the successful first candidate. Installed
`msc check program/main.ms --os=solana` passes **91 modules, zero type errors**.
Candidate build passes **53 modules**, owner suite **559/559**, and the actual
worktree ELF SHA-256 is exactly the first candidate's
`44f6b005c4642891ad0d7bca66b25cf23b705eb477e114c1cc632b55a7c554d5`.
Logs: `/tmp/hibernalSdkCombined20261007a/actualPort-{installed-check,candidate-build,owner}.log`.
The delta is **9 insertions / 9 deletions**, imports only; handlers, layouts and
rules unchanged. No commit/land/sync. This does not close the installed compiler
SBF blocker: typecheck is not codegen, and no matching gated/synced SDK release has
arrived. The earlier six host suites, IDL and SBF replay are carried forward because
source input equality and identical compiled ELF establish their unchanged scope.

## Scalar discriminator cleanup — 2026-10-07

Probe `/tmp/hibernalTypedDay20261007a/` started from the combined candidate.
Replaced three forwarding functions in `program/day.ms` and local Seeded word
packing with std `.word()`; strengthened the existing day assertion to the
independent Node SHA-256 `global:seeded` word **17358739751253998038**.
The first typed-struct/local-runtime-word variant passed day **594/594**, exact
IDL/fixture and 88-step SBF parity, but **RoundStart +23 CU**; it was not applied.
The next variant folds the complete std word into a typed scalar `@comptime`
local. This uses ordinary compile-time scalar code, not an application codec,
compiler patch or module-scope aggregate workaround.

Scalar candidate build passes **53 modules**, native day **594/594**,
fixture/IDL runs exit 0 and are exactly equal to the preceding combined candidate.
SBF replay **88 instructions, zero differing bytes**; 12 VRF/76 Hydra creates with
PDA signing. RoundStart **12,344–14,619 CU**, worst act-with-fight **772,545 CU**:
both **28 CU below** the combined baseline. ELF **367,840 bytes** (**80 smaller**),
SHA-256 `059fd8cd801ed56328953a960f5045711f755cf2fcdf61944badc9d30d2e12e2`.
Logs `scalar-{build,day,fixture,idl,dayLiteSvm}.log`; rejected variant ELF and replay
remain `typedStruct.so`, `typedStruct-dayLiteSvm.log`. Candidate support matches
manifest `df5dea9f...`, binary matches `669adbbd...` above.

Applied to canonical port `program/day.ms` and its existing day regression only;
legacy main gets it through a future port merge, not duplicate cleanup now.
Port program files compare equal to the successful scalar probe. Installed
upstream typecheck **91 modules, zero errors**; actual port candidate build
**53 modules**, ELF SHA-256
`76ff3cab0cfbdf556b23d47c8dbd5546d4a3229322b4c2bc174ed0dd2d18373a`.
It uses b50 rules, not combined current rules, so its ELF is not expected to equal
the combined scalar binary. Full matching-release gate and port land remain open.
No commit/sync/upgrade, external signing or running-world changes.

## Enum-storage contract probe — 2026-10-07

Historical alignment change `7c240804` explicitly chose byte storage in
`rules/layout.ms` `FightRecord`; it is not safe to infer removal from enum width
alone. `/tmp/hibernalEnumContract20261007a/` copies the successful scalar/combined
sources and changes only outcome storage to `Outcome`, its constructor assignment
in `rules/actions.ms`, and the needed visible enum import in `program/idl.cms`.

`msc-stable run layoutSizes.ms` before/after: **Outcome 1**, **FightRecord 120**,
**Pet 176**, **PetAccount 296**, **Block 4,888 bytes**, unchanged. This proves sizes,
not offsets or behavioral parity. Initial IDL run refused the enum because it was
not imported where `anchorIdl` is called; adding `Outcome` there makes
`msc-stable run program/idl.cms` pass. Its **entire IDL JSON object equals** the
preceding combined/scalar baseline: zero-copy enum width is emitted as **u8**,
not a new public enum declaration. Logs `byte-sizes.log`, `enum-sizes.log`,
`enum-idl.log`, result `enum-idl.json`.

Verdict: typed storage is an eligible cleanup, not an established IDL breaking
change; the first suspicion of such a change was disproved. No active rule or
port field type was changed in this probe. It still needs native/JS digests,
actual account bytes, codec invalid-enum tests and SBF/frame/CU validation before
application. Current byte view remains in the active source pending that gate;
no checked-codec fallback or new wire implementation was introduced.

## Typed outcome safety/compute gate — 2026-10-07

The same enum probe then removed `fightOutcome` and its ten calls, accesses the
now-typed field directly, and adds a wire-width regression (**Outcome 1 B / record
120 B**). These remain temporary edits; active main/port still have byte storage.
`gateEnum.sh` runs the same **19 commands**, all exit 0: rules **417**, teacher
**437**, ffi **471**; program admission **559**, owner **562**, payout **562**,
resort **529**, shop **562**, day **595**. All eight native/JS digest lines and
all eleven curve rows equal the preceding combined gate; full IDL JSON and the
three-day fixture are exactly equal. SDK support is still the same 296-file
manifest; no source/toolchain drift was attributed to this result.

`enumCodecConsumer.ms` uses std decode/encode on the real **4,896-byte Block**
from the SBF-compared fixture: exact roundtrip, invalid outcome byte **2** rejected.
The mutated position comes from diffing two std-encoded valid enum values, not a
layout offset. A separate attempted literal `2 as Outcome` was correctly refused
at typecheck; no unsafe construction was used to bypass that refusal. The probe
therefore proves invalid-byte decode rejection, not an invalid-value encode test.

`dayLiteSvm.mjs` on the typed candidate with the **unchanged** baseline fixture:
**88 instructions, zero byte differences**, 12 VRF / 76 Hydra creates with PDA
signing. RoundStart **12,410–14,685 CU**, worst act-with-fight **772,599 CU**.
Compared with scalar-discriminator parent: RoundStart **+66 CU**, worst act
**+54 CU**, ELF **368,920 B (+1,080 B)**, SHA-256
`90ed9a72f845d4da6fb70076bd0abc723172d25f637b448a26478979953fdfb2`.
The parent source variant and support were held fixed except the enum cleanup;
this is the measured cost of the typed/checked bundle, not an isolated validator
instruction attribution. Native tests also include domain checks, not new economy.

Recommendation: accept the small CU/size increase for standard checked enum
rejection and honest field typing. The goal requires the person's trade-off
decision **before release**; this variant remains unapplied in `/tmp`, not a
reason to pause independent integration. Keeping explicit byte storage is the
alternative, not permission for a manual range decoder. Logs/binary/codec probe
remain under `/tmp/hibernalEnumContract20261007a/`. No world reset/signing/deployment.

## Normal owner fixture codec probe — 2026-10-07

Copied the current canonical port into `/tmp/hibernalOwnerCodec20261007a/` and
changed only `program/test/owner.ms` normal PetAccount/World staging and PetAccount
readback to shared `encode`/`decode`. The copied file has no `Ptr` overlay or
staging globals; decoding passes the actual holder owner and expected program.
Fixture rejection fails loudly. Production handlers and existing session
owner/authority/PDA/expiry, signer, replay, dead-pet and compressed-clock cases
are unchanged. SessionTokenV2 manual fixture bytes are still an upstream-surface
prerequisite, not replaced by another application codec.

`/Users/le/metascript/.wt/wt-std-solana/msc-stable test
/tmp/hibernalOwnerCodec20261007a/program/test/owner.ms`: **559/559**, exit 0.
The binary still has SHA-256 `669adbbdf20125bc677e7b60ef05bc38935232db381b20bb158d53d0e642ac14`.
A repeated run holds the 296 SDK support files fixed before/after, manifest
SHA-256 `9161e8a52cd60750b62d96ee168a02f986c05c70d02a6679beb8d2da21ed0c67`.
This differs from the earlier combined gate in `std/solana/macro.ms` and
`test.cms`; earlier SBF/IDL results are not a gate of this newer SDK snapshot.
The port parent is still tree `f1a2a8f16aeb4f9368ad9d251ecc21c931c5a8bc`, with
its previously measured ten-file public-barrel/scalar-discriminator delta.
`ownerCodec.patch` SHA-256 `dfe248cf848df987416ba36935c7f3f0a5939cf331919f103bb474f99edeb928`.
The migration is temporary only: installed std still lacks accountCodec, so
no active import or completed std-consumers claim. Test and manifest artifacts
remain beside the patch.

## Installed 0d83c4867 remeasurement — 2026-10-07

Installed BUILD now names binary/support **0d83c4867**, synced
`2026-10-07T20:12:04+07:00` by another session. Coordinator confirms this contains
sized-array land `097316d5f` through the land-queue gate, including
`src/test/lang/sizedArrayConstDimension.ms` and `sizedArrayLiteralCarriesSize.ms`.
This is a gated land and sync, **not a release cut or SDK delivery**; local
compiler main was already `2fe0c4e1c` when checked. No sync performed here.

Artifacts and commands: `/tmp/hibernalUpstream0d83/gateInstalled.sh`,
`results.tsv`, `verified.json`, and per-command logs. Actual active rules/sim
source diff stays `4dd97a006dc9a2aac2208e95a5f35cff1293d5208b0e1bded8bfcb560621fff5`.
Installed binary SHA-256 `e4ea8ad7cb3d2a4176d4d63add5c587bb0cd0116669f66ea76d1d0dfe4ceb221`;
all 287 installed std/runtime files and binary/BUILD are unchanged before/after
these gates (manifest SHA-256
`4f9cd70a524175d14f08ee342c41ddf8e65ac69b645019274fbd1581ccb57be8`).

- Existing imported ECONOMY_INPUTS probe: C and JS both **`imported size 46`**, exit 0.
- Existing literal/for-of probe: C and JS both **`literal size 4 total 7`**, exit 0.
- Actual active rules **416**, teacher **436**, ffi **470**, all pass.
- All eight native/JS digests equal each other and the preceding arithmetic
  migration; all eleven curve rows unchanged. Engine **15072111084034916937**.
- Actual canonical port typecheck **91 modules / 0 errors**, but **SBF build
  and owner host test still fail** with the four known unlowered `program<System>`
  TryExpr errors at 173:16 in admission/shop/resort/payout. The public-barrel
  two-module repro in `programSystemTwoModules/` fails with the same single
  second-module error. The original `/tmp/msRepro/...` path was missing and
  was re-created at this new artifact path; its missing-file attempt is not
  counted as compiler evidence. Existing compiler card updated.

The foreground aggregate timed out at 120 s after the first four commands;
remaining commands were explicitly resumed in the background and finished.
No test was bypassed or counted from incomplete output. Sized-array consumers
can now be probed for cleanup, but full port acceptance remains open; no compiler
card closed, brain buffer guard removed, commit/land/deploy/reset, or candidate
codec installed. The enum trade-off does not pause this independent work.

## Named brain buffer consumer probe — 2026-10-07

On installed binary/support0d83c4867, copied current rules/sim and actual
`program/brain.ms` into control/candidate trees under
`/tmp/hibernalNamedBrain20261007a/`. Candidate changes only the nine scratch-array
sizes to imported dimensions, with the attack-choice count a scalar const derived
from ATTACK_HOLD. The genuinely scalar node score stays `[1]`; the existing
buffersMatchRules guard remains until the whole consumer can be gated. No active
source changed. The inline dimension expression `[ATTACK_HOLD + 1]` was refused;
its named scalar const variant passes native and JS in the isolated
`derivedDimension.ms` probe (length41/value7), so no unsupported expression or
compiler patch is smuggled into the candidate.

Real p31s5 policy equals the existing out/actProbe/policy.txt fixture exactly:
4,763bytes, SHA256 `e86d99a3151dcbf9adbd0438ce079012d8a936f424c837fa493c3bb0c2973f5a`.
The consumer runs three actual program-brain heads against sim/env/actor before
each economy/node/attack application, over40epochs. Both literal control and
named candidate native runs exit0: **1,600 cases**, **701 nonempty node masks**,
**1,160 eligible attack masks**, identical digest **6917852495658717615**.
This is head-choice parity, not full chain/re-sort/wild-retirement acceptance.

Control JS builds but Node refuses duplicate `Tree...Eq` declarations; the
identical structural-equality helper appears four times. The candidate's initial
build stopped on the dimension expression; after using its scalar const, JS
builds but reaches the same duplicate-helper refusal. No JS output surgery,
handwritten comparator or dropped reference check. Earlier sim/determinism
C/JS remains green; this is a newly exposed consumer boundary. Binary/support
manifests stayed fixed throughout these probes. Logs: `control-native.log`,
`control-js.log`, `candidate-named-native.log`, `candidate-named-js*.log`.

Simple nested/cross-module/test-bearing/array equality controls, actor imports,
individual world actions and their three-stage composition all pass JS; they do
not isolate the failing phase. Smallest failing consumer found here remains
`brainConsumer.ms`; the compiler owner must finish reduction/root tracing.
Named blocked site and commands in
`~/metascript/.inbox/compiler/2026-10-07-js-struct-equality-helper-declared-repeatedly-in-actor-brain-consumer.md`.
Active brain/port keep their literals and guard; no cleanup or goal completion
claimed while this consumer JS gate is red.

### Latest installed remeasurement — c0949e9f2

On matching installed binary/support c0949e9f2 (sync2026-10-08 08:40+07),
reconstructed the real-policy literal/named A/B from current sources after old
`/tmp` artifacts disappeared. Both native runs pass39modules with1600cases,
701nonempty node masks,194selected non-hold attacks and digest
10091286560668025030. The attack counter/digest differ from the historical
probe definition, not between candidates. Both JS67-module builds succeed;
actual Node ESM execution still refuses the four duplicate Tree helpers.
The284-file support and binary manifests held fixed before/after; binary SHA256
1362b92c073c9d18a8aee661839d33c5ea682ffeee728ed858356128d3321494.

The failing entry is now reduced to10lines: import `std/fs::readLines` and
`sim/world::World`, construct one block, print its length and read BUILD.
`std/fs` emits an ESM import; a World-only control already contains three
same-named helpers, tolerated by Node's automatic CommonJS execution but
rejected by explicit ESM parsing. **Plain `node --check file.js` is insufficient**:
use actual ESM execution or `node --input-type=module --check < file.js`.
Fresh reduction controls all fail that explicit module check; older plain-check
syntax greens do not establish unique helper emission. This isolates parser
mode, not the compiler implementation's root cause. Sources/commands are in the
existing compiler card; no forcing CommonJS, comparator or output patch.

Further reduction is now independent of Hibernal: one Leaf nested in two
different parent structs, with parent comparisons in separate modules and a
std/fs ESM import. Native prints three true values; Node rejects duplicate
Leaf equality declarations. Removing the second comparison import passes;
merely removing its call does not. Four tiny source files and commands are in
the existing compiler card (`/tmp/hibernalC0949/equality/`).

An independent copied `tools/policyBench.ms` literal/named-buffer A/B builds
SBF9modules on that same c0949 delivery. LiteSVM runs real p31s5 weights with
one economy pass,9attack targets and6node candidates: **427559CU / 8840B**
both. ELFs are byte-identical, SHA256
fcb2eecddb33e93ab0f4d1399078af1902b2b3646ea5cb8895c60f1a03b2aa6b.
Native/SBF checksum matches9959996096057471538. Both probes reject wrong owner
(145CU), truncated and longer raw-policy fixtures (172CU each). The existing
probe-only policy overlay is retained, not a new account codec or a full-flow
acceptance claim. Both corresponding std/fs host JS consumers still hit the
known duplicate Tree ESM refusal. No active source cleanup follows from the
isolated SBF green. Binary/support284files remain identical after these gates.
Evidence: `policyLiteSvm.json`, `policy-*-*.log`; all fresh sources/logs/raw
readback are preserved in ignored `out/compilerProbes/c0949BrainAndHudReadiness.tar.gz`.

Actual canonical public-barrel port check passes91modules/0errors, but its SBF
build and fresh owner host test still fail the same four unlowered TryExpr173
sites before owner tests run. Independent installed source-IDL generation passes
27instructions/9accounts and exactly matches current `out/idl/hibernal.json`
(canonical sorted-JSON SHA256b9b07414fbe70376a640ec9c91b360d46afea464fbb87fc24734bcfaefb209df).
Fresh installed rules416/teacher436/ffi470 pass; all eight native/JS determinism
lines match, engine15072111084034916937; all11curve rows retain their recorded
numbers. Support-before equals support-after-suites across all284files. This is
partial consumer coverage, not a green program/host release gate. Existing actHost
also has two stale World.wilds accesses: source drift, not a compiler regression.
No accepted program/host gate or active brain cleanup follows from these probes.

Readonly public-devnet metadata at2026-10-08 04:08:29–35Z confirms old9Z51nH
program executable on L1/ER, Config304bytes and one registered Pet272bytes
versus current canonical304bytes. L1slots508691007→508691027 and
ER746031395→746031842 advance; this does not prove world progress or recovery.
The selected public owner's confirmed Token2022 holdings return an empty list.
HUD received raw fingerprints with no cross-layout field decode. Registry-only
ops discovery remains a blocker for arbitrary MWA Claim placement; no matching
accepted deployment/layout/client tuple or signing/upgrade authority inferred.
Artifacts: `/tmp/hibernalC0949/`, including `hudReadiness.json`.

### Later delivery — installed525c8ba4f

Matching installed binary/support525c8ba4f, sync2026-10-08 09:54:47+07,
binary SHA256e41b3d81406ec802d14abba2bc96e8ed63ecb9f6a7fdb16663aa86d8bfb94f64;
286support files held fixed before/after. Actual port check91/0 passes;
SBF and owner host still fail the same four System TryExpr173 sites. Rebuilt
independent Leaf ESM repro remains red. AccountCodec/client remain unshipped.
Fresh rules416/teacher436/ffi470 and eight native/JS digests pass, unchanged
engine15072111084034916937. Source-IDL27/9 exactly matches canonical JSON;
native3-module shared-type consumer confirms recorded layout sizes. These are
source/type proofs, not deployment or codec/client acceptance.

An independent frozen **UNGATED SDK** candidate now exercises actual canonical
PetAccount: public encode/decode304-byte roundtrip, exact re-encoded bytes and
owner/truncation/discriminator refusals pass native24modules and automatic
Node CJS execution of the JS72-module bundle. Explicit ESM parsing refuses
`msSized_2qo35eEq` duplicate declarations; CJS is not a workaround/acceptance.
A separate four-file sized-array/two-parent comparison repro reproduces that
same declaration failure on installed525c, native three-true control green.
Both sightings are added to the existing JS compiler card, not a new card.

Frozen SDK binary1367157edc308de7260a57410fccbe292e9b90c5e86dfb698b199768d98efb94;
293source files unchanged. Owner per-root sorted recipe(std then runtime)
hashd589b16fdd21fa66cc113cddfa0ebb6c3ae1cad7e285cfcad4f0da23c8a0c7a6;
global-sort recipe854f6c5e4bcd06ced8536a0e8e1e073ee11aa4b0cac57a2b6a6293a17ff06cac
identifies exactly the same files, as owner confirmed. Probe initially copied
only those sources/binary and omitted existing crypto vendor dependencies;
copying/fingerprinting vendor/mbedtls completed its native closure(2996files,
manifest52ed07a9a25e0ca83e435b32fa463e713280dcea3c42321f90b80ae8128fd0d0).
That was our probe snapshot omission, not a compiler/original SDK packaging bug.
Initial main-layout input used obsolete Seeds; the measured fixture instead
uses the existing canonical port layout, not an application API workaround.
No SDK/compiler edits, active codec import, Claim, upgrade or deployment.

Evidence: `/tmp/hibernal525c/`, `/tmp/hibernalSdkD589/`, preserved in ignored
`out/compilerProbes/525c-and-sdk-d589.tar.gz`. HUD received source/type paths and
explicit no-readiness caveats; SDK owner and coordinator received exact reds.

## Wild/ER prerequisite checkpoint — 2026-10-08

Installed0d83 remains unchanged. Existing `msc check tools/wildProbe.ms --os=solana`
exits1 on obsolete `Instruction`/`Seeds`/`Pubkey.magicProgram` surfaces plus
cascading signer-seed errors (nine diagnostics including final summary; log
`/tmp/hibernalWildProbe0d83-check.log`). Its ephemeral create/close tags12/14 are
still a missing shared protocol surface, not permission to rebuild them locally.
Full port uses dead-wild scratch; no wilds/retirement chain proof inferred from
prior88-instruction LiteSVM gate or native1600-head parity.

Coordinator confirms **both compiler cards lack fixing owners**, surfaced to
person for fresh recompiler sessions. Stdowner confirms no accepted delivery,
land or sync; candidate core.cms/test.cms/runtime/solana/host.c now changed to a
feature-gated Systemopcode13 path. Old frozen candidate/support/SBF evidence
cannot accept that changed source. No Hibernal implementation or install made.

Read-only old-world health check exposed ER RPCbank clock freeze at8414055
(all four commitments and processedbank/blockhash replies), despitegetHealthok,
continuedvalidatorprocess/snapshotarchiving and advancingL1. Evidence/details:
`ER-BUGS.md`#2, `/tmp/hibernalErStall20261008a/`, validatorowningrepobrief
`.inbox/hibernal/2026-10-08-rpc-bank-clock-frozen-while-snapshots-advance.md`.
Watchdog'sfrozen-slotstuck0/resumed0 isnotmaintenance recovery. No reset/restart
or signing; this historicalprivateworld isnotupstream48hendorsement. HUD received
alarm and retainsvisual-only/Claimdisabled scope.

### af9f92644 delivered JS acceptance — 2026-10-08

The preceding ownership/install snapshots are historical. Compiler delivery note
`~/metascript/.inbox/hibernal/2026-10-08-compiler-synced-660ed426f-js-equality.md`
reports the bundle equality-helper fix shipped. Actual installed binary/support
is `af9f92644`, synced20:59+07; read-only ancestry confirms660ed426f is an ancestor.
Consumer closure288paths (binary/BUILD/std/runtime) held fixed before/after.
App bases: chain tree `cd0c708d59589141ae2491d2423b19b65f40048a`, port tree
`f1a2a8f16aeb4f9368ad9d251ecc21c931c5a8bc`; dirty rule/sim inputs remain in scope.
Archived brain sources were compared directly with current app:42files, zero differences.

For Leaf, sized-array and actual brain: `msc run <entry>`, `msc build <entry>
--target=js --output=<bundle>`, `node --input-type=module --check < <bundle>`,
and `node --input-type=module < <bundle>` all exit0. Leaf/sized both print true×3
on native and ESM. Actual brain native39modules and ESM both print
`cases 1600 nodes 701 attacks 194 digest 10091286560668025030`.
The194 counts selected non-hold attacks, not historical eligible-mask count1160.
Policy remains exactp31s5/4763B/SHA256e86d99a3151dcbf9adbd0438ce079012d8a936f424c837fa493c3bb0c2973f5a.
Archive `out/compilerProbes/af9-js-consumer-acceptance.tar.gz` retains sources,
closure hashes, bundles and full logs; scratch `/tmp/hibernalJsDelivery/`.
This closes only Hibernal's JS equality consumer blocker: no generated-JS patch,
forced CommonJS, std/compiler/app workaround or active brain-dimension change.

Other independent measurements completed before that delivery:
- FrozenSDKd589/136715 unchanged canonical port:53modules/360088B ELF,
  SHA256ca17dd411c36679b074f89c7516781bb254e861f4fbfb161b9bb0c851ccda56c;
  owner559/day592;3-dayfixture,88LiteSVMinstructions/0byteDiff,
 12VRF/76Hydra requests accepted by STUBS; worstsampledfight806751CU.
  Binary/support/vendor+84appfiles unchanged. Archive
  `out/compilerProbes/d589-unchanged-port-host-liteSvm.tar.gz` is oldcandidate
  diagnostic, not latestSDK/installed/realexternal-contract acceptance.
- `tools/actHost.ms` source drift repaired by reusing
  `sim/world.ms` `surroundingsOf`'s existing absent-storage mapping. Prior check
  refused two missingWorld.wilds reads; native39modules then exits0, existing
  typical/busiest sim-choice+digest checks bothtrue, dawnfixture and50acts/5runs
  complete. Archive `out/compilerProbes/actHost-source-drift.tar.gz`.
  No rule/policy change; unchanged rule suites do not observe this host-only edit.
- `out/compilerProbes/2d7-coordinator-boundaries.tar.gz` retains fresh historical
  installed2d7 fourSystemTryExpr173 errors and sizedESMred. Do not relabel that
  as af9 SBF measurement: af9 SBF/ownerhost were not rerun for this JS-only gate.
- Read-only `out/compilerProbes/er-recovery-readback.json`: L1slot306187→306193
  while ERslot/blockheight8414055 and blockhash stayfixed, getHealthok; oldworld
  opsrecordepoch46/resort42/living38784 and stale ownerstatus. No recovery or
  upstream48h proof; no restart/reset/signing/send.

SDK gate/land/sync, generic-inline fix delivery, deferred client/protocol ownership,
real ER recovery, fresh matching devnet deployment and Seeker full flow remain
separate requirements. Compiling/playing a fixture is not submission readiness.

### Independent orchestration regressions — 2026-10-08

Read-only workflow `b03ad4ca-505d-4278-bcb5-63e274f7ab10` found two application
orchestration defects. Parent checked source and reproduced both offline before
fixing; host-consumer lane found no additional grounded defect. App base remains
chain tree `cd0c708d59589141ae2491d2423b19b65f40048a` with session edits.

`node --test tools/chain/ops.test.mjs`: initial five cases had three expected
failures (invalid/missing ops timestamp; cached cranker slot never polled again).
Fix uses existing `gameCranker.mjs` `refreshBlockhash` loop to refresh its clock
from the existing shipped RPC call; one slot read per successful refresh, no new
transport/watchdog. A sixth regression caught HTTP overwriting a newer streamed
slot; older responses now cannot rewind the observed clock. Sentinel `opsCheck`
reports invalid timestamps through its existing alarm path. Final six tests pass;
actual source-extracted refresh→tick consumer releases due/retry work with no slot
stream. Live entrypoints, keys, sends and running processes were not touched.
This proves the application scheduling/check contract, not vendor ER recovery.

IDL coverage control: existing source-only `out/idl/hibernal.json` copied to scratch;
only Initialize's first argument type changed from pubkey to u8. Original and
mutant both passed `node tools/chain/idlCheck.mjs <path>`,23checks. Output and prior
claims now explicitly name discriminator/account metadata and exclude argument
ABI. No current builder mismatch established and no app serializer added. Shared
checked argument-builder acceptance still waits upstream delivery.

Full lane reports, before/after logs, mutation inputs and session delta are retained
in `out/compilerProbes/independent-orchestration.tar.gz`. These are local source
changes, not activation/restart, deployment, upstream acceptance or submission.

### 1064f8c61 installed program acceptance and named buffers — 2026-10-08

Delivery note `~/metascript/.inbox/hibernal/2026-10-08-compiler-synced-1064f8c61-inline-generic.md`
arrived during independent work. Actual installed binary/support1064f8c61 closure
288paths remained fixed. Canonical port83sourcefiles unchanged during baseline
consumer gate, same port base tree as above. No private compiler or SDK candidate.

Actual `msc build <port>/program/main.ms --os=solana --output=<scratch>/hibernal.so`
builds53modules, ELF352304B/SHA256421288ccab61785dfce4df03c881d010a15f39c91fc16b60aab871d8890b71d8.
Program host suites admission555/day591/owner558/payout558/resort525/shop558 all
pass. Current main rules416/teacher436/ffi470 pass; native and explicitESM all
eight determinism lines match. `program/idl.cms` prints JSON; it does NOT write
`out/idl/hibernal.json`. A mistaken scratch-file assumption failed with missing
file, not compiler regression; running its compiled native binary with stdout
redirect produces canonical JSON,27instructions/9accounts exactly unchanged.
Existing metadata gate23passes; argument ABI coverage remains separate.

Day fixture ran from isolated scratch CWD with staged exactp31s5;3days. VRF10/Hydra7
stub builds and `dayLiteSvm.mjs` pass:88instructions,0byteDiff,12VRF/76Hydra requests
throughSTUBS with PDA payer, worstsampledfight806498CU. No actual external protocol
or deployed ER acceptance. Archive `out/compilerProbes/1064-installed-program.tar.gz`
contains literal baseline sources, closure/app hashes, ELFs, fixtures and logs.
This closes Hibernal's generic-inline System consumer blocker, not SDK delivery.

Then removed nine historical literal buffer dimensions in `program/brain.ms` in
both owned worktrees using existing rule constants and a derived named scalar
attack-choice count. Intentional scalar score[1] and shape guards remain. Only
portsource `program/brain.ms` changed; main/port copies identical. Actual brain
native+explicitESM gives unchanged1600cases/701nodes/194selectedattacks and
choice digest10091286560668025030. Full named/literal program ELF is BYTEIDENTICAL;
88-step replay logs including every sampled CU line are BYTEIDENTICAL. Thus no
layout/policy/gameplay/ELF/CU change. Native suites for unchanged rules have no new
inputs; focused real-brain/C-JS/full-SBF/replay checks observe this buffer edit.
Archive `out/compilerProbes/1064-named-brain.tar.gz` retains the A/B proof.

Installed accountCodec.ms/client.ms/rpc.ms/transaction.ms/mwa.ms existence checks
are still false. Their accepted API delivery, deferred protocols, real ER recovery,
wild retirement, current integrated deployment and Seeker full flow stay open.
No note from another writer was deleted; no commit/land/push/sync/signing/send,
process restart/reset, funding or deployment performed by this worker.

### Combined current inputs on installed1064 — 2026-10-08

Integration preparation assembled isolated current main rules/sim/actBench plus
canonical port program;63sourcefiles checked byte-for-byte against their origins,
installed1064 closure288paths unchanged. No actual branch rebase/merge or privateSDK.
`msc check <combined>/program/main.ms --os=solana`:91modules/0errors;
SBF53modules,359776B/SHA256141b7c09ed3fb4bd26488af0ef6e8799b408366b7aef3b67a9c7d14a69e6aada.
Owner560/day593 pass. SourceIDL27/9 exactlycanonical,23discriminator/account-meta
checks (argumentABI not checked). Fixture3days matches canonical historical hash
b087cbc727f5cf6b48facaff886ff33d52f7201853322a7bb5dd11152efec491.

LiteSVM88instructions/0byteDiff;12VRF/76Hydra requests throughSTUBS.
Worstsampledfight772185CU; dawn67045, dayEnd66083–67149. This is the combined
current rule migration, not a claim the unchanged port's baseline806498CU changed
by named dimensions: those named/literal ELFs were identical above.
Aggregate180s deadline interrupted fixture execution after successful build;
resumed the existing native fixture binary, completed runtime and replay, then
ran day suite and IDL checks green. No check skipped or red reclassified.
Archive `out/compilerProbes/1064-combined-port.tar.gz` carries source manifest,
closure, sources, logs, ELF/IDL/fixture and scoped result. Missing upstream shared
codec/client/protocol delivery and real ER/world/app acceptance remain open.

### Validator RPC publication investigation — source-confirmed, 2026-10-09

User approved an investigator in owning validator repo, not implementation or
recovery. Source revision e66d914762887334d027507a8812f8a01521e37c;
parent independently read `magicblock-aperture/src/processor.rs:EventProcessor::run`,
`magicblock-ledger/src/lib.rs:LatestBlock`, `state/blocks.rs:BlocksCache` and
cached Tokio1.52.3 select documentation. Ok-only block receive pattern does not
handle broadcast Lagged. Documented select pattern mismatch disables that arm
until select returns; pending account/transaction/cancellation arms can leave
RPC publication idle indefinitely. Authoritative latest is stored before broadcast,
capacity32; RPC cache is independent. This is an inspected caller availability
bug, not executed Tokio proof, established attacker exploit or historic attribution.

Correction to earlier wording: frozen getSlot/blockhash demonstrates stale RPC
view, NOT necessarily frozen scheduler/ledger/bank. Snapshot suffix denotes
scheduler checkpoint slot; asynchronous archive-start log does not prove completed
archive or runtime/source identity. getHealth in this revision returns unconditional
ok. Historical root remains probable: initial lag, actual running ELF and matched
Clock/ledger/cache observations missing. Analytical Python model is illustrative,
not a real-runtime red/green test. No native Rust build/test or live probe performed.

Proposed scope after approval: targeted Aperture Lagged-without-other-events
regression, unconditional receive-result handling and authoritative-latest resync;
prevent stale buffered/concurrent cache rewind, preserve startup readiness,
blockhash eligibility/TTL and cancellation. Adjacent executor uses authoritative
resync idiom. Channel enlargement/forced traffic/client wall clock/reset were
rejected as bypasses, not fixes. No implementation diff or change-induced invariant
violation; invariants reviewed, runtime correctness not attested. Validator docs
untouched; potential follow-up not queued.

Current resumed-child safeguard reports main checkout detached at
`/Users/le/projects/magicblock-validator`; parent confirmed HEAD is not symbolic.
Owner must repair checkout before code work; no branch switch/bypass here. Earlier
original-run checkpoint provenance was withdrawn, distinct from current safeguard.
Source fix/test/build and live recovery are separate, still unapproved. Keep retained
world and pending obligations intact. Full report, parent review and model preserved
in `out/compilerProbes/validator-investigation.tar.gz`. All five readiness scores
remain7/8/7/3/3; discovering source bug does not close recovery/endurance/device gates.

### ER/Seeker/internal-release handoff — 2026-10-09

User-approved parallel workflow `d05c859f-3422-4c53-86c8-d2b5724a1a49`
returned three source-only packets. Parent reviewed actual placement/discovery
consumers, recovery fields and public artifact hashes. No new RPC/device polls:
HUD reports user stopped additional live probes pending gentle-poll policy.

`tools/chain/ops.mjs:blocks` previously reported queue length after planning as
pending count, excluding refused placement batches. Parent regression reproduces
one pending pet, zero placed, incorrectly zero left. Result now uses original
unplaced count minus successful placements. Refusal/success/no-capacity controls
and prior ops guards pass12/12; syntax/diff checks pass. This remains a send-based
status estimate, not confirmed contextual owner membership. Existing retries remain;
no live operator activation/backfill or new protocol/discovery mode was performed.

Existing registry file plus DISCOVER=registry bypasses history discovery, so
historical50k registry operation does not prove arbitrary MWA Claim consumption.
`blocks` requires owner delegation and ER clone before authority Place; it does
not delegate the owner's Pet. HUD correctly keeps Claim→delegation→placement→live
separate; Home must require Pet/Block/World identity and membership, not aggregates.

Validator inbox still open/unassigned. Parent asked both HUD sessions and
neon-main coordinator; none knows a current validator owner. Paired durable
`er-recovery-readback.json` survives; old referenced scratch directory is missing.
Recovery packet names raw pendingVRF/re-sort/crank fields and approval boundaries;
no advancing bank/game or retained-state recovery proof is supplied by it.

Parent checked eleven explicitly public local inventory hashes and both older1064
SBF archive ELF hashes against packet. No matched release tuple exists. Internal
shotlist marks every live-gameplay shot NOT YET PROVEN; historical cutoff, preview
APK and native/STUB evidence are not live footage or accepted release artifacts.
Existing archives are not wholesale secret-audited publication bundles.

Durable packets: `out/compilerProbes/er-seeker-release-handoff/{er-recovery,
chain-seeker,submission-prep}.md`; archive `er-seeker-release-handoff.tar.gz`
retains packet/probe/red-green evidence. Two HUD sessions keep app ownership;
this lane owns chain/operator acceptance. All five groups retain7/8/7/3/3.
No signing, deploy, reset, publication, std/compiler workaround or UI change.

### Five-group solidify — native/offline evidence, 2026-10-09

Workflow `c6104c66-66ae-4440-8698-28a1f0627a89` returned five reports; parent
reviewed source, recomputed raw evaluation sums, and integrated two app fixes
plus one canonical-port rejection test. Installed717769655 was observed, not
silently treated as prior1064 SBF acceptance. std/compiler workaround repair
remains with owning lanes; none of these results accept a new shared API.

- `train/checkExact.py` now fails when stale policy is accepted or integer logits
  differ. Parent original and guard-mutation controls fail; integrated consumer
  mock passes. Actual native fresh35-module env library check exits0: stale engine
  refused(-5), economy52624/node22148/attack206055 legal logits, zero differences.
  This checker uses its existing random policy, not new training or p31s5 behavior.
- Canonical-port `program/test/payout.ms` now rejects substituted existing Paid
  ledger address for both Pet ownership branches; balances/supply/ledger unchanged,
  canonical subsequent claim/replay preserved. Payout559tests pass. Parent removed
  only Paid-PDA guard in scratch: assertion fails; byte-exact handler restoration
  passes. No handler or money-rule change.
- `tools/chain/ops.mjs:discoverPets` commits history cursor after transaction
  consumption; null transaction now fails instead of silently skipping Claim.
  Parent baseline/mutation fail two retry-after-failure tests; integrated9/9 pass
  and syntax checks pass. Existing cursor/pets/retry idioms retained. Registry-only
  historical runs bypass this path; not a fix or diagnosis for frozen ER bank.
  Previously advanced live cursors are not automatically repaired/activated.

Full native `p31s5` evaluation: fixed blocks versus7-day combat re-sort control,
8worlds×20blocks×10seats×120epochs, seed9001/wilds1. Seven days is experimental
control, not a new launch decision. Same exact57inputs/policy/freshlibrary and
288-path installed717closure before/after; parent recomputed all58counter sums
from1600-row arrays. Concurrent checkExact edit is outside health imports.

| Measured output | Fixed | Re-sort7 |
| --- | ---: | ---: |
| Illegal / funded-starved | 0 / 0 | 0 / 0 |
| ffiStats fights / deaths / heirs | 83133 / 1675 / 1374 | 62499 / 1641 / 1348 |
| Early deaths per100lives | 3.33 | 5.73 |
| Vengeful revenge within3days | 6.98% | 74.45% |
| Persona recall with revenge | 0.712 | 0.780 |
| Highest/lowest starting-region wealth median | 1.42 | 6.56 |
| Existing OFF health targets | 6 | 6 |

These are existing harness outputs, not all-green balance acceptance: full lists
and owner/persona breakdown remain in archived reports/logs. ffiStats living
includes wild seats; Feel ending wealth/living excludes wilds but action counters
can include wild actions attached to origins. Existing Feel fight-count tests
require seat-wide counts. Do not silently reinterpret these as pure-owner behavior
or change metric contract to erase OFF results. Terminal stats precede final attack.
No daily eligibility/stagger chronology/diary trace or realER failure/recovery
proof is added by aggregate evaluation.

Seeker report cross-checks existing HUD matrix against canonical handlers, without
finding a contradiction. Parent checked Load's no-owner-signer and partial-success
semantics, CommitPet's asynchronous checkpoint/no gift reset, ClaimReward's Paid
increment/caps. Source checklist is not matched deployed ABI or MWA proof; actual
profile/shared clients/replication and signatures remain missing.

Evidence archives: `solidify-ai-l1.tar.gz`, `solidify-ai-native-checker.tar.gz`,
`solidify-simulation-p31s5.tar.gz`, `solidify-ops-seeker.tar.gz` under
`out/compilerProbes/`. No live activation, retraining, gameplay/protocol change,
commit or deployment. Readiness scores are not raised from these bounded proofs.

### Native wild lifecycle regressions — 2026-10-08

Three authorized scratch-only agents prepared native wild actor/replacement/metrics
regressions; parent read the actual code, integrated tests and reran checks.
`sim/world.ms` owns retirement, live-wild→heir-before-re-sort accounting, and wild
exclusion from owner metrics tests. `sim/env/wildActor.ms` consumes realp31s5 via
existing `out/actProbe/policy.txt` fixture and `Batch` trained-controller path;
run it with `msc test sim/env/wildActor.ms` from a CWD holding that exact fixture.
It checks all three head observations/legal actions/transitions, invalid external
action overridden by assigned policy, absent realpet preserved and realstatechange.
No teacher-only action is relabelled trained inference.

Installed1064 native world433tests and actor importgraph527tests pass. Parent
independently removed each existing invariant in isolated copies: wild exclusion
from `living`, `vacated` before heir creation, trainedwild dispatch (forcedhold).
Each corresponding focused regression fails at its targeted assertion; restored
sources match project and focused actor passes. Exactp31s5 bytes/hash unchanged.
Replacement fixture keeps death/work accounting consistent via existingwithDeath;
synthetic wildwallet/gift amounts isolate accounting, not new game behavior.
Metrics fixture naturally spawns wilds, not manually edited metric balances.

Archive `out/compilerProbes/native-wild-lifecycle.tar.gz` retains reports, parent
logs, focused tests, source and policy identity. Earlier dead-wild retirement
red/green proof is `wild-retirement-regression.tar.gz`. Changes here are tests only;
rule/gameplay consumers have unchanged inputs, so curve/fullSBF checks have no new
behavior to observe. These guards do not prove ER-onlycreate/close, external
protocols, validator recovery or full-world endurance. Those remain separate gates.
