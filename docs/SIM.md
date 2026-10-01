# SIM — dùng simulation để quyết định game

> Sim (`sim/` trên `rules/`) dùng để trả lời ba câu cho từng feature: có cần không, có tạo ra cảm giác mong muốn không, thông số đã tối ưu chưa. Mỗi case ghi: trạng thái, tâm lý mong muốn, luật và hệ thống ảnh hưởng, chỉ số, số đo hiện có, câu hỏi còn mở. Số đo AI ở `ON-CHAIN-AI.md` §6.
>
> Trạng thái luật: **Có trong code** · **Chốt hướng** (user đã quyết, chưa code) · **Đề xuất** · **Mở** (cần user quyết).
> Trạng thái đo: **Đo được** · **Chưa đo** · **Chưa có trong sim** (thiếu hệ thống để đo).

---

## 0. Kiến trúc: sandbox và env train

- Chốt hướng: tách simulation đầy đủ (sandbox) khỏi env train; thêm dần mọi concept của game vào sandbox, từng bước.
- Chốt cách chia:
  - `rules/`: lõi luật chung, chạy cả trên chain; nguồn sự thật duy nhất.
  - Sandbox: thế giới đầy đủ (đồng hồ thời gian thực, các kiểu chủ, SKR, bonding, item, chợ, wild pet), dùng để trả lời câu hỏi thiết kế và tune; chậm cũng được, log đầy đủ; brain là hộp đen (teacher hoặc policy int8). Là một lớp mới trên `World` (`sim/world.ms`); user đồng ý mở và đầu tư.
  - Env train (`sim/env/`): chỉ những gì pet thấy khi `act`; chủ và thời gian thực thu gọn thành sự kiện ngẫu nhiên có phân phối đo từ sandbox; giữ tốc độ batch.
  - Hai phía chung `rules/` và `act`; policy train xong phải sống qua sandbox mới được tin.
- Thứ tự chốt: A (inventory đồ ăn, quota, đồ ăn khởi đầu) → C3 (luật đánh mới) → khung sandbox (đồng hồ, chủ) → B (bonding, ROI).

## H. Bảng sức khỏe — Có trong code · Đo được

- Lệnh: `cd train && uv run python health.py --policy teacher|<checkpoint> --worlds 8` (mọi ghế do một bộ điều khiển chơi, 120 ngày, seed 9001). Mỗi dòng là một chỉ số, mục tiêu và nguồn (BRIEF §6 hay mục của file này). Bộ đếm nằm trong `sim/env/feel.ms`, nên teacher và policy được đo bằng cùng một đoạn code.
- Mục tiêu do agent đặt từ lời văn của BRIEF và file này (đề xuất, chờ user xác nhận): cấp 10 ở ngày 5–10, cấp 20 ở ngày 24–40; tiền ăn ở cấp 20 bằng 60–70% thu nhập; của cải p90 / trung vị 2.0–3.2, p99 3–5, top ≥ 10; pet sinh từ ngày 60 có ≥ 5% vào nhóm 25% giàu nhất; trung vị của cải giữa hướng giàu nhất và nghèo nhất ≤ 1.5 lần; trận dưới 40% odds ≤ 1%; nhận ra persona ≥ 0.9. Các dòng "info" chưa có mục tiêu.
- Ghi chú đo: của cải lấy lúc hết episode trên pet còn sống, nên hai ghế sinh muộn nhất (8, 9) thường vắng vì pet đời đầu vừa chết già mà heir chưa về.
- Sau đợt tune 2026-09-25 (teacher, 8 world, engine `14630790477522747314`, commit `831d328`): lệch 4 dòng, hai dòng chỉ sát mép — tiền ăn ở cấp 20 là 58.9% (mục tiêu 60–70), chênh của cải theo hướng 1.55 (≤ 1.5); top thu nhập 3.75 và của cải 3.59 (cần items); nhận ra persona 0.87 (≥ 0.9). 22 chết đói (1.3 trên 100 đời), 0 khi còn tiền. File thô `out/health/teacher.9ac9401.txt` trong worktree on-chain-ai.
- Lần đo đầu (teacher, 8 world, engine `8940418975996108247`): lệch 6 dòng. Cấp 20 ở ngày 16; tiền ăn ở cấp 20 bằng 14% thu nhập; p90 / trung vị 3.45, top 4.6; của cải theo hướng xuất phát chênh 4.3 lần; nhận ra persona 0.86. Kẻ cướp lấy 57% thu nhập, Worker Greedy và Vengeful mất 92–93%.

- Bộ dò (S2, `train/tune.py`, 2026-09-25): mỗi biến thể vá knob `export const` trong một bản sao cây code và build lại, chấm bằng các dòng có mục tiêu của bảng này: tổng khoảng cách ra ngoài dải mục tiêu ÷ mục tiêu (dòng gate phạt ×10), dò lần lượt từng knob. Chưa chốt knob nào được dò và trọng số: mặc định mọi dòng trọng số 1.
- Lần dò đầu (teacher, 4 world, seed 9001, engine `1622489765003688175`): giá ăn 90–135%, offset trọng số 20–50, giá mint 400–800. Tốt nhất: giá ăn 135%, offset 50, giá mint 400, điểm 2.84 → 2.01, còn lệch 4 dòng (top của cải 3.8, top thu nhập 4.0, chênh của cải theo hướng 2.6, persona 0.86); tiền ăn ở cấp 20 và p90 / p99 của cải vào dải. Offset 20–30 luôn tệ hơn (chênh theo hướng xuất phát). Kiểm lại trên 8 world, seed 4242: tiền ăn 52 → 66% thu nhập, của cải p90 1.64 → 2.10, nhưng chết sớm 1.53 → 3.40 trên 100 đời (chết đói 24 → 56; chủ chăm 0 → 0, thỉnh thoảng 0.66 → 2.85, bỏ mặc 3.79 → 6.49); 0 chết khi còn tiền. Tức là dải tiền ăn 60–70% đổi bằng số pet chết đói — cần user chọn mức chết chấp nhận được (A7). Chưa áp dụng. File thô `out/tune/first.tsv`, `out/health/teacher.tuned.4242.txt`, `teacher.default.4242.txt`.
- Lần dò thứ hai, thêm trần chết sớm ≤ 2 trên 100 đời (`--limit`, trần do agent đặt): tốt nhất giá ăn 120%, offset 50, giá mint giữ 600. Kiểm trên 8 world, seed 4242, ba mức (A mặc định · B giá ăn 120% + offset 50 · C giá ăn 135% + offset 50 + mint 400):

| | A | B | C |
|---|---|---|---|
| Chết sớm / 100 đời (chủ chăm · thỉnh thoảng · bỏ mặc) | 1.53 (0 · 0.66 · 3.79) | 2.18 (0 · 1.88 · 4.18) | 3.40 (0 · 2.85 · 6.49) |
| Tiền ăn ở cấp 20, % thu nhập (mục tiêu 60–70) | 52.0 | 59.4 | 66.1 |
| Của cải p90 / p99 / top so với trung vị | 1.64 / 2.23 / 3.28 | 1.85 / 2.55 / 3.05 | 2.10 / 2.99 / 4.17 |
| Thu nhập top so với trung vị | 5.68 | 4.90 | 5.06 |
| Của cải trung vị, hướng giàu nhất / nghèo nhất | 2.72 | 2.43 | 2.34 |

  `sim/builds.ms` ở mức B (4 seed): chết sớm toàn bộ 6 → 7%, Glass Cannon 10 → 13%, Tycoon 11 → 15%, Bulwark 10 → 7%; keystone yếu vẫn yếu. Đề xuất của agent: B nếu chấp nhận chết sớm ~2 trên 100 đời (toàn ở chủ thỉnh thoảng và bỏ mặc); giữ A nếu "never starves" (§6.1) là cứng. Chưa áp dụng. File thô `out/tune/capped.tsv`, `out/health/teacher.capped.4242.txt`.
- User chốt 2026-09-26: tỉ lệ tiền ăn trên thu nhập không quan trọng, bỏ mục tiêu 60–70%, giá ăn giữ mức A. Điều quan trọng: pet làm ăn tốt phải dư tiền; pet chết đói nên vì bị cạnh tranh, bị cướp, hết tài nguyên, không vì đồ ăn đắt. Dòng tiền ăn ở cấp 20 thành info.

## A. Sinh tồn: đói, tim, đồ ăn

### A1. Đói mất 1 tim mỗi ngày — Có trong code · Đo được

- Tâm lý: cái chết chậm, thấy trước, tránh được (D10); nỗi sợ là chính cái chết (A5).
- Luật hiện tại: `tickTo` (`rules/life.ms`) trừ 1 tim mỗi ngày; ba ngày newborn chỉ đói ngày cách ngày (`hungerOn`, `rules/emission.ms`); ngày chết già không đói. 0 tim là chết: ví chia 50% cho hàng xóm, 50% đốt.
- Quyết định: giữ 1 tim/ngày cho mọi pet, **bỏ ngoại lệ newborn** (xem A2).
- Đo được: xem A6.

### A2. Newborn được bảo vệ bằng đồ ăn khởi đầu — Có trong code · Chưa đo riêng

- Tâm lý: người mới không chết oan trong mấy ngày đầu, nhưng vẫn học luật đói ngay từ ngày 1.
- Luật: thay `hungerOn` bằng một phần đồ ăn sẵn trong inventory lúc claim. Luật đói không có ngoại lệ, chỉ thêm một item.
- Cần: inventory đồ ăn (A4). Khiên chống bị đánh 3 ngày (§3.2) vẫn giữ.
- Chốt: mỗi ngày trong 3 ngày khiên, hệ thống thả 1 phần Small vào một slot riêng, không tính vào quota x; hết hạn như mọi đồ ăn khác (A4).

### A3. Ăn ở sàn và ăn chủ động — Có trong code (theo A4)

- Ăn ở sàn: lúc tick, nếu mất tim sẽ làm tim xuống dưới `pet.minHearts` (mặc định 2) và burrow đủ tiền một bữa Small, tick trừ tiền bữa Small và **không mất tim**. Không có shop hay inventory: đồ ăn là một khoản trừ tiền. Đây là lưới an toàn thụ động; pet không phải quyết định gì.
- Ăn chủ động: hành động `eat` của brain trong `act`, chọn Small/Medium/Large (+1/+2/+3 tim, không vượt max). Giá `foodCost` = {8, 15, 21} × (20 + level)/20 `$HBRN`, bữa lớn rẻ hơn tính theo tim. Mỗi lượt `act` một hành động economy; sim chạy 4 lượt/ngày (`ACTS_PER_EPOCH`), nên thực tế không có giới hạn trừ tim tối đa và tiền.
- Tiền ăn chia theo `Split.ofSpend` (60 recycle / 30 burn / 10 protocol).
- Teacher (`pickFood`, `rules/brain.ms`) ăn khi tim ≤ `persona.minHearts + 1` và mua bữa lớn nhất đủ tiền, nên pet giữ ~5 tim.

### A4. Quota đồ ăn mỗi ngày, đồ thừa hết hạn — Có trong code (trừ slot chủ) · Đo được

- Tâm lý: rủi ro chết là thật; có tiền cũng không mua được sự an toàn vô hạn. Pet phải tính và vẫn hơi hên xui.
- Luật: mỗi ngày pet mua được **x** phần; số phần cố định, chất lượng (Small/Medium/Large) do pet chọn. Chủ có slot riêng **y < x** phần, tác động nhỏ hơn (B1). Phần chưa ăn hết thì mất cuối ngày.
- Thay thế: ăn chủ động không giới hạn ở A3.
- Chốt hết hạn: tick đầu ngày trừ đói, được ăn đồ còn lại của hôm qua, rồi mới bỏ phần thừa. Pet phải để dành cho đêm nay mà không để quá nhiều.
- Chốt ăn ở sàn: tick chỉ tự ăn đồ đã có trong kho khi tim sắp xuống dưới `minHearts`; không tự mua bằng tiền nữa. Mua là quyết định của pet, trong quota x.
- Chỉ số: số phần bỏ phí mỗi ngày; tim giữ theo ngày; tỉ lệ chết sau chuỗi ngày bị đánh.
- Mở: x, y, tim mỗi loại, giá mỗi loại. Chốt cách chọn: đo vài bộ x, y trên sim rồi mới chọn.
- Code: `rules/pantry.ms` (`Pantry`, `FOOD_BUYS_PER_DAY` = 2, `NEWBORN_RATION`), `buy`/`eat` trong `rules/actions.ms` (economy head có 8 action: Rest, Bank, Buy×3, Eat×3), vòng đói trong `tickTo` (`rules/life.ms`). Slot chủ **y** chưa có: chờ mô hình chủ trong sandbox (B1). Luật cũ "tim thấp thì tự mua bằng tiền" và "newborn đói ngày cách ngày" đã bỏ.
- Teacher (`sim/teacher.ms` `teachEconomy`, `pickMeal`/`pickPurchase` trong `rules/brain.ms`): khi tim ≤ `persona.minHearts + 1` thì ăn phần lớn nhất đang có; kho trống thì mua phần lớn nhất đủ tiền.
- Đo được: teacher, 4 worlds × 200 pets × 120 ngày, seed 9001, commit `669ac72`, engine `270516388394663426`; x và giá ăn đổi tạm rồi trả lại (`out/feel/quotaSweep.py`):

| x (phần/ngày) | Giá ăn | Chết trước ngày 90, mỗi world | Chết đói, tổng / với harvest chưa bank / còn đồ ăn hoặc tiền | Bữa ăn mỗi pet | Tim giữ mỗi ngày |
|---|---|---|---|---|---|
| 1, 2 hoặc 3 | ×1 | 0 | 0 / 0 / 0 | 42.4 | 5.32 |
| 1, 2 hoặc 3 | ×10 | 34.8, từ ngày 41 | 152 / 0 / 1 (toàn Vengeful) | 42.2 | 5.29 |

