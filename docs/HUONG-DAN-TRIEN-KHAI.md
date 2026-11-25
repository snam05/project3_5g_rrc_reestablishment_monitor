# Định hướng triển khai: Lab OAI 5G giám sát RRC Reestablishment

Bản 25/11/2026 · hạn bàn giao 21/12/2026 · bám theo `huong-dan-lab-oai-reestablishment.pdf` (gọi tắt **PDF**, số mục ghi dạng PDF §x.y).

File này là bản đồ. Mỗi mục có số (ví dụ **3.2**) để hỏi dần: "hướng dẫn tôi làm 3.2". Ký hiệu:

- ⚠️ **Cần xác minh**: chưa kiểm trên máy lab của Nam, hoặc chưa đọc tới mã OAI. Không dùng như sự thật cho tới khi kiểm.
- ✅ **Đã có**: PDF ghi đã chạy được ngày 22/11/2026.

> ⚠️ Các file `lab/` trong repo được dựng lại từ phụ lục mã nguồn của PDF (§11.3) ngày 25/11/2026, không chép từ máy lab. `CONTEXT.md` và `CLAUDE.md` viết mới theo nội dung PDF. Nếu máy lab có bản gốc khác, bản gốc thắng (xem **2.0**).

---

## Mục lục

1. Hiểu mô phỏng
2. Triển khai từng bước
3. Test và kích hoạt Reestablishment
4. Thu log
5. Tool phân tích: gộp log rời rạc thành một luồng Reestablishment
6. Mốc thời gian tới 21/12/2026 và tiêu chí hoàn thành

---

## 1. Hiểu mô phỏng

### 1.1 Bức tranh một câu

Một mạng 5G SA thu nhỏ gồm 7 container Docker (theo Compose mẫu của OAI). "Sóng radio" là mẫu IQ gửi qua TCP cổng 4043 (RFsimulator), nên ta có thể tăng suy hao bằng phần mềm để gây Radio Link Failure (RLF), rồi quan sát UE tự nối lại bằng RRC Reestablishment. (PDF §1)

### 1.2 Các thành phần

| Thành phần | Container · IP | Vai trò | Ghi nhớ khi bảo vệ |
|---|---|---|---|
| UE mô phỏng | `oai-nr-ue` · 192.168.71.150 | `nr-uesoftmodem`: điện thoại 5G (RRC/PDCP/RLC/MAC/PHY + NAS) | Là client RFsim; bật `chanmod` và telnet :9090 để vặn suy hao |
| gNB | `oai-gnb` · 192.168.71.140 | `nr-softmodem` monolithic (CU+DU một tiến trình) | Là server RFsim (TCP 4043); nhận `RRCReestablishmentRequest` |
| AMF | `oai-amf` · .71.132 | Đăng ký, di động, NAS; N2 (NGAP/SCTP 38412) | Cấu hình "mini": AMF tự làm AUSF/UDM, đọc thuê bao từ MySQL |
| SMF | `oai-smf` · .71.133 | Quản lý PDU session, cấp IP UE, điều khiển UPF qua N4 (PFCP) | Giữ **UE pool** 12.1.1.0/24 |
| UPF | `oai-upf` · .71.134 (N3) / .72.134 (N6) | Chuyển gói user plane: GTP-U ↔ IP | Đầu cuối tunnel GTP-U phía core |
| MySQL | `mysql` · .71.131 | CSDL thuê bao (`oai_db.sql`) | IMSI/key/OPc phải khớp `nrue.uicc.yaml` |
| ext-dn | `oai-ext-dn` · 192.168.72.135 | "Internet" của lab, đích ping/probe | Có route 12.1.1.0/24 qua 192.168.72.134 (UPF) |

### 1.3 Mạng 192.168.71.x và 192.168.72.x

- `public_net` 192.168.71.128/26, bridge `rfsim5g-public`: mọi thứ của RAN và core: RFsim (TCP 4043), N2 (NGAP/SCTP), N3 (GTP-U/UDP 2152), N4 (PFCP), SBI, SQL.
- `traffic_net` 192.168.72.128/26, bridge `rfsim5g-traffic`: chỉ có N6, nối UPF (eth1 .72.134) với ext-dn (.72.135).
- Tách hai mạng để mô phỏng đúng kiến trúc: mạng nhà mạng (RAN + core) tách khỏi mạng dữ liệu bên ngoài (N6).

### 1.4 `oaitun_ue1` và UE pool

