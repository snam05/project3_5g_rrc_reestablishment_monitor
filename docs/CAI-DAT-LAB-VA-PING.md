# Cài OAI từ đầu và chạy được ping

Bản 27/11/2026. Mục tiêu duy nhất của file này: từ một máy trống, kéo repo về, dựng lab OAI 5G SA bằng RFsimulator, và **UE ping được tới `oai-ext-dn` qua 5G Core**. Chưa đụng tới Reestablishment.

File này chi tiết hóa các mục **2.0 → 2.4** của [HUONG-DAN-TRIEN-KHAI.md](HUONG-DAN-TRIEN-KHAI.md). Lệnh và mã lấy từ PDF `huong-dan-lab-oai-reestablishment.pdf` (§3, §4, §7, §9, §11.3).

Ký hiệu: ⚠️ **cần xác minh** = chưa chạy trên máy lab của Nam.

---

## 0. Giả định

| Điều | Chọn | Lý do |
|---|---|---|
| Radio | RFsimulator (không USRP) | Như PDF; không cần phần cứng |
| Core | OAI CN5G `v2.2.2` (AMF/SMF/UPF) + `mysql:9.6`, cấu hình "mini" của OAI | Có sẵn trong Compose mẫu của OAI |
| OAI RAN | tag `2026.w47`, commit `75d439de6f4fb37c7e53b21774273f172f18cecb`, image cùng tag | Mã đọc được khớp binary đang chạy (PDF §2.2). Đã kiểm commit này bằng `git ls-remote` ngày 27/11 |
| Hệ điều hành | **Ubuntu 24.04 hoặc 26.04 LTS, amd64** | Máy đang kết nối với Claude là **Windows x64** (có VirtualBox). OAI cần kernel Linux (TUN, SCTP, cgroup), nên chạy trong máy ảo Ubuntu hoặc máy Linux riêng |
| Cách dựng | Không build OAI, dùng image dựng sẵn trên Docker Hub | PDF §2.1: image đã có `nr-softmodem`, `nr-uesoftmodem` |

⚠️ Nếu máy lab thật khác (Linux cài thẳng, arm64, ít hơn 4 CPU), chỉ bước 1 thay đổi; từ bước 2 trở đi giống nhau.

Luồng tổng: **(1) máy Linux → (2) Docker → (3) kiểm host → (4) clone repo → (5) chốt cấu trúc → (6) tạo file lab → (7) clone OAI → (8) pull image → (9) chạy Core → gNB → UE → (10) ping → (11) lưu baseline.**

---

## 1. Chuẩn bị máy Linux

### 1.1 Chọn đường

| Đường | Khi nào | Ghi chú |
|---|---|---|
| **A. Máy ảo Ubuntu trên VirtualBox** (đề xuất) | Chỉ có máy Windows | Dễ làm lại từ đầu bằng snapshot |
| B. Ubuntu cài thẳng / dual boot | Có máy hoặc ổ riêng | Nhanh nhất, RFsim ít lệch thời gian thực hơn |
| C. WSL2 | Không khuyên | ⚠️ Kernel WSL2 mặc định có thể không có module `sctp` (N2 cần SCTP); cần xác minh trước khi dùng |

### 1.2 Cấu hình máy ảo (đường A)

- ISO: Ubuntu Server hoặc Desktop 24.04/26.04 LTS amd64.
- **CPU ≥ 4** (tốt hơn 6). Lab ghim vào CPU 1–3 (`OAI_LAB_CPUSET=1-3`), CPU 0 để cho hệ điều hành.
- **RAM ≥ 8 GB**, **đĩa ≥ 50 GB** (7 image vài GB + mã OAI + log).
- Mạng: NAT là đủ (chỉ cần ra Internet để kéo image).
- Không đặt repo trong thư mục chia sẻ với Windows (quyền file, symlink, xuống dòng CRLF làm hỏng script bash). Làm hết trong `~` của máy ảo.

⚠️ Nếu Windows đang bật Hyper-V/WSL2, VirtualBox có thể chạy qua backend Hyper-V và chậm hơn; RFsim càng lệch thời gian thực. Cần xác minh trên máy của Nam (VirtualBox hiện biểu tượng con rùa xanh ở góc cửa sổ VM khi bị như vậy).

### 1.3 Gói cơ bản

```bash
sudo apt-get update
sudo apt-get install -y git curl ca-certificates python3 iproute2 iputils-ping tcpdump
```

**Đạt khi:** `git --version` và `python3 --version` in ra phiên bản.

---

## 2. Cài Docker Engine và Compose plugin

