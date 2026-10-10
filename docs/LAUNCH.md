# LAUNCH — beta devnet để nộp, mainnet theo readiness

Quyết định được người dùng chốt 2026-09-30: **nộp một beta/devnet chơi được trong cửa sổ nộp 2026-10-08 → hạn chót 2026-10-12 (người dùng xác nhận 2026-10-09; giờ/múi giờ cutoff chưa xác nhận), trung thực và on-chain thật; mainnet là mốc riêng sau security và vận hành gates.** Không còn ép launch mainnet trong ba ngày để chừa thời gian review Store.

Đổi thời điểm phát hành tiền thật, không bỏ mục tiêu game online/on-chain AI, không cắt luật game và không tạo một implementation demo riêng. Phạm vi launch là toàn bộ `BRIEF.md` §7.1; phần chưa làm là nợ, không phải "sau hackathon". D38 vẫn áp dụng khi launch mainnet: `$HBRN` là token thật từ ngày launch, chỉ program mint và L1 kiểm tra outflow. Beta dùng tài sản devnet được ghi rõ là thử nghiệm.

## 1. Hai đích đến và đường găng

**Mốc A — submission:** giám khảo cài APK trên Seeker, kết nối MWA, vào game devnet/ER và trải nghiệm pet tự sống khi app đóng. APK, repo, demo và pitch phải truy cập được trước deadline.

**Mốc B — launch:** cùng game qua verification tiền thật và recovery, deploy mainnet được người dùng duyệt, vận hành ngoài máy phát triển rồi mở cho người chơi.

```text
Chốt ABI + compiler chứa lane A
             ↓
Game program: admission → lifecycle → AI → VRF → settlement
             ↓
APK Seeker/MWA + game online thật trên devnet/ER
             ↓
Freeze beta → demo/repo/pitch/APK → nộp ngày 8       [Mốc A]
             ↓
Security/recovery/mainnet preflight → canary → launch [Mốc B]

App/device và ops chạy cùng chain ngay từ đầu.
Mainnet deployment và Store approval không chặn Mốc A.
```

