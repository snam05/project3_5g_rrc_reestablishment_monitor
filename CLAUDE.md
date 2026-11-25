# CLAUDE.md

Quy tắc cho agent AI làm việc trong repo này.

1. Đọc `CONTEXT.md` trước, rồi `docs/HUONG-DAN-TRIEN-KHAI.md`. Người dùng sẽ hỏi theo số mục của file định hướng (ví dụ "làm 3.4"): bám vào mục đó.
2. Ghép với OAI: mọi lệnh Docker đi qua `lab/lab.sh` (hàm `dc()`), không gọi `docker compose` trơn. Không sửa file trong `lab/upstream/`; thay đổi hành vi bằng `lab/compose.lab.yaml` hoặc cờ dòng lệnh.
3. Phiên bản: đổi OAI thì sửa cùng lúc `OAI_REF`, `OAI_COMMIT`, `TAG` trong `lab/versions.env`, rồi chạy lại `setup → pull → up → baseline`.
4. Đọc trace: cột monotonic của OAI chung cho gNB và UE; dòng `[TELNETSRV]` chỉ có timestamp UTC của Docker. Nối UE và gNB qua dòng `Reestablishment RNTI <mới> req C-RNTI <cũ>`.
5. Định nghĩa phép đo: `cfg_recovery_ms = t_cfg − t_req`, `drb_recovery_ms = t_drb − t_req`. Không suy `t_drb` từ ping. Báo số kèm điều kiện lab (tag, cpuset, tham số fade, n).
6. Sửa mã OAI: làm trên branch hoặc patch trong checkout, ghi commit nền vào `CONTEXT.md`, log điểm đo với tiền tố `[MEAS]` dạng key=value, chạy lại baseline trước khi đo.
7. Telnet của UE: luôn đọc tới prompt rồi mới đóng kết nối; không ngắt `fade.py` giữa chừng.
8. Chỗ chưa kiểm trên máy lab thì ghi rõ "cần xác minh", không khẳng định.