Cài từ kho chính thức của Docker. **Không** dùng gói `docker.io` / `docker-compose` (bản v1) của Ubuntu: Compose của OAI dùng thuộc tính `interface_name`, cần **Compose ≥ 2.36.0** (PDF §7.1).

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Cho user hiện tại dùng docker không cần sudo, rồi đăng xuất/đăng nhập lại (hoặc: newgrp docker)
sudo usermod -aG docker "$USER"
```

Kiểm tra (sau khi đăng nhập lại):

```bash
docker version --format '{{.Server.Version}}'   # có số phiên bản server, không báo permission denied
docker compose version --short                    # >= 2.36.0
docker run --rm hello-world                       # in "Hello from Docker!"
```

**Đạt khi:** cả ba lệnh chạy không cần `sudo`. Máy PDF dùng Docker 29.10.0, Compose 5.8.0.

| Lỗi | Cách sửa |
|---|---|
| `permission denied while trying to connect to the Docker daemon socket` | Chưa đăng nhập lại sau `usermod -aG docker`; hoặc chạy `newgrp docker` |
| `docker: 'compose' is not a docker command` | Thiếu `docker-compose-plugin`; cài lại dòng `apt-get install` ở trên |
| `toomanyrequests` khi pull | Docker Hub giới hạn người dùng ẩn danh: `docker login` |

---

## 3. Kiểm tra host

```bash
ls -l /dev/net/tun                          # phải có: crw-rw-rw- ... /dev/net/tun
sudo modprobe sctp && lsmod | grep sctp     # phải thấy dòng sctp
nproc                                       # >= 4
df -h ~                                     # còn >= 20 GB
ip route | grep -E '192\.168\.7[12]\.' || echo "subnet trống, OK"
```

Cho `sctp` tự nạp sau mỗi lần khởi động:

```bash
echo sctp | sudo tee /etc/modules-load.d/sctp.conf
```

| Lỗi | Cách sửa |
|---|---|
| `modprobe: FATAL: Module sctp not found` | `sudo apt-get install -y linux-modules-extra-$(uname -r)` rồi `sudo modprobe sctp` lại |
| `ip route` có 192.168.71.x hoặc 72.x | Một mạng khác (Docker cũ, VPN) trùng subnet của lab. Xem `docker network ls`, gỡ mạng trùng (`docker network rm …`) |
| `nproc` < 4 | Tăng CPU cho VM; nếu không thể, khi chạy lab đặt `OAI_LAB_CPUSET=0-1` (bước 9) và chấp nhận RFsim chậm hơn |

---

## 4. Kéo repo dự án về

```bash
git config --global core.autocrlf input       # giữ LF cho script bash
mkdir -p ~/work && cd ~/work
git clone https://github.com/snam05/project3_5g_rrc_reestablishment_monitor.git
cd project3_5g_rrc_reestablishment_monitor
git log --oneline -3
```

Nếu repo để private, `git clone` qua HTTPS sẽ hỏi mật khẩu: dùng **Personal Access Token** của GitHub thay cho mật khẩu, hoặc cài `gh` rồi `gh auth login`, hoặc dùng SSH (`git@github.com:snam05/project3_5g_rrc_reestablishment_monitor.git` sau khi thêm SSH key vào GitHub).

Tạo nhánh làm việc cho phần dựng lab:

```bash
git switch -c lab-setup
```

**Đạt khi:** thấy `CONTEXT.md`, `CLAUDE.md`, `docs/` trong thư mục.

---

## 5. Cấu trúc thư mục dự án (đề xuất, chờ Nam chốt)

Theo PDF §3.1, thêm chỗ cho các phần sau (tool phân tích, kịch bản, website) nhưng **chưa tạo** cho tới khi làm tới:

```text
project3_5g_rrc_reestablishment_monitor/
├── README.md, CONTEXT.md, CLAUDE.md, .gitignore
├── docs/                         tài liệu (file này, file định hướng)
├── lab/                          ← tạo ở bước 6
│   ├── versions.env              phiên bản OAI + tag image (một chỗ duy nhất)
│   ├── compose.lab.yaml          lớp phủ lên Compose của OAI: CPU, chanmod, telnet cho UE
│   ├── lab.sh                    script điều khiển: setup, pull, up, status, baseline, rlf, down
│   ├── fade.py                   gây suy hao qua telnet UE (dùng ở mục 3 file định hướng)
│   ├── upstream/openairinterface5g/   mã OAI do `lab.sh setup` clone (Git bỏ qua)
│   └── runs/<UTC>-baseline|rlf/       bằng chứng mỗi lượt chạy (Git bỏ qua)
├── scenarios/                    (sau, B6) kịch bản khai báo, seed
├── tools/                        (sau, B5) tool phân tích log → attempts.csv, timeline.json
└── web/                          (sau, B8, nếu giữ website)
```

Vì sao như vậy:

- Repo dự án **mỏng**: không chép mã hay cấu hình của OAI vào repo. Mã OAI nằm trong `lab/upstream/` và bị Git bỏ qua; muốn đổi phiên bản chỉ sửa `versions.env`.
- **Không sửa file của OAI**: mọi thay đổi hành vi nằm trong `compose.lab.yaml` hoặc cờ dòng lệnh (quy tắc 3 của `CLAUDE.md`).
- `lab.sh` là **điểm vào duy nhất**: mọi lệnh Docker đi qua hàm `dc()`, luôn ghép đúng bộ file (Compose OAI + `compose.lab.yaml` + `versions.env`). Gõ `docker compose` trơn trong thư mục OAI sẽ mất lớp phủ (UE thiếu telnet, mất giới hạn CPU).

Tên `scenarios/`, `tools/`, `web/` chỉ là gợi ý; Nam chốt khi tới bước đó.

---

## 6. Tạo các file lab

Chạy từ gốc repo. Mỗi khối là một lệnh copy-paste nguyên khối (heredoc có dấu nháy nên bash không thay biến bên trong). Nội dung y như PDF §11.3, chỉ nối lại các dòng bị ngắt khi in PDF.

### 6.1 `lab/versions.env`

```bash
mkdir -p lab
cat > lab/versions.env <<'EOF'
# Phiên bản OAI dùng cho lab. lab.sh đọc file này, Docker Compose đọc qua --env-file.
# Mã nguồn và image gNB/UE ghim cùng một tag tuần để binary đang chạy khớp với source đọc được.
OAI_REPO=https://github.com/OPENAIRINTERFACE/openairinterface5g.git
OAI_REF=2026.w47
OAI_COMMIT=75d439de6f4fb37c7e53b21774273f172f18cecb
TAG=2026.w47
EOF
```

### 6.2 `lab/compose.lab.yaml`

```bash
cat > lab/compose.lab.yaml <<'EOF'
# Lớp phủ của dự án lên ci-scripts/yaml_files/5g_rfsimulator/docker-compose.yaml của OAI.
# lab.sh luôn nạp file này sau file của OAI, nên các khóa dưới đây ghi đè hoặc bổ sung cho bản gốc.

