# App integration coverage

Current workflow: ordinary coverage-first implementation; user permits measured local
workarounds with explicit debt. Historical goal `muyzge1d-sq1g9g` remains paused;
no persistent goal mode. One outer Home. Signing/deployment/commit permissions unchanged.
This is an integration verdict, not a release or live-game readiness claim.

## Readiness audit — 2026-10-08

Checked dirty HUD over tree `9bdf70e27fb9829ba971d76d4c7c7f3e203647aa`, main
`98fad4e` / tree `1c91583806d38eefbc42a39cfd78da91c7385655`, chain `fc8f8f5` /
tree `cd0c708d59589141ae2491d2423b19b65f40048a`, and port `b50e0b5` /
tree `f1a2a8f16aeb4f9368ad9d251ecc21c931c5a8bc`. These trees identify bases;
chain/port have uncommitted work and are not delivered binaries.
Installed binary/support: `c0949e9f2`, sync `2026-10-08T08:40:38+07:00`.

Commands: `ls ~/.metascript/std/solana`, explicit file-existence checks,
`rg` on app/native call sites and chain `program/`, `git rev-parse HEAD HEAD^{tree}`,
and `git diff --no-index --stat rules/layout.ms ../hibernal/rules/layout.ms`.
Measured: installed `accountCodec.ms`, `rpc.ms`, `transaction.ms`, `mwa.ms` absent;
HUD has no `program/`; its `rules/layout.ms` differs from main (52 insertions,
32 deletions). Existing shipped std is program-side, not an app client.
Std owner independently confirmed no accepted client/codec delivery note.
Chain owner reports current port typecheck 91/0 but fresh SBF still four known
`Program<System>` / `TryExpr173` errors, no matched new deployment/fixture.
Those build results are peer-reported, not an app gate rerun.

Earlier candidate 304-byte PetAccount and exact 27-instruction fixture/88-step
proof are not installed acceptance. Old devnet Pet fixture is 272 bytes total;
never combine it with current shared payload. Historical private-world ER RPC
bank clock freezes despite process/snapshot progress; this is not healthy
upstream endurance or a diagnosed whole-process death. Fresh readback was requested
from the chain owner; cards are not current endpoint/deployment proof.
External evidence: chain `docs/STD-SOLANA-AUDIT.md`, `docs/OPERATIONS.md` §9,
`ER-BUGS.md` #2 and its compiler/validator owning inbox cards.

## Coverage matrix

States: **verified identity** = previously exercised real wallet/public identity;
**local preview** = visual/helper only, not chain integration;
**ready local gap** = fix uses an existing accepted local contract;
**blocked** = required delivery or real boundary proof missing;
**launch debt** = not an available owner interaction in audited program dispatch.
No blocked row is counted as integrated.

### Onboarding and lifecycle

| Capability | Current app verdict | Contract / next gate |
| --- | --- | --- |
| MWA connect/disconnect, cancel/no-wallet/failure | Verified identity, not transaction signing | `WalletBridge.request/connect/disconnect`, `host.ms` wallet ABI; renderer only requests UI-thread work |
| Remember owner independently of auth | Verified foreground identity | Strict public-key cache and native revision protocol; no cache-based Connected/game-ready |
| Restore owner from wallpaper-only process start | Verified local identity, §Passive owner proof | `GameOwnerStore.restore` runs from common `VoidNative.prepare` before rendering, without an Activity/MWA request |
| Cache loading/error and owner replacement | Strict cache algorithm retained; restore completes before first surface | Existing identity publication idiom; writes retain IO/cancellation checks; fresh connect/corrupt-cache device re-tests not performed |
| SGT admission discovery and existing-Pet lookup | Read-only owner lookup and empty Token-2022 holdings integrated on Seeker; eligibility/found-Pet body blocked | §Coverage-first read proof; Config pair/owner-filtered L1 program/delegation and ER queries; no NFT group eligibility inferred from nonempty holdings |
| No-Pet versus RPC/codec failure | Verified real empty result; explicit failure/unsupported branches guarded | §Coverage-first read proof; only successful checked lookups produce absence; fixture failure checks are not on-device outage proof |
| Claim/Summon | Local preview, hard-disabled | Shared admission/build/simulate/MWA-confirm contract and matching admission/deployment; B1–B4 |
| Resume existing or partial Claim | Blocked | Actual L1/ER evidence; never issue Claim again merely because placement is pending |
| DelegatePet | Blocked | Owner/authority gate in chain `program/admission.ms`; app transaction delivery missing |
| Place / ER block membership | Blocked B4 | `place` is authority-only; operator contract must handle arbitrary app claims, not only pre-registered delegated pets |
| Enter live game | Blocked | `hud.ms` currently always routes app to onboarding; require matched validated Pet, delegation/placement/membership and freshness before live Home |
| Dead/heir/lineage resume | Local numeral helper; live state blocked | Shared `rules/life.ms` and account identity; heir is not a fresh Claim; UI name selection has no chain name field |
| Background/wallpaper/app roundtrip | Visual device proof, not live sync | Same core and pointer isolation; public owner must restore without Activity; typed cached state needs B1/B2 |
| Offline/stale/frozen ER | Real read producer and explicit checking/error/unsupported UI; outage/frozen-world proof pending | `GameSync.select`, `host.gameRead`, `gameAvailability.petReadStatus`; RPC context slots do not establish World progress or game readiness |

### Live display consumers

Source truth is chain `program/layout.ms` plus shared rules; no second field layout.
The rows group actual consumers, not duplicate the account field declarations.