- Chốt (2026-09-24): giữ x = 2 làm trần an toàn; đo lại khi có brain dám liều (PPO train lại, hoặc skill Berserker), vì chỉ khi đó pet mới mất nhiều tim trong một ngày.
- Sau C3 (engine `1541300188293959202`): x = 1 và x = 2 vẫn cho kết quả giống nhau từng số, ở cả giá ×1 và ×5. Tổng tim mất ngoài đói chỉ ~0.3 tim/ngày, nên một bữa Large (3 tim) đủ hơn 2 ngày.
- Quét x, y sau tầng chủ (2026-09-25, teacher, 4 world, engine `6058853656672036622`, `out/feel/sweeps/quota.sh`): (x, y) = (2, 1), (2, 2), (3, 1) giống nhau từng số, (1, 1) gần như giống — teacher vẫn không chạm quota. y = 0 so với y = 1: chết đói 32 so với 15, chết sớm 3.45 so với 1.95 trên 100 đời; y = 2 không thêm gì vì chủ chỉ cho ăn khi pet đói. Giữ x = 2, y = 1; x cần đo với PPO.
- x không đổi gì: ba giá trị cho kết quả giống nhau từng số. Đói chỉ lấy 1 tim/ngày và một bữa Large cho 3 tim, nên teacher mua một lần mỗi ~3 ngày và không bao giờ chạm quota. x chỉ có tác dụng khi pet mất tim nhanh hơn, tức là sau C3 (đánh vào máu). Đo lại x cùng C3.
- Ở giá ×10 có 1 pet chết đói khi còn tiền mua. Chưa truy; giả thuyết: teacher bank ở lượt cuối ngày, nên tiền vào burrow sau lượt mua cuối cùng.

### A5. Tim thấp không làm pet yếu đi — Chốt · Có trong code

- Quyết định: tim thấp không giảm năng suất hay sức đánh. Một skill kiểu Berserker có thể làm pet phẫn nộ và mạnh hơn khi tim thấp (F1).
- Hiện tại: đã đúng như vậy; chỉ mod Scavenger đọc tim (của mục tiêu).
- Hệ quả: nỗi sợ "không làm việc hay đi cướp được" của D22 không đến từ tim; nỗi sợ là chính cái chết. D22 cần viết lại theo hướng này.

### A6. Giá thức ăn so với thu nhập (§6 inv. 2) — Có trong code · Đo được

- Mục tiêu đã ghi: tiền ăn của pet max ≈ 60–70% thu nhập ngày.
- Hiện tại: ~3%. Bữa Small ở level 20 là 16 `$HBRN`/ngày; thu nhập trung bình ≈ emission / pet sống ≈ 100,000 / 200 = 500 `$HBRN`/ngày.
- Đo được: teacher, 4 worlds × 200 pets × 120 ngày, seed 9001, tree `b1b0c2e`; `foodCost` nhân K bằng thay đổi tạm, đã trả lại (`out/feel/foodSweep.py` trong worktree on-chain-ai):

| Giá ăn | Chết trước ngày 90, mỗi world | Chết đói Cautious / Greedy / Vengeful (trên 320 / 240 / 240) | Chết đói khi còn đồ ăn | Tim giữ mỗi ngày, mọi pet |
|---|---|---|---|---|
| ×1 (hiện tại) | 0 | 0 / 0 / 0 | 0 | 5.31 |
| ×5 | 14.2, từ ngày 57 | 0 / 0 / 58 | 0 | 5.30 |
| ×10 | 35.8, từ ngày 41 | 0 / 0 / 152 | 0 | 5.28 |
| ×20 | 59.0, từ ngày 28 | 0 / 0 / 233 | 0 | 5.27 |

- Giá tăng chỉ giết build Vengeful (keystone Cannibal), xem F1. Teacher không đổi cách ăn theo giá.
- Mở: giữ 60–70% hay hạ; đo lại sau A4 vì quota đổi bài toán.
- Đã chọn (đề xuất của agent, áp dụng 2026-09-25, commit `9ac9401`): giá gốc ×7, `foodCost` = {168, 315, 490} × (20 + level) / 20. Quét trên kinh tế D34 + teacher bank sớm (4 world): ×3 / ×5 / ×7 / ×9 cho tiền ăn ở cấp 20 bằng 30 / 46 / 59 / 70% thu nhập làm việc; chết đói 0 / 4 / 15 / 26 (0.07 / 0.77 / 1.74 / 3.61 trên 100 đời), không ca nào còn tiền mua. Theo hướng ở ×7: Worker 37%, Fighter 108% (sống bằng tiền cướp), Survivor 61%. Người chết đói gần hết là Fighter Vengeful: trả thù ở odds thấp, mất cọc, hết tiền ăn.
- Đo trên engine `14630790477522747314` (teacher, 8 world): tiền ăn ở cấp 20 bằng 58.9% thu nhập; 22 chết đói, 1.3 trên 100 đời; nhận ra persona 0.87.
- Sau tầng chủ, đồ và phẫn nộ (engine `2369342061091774511`, teacher): ở ×7 tiền ăn cấp 20 còn 51% (chủ cho ăn thêm, pet tiêu vào đồ), 1.6 chết sớm trên 100 đời. Quét lại (4 world): ×8 → 56%, 2.5 chết sớm (pet chủ bỏ mặc 5.7); ×9 → 60%, 3.4 (chủ bỏ mặc 7.9). Chạm 60–70% (BRIEF §6.2) thì vi phạm §6.1 ("pet chơi tốt, không SKR, không bao giờ chết đói"), vì người chết thêm là pet không có chủ. Agent giữ ×7 và ưu tiên §6.1. Mở: hạ mục tiêu §6.2 hay chấp nhận pet bị bỏ mặc chết nhiều hơn.

- Quét đói và trần cắn (2026-09-24, cây v2, engine `1490032922165168608` ở 10%/20%; teacher, 4 world × 200 pet × 120 ngày, seed 9001; biến thể build trong bản sao `/tmp/sweep`, `out/feel/quotaSweep.py`):

| Đói mỗi ngày (% tim tối đa) | Chết trước ngày 90, mỗi world | Chết đói / bị cắn chết (4 world) | Bữa ăn mỗi pet | Tim bị cắn mỗi đời: Cautious / Greedy / Vengeful |
|---|---|---|---|---|
| 5% | 2.0 | 1 / 0 | 49 | 127 / 41 / 9 |
| 10% (hiện tại) | 2.8 | 1 / 0 | 65 | 128 / 41 / 9 |
| 15% | 12.5 | 4 / 2 | 78 | 129 / 41 / 9 |

  - Trần cắn 30% cho kết quả giống 20% từng số: 10% × tỉ lệ sức kẹp tối đa ×2 không bao giờ vượt 20%, nên trần hiện là thừa. Muốn trần có tác dụng thì nới kẹp tỉ lệ sức.
  - Cautious bị cắn gấp 3 Greedy và 15 lần Vengeful. Chưa truy nguyên nhân.

- BC và PPO trên luật mới (2026-09-24, engine `1490032922165168608`, commit `5b89e26`; `out/feel/step6/train.sh` trong worktree on-chain-ai: `bc.py --envs 16 --steps 4000`, rồi `ppo.py --alternate --learningRate 1e-3 --passes 4 --iterations 30`, seeds 5–7; `evaluate.py`, 16 world mỗi lần):

| | Teacher | BC | PPO seeds 5 / 6 / 7 |
|---|---|---|---|
| Illegal | 0 | 0 | 0 / 0 / 0 |
| Chết đói trong world của chính nó: tổng / còn đồ ăn hoặc tiền mua | 2 / 0 | 0 / 0 | 2 / 2 · 11 / 6 · 34 / 15 |
| Của cải world của chính nó so với teacher | 55,122 `$HBRN`/pet | −1.5% | +9.7 ± 1.2% |
| Mixed world so với teacher | −0.1% (nhiễu ghế) | −8.6% | +15.5 ± 4.2% |
| Trận mỗi pet | 129 | 110 | 59–63 |
| Nhận ra persona từ log | 0.87 | 0.95 | 0.75 ± 0.02 |
| Tim bị cắn mỗi đời, Cautious / Greedy / Vengeful | 128 / 41 / 9 | 128 / 37 / 6 | ~4 / ~0 / ~5 |

  - Vi phạm nghiệm thu: PPO để pet chết đói khi vẫn còn đồ ăn trong kho hoặc tiền mua (2, 6, 15 pet), phần lớn là Vengeful.
  - PPO gần như không bị cắn: nó giữ harvest để kẻ cướp lấy tiền thay vì tim, đúng đánh đổi mà C3 tạo ra.
- Truy nguyên chết đói của PPO (2026-09-24, cùng engine; policy chạy argmax như `evaluate.py`, 16 world, seed 9001, tái lập đúng 34 / 15 của t7; bản sao `/tmp/hib-trace` có thêm export đọc trạng thái pet, script và kết quả thô ở `out/feel/step6/trace/` của worktree on-chain-ai):
  - Không phải Berserker: không pet chết đói nào có keystone; PPO gần như không lấy keystone nào (chỉ Cannibal, ở 0–14% đời Cautious).
  - Mọi pet chết đói, cả PPO lẫn teacher, ngồi ghế 6 (93 trên 97) hoặc ghế 9. Không ca nào còn đồ trong kho; mọi ca "còn tiền" đều có 1–3 phần Small, chưa đủ một phần Large.
  - Nguyên nhân thứ nhất, thứ tự lượt: env cho 10 ghế hành động theo thứ tự cố định 0 → 9 ở mọi vòng mọi ngày, còn thu nhập ngày vào harvest lúc tick đầu ngày, trước mọi lượt. Ghế sau chỉ bank được ở lượt của mình, nên ghế trước cướp được thu nhập còn nguyên, ngày nào cũng cùng một nạn nhân. PPO học đúng kẽ hở này: 98.8% trận vòng 0 của nó đánh ghế đi sau (teacher 58%); ghế 1 đánh ghế 6 10,314 lần. Ghế 6 bị cướp trước lượt đầu 57–66% số ngày (teacher 57%), các ghế khác 0–20%. Trong 10 ngày trước khi chết, pet chết đói bị cướp trước lượt đầu 93–97% số ngày, thu nhập còn lại trung vị 0.
  - Nguyên nhân thứ hai, cỡ phần mua: teacher mua phần lớn nhất đủ tiền, và pet của nó hầu như luôn đủ tiền mua Large, nên trong dữ liệu BC chỉ có 155 lần mua Small/Medium trên 1.27 triệu lượt. BC và PPO chỉ học "mua = Large". Khi đói, kho trống và chỉ đủ tiền Small/Medium, BC mua 0 / 196 lượt, PPO 0–3.6% (907–983 lượt mỗi seed), còn lại Rest; logit Rest hơn logit Buy tốt nhất trung vị 293–515.
  - Chuỗi: ghế 6 bị cướp mỗi ngày → tiêu dần burrow vào đồ ăn → còn tiền cho vài phần Small nhưng không mua → chết "còn tiền". Teacher và BC cũng mất thu nhập ở ghế 6 nhưng ít hơn, nên hiếm khi rơi xuống đáy.
  - Chốt (2026-09-24): sim xáo thứ tự lượt của từng block mỗi vòng theo seed của world (`World.inRound`); BC thêm vòng để chính policy chơi, teacher gán nhãn mọi trạng thái nó đi tới (`bc.py --studentRounds`, mặc định 2).
  - Mở, cho chain: crank trên ER có chạy pet theo thứ tự cố định không. Nếu có, kẽ hở trên xuất hiện lại trong game thật.
- Đo lại sau khi xáo lượt (2026-09-25, engine `8940418975996108247`; `out/feel/step7/train.sh` trong worktree on-chain-ai: `bc.py --envs 16 --steps 4000 --studentRounds 2`, rồi `ppo.py --alternate --learningRate 1e-3 --passes 4 --iterations 30`, seeds 5–7; `evaluate.py`, 16 world mỗi lần; dòng trace: 16 world toàn policy, seed 9001, `out/feel/step6/trace/starveTrace.py`):

| | Teacher | BC | PPO seeds 5 / 6 / 7 |
|---|---|---|---|
| Illegal | 0 | 0 | 0 / 0 / 0 |
| Chết đói trong world của chính nó: tổng / còn đồ ăn hoặc tiền mua | 0 / 0 | 0 / 0 | 0 / 0 · 0 / 0 · 0 / 0 |
| Trace 16 world toàn policy: chết đói / còn tiền | 0 / 0 | 1 / 1 | 0 / 0 · 0 / 0 · 0 / 0 |
| Của cải world của chính nó so với teacher | 52,279 `$HBRN`/pet | −0.1% | +3.2 ± 0.6% |
| Mixed world so với teacher | +0.7% (nhiễu ghế) | −2.0% | +26.3 ± 2.6% |
| Trận mỗi pet | 128 | 134 | 76 / 96 / 70 |
| Nhận ra persona từ log | 0.87 | 0.90 | 0.80 ± 0.06 |
| Tim bị cắn mỗi đời, Cautious / Greedy / Vengeful | 126 / 42 / 5 | 125 / 42 / 6 | 1 / 11 / 21 · 31 / 13 / 37 · 2 / 10 / 2 |
| Đời Vengeful có Cannibal (trace) | 641 | 640 | 0 / 547 / 641 |

  - Trước khi sửa (step6): teacher 2 chết đói, PPO 2 / 11 / 34; BC −1.5% và −8.6%, và BC gần như không lấy Cannibal (3 đời trên 641 của teacher) vì đầu chọn node chỉ khớp teacher 32% trên trạng thái chính nó đi tới.
  - Sau khi xáo, Worker vẫn bị cướp trước lượt đầu nhiều nhất (teacher: ghế 3 30%, ghế 6 39%; PPO: Worker 18–49%), nhưng không pet nào trắng tay: burrow trung vị lúc lượt đầu của Vengeful dưới PPO 16–17k, trước là 4–5k. Đó là Fighter săn Worker, là lối chơi, không còn là kẽ hở thứ tự.
  - Còn lỗ hổng: khi đói, kho trống và chỉ đủ tiền Small/Medium, BC mua 0 / 78 lượt, PPO 0 / 12 · 8 / 63 · 1 / 9. Logit BuyL (không hợp lệ) vẫn cao hơn Rest ở 97% các lượt đó: brain muốn mua, nhưng muốn đúng phần Large. Trạng thái này giờ hiếm, nhưng ca BC chết khi còn 132 `$HBRN` ở trên là nó.
  - Mở: "gấp cỡ phần" (cỡ không làm được thì lấy cỡ nhỏ hơn gần nhất làm được, giống nhau lúc train, evaluate và trong `act`), hay đổi luật thành một lệnh Mua phần lớn nhất đủ tiền. Đề xuất: gấp cỡ phần, vì giữ quyền chọn cỡ của A4.