# Giới hạn CPU: gNB/UE có nhiều thread SCHED_RR, nên ghim cả lab vào một tập CPU cố định
# (mặc định 1-3, chừa CPU 0 cho host) và giữ quota riêng cho từng container.
x-lab-cpuset: &lab-cpuset "${OAI_LAB_CPUSET:-1-3}"

services:
  mysql:
    cpuset: *lab-cpuset
    cpus: 0.20
  oai-amf:
    cpuset: *lab-cpuset
    cpus: 0.10
  oai-smf:
    cpuset: *lab-cpuset
    cpus: 0.10
  oai-upf:
    cpuset: *lab-cpuset
    cpus: 0.15
  oai-ext-dn:
    cpuset: *lab-cpuset
    cpus: 0.05
  oai-gnb:
    cpuset: *lab-cpuset
    cpus: 1.00
  oai-nr-ue:
    cpuset: *lab-cpuset
    cpus: 0.90
    environment:
      # Compose thay cả chuỗi chứ không nối thêm, nên dòng đầu chép nguyên các cờ UE của OAI.
      # Dòng sau bật mô hình kênh (mục channelmod trong nrue.uicc.yaml) và telnet chỉ nghe trên loopback.
      USE_ADDITIONAL_OPTIONS: >-
        -E --rfsim -r 106 --numerology 1 --uicc0.imsi 208990100001100 -C 3319680000
        --rfsimulator.[0].serveraddr 192.168.71.140 --log_config.global_log_options level,nocolor,time
        --rfsimulator.[0].options chanmod --telnetsrv --telnetsrv.listenaddr 127.0.0.1
EOF
```

Ghi nhớ: Compose **thay cả chuỗi** `USE_ADDITIONAL_OPTIONS`, không nối thêm. Vì vậy dòng đầu chép nguyên cờ UE gốc của OAI (đã đối chiếu với `docker-compose.yaml` tại tag 2026.w47), rồi mới thêm `chanmod` và `telnetsrv`. gNB giữ nguyên cờ của OAI.

### 6.3 `lab/lab.sh`

```bash
cat > lab/lab.sh <<'LABSH_EOF'
#!/usr/bin/env bash
# Điều khiển lab OAI 5G SA + RFsimulator cho đề tài RRC Reestablishment.
# Mọi lệnh Docker Compose của dự án đi qua hàm dc() bên dưới.
set -euo pipefail

lab_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
versions_env="$lab_dir/versions.env"
# shellcheck source=versions.env
. "$versions_env"
export TAG

oai_dir="$lab_dir/upstream/openairinterface5g"
compose_dir="$oai_dir/ci-scripts/yaml_files/5g_rfsimulator"
runs_dir="$lab_dir/runs"
ext_dn_ip=192.168.72.135
core_services=(mysql oai-amf oai-smf oai-upf oai-ext-dn)
ran_services=(oai-gnb oai-nr-ue)

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'lỗi: %s\n' "$*" >&2; exit 1; }

# File OAI nạp trước, compose.lab.yaml nạp sau để ghi đè. --project-directory giữ cho các đường dẫn
# tương đối trong file OAI (../../conf_files/...) được hiểu từ thư mục 5g_rfsimulator.
dc() {
  docker compose --project-directory "$compose_dir" --env-file "$versions_env" \
    -f "$compose_dir/docker-compose.yaml" -f "$lab_dir/compose.lab.yaml" "$@"
}

need_checkout() {
  [ -f "$compose_dir/docker-compose.yaml" ] || die "chưa có checkout OAI, chạy: $0 setup"
}

wait_for_log() { # service, regex, timeout(s)
  local svc=$1 pattern=$2 timeout=$3 t=0
  until dc logs --no-color "$svc" 2>/dev/null | grep -qE "$pattern"; do
    ((t += 2)) && ((t <= timeout)) || die "$svc: không thấy '$pattern' sau ${timeout}s (xem: $0 logs)"
    sleep 2
  done
  echo "$svc: thấy '$pattern'"
}

ue_ip() {
  dc exec -T oai-nr-ue ip -4 -o addr show oaitun_ue1 2>/dev/null | awk '{print $4}'
}

