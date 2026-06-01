#!/bin/bash
# File Name: analyze_slow_log.sh
# Purpose: Analyze YashanDB slow SQL log files
# Created: 20260517  by  huangtingzhong

set -euo pipefail

TOPN_DEFAULT=10
SPLIT_BY_SECONDS_DEFAULT=300
KEEP_SPLIT_SLOW_LOG_FILE_DEFAULT=0

SLOW_LOG_FILE=""
TOPN="${TOPN_DEFAULT}"
SPLIT_BY_SECONDS="${SPLIT_BY_SECONDS_DEFAULT}"
KEEP_SPLIT_SLOW_LOG_FILE="${KEEP_SPLIT_SLOW_LOG_FILE_DEFAULT}"
SLOW_LOG_SUMMARY=""
COLLECT_START_TIME=""   # YYYY-MM-DD HH:MM:SS.mmm
COLLECT_DURATION=0      # seconds; 0 means "until now"
TABLES_PATTERN=""       # e.g. "table1|table2" (case-insensitive regex)

function usage() {
  cat <<'EOF'
Usage:
  analyze_slow_log.sh --log <slow.log> [options]

Required:
  -l, --log <file>               Slow SQL log file path

Optional:
  -n, --topn <N>                 Top N (default: 10)
  -s, --split <seconds>          Split window in seconds (default: 300; 0 disables splitting)
  -k, --keep-split <0|1>         Keep split log files (default: 0; only effective when --split>0)
  -o, --out <file>               Output summary file (default: slow.log.sum.YYYYmmdd_HHMMSS)
  -S, --start "<time>"           Collection start time (format: YYYY-MM-DD HH:MM:SS[.mmm])
  -d, --duration <seconds>       Collection duration in seconds (default: 0 means until now)
  -t, --tables "<pattern>"       Table filter on SQL text (case-insensitive regex; supports table1|table2)
  -h, --help                     Show help

Examples:
  --start "2026-02-05 16:08:59"
  --start "2026-02-05 16:08:59.303"
  --tables "CNTR|CONTAINER"

Default time window:
  - If neither --start nor --duration is provided: from now-1h to now
  - If only --start is provided: from start to now
  - If only --duration is provided: from now-duration to now
EOF
}

function die() {
  echo "[ERROR] $*" >&2
  exit 1
}