| Consumer | Current verdict | Source / gate |
| --- | --- | --- |
| Pet appearance, level/size, fire/hearts | Local preview | `androidEntry.ms` stand-in level and scene; bind validated Pet and existing rules only after B1/B2 |
| Harvest/burrow and daily rate | Stand-ins, explicit PREVIEW HARVEST/BURROW verified on wallpaper | `home.ms` `wealth`; real amount widths/rate/time require shared Pet/World/rules, no guessed balances |
| Hearts, bonding, growth bars | Stand-ins | `homeFrame`; use true bounds/expiry/derived rules, not preview constants |
| XP/level/points/tree and core/combat stats | Stand-ins / read-only ring helper | `Character`, `characterStats`, `skillRing`; actual rules-derived view with validated Pet |
| Talent reveal, modifiers, insurance, skin, pantry/gear | Partial visual helpers, no live binding | Shared rules plus owner product state; do not mistake supplied weapon icons for protocol products |
| Identity/name/lineage/life/death/age | Session-only name preview / numeral guards | Existing generation is shared; no authorized new nameId/account layout or claim name persistence |
| Block/neighbours/region/relationships | Not wired | Validated Block membership and neighbour Pet reads; full-info cards remain launch debt until their consumer exists |
| Epoch/round/season/Winter/emission/re-sort | Not wired | World/Block/config and actual freshness; no local timer substitutes for bank progress |
| Diary, morning digest, fight replay/odds | Stand-in activity list / kit helpers | Actual event history and FightRecord with shared combat semantics; snapshot alone is not complete diary history |
| SKR/HBRN balances, purchase/load/claim ledgers | Not wired | Correct mints/decimals/owner, Ledger/Paid and confirmed deltas; B1–B3 |
| Glance widget | Launch debt | Separate actual widget consumer absent; wallpaper is not widget proof |

### Interactions and authority

Inventory is audited from chain `program/main.ms` dispatch and its called handlers.
Existing operations are not automatically app-ready or owner-authorized.

| Interaction | Backend boundary | App verdict / gate |
| --- | --- | --- |
| Engage on app open | Owner or validated SessionTokenV2; per-round/day refusal | Blocked client/session contract; never use signing timer or remembered owner as authority |
| Bank | Owner-signed, rules cooldown/refusal | Blocked build/simulation/MWA/confirmation/readback |
| Buy | Owner-signed L1 SKR payment; Food/Growth/Insurance/Skin handlers | Current nine-item art shop is preview, not actual product or price catalogue; blocked shared product/tx delivery |
| Load | Ledger-to-ER application, PDA/ledger checks; handler has no owner signer | Blocked sequencing/freshness/tx; retries must observe cumulative ledger state, not duplicate payment |
| CommitPet then ClaimReward | Owner ER commit, then capped L1 payout to owner's token destination | Blocked MagicBlock signed paid-commit/client plus confirmation and mint/ledger proof |
| Claim / DelegatePet | Admission owner, then owner or configured authority | Blocked matched provisioning/ABI/client; signing approval remains separate |
| Skill allocation, eat, item mint/equip/trade, combat | Autonomous brain/rules paths; no independent owner opcode in current dispatch | Display existing outcomes; do not invent owner instructions or override pet autonomy |
| Neighbour cards / replay links | Read-only display navigation inside Home | Live reads/history blocked; supplied UI helpers are not connected behaviours |
| Hunt/Bounty/Move/leaderboard/auto-policy editor | No owner opcode in audited dispatch | Launch debt, not ready app integration or a silently dropped feature |
| Initialize/WritePolicy/CreateBlock/delegate world-block-resort-payer/ProcessUndelegation/Place/Seeded/resort/StartBlock/RoundStart/Turn/Sweep/WithdrawRevenue | Publisher/operator/day/payout administration; handler-specific authority | Not ordinary owner controls; no app signing/send or operator recovery implied |

`native/hud/signing.ms` is explicitly a frame-count stand-in; it is not a signing,
simulation or confirmation implementation and must never feed a live success path.
The actual accepted MWA bridge only exposes CONNECT and DISCONNECT.

## Blocking deliveries

- **B1 — shared checked account/client delivery.** Std owner `pi-42346` owns codec work;
  RPC/transaction/MWA are outside that goal, with no separate accepted owner/delivery.
  Unblock: installed BUILD/API note, exact consumer APIs, negative checks and supported
  host/native boundary. User now permits measured local HUD substitutes; read-only RPC
  workaround below does not expand std/compiler/protocol owner permissions or establish
  a delivered deployed-body codec.
- **B2 — matching shared types and deployed program.** Chain owner `pi-24590`, port
  worktree and owning System/compiler cards. Unblock: canonical build gate, supported
  shared-type handoff, engine/layout/cluster/program identity and matching fresh fixture.
  HUD's older rules are not automatically the current deployed type model.
- **B3 — transaction/session/payout boundary.** Client owner not assigned by existing std
  scope. Need actual builder/simulation/confirmation and MWA request/return contract,
  correct owner/session authority, Token-2022 products/admission and MagicBlock commit.
  App UI connection is not any of these contracts.
- **B4 — admission and operator/ER health.** Chain/ops and validator owning lane.
  Need an eligible unclaimed member for selected owner, arbitrary-claim discovery,
  delegation/placement/membership proof and advancing ER bank clock. Provisioning,
  upgrade/reset/recovery/spending require explicit decisions in owning window.

