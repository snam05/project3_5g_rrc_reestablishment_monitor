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