- Đo lại sau đợt thêm cơ chế (2026-09-25, engine `2369342061091774511`, commit `0bfbac7` — đã land vào `main` local; `~/metacraft/hibernal-train/step12`: `bc.py --envs 8 --steps 4000 --studentRounds 2`, PPO `--alternate --learningRate 1e-3 --passes 4 --iterations 30` seeds 5–7; `evaluate.py` 16 world, `health.py` 8 world):

| | Teacher | BC | PPO seeds 5 / 6 / 7 |
|---|---|---|---|
| Illegal | 0 | 0 | 0 / 0 / 0 |
| Chết đói khi còn đồ ăn hoặc tiền (health, 8 world) | 0 | 0 | 0 / 0 / 0 |
| Chết sớm trên 100 đời | 1.6 | 1.8 | 0.56 / 0.77 / 0.84 |
| Của cải world của chính nó | 29,798 `$HBRN`/pet | 29,961 | 40,385 / 41,551 / 40,988 |
| Mixed world so với teacher | +1.1% (nhiễu ghế) | −1.8% | +6.5 / +12.6 / +12.5% |
| Trận mỗi pet | 42 | 42 | 42 / 47 / 42 |
| Tiền ăn ở cấp 20, % thu nhập | 51 | 52 | 31 / 29 / 30 |
| Chênh của cải theo hướng xuất phát | 2.1 | 2.1 | 1.63 / 1.50 / 1.39 |
| Mint mỗi đời, % thu nhập vào đồ | 4.6, 9.7% | 3.9, 6.8% | 2.3–2.5, 3.3% |
| Cướp lặp lại trong 3 ngày | 13% | — | 10–12% |
| Nhận ra persona (có trả thù) | 0.86 | 0.93 | 0.73 / 0.73 / 0.76 |

  - PPO ăn tiết kiệm hơn teacher nhiều (tiền ăn 30% thu nhập so với 51%) và chơi các hướng đều tay hơn; mục tiêu 60–70% của BRIEF §6.2 càng xa khi pet biết tính. Persona của PPO mờ đi (0.73–0.76) như các lần trước.

- Engine mới nhất (sàn phần thưởng, wild pet, bán đồ, reward tính đồ; engine `12482136861935123128`, `~/metacraft/hibernal-train/step13`, `step14`): teacher và BC đạt (0 illegal, 0 chết đói khi còn tiền, chết sớm 1.4 và 2.0 trên 100 đời). PPO seeds 5 / 6 / 7 (từ BC `bc13`): 0 illegal, nhưng chết đói khi còn tiền 1 / 0 / 1 (health, 8 world), chết sớm 2.3 / 2.1 / 1.6 trên 100 đời, pet chủ bỏ mặc 6.0 / 5.6 / 3.9. Truy (`out/feel/step6/trace/starveTrace.py` cập nhật cho 10 hành động): pet giàu (4,500–9,000 `$HBRN`), tim 2–6, kho trống, được mua Large mà chọn Rest; logit cao nhất là ăn Large (không hợp lệ vì kho trống), logit mua thấp hơn Rest. Khi tim dưới 30% PPO mua ở 45–52% số lượt, nên đây là lỗi hiếm của policy, không phải thói quen. BC không mắc; PPO làm hỏng dần hành vi mua ở trạng thái hiếm.
- Thử gấp "muốn ăn khi kho trống → mua phần đó" chỉ ở bước giải mã, trên policy train không có phép gấp: 0 chết khi còn tiền nhưng chết đói tổng 106–166, tiền ăn 80% thu nhập — logit ăn của PPO cao cả khi không đói, gấp vào mua thành mua liên tục. Kết luận: phép gấp phải có mặt cả khi train.
- Hai hướng sửa đo song song (engine `12482136861935123128`): (1) `step15`, BC và PPO train với phép gấp "muốn ăn khi kho trống → mua" (commit `a516f20`): 0 illegal, 0 chết đói khi còn tiền ở cả evaluate lẫn health cho BC và PPO seeds 5–7; PPO hơn teacher +18.2 / +25.2 / +26.8% ở mixed world, chết sớm 1.8–2.3 trên 100 đời, tiền ăn 33% thu nhập; BC chết sớm 1.3 (không phép gấp: 2.0). (2) `step16`, không phép gấp, PPO thêm hạng bắt chước teacher ở đầu economy (`--imitation 0.5`): cũng 0 chết khi còn tiền nhưng yếu (−27 / −8 / +12%) và chết sớm 2.1–4.0. Chọn (1), bảng đầy đủ ở `ON-CHAIN-AI.md` §6 package 5c; `--imitation` giữ lại, mặc định tắt.
### A7. Ai chết đói, và bao nhiêu — Mở · Đo được một phần

- Tâm lý: chết đói "đáng sợ mà công bằng"; 0 cái chết vô lý (chết khi còn đồ ăn trong burrow).
- Chỉ số: % pet chết sớm mỗi đời; % chết khi còn đồ ăn; số ngày từ lúc tụt tim đến lúc chết; ai chết (bị cướp nhiều, lười, hay build yếu).
- Hiện đo: 0% chết sớm và 0 chết vô lý ở giá ×1 (`ON-CHAIN-AI.md` §6 package 5b).
- Mở: dải mục tiêu.

## B. Chủ và pet: bonding, SKR, ROI

### B1. Chủ mua đồ ăn bằng SKR — Có trong code · Đo được

- Tâm lý: cho ăn là cách chủ gắn bó với pet, và làm tăng bonding.
- Luật: đồ chủ mua dùng slot riêng **y** (A4); chỉ khác số lượng, y luôn nhỏ hơn x, cùng loại và cùng tác dụng; sweet spot của y đo bằng sim; chủ mua đều tay thì pet khỏe hơn. SKR 100% vào treasury (§3.5). Bonding và việc từ chối đồ ăn khi bonding thấp: `GAME-DESIGN.md` §14, D36.
- Code (2026-09-25, commit `12da6cc`, `rules/owner.ms`; đề xuất của agent): `ownerFed(food)` ăn ngay, y = `OWNER_FOOD_PER_DAY` = 1 phần mỗi ngày, bonding +6, từ chối khi bonding < −40. Cùng module: `talkedTo` (+3, tối đa 2 lần/ngày), `grownBy` (growth +5% mỗi bậc, tối đa 3 bậc, trần 1.20, hiệu lực cho lần tick kế tiếp; tick trả thưởng growth khi buff còn hiệu lực lúc bắt đầu khoảng thời gian), `insured` (một lần mỗi pet); mua bằng SKR cho bonding +15.
- Bảo hiểm (BRIEF §3.5): khi tim về 0 vì đói, bị cắn hay thua trận, pet được hồi với 30% tim tối đa, đốt 50% ví, +1 scar, một lần mỗi pet. Cannibal chỉ ăn được nếu nạn nhân vẫn chết sau khi xét bảo hiểm.
- Mô hình chủ trong sim (`sim/owner.ms`, strawman của agent): chủ chăm 25% (ghé 90% số ngày, cho ăn Large khi tim < 70%, 30% số lần ghé mua growth 3 bậc, mua bảo hiểm ngay), thỉnh thoảng 45% (ghé 35%, Medium khi tim < 50%, 10% mua growth 1 bậc, 5% mua bảo hiểm), bỏ mặc 30% (không ghé). Chủ ghé lúc bình minh, sau tick. Giá SKR (strawman): đồ ăn 1 / 2 / 3, growth 2 mỗi bậc, bảo hiểm 20.

### B2. Bonding → pet tặng `$HBRN` cho chủ — Có trong code · Đo được

- Tâm lý: điều người chơi thực sự muốn là `$HBRN` từ pet; cách duy nhất để lấy được là thiện cảm của pet.
- Luật: bonding (`i8`, giảm mỗi ngày) tăng khi cho ăn, mua SKR, `talk` (có giới hạn mỗi ngày); bonding cao thì pet tặng quà, có giới hạn mỗi ngày, không bao giờ làm pet thiếu tiền ăn (`GAME-DESIGN.md` §14).
- Code (đề xuất của agent): bonding giảm 2 mỗi ngày (xuống dưới 0 khi bị bỏ mặc); từ bonding 60, mỗi tick pet tặng tối đa `GIFT_SHARE_BPS` × (bonding − 60) / 67 burrow, trần 500 `$HBRN` mỗi ngày, luôn giữ quỹ ăn 3 ngày (phần Large, theo đói mỗi ngày). Quà cộng vào `giftOwed` (bản hackathon, BRIEF §3.13), heir giữ `giftOwed` của chủ. Quà là tự động theo bonding, chưa phải hành động của brain.
- Quét tỉ lệ quà (teacher, 4 world, engine `8285827034452240052`): 1% / 2% / 5% burrow mỗi ngày ở bonding tối đa → pet chủ chăm tặng 21 / 31 / 37% thu nhập, chủ nhận 70 / 99 / 120 `$HBRN` cho mỗi SKR, của cải trung vị pet chủ chăm 34.6k / 27.1k / 21.8k (chủ thỉnh thoảng ~26k, bỏ mặc ~25k). Chọn 1% (commit `ebbf2d8`): chăm chủ thì pet vẫn giàu nhất, không bị vắt.
- Kết quả theo kiểu chủ (1%): chủ chăm bonding trung bình 110, 0 chết sớm; chủ thỉnh thoảng bonding ~−2, quà gần như 0, 17 lần bị từ chối đồ ăn; chủ bỏ mặc bonding −75, không quà, chết sớm 1.3–1.6 trên 100 đời.
- Mở: chủ thỉnh thoảng hầu như không nhận được gì (bonding giảm 2/ngày, thăm 35% số ngày); đúng ý "phải ghé hằng ngày" (D36) hay quá gắt. Bonding chưa vào observation của policy.
- User chốt 2026-09-26: pet cho chủ rất ít, mỗi ngày tối đa 5% thu nhập trong ngày của nó, và cho vì thích (theo bonding), không có lợi ích sinh tồn nào. `$HBRN` trong tay chủ không làm được nhiều (giống SKR); đường tốt nhất cho tiền của pet là để lại cho heir khi pet chết già đúng quy trình (một tài khoản chỉ có một pet đang chơi).
- Đã cài (worktree on-chain-ai, chưa commit, engine `13253351794902336611`): `giftFor(reserve, income)` lấy `GIFT_SHARE_BPS` = 500 × (bonding − 60) / 67 của thu nhập mới trong lần tick, vẫn giữ quỹ ăn 3 ngày; bỏ trần 500 `$HBRN` (`GIFT_CAP`). Teacher, 8 world, seed 9001, cùng lần đo với C6: quà cho chủ chăm 175 → 36 `$HBRN` mỗi ngày (20% → 4% thu nhập), của cải trung vị pet chủ chăm 37.4k → 52.9k; chủ thỉnh thoảng 1.6 → 0.3 mỗi ngày.

### B3. ROI của người chơi — Mở · Đo được (strawman)

- `$SKR` đã có giá fiat; `$HBRN` ngoài đời có thể là tiền thật (token thật từ ngày launch, D38; D17 đã bỏ).
- Chỉ số: SKR bỏ vào so với `$HBRN` nhận về theo thời gian, theo mức bonding và theo từng loại tương tác; thời gian hoà vốn; ROI của chủ chăm, chủ thỉnh thoảng, chủ bỏ mặc.
- Đo (strawman ở B1, B2): chủ chăm tiêu 2.85 SKR mỗi ngày, nhận ~200 `$HBRN` mỗi ngày (70 `$HBRN` cho mỗi SKR); chủ thỉnh thoảng 0.3 SKR mỗi ngày, ~5 `$HBRN` cho mỗi SKR; chủ bỏ mặc 0 / 0. Tỉ giá SKR / `$HBRN` để quy ra ROI còn mở.

### B4. Tương tác thời gian thực — Mở · Chưa có trong sim

- Tâm lý: chủ phải tương tác thường xuyên theo thời gian thực, không chỉ cho ăn và cho tiền.
- Hiện tại: sim theo ngày, mỗi ngày 4 lượt `act`, thứ tự lượt xáo mỗi vòng (A6); chủ ghé một lần lúc bình minh theo kiểu chủ (B1); chưa có giờ trong ngày hay thông báo.
- Cần: mô hình thời gian trong ngày (khi nào chủ mở app, phản ứng với thông báo) và danh sách hoạt động. Cơ chế mới đã được user đồng ý mở, thuộc sandbox (mục 0).

## C. Đánh nhau

### C1. Chọn mục tiêu, odds công khai (D8) — Có trong code · Đo được

- Tâm lý: Fighter chơi xác suất, không phải máy slot.
- Chỉ số: tỉ lệ trận dưới 40% odds; EV thực tế so với odds.
- Hiện đo: 0–0.7% dưới 40% (teacher), 0 (clone và PPO).

### C2. Quota bị đánh — Có trong code · Đo được

- Luật: tối đa `INCOMING_CAP` = 3 trận bị đánh mỗi ngày, 1 lần bite (`BITES_CAP`), mỗi kẻ đánh chỉ đánh một mục tiêu một lần mỗi ngày (`rules/fight.ms`).
- Chỉ số: số trận bị đánh mỗi ngày, số ngày chạm quota.
- Đo (teacher, 4 world, engine `1622489765003688175`, `train/health.py`): 0.37 trận bị đánh mỗi pet mỗi ngày; 2.3% số pet-ngày chạm trần 3.

### C3. Sát thương theo sức kẻ đánh và theo tiền bị cướp — Có trong code · Đo được