Fresh chain-owner readback at 2026-10-08 04:08:29–35Z, artifact
`/tmp/hibernalC0949/hudReadiness.json`: public devnet L1 endpoints agree on genesis;
ER reports an all-ones genesis, so it is not an L1 identity proof. The configured
program is executable on both endpoints, but different loader/length/fingerprint
is not source/ELF parity. Config bytes match (304 total); known registered Pet
remains 272 total on both, incompatible with canonical current 304. Selected owner
has zero Token-2022 accounts at confirmed slot 508691013; group eligibility is not
established. L1 and public devnet ER slots advance, which does not establish game
world progress or placement health. No accepted app tuple or arbitrary-MWA Claim
operator contract was delivered. This is a peer's raw metadata audit, not an app
reader/decoder or signing proof; historical private-world frozen-clock evidence
must not be generalized to these advancing public endpoints.

While these wait, make unavailable/preview status truthful. Do not enter live Home,
authorize transactions or fabricate discovered Pet.
When a dependency lands, freeze its exact identities and replace the affected local
workaround after consumer acceptance. Current user-authorized HUD substitutes must retain
validation, truthful status, version provenance and separately approved signing.

## Passive owner proof — 2026-10-08

Ready local slice, same dirty HUD base tree above, installed c0949e9f2:
`bash scripts/buildAndroid.sh` built 95 modules, APK
`6eb0dd9a56dab1e878facbb56d22894193e89d641a28e91b65dbc228cbb4156e`.
`GameOwnerStore` reuses the strict public-key AtomicFile algorithm; its common
prepare caller restores before rendering. Wallet publication still checks coroutine
cancellation after IO; no auth-file format or automatic wallet request was added.

Normally leased Seeker run 11:08:35–11:09:03 +07: Home before `adb install -r`,
PID 23212 → 24414, Launcher still foreground, new process logged
`Public owner restored: remembered=true` at 11:08:40.304 before app launch.
Then MainActivity showed OWNER REMEMBERED/public address/CONNECT WALLET; no wallet
intent or Connected/game-ready was inferred. Wallpaper retained roaming Pet/scene.
Evidence: `/tmp/hibernalPassiveOwnerCheck.log`,
`/tmp/hibernalPassiveOwnerWallpaper.png`, `/tmp/hibernalPassiveOwnerApp.png`.

Native C probe (`clang -std=c11 -pthread`, `native/host/hostLink.c`) passed exact
32-byte key/state/even-revision, disconnect independence, invalid length/null and
out-of-range byte checks. Source inspection pins restore-before-render and
write-before-cancellation-check-before-publication. This is not a new reconnect,
corrupt-cache or transaction device verdict; previous cache error proof is in
`RENDERER-BRIEF.md` §§11–13. Full identity/onboarding goal task stays unfinished
because real discovery/state transitions require B1/B2.

## Honest availability proof — 2026-10-08

`unavailablePetStatus` consumes existing `GameOwnerState`, not an invented producer:
unselected is not proof of no Pet; remembered is not discovery/authorization;
cache failure is not Pet absence. Onboarding says MODEL PREVIEW / NO VERIFIED
PET STATE plus the specific owner/client-unavailable status; Summon stays disabled.
Stand-in wealth retains its layout with explicit PREVIEW HARVEST/BURROW.
No live surface is entered or simulated signing helper used as an action.

`msc test native/hud/gameAvailability.ms`: 307 tests / 16 files pass, including
three pure view-message guards. `bash scripts/buildAndroid.sh`: 96 modules on
c0949e9f2, APK
`4df342f1f2b410745b76a9c3418e99389f1567028bf809990b333e921bb60182`.
Normally leased Seeker 11:32:49–11:33:02 +07, install-r/Home/app: captures show
preview wealth without clipping, remembered owner with CONNECT WALLET and
CHAIN CLIENT UNAVAILABLE. PET STATE UNKNOWN; disabled Summon tap remains in
MainActivity. Evidence: `/tmp/hibernalAvailabilityCheck.log`,
`/tmp/hibernalAvailabilityApp.png`, `/tmp/hibernalAvailabilityWallpaper.png`,
`/tmp/hibernalAvailabilityDisabled.png`. Unselected/cache-failure messages
are pure guards, not new on-device corruption/connect/reject verdicts.

## Resumed-goal dependency routing — 2026-10-08

Installed binary/support advanced to `525c8ba4f` (09:54:47 +07). Direct source
inspection confirms `borsh.ms` exports typed primitive readers/writers, `buffer.cms`
exports byte writers, and `typed.cms` wraps program account proofs. `host.cms` is a
program simulation harness, not an RPC account decoder. These exist, but do not
supply an accepted canonical HUD account/client contract. Four expected consumer
modules remain absent. No private fallback was created.

Std owner confirms checked `decode<T>`/`encode<T>` are implemented but ungated and
cannot deliver until the whole approved arc is committed, landed and legitimately
synced. Its own fixture is not the Hibernal layout. Chain owner reports its frozen
WIP SDK snapshot can round-trip canonical PetAccount on JS/native, but explicitly
offers no accepted SDK handoff. Its first native snapshot omitted crypto vendor
files; completing that diagnostic copy fixed the copy, not a distribution bug.
Do not turn this control into an app install/deployment verdict.

Chain owner independently measured installed 525c canonical check 91/0, but SBF
still fails exactly four `TryExpr173` sites in admission/shop/resort/payout. Existing
272-byte deployed Pet remains incompatible with current 304-byte source. Original
IDL source-only inventory remains diagnostic, not deployed-source parity.

The metascript coach `neon-main` confirms no supervised arc/card owns Solana RPC
read/send/confirm or MWA request/return, and it does not supervise Hibernal. Routing
is now measured: assigning this missing client scope requires the user's call.
Codec owner stays `pi-42346`; protocol/layout/deployment owner stays `pi-24590`.
HUD reran `/tmp/hibernal525c/layoutConsumer.ms` on installed 525c: 3 modules,
PetAccount/Block/World/Config/Ledger/Pet/FightRecord payload sizes
296/4888/128/296/64/176/120, exit 0. This imports canonical port source only;
no accepted client decoder or deployment match is inferred. The same compiler
reran `msc test native/hud/gameAvailability.ms`: 307 tests / 16 files pass.
Logs: `/tmp/hibernalHud525cTypes.log`,
`/tmp/hibernalHud525cAvailabilityTests.log`. Last Seeker APK stays 4df342… built
with c0949; it was not rebuilt/installed by these source-only checks.

