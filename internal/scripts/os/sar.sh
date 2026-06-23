#!/usr/bin/env bash
# File Name: sar.sh
# Purpose: SAR trend report shell wrapper for sysstat sar
# Created: 20260517  by  huangtingzhong
# SAR trend report: compare target day vs 7-day / 30-day baselines (same time slot).
#
# Linux compatibility (sysstat/sar):
#   RHEL/CentOS/Rocky/Alma, Oracle Linux/UEK, Fedora, openSUSE,
#   openEuler, Anolis OS, Kylin (麒麟), UnionTech UOS, TencentOS, EulerOS, etc.
#   Typical sar dir: /var/log/sa (RHEL family) or /var/log/sysstat (Debian/Ubuntu).
#   Requires: bash 4+, GNU date, awk; sar 12h (AM/PM) and 24h output both parsed.
#
# Modes:
#   hourly (default): slots 00-23, each hour vs historical same hour
#   interval: requires -t HOUR and -i MINUTES (e.g. -t 08 -i 10 -> 08:00,08:10,...08:50)
#
# Usage:
#   sar.sh [-D DATE] [-n IFACES] [-d DISKS] [-o FILE]
#   sar.sh -t 08 -i 10 -n ens160 -d dm-0
#   sar.sh -E "-s 140000 -e 145959" -M cpu,net
#
set -eu
# pipefail off: sar|awk pipelines may SIGPIPE when sar writes ahead of awk

SAR_DIR="/var/log/sa"
HISTORY_DAYS=30
WINDOW_7=7
THRESH_MID=20
THRESH_HIGH=50
IFACES=""
DISKS=""
SAR_EXTRA_OPTS=""
MODULES="cpu,mem,load,disk,net,swap"
METRICS_FILTER=""
OUT_FILE=""
SAR_DIR_EXPLICIT=0
COMPARE_DATE=""
CURRENT_SLOT_ONLY=0
MODE="hourly"
PIN_HOUR=""
INTERVAL_MIN=""