- Tâm lý: pet không biết ai sẽ đánh mình. Có tiền thì kẻ mạnh cướp xong bỏ đi; không có tiền thì kẻ mạnh đánh vào máu.
- Luật đề ra: số trận bị đánh vẫn cố định (C2), nhưng tim mất tăng theo sức kẻ đánh và giảm theo số tiền kẻ đó cướp được.
- Hiện tại: thắng thì cướp harvest; chỉ bite −1 tim khi harvest trống, **và chỉ khi sức nạn nhân ≥ 50% kẻ đánh** (`biteAllowed`, D11: "Fighters kill peers, not kids").
- Luật mới ngược với D11 (kẻ mạnh không được cắn pet dưới 50% sức) và với "đánh không giết" của D10.
- Chốt: theo luật mới, bỏ quy tắc 50% của D11, giữ ý chống bắt nạt bằng ba chốt: trần tim mất mỗi đòn (1–2), giữ `BITES_CAP` mỗi ngày, và đánh vào máu không cho kẻ đánh gì (không loot, XP thấp) để giết pet yếu không thành cách kiếm tiền (§6 inv. 6). Giữ khiên newborn. D10 thành "đánh nhau giết được, nhưng chỉ pet không có gì để mất".
- Đánh đổi mới cho pet: bank hết thì harvest trống, kẻ cướp đánh vào tim; để lại ít tiền thì mất tiền nhưng giữ tim. Liên quan C6 (D9).
- Code (`rules/fight.ms` `biteHearts`, gọi trong `settleAttack`): kẻ thắng cướp được ≥ tiền cọc thì không cắn; cướp được ít hơn (kể cả harvest trống) thì cắn 1 tim, 2 tim nếu sức kẻ đánh ≥ 2 lần nạn nhân (`BITE_HEARTS_CAP`, `CRUSHING_POWER_RATIO`); tối đa 1 lần cắn mỗi ngày (`BITES_CAP`). Quy tắc 50% đã bỏ. BRIEF D10, D11, §3.6 đã viết lại.
- Đổi (2026-09-25, commit `273e260`, xem F1): cú cắn = 2 tim × tỉ lệ sức (0.5–2), thua trận = 2 tim, cả hai trần 20% tim tối đa; trước đó là 10% tim tối đa × tỉ lệ sức và 10% tim tối đa.
- Đo được (teacher, 4 worlds × 200 pets × 120 ngày, seed 9001, engine `1541300188293959202`, commit `393a268`): mỗi pet mất trung bình 10.9 tim vì bị cắn (Cautious 10.3, Greedy 17.7, Vengeful 5.0) và 16.7 tim vì tấn công thua (4.6 / 31.5 / 17.9) trong ~90 ngày sống, so với ~90 tim vì đói. Ở giá ăn ×1: 0 chết sớm, 0 chết vì bị cắn. Ở giá ×5: 8 pet chết vì bị cắn (7 Vengeful, 1 Greedy) và 59 chết đói (toàn Vengeful).

### C4. Tấn công thua mất 1 tim (§3.6) — Có trong code · Đo được

- Tâm lý: tấn công có rủi ro.
- Chỉ số: tim mất do thua / tim mất do đói.
- Đo được: tấn công thua 16.7 tim mỗi pet mỗi đời, đói ~90 (xem C3). Counter `HeartsLostAttacking`, `HeartsBitten` trong `sim/env/feel.ms`.

### C5. Pet 1 tim có được tấn công — Chốt · Có trong code

- Quyết định: được; đó là quyền của pet, luật không cấm. Thế giới tự do, brain được làm cả điều điên rồ.
- Hiện tại: `attackable` không chặn; thua là chết.

### C6. Loot là harvest, burrow an toàn (D9) — Có trong code · Đo được

- Tâm lý: bank hằng ngày = an toàn.
- Chỉ số: % của cải mất do bị cướp; chênh lệch giữa pet bank đều và pet lười.
- Phát hiện (2026-09-25): teacher chỉ bank ở lượt cuối ngày hoặc khi harvest > 25% burrow, nên thu nhập ngày bị phơi ba lượt. Kẻ cướp lấy 57% thu nhập; Worker Greedy và Vengeful mất 92–93%; của cải theo hướng xuất phát chênh 4.4 lần.
- Đã sửa teacher (đề xuất của agent, áp dụng, commit `ec175a2`): ăn nếu đói và có đồ, rồi bank ngay khi có harvest, rồi mới mua. Teacher, 4 world: tiền bị cướp 57.8% → 25.6% thu nhập; chênh của cải theo hướng 4.4 → 1.4 lần; p90 của cải 3.4 → 2.1; trận mỗi pet mỗi ngày 1.3 → 0.4; nhận ra persona 0.97 → 0.93. Bank trước khi ăn cho kết quả giống hệt (lúc bình minh kho vừa bị tick dọn).
- Còn lại (engine `14630790477522747314`): mất 28% thu nhập vì bị cướp; Worker Greedy và Vengeful vẫn mất ~60%, vì chúng mang keystone tấn công (Glass Cannon, Cannibal) và bị cướp trước lượt đầu trong ngày.
- Lượng cướp theo D26 (2026-09-25, commit `5ac628f`; luật đã chốt trong BRIEF, trước đó code vẫn dùng `(1000 − grit) / 1000`): `loot = min(1.5 × stake, harvest, harvest × 2 × might kẻ cướp / (might + grit nạn nhân))`. Grit chỉ che tiền khi grit nạn nhân lớn hơn might kẻ cướp; kẻ cướp mạnh hơn lấy trọn phần với tới. Đo (teacher, 4 world, engine `1666978971620739088`, so với `12482136861935123128`): tiền bị cướp 27.4 → 29.5% thu nhập (Worker 39.9 → 42.5%, Survivor 5.2 → 6.8%); chết sớm 1.33 → 2.09 trên 100 đời (chết khi tấn công thua 7 → 14, bị cắn chết 0 → 3; mẫu nhỏ); 0 chết đói khi còn tiền. `sim/builds.ms` (4 seed): chết sớm toàn bộ 3 → 6%; Worker Tycoon 6 → 20% chết sớm, của cải trung vị ×0.28 → ×0.13; Survivor khá lên (depth ×1.40 → ×1.56). File thô `out/health/teacher.d26.txt`, `out/feel/sweeps/builds.d26.txt` (so với `builds.base7acd525.txt`).
- Mở: Worker bị cướp ~42% thu nhập: cả ngày thu nhập vào harvest lúc bình minh, kẻ cướp đi trước lượt đầu của nó lấy trọn. Trên chain cũng vậy (phần thưởng settle theo epoch, D23; crank xếp lượt ngẫu nhiên). Chia thu nhập theo lượt chưa chắc giảm tổng, vì mỗi lượt lại mở một cửa sổ mới cho kẻ cướp; chưa đo.
- PPO làm cửa sổ này thành chỗ chết (step19, 8 world): chết đói vì cháy túi 60–77 ca trên ~2,900 đời (teacher 27), pet của chủ bỏ mặc chết sớm 6.1–6.5 trên 100 đời. Trace (`~/metacraft/hibernal-train/step19/out/debug/brokeTrace.ms`, PPO seed 5): sáng nào nạn nhân cũng có 500–1,300 thu nhập trong harvest, nhưng trước lượt kinh tế đầu tiên đã bị cướp trọn (`fightsInToday` = 1, harvest 0), ngày này qua ngày khác, tới khi burrow dưới giá một phần Small và chết đói. PPO thắng teacher +47 / +76 / +52% trong world trộn, một phần nhờ cướp hiệu quả hơn.
- Đo phương án ngược lại (2026-09-25, chỉ trong bản sao, không đổi luật): mỗi vòng cho mọi pet làm kinh tế (bank) trước rồi mới đánh nhau, tức "bank hằng ngày = an toàn" đúng từng chữ. `sim/builds.ms`, 4 seed, engine `1622489765003688175`: Worker giàu ×3.3–6.4 trung vị, 0% chết sớm, top ×15.8 (Worker Tycoon — đuôi ×20 gần tới); Fighter sụp ×0.03–0.36, chết sớm 13–31%; Survivor ×0.2–0.6. Thứ tự hiện tại (lượt xen kẽ): Worker ×0.12–1.24, Fighter ×1.27–1.86, Survivor ×0.31–1.65. Hai đầu đều lệch; lượng cướp "đúng" nằm giữa và là quyết định thiết kế: Worker nên mất bao nhiêu cho kẻ cướp (BRIEF §6 inv. 5 cho phép tới q < 0.67), và Fighter sống bằng gì khi Worker bank kịp. File thô `out/feel/sweeps/builds.twoPhase.txt`, `builds.market.txt`.
- User chốt 2026-09-26: chủ mở app thì cất được ngay 50% harvest, cooldown 8 tiếng (retention vừa phải); pet vẫn tự cất ở lượt của nó như trước.
- Thử trong bản sao trước khi chốt (teacher, 8 world, seed 9001, gốc engine `2583165197786226676`; bản sao `/tmp/hib-bank`, không đổi luật). Chủ ghé lúc bình minh, trước mọi trận, nên đây là mức tốt nhất cho chủ:

| | Hiện tại | Chủ cất hết | Chủ cất hết + pet chỉ tự cất đủ 5 ngày ăn | Chủ cất hết + nửa harvest tự cất lúc bình minh, pet không cất | Chủ cất 50% | Chủ cất 50% + quà 5% (B2) |
|---|---|---|---|---|---|---|
| Tiền bị cướp, % thu nhập | 32.4 | 21.8 | 39.7 | 22.7 | 26.4 | 26.3 |
| Chết sớm / 100 đời (chung · bỏ mặc) | 1.87 · 3.69 | 3.73 · 9.83 | 5.26 · 14.21 | 13.03 · 29.09 | 2.37 · 6.51 | 1.96 · 5.62 |
| Chết đói khi còn tiền | 0 | 0 | 1 | 7 | 0 | 0 |
| Của cải trung vị: chủ chăm / thỉnh thoảng / bỏ mặc | 34.3k / 26.1k / 24.8k | 35.7k / 23.6k / 19.2k | 48.7k / 18.4k / 4.3k | 39.8k / 24.5k / 15.8k | 37.4k / 24.7k / 21.0k | 52.9k / 25.8k / 23.1k |
| Của cải trung vị, hướng giàu nhất / nghèo nhất | 4.03 | 5.01 | 8.53 | 6.92 | 3.72 | 3.90 |

  Kẻ cướp không đụng được pet có chủ ghé nên dồn sang pet bị bỏ mặc. Giới hạn thêm cho pet (hai cột giữa) làm pet bị bỏ mặc chết hàng loạt, và tiền nằm ở harvest thì không mua được đồ ăn nên có pet chết khi còn tiền. Bộ đếm thu nhập của `sim/env/feel.ms` đọc harvest lúc mở ngày, nên cộng lại phần chủ đã cất (`OwnerLedger.banked`).
- Đã cài (worktree on-chain-ai, chưa commit, engine `13253351794902336611`): `ownerBanked(now)` trong `rules/owner.ms` chuyển `OWNER_BANK_PERCENT` = 50% harvest vào burrow, từ chối trong `OWNER_BANK_COOLDOWN_SECONDS` = 8 giờ kể từ lần trước (`Pet.ownerBankedAt`, giây). Sim: chủ cất khi ghé (bình minh, trước khi nói chuyện và cho ăn), `now` = epoch × `EPOCH_SECONDS`; chủ ghé tối đa một lần mỗi ngày nên cooldown chưa lần nào chặn trong sim (B4). Teacher, 8 world: số giống hệt cột cuối.
- Cooldown trong sim (user 2026-09-26: "ừ làm cooldown"; commit `3b0b516`): ngoài lần ghé lúc bình minh, ở mỗi vòng sau (6, 12, 18 giờ) chủ mở app với xác suất 50% (chăm) / 10% (thỉnh thoảng) / 0 (bỏ mặc) `[strawman của agent]`, mỗi lần cất 50% nếu đã qua 8 giờ (`ownersOpened` trong `sim/world.ms`). Với 4 vòng mỗi ngày, lần mở 6 giờ sau lần cất lúc bình minh bị chặn; chủ chăm cất tối đa 2 lần mỗi ngày. Teacher, 8 world, so với step28 (khi đó còn luật tài năng nhân trọng số, nên không tách riêng được): tiền bị cướp 26.1 → 26.3% thu nhập, của cải trung vị chủ chăm 53.5k → 52.7k — gần như không đổi, vì chủ chăm đã cất trước mọi trận lúc bình minh.
- Cooldown 4 giờ thay vì 8 (câu của user 2026-09-26, đo trong bản sao `~/metacraft/hibernal-train/cooldown4`, không đổi luật; 8 world, seed 9001, engine `16948401298924711931`): teacher và PPO seed 5–7 (`step29b`) cho bảng sức khỏe giống hệt từng byte, engine không đổi. Đối chứng cooldown 48 giờ (`cooldown48`, teacher): engine đổi, tiền bị cướp 26.4 → 28.7% thu nhập, chết đói 54 → 48 — tức là hằng số có vào thư viện. Lý do: thu nhập cả ngày vào harvest một lần lúc bình minh (settle theo epoch, D23), loot của kẻ cướp vào thẳng burrow, và cả teacher lẫn PPO cất sạch harvest ở lượt đầu; chủ mở app ở vòng sau chỉ gặp harvest rỗng. Trên chain cũng vậy. Độ dài cooldown dưới 24 giờ chỉ đổi trải nghiệm nút bấm, không đổi kinh tế; giá trị của lần mở app là mở sớm, trước kẻ cướp.
- Tiêu thẳng harvest (câu của user 2026-09-26; agent chốt, user ủy quyền): mua đồ ăn, mint và mua trên chợ trả bằng harvest trước rồi mới tới burrow (`wallet()`, `charged()` trong `rules/layout.ms`); cọc đánh nhau vẫn lấy từ burrow. Brain thấy ví (harvest + burrow) trong `FoodDays` và số lần mua đủ tiền. Loại "chết khi còn tiền chưa cất" (`Larder.Unbanked`) gộp vào "chết khi còn đồ ăn hoặc tiền" của gate. Teacher: số giống hệt (luôn cất trước khi mua). Lý do: không pet nào chết đói khi tiền nằm ngay trong túi, brain không tốn một lượt để cất rồi mới mua, và tiền dễ bị cướp được tiêu trước.

## D. Hàng xóm và persona

### D1. Trả thù (D12) — Có trong code · Đo được

