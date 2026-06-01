#!/usr/bin/env bash
# Reproducible OS channel (ytop + SSH key + login-cmd), per db-connect-unified
set -euo pipefail
SQLID="${1:-cguk7353yk9yw}"
DIR="/Users/yihan/tool/develop/yastop/work/sql_plan_test"
mkdir -p "$DIR"
{
  echo "set serveroutput on;"
  awk '/^prompt PLAN from v\$sql_plan/,/^\/$/' \
    /Users/yihan/tool/develop/yastop/internal/scripts/sql/yashandb/sql.sql \
    | sed "s/&&sqlid/${SQLID}/g"
} > "$DIR/plan_ytop.sql"

ytop -t 10.10.10.130 -u yashan -k ~/.ssh/id_rsa \
  --login-cmd 'yasql -S sys/oracle@10.10.10.130:1688' \
  -f "$DIR/plan_ytop.sql" \
  2>&1 | tee "$DIR/run_result.txt"