- `oaitun_ue1` là giao diện TUN do `nr-uesoftmodem` tạo khi có PDU session. Gói đi vào TUN được UE đưa xuống SDAP → PDCP → RLC → MAC → PHY. Vì vậy container UE cần `/dev/net/tun`, và ping phải có `-I oaitun_ue1` (không thì gói đi `eth0`, bỏ qua 5G).
- **UE pool** là dải IP SMF cấp cho UE: DNN `oai`, IPv4 12.1.1.0/24 (trong `mini_nonrf_config.yaml`). UE thường nhận 12.1.1.2; tạo lại UE có thể nhận IP khác (PDF §9 ghi lần thử nhận 12.1.1.4).
- Địa chỉ 12.1.1.x không có trên dây nào trong `public_net`: nó chỉ tồn tại *bên trong* tunnel GTP-U.

### 1.5 GTP-U "giống VPN"

Giống:
- Gói IP của UE (nguồn 12.1.1.2, đích 192.168.72.135) được bọc nguyên trong gói khác: IP ngoài 192.168.71.140 ↔ 192.168.71.134, UDP 2152, header GTP-U có **TEID** (mã tunnel).
- Hai đầu tunnel (gNB và UPF) bóc/bọc, mạng ở giữa chỉ thấy IP ngoài. Đúng như VPN site-to-site.

Khác:
- GTP-U **không mã hóa**. Bảo mật của user plane nằm ở PDCP trên giao diện vô tuyến; N3 có thể thêm IPsec nhưng lab không dùng.
- Tunnel do control plane dựng: SMF chọn TEID, báo UPF qua PFCP (N4) và báo gNB qua AMF/NGAP (PDU Session Resource Setup). Hai đầu không tự "bắt tay" như VPN.
- Một tunnel cho mỗi PDU session (theo QoS flow), không phải một tunnel cho cả site.

Chứng minh khi bảo vệ: `tcpdump -i rfsim5g-public udp port 2152` rồi mở Wireshark thấy hai lớp IP (xem **4.4**).

### 1.6 Đường đi một gói ping (PDF §1.3)

`ping -I oaitun_ue1 192.168.72.135` → TUN → SDAP/PDCP/RLC/MAC/PHY của UE → mẫu IQ uplink qua TCP 4043 → gNB giải mã lên PDCP → `deliver_sdu_drb()` (điểm `t_drb`) → SDAP bọc GTP-U → UPF (N3) → bóc tunnel, SNAT → eth1 → ext-dn. Phản hồi đi ngược lại.

⚠️ UPF bật `enable_snat: yes` nhưng ext-dn lại có route 12.1.1.0/24 về UPF. Cần xác minh ext-dn thấy nguồn là 12.1.1.2 hay 192.168.72.134 (bắt gói trên `rfsim5g-traffic`, xem **4.4**).

### 1.7 RRC Reestablishment trong lab (PDF §6)

1. Tăng suy hao downlink lên 65 dB (`fade.py`).
2. UE gửi SR 64 lần không được phục vụ → MAC làm RA → không nghe được RAR → **lỗi RA = RLF** (TS 38.331 §5.3.10.3). Lab đi đường này, không phải đường T310.
3. UE có AS security + SRB2 + DRB nên bắt đầu Reestablishment (cause `otherFailure`): dừng T310, chạy T311, treo SRB/DRB, reset MAC, tìm cell.
4. Kênh về 10 dB → UE sync lại PCI 0 → RA → Msg3 = `RRCReestablishmentRequest` (C-RNTI cũ, PCI cũ, shortMAC-I).
5. gNB tìm được context cũ → `RRCReestablishment` (SRB1 re-establish) → UE trả `RRCReestablishmentComplete`.
6. gNB re-establish SRB2/DRB, gửi `RRCReconfiguration` (xid N) → UE trả `RRCReconfigurationComplete`.
7. Gói UL đầu tiên qua DRB 1 tại gNB = `t_drb`.

Nhánh thất bại cần nhận diện: gNB fallback `RRCSetup`; T311 hết hạn → IDLE; T301 hết hạn.

Sơ đồ chi tiết (12 khối, nhãn OAI/3GPP): https://claude.ai/artifact/Hy78P5ny1pFjnH35wWDQZE

### 1.8 Câu hỏi bảo vệ và trả lời ngắn

**Kiến trúc**