Minimum client handoff the HUD will consume (not proposed replacement APIs):
- Public L1/ER account, owner-Pet and Token-2022 admission discovery independent
  of wallet authorization; context slot/commitment/endpoint errors explicit.
- Off-render-thread native/Android-compatible checked decoding from shared
  canonical types, owner/discriminator/length/invariant refusals and owned snapshots.
- Shared instruction/account ordering and products/quotas, unsigned construction,
  simulation, blockhash/expiry, confirmation and typed state-delta readback.
- Official MWA connect/disconnect plus transaction request/return, user-controlled
  signing, cancellation/rejection, account/cluster checks and no double send.
- Exact API/BUILD/native consumer acceptance, shared revision, program/cluster/
  deployment/layout and real matching fixtures; arbitrary-Claim operator placement.

Remaining goal tasks need B1/B2 typed delivery and/or B3/B4 action/placement,
provisioning and user-approved signing. This local proof does not complete the
identity-onboarding or live-game-surface milestone. This historical check used no
private reader/decoder, layout/protocol change, signing, transaction, commit or land.

## Coverage-first read proof — 2026-10-08

User authorized local measured workarounds; no goal mode. Dirty HUD over the same
base tree, installed binary/support `2d7abb082`. Two bounded Pi CLI workers audited
layout provenance and implemented read-only RPC in path-disjoint files; main read
both reports and reran affected checks. Historical source tree
`511868044a069d6e35ddf512af5f5533cab501ac` describes legacy272 prefix/layout;
structural/PDA evidence is not deployed source/ELF certification. Current304 remains
incompatible. Found candidates stay unsupported; no Pet body decoder or live-ready
state is provided by this slice.

`SolanaRpc` preserves platform HTTPS trust/hostname checks, exact unsigned JSON
numbers and bounded strict envelopes/account metadata. `GameSync.select` uses common
owner preparation, not Activity authorization. Its owner-revision publication follows
existing host mutex/revision idiom; replacing owner clears snapshot and rejects earlier
results. Cache failure cancels selection. The view uses `host.gameRead` and
`gameAvailability.petReadStatus`; failed reads cannot produce NoPet. Independent
wallet disconnect still leaves public-owner selection intact.

Verification: `msc test native/hud/gameAvailability.ms` reports `308 passed` across
16 files. Main reran real platform-parser fixture classes: `OK (9 tests)` (0.222s),
covering envelope/type/numeric/key/base64/null/bounds/cancellation guards. C ABI probe
passed snapshot slots/unknown/reset/stale-owner/disconnect/invalid-state refusals.
`bash scripts/buildAndroid.sh`: `Built 96 module(s)` and
`OK: android/app/build/outputs/apk/debug/app-debug.apk`. APK SHA256:
`a3511e4185d8f86c061bb3b577e4a94bb01c358cdff37d85dec89d57f6c0802c`.

Normally leased Seeker 17:44:48–17:45:22 +07, Home/install-r/MainActivity, no wallet
intent/signature/transaction. New process32608 logged at17:44:52.255:
`Public owner restored: remembered=true`. After30s, actual screen shows
`NO PET FOUND. NO TOKEN-2022 ADMISSION HELD.` and
`NO OWNER PET / NO TOKEN-2022 HOLDINGS`; owner remembered/CONNECT WALLET and disabled
SUMMON remain. This branch requires successful Config pairing, validated contextual
L1 program/delegation and ER owner-filtered enumeration, and empty L1 Token-2022
holdings; it is not absence inferred from cache or missing SDK. Render worker's actual
PixelArtRenderer preview is preserved. Evidence: `/tmp/hibernalGameSyncApp.png`,
`/tmp/hibernalGameSyncDevice.log`, `/tmp/hibernalGameSyncBuild.log`,
`/tmp/hibernalGameReadTests.log`, `/tmp/hibernalGameReadProbe.c` and RPC worker report.

Host-IP read probes returned `RPC HTTP status 403` for program enumeration, including
an explicit MagicBlock L1 probe; Seeker's configured official endpoint succeeded.
Variables differ: host versus Android TLS/parser runtime, outbound route/IP, request
headers and timing. No single cause inferred, no silent endpoint substitution. Negative
fixtures do not prove device outage behavior. No new corrupt-cache/reconnect/signing,
found-Pet/PDA/body, frozen World, wallpaper network roundtrip or endurance verdict.

Workaround debt and triggers:
- Local Android RPC/JSON transport replaces missing accepted std client only here.
  Replace when legitimately installed shared RPC has equivalent Android TLS/strict
  envelope/native consumer proof. No compiler/std worktree edits authorized.
- Legacy/current shared Pet prefix is diagnostic only; lengths never select a body
  decoder. Upgrade gate: accepted program/layout/engine and matching real fixture/PDA
  contract, then version-specific checked body decoding before Home/metrics/signing.
- RPC wire body4MiB/depth32/numeric128, connect10s/read15s, refresh30s. Larger discovery
  requires bounded lookups/pagination contract. In-flight blocking cancellation may
  wait until socket timeout; stale-owner publication still refused. Controlled TLS,
  redirect/truncation, device offline and power/endurance checks remain unverified.