- Tâm lý: đọc được hàng xóm, trả thù, thừa kế.
- Chỉ số: % trả thù trong 3 ngày; % cướp lặp lại cùng một nạn nhân.
- Hiện đo: Vengeful của teacher 2.4%, PPO 0.0–0.1%. Mục tiêu: Mở.
- Bắt nạt (2026-09-25, câu hỏi "phẫn nộ" của user): đo tỉ lệ vụ cướp mà cùng kẻ cướp lại cướp cùng nạn nhân trong 3 ngày (`robbedAgain` trong `sim/env/feel.ms`). Teacher, 4 world, engine `3931114478917005264`: 17%; Worker bị cướp 0.6–0.8 lần mỗi ngày, nạn nhân nặng nhất bị cùng một kẻ cướp lại 24–28 lần trong đời.
- Đã thêm phẫn nộ (đề xuất của agent theo ý user, commit `42b0ade`): bị cùng một hàng xóm cướp hoặc cắn lần nữa thì phẫn nộ +1 (tối đa 3, giữ 3 ngày từ lần cuối); khi đánh với kẻ đó ở vai nào cũng được might và grit +10% mỗi bậc; thắng kẻ đó thì hết. Odds mà brain thấy có tính phẫn nộ. Đo (teacher, 4 world, engine `2369342061091774511`): cướp lặp lại 17% → 13%, tỉ lệ thắng khi tấn công 0.83 → 0.81, tổng tiền bị cướp không đổi (27% thu nhập), nhận ra persona 0.86 → 0.89. Bản đầu cho phẫn nộ giảm 1 mỗi ngày thì không bao giờ có tác dụng (kẻ cướp chỉ đánh một mục tiêu một lần mỗi ngày), engine không đổi — đã sửa thành giữ 3 ngày.

### D2. Persona đọc được từ log (D18) — Có trong code · Đo được

- Chỉ số: recall khi đoán persona từ log một pet.
- Hiện đo: teacher 0.95, clone 1.00, PPO 0.79 ± 0.10. Mục tiêu: ≥ 0.9, cần user xác nhận.
- User chốt 2026-09-26: mục tiêu hạ xuống ≥ 0.8, đo trên PPO và chỉ báo cáo, không chặn land.

## E. Vòng đời

### E1. Lifespan và heir (D32) — Có trong code · Đo được một phần

- Tâm lý: cái chết là cột mốc, tiến bộ lặp lại mỗi thế hệ.
- Chỉ số: heir so với gen 1 cùng ngày tuổi; % heir vào top quartile (§6 inv. 4).
- Gói heir (2026-09-25, commit `c1b2a7e`, đề xuất của agent theo strawman `GAME-DESIGN.md` §7): heir giữ 2 món đồ điểm cao nhất (`HEIRLOOM_SLOTS`), di sản bán lại các món còn lại theo giá công thức vào burrow của heir; mỗi thế hệ nhân odds mọi hạng trên Common lên 1.05, trần 1.25 ở thế hệ 5 (`lineageNudgeBps`). Hướng xuất phát vẫn theo cha mẹ (chọn tự do cần mô hình chủ chọn hướng). Engine digest thêm dòng `lineage` (world trong digest chỉ 30 ngày, chưa có heir).
- Đo (teacher, 4 world, engine `6608752566691209999`): mint mỗi đời 4.64 → 5.26, tiền đồ 9.8 → 10.5% thu nhập, thưởng đồ trung bình 879 → 905 bps; các dòng khác không đổi. Pet sinh từ ngày 60 vào top 25% của cải: 23.9%.

### E2. Tốc độ lên cấp (§6 inv. 1) — Có trong code · Đo được

- Mục tiêu đã ghi: cấp 10 trong ~7 ngày, cấp 20 trong ~30 ngày (BRIEF D6, §6.1).
- Đo (teacher, `train/health.py`, 8 world, seed 9001, engine `8940418975996108247`): tuổi trung bình lúc lên cấp 10 là 7.0 ngày, cấp 20 là 16.1 ngày. Nhanh nhất Fighter Cautious (cấp 20 ở ngày 10, nhờ XP cướp), chậm nhất Survivor Cautious (33 ngày).
- Đã sửa (đề xuất của agent, áp dụng 2026-09-25, commit `bbbbd95`): `xpToReach` cộng thêm `LATE_LEVEL_XP_PER_CUBE` × (cấp − 10)³ (`rules/level.ms`), đường cong tới cấp 10 giữ nguyên. Quét 0 / 6 / 12 / 20 (teacher, 4 world): cấp 20 ở ngày 16.1 / 22.3 / 28.4 / 30.9, cấp 10 giữ 6.9; chọn 16. Đo lại trên engine `5201748116494185250`: cấp 10 ở ngày 6.9, cấp 20 ở ngày 32.5; các chỉ số khác không đổi đáng kể.

## F. Build

### F1. Skill tree và keystone (D13) — Có trong code (cây v2, 64 node) · Đo được một phần

- Tâm lý: build = lộ trình đến keystone; keystone nào cũng có đất sống.
- Chỉ số: tỉ lệ sống, thu nhập, tỉ lệ thắng theo keystone; pick rate từng node; node không ai chọn.
- Hiện đo: Cannibal chết đói khi giá ăn ×5 trở lên, Pacifist và Glass Cannon thì không (A6). Nguyên nhân chưa truy.
- Cần: cách chọn build không bị persona khoá cứng. Cây 64 node chưa xây.
- Chốt (2026-09-24): đầu tư tạo khác biệt lớn. Thứ gì được đầu tư thì có thể gấp mấy lần pet khác (thu nhập, tim, phòng thủ), nhưng điểm skill có hạn nên pet phải chọn. Tim tối đa tăng theo cả level lẫn cây. Cây phải sắc nét và pet phải thực sự nâng skill. Nguồn tham khảo: dữ liệu thật của Path of Exile và Grim Dawn, rút gọn cho Hibernal.
- Mở (thang tim, A/C): tăng thang tim (khởi đầu ~10–20, mạnh ~50) có ích khi đi cùng đói theo % tim tối đa, phần ăn hồi lượng cố định, và sát thương cắn liên tục có trần theo % tim tối đa. Hai con số chờ chốt: % đói mỗi ngày, trần % mỗi lần cắn.
- Nghiên cứu (2026-09-24, số đo từ dữ liệu thật; file thô và script ở `out/research/poe/`, `out/research/grimdawn/` của worktree on-chain-ai, git bỏ qua):
  - PoE 3.29.1 (`grindinggear/skilltree-export` commit `8bd138b3`): 2,321 node trên cây chính (1,476 nhỏ, 454 notable, 48 keystone, 315 mastery, 21 jewel socket), 123 điểm. Pet giữ 5–6% cây nhưng mọi node nằm trong 23–33 điểm từ điểm xuất phát: cái khó là chọn, không phải với tới. Notable nằm cuối cụm, trung vị 3 node nhỏ; notable ≈ 2–2.5 lần node nhỏ cùng chỉ số (máu 5% → 10%). Tổng mọi node `% increased maximum Life` là 568%. Node nhỏ và notable có 1,917 dòng "increased" (cộng) và 3 dòng "more" (nhân); "more/less" gần như chỉ ở keystone, mastery, ascendancy. 48 keystone đều là ngõ cụt, đổi luật kèm cái giá (Chaos Inoculation: máu thành 1, miễn chaos). Mastery: chọn 1 trong 4–6 hiệu ứng.
  - Grim Dawn 1.3.0.8 (grimtools calc, wiki): 250 điểm skill cho 2 cây, lấp khoảng 1/3; thanh mastery 50 rank cho chỉ số gốc (Soldier rank 50: +1,400 máu, +250 physique) và mở tầng skill ở rank 1, 5, 10, 15, 20, 25, 32, 40, 50. Devotion: 55 điểm cho 105 chòm, 559 sao (≈10%); chòm tầng 2–3 cần tích luỹ "affinity" từ chòm trước. Transmuter đổi hành vi skill kèm đánh đổi. Celestial power là hiệu ứng có điều kiện kích hoạt (Turtle Shell: 100% khi máu dưới 50%, hấp thụ 500 → 6,100). Máu cuối cùng gấp 2.5–5.7 lần mức chỉ có thanh mastery; % sát thương chính từ 0 lên 1,130–3,276%. Phần máu theo nguồn: thanh 18–39%, skill 1–7%, devotion 11–18%, đồ 47–64%.
- Chốt bản rút gọn (2026-09-24):
  - Node nhỏ +% cộng dồn cho một nhóm chỉ số, notable mạnh hơn và thêm một luật nhỏ; hệ số nhân (more/less) chỉ ở keystone, keystone là ngõ cụt có cái giá.
  - Giữ 64 node (3 hướng, cổng giữa, 6 keystone; mỗi hướng 4 cụm × 3 nhỏ + 1 notable). Chỉ mở rộng lên 128 (`2 × u64`) nếu sim cho thấy build hội tụ.
  - Nhóm chỉ số: Worker thu nhập, hiệu quả đồ ăn, XP · Fighter sức đánh, % cướp, số đòn/ngày · Survivor tim tối đa, phòng thủ, giảm tim mất khi bị cắn.
  - Level tăng mọi chỉ số gốc. Sau khi lộ tài năng, phần tăng theo level của forage/might/grit nhân theo tài năng; cộng thêm % của cây thì pet có tài năng mới lên mức cực đoan.
  - Tạm bỏ: rank nhiều cấp, mastery chọn 1 trong N, affinity kiểu devotion.
  - Tài năng giữ như D33: một tài năng (forage, might hoặc grit) kèm hạng; chỉ phần tăng theo level của chỉ số đó được nhân.
  - Đổi (user chốt 2026-09-25, phương án A ở G1): tài năng nhân **cả** chỉ số (gốc + hướng + cây + cấp), để mọi hạng đều lộ ra trong block chứ không chỉ elite. Commit `42300a8`.
  - Thứ tự làm: (1) thang tim, đói theo sức mạnh, phần ăn hồi lượng cố định, cắn liên tục; (2) level tăng mọi chỉ số; (3) tài năng lộ ở cấp 10; (4) cây 64 node v2; (5) sim chọn build không theo persona và đo; (6) quét con số, train lại BC/PPO.
- Chốt đói theo sức mạnh (A1): mức đói mỗi ngày là % tim tối đa, nhân theo chỉ số: grit cao đói chậm hơn, might cao đói nhanh hơn, forage cũng làm đói nhanh nhưng ít hơn might. Mọi thứ đều có đánh đổi, nhưng mạnh hơn vẫn phải có lời. Con số chỉnh bằng sim.
- Code (2026-09-24, commit `65952f8`, `rules/tree.ms`): cây v2 đúng bản chốt, 6 keystone Glass Cannon, Tycoon, Cannibal, Berserker, Pacifist, Bulwark; hiệu ứng trong `BRIEF.md` §3.9, bố cục trong `GAME-DESIGN.md` §5.
- Đo được (`msc build sim/builds.ms --release --output=out/builds && out/builds`, tree `9499f0a`, engine `1490032922165168608`): teacher, 4 seed × 200 pet × 120 ngày, mỗi pet nhận ngẫu nhiên 1 trong 5 mục tiêu (4 keystone chạm hướng xuất phát, hoặc "depth" = không keystone); 817 đời, của cải lúc chết so với trung vị chung 38,393 `$HBRN`:

| Hướng xuất phát | Trung vị của cải theo mục tiêu (×trung vị chung) | Chết sớm |
|---|---|---|
| Worker | depth 0.46 · Glass Cannon 0.39 · Tycoon 0.60 · Pacifist 0.95 · Bulwark 0.16 | 0–10% |
| Fighter | depth 2.98 · Glass Cannon 2.14 · Tycoon 2.75 · Cannibal 2.76 · Berserker 3.21 | 0–3% |
| Survivor | depth 1.09 · Cannibal 0.79 · Berserker 1.30 · Pacifist 0.87 · Bulwark 0.31 | 0% |

  - Theo keystone sở hữu (103–126 đời mỗi cái): Berserker 2.34, Tycoon 2.02, Cannibal 1.85, Pacifist 0.90, Glass Cannon 0.63, Bulwark 0.25 (×trung vị). Toàn bộ: p90 ×3.21, top ×4.45.
  - Tài năng khớp hướng xuất phát, Legendary: trung vị ×3.98 (chỉ 4 đời); các hạng khác không khác pet không khớp. Mẫu quá nhỏ để kết luận.
  - Mọi node đều được ít nhất 5% số đời chọn.
  - Cảnh báo: teacher chỉ bank ở lượt cuối ngày, nên harvest của Worker bị cướp trong ba lượt đầu. "Fighter giàu, Worker nghèo" có thể là do teacher, chưa chắc do luật; phải đo lại với policy biết bank sớm (bước 6).
  - Lỗi teacher đã sửa trên đường: teacher tiêu từng điểm ngay nên không bao giờ gom đủ 3 điểm cho keystone (0% đời có keystone); giờ nó giữ điểm khi đã đứng cạnh keystone mục tiêu.
