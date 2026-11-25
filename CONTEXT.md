# CONTEXT

Toàn bộ bối cảnh dự án tính đến 25/11/2026, để Claude Code (local) đọc và hỏi đáp tiếp. Cập nhật file này sau mỗi thay đổi đáng kể.

## 1. Đề tài

- Project 3, IT2 HUST. Người làm: Nam. Hạn bàn giao **21/12/2026**.
- Sản phẩm: **giám sát quy trình RRC Reestablishment** trên lab OpenAirInterface 5G SA (RFsimulator): gây RLF có kiểm soát, thu log, gộp log thành một luồng Reestablishment hoàn chỉnh, đo thời gian phục hồi.
- Giảng viên **không đưa yêu cầu hay hướng dẫn nào**: phạm vi và tiêu chí do Nam tự đặt, nên phải chọn mục tiêu trình bày và bảo vệ được.
- 25/11/2026 Nam chọn **đi theo hướng của PDF** `docs/huong-dan-lab-oai-reestablishment.pdf`. Lộ trình chi tiết: [docs/HUONG-DAN-TRIEN-KHAI.md](docs/HUONG-DAN-TRIEN-KHAI.md). Nam sẽ hỏi theo số mục của file đó (ví dụ "làm 3.4").

## 2. Yêu cầu Nam đã nêu (23/11/2026)

- Trước hết **hiểu cách OAI hoạt động** và các thành phần mô phỏng, đủ để trả lời khi bảo vệ.
- **Kịch bản tái hiện được**: chạy lại cùng cấu hình ra cùng chuỗi sự kiện.
- **Kịch bản suy hao ngẫu nhiên**, sinh từ seed ghi lại được.
- **Kiểm tra UE có attach lại được không** sau mất kết nối; phân loại: Reestablishment thành công / fallback RRCSetup rồi đăng ký lại / mất hẳn.
- **`drb_recovery_ms` nằm trong phạm vi** ("tôi sẽ thêm drb recovery"). Nếu build gNB sửa mã trễ quá 6/12 thì chỉ báo `cfg_recovery_ms`, để trống `drb_recovery_ms`.
- Muốn có **website** giám sát (chọn kịch bản/seed, chạy, timeline UE/gNB, kết quả từng lần thử). Chưa chốt có giữ website trong lịch hay không (xem mục 8).
- Thích sơ đồ **đầy đủ khối và bản tin, có nhãn nguồn** (3GPP / OAI); không thích bản rút gọn.
- Ưu tiên tài liệu và sơ đồ vẽ sẵn của OAI (`doc/RRC/rrc-dev.md`) trước khi tự suy từ mã.

## 3. Lab hiện có (theo PDF, kiểm chứng 22/11/2026)

- OAI RAN tag `2026.w47`, commit `75d439de6f4fb37c7e53b21774273f172f18cecb` (mã và image gNB/UE cùng tag). Core OAI CN5G `v2.2.2`, `mysql:9.6`.
- Máy lab: Ubuntu 26.04 arm64, 4 CPU, Docker 29.10.0, Compose 5.8.0, `OAI_LAB_CPUSET=1-3`.
- Các file lab nằm **trên máy lab**, chưa có trên GitHub: `lab/versions.env`, `lab/compose.lab.yaml`, `lab/lab.sh`, `lab/fade.py`, `docs/build.sh`, `docs/src/huong-dan.html`, PDF. `lab/upstream/` và `lab/runs/` bị Git bỏ qua.
- 7 container: `oai-nr-ue` .71.150, `oai-gnb` .71.140 (monolithic), `oai-amf` .71.132, `oai-smf` .71.133, `oai-upf` .71.134/.72.134, `mysql` .71.131, `oai-ext-dn` 192.168.72.135. UE pool 12.1.1.0/24 (DNN `oai`).
- Gây RLF: `fade.py` qua telnet 127.0.0.1:9090 trong UE, `channelmod modify 0 ploss 65` trong 2,0 s ảo (đếm bằng `rfsimu vtime`), rồi về 10 dB. Chỉ suy hao downlink.

### Kết quả đã có

| Run (`lab/runs/…`) | RNTI cũ → mới | t_rrc−t_req | t_cfg−t_req | mất ping |
|---|---|---|---|---|
| `20261122T053947Z-baseline` | | | | ping 10/10 |
| `20261122T054006Z-rlf` | e513 → dc52 | 164,750 ms | 222,500 ms | 5,533 s |
| `20261122T054109Z-rlf` | dc52 → 22e4 | 160,368 ms | 218,715 ms | 5,531 s |
| `20261122T054146Z-rlf` | 22e4 → a307 | 160,472 ms | 220,349 ms | 5,497 s |

Cả 3 ca: 65 dB, 2,0 s ảo, RLF qua lỗi random access (không phải T310), không có fallback `RRCSetup` hay `T311 expired`.

## 4. Đánh giá (23/11/2026)

Mạnh: lab chạy lặp lại, phiên bản/image/hash ghim khớp; baseline + 3 ca RLF đủ chuỗi Reestablishment; chỉ số định nghĩa chặt; PDF 35 trang nối log với hàm OAI và 3GPP.