1. *Lab gồm những gì?* 7 container: UE, gNB, AMF, SMF, UPF, MySQL, ext-dn; theo Compose mẫu của OAI, dự án chỉ thêm lớp phủ `compose.lab.yaml` và script `lab.sh`.
2. *Không có radio thì "sóng" ở đâu?* RFsimulator: gNB và UE trao đổi mẫu IQ qua TCP 4043. Channel model của UE thêm suy hao và nhiễu AWGN vào mẫu downlink.
3. *Vì sao hai mạng 192.168.71 và 72?* 71 là mạng nhà mạng (RAN, N2, N3, N4, SBI); 72 là N6 ra mạng dữ liệu. Tách đúng như kiến trúc 5G.
4. *`oaitun_ue1` là gì?* Giao diện TUN UE tạo khi có PDU session; ứng dụng gửi gói vào đây thì gói đi qua ngăn xếp 5G.
5. *UE lấy IP ở đâu?* SMF cấp từ UE pool 12.1.1.0/24 của DNN `oai`, gửi về UE trong NAS PDU Session Establishment Accept.
6. *GTP-U khác VPN thế nào?* Cùng ý tưởng bọc IP trong IP/UDP, nhưng không mã hóa, mỗi PDU session một tunnel (TEID), và tunnel do SMF dựng qua PFCP/NGAP.
7. *gNB monolithic nghĩa là gì?* CU và DU chạy chung một tiến trình; trong OAI các khối vẫn trao đổi bằng bản tin F1AP/E1AP nhưng truyền nội bộ.
8. *Vì sao ghim tag 2026.w47 cho cả mã và image?* Để mã đọc được trùng với binary đang chạy (hash in ra lúc khởi động trùng commit checkout).

**Thủ tục**

9. *RLF là gì, UE phát hiện thế nào?* Mất liên kết vô tuyến. Theo 38.331 §5.3.10.3: T310 hết, lỗi RA, RLC đạt max retx… Lab phát hiện bằng lỗi RA (khoảng 0,75 s sau khi tăng suy hao).
10. *Vì sao không phải T310?* SR hết lượt trước khi đủ N310 lần out-of-sync, MAC làm RA và RA thất bại sớm hơn T310 (2000 ms).
11. *Điều kiện để Reestablishment thay vì về IDLE?* Đã có AS security, SRB2 và ít nhất một DRB (`handle_rlf_detection()`).
12. *Reestablishment lợi gì so với kết nối lại từ đầu?* Giữ context ở gNB (khóa, bearer, PDU session) nên không phải đăng ký lại với core; nhanh hơn và giữ được IP.
13. *Request chứa gì?* C-RNTI cũ, PCI cũ, shortMAC-I, cause. gNB dùng C-RNTI + PCI để tìm context cũ. ⚠️ Cần xác minh OAI có kiểm shortMAC-I hay không.
14. *Vì sao log có hai RNTI?* UE gửi C-RNTI cũ (vd. e513) để tìm context; sau RA nó có TC-RNTI mới (dc52). Dòng `Reestablishment RNTI dc52 req C-RNTI e513` nối hai giá trị.
15. *Khi nào gNB fallback RRCSetup?* Không tìm thấy/không dùng được context cũ (UE đã bị release, PCI khác cùng DU…). Mã w47 có 7 điều kiện fallback.
16. *T311 dùng làm gì?* Thời gian tối đa UE tìm cell phù hợp sau RLF (3000 ms); hết hạn → IDLE.
17. *Tìm cell mất 4,1 s mà T311 = 3 s sao không hết hạn?* 4,1 s là thời gian thực; timer OAI chạy theo thời gian mô phỏng, và RFsim chạy chậm (2,0 s ảo ≈ 3,7 s thực).
18. *Bảo mật sau Reestablishment?* UE và gNB dẫn xuất khóa mới (KgNB* theo NCC trong `RRCReestablishment`), SRB1 dùng khóa mới ngay; SRB2/DRB được re-establish qua RRCReconfiguration.

**Đo đạc và giới hạn**

19. *Đo cái gì?* `cfg_recovery_ms = t_cfg − t_req` (đã có từ log) và `drb_recovery_ms = t_drb − t_req` (cần điểm đo trong gNB). 3 ca đầu: `t_rrc − t_req` ≈ 160–165 ms, `t_cfg − t_req` ≈ 219–223 ms.
20. *Vì sao không đo bằng ping?* Ping phụ thuộc chu kỳ gửi và RTT; mất ping 5,5 s chủ yếu là thời gian giữ suy hao và tìm cell, không phải thời gian Reestablishment.
21. *Số đo có ý nghĩa ngoài đời không?* Chỉ "trong điều kiện lab": RFsim lệch thời gian thực, phụ thuộc CPU. Vì vậy giữ cố định cpuset và báo kèm điều kiện.
22. *Tái hiện thế nào?* Phiên bản ghim (tag + digest), suy hao tính theo thời gian ảo (`rfsimu vtime`), kịch bản ghi tham số và seed vào `params.txt`.
23. *Giới hạn của lab?* Một gNB, một cell, một UE; không có Xn/inter-gNB; chỉ suy hao downlink; RLF chỉ đi đường lỗi RA (chưa có ca T310/T311/fallback cho tới khi làm **3.4**).

---

## 2. Triển khai từng bước

