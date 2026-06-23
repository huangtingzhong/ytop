#!/usr/bin/env bash
# File Name: ps_mem.sh
# Purpose: Top processes and per-user RSS summary (ps snapshot)
# Created: 20260616  by  huangtingzhong
#
# Usage:
#   ps_mem.sh                  # top 25 processes + top 10 users (§2)
#   ps_mem.sh -U 0             # §2: all users
#   ps_mem.sh -U 20            # §2: top 20 users
#   ps_mem.sh -u yashan        # both sections: only user yashan
#   ps_mem.sh -y               # yasdb / yasagent only (process section)
#   ps_mem.sh -p 86501         # filter PID (process section)
#   ps_mem.sh -c 'bpftrace'    # filter COMMAND (process section)
#
# Note: Linux RSS is per-process; user RSS = sum of that user's processes.
#
# Value: quick OS memory snapshot (process RSS + per-user RSS sum)

set -eo pipefail

if [[ "$(uname -s 2>/dev/null)" != "Linux" ]]; then
  echo "ERROR: ps_mem.sh requires Linux (procps ps -eo)." >&2
  exit 1
fi

TOPN=25
USER_TOPN=10
USER_FILTER=""
COMM_FILTER=""
PID_FILTER=""
YASDB_ONLY=0
CMD_MAX=96

usage() {
  cat <<USAGE
Usage: $(basename "$0") [-n N] [-U N] [-u USER] [-c PATTERN] [-p PID] [-y]
  -n N   Top N processes by RSS (default: 25)
  -U N   Top N users in section 2 (default: 10; use -U 0 for all users)
  -u     Filter both sections by USER (exact match on ps USER column)
  -c     Filter process COMMAND (regex; section 2 unfiltered)
  -p     Filter process list by PID
  -y     Process list: yasdb / yasagent only
  -h     This help

Section 1: processes by RSS.  Section 2: per-user proc count + RSS sum.
USAGE
}

while getopts "n:U:u:c:p:yh" opt; do
  case "${opt}" in
    n) TOPN="${OPTARG}" ;;
    U) USER_TOPN="${OPTARG}" ;;
    u) USER_FILTER="${OPTARG}" ;;
    c) COMM_FILTER="${OPTARG}" ;;
    p) PID_FILTER="${OPTARG}" ;;
    y) YASDB_ONLY=1 ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1)) || true

if ! [[ "${TOPN}" =~ ^[0-9]+$ ]] || [[ "${TOPN}" -lt 1 ]]; then
  echo "ERROR: -n must be a positive integer" >&2
  exit 1
fi
if [[ "${USER_TOPN}" != "0" ]] && { ! [[ "${USER_TOPN}" =~ ^[0-9]+$ ]] || [[ "${USER_TOPN}" -lt 1 ]]; }; then
  echo "ERROR: -U must be a positive integer" >&2
  exit 1