Yếu:
1. Chưa có tool phân tích, kịch bản có tên, suy hao ngẫu nhiên, website.
2. `drb_recovery_ms` chưa đo được, cần sửa mã gNB (`deliver_sdu_drb()`).
3. 3 ca cùng một đường (lỗi RA, 65 dB, một UE), kết quả gần giống nhau; chưa có fallback `RRCSetup` hay T311.
4. Số đo là thời gian máy dưới giới hạn CPU; RFsim lệch thời gian thực (2 s ảo ≈ 3,7 s thực), nên chỉ có nghĩa "trong điều kiện lab".
5. Telnet UE crash nếu client đóng socket trước khi đọc tới prompt (`lab/runs/20261122T060434Z-telnet-crash/`).

Hướng xử lý: báo số kèm điều kiện lab; ưu tiên thêm ca T311/fallback và kịch bản seed để đa dạng.

## 5. Phát hiện từ mã OAI 2026.w47

Đã đọc `rrc_gNB.c`, `rrc_UE.c`, `rrc_timers_and_constants.c`, `mac_rrc_dl_handler.c`, `f1ap_du_rrc_message_transfer.c`, và `doc/RRC/rrc-dev.md` (đọc qua raw.githubusercontent.com; gitlab.eurecom.fr bị chặn từ cloud).

- `rrc_handle_RRCReestablishmentRequest()` có 4 nhánh: A cùng cell/DU (PCI trùng); B khác DU (PCI khác và assoc_id khác); C quay về cell nguồn khi đang handover (rollback); D PCI khác cùng DU thì fallback RRCSetup ("too fast movement"). Có 7 điều kiện fallback và 3 điều kiện bỏ qua im lặng. Không có nhánh Xn/inter-gNB.
- Lab là intra-gNB, cùng cell, cùng DU. "Khác cell cùng DU" không có nhánh riêng.
- UE chỉ tự phát cause `otherFailure` và `handoverFailure`.
- gNB phát hiện mất UE bằng PUSCH DTX; `UL_FAILURE_TIMEOUT` ≈ 30 s thì F1 Release Request → NGAP release. UE quay lại sau đó sẽ bị fallback (cách tạo ca fallback).
- CellGroupConfig lỗi dùng cause `otherFailure` thay vì `reconfigurationFailure`. T311 dừng ngay khi giải được MIB. Tìm cell chỉ cùng tần số. PDCP AM re-establish không phát lại SDU (khác TS 38.323 §5.1.2).
- gNB monolithic vẫn dùng bản tin F1AP/E1AP nội bộ. CU hỏi CellGroupConfig bằng F1AP UE Context Modification. Fallback gửi NGAP UE Context Release Request.
- Khác biệt `rrc-dev.md` so với mã: (1) doc vẽ E1AP Bearer Context Modification ngay sau RRCReestablishmentComplete, còn mã gửi trong `rrc_gNB_generate_dedicatedRRCReconfiguration()` sau F1 Response; (2) doc vẽ reconfigCellGroup cho cả hai nhánh DU, mã chỉ làm khi tìm thấy UE cũ; (3) doc không vẽ F1 Release Command tới DU cũ.

## 6. Sơ đồ đã vẽ (artifact claude.ai)

- Chi tiết 12 khối, 10 pha, nhãn 3GPP+OAI / OAI / 3GPP, theo `rrc-dev.md` (bản dùng chính): https://claude.ai/artifact/Hy78P5ny1pFjnH35wWDQZE
- Bản đầu 16 khối: https://claude.ai/artifact/3qsWeVsLbGMixzVUFksDyA
- Bản rút gọn 7 khối (Nam chê sơ xài): https://claude.ai/artifact/G19LQsmBEqqrUXrx5Qj74c
- Kế hoạch theo tuần (bản cũ, trước khi chọn hướng PDF): https://claude.ai/artifact/BXab99QW1DJt1pVRk2jmeo

## 7. Định nghĩa phép đo

- `t_req`: gNB nhận RRCReestablishmentRequest (`rrc_gNB.c:1529`).
- `t_rrc`: gNB nhận RRCReestablishmentComplete (`rrc_gNB.c:1313`).
- `t_cfg`: gNB nhận RRCReconfigurationComplete của cấu hình phục hồi (`rrc_gNB.c:2294`, ghép theo xid).
- `t_drb`: gói uplink đầu tiên qua DRB 1 tại gNB (`nr_pdcp_oai_api.c:401` `deliver_sdu_drb()`); cần thêm log `[MEAS]`.
- `cfg_recovery_ms = t_cfg − t_req`; `drb_recovery_ms = t_drb − t_req`. Không suy `t_drb` từ ping.

## 8. Câu hỏi còn mở

- Có giữ website trong lịch không, hay demo bằng CLI + timeline?
- Có cần thêm nhánh "khác cell cùng DU" (cần cấu hình 2 cell) không?
- Đối chiếu file `lab/` trên máy lab với mô tả trong PDF trước khi đưa lên GitHub.

## 9. Tiến độ

Theo [docs/HUONG-DAN-TRIEN-KHAI.md](docs/HUONG-DAN-TRIEN-KHAI.md) mục 6:

- [ ] B1 Hiểu mô phỏng (25–29/11)
- [ ] B2 Dựng lại lab, baseline, 1 ca RLF (26–30/11)
- [ ] B3 Thu log đầy đủ: core.log, pcap (30/11–4/12)
- [ ] B4 Điểm đo `[MEAS]` trong gNB + probe UDP (hạn cứng 6/12)
- [ ] B5 Tool phân tích log (3–10/12)
- [ ] B6 Kịch bản đa dạng: T311, fallback, seed (8–14/12)
- [ ] B7 Chiến dịch đo (12–15/12)
- [ ] B8 Giao diện, nếu giữ website (11–17/12)
- [ ] B9 Báo cáo, demo (15–20/12)
