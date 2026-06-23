#!/usr/bin/env bash
# File Name: ss_summary.sh
# Purpose: TCP socket summary listen backlog and connection states
# Created: 20260616  by  huangtingzhong
#
# Usage: ss_summary.sh
# Value: connection storm / listen backlog / TIME_WAIT surge (§5.4.1)

set -euo pipefail

echo "=== SNAP $(date '+%F %T') ==="
echo "=== ss -s (protocol summary) ==="
if ss -s 2>/dev/null; then
  :
elif netstat -s 2>/dev/null | head -50; then
  :
else
  echo "WARN: ss/netstat not available"
fi

echo ""
echo "=== TCP state counts ==="
if ss -tan 2>/dev/null | awk '
  NR > 1 {
    st = $1
    sub(/^[^-]+-/, "", st)
    c[st]++
  }
  END {
    for (k in c) printf "%-14s %8d\n", k, c[k]
  }' | sort -k2 -nr; then
  :
else
  netstat -ant 2>/dev/null | awk 'NR>2 && $6!=""{c[$6]++} END{for(k in c) print k,c[k]}'
fi

echo ""
echo "=== LISTEN (local, with process) ==="
ss -ltnp 2>/dev/null | head -30 || netstat -ltnp 2>/dev/null | head -30

echo ""
echo "=== ESTAB to yasdb/yash (sample) ==="
ss -tnp state established 2>/dev/null | grep -iE 'yasdb|yash|:1688|:1521|:8910' | head -25 || true

echo ""
echo "=== ESTAB / TIME-WAIT totals ==="
printf "established   %8d\n" "$(ss -tan state established 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"
printf "time-wait     %8d\n" "$(ss -tan state time-wait 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"