- Chốt node mới: Berserker, mạnh hơn khi tim thấp (A5). Notable Bloodthirst hiện có đọc máu trong trận (fight HP), không đọc tim.
- Phát hiện (2026-09-25, `sim/builds.ms`, engine `6687851897011409549`): Bulwark (tim tối đa ×2, might ×0.5) là bẫy chết — 20% đời chết sớm (Survivor 32%), của cải trung vị ×0.04. Vì đói, cú cắn và thua trận đều tính theo % tim tối đa, còn bữa ăn hồi lượng cố định, nên tim tối đa lớn chỉ là tiền ăn thêm. Đã sửa (đề xuất của agent, áp dụng): Bulwark +100% tim mỗi bữa (`BULWARK_FOOD_BPS`, commit `8b9e86e`) → 3% chết sớm, ×0.41; cú cắn và thua trận thành số tim tuyệt đối (2 tim × tỉ lệ sức 0.5–2, trần 20% tim tối đa; commit `273e260`), đúng ý "sát thương cắn liên tục có trần theo % tim tối đa" → Bulwark ×0.50, 8% chết sớm (112 đời, còn nhiễu). Các keystone khác ×0.87–1.46.
- Sau đồ và phẫn nộ (`sim/builds.ms`, engine `2369342061091774511`): Tycoon ×1.72 (với đói theo % tim tối đa, cái giá "tim ×0.7" thành lợi vì ít đói hơn), Bulwark ×0.43, các keystone khác ×0.86–1.16. Đã chỉnh (đề xuất của agent, commit `441d8a9`): Tycoon forage ×1.5 → ×1.3 (→ ×1.48), Bulwark might ×0.5 → ×0.7 (→ ×0.58, chết sớm 2% → 1%).
- Sau D26 (`sim/builds.ms`, engine `1666978971620739088`): Worker cầm Tycoon chết sớm 6 → 20%, Worker cầm Bulwark 9 → 15%. Truy 38 ca Worker chết sớm: 35 chết đói lúc bình minh, và tối hôm trước đều cháy túi (burrow dưới giá một phần Small, harvest 0, kho trống) — không phải lỗi teacher. Tycoon đói 3–5 tim/ngày trên 12–14 tim tối đa (forage rất cao đẩy khẩu phần lên ~2.5–3.5 lần), Bulwark 6–8 trên 32–40; cả hai là harvest to nhất block nên bị cướp gần như mỗi ngày trước lượt bank đầu tiên. Mở: nguyên tắc "mạnh hơn vẫn phải có lời" (A1) không còn đúng cho Tycoon trên Worker khi bị cướp ~42%.
- Mở: Bulwark vẫn nghèo nhất (×0.5). Pacifist trên Survivor ×0.46 nhưng không chết sớm. "Keystone nào cũng có đất sống" đạt về sống sót, chưa đạt về của cải cho Bulwark.
- Phát hiện (2026-09-25): keystone Cannibal không có tác dụng nào trong code (`Mod.Cannibal` chỉ được gán, không được đọc), dù BRIEF ghi "đòn kết liễu → 50% ví của nạn nhân". Đã cài (commit `6532755`): khi cú cắn giết nạn nhân, kẻ có Cannibal lấy `CANNIBAL_WALLET_BPS` = 50% ví còn lại vào burrow, phần còn lại vẫn chia theo luật chôn cất. Với teacher, kill bằng cú cắn hiếm nên số đo gần như không đổi.

### F2. Worker / Fighter / Survivor (§6 inv. 5, 6, 8) — Có trong code · Đo được

- Tâm lý: ba lối chơi ngang giá trị.
- Chỉ số: thu nhập theo vùng xuất phát.
- Đo (teacher, 4 world, engine `1622489765003688175`): thu nhập mỗi ngày Worker 1,503, Fighter 481, Survivor 461 (Worker / Survivor 3.3 lần, inv. 5 muốn ≈ 3); của cải trung vị hướng giàu nhất / nghèo nhất 2.93 (mục tiêu agent đặt ≤ 1.5). Theo keystone và theo thứ tự lượt: xem F1 và C6.

## G. Kinh tế

### G1. Phân phối thu nhập (D34, §6 inv. 3) — Có trong code · Đo được

- Tâm lý: có đuôi đáng khoe, nhờ may.
- Mục tiêu đã ghi: p90 ×2.6, p99 ×4, top ×20 so với trung vị.
- Phát hiện (2026-09-25): code chia thưởng theo `work_power` tuyến tính, D34 (đã chốt) là `work_power²`. Đã cài (commit `82ad940`, `rewardWeight` trong `rules/stats.ms`).
- Đo (teacher, 4 world, thu nhập mỗi ngày theo pet): tuyến tính p90 2.2, p99 2.6, top 3.0, Worker / Survivor 2.4 lần. `work_power²` thuần: p90 4.7, p99 5.8, top 7.4, Worker / Survivor 5.4 lần — lớp xuất phát đè lên may mắn, và BRIEF §6.5 muốn Worker ≈ 3 lần Survivor.
- Đã sửa (đề xuất của agent, áp dụng): trọng số `(work_power + REWARD_WEIGHT_OFFSET)²`, `work_power` giữ nguyên cho XP. Quét offset (dưới dạng hằng cộng vào `work_power`) 0 / 10 / 25 / 40: Worker / Survivor 5.4 / 4.4 / 3.5 / 2.9 lần, p90 thu nhập 4.7 / 3.9 / 3.2 / 2.6. Chọn 40.
- Đo trên engine `14630790477522747314` (teacher, 8 world): thu nhập p90 2.65, p99 3.11, top 3.75; của cải p90 2.28, p99 3.13, top 3.59. Top ×20 cần items (D35).
- Sàn phần thưởng (D34) đã cài (2026-09-25, commit sau `ba5c53a`): mẫu số = tổng trọng số + `BOT_WEIGHT` (= trọng số một Fighter cấp 20 thường, 8,649) × số slot trống dưới sàn. Trong sim sàn = số slot của world (200), nên bot chính là các slot chưa claim hay đang chờ heir; phần của bot không được mint (đề xuất của agent; BRIEF §10 để mở: đốt, pot hay không mint). Trước đó ngày 1 chỉ ~7 pet chia 100k `$HBRN`.
- Đo sau sàn (teacher, 4 world, engine `9035093710658706689`): thu nhập mỗi ngày Worker 1,587 → 1,304, hướng khác ~540 → ~450; của cải p90 / p99 / top 2.2 / 3.1 / 4.3 → 1.78 / 2.26 / 3.10 (người claim sớm không còn trúng lớn); chết sớm 1.6 → 2.4 trên 100 đời (chủ chăm 0, thỉnh thoảng 2.4, bỏ mặc 4.8); chênh của cải theo hướng 2.1 → 3.4 lần — tiền ăn là chi phí cố định nên đè lên hướng thu nhập thấp (Survivor tiêu ~55% thu nhập cho ăn, Worker ~19%). Mở: cân tiền ăn theo thu nhập hay chấp nhận Survivor nghèo.
- Wild pet (D37, commit sau `d467abb`, đề xuất của agent): mỗi slot trống hiện một wild pet (pet thường ở cấp trung vị của world, không đánh, không chết); harvest của nó là phần của bot trong ngày, hàng xóm cướp được theo luật thường; phần không ai lấy mất lúc bình minh, cọc thua vào tay wild pet về pot. Đo (teacher, 4 world, engine `6058853656672036622`): tiền cướp từ wild pet = 10% thu nhập; trận mỗi pet mỗi ngày 0.42 → 0.56; chết sớm 2.4 → 2.0 trên 100 đời; chênh của cải theo hướng 3.4 → 3.2; của cải p90 / trung vị 1.52 (dưới 2.0: thế giới đều hơn), thu nhập p90 2.73; nhận ra persona 0.88 → 0.83.

- Tài năng có tạo đuôi không (2026-09-25, `out/debug/talentIncome.ms` trong worktree on-chain-ai, teacher, 8 seed, engine `17847782851134087884`, 2,441 đời đã lộ tài năng): tài năng lộ ở cấp 10 (`revealTalent`, mỗi bình minh). Trọng số phần thưởng so với chính pet đó khi không có tài năng: forage Common ×1.02, Rare ×1.06, Epic ×1.17, Legendary ×1.33, Mythic ×1.63; might và grit ×1.00 (không vào thu nhập làm việc). Thu nhập mỗi ngày trung bình so với forage Common: Rare ×0.98, Epic ×1.20, Legendary ×1.54, Mythic ×2.9 (1 đời). Đời giàu nhất 5.8 lần trung vị. Lý do đuôi ngắn: tài năng chỉ nhân phần chỉ số tăng theo cấp (chốt 2026-09-24), trọng số `(work_power + 40)²` làm phẳng, và đồ chưa hoàn vốn nên không ai "mua đồ cho đúng tài năng" (I2). GAME-DESIGN §9 tính Mythic ×7.6–9.3 trên `work_power²` thuần với tài năng nhân cả chỉ số.

- Bốn hướng kéo đuôi, tính trên một Worker cấp 20 điển hình (forage 402 khi chưa có tài năng; `out/debug/talentOptions.ms`, world teacher seed 1 ngày 45; phần thưởng so với pet trung vị, trước khi bị cướp): hiện tại Common / Epic / Legendary / Mythic ×3.1 / 4.0 / 4.6 / 5.9. A (tài năng nhân cả chỉ số): ×3.1 / 4.8 / 6.2 / 9.0. B (giữ luật phần theo cấp, Legendary ×2, Mythic ×3): ×3.1 / 4.0 / 5.9 / 9.6. C (bỏ +40 trong trọng số): ×5.2 / 7.2 / 8.8 / 11.8, và Worker thường thành 5.2 lần Survivor (inv. 5 muốn ≈ 3). D (đồ đúng chỉ số): Mythic hiện tại + 4 món forage Epic ×8.8, + 4 món Mythic ×11.7; A + 4 món Mythic ×18.4. B giữ đuôi ở đỉnh (Epic không đổi), khớp "vài con ×20, còn lại ×1–3" và "tài năng một mình ~×9" của GAME-DESIGN §8.

- Sau A (engine `13571430760533228664`, teacher, 8 seed, `out/debug/talentIncome.ms`): trọng số so với chính pet đó khi không có tài năng: forage Common ×1.04, Rare ×1.12, Epic ×1.33, Legendary ×1.64, Mythic ×2.30 (trước ×1.02 / 1.06 / 1.17 / 1.33 / 1.63). Thu nhập mỗi ngày trung bình so với forage Common: Rare ×1.07, Epic ×1.48, Legendary ×1.98, Mythic ×4.3 (1 đời). Health teacher 4 world: thu nhập p99 / top so với trung vị 3.76 / 4.29 → 4.45 / 5.40; của cải top 2.36 → 3.61; chết sớm 1.75 → 1.39 trên 100 đời; số trận mỗi pet mỗi ngày không đổi (0.55); chênh của cải theo hướng 3.41 → 3.76.

## I. Đồ (items, D35)

### I1. Mint, hao mòn, bán lại — Có trong code (bản đầu) · Đo được

- Tâm lý: chỗ tiêu `$HBRN` khi cấp không còn tốn tiền; có đuôi may mắn (hạng Mythic) nhưng không cho kẻ giàu lăn cầu tuyết mãi (hao mòn).
- Code (2026-09-25, commit `4e675a2`, `rules/items.ms`; strawman của agent theo `GAME-DESIGN.md` §11): 4 ô (đầu, thân, tay, chân) đóng gói trong `Pet`; hạng dùng `TalentGrade`, bảng mint 55 / 30 / 12 / 2.5 / 0.5%, mỗi món +2 / 4 / 7 / 10 / 13% vào một chỉ số bốc ngẫu nhiên (forage, might, grit), hao 1% mỗi ngày. Hành động economy `Mint` (thứ 9): giá `600 × (20 + level) / 20`, giữ món tốt hơn giữa món mới và món yếu nhất đang mặc, món kia bán lại 50% giá mint trừ hao mòn. Chết già thì heir nhận đồ; chết đói hay chết trong trận thì mất đồ. Chưa có skill (hồi sinh, chống cướp, giảm sát thương), chợ, tháo đồ.
- Brain thấy đồ: khối quan sát bản thân tăng từ 32 lên 40 (commit `3af2636`): cờ Relentless và Berserker, bonding, tổng thưởng đồ, món yếu nhất, số lần mint đủ tiền, đói mỗi ngày theo % tim tối đa, lượt mua còn lại. Blob policy 4,463 byte, `POLICY_FORMAT` 2.
- Teacher: mint vào ô trống hoặc thay món đã mòn ≥ 50%, khi giá mint ≤ phần burrow persona chịu tiêu (`Persona.reserveBps`: Cautious giữ 70%, Greedy 30%, Vengeful 50%).
- Lần đo đầu, chỉ số theo hướng xuất phát và teacher mint liên tục để nâng hạng (teacher, 4 world): 58 lần mint mỗi đời, tiêu 51% thu nhập; của cải trung vị sụp từ ~25k xuống 2.6k; thu nhập Worker gấp 4 lần hướng khác (forage + `work_power²`); 3.4 chết sớm trên 100 đời. Đã sửa: chỉ số ngẫu nhiên (đúng "any attribute" của D35) và teacher chỉ mint khi ô trống hoặc món đã mòn.
- Đo sau khi sửa (teacher, 4 world, engine `14428871617754506317`): 4.9 lần mint mỗi đời, 8% thu nhập, đồ cộng trung bình +9.4%; thu nhập p90 / p99 / top so với trung vị 2.79 / 3.34 / 3.63; 1.7 chết sớm trên 100 đời; của cải trung vị theo hướng Worker 31.7k, Fighter 29.0k, Survivor 15.3k (chênh 2.07 lần, trước khi có đồ 1.65); nhận ra persona 0.82.
- Skill (commit sau `331c0f5`, đề xuất của agent theo §11): Epic 10%, Legendary 40%, Mythic 100% có một skill ngẫu nhiên — hồi sinh (một lần, 30% tim tối đa, không đốt ví, món mất skill; chạy trước bảo hiểm), chống cướp (−40% loot), giảm sát thương (+40% guard cho cú cắn và thua trận); cùng skill không cộng dồn. ~2.7% số món có skill, nên số tổng gần như không đổi (teacher, 4 world, engine `3931114478917005264`).
- Theo hướng xuất phát (teacher, cùng lần đo): Worker thu nhập 1,587/ngày, mất 38% vì bị cướp, 1.4 chết sớm trên 100 đời; Fighter 564/ngày, tiền ăn bằng 89% thu nhập làm việc (sống bằng tiền cướp), 3.2 chết sớm; Survivor 528/ngày, mất 9%, 0.5 chết sớm, của cải trung vị ×0.5 so với Worker. Tam giác: Worker giàu mà bị cướp, Fighter liều, Survivor an toàn mà nghèo.
- Mở (F2): "ngang giá trị" đo bằng của cải hay bằng cả sống sót? Mục tiêu ≤ 1.5 lần về của cải agent đặt có thể quá hẹp.
- User chốt 2026-09-26 (câu 4): chấp nhận mức thu nhập (Worker ~3.4 lần Survivor); Fighter và Survivor phải lớn theo tốt, Worker không được quá bá.
- Đo theo hướng (`out/debug/classScale.ms` trong worktree on-chain-ai, teacher, 8 seed, luật chủ cất 50% + quà 5%; của cải mỗi ngày sống, đời ≥ 30 ngày): trung vị Worker 370, Fighter 372, Survivor 270 — ở trung vị Worker không quá bá; chênh nằm ở đuôi và ở tài năng. Theo tài năng trên chỉ số xuất phát, Common → Epic: Worker 383 → 803 (Legendary 994), Fighter 349 → 293 (tài năng might không trả gì), Survivor 262 → 435. Chênh 3.9 lần của bảng H là của cải lúc hết episode, phần lớn là heir mới sinh cầm tài sản thừa kế (Worker 38.7k, Fighter 26.9k, Survivor 9.2k).
- Thử hai đòn bẩy (bản sao, teacher 8 world): (a) tài năng và đồ trên chỉ số xuất phát của Fighter / Survivor nhân trọng số phần thưởng: chênh của cải theo hướng 3.90 → 2.11, thu nhập Worker / Survivor 3.57 → 2.80, chết sớm 1.96 → 2.85 trên 100 đời (bỏ mặc 5.6 → 7.4); (b) chỉ tài năng: chênh 3.90 → 3.31, thu nhập giữ nguyên (Worker 1,488, Fighter 450, Survivor 428), chết sớm 1.96 → 1.96; Common → Epic: Worker 381 → 717, Fighter 363 → 517, Survivor 261 → 570. Chốt (b) (agent, user ủy quyền): giữ mức thu nhập user đã chấp nhận, mỗi hướng lớn theo may mắn của mình, không thêm chết. Code: `rewardBoostBps` trong `Stats`, `startTalentBps` trong `rules/layout.ms`, engine `9237392065831878773`. Đồ trên might / grit vẫn chỉ trả qua cướp và thủ.
- User 2026-09-26 (lượt sau): kiếm tiền là tài năng của Worker; gỡ luật tài năng might / grit nhân trọng số (revert `6e639d1`). Worker chỉ lo kiếm tiền mà chết vì bị cướp là đáng: cây cho nâng xuyên nhánh (grit, máu), nên đó là lựa chọn build, không phải lỗi.
- Bán đồ (commit `93e9a76`, `1a61114`, đề xuất của agent): hành động economy thứ 10 `SellItem` bán món yếu nhất theo giá công thức. Lần đầu teacher chỉ bán khi đã cạn tiền mua phần Small, có ca bán ở lượt cuối ngày rồi chết đêm đó với tiền trong burrow (vi phạm nghiệm thu; pet 194: Fighter Greedy vừa mint 1,200 thì thua cọc hai ngày liền). Đã sửa teacher: bán khi đói mà không đủ tiền phần Large và còn lượt để mua; chỉ mint nếu sau đó còn quỹ ăn 3 ngày. Đo (teacher, 4 world, engine `12482136861935123128`): 0 chết đói khi còn tiền, chết sớm 2.0 → 1.3 trên 100 đời, 29 lần bán trên 100 đời.
- Mở: top ×20 của D34 chưa tới (3.6): với thưởng mỗi món ≤ 13% và offset 40 trong trọng số, may mắn chỉ đẩy được ~×4. Survivor nghèo nhất (ít thu nhập làm việc, gần như không cướp, đồ không giúp thu nhập). Đồ chưa có skill, nên Survivor chưa có món chống cướp.