wait_for_ue_ip() { # timeout(s)
  local t=0 ip
  until ip="$(ue_ip)" && [ -n "$ip" ]; do
    ((t += 2)) && ((t <= $1)) || die "UE chưa có IP trên oaitun_ue1 sau $1s"
    sleep 2
  done
  echo "oaitun_ue1: $ip"
}

new_run_dir() { # nhãn
  local dir
  dir="$runs_dir/$(date -u +%Y%m%dT%H%M%SZ)-$1"
  mkdir -p "$dir"
  echo "$dir"
}

write_versions() { # file
  {
    echo "oai_ref=$OAI_REF"
    echo "oai_commit=$(git -C "$oai_dir" rev-parse HEAD)"
    echo "docker_compose=$(docker compose version --short)"
    echo "docker_server=$(docker version --format '{{.Server.Version}} {{.Server.Os}}/{{.Server.Arch}}')"
    echo "OAI_LAB_CPUSET=${OAI_LAB_CPUSET:-1-3}"
    echo "# image: tag digest arch"
    dc images -q | sort -u | xargs -r docker image inspect \
      --format '{{index .RepoTags 0}} {{index .RepoDigests 0}} {{.Architecture}}'
    echo "# revision mà binary gNB/UE in ra khi khởi động"
    dc logs --no-color oai-gnb oai-nr-ue 2>/dev/null | grep -m 4 -E 'Version:|Hash' || true
  } > "$1"
}

cmd_setup() {
  local v
  v="$(docker compose version --short)"
  [ "$(printf '%s\n' 2.36.0 "$v" | sort -V | head -1)" = 2.36.0 ] \
    || die "cần Docker Compose >= 2.36.0 (đang có $v) vì Compose của OAI dùng interface_name"
  [ -c /dev/net/tun ] || die "host không có /dev/net/tun, UE không tạo được oaitun_ue1"
  grep -qw sctp /proc/modules || [ -d /proc/sys/net/sctp ] \
    || echo "cảnh báo: chưa thấy module sctp trên host; N2 (gNB-AMF) cần SCTP. Thử: sudo modprobe sctp"
  if [ -d "$oai_dir/.git" ]; then
    echo "đã có checkout tại $oai_dir"
  else
    git clone --depth 1 --branch "$OAI_REF" "$OAI_REPO" "$oai_dir"
  fi
  [ "$(git -C "$oai_dir" rev-parse HEAD)" = "$OAI_COMMIT" ] \
    || die "checkout không ở $OAI_COMMIT ($OAI_REF); xóa $oai_dir rồi chạy lại setup"
  dc config --quiet
  echo "OAI $OAI_REF ($OAI_COMMIT), image tag $TAG: sẵn sàng"
}

cmd_pull() {
  need_checkout
  dc pull "${core_services[@]}" "${ran_services[@]}"
}

# Thứ tự theo README OAI mục 2: Core healthy -> gNB (NG Setup với AMF) -> UE.
cmd_up() {
  need_checkout
  say "5G Core: ${core_services[*]}"
  dc up -d --wait --wait-timeout 180 "${core_services[@]}"
  say "gNB"
  dc up -d --no-deps --wait --wait-timeout 120 oai-gnb
  wait_for_log oai-gnb 'Received NGSetupResponse' 90
  say "NR-UE"
  dc up -d --no-deps --wait --wait-timeout 120 oai-nr-ue
  wait_for_ue_ip 120
  cmd_status
}

cmd_status() {
  need_checkout
  dc ps -a --format 'table {{.Name}}\t{{.Image}}\t{{.Status}}'
  echo "oaitun_ue1: $(ue_ip || true)"
  dc exec -T oai-nr-ue ping -n -I oaitun_ue1 -c 5 -W 2 "$ext_dn_ip"
}

cmd_baseline() {
  need_checkout
  local dir
  dir="$(new_run_dir baseline)"
  dc ps -a > "$dir/compose-ps.txt"
  dc logs --no-color --timestamps "${core_services[@]}" > "$dir/core.log"
  dc logs --no-color --timestamps oai-gnb > "$dir/gnb.log"
  dc logs --no-color --timestamps oai-nr-ue > "$dir/ue.log"
  dc exec -T oai-nr-ue ip -4 addr show oaitun_ue1 > "$dir/ue-tun.txt"
  dc exec -T oai-nr-ue ping -n -I oaitun_ue1 -c 10 -W 2 "$ext_dn_ip" | tee "$dir/ping.txt"
  write_versions "$dir/versions.txt"
  echo "đã lưu: $dir"
}

# Khoảng lớn nhất giữa hai phản hồi ping liên tiếp (ping -D in epoch ở đầu mỗi dòng).
ping_gap() { # ping.txt
  awk -F'[][]' '/bytes from/ { t = $2 + 0; if (prev && t - prev > gap) { gap = t - prev; a = prev; b = t } prev = t; n++ }
    END { if (n) printf "replies=%d max_gap=%.3fs (%.3f -> %.3f)\n", n, gap, a, b; else print "replies=0" }' "$1"
}