**Điều lệ đã kiểm tra 2026-09-30:** [CLOCK IN Terms & Conditions](https://solanamobile.radiant.nexus/legal/clock-in-terms.pdf) §6.3–6.4 yêu cầu APK functional, Solana Mobile Stack/MWA, tương tác Solana có ý nghĩa, GitHub repo, demo và pitch; không quy định cluster mainnet. §8.1 chấm stickiness/PMF, UX, innovation và presentation/demo, mỗi mục 25%; không yêu cầu đã có traffic hay chứng minh PMF trước khi nộp. [Website/FAQ chính thức](https://solanamobile.radiant.nexus/) nói không phải publish trên Store trước deadline.

§9.3 yêu cầu đội thắng giải thuộc điều kiện publication phải **publish/list/public trên dApp Store trong 30 ngày lịch sau công bố người thắng**; chỉ nộp review không tính là publish. [Hướng dẫn Store](https://docs.solanamobile.com/dapp-store/submit-new-app) ghi review 3–5 ngày làm việc. Chuẩn bị publisher/release key và KYC khi cần, nhưng không dùng thời gian review làm lý do ép mainnet trước ngày 8. Không coi điều lệ không ghi mainnet là bảo đảm mọi beta đều hợp lệ: beta vẫn phải đáp ứng các yêu cầu functional/mobile/network và mọi điều kiện track áp dụng.

Tiền lệ được truy xuất bằng Colosseum Copilot 1.2.1 ngày 2026-09-30: [Maneko Pet](https://colosseum.com/projects/explore/maneko-pet), game Tamagotchi mobile, đạt hạng 5 Gaming ở Renaissance (tháng 3–4/2024); submission tự mô tả “everything is running smoothly on the devnet” và dự định go live hai tuần sau. Tiền lệ này ủng hộ việc nộp sản phẩm beta chạy thật, không chứng minh CLOCK IN dùng cùng luật hoặc beta chắc thắng. [Alliance — 20 Lessons for Crypto Founders](https://alliance.xyz/essays/lessons-for-crypto-founders) mục 4 khuyên kiểm chứng luận điểm bằng sản phẩm dùng được; đây là lý do tập trung consumer/game loop, không phải lý do bỏ on-chain AI hay phát hành tiền thật chưa an toàn.

## 2. Điểm xuất phát — đã chứng minh gì, chưa có gì

| Phần | Bằng chứng / giới hạn tại thời điểm lập kế hoạch |
|---|---|
| Rules và brain | Luật dùng chung, model đã train; bảng đánh giá engine hiện tại ở `ON-CHAIN-AI.md` §6 package 5f. `p29s5` là ứng viên được khuyến nghị, chưa phải lựa chọn đã được người dùng duyệt. |
| AI trên SBF/ER | Inference, observation, apply economy/node và lựa chọn attack đã đo; `SOLANA.md` §7 và `ON-CHAIN-AI.md` §6 package 6 giữ phép đo. Tick dawn có bằng chứng trên build lane A; chưa phải tick trong production game program trên mainnet. |
| Probe không phải game hoàn chỉnh | `tools/actBench.ms` `actTicked` trả lựa chọn attack, **không** request VRF/settle trận; `appliedEconomy` dùng seed trong `ActContext`. `tools/fightProbe.ms` chứng minh VRF riêng. Hai đường chưa ghép thành vòng game production. Context, thời gian, persona, market và entropy phải lấy từ trạng thái/nguồn được program xác minh, không từ fixture do client viết. |
| Compiler | A/B tips đã đọc refs: `bca987c4` (bug639), `51a0426e` (bug640/641), worker báo queue sau train6. C **HOLD lại** tại `50b08cf8`: worker rút kết luận parity-complete vì `Span<Pet> → Ptr<Pet> → Ptr<void> → Ptr<uint8>` lọt guard JS, C in `1` nhưng JS `[object Object]`; cần sửa invariant reinterpret, không chỉ direct-span case. Chưa có lane land/sync verdict. Installed `BUILD` lần cuối kiểm tra 2026-09-30 vẫn `013853dd`. A vẫn chặn tick trên compiler cài đặt. |
| std/solana | Local recompiler `main` đã được đọc ref tại `2886f553`; card std ngày 2026-09-30 báo land `da675b66..2886f553`, gồm return data, multi-account commit/VRF/task, delegated fee payer, host và token byte layer. Chưa sync vào installed `013853dd`, nên Hibernal chưa dùng được các API đó. Tip std riêng `28f20737` chưa land. Hydra, `std/bytes`, arithmetic đã được quyết để làm; typed account/client surface vẫn còn việc. Không coi “đã giao 17 việc” là “đã ship 17 việc”. |
| Game program | Worktree này chưa có source `program/`; main checkout chỉ có output probe trong `program/out/`. Chưa có game program production để deploy. |
| App Hibernal | `android/` và `native/` trong main checkout được đọc trực tiếp và đang trống. Chưa xác minh APK Hibernal có MWA + game RPC ở repo/worktree khác. Điều này không phủ nhận renderer/library có thể đã được làm nơi khác; cần nhập đúng artifact và chứng minh đường app thật. |
| Vận hành | Day probe devnet đã chạy 50/50 acts, byte-perfect, theo `SOLANA.md` §7 item 2; cranker chạy trên Mac của người phát triển. Không chứng minh service production tự restart hoặc mainnet validator/Hydra đang phù hợp. Devnet hiện đã teardown. |

Smoke local chạy lại 2026-09-30, **không gửi network transaction**: trong `/tmp/hibDawn`, `ZIG_GLOBAL_CACHE_DIR=/tmp/zigCacheHibernal node tools/chain/actLiteSvm.mjs out/actProbe.so /Users/le/metacraft/hibernal-wt-on-chain-ai/train/checkpoints/p29s5.policy`. Dùng `.so` đã build bằng lane A `420dbac4`, host fixture được harness tạo bằng installed `msc` `013853dd`, LiteSVM limit 1.4M CU. Typical/busiest/dawn lần lượt 367,691 / 487,494 / 659,090 CU, choice/digest khớp và 0/1,984 byte khác host; day 50/50 acts, 0 choice và 0 byte khác. Đây là baseline của probe, không phải full-game VRF/payout gate, không phải so tốc độ hai compiler.

Định danh baseline tại close-out 2026-09-30: source tree của revision lane A `420dbac4` là `71ab2d8baf0de05ecf8fc878b25f946ad2a20cfe`; source tree installed revision `013853dd` là `863a66e40b23fb35917c192c3ba9c0bff74d5f5e`. SHA-256 của `/tmp/hibDawn/out/actProbe.so`: `93a6bcd4934381636ebee4f932baa13f6249c7e4360d7a202fef088ff8949ae4`; của `train/checkpoints/p29s5.policy`: `b6c9be05f955ad585956d5f510a22f1d53d516c1bf58c0515a8947cae4b288a1`. Đây là identity của probe/artifact đã đo, không phải release production.

`ROADMAP.md` giữ danh mục dài hạn; nhiều hàng vẫn là kế hoạch tháng 9, kể cả heuristic fallback. Trong khung này dùng các gate dưới đây, không suy trạng thái từ các ước lượng cũ. **Không thay on-chain AI bằng heuristic/off-chain quyết định để giữ lịch.**

## 3. Deploy những gì và trách nhiệm ở đâu

**Đề xuất: một Hibernal program ID, deploy trên Solana L1; cùng code được ER dùng để thực thi trên account đã delegate.** Không cần tự dựng một program AI thứ hai chỉ vì brain chạy trong ER. Bản deploy phải chứng minh ER nhìn thấy đúng bytecode; không suy từ các probe devnet.

| Surface | Trách nhiệm cần hoàn thành |
|---|---|
| Hibernal trên L1 | Init/config authority; SGT admission và registry duy nhất theo mint; tạo/delegate state; SKR shop và receipt; callback undelegate; ledger chi trả và `$HBRN` mint; kiểm tra mọi khoản rời game. |
| Hibernal trong ER | Tick/emission; observation/inference; economy/node; attack, talent và item randomness qua VRF; settlement, replay, market, bonding/gift, death/heir; owner actions; kiểm tra lịch act và replay protection. |
| Account giữ trên L1 | Policy được xác thực và cập nhật bởi authority; admission/identity mapping theo layout đã chốt; cấu hình giới hạn outflow và paid ledger không delegate; purchase receipts nếu dùng đường L1 → ER. |
| Account delegate | Game state theo layout đã chốt, gồm block/pets, market/replay/pending state và global reward state. Mọi state một transaction ghi phải ở **cùng một ER**. |
| Hạ tầng có sẵn | System, SPL Token/Token-2022, MagicBlock delegation/magic/VRF/Hydra, session program nếu dùng. Xác minh ID, version, validator và quyền ở cluster thật; không deploy lại chúng như program của Hibernal. |
| Service do đội vận hành | Hydra cranker/sponsor, RPC read/routing, health monitoring và thủ tục recovery. Service kích hoạt instruction, không chạy brain hoặc chọn hộ pet. |
| Seeker app | Native renderer/HUD + Kotlin shell/MWA, đọc account theo ABI, ký owner transaction và hiển thị outcome thật. Không dùng dữ liệu sim thay trạng thái online. |

Library/compiler work làm ở session của tầng đó. Hibernal viết các constraint của game trên byte API hiện có, dùng `BRIEF.md` §5.7 làm security contract; không tạo một SDK tổng quát thứ hai. Khi helper upstream land/sync thì port caller và bỏ stand-in. Không đưa các tối ưu không chặn launch vào đường găng.

## 4. Blocker hiện tại — tập trung cho beta trước

| Ưu tiên | Blocker | Việc mở khóa / tiêu chí đóng |
|---|---|---|
| **B0** | Chưa chốt ABI/layout chung cho program và app | Người dùng chốt bước 0. Full Block một account (7,336 byte) đã đo act, commit, claim từ slot trên devnet ngày 2026-09-30 (`SOLANA.md` §7 item 16); layout vẫn chờ chốt. Không bắt đầu `program/` trước câu trả lời layout. |
| **B1** | Chưa có game program nối AI/VRF/settlement | Hibernal chain ghép state machine game; không chỉ đổi tên/copy probe. Core loop chạy qua APK trên devnet. |
| **B2** | Installed compiler chưa nhận tick fix | Recompiler/merge-train full gate → land → sync A; Hibernal pin và remeasure. Không bỏ gate hoặc tự nhắn đổi ưu tiên queue. |
| **B3** | APK/MWA/live-state consumer chưa chứng minh | App owner nhận artifact renderer nếu ở nơi khác, hoàn thành native RPC/ABI và Kotlin/MWA; APK chạy trên Seeker, không chỉ simulator. |
| **B4** | Game chưa tự vận hành ngoài laptop | Ops chạy supervised Hydra cranker trên devnet, kiểm restart/catch-up/pending VRF; app đóng mà pet tiếp tục, service restart không lặp lượt. |
| **B5 — mainnet gate** | Tiền thật và cluster mainnet chưa được kiểm | L1-only limits/paid ledger, adversarial/differential verification, recovery, authority/funding/network preflight. Không phát hành tiền thật trước khi green; thực hiện cùng đường code đã thử trên devnet. |

Không chờ language design mới, LTO/memset tối ưu, retrain hoặc chỉnh balance để nối game. Lỗi ảnh hưởng đường đang dùng, authorization và kiểm tra balance/counter không được che bằng nhãn “beta”.

## 5. Step by step trước ngày 8

Các mốc là checkpoint, không phải cam kết đã đủ thời gian. Chờ upstream/ABI vẫn tiêu vào cửa sổ hiện tại. Nếu trễ, báo hạng mục thực tế; không âm thầm hạ beta thành idea, bỏ tính năng hoặc giả outcome.

### Bước 0 — freeze contract và giao owner ngay

Owner: người dùng + một integration owner giữ ABI/release manifest. App và ops bắt đầu cùng chain, không đợi game program viết xong.

Cần chốt trước production code:

1. Đề xuất một ER + global reward state ở ER đó; block vẫn 10 pet theo luật. Không chia nhiều ER.
2. Pet trong Block hay account riêng; vị trí market/replay/pending và mapping admission mint → block/slot. Đo **full Block**, không gọi bundle pet ~2 KB là toàn Block: đề xuất một account đã đo ở `SOLANA.md` §7 item 16. `rules/layout.ms` là game value layout, không tự mang owner/SGT/header production.
3. Header/discriminator, version, seeds, encoding, account order và signer/writable roles; thống nhất với đề xuất Anchor-compatible 8-byte discriminators của std. Chưa được duyệt thì chưa freeze.
4. Time/round/turn order; persona/grudge/market lấy từ state; semantics pending VRF, action resumption, stale callbacks, late/duplicate triggers.
5. Đề xuất policy `p29s5`, pin engine/format và quyền update; lỗi mismatch fail loud. Không tự retrain/đổi rule để né mismatch.
6. Token/outflow contract dùng chung: đề xuất SPL Token theo đường đã đo, mint khi gift claim, không cho owner rút burrow. Beta dùng test `$HBRN`/SKR và DevAdmission; mainnet giữ D38 và kiểm SGT thật. Mainnet caps per-owner/global phải chốt trước phần tiền thật, không lấy cap demo làm economics.
7. SKR treasury/token program và purchase receipt → ER consume đúng một lần. Mainnet IDs/admission groups không được lẫn với test config.
8. Đề xuất Hydra; ops host, sponsor/fee payer, authority/ngân sách devnet. Gameplay không tự commit (D21), claim trigger commit; weekly backup commit vẫn là quyết định riêng chưa chốt.
9. Owner/session authorization, emergency controls và recovery; người giữ upgrade/config authority theo D15. Control mới là proposal cần duyệt, chưa tồn tại chỉ vì có runbook.

Gate: ABI versioned được duyệt; owner chain/app/ops thực; có Seeker và release signing key; upstream A có đường gate/land/sync. “Ok” cho hai mốc release không thay câu trả lời các quyết định kỹ thuật còn mở.

### Bước 1 — compiler sync và account layout được chứng minh

Owner: compiler/merge-train cho upstream; Hibernal cho consumer gate.

- Khi synced compiler chứa A: đưa tick vào probe, lỗi tick có tên riêng, bỏ `ticked` thừa; remeasure typical/busiest/dawn cùng compiler. Chạy `out/gate.sh` với `ZIG_GLOBAL_CACHE_DIR=/tmp/zigCacheHibernal`.
- Đo full layout/commit/claim từ slot, account size/rent, CU và byte equality host/SBF/ER. Budget phải tính production instructions, không suy từ riêng inference.
- B/C sync thì nhận fix; chuyển odds table/scalar knobs vẫn cần phê duyệt rule-file như cũ, không trở thành điều kiện của beta.

Gate: pinned compiler, rules suite/native-JS determinism green; dawn byte-perfect; full Block commit được; transaction/callback CU nằm trong budget.

### Bước 2 — nối game program và APK theo ABI

Owner: Hibernal chain + app/device. Mục tiêu checkpoint khoảng **2026-10-03: core loop tích hợp chơi được trên devnet**, không phải mainnet launch.

- Game account/guard/instruction layer trên rules hiện có: config, admission uniqueness/owner, block assignment, claim/delegate, policy và lifecycle. DevAdmission là token test được ghi nhãn, không giả là SGT mainnet.
- `act` lấy clock/context hợp lệ từ chain, xác thực caller/schedule, không chạy cùng pet/round hai lần; wild pets và observation xây trong program, không nhận fixture tin cậy từ client.
- Nối economy/node/attack, food/bank, items/market, owner feed/talk/shop, gifting, reward accounting, death/heir. Layout change không được làm mất admission mapping.
- Attack policy → reserve/lock → pending VRF → verified callback → settle hai pet/global/block/replay một lần. Talent/item mint cũng dùng VRF, không client seed/slot-hash fallback. Kiểm mutation khi pending, stale/out-of-order callbacks và recovery.
- Native RPC/decoder dùng ABI thật; Kotlin/MWA connect/sign/cancel/reconnect; app đọc pet/neighbor/records từ ER. Nhập renderer artifact đúng repo nếu đã có, không tự đổi stack.

Gate: cài APK trên Seeker → MWA → claim test → delegate → scheduled AI → VRF settlement → state/replay trên điện thoại. App đóng mà pet tiếp tục. Inference benchmark và video fixture riêng không đạt gate này.

### Bước 3 — test-token boundaries và vận hành beta

Owner: chain/security + ops + app. Mục tiêu checkpoint **2026-10-04 đến 2026-10-05**.

- Test SKR purchase/receipt → game effect đúng một lần; gift → commit không undelegate → L1 claim → test `$HBRN`. Cùng constraint và state machine dự định dùng mainnet; không hardcode “success” cho demo.
- Giữ paid ledger/limits trên account không delegate. `SOLANA.md` §7 item 7: ER validator có thể commit bytes tùy ý; `paid` chống trả lặp nhưng không chứng minh earned đúng. Thử forged state, owner/destination/amount sai, duplicate claims và bounds độc lập per-owner/global.
- Guards theo `BRIEF.md` §5.7, signer/PDA/owner/version/length/writable/duplicates/CPI IDs, callbacks/receipts replay, overflow và admission reclaim. Differential model/native/LiteSVM trên program thực với cùng VRF outputs, clock jumps, market/death/heir; UBSan theo contract, không chỉ rules tests.
- Supervised Hydra cranker ngoài laptop; restart không tạo crank/lặp action; thử RPC outage, app offline, pending VRF và epoch/round boundary. Alert age của act/pending/commit và người nhận support.
- APK phân biệt pending/confirmed/stale/error; owner thao tác khi delegate vẫn đúng, cache không quyết định game. Wallpaper/lifecycle/replay dùng state thật.

Gate: beta phục vụ được người test/giám khảo mà developer không bấm hộ mỗi lượt; restart không double-settle/payout; test tokens và limitations ghi rõ. Mainnet money gate vẫn riêng, không tự đánh dấu green bằng test run này.

### Bước 4 — freeze beta và đóng gói submission

Owner: integration + app + người dùng. Mục tiêu **2026-10-06 đến 2026-10-07**, không để ngày 8 thành ngày sửa core loop.

- Freeze compiler/program/ABI/policy/config; archived `.so`/policy/APK hashes, engine, program/test-mint IDs, endpoints và authorities dạng public key. Checkpoints đang ignored phải thành release artifact bền vững, không chỉ `/tmp`.
- Signed APK cài trên Seeker, fresh wallet/test admission onboarding; hướng dẫn judge lấy test tokens, RPC/ER và các thao tác. Không đưa private keys operator vào APK/repo/log.
- Clone/build/run instructions và source repo truy cập được; đúng commit là bản APK được quay demo. Liệt kê các tính năng đang chạy và còn thiếu, không gọi beta là production.
- Demo khoảng ba phút theo website: mở app/wallpaper → MWA → pet tự act → VRF fight/replay → owner interaction/test-token claim; pitch giải thích khác biệt và con đường mainnet. Accelerated devnet epochs phải ghi nhãn.
- Giữ deployment/devnet cranker/RPC phục vụ sau deadline cho technical review, có owner/funding/restart; không teardown sau khi quay video.

Gate: người khác cài APK và tự đi qua game được, repo/release artifacts truy cập được, demo/pitch trung thực và reproducible. Traffic/PMF thật có thể bổ sung bằng chứng nếu có; không phải lý do trì hoãn nộp và không được bịa metrics.

### Bước 5 — nộp trước hạn chót 2026-10-12

Owner: người dùng/team representative.

Nộp functional APK, GitHub repo, demo và pitch theo portal/giờ cutoff của ban tổ chức; giữ submission receipt và kiểm quyền truy cập mọi link. Không giả định deadline là cuối ngày theo giờ local. Store review/publish và mainnet deployment **không** chặn việc nộp beta này.

Gate: bộ hồ sơ đủ, truy cập được trước cutoff; app/backend devnet tiếp tục phục vụ verification. Chỉ idea/slides/probes rời không được coi là submission đã hoàn thành.

## 6. Sau beta — launch mainnet khi sẵn sàng

Không gán ngày launch chắc chắn trước khi biết kết quả các gate. Tiếp tục trên cùng code, không rewrite game hay đổi brain sang server.

### M0 — đóng security và vận hành gates

Owner: Hibernal security/integration + ops.

Review program cuối và toàn money path: SGT mainnet identity/ownership, SKR mint/treasury, emission/growth/gift bounds, L1-only config/caps/paid ledger, CPI authority, arithmetic và reinit/duplicate/replay. Chạy adversarial/differential/UBSan và recovery/upgrade rehearsal trên layout cuối. Khắc phục mọi red liên quan; quyết external audit vẫn phải có người dùng chốt.

Xác minh mainnet RPC/ER/VRF/Hydra deployments và validator identity, code/policy visibility, full sizes/CU/rent/deploy-buffer funding, sponsor service, permissions và emergency controls đã tồn tại thật. Testnet không thay bằng chứng mainnet (`SOLANA.md` §7 item 14).

Gate: không còn blocker authorization/settlement/outflow/recovery; limits không tin tùy ý state ER. Beta deadline không miễn gate này.

### M1 — mainnet deploy và canary có phê duyệt

Owner: người dùng duyệt transaction plan, chain + ops thực thi.

Người dùng xác nhận cluster, program/mint IDs, funding, fee payer, upgrade/config/mint authorities và giới hạn chi; simulate trước khi gửi. Deploy/init program, policy, L1 ledgers và `$HBRN` thật, zero pre-mine theo D3/D38. Cùng program ID chạy game trong ER.

Seeker thật → SGT → delegated pet → AI → VRF → settlement → owner gift → L1 token; observe epoch boundary, restart và confirmation. Canary/capacity rollout cần người dùng duyệt, không âm thầm cắt scope game. Red thì dừng mở rộng.

Gate: state/money/permissions đúng, đủ CU, schedule/recovery hoạt động; chạy khi laptop tắt.

### M2 — public launch và Store

Owner: app + ops + người dùng.

Signed release APK trỏ mainnet được thử trên Seeker; mở game theo capacity đã đo, alert/support/funding/runbook có hiệu lực. Chuẩn bị publisher/KYC, metadata, screenshots/privacy/support và nộp Store release-ready; không nộp placeholder.

Nếu thắng CLOCK IN, track đúng mốc §9.3: **publish/list/public trong 30 ngày sau công bố người thắng**. Được duyệt/publish là gate bên Store; submission receipt không thay thế nó. Bắt đầu quy trình đủ sớm cho review/sửa, không mặc định có gia hạn.

## 7. Owner và quyết định tiếp theo

| Lane | Đường găng beta | Phần mainnet tiếp tục sau beta |
|---|---|---|
| Compiler/merge-train | A full gate/land/sync; lỗi đường consumer thực | Không ép language design/tối ưu không cần thành blocker |
| std/solana | Minimal primitives game cần, ABI Pubkey thống nhất | Nhận các API đã land và bỏ stand-in; không dựng SDK thứ hai ở app |
| Hibernal chain | Game program + AI/VRF/lifecycle + test-token flows | Security/outflow mainnet và deployment |
| App/device | Seeker/MWA/native RPC/HUD/wallpaper và APK beta | Mainnet release config + Store |
| Ops/submission | Devnet service/restart/support, judge onboarding, demo/receipt | Mainnet preflight/service/funding/canary và publisher |

Các lane cần owner thực; thêm agent không thay thế ABI, consumer verification hoặc thiết bị. Chưa xác minh owner/artifact nào thì báo rõ, không mặc định đã có app ở repo khác.

**Mở khóa ngay:** câu trả lời layout/ABI ở bước 0; owner/artifact app và ops host; lane A gate/sync. Model, một ER, Hydra, token/caps/emergency design vẫn là các quyết định còn mở theo card; chấp thuận beta trước không tự duyệt chúng.

Quyết định 2026-09-30 chỉ duyệt tách hai mốc và thay ưu tiên submission. Không authorize commit/push, mainnet transaction, rule/reward change, program layout chưa được chốt hoặc nhắn merge-train đổi ưu tiên. Cập nhật “done” bằng output/artifact thực, không bằng nhãn beta hay lời báo một lane.