- Nonempty Token-2022 holdings are not SGT eligibility; need checked mint/group/member
  and unclaimed/heir discovery. Zero holdings is sufficient only for this absence
  message, not provisioning. All action/confirmation/operator/ER-ready rows remain open.

## Source-only unsigned/preflight proof — 2026-10-08

User-authorized local client work continues without signing. `OwnerTransaction`
explicit source-profile builders and `prepareSourceOnly` reuse cached official
Solana JVM0.3.1 serialization; `OwnerPreflight.inspectSourceOnly` consumes fresh
blockhash, fee, simulation and block-height RPC through `SolanaRpc`. No send method
or wallet transaction request was added. Protocol owner explicitly confirms no newly
accepted deployed wire/layout/engine/PDA/source-ELF profile. Current source contracts
remain source-only; matching bytes for one action do not certify other old/new actions.

Measured SDK defect, not an assumed missing API: `Message.Builder` omits appended
program IDs from readonly-nonsigner count, and fails to merge a duplicate payer into
writable signer privilege. Initial worker wire fixtures failed5/7; main independently
ran the retained defect fixture and Bank whole-envelope golden. Small workaround uses
SDK `LegacyMessage`/`Instruction` directly for explicit key order/header; SDK still owns
wire serialization and zero-signature envelope. No installed SDK edit. Upgrade trigger:
rerun `OwnerTransactionTest.sdk031BuilderOmitsProgramReadonlyCountAndDoesNotMergeSignerPrivileges`
on dependency upgrade; remove local ordering only after corrected SDK consumer proof.

Main verification `bash /tmp/hibernalCheckRpc.sh`: fresh Kotlin2.2.21/JVM17 classes,
real SDK Android34 JsonReader source, cached org.json/official Solana SDK/kborsh classes:
`OK (20 tests)` in0.309s. Includes8 owner-action wire contracts plus legacy differences,
exact1232-byte boundary, payer/header/zero-signature/alias refusals, uint64/product bounds,
strict simulation errors/logs/units and input bounds, and inclusive expiry/unknown fee.
This is JVM/API proof; normal Gradle local tests still need real Android parser runtime,
not returnDefaultValues. Logs `/tmp/hibernalPreflightFixtures.log`; worker source/API
report `/tmp/hibernalUnsignedReport.md`. No new MetaScript behavior changed, so prior
308-test availability evidence is carried, not rerun for Kotlin-only wire helpers.

Actual compiled `OwnerPreflight` public-read probe, not signing or send:
`/tmp/hibernalSourceOnlyPreflightProbe.kt` → `/tmp/hibernalSourceOnlyPreflightProbe.log`.
Both used source-only canonical Bank, selected remembered owner as zero-signature payer,
known registered **other owner's** Pet and source-derived World address. Deliberately
not an authorized action or runtime-profile acceptance; entire envelope244bytes, all
64 signature bytes asserted zero. `sigVerify=false`, no blockhash replacement.

| Endpoint | Real measured preflight |
| --- | --- |
| Official devnet | blockhash slot508813496; fee context508813497, fee5000; simulation context508813497, error`AccountNotFound`, units0/logs0; last-valid height496049370, observed496049223, not expired |
| ER Asia | blockhash slot748953762; fee context748953765, fee0; simulation context748953770, error`InstructionError[0].Custom:2001`, units1902/logs3; last-valid height748959762, observed748953782, not expired |

No cause for custom2001 inferred, no fee/compute/endurance generalization. Simulation
is nonpersistent and does not prove signer authority, successful action, state delta,
legacy/canonical deployment parity, actual wallet rejection/expiry/retry or UI integration.
Signing/confirmation/admission/operator/live-Pet metrics remain unfinished. New preflight
helpers were not yet separately installed/device-verified at this measurement; render
lane owned concurrent Android build/device slot. Subsequent combined proof follows.

## Admission/member and claim-record proof — 2026-10-08

Same dirty base tree, installed2d7abb082; no sign/send/provisioning/deployment/commit.
`TokenAdmission.heldMint/memberNumber` provides measured local Token-2022 decoding;
`AdmissionDiscovery.read/claimRecordPresent` prevents existing Pet/Paid records from
being counted unclaimed, even when owner-filtered discovery misses a transferred mint.
`GameSync.validateConfig` now checks SDK-derived Config PDA/bump and common304-byte
Config admission prefix. Those source fields match historical511868 and canonical
f1a2a8f trees; this does not certify whole deployed-body/ELF/profile or Claim readiness.
Malformed data remains error/unknown, not absence. No token account is silently chosen
for signing; multiple held accounts remain explicit in diagnostic member data.

Token workaround anchors: installed `std/solana/token.ms` readers and `admitted/claim`
in historical and canonical `program/admission.ms`. Full-u32 COption and complete TLV
validation intentionally reject malformed input more strictly than installed readers;
unrelated extensions remain opaque. Frozen holdings are accepted as source handler does;
no extra decimals/supply business rule invented. Debt trigger: replace local byte decoding
when shared accepted client decoder has equivalent Token-2022/Android consumer evidence.

Independent main check `bash /tmp/hibernalCheckRpc.sh`: fresh current Kotlin compilation,
`OK (45 tests)` in1.16s. Decoder22 fixtures plus existing wire/preflight guards and3
claim-record absence/delegation/malformed tests. C ABI probe passes count-order bounds,
unknown resets, stale-owner/disconnect and invalid-snapshot refusals. MetaScript view
suite reports308tests/16files; member-matched/unclaimed/claimed messages remain explicit
unverified-contract states, never game-ready. Counts travel through existing native
owner-revision snapshot idiom; even admission match leaves SUMMON disabled.