cmd_rlf() {
  need_checkout
  local seconds="${1:-2.0}" window="${PING_WINDOW:-30}" dir started fade_rc=0 ping_pid
  shift || true
  [ -n "$(ue_ip)" ] || die "UE chưa có IP, chạy $0 status trước"
  dir="$(new_run_dir rlf)"
  started="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
  echo "seconds=$seconds extra_args=$* ping_window=${window}s started=$started" > "$dir/params.txt"

  # Ping 4 gói/giây trong suốt cửa sổ quan sát để thấy đoạn mất và lúc user plane trở lại.
  dc exec -T oai-nr-ue ping -D -n -I oaitun_ue1 -i 0.25 -W 1 -w "$window" "$ext_dn_ip" \
    < /dev/null > "$dir/ping.txt" 2>&1 &
  ping_pid=$!
  sleep 2
  say "fade ${seconds}s (thời gian ảo)"
  dc exec -T oai-nr-ue python3 - "$seconds" "$@" < "$lab_dir/fade.py" 2>&1 | tee "$dir/fade.txt" \
    || fade_rc=$?
  say "chờ hết cửa sổ ping ${window}s"
  wait "$ping_pid" || true

  dc logs --no-color --timestamps --since "$started" oai-gnb > "$dir/gnb.log"
  dc logs --no-color --timestamps --since "$started" oai-nr-ue > "$dir/ue.log"
  {
    echo "# UE"
    grep -nE 'RLF|T310|T311|T301|re-establishment|Reestablishment|re-established|RRCSetup' "$dir/ue.log" || true
    echo "# gNB"
    grep -nE 'Reestablishment RNTI|RRCReestablishment|Received RRC(Reestablishment|Reconfiguration)Complete|RRCSetup|Release' \
      "$dir/gnb.log" || true
    echo "# ping"
    ping_gap "$dir/ping.txt"
    tail -2 "$dir/ping.txt"
  } > "$dir/summary.txt"
  cat "$dir/summary.txt"
  echo "đã lưu: $dir"
  return "$fade_rc"
}

cmd_logs() { need_checkout; dc logs -f --tail="${1:-50}" oai-gnb oai-nr-ue; }
cmd_down() { need_checkout; dc down; }
cmd_compose() { need_checkout; dc "$@"; }

usage() {
  cat <<EOF
Cách dùng: $0 <lệnh> [tham số]
  setup              kiểm tra host, clone OAI $OAI_REF vào lab/upstream/
  pull               tải image (Core, gNB, UE tag $TAG)
  up                 chạy Core -> gNB -> UE theo thứ tự OAI, chờ UE có IP
  status             trạng thái container, IP UE, ping 5 gói tới oai-ext-dn
  baseline           lưu log/ping/phiên bản vào lab/runs/<UTC>-baseline/
  rlf [giây] [...]   một lần fade downlink rồi thu log vào lab/runs/<UTC>-rlf/
                     tham số thêm chuyển cho fade.py, ví dụ: rlf 3 --loss 70
  logs [n]           theo dõi log gNB và UE
  down               gỡ toàn bộ container và network của lab
  compose ...        chạy docker compose với đúng các file của lab
EOF
}

case "${1:-}" in
  setup | pull | up | status | baseline | rlf | logs | down | compose)
    c=$1; shift; "cmd_$c" "$@" ;;
  *) usage; exit 1 ;;
esac
LABSH_EOF
chmod +x lab/lab.sh
```

### 6.4 `lab/fade.py`

Chưa dùng để ping, nhưng tạo luôn cho đủ bộ (dùng ở mục 3 file định hướng).

```bash
cat > lab/fade.py <<'EOF'
"""Tạo một lần suy hao downlink trong RFsimulator để gây RLF cho NR-UE.

Script chạy bên trong container oai-nr-ue (lab.sh đẩy nó qua stdin vào python3) và nói chuyện
với telnet server của nr-uesoftmodem ở 127.0.0.1:9090. Model 0 (rfsimu_channel_enB0) là kênh
AWGN mà UE áp lên tín hiệu downlink nhận từ gNB.

Thời gian giữ suy hao tính theo đồng hồ mẫu của RFsimulator (lệnh "rfsimu vtime"), không theo
đồng hồ máy, vì RFsimulator có thể chạy chậm hoặc nhanh hơn thời gian thực tùy CPU.
"""

import re
import socket
import time
from argparse import ArgumentParser

TELNET = ("127.0.0.1", 9090)
DOWNLINK_MODEL = 0
DOWNLINK_MODEL_NAME = "rfsimu_channel_enB0"
WALL_TIMEOUT_S = 60


def command(conn, text):
    """Gửi một lệnh telnet và đọc đến prompt "softmodem_5Gue> " mà server gửi sau mỗi lệnh.

    Luôn đọc hết tới prompt: đóng socket sớm đã làm nr-uesoftmodem abort (buffer overflow detected).
    """
    conn.sendall((text + "\n").encode())
    reply = b""
    while not reply.endswith(b"> "):
        chunk = conn.recv(8192)
        if not chunk:
            raise RuntimeError("telnet server của UE đã đóng kết nối")
        reply += chunk
    out = reply.decode(errors="replace")
    if "is not a softmodem command" in out:
        raise RuntimeError(f"lệnh không được hỗ trợ: {text}\n{out}")
    return out