usage() {
  cat <<'EOF'
SAR trend report (English output)

Option convention:
  lowercase  common:  -d -t -i -m -f -n -o --now
  uppercase  advanced: -D -H -W -E -S
  aliases: -M same as -m; -I same as -n; -w7 same as -W

Options:
  -D DATE       Compare date YYYYMMDD or YYYY-MM-DD (default: latest archive)
                e.g. -D 20260610
  -t HOUR       Pin hour for interval mode (requires -i)
                e.g. -t 8  or  -t 08  or  -t 08:00
  -i MINUTES    Sample interval within pinned hour (requires -t)
                e.g. -i 10  -> slots 08:00,08:10,...,08:50
  -m MODULES    Report modules, comma-separated (default: all)
                cpu,mem,load,disk,net,swap
                e.g. -m cpu,net  or  -m disk
  -f METRICS    Filter metrics (default: all enabled by -m). Forms:
                NAME         e.g. wkB, iowait, txkB (wkB is disk-only)
                MODULE/NAME  e.g. disk/wkB, cpu/iowait, net/txkB
                MODULE       e.g. cpu, disk, net (all metrics in module)
                All metrics by module:
                  cpu:  iowait, user, system, idle
                  mem:  memused_pct
                  load: ldavg1, ldavg15
                  disk: tps, rkB, wkB, areq-sz, aqu-sz, await, svctm, util
                  net:  rxpck, txpck, rxkB, txkB, rxcmp, txcmp, rxmcst, ifutil
                  swap: pswpin, pswpout
                e.g. -f wkB,txkB  |  -f disk/wkB,cpu/iowait  |  -f disk
  -n IFACES     Network interfaces, comma-separated (default: auto top3 txkB, skip lo)
                e.g. -n ens160  or  -n eth0,eth1
  -d DISKS      Disk devices, comma-separated (default: auto top3 wkB)
                e.g. -d dm-0  or  -d nvme0n1
  -o FILE       Save report to file (stdout still printed)
                e.g. -o /tmp/sar_report.txt
  -H DAYS       Long history window for 30d baseline (default: 30)
                e.g. -H 14
  -W DAYS       Prior N calendar days as daily columns (default: 7)
                e.g. -W 3
  -E "OPTS"     Extra sar arguments after sar -f FILE
                e.g. -E "-s 140000 -e 145959"
  -S DIR        Sar archive directory (default: auto /var/log/sa or /var/log/sysstat)
                e.g. -S /var/log/sa
  --now         Current slot only: all metrics for NOW hour/slot
  -h, --help    Show this help

Modes:
  hourly   Default: compare each hour 00-23 vs prior 7 days (daily) + 30d avg
  interval Requires -t and -i: compare HH:00, HH:10, ... within pinned hour

Examples:
  # Default hourly report: all modules, auto top disk/net
  sar.sh

  # Hourly CPU+net on ens160, save to file
  sar.sh -m cpu,net -n ens160 -o /tmp/sar_report.txt

  # Current slot only (quick snapshot for troubleshooting)
  sar.sh --now -m cpu,net -n ens160

  # Interval mode: 08:00-08:50 every 10 minutes vs same clock baseline
  sar.sh -t 8 -i 10 -m cpu,net -n ens160

  # Specific compare date with shorter history windows
  sar.sh -D 20260610 -H 14 -W 3 -m cpu --now

  # Cross-module: wkB (disk), txkB (net), iowait (cpu)
  sar.sh -m cpu,disk,net -f wkB,txkB,iowait --now

  # Disk: wkB is one of eight disk metrics
  sar.sh -m disk -d nvme0n1 -f disk/wkB,util

  # Pass time range to sar (hourly mode, CPU iowait only; HHMMSS compact)
  sar.sh -E "-s 140000 -e 145959" -m cpu -f iowait

  # Non-default sar archive dir (Debian/Ubuntu sysstat path)
  sar.sh -S /var/log/sysstat -m cpu --now
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -D) COMPARE_DATE="$2"; shift 2 ;;
    -H) HISTORY_DAYS="$2"; shift 2 ;;
    -W|-w7) WINDOW_7="$2"; shift 2 ;;
    -t) PIN_HOUR="$2"; shift 2 ;;
    -i) INTERVAL_MIN="$2"; shift 2 ;;
    -n|-I) IFACES="$2"; shift 2 ;;
    -d) DISKS="$2"; shift 2 ;;
    -m|-M) MODULES="$2"; shift 2 ;;
    -f) METRICS_FILTER="$2"; shift 2 ;;
    -E) SAR_EXTRA_OPTS="$2"; shift 2 ;;
    -S) SAR_DIR="$2"; SAR_DIR_EXPLICIT=1; shift 2 ;;
    -o) OUT_FILE="$2"; shift 2 ;;
    --now) CURRENT_SLOT_ONLY=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1"; usage 1 ;;
  esac
done

normalize_date() {
  local d="$1"
  if [[ "$d" =~ ^[0-9]{8}$ ]]; then
    printf '%s-%s-%s' "${d:0:4}" "${d:4:2}" "${d:6:2}"
  else
    printf '%s' "$d"
  fi
}

normalize_sar_extra_opts() {
  local opts="$1" normalized="" prev="" tok
  [[ -z "$opts" ]] && return 0
  for tok in $opts; do
    if [[ ( "$prev" == "-s" || "$prev" == "-e" ) && "$tok" =~ ^[0-9]{6}$ ]]; then
      tok="${tok:0:2}:${tok:2:2}:${tok:4:2}"
    fi
    normalized+="$tok "
    prev="$tok"
  done
  printf '%s' "${normalized% }"
}

[[ -n "$COMPARE_DATE" ]] && COMPARE_DATE=$(normalize_date "$COMPARE_DATE")
[[ -n "$SAR_EXTRA_OPTS" ]] && SAR_EXTRA_OPTS=$(normalize_sar_extra_opts "$SAR_EXTRA_OPTS")

if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
  echo "ERROR: bash 4+ required (RHEL7+/openEuler/Kylin and most domestic distros OK)"
  exit 1