# Parse "YYYY-MM-DD HH:MM:SS.mmm" to epoch ms (Linux date -d; macOS date -j -f)
function ts_to_epoch_ms() {
  local ts="$1"
  local base
  local ms
  if [[ "${ts}" == *.* ]]; then
    base="${ts%.*}"
    ms="${ts##*.}"
  else
    base="${ts}"
    ms="000"
  fi
  ms="$(printf "%03d" "$((10#${ms}))" 2>/dev/null || echo "000")"
  local sec
  sec="$(date -d "${base}" +%s 2>/dev/null || true)"
  if [[ -z "${sec}" ]]; then
    sec="$(date -j -f "%Y-%m-%d %H:%M:%S" "${base}" +%s 2>/dev/null || true)"
  fi
  [[ -n "${sec}" ]] || return 1
  echo "$((sec * 1000 + 10#${ms}))"
}

# Current epoch ms (GNU date %3N; else second precision)
function now_epoch_ms() {
  local ms
  ms="$(date +%s%3N 2>/dev/null || true)"
  if [[ -n "${ms}" && "${ms}" =~ ^[0-9]+$ ]]; then
    echo "${ms}"
    return 0
  fi
  echo "$(( $(date +%s) * 1000 ))"
}

# Parse slow log to TSV: epoch_ms, time_str, sql_id, exec_ms, rows
# exec_ms from COST_EXECUTE_TIME (seconds, float), rounded to ms
function emit_records_tsv() {
  local slow_log_file="$1"
  local start_ms="${2:-}"
  local end_ms="${3:-}"
  local tables_pattern="${4:-}"

  awk -v START_MS="${start_ms}" -v END_MS="${end_ms}" -v TPAT="${tables_pattern}" '
    BEGIN {
      FS=" "
      OFS="\t"
      IGNORECASE=1
      ts_ms=""
      ts_str=""
      sql_id=""
      rows=""
      exec_ms=""
      sql_text=""
      inwin=1
    }
    function parse_time_to_ms(date_s, time_s,   t, ms, base, cmd, sec) {
      # time_s: HH:MM:SS or HH:MM:SS.mmm
      t = time_s
      ms = 0
      if (index(t, ".") > 0) {
        ms = substr(t, index(t, ".")+1)
        t = substr(t, 1, index(t, ".")-1)
      }
      base = date_s " " t
      cmd = "date -d \"" base "\" +%s 2>/dev/null"
      sec = ""
      cmd | getline sec
      close(cmd)
      if (sec == "" || sec+0 <= 0) return ""
      ms = int(ms + 0)
      return (sec+0) * 1000 + ms
    }
    function in_window(ms) {
      if (START_MS != "" && ms < START_MS) return 0
      if (END_MS   != "" && ms > END_MS) return 0
      return 1
    }
    function flush() {
      if (ts_ms == "" || !inwin) return
      if (sql_id == "" || rows == "" || exec_ms == "") return
      if (TPAT != "") {
        if (sql_text !~ TPAT) return
      }
      print ts_ms, ts_str, sql_id, exec_ms, rows
    }
    /^# TIME:/ {
      flush()
      # format: # TIME: YYYY-MM-DD HH:MM:SS.mmm
      date_s=$3
      time_s=$4
      ts_ms = parse_time_to_ms(date_s, time_s)
      if (ts_ms == "") { inwin=0 } else { inwin=in_window(ts_ms) }
      # normalize time string to include .mmm if missing
      if (index(time_s, ".") == 0) {
        ts_str = date_s " " time_s ".000"
      } else {
        # keep only 3 decimals if longer
        split(time_s, tt, ".")
        frac = tt[2]
        if (length(frac) < 3) frac = frac sprintf("%*s", 3-length(frac), "0")
        if (length(frac) > 3) frac = substr(frac, 1, 3)
        ts_str = date_s " " tt[1] "." frac
      }
      sql_id=""; rows=""; exec_ms=""; sql_text=""
      next
    }
    !inwin { next }
    /^# SQL_ID:/ { sql_id=$3; next }
    /^# ROWS_SENT:/ { rows=$3; next }
    /^# COST_EXECUTE_TIME:/ {
      v=$3+0.0
      exec_ms = int(v*1000+0.5)
      next
    }
    /^SQL:/ {
      sub(/^SQL:[[:space:]]*/, "", $0)
      sql_text = $0
      next
    }
    {
      # If SQL text already started, append subsequent non-# lines (multi-line SQL)
      if (sql_text != "" && $0 !~ /^#/) {
        sql_text = sql_text "\n" $0
      }
    }
    END { flush() }
  ' "${slow_log_file}"
}

function repeat() {
  local char="$1"
  local count="$2"
  local i
  for i in $(seq 1 "${count}"); do
    printf "%s" "${char}"
  done
  echo ""
}

function fmt_ms_to_s3() {
  local ms="$1"
  awk -v ms="${ms}" 'BEGIN{printf "%.3f", (ms/1000.0)}'
}

function get_topN() {
  local tsv_file="$1"
  local slow_log_file_label="$2"

  repeat "-" 96
  printf "Slow log file: %s\n" "${slow_log_file_label}"
  printf "Top %s SQL by execution time\n" "${TOPN}"
  printf "%15s %18s %18s %23s\n" "SQL_ID" "Exec_time(s)" "Rows" "TIME"
  repeat "-" 96

  # sort by exec_ms desc (field4), take topn
  sort -t $'\t' -k4,4nr "${tsv_file}" | head -n "${TOPN}" | \
    awk -F'\t' '{ printf("%15s %18.3f %18s %23s\n", $3, ($4/1000.0), $5, $2) }'
}