def virtual_time(conn):
    """Trả về (số mẫu, tốc độ lấy mẫu) hiện tại của RFsimulator."""
    out = command(conn, "rfsimu vtime")
    m = re.search(r"TS (\d+) sample_rate ([\d.]+)", out)
    if not m:
        raise RuntimeError(f"RFsimulator không trả về thời gian ảo\n{out}")
    return int(m[1]), float(m[2])


def path_loss(conn):
    """Đọc path loss hiện tại của model downlink từ "channelmod show current"."""
    out = command(conn, "channelmod show current")
    blocks = re.split(r"(?=^model \d+ )", out, flags=re.M)
    block = next((b for b in blocks if b.startswith(f"model {DOWNLINK_MODEL} {DOWNLINK_MODEL_NAME} ")), None)
    if block is None:
        raise RuntimeError(f"không thấy model {DOWNLINK_MODEL} {DOWNLINK_MODEL_NAME}; chanmod đã bật chưa?\n{out}")
    m = re.search(r"path loss: (-?[\d.]+)", block)
    if not m:
        raise RuntimeError(f"không đọc được path loss\n{block}")
    return float(m[1])


def set_path_loss(conn, db):
    command(conn, f"channelmod modify {DOWNLINK_MODEL} ploss {db:g}")
    print(f"ploss={db:g} dB", flush=True)


def main():
    parser = ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("seconds", nargs="?", type=float, default=2.0, help="thời gian giữ suy hao, tính bằng giây ảo")
    parser.add_argument("--loss", type=float, default=65.0, help="path loss khi fade (dB)")
    parser.add_argument("--nominal", type=float, default=10.0, help="path loss bình thường (dB), như nrue.uicc.yaml")
    args = parser.parse_args()
    if not 0 < args.seconds < 600:
        parser.error("seconds phải nằm trong (0, 600)")

    with socket.create_connection(TELNET, timeout=5) as conn:
        before = path_loss(conn)
        if abs(before - args.nominal) > 1e-6:
            raise SystemExit(f"path loss đang là {before} dB, không phải {args.nominal} dB; dừng để không chồng hai lần fade")
        wall_start = time.monotonic()
        try:
            set_path_loss(conn, args.loss)
            ts_start, rate = virtual_time(conn)
            ts_target = ts_start + round(args.seconds * rate)
            ts = ts_start
            while ts < ts_target:
                if time.monotonic() - wall_start > WALL_TIMEOUT_S:
                    raise TimeoutError("RFsimulator không chạy tới thời điểm ảo mong muốn")
                time.sleep(0.02)
                ts, _ = virtual_time(conn)
            print(f"fade virtual={(ts - ts_start) / rate:.3f}s wall={time.monotonic() - wall_start:.3f}s", flush=True)
        finally:
            set_path_loss(conn, args.nominal)
        after = path_loss(conn)
        print(f"path loss after: {after:.6f}", flush=True)
        if abs(after - args.nominal) > 1e-6:
            raise SystemExit("không trả được path loss về mức bình thường")


if __name__ == "__main__":
    main()
