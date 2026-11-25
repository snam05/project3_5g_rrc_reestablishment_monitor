# CLAUDE.md

Quy tắc cho agent AI làm việc trong repo này.

1. Đọc `CONTEXT.md` trước (bối cảnh đầy đủ: yêu cầu, đánh giá, phát hiện từ mã OAI, sơ đồ, câu hỏi mở), rồi `docs/HUONG-DAN-TRIEN-KHAI.md`. Người dùng sẽ hỏi theo số mục của file định hướng (ví dụ "làm 3.4"): bám vào mục đó.
2. Repo đang trống, chưa chốt cấu trúc. Không tự tạo file hay thư mục ngoài yêu cầu; đề xuất trước, Nam chốt rồi mới làm.
3. Cách dựng lab tham khảo theo PDF `huong-dan-lab-oai-reestablishment.pdf` (ghim OAI tag 2026.w47, không sửa mã OAI trực tiếp mà dùng lớp phủ Compose hoặc cờ dòng lệnh).
4. Đọc trace: cột monotonic của OAI chung cho gNB và UE; dòng `[TELNETSRV]` chỉ có timestamp UTC của Docker. Nối UE và gNB qua dòng `Reestablishment RNTI <mới> req C-RNTI <cũ>`.
5. Định nghĩa phép đo: `cfg_recovery_ms = t_cfg − t_req`, `drb_recovery_ms = t_drb − t_req`. Không suy `t_drb` từ ping. Báo số kèm điều kiện lab (tag, cpuset, tham số fade, n).
6. Sửa mã OAI: làm trên branch hoặc patch trong checkout, ghi commit nền vào `CONTEXT.md`, log điểm đo với tiền tố `[MEAS]` dạng key=value, chạy lại baseline trước khi đo.
7. Telnet của UE: luôn đọc tới prompt rồi mới đóng kết nối; không ngắt `fade.py` giữa chừng.
8. Chỗ chưa kiểm trên máy lab thì ghi rõ "cần xác minh", không khẳng định.
9. Commit và PR không ghi Claude là đồng tác giả, không thêm footer nhắc Claude.