Thứ tự bắt buộc: Core → gNB → UE (README OAI mục 2: "Just docker-compose up -d WILL NOT WORK!"). Lệnh lấy từ PDF §7, §11.1.

### 2.0 Đồng bộ repo với máy lab (làm trước tiên)

Trên máy lab (Ubuntu), trong thư mục dự án cũ:
```bash
git remote -v                     # nếu chưa nối với GitHub: git remote add origin <url repo>
git fetch origin
git diff origin/main -- lab/      # so file lab của máy với bản trên GitHub
```
Có khác biệt thì giữ bản của máy lab (đã chạy thật) và đẩy lên. Nếu máy lab chưa có repo: `git clone` repo này rồi chạy **2.1**.

Xong khi: `lab/` trên GitHub trùng với bản đang chạy trên máy lab.

### 2.1 Chuẩn bị host (PDF §7.1)

```bash
docker version; docker compose version     # Compose >= 2.36.0
ls -l /dev/net/tun
lsmod | grep sctp || sudo modprobe sctp
nproc; df -h                               # >= 4 CPU, ~10 GB trống
ip route | grep -E '192\.168\.7[12]\.'     # không trùng subnet
```

### 2.2 Lấy mã và image (PDF §7.2)

```bash
lab/lab.sh setup     # clone OAI 2026.w47, kiểm commit 75d439de…, kiểm cú pháp Compose
lab/lab.sh pull      # 7 image; nếu bị rate limit: docker login
```

### 2.3 Khởi động (PDF §7.3)

```bash
lab/lab.sh up        # Core healthy → gNB thấy NGSetupResponse → UE có IP trên oaitun_ue1
lab/lab.sh status    # ps, IP UE, ping 5 gói tới 192.168.72.135
```
Kỳ vọng: 7 container healthy, `oaitun_ue1: 12.1.1.x/24`, ping 0% loss, TTL 63. Tổng khoảng 1 phút.

### 2.4 Baseline (PDF §7.5)

```bash
lab/lab.sh baseline  # lưu lab/runs/<UTC>-baseline/
```
Đọc lại luồng gắn mạng trong `gnb.log`/`ue.log` và so với PDF Hình 8 (RA → RRCSetup → Security → Registration Accept → PDU Session → DRB 1).

### 2.5 Khi một bước không qua

Theo PDF §9, Hình 11 (8 tình huống). Nguyên tắc: lỗi ở bước sau thường do bước trước. Khi nghi ngờ, `lab/lab.sh down` → `up` → `status`.

### 2.6 Các lệnh hay dùng

| Lệnh | Tác dụng |
|---|---|
| `lab/lab.sh logs` | Theo dõi log gNB + UE |
| `lab/lab.sh compose exec oai-nr-ue bash` | Vào shell UE |
| `lab/lab.sh compose config oai-nr-ue` | Xem cấu hình cuối sau khi ghép |
| `OAI_LAB_CPUSET=2-3 lab/lab.sh up` | Đổi tập CPU (phải giữ cố định giữa các lần đo) |
| `lab/lab.sh down` | Gỡ toàn bộ lab |

---

## 3. Test và kích hoạt Reestablishment

### 3.1 Công cụ

| Công cụ | Chạy ở đâu | Dùng để |
|---|---|---|
| `lab/lab.sh rlf` | host | Điều phối một ca: ping nền + fade + thu log + `summary.txt` |
| `lab/fade.py` | trong container UE (qua stdin) | Nói với telnet :9090: `channelmod modify 0 ploss <dB>`, đếm thời gian ảo bằng `rfsimu vtime` |
| telnet server OAI | trong UE, chỉ 127.0.0.1:9090 | Vặn kênh khi đang chạy |
| `ping -D` | trong UE | Quan sát mất/khôi phục user plane (thô) |
| probe UDP | UE → ext-dn | (Sẽ làm, **4.6**) đo user plane có số thứ tự |

Lưu ý an toàn: không Ctrl+C `fade.py` giữa chừng; không viết client telnet "gửi rồi đóng" (làm UE crash, PDF §4.4).

### 3.2 Ca chuẩn (đã có ✅)

```bash
lab/lab.sh rlf 2.0                 # 65 dB trong 2,0 s ảo
cat lab/runs/<UTC>-rlf/summary.txt
```
Kỳ vọng: UE `Initiating RRC re-establishment (cause=otherFailure)`; gNB `Reestablishment RNTI <mới> req C-RNTI <cũ>` → `Send RRCReestablishment` → `Received RRCReestablishmentComplete` → `Received RRCReconfigurationComplete`; ping trở lại.

### 3.3 Đổi tham số