function sum_slow_log() {
  local tsv_file="$1"
  local slow_log_file_label="$2"

  local total_slow_sql
  total_slow_sql="$(wc -l "${tsv_file}" | awk '{print $1}')"

  local start_time end_time
  start_time="$(awk -F'\t' 'NR==1{print $2; exit}' "${tsv_file}" 2>/dev/null || true)"
  end_time="$(awk -F'\t' 'END{print $2}' "${tsv_file}" 2>/dev/null || true)"

  echo ""
  repeat "-" 120
  printf "%16s %-70s\n" "Slow log file:" "${slow_log_file_label}"
  printf "%16s %-70s\n" "Start time:" "${start_time:-N/A}"
  printf "%16s %-70s\n" "End   time:" "${end_time:-N/A}"
  printf "%16s %-70s\n" "Total slow sql:" "${total_slow_sql}"

  printf "\n%15s %12s %16s %16s %23s %23s %12s\n" \
    "SQL_ID" "Count" "Total_time(s)" "Avg_time(s)" "First_time" "Last_time" "Span(s)"

  awk -F'\t' '
    {
      # fields: 1=epoch_ms 2=time_str 3=sql_id 4=exec_ms 5=rows
      id=$3
      cnt[id]++
      tot_ms[id]+=$4
      if (!(id in first_ms) || $1 < first_ms[id]) { first_ms[id]=$1; first_ts[id]=$2 }
      if (!(id in last_ms)  || $1 > last_ms[id])  { last_ms[id]=$1;  last_ts[id]=$2 }
    }
    END{
      for (id in cnt) {
        c=cnt[id]
        total_s=tot_ms[id]/1000.0
        avg_s=tot_ms[id]/1000.0/c
        span_s=(last_ms[id]-first_ms[id])/1000.0
        if (c==1) span_s=total_s
        printf("%15s %12d %16.3f %16.3f %23s %23s %12.0f\n",
          id, c, total_s, avg_s, first_ts[id], last_ts[id], span_s)
      }
    }
  ' "${tsv_file}" | sort -rnk 2
}