EOF
```

### 6.5 Bỏ qua mã OAI và log

```bash
printf '%s\n' 'lab/upstream/' 'lab/runs/' >> .gitignore
cat .gitignore
```

### 6.6 Kiểm tra

```bash
bash -n lab/lab.sh && echo "lab.sh: cú pháp OK"
python3 -m py_compile lab/fade.py && echo "fade.py: cú pháp OK"
lab/lab.sh            # in bảng "Cách dùng", mã thoát 1 là bình thường
```

**Đạt khi:** hai dòng OK và bảng cách dùng hiện ra.

| Lỗi | Cách sửa |
|---|---|
| `/usr/bin/env: 'bash\r': No such file or directory` | File bị xuống dòng CRLF (thường do tạo trên Windows). `sed -i 's/\r$//' lab/lab.sh lab/*.env lab/*.yaml` |
| `Permission denied` khi chạy `lab/lab.sh` | Thiếu `chmod +x lab/lab.sh` |

---

## 7. Lấy mã OAI đúng tag

```bash
lab/lab.sh setup
```

Lệnh này: kiểm Compose ≥ 2.36.0, `/dev/net/tun`, `sctp`; `git clone --depth 1 --branch 2026.w47` vào `lab/upstream/openairinterface5g`; so `HEAD` với `OAI_COMMIT`; chạy `docker compose … config --quiet` để kiểm tra phép ghép file.

**Đạt khi** dòng cuối là (đã chạy thử `setup` ngày 27/11 trên máy cloud, ra đúng dòng này; phần `up` và ping thì chưa chạy được ở đó vì không có Docker daemon và SCTP):

```text
OAI 2026.w47 (75d439de6f4fb37c7e53b21774273f172f18cecb), image tag 2026.w47: sẵn sàng
```

Xem cấu hình UE sau khi ghép (phải thấy `chanmod --telnetsrv` và image `oai-nr-ue:2026.w47`; đã chạy thử lệnh này ngày 27/11):

```bash
lab/lab.sh compose config oai-nr-ue | grep -E 'chanmod|telnetsrv|oai-nr-ue:2026'
```

| Lỗi | Cách sửa |
|---|---|
| `cần Docker Compose >= 2.36.0` | Quay lại bước 2, cài Compose từ kho Docker |
| `checkout không ở 75d439de…` | Có checkout cũ hoặc tag bị dời: `rm -rf lab/upstream/openairinterface5g` rồi `lab/lab.sh setup` lại |
| `Additional property interface_name is not allowed` | Compose cũ (v1 hoặc < 2.36) |

---

## 8. Tải image

```bash
lab/lab.sh pull
docker images | grep -E 'oai-|mysql|trf-gen'
```

**Đạt khi** có đủ 7 image: `oai-gnb:2026.w47`, `oai-nr-ue:2026.w47`, `oai-amf:v2.2.2`, `oai-smf:v2.2.2`, `oai-upf:v2.2.2`, `trf-gen-cn5g:latest`, `mysql:9.6`. Lần đầu mất vài phút tùy mạng.

Lỗi `toomanyrequests` → `docker login` rồi pull lại.

---

## 9. Khởi động: Core → gNB → UE

README của OAI ghi rõ: *"Just docker-compose up -d WILL NOT WORK!"*. Phải theo thứ tự, và `lab.sh up` làm đúng việc đó:

```bash
lab/lab.sh up
# máy ít CPU (⚠️ chưa thử với 2 CPU):  OAI_LAB_CPUSET=0-1 lab/lab.sh up
```

Ba điểm chờ, mỗi điểm là một điều kiện cụ thể chứ không phải `sleep`:

| Pha | Lệnh bên trong | Chờ tới khi | Tối đa |
|---|---|---|---|
| ① Core | `up -d --wait` mysql, oai-amf, oai-smf, oai-upf, oai-ext-dn | 5 container healthy | 180 s |
| ② gNB | `up -d --no-deps --wait oai-gnb` | log gNB có `Received NGSetupResponse` (đã nối AMF qua N2/SCTP) | 90 s |
| ③ UE | `up -d --no-deps --wait oai-nr-ue` | `oaitun_ue1` có IPv4 (đã đăng ký và có PDU session) | 120 s |

Kết quả mong đợi (PDF §7.3, tổng khoảng 1 phút):

```text
==> 5G Core: mysql oai-amf oai-smf oai-upf oai-ext-dn
==> gNB
oai-gnb: thấy 'Received NGSetupResponse'
==> NR-UE
oaitun_ue1: 12.1.1.2/24
NAME                 IMAGE                                     STATUS
rfsim5g-mysql        mysql:9.6                                 Up … (healthy)
rfsim5g-oai-amf      oaisoftwarealliance/oai-amf:v2.2.2        Up … (healthy)
rfsim5g-oai-ext-dn   oaisoftwarealliance/trf-gen-cn5g:latest   Up … (healthy)
rfsim5g-oai-gnb      oaisoftwarealliance/oai-gnb:2026.w47      Up … (healthy)
rfsim5g-oai-nr-ue    oaisoftwarealliance/oai-nr-ue:2026.w47    Up … (healthy)
rfsim5g-oai-smf      oaisoftwarealliance/oai-smf:v2.2.2        Up … (healthy)
rfsim5g-oai-upf      oaisoftwarealliance/oai-upf:v2.2.2        Up … (healthy)
64 bytes from 192.168.72.135: icmp_seq=1 ttl=63 time=55.4 ms
5 packets transmitted, 5 received, 0% packet loss
```

Chú ý: "healthy" của gNB chỉ nghĩa là tiến trình `nr-softmodem` đang chạy (healthcheck là `pgrep`), chưa nghĩa là đã nối AMF. Vì vậy mới phải chờ dòng `NGSetupResponse`.

### 9.1 Tự kiểm từng pha bằng tay (để hiểu, và khi `up` dừng giữa chừng)

```bash
# ① Core
lab/lab.sh compose ps -a
# ② gNB đã nối AMF?
lab/lab.sh compose logs oai-gnb | grep -E 'NGSetupResponse|Version:'
# ③ UE đi qua các bước gắn mạng chưa? (RRCSetup → Registration Accept → PDU Session)
lab/lab.sh compose logs oai-nr-ue | grep -iE 'RRCSetup|Registration Accept|PDU Session' | head -20
lab/lab.sh compose exec oai-nr-ue ip -4 addr show oaitun_ue1
```

⚠️ Chuỗi log chính xác cho bước ③ chưa đối chiếu trên máy của Nam; grep trên để rộng (không phân biệt hoa thường). So luồng với PDF §7.4 Hình 8 (RA → RRCSetup → Security → Registration Accept → PDU Session → DRB 1, khoảng 1,1 s).

Dòng `Version:` của gNB và UE phải có `Abrev. Hash: 75d439d`, trùng commit checkout (PDF §2.3).

---

## 10. Ping end-to-end

```bash
lab/lab.sh status
```

Hoặc gõ tay để thấy rõ đường đi:

```bash
lab/lab.sh compose exec oai-nr-ue ping -I oaitun_ue1 -c 10 192.168.72.135
```

**Đạt khi:** `0% packet loss`, **TTL 63**, RTT vài chục ms (PDF đo trung bình 46,4 ms).

- `-I oaitun_ue1` là bắt buộc. Thiếu nó, gói đi `eth0` của container và **bỏ qua 5G** (vẫn ping được nhưng vô nghĩa).
- TTL 63 = 64 − 1: gói qua đúng một bước định tuyến (UPF) trước khi tới `oai-ext-dn`.
- RTT cao hơn mạng thật vì RFsimulator xử lý mẫu IQ bằng CPU. Không phải lỗi.
- Đường đi của gói: `oaitun_ue1` → SDAP/PDCP/RLC/MAC/PHY của UE → mẫu IQ qua TCP 4043 → gNB → GTP-U (N3, UDP 2152) → UPF → N6 → `oai-ext-dn` (PDF §1.3).

Muốn tận mắt thấy tunnel GTP-U (tùy chọn), mở terminal thứ hai trên host trong lúc ping:

```bash
sudo tcpdump -ni rfsim5g-public udp port 2152 -c 10
```

Mỗi gói hiện IP ngoài 192.168.71.140 ↔ 192.168.71.134 (gNB ↔ UPF); IP trong 12.1.1.x ↔ 192.168.72.135 chỉ thấy khi mở bằng Wireshark.

---

## 11. Lưu baseline và commit

```bash
lab/lab.sh baseline              # lưu lab/runs/<UTC>-baseline/
ls lab/runs/*-baseline/
cat lab/runs/*-baseline/versions.txt
```

Thư mục có `compose-ps.txt`, `core.log`, `gnb.log`, `ue.log`, `ue-tun.txt`, `ping.txt` (10 gói), `versions.txt` (commit OAI, Docker, digest image, hash binary). Ghi tên thư mục baseline và cấu hình máy vào `CONTEXT.md` (mục 3 và 9).

Khi Nam đã chốt cấu trúc ở bước 5 và lab chạy được, commit các file lab:

```bash
git add .gitignore lab/versions.env lab/compose.lab.yaml lab/lab.sh lab/fade.py
git status        # không được có lab/upstream/ hay lab/runs/
git commit -m "Thêm script dựng lab OAI 2026.w47 (RFsim + CN5G v2.2.2)"
git push -u origin lab-setup
```

---

## 12. Lỗi thường gặp (theo thứ tự chạy, PDF §9)

Nguyên tắc: lỗi ở bước sau thường do bước trước chưa xong. Khi nghi ngờ: `lab/lab.sh down` → `lab/lab.sh up`.

| Triệu chứng | Xem | Nguyên nhân hay gặp |
|---|---|---|
| ① Core không healthy | `lab/lab.sh compose logs mysql oai-amf` | MySQL nạp `oai_db.sql` lần đầu chậm → chạy lại `up`; pull lỗi (rate limit) → `docker login`; subnet 192.168.71/72 trùng mạng khác |
| ② Không thấy `NGSetupResponse` sau 90 s | log AMF có gNB "Connected" không | Host chưa có `sctp` (`sudo modprobe sctp`); PLMN 208/99, TAC 1, SST 1 phải khớp giữa gNB và AMF (mặc định của OAI đã khớp, chỉ lệch nếu ai đó sửa) |
| ③ UE không có IP trên `oaitun_ue1` | `lab/lab.sh compose logs oai-nr-ue` | Không có RRCSetup → UE chưa nối RFsim tới 192.168.71.140:4043 (gNB chết?); không có Registration Accept → IMSI/key/OPc lệch DB; không có PDU Session Accept → DNN `oai`, xem log SMF/UPF |
| ④ Có IP mà ping không qua | log `oai-upf`, `oai-ext-dn` | Thiếu `-I oaitun_ue1`; ext-dn cần route 12.1.1.0/24 qua 192.168.72.134 (`docker exec rfsim5g-oai-ext-dn ip route`) |
| `oaitun_ue1` có IP khác 12.1.1.2 | | Bình thường sau khi tạo lại UE (PDF ghi một lần nhận 12.1.1.4). Xem IP bằng `lab/lab.sh status` |
| gNB/UE ăn hết CPU, máy đơ | `top` | Đổi `OAI_LAB_CPUSET`; giữ cố định giá trị này giữa các lần đo |
| UE chạy nhưng thiếu telnet/chanmod | `docker inspect rfsim5g-oai-nr-ue --format '{{range .Config.Env}}{{println .}}{{end}}' \| grep telnetsrv` (trống là thiếu) | UE bị tạo lại bằng `docker compose` trơn (không qua `lab.sh`). Chạy lại `lab/lab.sh up` |
| Tiến trình treo, không in log | | Image UE có `gdb`: vào container, `gdb -p <pid> -batch -ex 'thread apply all bt'` |

## 13. Dừng và gỡ

```bash
lab/lab.sh compose stop     # dừng tạm, giữ container
lab/lab.sh down             # gỡ hẳn container và network (giữ image và lab/upstream)
```

## 14. Xong phần này khi

- [ ] `lab/lab.sh setup` in "sẵn sàng" với commit `75d439de…`
- [ ] `lab/lab.sh up` tới `oaitun_ue1: 12.1.1.x/24`, 7 container healthy
- [ ] `ping -I oaitun_ue1` 0% loss, TTL 63
- [ ] Có một thư mục `lab/runs/<UTC>-baseline/`, `versions.txt` hash `75d439d`
- [ ] Cấu hình máy lab (OS, CPU, RAM, cpuset) ghi vào `CONTEXT.md`

Bước tiếp theo: mục **3.2** của file định hướng (ca RLF chuẩn `lab/lab.sh rlf 2.0`).