Actual public read probe `/tmp/hibernalAdmissionLiveProbe.kt` →
`/tmp/hibernalAdmissionLiveProbe.log`: Config/mint slot508844317, group
`6jXijzhCm1Njikk3vLTmrw1mjPzWrwKherDYvELgwCpR`, mint
`B9BgHeSaRBgAuwEGtjJ3KWGEWWMZJDqipvvj9Ri3EAha`310bytes, memberNumber24.
Selected owner at slot508844319: holdings0/members0/unclaimed0.
Known public **other owner**6cdG… at L1 slot508844319 / ER749689774:
holdings1/members1/unclaimed0, derived Pet exactlyHEpm… and claim record present.
No owner selection/cache changed for this diagnostic and no wallet was opened.
Positive decoder/PDA/claimed-record proof is not selected-owner admission or actual Claim.

`bash scripts/buildAndroid.sh`:98modules and APK success. SHA256
`662cb1964375fe9aa8c11c6cbb2e66e26cd24ad4a4569626a56bde8c1d7cbbf0`.
Normal Seeker lease21:40:59–21:41:33+07, Home/install-r/app→wallpaper→app, no unlock,
wallet or transaction: app and return retain remembered owner/CONNECT WALLET/disabled
SUMMON and real NoPet/no Token-2022 result; wallpaper retains explicit preview wealth.
Evidence `/tmp/hibernalAdmission{App,Wallpaper,Return}.png`,
`/tmp/hibernalAdmissionBuild.log`, `/tmp/hibernalAdmissionIntegrationFixtures.log`,
`/tmp/hibernalAdmissionViewTests.log`, `/tmp/hibernalGameReadProbe.c`.
This combined APK includes render lane's Step3 lighting WIP; render acceptance belongs
there, not inferred from client build/absence proof. Sourcecampfiremtime21:27:05 precedes
SO21:36:04/APK21:36:19. No final renderer, live-Pet, offline/endurance or transaction verdict.
Render lane subsequently installed898a0330… and reported its own six-frame proof;
its later user-requested zoom correction is separate and still in flight.

## Read-only confirmation preparation — 2026-10-08

`SolanaRpc.getSignatureStatuses/signatureStatuses` prepares confirmation observation,
not send or action success. Signature absent and confirmation unknown remain distinct;
finalized execution errors remain errors. Main51JVMfixtures pass0.58s; six new fixtures
cover widths/canonical64-byte signatures, null/missing/malformed statuses, future slot,
processed/confirmed/finalized distinctions and retained execution failure.

`cd android && ./gradlew :app:compileDebugKotlin` first caught `Unresolved reference
'funkatronics'/'Base58'` despite JVM fixtures: cached fixture classpath included SDK's
runtime-only dependencies, not Android's exposed compile graph. `dependencyInsight`
proved Base58 is inside already-resolved Multimult0.2.6 used by SDK0.3.1; explicit same
version compile dependency in `android/app/build.gradle.kts` removes visibility gap.
Successful Android compile34s proves real consumer imports; no new crypto/runtime
version or handwritten base58. Both initial wrong visibility attempts were discarded.

Actual public read `/tmp/hibernalSignatureStatusLiveProbe.kt/.log`, all-zero64-byte
signature only: L1 context508866837 and ER750226798 both return null. This proves
read-only method/parsing/absence path, **not real signing, send, successful confirmation
or typed state delta**. These helper additions are newer than installed898a0330…;
Android compile and JVM/public RPC proof are not separately installed-device proof.
Existing GameSync/view/native inputs unchanged, so308MetaScript/C evidence reused;
those checks cannot observe newly unused Kotlin confirmation methods.

## Source-body/coherence and display-width preparation — 2026-10-08

`SourcePetRead.decodeSourceOnly` and `SourceWorldRead.decodeSourceOnlyWorld/
decodeSourceOnlyBlockHead` are explicitly source-only, using existing exact
`OwnerTransaction.SourceProfile` trees above. No inferred profile, fallback or GameSync
body/Ready binding. Block head output does not claim its omitted tail is decoded.
Local workaround replacement trigger: accepted shared codec/runtime consumers with
same width/refusal/coherence evidence, not source-IDL shipment alone.

Main independently reviewed worker drafts, made profile selection exhaustive, added
alive=false/unplaced/deathEpoch0 preservation regression, and integrated them.
`bash /tmp/hibernalCheckRpc.sh`:75combinedJVMtests pass0.299s; new13Pet+11World/Block
fixtures include independent whole-source goldens, width boundaries, metadata,
padding/enums/placement refusals. Both Block source layouts are identical, so bytes
cannot distinguish these provenance labels; tests deliberately do not invent such a
refusal. Public keys preserve zero member sentinels; no PDA identity from bytes alone.

Actual public other-owner diagnostic `/tmp/hibernalSourcePetLiveProbe.kt/.log`:
L1 slot508873289 Pet272/delegation owner refuses program-owner check without
normalization. ER750380561 parses historical511868, SDK-derived Pet PDA/bump and
embedded owner/mint match: ordinal6,Vengeful,Block25/seat3,alive=true,diedEpoch0,
lastTick28,hearts8/18,harvest0,burrow2179950569,bonding−22. Explicit canonical304
profile refuses272. These are diagnostic source values, not selected-user live metrics.

