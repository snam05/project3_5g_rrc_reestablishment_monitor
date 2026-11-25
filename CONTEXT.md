# CONTEXT

Sổ trạng thái của dự án. Cập nhật sau mỗi thay đổi đáng kể.

## Phiên bản đang ghim

- OAI RAN: tag `2026.w47`, commit `75d439de6f4fb37c7e53b21774273f172f18cecb` (mã và image gNB/UE cùng tag)
- 5G Core: OAI CN5G `v2.2.2` (AMF, SMF, UPF), `mysql:9.6`, `trf-gen-cn5g:latest`
- Máy kiểm chứng (22/11/2026): Ubuntu 26.04 arm64, 4 CPU, Docker 29.10.0, Compose 5.8.0, `OAI_LAB_CPUSET=1-3`

## Kết quả đã kiểm chứng (22/11/2026)

Thư mục bằng chứng nằm trong `lab/runs/` trên máy lab (không đưa lên Git).

| Run | Kết quả |
|---|---|
| `20261122T053947Z-baseline` | 7 container healthy, UE 12.1.1.2, ping 10/10 |
| `20261122T054006Z-rlf` | RNTI e513 → dc52; t_rrc−t_req 164,750 ms; t_cfg−t_req 222,500 ms; mất ping 5,533 s |
| `20261122T054109Z-rlf` | dc52 → 22e4; 160,368 ms; 218,715 ms; 5,531 s |
| `20261122T054146Z-rlf` | 22e4 → a307; 160,472 ms; 220,349 ms; 5,497 s |

Cả 3 ca RLF: 65 dB trong 2,0 s ảo, RLF qua lỗi random access, không có fallback `RRCSetup` hay `T311 expired`.

## Vướng mắc đã biết

- Client telnet đóng socket trước khi đọc tới prompt làm `nr-uesoftmodem` abort (`buffer overflow detected`). Bằng chứng: `lab/runs/20261122T060434Z-telnet-crash/`.
- RFsimulator chạy chậm hơn thời gian thực (2,0 s ảo ≈ 3,7 s thực): số đo chỉ có nghĩa trong điều kiện lab.
- Chưa có `t_drb` (`drb_recovery_ms`): log OAI mặc định không có điểm đo này.

## Bước tiếp theo

Theo [docs/HUONG-DAN-TRIEN-KHAI.md](docs/HUONG-DAN-TRIEN-KHAI.md) mục 6. Tiến độ:

- [ ] B1 Hiểu mô phỏng
- [ ] B2 Dựng lại lab, baseline, 1 ca RLF
- [ ] B3 Thu log đầy đủ (core.log, pcap)
- [ ] B4 Điểm đo `[MEAS]` trong gNB + probe UDP (hạn cứng 6/12)
- [ ] B5 Tool phân tích log
- [ ] B6 Kịch bản đa dạng (T311, fallback, seed)
- [ ] B7 Chiến dịch đo
- [ ] B8 Giao diện (nếu giữ website)
- [ ] B9 Báo cáo, demo