function split_and_summarize() {
  local slow_log_file="$1"
  local tsv_file="$2"
  local split_seconds="$3"
  local start_ms_filter="${4:-}"
  local end_ms_filter="${5:-}"

  if [[ "${split_seconds}" -le 0 ]]; then
    return 0
  fi

  local first_epoch_ms
  first_epoch_ms="$(awk -F'\t' 'NR==1{print $1; exit}' "${tsv_file}" 2>/dev/null || true)"
  if [[ -z "${first_epoch_ms}" ]]; then
    return 0
  fi

  echo ""
  repeat "-" 120
  printf "Split by %s seconds\n" "${split_seconds}"
  repeat "-" 120

  local tmpdir=""
  if [[ "${KEEP_SPLIT_SLOW_LOG_FILE}" -ne 0 ]]; then
    tmpdir="./slow_log_splits.$(date "+%Y%m%d_%H%M%S")"
    mkdir -p "${tmpdir}"
  else
    tmpdir="$(mktemp -d)"
  fi

  # Split log into time-window files by TIME field (block-aligned)
  # Keep original blocks so sum_slow_log works on each split file
  local start_ms="${first_epoch_ms}"
  awk -v BASE_MS="${start_ms}" -v SPLIT_S="${split_seconds}" -v OUTDIR="${tmpdir}" -v START_MS="${start_ms_filter}" -v END_MS="${end_ms_filter}" '
    BEGIN { IGNORECASE=1; cur_file="" }
    function parse_time_to_ms(date_s, time_s,   t, ms, base, cmd, sec) {
      t = time_s
      ms = 0
      if (index(t, ".") > 0) {
        ms = substr(t, index(t, ".")+1)
        t = substr(t, 1, index(t, ".")-1)
      }
      base = date_s " " t
      cmd = "date -d \"" base "\" +%s 2>/dev/null"
      sec = ""
      cmd | getline sec
      close(cmd)
      if (sec == "" || sec+0 <= 0) return ""
      ms = int(ms + 0)
      return (sec+0)*1000 + ms
    }
    /^# TIME:/ {
      date_s=$3
      time_s=$4
      ts_ms=parse_time_to_ms(date_s, time_s)
      if (ts_ms == "") { cur_file="" ; next }
      if (START_MS != "" && ts_ms < START_MS) { cur_file=""; next }
      if (END_MS   != "" && ts_ms > END_MS)   { cur_file=""; next }
      idx = int(((ts_ms - BASE_MS)/1000.0) / SPLIT_S)
      if (idx < 0) { cur_file=""; next }
      cur_file = OUTDIR "/split_" idx ".log"
    }
    {
      if (cur_file != "") print $0 >> cur_file
    }
  ' "${slow_log_file}"

  # Summarize each split file
  local f
  for f in "${tmpdir}"/split_*.log; do
    [[ -f "${f}" ]] || continue
    local tsv_part
    tsv_part="$(mktemp)"
    emit_records_tsv "${f}" "" "" "${TABLES_PATTERN}" > "${tsv_part}" || true
    if [[ -s "${tsv_part}" ]]; then
      sum_slow_log "${tsv_part}" "${f}"
    fi
    rm -f "${tsv_part}"
    if [[ "${KEEP_SPLIT_SLOW_LOG_FILE}" -eq 0 ]]; then
      rm -f "${f}"
    fi
  done

  if [[ "${KEEP_SPLIT_SLOW_LOG_FILE}" -eq 0 ]]; then
    rmdir "${tmpdir}" 2>/dev/null || true
  else
    printf "\nSplit files kept in: %s\n" "${tmpdir}"
  fi
}

#
# Main: parse args
#