fi
command -v sar >/dev/null || {
  echo "ERROR: sar not found — install sysstat (yum/dnf/apt) and enable sa1/sa2 collection"
  exit 1
}
command -v awk >/dev/null || { echo "ERROR: awk not found"; exit 1; }
if ! date -d "2020-01-01 -1 days" +%Y-%m-%d >/dev/null 2>&1; then
  echo "ERROR: GNU date required (standard on RHEL/openEuler/Kylin; not BSD/macOS)"
  exit 1
fi

has_sar_files() {
  local d="$1" f
  [[ -d "$d" ]] || return 1
  for f in "$d"/sa[0-9][0-9] "$d"/sa[0-9]; do
    [[ -f "$f" ]] && return 0
  done
  return 1
}

if [[ "$SAR_DIR_EXPLICIT" -eq 0 ]]; then
  for _try in /var/log/sa /var/log/sysstat; do
    if has_sar_files "$_try"; then
      SAR_DIR="$_try"
      break
    fi
  done
fi
if ! has_sar_files "$SAR_DIR"; then
  echo "ERROR: no sar archives in ${SAR_DIR} — install sysstat, enable sa1/sa2, or use -S DIR"
  exit 1
fi

# Normalize -t to 2-digit hour
if [[ -n "$PIN_HOUR" ]]; then
  PIN_HOUR=$(echo "$PIN_HOUR" | awk -F: '{printf "%02d", $1}')
fi

if [[ -n "$PIN_HOUR" && -n "$INTERVAL_MIN" ]]; then
  MODE="interval"
elif [[ -n "$PIN_HOUR" || -n "$INTERVAL_MIN" ]]; then
  echo "ERROR: interval mode requires both -t HOUR and -i MINUTES (e.g. -t 08 -i 10)"
  exit 1
fi

if [[ "$MODE" == "interval" && ( "$INTERVAL_MIN" -lt 1 || "$INTERVAL_MIN" -ge 60 ) ]]; then
  echo "ERROR: interval must be between 1 and 59 minutes"
  exit 1
fi

module_enabled() {
  local m="$1"
  local x
  IFS=',' read -ra _mods <<< "$MODULES"
  for x in "${_mods[@]}"; do
    [[ "$x" == "$m" ]] && return 0
  done
  return 1
}