### I2. Chợ đồ giữa các pet — Có trong code (bản đầu) · Đo được

- Tâm lý: đồ đúng build là thứ mua được bằng tiền, không chỉ nhờ hên (GAME-DESIGN §9: pet ×20 là pet có tài năng Mythic *và* đồ mua cho đúng chỉ số); pet bán đồ lệch build cho hàng xóm cần nó.
- Luật (2026-09-25, commit `0ee2e8b`, `a084f9e`, `0bec2f6`; đề xuất của agent): chỉ số chính của pet là chỉ số cao nhất trong forage, might, grit; món ở chỉ số khác là "đồ thừa". `ListItem` treo món thừa điểm cao nhất, giá `giá mint × điểm món / 360` (360 = điểm trung bình một lần mint, nên món trung bình treo đúng giá mint), mỗi pet một món, 3 ngày; hết hạn thì hệ thống mua lại theo giá bán lại. `BuyItem` mua, trong các món cùng block đủ tiền, món tăng chỉ số chính nhiều nhất, thay vào ô ít có ích nhất (món bị thay bán lại hệ thống); 5% giá vào pot, phần còn lại cho người bán (người bán đã chết thì vào pot). Economy head 12 hành động, 44 feature tự thân (thêm giá món thừa, đang treo, lợi nhất trên chợ, giá của nó); policy format 4, 4,699 byte.
- Chợ theo block, không toàn world: chợ chung làm kết quả phụ thuộc thứ tự xử lý giữa các block (test batch = episode đỏ); trên chain, listing nằm trong account `Block`, không có một account chung bị ghi dồn.
- Teacher: mua trên chợ trước khi mint, cùng điều kiện tiền như mint (giữ quỹ ăn 3 ngày, không quá phần persona chịu tiêu); treo món thừa khi không còn gì làm.
- Đo (teacher, 4 world, engine `1622489765003688175`, so với `6608752566691209999`): 531 món treo mỗi 100 đời, 91% bán được; thưởng đồ trên chỉ số chính 97% (trước là chỉ số ngẫu nhiên); mint mỗi đời 5.3 → 9.0, tiền mint 10.5 → 18.0% thu nhập, tiền mua trên chợ 10.3% thu nhập (chuyển giữa các pet, 5% vào pot); tiền ăn ở cấp 20 55.4 → 51.9% thu nhập; thu nhập p90 / p99 / top so với trung vị 2.73 / 3.36 / 3.82 → 3.07 / 3.77 / 4.70; chênh của cải theo hướng 3.16 → 2.93; chết sớm 2.23 → 2.09 trên 100 đời; nhận ra persona 0.88 → 0.84. File thô `out/health/teacher.market.txt`.
- Mở: giá theo công thức, chưa có pet tự đặt giá; chợ chỉ trong block; chỉ số chính là chỉ số cao nhất, chưa tính tài năng; tiền đồ tổng cộng ~28% thu nhập.
- BC và PPO trên chợ (step18, `~/metacraft/hibernal-train/step18`, commit `0bec2f6`, 8 world, mỗi ghế một bộ điều khiển): 0 illegal cho teacher, clone, PPO 5–7. PPO thắng teacher trong world trộn +35.6 / +43.0 / +29.0% (step15: +18 / +25 / +27%), nhưng gần như không dùng chợ: mint 1.3–1.7 mỗi đời, treo 83–108 món mỗi 100 đời (teacher 531), tiền đồ 2–3% thu nhập; tiền ăn ở cấp 20 32–35%; của cải p90 / trung vị 2.1–2.2 (trong dải); nhận ra persona 0.59–0.73.
- Đồ có hoàn vốn không (teacher, 4 world, engine `1622489765003688175`; bản teacher không mint, không mua trên chợ, chỉ trong bản sao): chết sớm 2.09 → 0.98 trên 100 đời; của cải trung vị chủ chăm 32.6k → 32.3k, thỉnh thoảng 23.8k → 27.0k, bỏ mặc 22.5k → 24.9k; thu nhập Worker 1,502 → 1,287 mỗi ngày. Với giá mint `600 × (20 + cấp) / 20`, thưởng trung bình +3.5% vào một chỉ số và hao 1%/ngày, đồ lỗ vốn: PPO bỏ qua là đúng, teacher mua thì nghèo hơn và chết đói nhiều hơn. Mâu thuẫn với vai trò của đồ (chỗ tiêu `$HBRN`, đường tới đuôi ×20; atlas đặt hoàn vốn 4 ô Mythic ≤ 30 ngày). Mở: đồ phải đáng bao nhiêu — giá, thưởng hay hao mòn.
- Vì sao đồ lỗ: khẩu phần tính trên chỉ số đã cộng đồ (`hungerPerDay` đọc `pet.stats()`), nên món forage hay might làm pet đói hơn; và tiền mua đồ rút vào quỹ ăn. Đo trong bản sao (teacher, 4 world): chết đói / chết sớm trên 100 đời — hiện tại 15 / 2.09; khẩu phần không tính đồ 9 / 1.54; thưởng đồ ×2 27 / 2.55 (thu nhập Worker chỉ +4%); thưởng ×2 và khẩu phần không tính đồ 17 / 2.09; không mua đồ 6 / 0.98. Bộ dò `ITEM_BONUS_PERCENT` 150–300 × giá mint 300–400 với trần chết sớm ≤ 2: thưởng lớn hơn đều tệ hơn (`out/tune/items.tsv`). Đề xuất của agent: khẩu phần chỉ tính chỉ số của chính pet (cây, cấp, tài năng), không tính đồ — đúng nguyên tắc A1 "mạnh hơn vẫn phải có lời"; còn giá trị của đồ (giá, thưởng, hao mòn) là quyết định của user.
- Đã áp dụng (đề xuất của agent, commit `da078ed`, `52ce235`, engine `17847782851134087884`): khẩu phần đọc chỉ số của chính pet (`ownStats` trong `rules/layout.ms`), đồ không làm pet đói hơn. Teacher, 4 world, so với `1622489765003688175`: chết sớm 2.09 → 1.75 trên 100 đời, chết đói 15 → 13; của cải top 3.09 → 2.36; chênh của cải theo hướng 2.86 → 3.41 (Fighter might cao tốn ít tiền ăn hơn). Cần train lại BC và PPO sau khi land step19.
- D (user chốt 2026-09-25: làm cho đồ đáng mua). Lưới đầu, cả world có đồ so với cả world không đồ (`train/payback.py` bản đầu, teacher, 4 world, engine `13571430760533228664`, thưởng đồ 100/200/300% × giá mint 600/300 × hao mòn 100/200 ngày): pet của chủ chăm giàu thêm 1.6–3.7k khi đồ mạnh hơn, nhưng pet của chủ thỉnh thoảng và bỏ mặc hầu như luôn nghèo đi (−0.4 tới −4.1k) và chết sớm tăng tới 3–5 trên 100 đời khi đồ mạnh (không đồ: 1.53). Cách đo này trộn hai hiệu ứng: người mua có lời hay không, và kẻ cướp mặc đồ might thì cướp mạnh hơn. File `out/tune/payback.txt`.
- Đo lại cho đúng câu hỏi "người mua có lời không" (`train/payback.py`): trong cùng một world, nửa số ghế mua đồ, nửa kia không, rồi đổi vai; so từng ghế với chính nó. Hiện tại (thưởng 100%, mint 600, hao hết sau 100 ngày): người mua nghèo hơn 18.6%, chết sớm +1.5 trên 100 đời. Tốt nhất: thưởng 200%, mint 300, bền 200 ngày: người mua giàu hơn 19.3%, thu nhập +188 mỗi ngày, chết sớm +0.46 (trong mức nhiễu). File `out/tune/paybackPaired.txt`, `paybackPaired2.txt`.
- Teacher sửa trên đường (commit `ffebc91`): không tấn công khi một trận thua lấy hết số tim còn lại. Tổng chết sớm gần như không đổi (pet không đánh liều thì chết đói), nhưng đó là cách chơi đúng.
- Đã áp dụng D (user chốt 2026-09-25, commit `eb2671f`, engine `15880631425862158004`): thưởng đồ ×2, giá mint 300, đồ bền 200 ngày. Teacher, 8 world, seed 9001, A + D: thu nhập trung bình so với forage Common: Rare ×1.19, Epic ×1.51, Legendary ×2.9, Mythic ×4.6; thu nhập p90 / p99 / top so với trung vị 3.80 / 5.24 / 8.21; của cải p90 / top 1.62 / 4.29; thưởng đồ trung bình 2,498 bps (97% trên chỉ số chính); tiền mint 8.8% và tiền chợ 4.9% thu nhập. Cái giá: chết sớm 1.5 → 2.7 trên 100 đời (chủ chăm 0, thỉnh thoảng 1.6, bỏ mặc 6.7); thu nhập Worker 1,525 mỗi ngày so với Fighter 402 và Survivor 383 (gấp ~3.8 lần, inv. 5 muốn ≈ 3), vì phần thưởng mỗi ngày là tổng cố định và đồ forage làm Worker ăn phần lớn hơn; chênh của cải theo hướng 4.4.
- Điều chỉnh sau A + D (đề xuất của agent, áp dụng; commit `31a3659`, engine `11177242120393507468`): offset trọng số 40 → 50 (`BOT_WEIGHT` giờ tính từ offset: Fighter thường cấp 20, work power 53). Đo trên A + D, teacher 8 world: offset 40 / 50 / 60: chết sớm 2.74 / 1.70 / 1.81 trên 100 đời (chủ bỏ mặc 6.73 / 3.30 / 4.28); thu nhập p90 3.80 / 3.49 / 3.23, p99 5.24 / 4.49 / 4.20, top 8.21 / 7.21 / 6.30; Worker so với Fighter 3.8 / 3.4 / 3.2 lần; chênh của cải theo hướng 4.39 / 3.35 / 3.03. Chọn 50: đuôi bớt dốc nhưng các tầng vẫn tách, tầng đáy không chết thêm. Engine cuối, teacher 8 world: chết sớm 1.77; thu nhập p90 / p99 / top 3.50 / 4.68 / 7.22; tài năng forage so với Common: Rare ×1.13, Epic ×1.43, Legendary ×2.64.
- Step22 (A + D + offset 50, `~/metacraft/hibernal-train/step22`) không đạt nghiệm thu: clone và PPO 5–7 có 1–2 ca chết khi còn tiền, chết sớm 3.4–4.1 trên 100 đời (teacher 1.77). PPO giờ mua đồ (tiền đồ 7.8–9.6% thu nhập). Truy PPO seed 6 (`~/metacraft/hibernal-train/step22/out/debug/starveTrace.ms`):
  - Lỗ hổng buôn đồ: giá treo tính theo cấp người bán, giá hệ thống mua lại tính theo cấp người cầm, nên mua đồ của pet cấp thấp rồi bán lại ở cấp cao là có lời (pet 166 mua 192, bán 248, làm vậy cả khi đang đói và chết với 323 trong ví). Sửa gốc (commit `86898ce`): món đồ nhớ cấp lúc mint (`Item.level`), mọi giá tính theo cấp đó; test khoá: giá treo của một món luôn ≥ giá hệ thống mua lại nó.
  - Pet 104 là Fighter tài năng might, đói ~11–12 tim/ngày trên 22 (A nhân cả might), mua một phần Large mà không mua phần thứ hai, chết khi còn 15k. Trong thế giới teacher tài năng might Legendary / Mythic đói 25 / 31% tim tối đa mỗi ngày (thường 16–18%) nhưng không chết thêm (0–2%), nên đây là lỗi của policy. Train lại ở step23 sau khi bịt lỗ hổng.