while [[ $# -gt 0 ]]; do
  case "$1" in
    -l|--log)
      [[ $# -ge 2 ]] || die "--log requires a value"
      SLOW_LOG_FILE="$2"; shift 2
      ;;
    --log=*)
      SLOW_LOG_FILE="${1#*=}"; shift 1
      ;;
    -n|--topn)
      [[ $# -ge 2 ]] || die "--topn requires a value"
      TOPN="$2"; shift 2
      ;;
    --topn=*)
      TOPN="${1#*=}"; shift 1
      ;;
    -s|--split)
      [[ $# -ge 2 ]] || die "--split requires a value"
      SPLIT_BY_SECONDS="$2"; shift 2
      ;;
    --split=*)
      SPLIT_BY_SECONDS="${1#*=}"; shift 1
      ;;
    -k|--keep-split)
      [[ $# -ge 2 ]] || die "--keep-split requires a value"
      KEEP_SPLIT_SLOW_LOG_FILE="$2"; shift 2
      ;;
    --keep-split=*)
      KEEP_SPLIT_SLOW_LOG_FILE="${1#*=}"; shift 1
      ;;
    -o|--out)
      [[ $# -ge 2 ]] || die "--out requires a value"
      SLOW_LOG_SUMMARY="$2"; shift 2
      ;;
    --out=*)
      SLOW_LOG_SUMMARY="${1#*=}"; shift 1
      ;;
    -S|--start)
      [[ $# -ge 2 ]] || die "--start requires a value"
      COLLECT_START_TIME="$2"; shift 2
      ;;
    --start=*)
      COLLECT_START_TIME="${1#*=}"; shift 1
      ;;
    -d|--duration)
      [[ $# -ge 2 ]] || die "--duration requires a value"
      COLLECT_DURATION="$2"; shift 2
      ;;
    --duration=*)
      COLLECT_DURATION="${1#*=}"; shift 1
      ;;
    -t|--tables)
      [[ $# -ge 2 ]] || die "--tables requires a value"
      TABLES_PATTERN="$2"; shift 2
      ;;
    --tables=*)
      TABLES_PATTERN="${1#*=}"; shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      die "Unknown argument: $1 (use -h for help)"
      ;;
  esac
done

[[ -n "${SLOW_LOG_FILE}" ]] || { usage; die "Missing required argument: --log"; }
[[ -f "${SLOW_LOG_FILE}" ]] || die "File not found: ${SLOW_LOG_FILE}"

if [[ -z "${SLOW_LOG_SUMMARY}" ]]; then
  SLOW_LOG_SUMMARY="slow.log.sum.$(date "+%Y%m%d_%H%M%S")"
fi

if ! [[ "${TOPN}" =~ ^[0-9]+$ ]] || [[ "${TOPN}" -le 0 ]]; then
  die "--topn must be a positive integer"
fi
if ! [[ "${SPLIT_BY_SECONDS}" =~ ^[0-9]+$ ]]; then
  die "--split must be a non-negative integer"
fi
if ! [[ "${KEEP_SPLIT_SLOW_LOG_FILE}" =~ ^[0-9]+$ ]]; then
  die "--keep-split must be 0 or 1"
fi
if ! [[ "${COLLECT_DURATION}" =~ ^[0-9]+$ ]]; then
  die "--duration must be a non-negative integer (seconds)"
fi
if [[ -n "${TABLES_PATTERN}" ]]; then
  : # regex validation is best-effort; invalid regex will simply match nothing in awk
fi

START_MS=""
END_MS=""
NOW_MS="$(now_epoch_ms)"

if [[ -z "${COLLECT_START_TIME}" ]]; then
  if [[ "${COLLECT_DURATION}" -gt 0 ]]; then
    # only duration: last duration seconds until now
    START_MS="$((NOW_MS - COLLECT_DURATION * 1000))"
    END_MS="${NOW_MS}"
  else
    # neither start nor duration: last 1 hour until now
    START_MS="$((NOW_MS - 3600 * 1000))"
    END_MS="${NOW_MS}"
  fi
else
  START_MS="$(ts_to_epoch_ms "${COLLECT_START_TIME}")" || die "Failed to parse --start time: ${COLLECT_START_TIME}"
  if [[ "${COLLECT_DURATION}" -gt 0 ]]; then
    END_MS="$((START_MS + COLLECT_DURATION * 1000))"
  else
    # start only: until now
    END_MS="${NOW_MS}"
  fi
fi

if [[ -n "${START_MS}" && -n "${END_MS}" && "${END_MS}" -lt "${START_MS}" ]]; then
  die "Invalid time window: end < start (check --start/--duration)"
fi

tmp_tsv="$(mktemp)"
trap 'rm -f "${tmp_tsv}"' EXIT

emit_records_tsv "${SLOW_LOG_FILE}" "${START_MS}" "${END_MS}" "${TABLES_PATTERN}" > "${tmp_tsv}" || true
if [[ ! -s "${tmp_tsv}" ]]; then
  echo "No slow SQL records matched (log may be empty, or filters excluded all records)."
  exit 0
fi

# TopN and overall summary
get_topN "${tmp_tsv}" "${SLOW_LOG_FILE}" | tee "${SLOW_LOG_SUMMARY}"
sum_slow_log "${tmp_tsv}" "${SLOW_LOG_FILE}" | tee -a "${SLOW_LOG_SUMMARY}"

# Per-window summary (needs original log for block structure)
split_and_summarize "${SLOW_LOG_FILE}" "${tmp_tsv}" "${SPLIT_BY_SECONDS}" "${START_MS}" "${END_MS}" | tee -a "${SLOW_LOG_SUMMARY}"

echo ""
echo "Summary written to: ${SLOW_LOG_SUMMARY}"