fi
if [[ -n "${PID_FILTER}" ]] && ! [[ "${PID_FILTER}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: -p must be numeric PID" >&2
  exit 1
fi
if [[ "${YASDB_ONLY}" -eq 1 && -n "${COMM_FILTER}" ]]; then
  echo "ERROR: -y and -c are mutually exclusive" >&2
  exit 1
fi

ps_snapshot() {
  if ps -eo pid,user:14,rss,vsz,pmem,args --no-headers --sort=-rss 2>/dev/null; then
    return 0
  fi
  ps -eo pid,user,rss,vsz,pmem,args --no-headers 2>/dev/null | sort -k3 -nr
}

MEMTOTAL_KB="$(awk '/^MemTotal:/{print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)"

echo "=== Process memory (RSS desc) ==="
echo "SNAP $(date '+%F %T')"
echo ""
echo "=== System memory ==="
if free -h 2>/dev/null; then
  :
else
  awk '/^MemTotal:/ {printf "MemTotal: %s kB\n", $2}
       /^MemFree:/  {printf "MemFree:  %s kB\n", $2}
       /^MemAvailable:/ {printf "MemAvailable: %s kB\n", $2}
       /^SwapTotal:/ {printf "SwapTotal: %s kB\n", $2}
       /^SwapFree:/  {printf "SwapFree:  %s kB\n", $2}' /proc/meminfo 2>/dev/null || true
fi
echo ""

PS_ERR="$(mktemp)"
PS_LINES="$(mktemp)"
trap 'rm -f "${PS_ERR}" "${PS_LINES}"' EXIT

if ! ps_snapshot >"${PS_LINES}" 2>"${PS_ERR}"; then
  echo "ERROR: ps failed (need procps):" >&2
  sed 's/^/  /' "${PS_ERR}" >&2 || true
  exit 1
fi
if [[ ! -s "${PS_LINES}" ]]; then
  echo "ERROR: ps returned no data:" >&2
  sed 's/^/  /' "${PS_ERR}" >&2 || true
  exit 1
fi

# --- Section 1: top processes ---
echo "=== Top processes by RSS ==="
printf "%-8s %-14s %10s %10s %6s  %s\n" "PID" "USER" "RSS" "VSZ" "%MEM" "COMMAND"
printf "%s\n" "--------------------------------------------------------------------------------"

awk -v top="${TOPN}" -v u="${USER_FILTER}" -v c="${COMM_FILTER}" \
    -v pidf="${PID_FILTER}" -v yasdb_only="${YASDB_ONLY}" -v cmdmax="${CMD_MAX}" '
  function fmt_kb(kb,   n) {
    n = kb + 0
    if (n < 1024) return n "K"
    if (n < 1048576) return sprintf("%.2fM", n / 1024)
    return sprintf("%.2fG", n / 1048576)
  }
  function trunc_cmd(s,   n) {
    n = cmdmax + 0
    if (length(s) <= n) return s
    return substr(s, 1, n - 3) "..."
  }
  function yasdb_match(cmd) {
    return (cmd ~ /\/bin\/yasdb[[:space:]]/ || cmd ~ /\/bin\/yasagent[[:space:]]/)
  }
  BEGIN { IGNORECASE = 1; shown = 0; matched = 0 }
  {
    pid = $1; user = $2; rss = $3; vsz = $4; pmem = $5
    cmd = $6
    for (i = 7; i <= NF; i++) cmd = cmd " " $i
    if (pidf != "" && pid != pidf) next
    if (u != "" && user != u) next
    if (yasdb_only + 0 == 1 && !yasdb_match(cmd)) next
    if (c != "" && cmd !~ c) next
    matched++
    if (shown >= top) next
    shown++
    printf "%-8s %-14s %10s %10s %5s%%  %s\n",
      pid, user, fmt_kb(rss), fmt_kb(vsz), pmem, trunc_cmd(cmd)
  }
  END {
    if (matched == 0) print "(no matching processes)"
    else if (matched > shown) {
      if (c != "" || u != "" || pidf != "" || yasdb_only + 0 == 1)
        printf "\n(showing %d of %d matches; raise -n)\n", shown, matched
      else
        printf "\n(top %d by RSS; %d processes on host; raise -n for more)\n", shown, matched
    }
  }
' "${PS_LINES}"

# --- Section 2: per-user aggregate ---
echo ""
echo "=== Memory by USER (proc count + RSS sum) ==="
if [[ -n "${USER_FILTER}" ]]; then
  echo "(filter: user=${USER_FILTER})"
fi
printf "%-14s %8s %12s %8s\n" "USER" "PROCS" "RSS_SUM" "%MEM"
printf "%s\n" "----------------------------------------------------------------"

awk -v memtotal="${MEMTOTAL_KB}" -v user_top="${USER_TOPN}" -v u="${USER_FILTER}" '
  function fmt_kb(kb,   n) {
    n = kb + 0
    if (n < 1024) return n "K"
    if (n < 1048576) return sprintf("%.2fM", n / 1024)
    return sprintf("%.2fG", n / 1048576)
  }
  {
    user = $2; rss = $3 + 0
    if (u != "" && user != u) next
    if (!(user in procs)) order[++nu] = user
    procs[user]++
    rss_sum[user] += rss
  }
  END {
    if (nu == 0) {
      if (u != "") print "(no processes for user " u ")"
      else print "(no processes)"
      exit
    }
    for (i = 1; i <= nu; i++) {
      un = order[i]
      key[i] = rss_sum[un]
      usr[i] = un
    }
    for (i = 2; i <= nu; i++) {
      for (j = i; j > 1 && key[j-1] < key[j]; j--) {
        t = key[j-1]; key[j-1] = key[j]; key[j] = t
        t = usr[j-1]; usr[j-1] = usr[j]; usr[j] = t
      }
    }
    limit = nu
    if (user_top + 0 > 0 && nu > limit) limit = user_top + 0
    for (i = 1; i <= limit; i++) {
      un = usr[i]
      pct = (memtotal + 0 > 0) ? rss_sum[un] / memtotal * 100 : 0
      printf "%-14s %8d %12s %6.1f%%\n",
        un, procs[un], fmt_kb(rss_sum[un]), pct
    }
    if (user_top + 0 > 0 && nu > limit)
      printf "\n(top %d of %d users; -U 0 for all, or raise -U)\n", limit, nu
    else if (user_top + 0 == 0 && u == "" && nu > 0)
      printf "\n(%d users total)\n", nu
  }
' "${PS_LINES}"