metric_selected() {
  local cat="$1" met="$2"
  [[ -z "$METRICS_FILTER" ]] && return 0
  local x cat_lc="${cat,,}" met_lc="${met,,}"
  IFS=',' read -ra _mf <<< "$METRICS_FILTER"
  for x in "${_mf[@]}"; do
    x="${x// /}"
    x="${x,,}"
    [[ -z "$x" ]] && continue
    if [[ "$x" == */* ]]; then
      [[ "$x" == "${cat_lc}/${met_lc}" ]] && return 0
    elif [[ "$x" == "$cat_lc" ]]; then
      return 0
    elif [[ "$x" == "$met_lc" ]]; then
      return 0
    fi
  done
  return 1
}

append_metric_line() {
  local cat="$1" ent="$2" met="$3" unit="$4" label="$5"
  metric_selected "$cat" "$met" || return 0
  echo "${cat}|${ent}|${met}|${unit}|${label}" >>"$METRICS_FILE"
}

# Build slot list for report
SLOTS=()
if [[ "$MODE" == "hourly" ]]; then
  for h in $(seq 0 23); do SLOTS+=("$(printf '%02d' "$h")"); done
else
  m=0
  while [[ "$m" -lt 60 ]]; do
    SLOTS+=("${PIN_HOUR}:$(printf '%02d' "$m")")
    m=$((m + INTERVAL_MIN))
  done
fi

SLOTS_CSV=$(IFS=,; echo "${SLOTS[*]}")

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
CSV="$WORKDIR/slots.csv"

get_file_date() {
  local f="$1" hdr
  hdr=$(sar -f "$f" ${SAR_EXTRA_OPTS} -u 2>/dev/null | head -1)
  [[ -n "$hdr" ]] || hdr=$(sar -f "$f" ${SAR_EXTRA_OPTS} -n DEV 2>/dev/null | head -1)
  echo "$hdr" | awk '
    function emit(y,m,d) { printf "%04d-%02d-%02d\n", y, m, d; exit }
    {
      for (i=1;i<=NF;i++) {
        if ($i ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) {
          split($i,a,"-"); emit(a[1],a[2],a[3])
        }
        if ($i ~ /^[0-9]{2}\/[0-9]{2}\/[0-9]{4}$/) {
          split($i,a,"/")
          if (a[1]>12 && a[2]<=12) emit(a[3],a[2],a[1])
          else emit(a[3],a[1],a[2])
        }
        if ($i ~ /^[0-9]{2}\.[0-9]{2}\.[0-9]{4}$/) {
          split($i,a,".")
          if (a[1]>12 && a[2]<=12) emit(a[3],a[2],a[1])
          else emit(a[3],a[1],a[2])
        }
      }
    }'
}

date_minus() { date -d "$1 -$2 days" +%Y-%m-%d; }
date_le() { [[ "$1" < "$2" || "$1" == "$2" ]]; }

SAR_AUTO_OPTS=""
if [[ "$MODE" == "interval" && "$SAR_EXTRA_OPTS" != *"-s"* ]]; then
  SAR_AUTO_OPTS="-s ${PIN_HOUR}:00:00 -e ${PIN_HOUR}:59:59"
fi

run_sar() {
  local f="$1"
  shift
  # shellcheck disable=SC2086
  sar -f "$f" ${SAR_AUTO_OPTS} ${SAR_EXTRA_OPTS} "$@" 2>/dev/null
}

read -r -d '' SAR_AWK_HEAD <<'AWKHEAD' || true
function sar_hour24(t, ap,   a,h) {
  split(t,a,":"); h=int(a[1])
  if (ap=="AM" || ap=="PM") {
    if (ap=="AM" && h==12) h=0
    if (ap=="PM" && h!=12) h+=12
  }
  return h
}
function row_offset() {
  if ($2=="AM" || $2=="PM") { o=3; return 3 }
  o=2; return 2
}
function time_slot(   h,mi,a,ap) {
  split($1,a,":")
  h=int(a[1]); mi=int(a[2])
  if ($2=="AM" || $2=="PM") {
    ap=$2
    if (ap=="AM" && h==12) h=0
    if (ap=="PM" && h!=12) h+=12
  }
  if (mode=="interval") {
    if (sprintf("%02d", h) != pin_hour) return ""
    mi=int(mi/interval)*interval
    if (mi>=60) return ""
    return sprintf("%02d:%02d", h, mi)
  }
  return sprintf("%02d", h)
}
AWKHEAD

extract_cpu() {
  local f="$1" d="$2"
  run_sar "$f" -u | awk -v d="$d" -v mode="$MODE" -v pin_hour="$PIN_HOUR" -v interval="$INTERVAL_MIN" "$SAR_AWK_HEAD"'
    /^[0-9]{1,2}:[0-9]{2}:[0-9]{2}/ {
      slot=time_slot(); if (slot=="") next
      o=row_offset(); if ($(o)!="all") next
      u=$(o+1); s=$(o+3); io=$(o+4); id=$(o+6)
      if (u<=100) printf "%s,%s,cpu,,user,%.4f\n", d, slot, u
      if (s<=100) printf "%s,%s,cpu,,system,%.4f\n", d, slot, s
      if (io<=100) printf "%s,%s,cpu,,iowait,%.4f\n", d, slot, io
      if (id<=100) printf "%s,%s,cpu,,idle,%.4f\n", d, slot, id
    }'
}

extract_mem() {
  local f="$1" d="$2"
  run_sar "$f" -r | awk -v d="$d" -v mode="$MODE" -v pin_hour="$PIN_HOUR" -v interval="$INTERVAL_MIN" "$SAR_AWK_HEAD"'
    /^[0-9]{1,2}:[0-9]{2}:[0-9]{2}/ {
      slot=time_slot(); if (slot=="") next
      o=row_offset()
      if ($(o) !~ /^[0-9]+$/) next
      printf "%s,%s,mem,,kbmemfree,%.0f\n", d, slot, $(o)
      printf "%s,%s,mem,,kbavail,%.0f\n", d, slot, $(o+1)
      gsub(/%/,"",$(o+3))
      printf "%s,%s,mem,,memused_pct,%.4f\n", d, slot, $(o+3)
    }'
}

extract_load() {
  local f="$1" d="$2"
  run_sar "$f" -q | awk -v d="$d" -v mode="$MODE" -v pin_hour="$PIN_HOUR" -v interval="$INTERVAL_MIN" "$SAR_AWK_HEAD"'
    /^[0-9]{1,2}:[0-9]{2}:[0-9]{2}/ {
      slot=time_slot(); if (slot=="") next
      o=row_offset()
      if ($(o+1) !~ /^[0-9]/) next
      printf "%s,%s,load,,ldavg1,%.4f\n", d, slot, $(o+2)
      printf "%s,%s,load,,ldavg15,%.4f\n", d, slot, $(o+4)
    }'
}

extract_disk() {
  local f="$1" d="$2"
  run_sar "$f" -d | awk -v d="$d" -v mode="$MODE" -v pin_hour="$PIN_HOUR" -v interval="$INTERVAL_MIN" "$SAR_AWK_HEAD"'
    /^[0-9]{1,2}:[0-9]{2}:[0-9]{2}/ {
      slot=time_slot(); if (slot=="") next
      o=row_offset(); dev=$(o)
      if (dev ~ /^(DEV|scd)/) next
      gsub(/%/, "", $(o+8))
      printf "%s,%s,disk,%s,tps,%.4f\n", d, slot, dev, $(o+1)
      printf "%s,%s,disk,%s,rkB,%.4f\n", d, slot, dev, $(o+2)
      printf "%s,%s,disk,%s,wkB,%.4f\n", d, slot, dev, $(o+3)
      printf "%s,%s,disk,%s,areq-sz,%.4f\n", d, slot, dev, $(o+4)
      printf "%s,%s,disk,%s,aqu-sz,%.4f\n", d, slot, dev, $(o+5)
      printf "%s,%s,disk,%s,await,%.4f\n", d, slot, dev, $(o+6)
      printf "%s,%s,disk,%s,svctm,%.4f\n", d, slot, dev, $(o+7)
      printf "%s,%s,disk,%s,util,%.4f\n", d, slot, dev, $(o+8)
    }'
}

extract_net() {
  local f="$1" d="$2"
  run_sar "$f" -n DEV | awk -v d="$d" -v mode="$MODE" -v pin_hour="$PIN_HOUR" -v interval="$INTERVAL_MIN" "$SAR_AWK_HEAD"'
    /^[0-9]{1,2}:[0-9]{2}:[0-9]{2}/ {
      slot=time_slot(); if (slot=="") next
      o=row_offset(); iface=$(o)
      if (iface=="IFACE" || iface=="" || iface=="lo") next
      printf "%s,%s,net,%s,rxpck,%.4f\n", d, slot, iface, $(o+1)
      printf "%s,%s,net,%s,txpck,%.4f\n", d, slot, iface, $(o+2)
      printf "%s,%s,net,%s,rxkB,%.4f\n", d, slot, iface, $(o+3)
      printf "%s,%s,net,%s,txkB,%.4f\n", d, slot, iface, $(o+4)
      printf "%s,%s,net,%s,rxcmp,%.4f\n", d, slot, iface, $(o+5)
      printf "%s,%s,net,%s,txcmp,%.4f\n", d, slot, iface, $(o+6)
      printf "%s,%s,net,%s,rxmcst,%.4f\n", d, slot, iface, $(o+7)
      if (NF>=o+8) {
        util=$(o+8); gsub(/%/, "", util)
        printf "%s,%s,net,%s,ifutil,%.4f\n", d, slot, iface, util
      }
    }'
}

extract_swap() {
  local f="$1" d="$2"
  run_sar "$f" -W | awk -v d="$d" -v mode="$MODE" -v pin_hour="$PIN_HOUR" -v interval="$INTERVAL_MIN" "$SAR_AWK_HEAD"'
    /^[0-9]{1,2}:[0-9]{2}:[0-9]{2}/ {
      slot=time_slot(); if (slot=="") next
      o=row_offset()
      printf "%s,%s,swap,,pswpin,%.4f\n", d, slot, $(o)
      printf "%s,%s,swap,,pswpout,%.4f\n", d, slot, $(o+1)
    }'
}

declare -A FILE_BY_DATE=()
for f in "$SAR_DIR"/sa[0-9][0-9] "$SAR_DIR"/sa[0-9]; do
  [[ -f "$f" ]] || continue
  d=$(get_file_date "$f")
  [[ -n "$d" ]] || continue
  FILE_BY_DATE[$d]="$f"
done

if [[ ${#FILE_BY_DATE[@]} -eq 0 ]]; then
  echo "ERROR: no dated sar archives under ${SAR_DIR}"
  exit 1
fi

if [[ -z "$COMPARE_DATE" ]]; then
  COMPARE_DATE=$(printf '%s\n' "${!FILE_BY_DATE[@]}" | sort | tail -1)
fi

[[ -n "${FILE_BY_DATE[$COMPARE_DATE]:-}" ]] || {
  echo "ERROR: no sar data for compare date ${COMPARE_DATE}"
  exit 1
}

START_30=$(date_minus "$COMPARE_DATE" "$HISTORY_DAYS")
START_7=$(date_minus "$COMPARE_DATE" "$WINDOW_7")
END_7=$(date_minus "$COMPARE_DATE" 1)
# Calendar last WINDOW_7 days before compare; columns recent-first (e.g. 06-10, 06-09, ... 06-04)
DAYS_7=()
DAY_LABELS=()
for (( _di=1; _di<=WINDOW_7; _di++ )); do
  _d=$(date_minus "$COMPARE_DATE" "$_di")
  DAYS_7+=("$_d")
  DAY_LABELS+=("$(date -d "$_d" +%m-%d)")
done
DAYS_7_CSV=$(IFS=,; echo "${DAYS_7[*]}")
DAY_LABELS_CSV=$(IFS=,; echo "${DAY_LABELS[*]}")
NOW_SLOT=$(date '+%H')
if [[ "$MODE" == "interval" ]]; then
  NOW_MIN=$(($(date '+%M') / INTERVAL_MIN * INTERVAL_MIN))
  NOW_SLOT="${PIN_HOUR}:$(printf '%02d' "$NOW_MIN")"
fi

: >"$CSV"
for d in "${!FILE_BY_DATE[@]}"; do
  if ! date_le "$START_30" "$d" || ! date_le "$d" "$COMPARE_DATE"; then
    continue
  fi
  f="${FILE_BY_DATE[$d]}"
  module_enabled cpu   && extract_cpu "$f" "$d" >>"$CSV"
  module_enabled mem   && extract_mem "$f" "$d" >>"$CSV"
  module_enabled load  && extract_load "$f" "$d" >>"$CSV"
  module_enabled disk  && extract_disk "$f" "$d" >>"$CSV"
  module_enabled net   && extract_net "$f" "$d" >>"$CSV"
  module_enabled swap  && extract_swap "$f" "$d" >>"$CSV"
done

[[ -s "$CSV" ]] || { echo "ERROR: no slot data extracted"; exit 1; }

# Drop corrupt CPU percentages; aggregate samples per date+slot+metric
awk -F, '
  $3=="cpu" && ($6<0 || $6>100) { next }
  {
    k=$1","$2","$3","$4","$5; s[k]+=$6; c[k]++
  }
  END {
    for (k in s) {
      split(k,a,",")
      printf "%s,%s,%s,%s,%s,%.6f\n", a[1],a[2],a[3],a[4],a[5], s[k]/c[k]
    }
  }' "$CSV" >"$CSV.tmp" && mv "$CSV.tmp" "$CSV"

if [[ -z "$DISKS" ]] && module_enabled disk; then
  DISKS=$(awk -F, -v d="$COMPARE_DATE" '$1==d && $3=="disk" && $5=="wkB" {s[$4]+=$6} END{
    for(k in s) print s[k],k}' "$CSV" | sort -rn | head -3 | awk '{print $2}' | paste -sd, -)
fi
if [[ -z "$IFACES" ]] && module_enabled net; then
  IFACES=$(awk -F, -v d="$COMPARE_DATE" '$1==d && $3=="net" && $5=="txkB" && $4!="lo" {s[$4]+=$6} END{
    for(k in s) print s[k],k}' "$CSV" | sort -rn | head -3 | awk '{print $2}' | paste -sd, -)
fi

IFS=',' read -ra DISK_ARR <<< "${DISKS:-}"
IFS=',' read -ra IFACE_ARR <<< "${IFACES:-}"

METRICS_FILE="$WORKDIR/metrics.lst"
: >"$METRICS_FILE"
if module_enabled cpu; then
  for m in iowait user system idle; do
    append_metric_line cpu "" "$m" "%" "cpu/${m}"
  done
fi
if module_enabled mem; then
  append_metric_line mem "" memused_pct "%" "mem/memused_pct"
fi
if module_enabled load; then
  append_metric_line load "" ldavg1 "" "load/ldavg1"
  append_metric_line load "" ldavg15 "" "load/ldavg15"
fi
if module_enabled swap; then
  append_metric_line swap "" pswpin "" "swap/pswpin"
  append_metric_line swap "" pswpout "" "swap/pswpout"
fi
for dev in "${DISK_ARR[@]}"; do
  [[ -n "$dev" ]] || continue
  append_metric_line disk "$dev" tps "" "${dev}/tps"
  append_metric_line disk "$dev" rkB "" "${dev}/rkB"
  append_metric_line disk "$dev" wkB "" "${dev}/wkB"
  append_metric_line disk "$dev" areq-sz "" "${dev}/areq-sz"
  append_metric_line disk "$dev" aqu-sz "" "${dev}/aqu-sz"
  append_metric_line disk "$dev" await "" "${dev}/await"
  append_metric_line disk "$dev" svctm "" "${dev}/svctm"
  append_metric_line disk "$dev" util "%" "${dev}/util"
done
for iface in "${IFACE_ARR[@]}"; do
  [[ -n "$iface" && "$iface" != "lo" ]] || continue
  for m in rxpck txpck rxkB txkB rxcmp txcmp rxmcst ifutil; do
    u=""
    [[ "$m" == "ifutil" ]] && u="%"
    append_metric_line net "$iface" "$m" "$u" "${iface}/${m}"
  done
done

[[ -s "$METRICS_FILE" ]] || {
  echo "ERROR: no metrics match -f ${METRICS_FILTER:-}(check -m/-f)" >&2
  exit 1
}

REPORT="$WORKDIR/report.txt"
awk -F, \
  -v cmp="$COMPARE_DATE" -v s30="$START_30" \
  -v th_mid="$THRESH_MID" -v th_hi="$THRESH_HIGH" \
  -v now_slot="$NOW_SLOT" -v cur_only="$CURRENT_SLOT_ONLY" \
  -v slots="$SLOTS_CSV" -v days7="$DAYS_7_CSV" -v daylabs="$DAY_LABELS_CSV" \
  -v metrics_file="$METRICS_FILE" \
  '
  function pct(t,b) {
    if (b=="" || t=="") return "N/A"
    if (b==0) return (t==0 ? "0" : "N/A")
    return sprintf("%.0f", (t-b)/b*100)
  }
  function trend(p) {
    if (p=="N/A") return "-"
    n=int(p)
    if (n>=th_hi) return "CRIT"
    if (n>=th_mid) return "HIGH"
    if (n<=-th_mid) return "LOW"
    return "OK"
  }
  function bar(v,m,   n,i,s) {
    if (m<=0) { m=v; if (m<=0) m=1 }
    n=int(v/m*10); if (n>10) n=10
    s=""; for(i=0;i<n;i++) s=s"#"; for(;i<10;i++) s=s"."
    return s
  }
  function fmt_cell(v, unit) {
    if (v=="") return sprintf("%8s", "-")
    if (unit=="%") return sprintf("%7.2f%%", v)
    return sprintf("%8.2f", v)
  }
  function fmt_vs30(p) {
    if (p=="N/A") return sprintf("%6s", "N/A")
    return sprintf("%5s%%", p)
  }
  function load_metrics(   line, n) {
    nm=0
    while ((getline line < metrics_file) > 0) {
      n=split(line, a, "|")
      if (n < 5) continue
      nm++
      mc[nm]=a[1]; me[nm]=a[2]; mt[nm]=a[3]; mu[nm]=a[4]; ml[nm]=a[5]
    }
    close(metrics_file)
  }
  function idx(d, slot, cat, ent, met, v) {
    k=cat SUBSEP ent SUBSEP met SUBSEP slot SUBSEP d
    data[k]=v
  }
  function getv(d, slot, cat, ent, met) {
    k=cat SUBSEP ent SUBSEP met SUBSEP slot SUBSEP d
    return data[k]
  }
  function max_cmp(cat, ent, met,   i, slot, v, mx) {
    mx=0
    for (i=1;i<=ns;i++) {
      slot=sl[i]
      v=getv(cmp, slot, cat, ent, met)
      if (v!="" && v+0>mx) mx=v+0
    }
    return mx
  }
  BEGIN {
    load_metrics()
    ns=split(slots, sl, ",")
    nd=split(days7, d7, ",")
    split(daylabs, dl, ",")
    hdr=sprintf("%5s %-18s %8s", "Slot", "Metric", "Compare")
    for (j=1; j<=nd; j++) hdr=hdr sprintf(" %8s", dl[j])
    hdr=hdr sprintf(" %8s %6s %5s %-10s", "30d-avg", "vs30d", "Trend", "Bar")
    print hdr
  }
  {
    d=$1; slot=$2; cat=$3; ent=$4; met=$5; v=$6
    idx(d, slot, cat, ent, met, v)
  }
  END {
    for (i=1;i<=ns;i++) {
      slot=sl[i]
      if (cur_only==1 && slot!=now_slot) continue
      for (m=1; m<=nm; m++) {
        cat=mc[m]; ent=me[m]; met=mt[m]; unit=mu[m]; label=ml[m]
        today=getv(cmp, slot, cat, ent, met)
        sum7=0; c7=0
        for (j=1; j<=nd; j++) {
          hv=getv(d7[j], slot, cat, ent, met)
          dayv[j]=hv
          if (hv!="") { sum7+=hv; c7++ }
        }
        b7=(c7>0)?sum7/c7:""
        sum30=0; c30=0
        for (k in data) {
          split(k, a, SUBSEP)
          if (a[1]!=cat || a[2]!=ent || a[3]!=met || a[4]!=slot) continue
          if (a[5]<cmp && a[5]>=s30) { sum30+=data[k]; c30++ }
        }
        b30=(c30>0)?sum30/c30:""
        p30=pct(today, b30)
        tr=trend(pct(today, b7))
        mx=max_cmp(cat, ent, met)
        barv=(today=="")?0:today
        row=sprintf("%5s %-18s %s", slot, label, fmt_cell(today, unit))
        for (j=1; j<=nd; j++) row=row " " fmt_cell(dayv[j], unit)
        row=row " " fmt_cell(b30, unit) " " fmt_vs30(p30) " " sprintf("%5s", tr) " " bar(barv, mx)
        print row
      }
    }
  }' "$CSV" >"$REPORT"

[[ -s "$REPORT" ]] || { echo "ERROR: no report rows generated"; exit 1; }

cat "$REPORT"
if [[ -n "$OUT_FILE" ]]; then
  cp "$REPORT" "$OUT_FILE"
  echo "" >&2
  echo "Report saved: ${OUT_FILE}" >&2
fi