```bash
lab/lab.sh rlf 3 --loss 70          # 70 dB trong 3 s ảo
PING_WINDOW=45 lab/lab.sh rlf 5     # fade dài, cửa sổ quan sát dài hơn
```

### 3.4 Các ca cần thêm để đa dạng kết quả

| Ca | Cách tạo (đề xuất) | Dấu hiệu trong log | Trạng thái |
|---|---|---|---|
| A. Thành công | `rlf 2.0` | đủ 4 mốc gNB | ✅ |
| B. T311 hết hạn | fade dài theo giây ảo, ví dụ `rlf 4`, `rlf 6` | UE `Timer T311 expired` | ⚠️ chưa chạy; thử tăng dần |
| C. Fallback RRCSetup | để gNB xóa context trước khi UE quay lại (UE mất lâu hơn `UL_FAILURE_TIMEOUT` ≈ 30 s theo mã w47) | gNB `RRCSetup` ngay sau request | ⚠️ chưa chạy; ngưỡng cần đo |
| D. RLF qua T310 | suy hao vừa phải (để có out-of-sync nhưng SR chưa hết) | UE `Timer T310 expired` | ⚠️ chưa chắc tạo được; thử quét `--loss` |
| E. Ngẫu nhiên theo seed | mở rộng `fade.py`: chuỗi (thời gian, mức suy hao) sinh từ seed, ghi seed vào `params.txt` | tùy | chưa làm |

Mỗi ca chạy ít nhất 5 lần với cùng cấu hình để thấy độ lặp lại.

### 3.5 Kịch bản khai báo (tái hiện được)

Đề xuất: mỗi kịch bản là một file nhỏ, ví dụ `scenarios/t311.yaml` (tên, các bước `{loss_db, virtual_s}`, seed, số lần lặp). `lab.sh rlf` (hoặc script mới) đọc file đó và ghi nguyên nội dung vào thư mục run. Chi tiết làm ở bước B6 (mục **6**).

---

## 4. Thu log

### 4.1 Nguồn log và vị trí

Mỗi lượt `rlf` tạo `lab/runs/<UTC>-rlf/`:

| File | Nguồn | Đồng hồ trên mỗi dòng |
|---|---|---|
| `gnb.log` | `docker compose logs --timestamps oai-gnb` | UTC của Docker **và** monotonic của OAI (giây) |
| `ue.log` | như trên, `oai-nr-ue` | UTC Docker + monotonic OAI; dòng `[TELNETSRV]` chỉ có UTC |
| `ping.txt` | `ping -D` trong UE | epoch (giây) |
| `fade.txt` | stdout `fade.py` | không có; chỉ có `virtual=… wall=…` |
| `params.txt` | `lab.sh` | `started=` UTC |
| `summary.txt` | grep của `lab.sh` | dẫn số dòng |
| `versions.txt` | chỉ baseline | không |

Chưa thu nhưng nên thêm: `core.log` (AMF/SMF/UPF) cho ca fallback (thấy NGAP UE Context Release), log probe (**4.6**), pcap (**4.4**).

### 4.2 Ba đồng hồ và cách nối

- Monotonic OAI: chung cho gNB và UE (cùng kernel host) → so trực tiếp giữa hai file.
- UTC Docker: có trên mọi dòng log container → dùng cho telnet và nối với ping/probe (epoch).
- Cùng một dòng có cả UTC Docker và monotonic, nên tool tính được độ lệch `offset = utc − monotonic` rồi quy mọi sự kiện về một trục (**5.4**).

### 4.3 Bật mức log chi tiết

- Hiện tại lab có `--log_config.global_log_options level,nocolor,time` (UE). ⚠️ Cần xác minh gNB có cùng cờ không: `lab/lab.sh compose config oai-gnb | grep USE_ADDITIONAL_OPTIONS`.
- Mức log theo module dùng dạng `--log_config.<module>_log_level <level>` (ví dụ `debug`), thêm vào `USE_ADDITIONAL_OPTIONS`. ⚠️ Tên module chính xác (nr_rrc, nr_mac, pdcp…) cần đọc `common/utils/LOG/` tại tag 2026.w47.
- Muốn đổi cho gNB phải thêm khối `oai-gnb.environment.USE_ADDITIONAL_OPTIONS` vào `compose.lab.yaml`, chép nguyên chuỗi gốc của OAI rồi nối cờ mới (Compose thay cả chuỗi, PDF §4.2).
- ⚠️ Telnet của OAI có lệnh đổi mức log lúc đang chạy; cú pháp cần kiểm trong `telnetsrv.md`.
- Không bật debug cho mọi thứ khi đo: log nhiều làm chậm RFsim và lệch số đo. Bật debug chỉ để hiểu; khi đo dùng `info` + log `[MEAS]`.