Same-context ER `getMultipleAccounts` at750533253, SDK-derived World/Block25/Pet
PDAs+stored bumps and Pet membership/epochs agree. Source World128 epoch28,living413,
placed500,unplaced0,resorting=false,secondsPerDay7200; Block4896 phaseIdle,round1,
cursor10,filled10,crankSeq671. Decoded head440bytes; tail4456bytes still unparsed.
`/tmp/hibernalSourceCoherenceLiveProbe.kt/.log` owns executable probe. Initial probe
incorrectly used LE-u32 Block seed and got null account, not false coherence; pinned
`program/admin.ms:createBlock`/`program/admission.ms:place` and existing layout audit
require LE-u64 despite stored ID beingu32. Corrected SDK derivation matches public
Block25 `2fpaNG6XGo2kFaqVFnFi63qXFa3x15GZR3XKX22ZH7fD`.
No cache/owner selection changed. One coherent snapshot and advancing RPC context
are **not deployed ELF/source/engine parity or sustained game progress**. Protocol
peer still reports no accepted new tuple/client consumer API; todo8 records blocker.

Observed burrow exceeds signedint32, and maxHearts18 exceeds stand-in heart row10.
`home.ms:Home` preview wealth is now uint64 and `gameNumbers.ms:groupedAmount` formats
all unsigned digits; no signed/float narrowing and no live binding. Future hearts
consumer must retain actual max, not cap state to existing preview row. Native300tests,
JS63tests and141-module Home type check pass on installed1064f8c61; existing unused
skillInfo imports warn. Unknown build `--test` flag was rejected; correct JS command
is `msc test native/hud/gameNumbers.ms --target=js`. Formatting preserves old preview
labels/values and groups fullu64max correctly. Existing per-frame string allocation
remains quality debt; no performance claim.

`bash scripts/buildAndroid.sh`:99modules1064f8c61, APK
`15515488d5460820dfe677d879369900393b94076b46d768526b5315c13415bb`, build-only;
no install/device proof. Render lane retained installed5ee3d604… white-light trial and
later unlocked visual proof. Its Return showed honest transport-IOException failure,
not cached absence/success; source/body helpers and native wealth widening not yet
separately device-verified. Subsequent render changes may supersede candidate; rediscover
artifact. Main did not edit renderer paths or unlock device.

Additional forced negative unsigned Claim simulation, public other-owner's **already
claimed** admission: admission discovery unclaimed0, so actual client must not offer
Claim. `/tmp/hibernalClaimSourcePreflightProbe.kt/.log`:376bytes/64zero signature bytes,
source canonical profile, L1 blockhash/fee/simulation slot508883587,fee5000,nonexpired,
error `InstructionError[0,Custom0]`,units25758/logs6. No error-cause inference, signer,
send, successful Claim or runtime parity claim. Diagnostic simulation does not bypass
production duplicate-Claim gate; no wallet/cache/owner changed.

`SourcePetLifecycle.sourceFact` adds source-only returning/dead/heir facts without
publishing runtime state. Pinned `program/admission.ms:claim` writes falsealive and
unplaced sentinels; `place` is configured-authority-only, not an owner Claim retry.
`program/day.ms:dusked` records burial epoch; `dawned` attempts heir after7epochs and
clears death marker only on success. `rules/life.ms:heirOf` retains estate/lineage and
may refuse, so elapsed grace cannot be presented as heir spawned. Classifier distinguishes
unplaced, active first-life/heir, dead-unrecorded and recorded-death; conflicting
active/death or unplaced/death markers refuse instead of silently fixing records.
It neither infers missing epoch/freshness evidence nor schedules Place/Claim/heir/signing.
Main79combinedJVMtests pass0.384s, four added independent decoded-fixture regressions.
Falsealive/zero-marker fact is named `INACTIVE_WITHOUT_DEATH_RECORD`, not a permanent-
death verdict; main rerun79tests0.99s and real Android compile30s pass after that naming.
These helper inputs do not call GameSync/native/UI; no new lifecycle device proof.

Native snapshot stress `/tmp/hibernalGameReadConcurrencyProbe.c`:100000writes with3
concurrent readers using existing `host.ms:gameRead` revision-stability contract;
62089accepted stable snapshots all preserve slots/holdings/member/unclaimed pairing.
Repeat with `clang -fsanitize=thread -g`:91469stable snapshots coherent, exit0/no race
report. These are host C boundary stress checks, not Android JNI/render-thread stress
or process/network endurance. Sequential C probe still owns stale-owner/reset failures.
Second ThreadSanitizer probe `/tmp/hibernalOwnerSwitchConcurrencyProbe.c/.log` adds
50000owner switches and competing publisher/3readers:14074stable owner-bound snapshots
coherent,5953stale publications refused,exit0/no race report. ResetChecking snapshots
retain zero slots/unknown counts; publication snapshots agree with selected raw owner.
Still hostC consumer contract, not real Android wallet/account switch acceptance.

## Parallel coverage integration — 2026-10-09

Three read-only native worker lanes completed under workflow
`8b447002-31f8-4e85-8b17-a49f21fdea84`; main independently reviewed their drafts,
reproduced baseline failures and integrated narrowly sufficient fixes. Evidence uses
base tree `9bdf70e27fb9829ba971d76d4c7c7f3e203647aa` plus dirty HUD inputs fingerprinted
in `/tmp/hibernalParallelConsumerAudit.log`; no commit, deployment or signed transaction.

`GameSync.validatePetPrefix` and `AdmissionDiscovery.claimRecordPresent` own the
identity guards. Same six discovery regressions on frozen baseline:85tests/five
behavioral failures, not compiler failures. Main current-source runner
`/tmp/hibernalCheckRpc.sh`:102tests pass, including those six and17 wallet-boundary
regressions. Actual Android `:app:compileDebugKotlin` passes in17s. Wrong candidate
identity previously affected found/claimed diagnostics only; neither baseline nor
fix establishes gameplay readiness or deployed body compatibility.

