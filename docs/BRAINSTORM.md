1. Luật game hiện có trong code (rules/ + sim/)

Mỗi pet sống trong một block 10 con, mỗi ngày (epoch) một lượt tick:
- Tiền: pet có harvest (thu nhập từ emission chung, chia theo sức làm việc, bị cướp được) và burrow (kho an toàn). Hành động Bank chuyển harvest vào burrow.
- Đói: mỗi ngày mất 1 tim. Tim sắp chạm sàn thì tự ăn nếu burrow đủ tiền, hết tim thì chết. Pet chủ động ăn 3 loại (Small/Medium/Large) để giữ tim.
- Lên cấp → điểm → cây kỹ năng: mỗi điểm mở một node kề node đã có. Node tăng might/grit/forage… hoặc là notable/keystone đổi luật.
- Đánh nhau: chọn một hàng xóm trong block, đặt cọc 1/4, 1/2, 3/4 hoặc toàn bộ mức trần (trần tính theo harvest của nạn nhân). Thắng thì cướp một phần harvest của nó; thua thì mất cọc và 1 tim. Có giới hạn số đòn mỗi ngày, và pet mới sinh có khiên 3 ngày.
- Chết: tài sản chia cho hàng xóm và đốt một nửa. Sau 7 ngày, một heir vào thế chỗ.

Spec có nhưng chưa có trong sim: item, SKR của chủ, gift/bonding, social, talent, chợ. Đó là phần P0b trong arc.

2. Training hoạt động thế nào

 World giả lập (MetaScript, build thành lib C):
 20 block × 10 pet, 120 ngày, mỗi ngày 4 lượt
 mỗi lượt mỗi pet ra 3 quyết định:  Economy (5) → Node (25) → Attack (41)
            │                                         ▲
            ▼ quan sát (số nguyên)                    │ hành động
 ┌──────────────────────────────────────────────────────────────┐
 │ 1. THẦY: brain luật tay (rules/brain.ms + sim/teacher.ms)     │
 │    theo persona: Cautious ≥70% mới đánh, Greedy ≥50%,         │
 │    Vengeful ≥45% + trả thù                                    │
 │ 2. BC: ghi lại lựa chọn của thầy → mạng nhỏ học bắt chước     │
 │ 3. PPO: mạng tự chơi, reward = Δ(tài sản) + tim − chết        │
 │    + term riêng từng persona (comfort, loss aversion)         │
 │    đối thủ = thầy hoặc snapshot cũ của chính nó               │
 │ 4. ĐÁNH GIÁ: chạy bằng inference int8 viết bằng MetaScript    │
 │    (đúng bản sẽ chạy trên chain), so tài sản với thầy         │
 │    + 4 chỉ số "feel"                                          │
 └──────────────────────────────────────────────────────────────┘
            ▼
 Kết quả: 4 MLP int8, ~4.4k tham số → account ["policy"] → act trên chain (gói 6, chưa làm)

Ý chính: một mạng chung cho cả 3 persona. Persona là một input, và reward khác nhau theo persona. "Mạnh" nghĩa là giàu hơn thầy khi chơi chung một block (+7%). "Feel" nghĩa là hành vi đọc ra được tính cách: không chết đói khi còn tiền, không đánh liều, và nhìn log là đoán được persona.

3. Theo dõi về sau thế nào cho đỡ mất dấu

Tôi đề xuất vài cách, bạn chọn cái nào hợp:
- Xem đời một con pet cụ thể: tôi viết một script in nhật ký 120 ngày của 1–2 pet (ăn gì, bank lúc nào, đánh ai, cọc bao nhiêu, thắng thua, trả thù ai). Nhìn cái này hiểu luật và brain nhanh hơn đọc doc nhiều.
- Mỗi lần báo kết quả: giải thích bằng lời thường trước (chuyện gì xảy ra với con pet), số liệu sau, và định nghĩa thuật ngữ ngay lần đầu dùng.
- Một trang giải thích có hình: luật, vòng lặp training và ý nghĩa từng chỉ số, để đọc lại khi cần. Tôi chỉ làm nếu bạn muốn.