### 4.4 Bắt gói (pcap)

Trên host:
```bash
# N2 (NGAP/SCTP), N3 (GTP-U 2152), N4 (PFCP 8805)
sudo tcpdump -i rfsim5g-public -w lab/runs/<UTC>-rlf/cp_n3.pcap 'sctp or udp port 2152 or udp port 8805'
# N6
sudo tcpdump -i rfsim5g-traffic -w lab/runs/<UTC>-rlf/n6.pcap
```
- Không bắt TCP 4043: đó là mẫu IQ, Wireshark không giải được.
- Bản tin RRC không đi trên mạng Docker (gNB monolithic, RRC nằm trong mẫu IQ). Muốn thấy RRC trong Wireshark cần module pcap/tracer của OAI. ⚠️ Cần xác minh ở tag w47: tùy chọn `--opt.type pcap --opt.path …` (MAC-NR pcap) hoặc T tracer.
- Nên tích hợp tcpdump vào `lab.sh rlf` (chạy nền, dừng khi hết cửa sổ).

### 4.5 Điểm đo `[MEAS]` trong gNB (PDF §10.1)

Thêm log một dòng, dạng key=value, ngay tại:

| Mốc | Hàm (tag w47) |
|---|---|
| `t_req` | đầu `rrc_handle_RRCReestablishmentRequest()` `rrc_gNB.c:1529` |
| `t_rrc` | `rrc_gNB_process_RRCReestablishmentComplete()` `rrc_gNB.c:1313` |
| `t_cfg` | `handle_rrcReconfigurationComplete()` `rrc_gNB.c:2294` (kèm xid) |
| `t_drb` | `deliver_sdu_drb()` `nr_pdcp_oai_api.c:401` (chỉ gói probe hoặc gói đầu sau `t_req`) |

Ví dụ: `[MEAS] ev=t_req ts_ns=… rnti=dc52 old_crnti=e513 pci=0 cause=otherFailure`.
Build và chạy gNB đã sửa theo PDF §10.2 (`local-override.yaml` hoặc image riêng). Nếu tới 6/12 chưa build được: chỉ báo `cfg_recovery_ms`, để trống `drb_recovery_ms`.

### 4.6 Probe UDP

- Gửi: script Python trong UE, gửi qua `oaitun_ue1` tới 192.168.72.135, chu kỳ 50 ms, payload `seq,t_send_ns`.
- Nhận: script trong ext-dn, ghi `seq,t_send_ns,t_recv_ns` ra file.
- `lab.sh rlf` khởi động cả hai trước fade, thu file về thư mục run.

---

## 5. Tool phân tích: gộp log thành một luồng Reestablishment

### 5.1 Mục tiêu

Đầu vào: một thư mục `lab/runs/<UTC>-rlf/`. Đầu ra: mỗi lần thử Reestablishment là một chuỗi sự kiện có thứ tự, có mốc, có kết quả phân loại, và mỗi sự kiện dẫn được về dòng log gốc.

### 5.2 Cấu trúc đề xuất

```
monitor/
  reest_monitor/
    sources.py      # đọc từng file log → Event thô
    catalog.py      # bảng regex → loại sự kiện (bảng 5.3)
    clock.py        # nối đồng hồ (5.4)
    correlate.py    # gom sự kiện thành attempt (5.5)
    classify.py     # phân loại kết quả (5.6)
    export.py       # CSV, JSON, Markdown timeline
  cli.py            # python -m reest_monitor <run_dir>
  tests/fixtures/   # 3 run thật đã có + run giả cho fallback/T311
```
Python thuần (thư viện chuẩn), để chạy được ở mọi máy. Website (nếu làm) chỉ đọc JSON đầu ra.

### 5.3 Danh mục sự kiện (đối chiếu sơ đồ)

