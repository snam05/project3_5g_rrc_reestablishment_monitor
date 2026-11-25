# project3_5g_rrc_reestablishment_monitor

Lab OpenAirInterface 5G SA (RFsimulator) để gây Radio Link Failure có kiểm soát và giám sát thủ tục **RRC Reestablishment** của UE. Đề tài Project 3, hạn bàn giao 21/12/2026.

- Hướng dẫn đầy đủ (35 trang): [docs/huong-dan-lab-oai-reestablishment.pdf](docs/huong-dan-lab-oai-reestablishment.pdf)
- Định hướng triển khai từng bước: [docs/HUONG-DAN-TRIEN-KHAI.md](docs/HUONG-DAN-TRIEN-KHAI.md)
- Trạng thái hiện tại: [CONTEXT.md](CONTEXT.md)

## Cây thư mục

```
lab/versions.env       phiên bản OAI và tag image (một chỗ duy nhất)
lab/compose.lab.yaml   lớp phủ lên Compose của OAI (CPU, chanmod, telnet)
lab/lab.sh             script điều khiển: setup, pull, up, status, baseline, rlf, logs, down
lab/fade.py            chạy trong container UE, vặn suy hao kênh downlink qua telnet
lab/upstream/          mã OAI do `lab.sh setup` clone về (Git bỏ qua)
lab/runs/              bằng chứng mỗi lượt chạy (Git bỏ qua)
docs/                  tài liệu
```

## Lệnh chính

Yêu cầu: Linux, Docker Engine, Docker Compose >= 2.36, `/dev/net/tun`, module `sctp`, >= 4 CPU.

```bash
lab/lab.sh setup       # kiểm tra host, clone OAI 2026.w47
lab/lab.sh pull        # tải 7 image
lab/lab.sh up          # Core -> gNB -> UE, chờ UE có IP trên oaitun_ue1
lab/lab.sh baseline    # lưu bằng chứng baseline vào lab/runs/
lab/lab.sh rlf 2.0     # một ca RLF: 65 dB trong 2,0 s ảo, thu log
lab/lab.sh down        # gỡ lab
```

## Tài liệu OAI

- [5G RFsimulator lab README](https://github.com/OPENAIRINTERFACE/openairinterface5g/blob/2026.w47/ci-scripts/yaml_files/5g_rfsimulator/README.md)
- [RFsimulator](https://github.com/OPENAIRINTERFACE/openairinterface5g/blob/2026.w47/radio/rfsimulator/README.md)
- [RRC developer doc](https://github.com/OPENAIRINTERFACE/openairinterface5g/blob/2026.w47/doc/RRC/rrc-dev.md)