`OwnerTransaction.SourceOnlyUnsigned` and `inspectSourceOnlyWalletReturnShape` own
review immutability and returned-envelope binding. Main independently reproduces
baseline getter mutations with unchanged owner metadata using frozen input. Return
shape deliberately accepts a nonzero cryptographically invalid signature fixture:
shape is not Ed25519 verification, wallet authorization or permission to submit.
`OwnerPreflight.observeSignature` records confirmation/expiry facts, not success or
retry permission. Future consumer must bind signature, endpoint, retained attempt
and action-specific typed delta before reporting success. No actual MWA signing or
submission consumer was added.

Native `gameNumbers.heartShare`, `Home.maxHearts` and `hotbar` own display preparation.
`msc test native/hud/gameNumbers.ms`:302native tests/15files; JS:65tests/6files;
`msc check native/hud/home.ms`:141modules pass. Preview seven/ten remains unchanged;
actual18 and255 denominators and invalid-count refusals now have guards. XP text
checks signed32 boundary and uint32maximum. Cumulative source XP still cannot be
bound directly to within-level progress. Kotlin string-only display drafts were
reviewed and independently rerun (six draft tests plus79existing), but not copied:
native consumers already own this presentation, so another unused wrapper adds no
coverage. Inventory remains at the workflow's `consumers-result.md`; no live body,
life/death, stats, reward, shop or interaction acceptance inferred.

Full99module Android build passes. Installed/pulled Seeker APK SHA256
`b6ab0f2a93263d7ecb4701803787db07f90c89339cd14bae5d405c433b6d96da` matches
under normal device lease, with unlocked Hibernal already foreground. Settled capture
`/tmp/hibernalParallelClientSettled.png` shows remembered public owner, CONNECT WALLET,
disabled SUMMON and explicit `CHAIN READ FAILED. PET STATE IS UNKNOWN.` /
`RPC TRANSPORT FAILED: IOEXCEPTION`. This verifies honest failure presentation, not
fresh successful discovery or absence; earlier successful zero-holdings evidence is
historical. Initial capture preceded settled UI and is not final visual proof.
Filtered crash/heart/identity-error scan empty; no endurance, wallpaper transition,
TLS failure cause or real malformed-chain-account device proof. Renderer appearance
retained; no renderer/asset edits. Accepted deployed tuple and separately authorized
real actions remain open gates, not reasons to stop independent client preparation.

Follow-up `SolanaRpcTransportTest` extends existing JVM suite to108passing tests
(0.716s), without production changes. Isolated JVM HTTPS doubles exercise actual
`SolanaRpc.call`: redirect/compression/oversize-header refusal before body reads,
exact4MiB unknown-length stream versus one extra byte, truncation/socket-timeout
refusal, oversized request/write-method refusal before opening, and cancellation
propagation/close/disconnect after a blocked fixture read is explicitly released.
TLS default-object checks are configuration evidence, not real certificate rejection;
this does not prove interruption of a real blocked socket before its timeout.
No APK rebuild needed: only test inputs changed; app/native consumers remain those
in installed b6ab0f. Normal Gradle unit-test runtime was not substituted for the
real-Android-parser JVM runner.

Current-source public read probes also pass the new identity gates. Admission at
L1508902100: selected public owner0holdings/members/unclaimed; other public owner
one holding/member, unclaimed0 and valid claim record; ER751068259. Independently
invoke production candidate validator on public Pet: L1508902354,delegation owner,
272bytes; ER751074308,game-program owner,272bytes; both PDA/bump identity valid,
both bodyAccepted=false. `/tmp/hibernalParallelIdentityLive.log` and
`/tmp/hibernalParallelCandidateIdentityLive.log` retain results. These are host JVM
HTTP reads, not selected-owner cache changes, Android recovery, runtime profile or
wallet/action proof. Host and device differ in OS/TLS/network route, process and
request timing; host success does not diagnose the device IOException. Device later
locked; no unlock, foreground takeover or additional visual acceptance performed.

## Polling decision boundary — relaunch checkpoint

User constraint: “mình đọc state từ on-chain agressive quá thì không được đâu nha,
nó block mình á”. Additional live probes stopped after this warning. Existing
`GameSync.select` still runs full discovery every30seconds; selected-owner empty
admission path performs at least seven requests, including three program-account
queries, per completed cycle. This is a source-traced request budget, not measured
provider capacity or proof that device IOException was a rate-limit response.
No implemented rate-budget fix is claimed.

Client main explicitly asked whether to implement cache/batch/backoff rather than
only increasing the interval. Increasing interval reduces calls but repeats heavy
discovery; caching validated discovery with expiry, batching known-address reads
and rate-limit cooldown/backoff reduces repeated enumeration at the cost of slower
refresh. Stale/unknown must stay visible, and mutable Config must not become
permanent authority through caching. No exact interval/provider quota was accepted.
That question remains unanswered at relaunch; do not reopen live probes or infer
permission from peer messages. Existing APK continues its old poller.

Chain handoff is now available offline at
`/Users/le/metacraft/hibernal-wt-on-chain-ai/out/compilerProbes/er-seeker-release-handoff/chain-seeker.md`.
Main read it, not its executable paths. `Claim` confirmation means pending, not dead
or Ready; placement requires contextual Pet seat, matching Block membership and
World/profile freshness, not operator aggregate counters. Exact accepted deployment
tuple and shared client delivery remain UNKNOWN. The companion `submission-prep.md`
is an inventory/checklist, not release approval or a gameplay acceptance packet.

Renderer owns canonical rules-backed skill-tree UI; artifact is visual inspiration,
not permission for rules/training migration. Its previews and device reports live
in `docs/RENDERER-BRIEF.md` and the renderer lane, not client Ready evidence. Coordinate
before replacing the installed comparison preview. Main did not independently rerun
renderer host checks; unavailable host suites cannot be promoted to green.