| Mã | Phía | Regex gợi ý (theo PDF §6.4) | Pha trong sơ đồ |
|---|---|---|---|
| E00 | UE telnet | `channelmod modify 0 ploss (\d+)` | Gây sự cố (LAB) |
| E01 | UE | `Error decoding PBCH` (lần đầu) | DL hỏng |
| E02 | UE | `SR not served!.*sr_MaxTransmissions` | Phát hiện RLF |
| E03 | UE | `Triggering new RA procedure` | Phát hiện RLF |
| E04 | UE | `RAR reception failed` (lần đầu/lần cuối) | Phát hiện RLF |
| E05 | UE | `Timer T310 expired` | Phát hiện RLF (T310) |
| E10 | UE | `Initiating RRC re-establishment \(cause=(\w+)\)` | Bắt đầu, T311 chạy |
| E11 | UE | `Initial sync successful, PCI: (\d+)` | Chọn cell |
| E12 | UE | `RA-Msg3 transmitted` | Gửi Request |
| E20 | gNB | `Reestablishment RNTI (\w+) req C-RNTI (\w+) physCellId (\d+)` | `t_req` |
| E21 | gNB | `Send RRCReestablishment.*RNTI (\w+)` | Chấp nhận |
| E22 | UE | `Received RRCReestablishment` | |
| E23 | gNB | `Received RRCReestablishmentComplete` | `t_rrc` |
| E24 | gNB | `DRB (\d+) re-established` | Khôi phục bearer |
| E25 | gNB | `RRCReconfiguration after re-establishment.*xid (\d+)` | |
| E26 | UE | `DRB (\d+) re-established` | |
| E27 | gNB | `Received RRCReconfigurationComplete` | `t_cfg` |
| E28 | gNB | `[MEAS] ev=t_drb` | `t_drb` |
| E29 | probe/ping | phản hồi đầu tiên sau sự cố | user plane end-to-end |
| F01 | gNB | `RRCSetup` sau E20 cùng RNTI | Fallback |
| F02 | UE | `Timer T311 expired` | Thất bại → IDLE |
| F03 | UE | `Timer T301 expired` | Thất bại |
| E00b | UE telnet | `ploss 10` | Kết thúc sự cố |

⚠️ Regex cần chạy thử trên 3 run thật trước khi chốt; câu chữ log OAI có thể khác bảng trên một chút.

### 5.4 Nối đồng hồ

1. Với mỗi dòng có cả UTC Docker và monotonic: lấy `offset = utc_epoch − monotonic`. Lấy trung vị trên nhiều dòng (giảm nhiễu).
2. Dòng chỉ có UTC (telnet) → `mono = utc − offset`.
3. Ping/probe (epoch) → cùng cách.
4. Trục chuẩn của timeline: monotonic OAI; khi trình bày neo `t=0` tại E00 (ploss 65) hoặc tại `t_req`.
5. Báo sai số nối đồng hồ (độ lệch chuẩn của offset) trong đầu ra.

### 5.5 Gom thành attempt

- Một attempt bắt đầu ở E10 (UE) hoặc E20 (gNB).
- Nối UE ↔ gNB: E20 cho cặp (RNTI mới, C-RNTI cũ). RNTI cũ khớp RNTI của UE trước sự cố (E03 có `RNTI e513`), RNTI mới khớp các dòng gNB sau đó.
- Ghép `t_cfg` với `RRCReconfiguration` theo xid nếu có log `[MEAS]`; chưa có thì lấy `RRCReconfigurationComplete` đầu tiên cùng RNTI mới sau E25.
- Một run có thể có nhiều attempt (ví dụ RA lỗi nhiều lần) → đánh `attempt_id` tăng dần.

### 5.6 Phân loại kết quả (PDF §10.3)

| Kết quả | Điều kiện |
|---|---|
| `SUCCESS` | có E20, E23, E27 (và E28 nếu có probe) |
| `FALLBACK_RRCSETUP` | E20 rồi F01 |
| `NO_REQUEST_T311` | E10, F02, không có E20 |
| `STUCK_RRC` | E20 nhưng thiếu E23 hoặc E27 |
| `CFG_NO_DATA` | có E27, không có E28/probe sau đó |
| `DATA_NOT_E2E` | có E28 nhưng probe không tới ext-dn |
| `INCOMPLETE_EVIDENCE` | thiếu file hoặc thiếu mốc không xác định được |

Mỗi attempt ghi thêm `last_step` (sự kiện cuối cùng thấy được).

### 5.7 Định dạng đầu ra

`attempts.csv` (một dòng một attempt):
```
run_id,attempt_id,scenario,seed,pci,old_rnti,new_rnti,cause,
t_fade_start,t_rlf,t_reest_start,t_sync,t_req,t_rrc,t_cfg,t_drb,t_first_reply,
rlf_detect_ms,cell_search_ms,rrc_recovery_ms,cfg_recovery_ms,drb_recovery_ms,ping_gap_ms,
outcome,last_step,evidence
```
`evidence` = danh sách `file:dòng` của các mốc.

`timeline.json` (cho website/biểu đồ):
```json
{"run_id":"20261122T054006Z-rlf","clock":{"offset_s":...,"offset_std_ms":...},
 "attempts":[{"attempt_id":1,"outcome":"SUCCESS",
   "events":[{"code":"E20","side":"gNB","t_mono":170285.469055,"t_rel_ms":0.0,
              "phase":"t_req","text":"Reestablishment RNTI dc52 ...","src":"gnb.log:1234"}]}]}
```
`timeline.md`: bảng gộp UE/gNB theo thời gian giống PDF §8.2, đánh dấu pha, để dán vào báo cáo.