- Step23 (engine đã bịt lỗ hổng, commit `86898ce`): teacher, clone, PPO 5 và 7 sạch; PPO 6 còn 1 ca chết khi còn tiền (pet giàu 11k, cả ngày giữ 10 tim, trông vào bữa sáng của chủ nhưng chết ở tick đêm). Brain học được chết sớm 3.3–4.1 trên 100 đời (teacher 1.87; step20 1.3–2.2): chết đói vì cháy túi PPO 77–91 ca (step20 34), clone 70 (15), teacher 47 (30). Brain giờ mua đồ (PPO 8–10% thu nhập) nhưng không giữ quỹ ăn như teacher. Thêm feature `FoodDays` = số ngày burrow trả được tiền ăn theo mức đói (commit `9ce9e54`, policy format 6, 4,763 byte); train lại ở step24.
- Step24 (commit `9ce9e54`, engine `2583165197786226676`; land `580c4e2` lên `main` local, chưa push): teacher, clone, PPO 5–7 đều 0 illegal và 0 chết khi còn đồ ăn hoặc tiền. Nhưng chết đói vì cháy túi của PPO còn tăng: 122–135 ca trên ~3,000 đời (step23 77–91; teacher 47), chết sớm 4.7–5.1 trên 100 đời (chủ bỏ mặc 9–11); PPO vẫn giàu hơn teacher +7 đến +22% trong world trộn. `FoodDays` không giúp. Reward là thay đổi của cải của pet, nên pet nghèo chết thì mất rất ít; thêm phạt chết vào reward là quyết định của user. Bảng đầy đủ ở `ON-CHAIN-AI.md` §6 package 5e.
- Phạt chết (user chốt 2026-09-26: chết là mất sạch, phải rất tệ, brain phải có ý chí sinh tồn). Trước đó reward phạt chết 500 `$HBRN` (Cautious 1,500) cộng thêm việc mất hết của cải: pet giàu sợ chết, pet nghèo gần như không mất gì. Quét PPO seed 5 từ `bc24` (step25, engine `2583165197786226676`, luật trước khi chủ cất tiền; health 8 world), phạt Greedy / Vengeful 10k / 30k / 100k, Cautious gấp 3:

| | Teacher | 500 (p24s5) | 10k | 30k | 100k |
|---|---|---|---|---|---|
| Chết đói, mọi lý do | 47 | 122 | 146 | 145 | 113 |
| Chết sớm / 100 đời (chung · bỏ mặc) | 1.87 · 3.69 | 4.69 · 8.97 | 5.31 · 10.59 | 5.10 · 10.74 | 4.14 · 10.10 |
| World trộn, chết của PPO vs teacher (hai phía) | – | 35 vs 48 | 49 vs 37 | 44 vs 44 | 31 vs 38 |
| World trộn, của cải PPO so với teacher | – | +21.6% | +23.5% | +23.2% | +5.7% |
| Critic, explained variance cuối | – | 0.97 | 0.97 | 0.95 | 0.69 |

  Phạt lớn gần như không đổi số chết đói; 100k làm critic kém ổn định. Truy theo slot (`health.*.npy` của step24): trong world toàn PPO, pet chết đói gần như toàn là Worker (117/122 seed 5, 130/134 seed 6; teacher 23/47), bị cướp 0.57–0.61 lần mỗi ngày (slot khác 0.30), mất ~50% thu nhập, vẫn mint 76–98 `$HBRN` mỗi ngày (slot khác 44–52). Kẻ cướp PPO nuôi Worker làm mồi; trong world trộn, pet của PPO không chết nhiều hơn pet của teacher. Chốt (agent, user ủy quyền 2026-09-26): phạt 30k (Cautious 90k) — chết mất ngang của cải cả một đời trung bình, critic vẫn ổn — `RewardWeights` trong `sim/env/batch.ms`. Chết đói vì hết tiền của PPO vẫn ~2.5 lần teacher; đây là cạnh tranh giữa các brain, không phải brain nạn nhân bỏ cuộc.
- Step26 (`~/metacraft/hibernal-train/step26`, commit `6d5a7df`, engine `9237392065831878773`: chủ cất 50%, quà 5%, tiêu thẳng harvest, tài năng theo hướng xuất phát, phạt chết 30k): 0 illegal; evaluate 16 world 0 chết khi còn đồ ăn hoặc tiền cho cả năm bộ điều khiển; health 8 world: PPO seed 7 có 1 ca. Chết đói mọi lý do teacher 47, clone 67, PPO 118 / 109 / 106 (step24 PPO 122–135); chết sớm 1.96 / 3.67 / 4.33 / 3.90 / 3.96 trên 100 đời; PPO thắng teacher +22.9 / – / +13.2% trong world trộn (seed 5, 7).
- Truy ca PPO seed 7 (`step26/out/debug/starveTrace.ms`, env 3 pet 37): Fighter đói 6 tim/ngày trên 19, harvest bị lấy sạch mỗi sáng; ngày 55 ăn phần Small còn 268 (Small 327), bán đồ ở lượt cuối (+261 → 529) rồi không còn lượt mua, chết đêm đó với 529 trong burrow. Brain có thấy `Round` và `DawnHearts`, nhưng bán rồi mới mua là kế hoạch hai lượt. Sửa gốc (agent chốt, user ủy quyền; commit `cd4a929`): mua đồ ăn khi ví không đủ cả phần nhỏ nhất thì bán món yếu nhất ngay trong hành động mua (`fundedFor`); chỉ khi không mua nổi phần nhỏ nhất, để không ai bán đồ lấy phần lớn hơn. Teacher cũng chỉ tính đến bán đồ khi ví không mua nổi gì (commit `b550439`): bản đầu cộng giá món đồ vào quỹ, bán đồ để mua phần Large, chết đói 47 → 62; bản sửa 50, chết sớm 2.00 (trong nhiễu). Train lại ở step27.
- Step27 (commit `b550439`): 0 illegal; chết khi còn đồ ăn hoặc tiền: PPO seed 7 1 ca (health), evaluate world trộn 1 ca của clone và 1 ca của PPO seed 7. Chết đói mọi lý do teacher 50, clone 81, PPO 89 / 138 / 113; PPO thắng teacher +26.2 / +6.8 / +34.3% trong world trộn.
- Truy ba ca (`step27/out/debug/starveTrace.ms`, `evalTrace.ms`, thêm đói mỗi ngày, cấp, tài năng): (1) Fighter tài năng might Mythic ×2, đói 12 tim/ngày trên 22, 19k trong ví, sống nhờ bữa Large chủ cho mỗi sáng; thua một trận mất 2 tim, còn 12 tim, cả ngày không mua đồ ăn, chết đêm đó; (2) Fighter might Legendary ×1.6, đói 10/22, 13k, cả ngày 10 tim không mua gì; (3) clone, Worker cấp 12 bị cướp, đánh liên tục, bán đồ để lấy cọc, chết với 566 trong ví (phần Small 269). Cả ba: `DawnHearts` = 0 và ví đủ tiền mà brain không mua — lớp lỗi đã gặp ở step19 và step23. Đói theo tài năng (teacher, `out/debug/talentIncome.ms`): might Common 16%, Legendary 20%, Mythic 31% tim tối đa mỗi ngày trung bình; từng pet cấp 20 tới 45–55%.
- Chốt (agent, user ủy quyền 2026-09-26): phản xạ sinh tồn trong `act` (`survivalMask` trong `sim/world.ms`, `dawnHearts` trong `rules/life.ms`, commit `3e52998`): ở lượt kinh tế cuối ngày, pet sẽ không thức dậy (`dawnHearts` ≤ 0) mà ăn hoặc mua được thì chỉ được ăn hoặc mua; brain học vẫn chọn ăn gì, mua phần nào. Bản bật phản xạ mọi lượt làm teacher chết đói 50 → 65 (cấm cất harvest lúc đang đói nên bị cướp thêm một vòng), thêm bán đồ vào tập sinh tồn cũng vậy (70); bản chỉ lượt cuối: teacher giống hệt step27. Policy cũ `p27s7` và `bc27` chạy trên luật có phản xạ: 0 ca chết khi còn đồ ăn hoặc tiền (health và evaluate). Gỡ: bỏ dòng gọi `survivalMask` trong `economyMaskFor`. Chưa làm: trần độ thèm ăn cho pet might rất cao (đói 45–55% tim mỗi ngày) — là chuyện cân bằng, cần user. Train lại ở step28.
- User 2026-09-26 (lượt sau): để brain tự học — gỡ phản xạ sinh tồn (revert `b93c950`); giữ `dawnHearts` trong luật và luật bán đồ khi mua ăn. Phạt chết là điểm trong reward lúc train, không trừ tiền của ai trong game.
- Trần thèm ăn (user 2026-09-26: "nếu có ý tưởng tốt thì làm thử / đo thử"). Teacher, 8 world, seed 9001, cùng luật chủ mở app trong ngày: base chết đói 55, chết sớm 2.13 trên 100 đời; (A) đói tính từ chỉ số chưa nhân tài năng (như đồ không làm pet đói hơn): 70, 2.74 — tệ hơn, bỏ; (B) trần `MAX_APPETITE_BPS` = 300% (đối xứng sàn 50%): 54, 2.10, might Mythic đói 36 → 31% tim tối đa mỗi ngày. Chốt (B), commit `c90b0a8`, engine `16948401298924711931`: chỉ cắt đuôi 45–55% mà brain hay chết, teacher không đổi.
- Step29 (commit `7ab5e6f`, không phản xạ, không luật tài năng nhân trọng số, có trần thèm ăn và chủ mở app trong ngày): clone và PPO 5–7 0 illegal, 0 chết khi còn đồ ăn hoặc tiền ở cả health và evaluate — brain tự học được. Teacher có 1 ca trong evaluate. Truy (`step29/out/debug/evalTraceTeacher.ms`): Fighter 2/20 tim, đói 5, bán hết 2 món, mua được một phần Small, đêm đó ăn rồi vẫn chết — không có đường sống; bộ đếm xếp vào "còn đồ ăn" vì phần Small nằm trong kho lúc hết ngày. Bữa ăn đêm ăn hết kho khi tim dưới sàn, nên pet đã chết thì kho luôn rỗng: điều kiện "còn đồ ăn" chỉ bắt được báo động giả. Sửa cách đo (commit `ccbae26`): chết đói tính cho brain khi cuối ngày ví còn đủ một phần Small (`Larder.Funded`, dòng "starved with money for a meal" của `health.py`).
- Đo lại step29 với bộ đếm mới (`step29b`, commit `ccbae26`): teacher, clone, PPO 5–7 đều 0 illegal và 0 chết khi còn tiền mua một bữa (evaluate 16 world, health 8 world). Chết đói vì hết tiền 54 / 51 / 97 / 131 / 110; chết sớm 2.10 / 3.61 / 3.77 / 4.68 / 4.15 trên 100 đời; PPO thắng teacher +15.1 / +14.3 / +3.4% trong world trộn; chênh của cải theo hướng trong world PPO 1.7 / 2.0 / 3.0 (teacher 3.7); nhận ra persona PPO 0.71–0.75. Package 5f trong `ON-CHAIN-AI.md` §6, land `4feeb1b` lên `main` local.
- Step28 (commit `3e52998`, engine `9237392065831878773`; package 5f trong `ON-CHAIN-AI.md` §6): teacher, clone, PPO 5–7 đều 0 illegal và 0 chết khi còn đồ ăn hoặc tiền (evaluate 16 world và health 8 world). Chết đói vì hết tiền 50 / 68 / 101 / 113 / 95 (PPO ~2 lần teacher, step24 122–135); chết sớm 2.00 / 4.11 / 3.55 / 3.87 / 3.92 trên 100 đời; PPO thắng teacher +27.5 / +24.6 / +36.1% trong world trộn; chênh của cải theo hướng trong world PPO 1.36–1.56 (teacher 3.3); nhận ra persona PPO 0.77 / 0.62 / 0.66 (mục tiêu 0.8, chỉ báo).
- PPO seed 6 để 1 pet chết đói khi còn tiền (8 world). Truy (`out/debug/starveTrace.ms`): Fighter might rất cao, đói 10 tim/ngày trên 22 tim tối đa, 19k trong ví, không bao giờ tự mua đồ ăn mà sống nhờ bữa Large chủ cho mỗi sáng (sau tick đêm chỉ còn 2 tim); ngày 46 tấn công thua mất 2 tim, chết ở tick bình minh trước khi chủ ghé. Policy thấy tim và mức đói ở hai feature riêng nhưng không thấy trực tiếp "đêm nay có chết không". Đã thêm feature `DawnHearts` = số tim sáng mai tính bằng chính `nightMeals` của tick (commit `ffa703f`, policy format 5, 4,731 byte); train lại ở step19.
- Nghiệm thu trên engine khẩu phần không tính đồ (step20, commit `52ce235`, engine `17847782851134087884`; land `f6dcf6f` lên `main` local, chưa push): teacher, clone, PPO 5–7 đều 0 illegal và 0 chết đói khi còn đồ ăn hoặc tiền (evaluate 16 world và health 8 world). Chết sớm trên 100 đời 1.75 / 1.32 / 1.53–2.15; PPO thắng teacher +55.7 / +37.3 / +38.1% trong world trộn. Clone ở step19 từng để 1 pet chết khi còn tiền (mua Small thay vì bán đồ như teacher, bán muộn một lượt); `bc.py --balance 0.5` (cân nhãn hiếm) sửa được và giờ là mặc định. Bảng đầy đủ ở `ON-CHAIN-AI.md` §6 package 5d.