### 5.8 Đối chiếu với sơ đồ

Mỗi mã sự kiện gắn với một pha của sơ đồ Reestablishment (artifact ở **1.7**). Tool in thêm bảng "pha đã thấy / pha thiếu" cho mỗi attempt. Các bước có trong sơ đồ nhưng không có log mặc định (F1AP/E1AP nội bộ, Bearer Context Modification) ghi là `not_logged`, không coi là lỗi.

### 5.9 Các bước viết tool

1. Viết `sources.py` + `catalog.py`, chạy trên 3 run thật, in danh sách sự kiện. Sửa regex cho khớp.
2. `clock.py`: kiểm `t_rrc − t_req` tính ra trùng 164,750 / 160,368 / 160,472 ms (PDF §8.4).
3. `correlate.py` + `classify.py`: 3 run thật phải ra `SUCCESS`.
4. Tạo fixture giả cho `FALLBACK_RRCSETUP`, `NO_REQUEST_T311`, `STUCK_RRC` (cắt/sửa log thật), viết test.
5. `export.py`: CSV, JSON, Markdown.
6. Gọi tool cuối `lab.sh rlf` để mỗi run tự có `attempts.csv`.
7. Script gộp nhiều run → thống kê: tỉ lệ RLF/lần kích hoạt, tỉ lệ phục hồi/lần có request, median/min/max/n của các `*_recovery_ms`.

---

## 6. Mốc thời gian tới 21/12/2026 và tiêu chí hoàn thành

| Bước | Thời gian | Việc | Hoàn thành khi |
|---|---|---|---|
| B1 Hiểu mô phỏng | 25–29/11 | Mục 1; trả lời được 1.8 không nhìn tài liệu | Nam tự giải thích được Hình 1, 6, 8 của PDF và 23 câu ở 1.8 |
| B2 Dựng lại lab | 26–30/11 | 2.0–2.4, chạy lại 3.2 | lab/ trên GitHub khớp máy lab; baseline mới + ≥ 1 ca RLF `SUCCESS`; versions khớp 2026.w47 |
| B3 Thu log đầy đủ | 30/11–04/12 | 4.3, 4.4, thêm `core.log` vào `rlf` | Một run có gnb/ue/core log + 2 pcap; mở pcap thấy NGAP và GTP-U hai lớp IP |
| B4 Điểm đo + probe | 30/11–06/12 | 4.5, 4.6, build gNB sửa mã | Log có 4 dòng `[MEAS]` mỗi ca; probe có file gửi/nhận. **Hạn cứng 6/12**, trễ thì bỏ `t_drb` |
| B5 Tool phân tích | 03–10/12 | Mục 5, bước 5.9.1–5.9.6 | 3 run thật → `SUCCESS` với số trùng PDF §8.4; test fixture fallback/T311 qua |
| B6 Kịch bản đa dạng | 08–14/12 | 3.4 B–E, 3.5 | Có ít nhất 1 run thật mỗi loại `SUCCESS`, `NO_REQUEST_T311`, và thử `FALLBACK`; kịch bản seed chạy lại ra cùng chuỗi suy hao |
| B7 Chiến dịch đo | 12–15/12 | ≥ 3 profile × ≥ 10 lần | Bảng thống kê 5.9.7 có n, median, min/max |
| B8 Giao diện (nếu giữ website) | 11–17/12 | Website đọc `timeline.json`/`attempts.csv`: chọn run, xem timeline UE/gNB, bảng attempt | Mở một run bất kỳ thấy đủ pha và link về dòng log |
| B9 Báo cáo, demo | 15–20/12 | Cập nhật PDF/báo cáo, diễn tập demo baseline → RLF → recovery → tool | Demo chạy trọn ≤ 10 phút; báo cáo nêu rõ điều kiện lab |
| Bàn giao | 21/12 | | |

Quy tắc chung:
- Sau mỗi bước, ghi tiến độ và thư mục bằng chứng vào `CONTEXT.md`.
- Mọi số đo báo kèm điều kiện: tag OAI, cpuset, tham số fade, n.
- Thiếu thời gian thì cắt theo thứ tự: B8 (website) → ca D (T310) → ca C (fallback). Không cắt B5.

### Còn mở (cần Nam chốt)

- ⚠️ Có giữ website (B8) không, hay demo bằng CLI + `timeline.md`? (Theo ghi nhận 23/11 Nam muốn website.)
- ⚠️ Máy lab: vẫn là Ubuntu arm64 4 CPU như PDF? Đường dẫn repo trên máy?
- ⚠️ Có cần thêm nhánh "khác cell cùng DU" (cần cấu hình 2 cell) hay giữ phạm vi một cell?
