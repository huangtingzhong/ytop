#!/usr/bin/env bash
# Five tables + five plan tests; show Pid/Ord (avoid slow DDL @file)
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
HOST="10.10.10.130"
YASQL='yasql -S sys/oracle@10.10.10.130:1688'
SQL_SH="/Users/yihan/tool/develop/yastop/internal/scripts/sql/yashandb/sql.sql"

# sql_id captured from v$sql (see plan_test_sql_ids.txt)
SQLID_Q1=4r45cmukz9dgs
SQLID_Q2=3b5yjk80p48ky
SQLID_Q3=9y5n9372aaur5
SQLID_Q4=517ja490d9j9r
SQLID_Q5=85zp37r5ugh37

show_plan() {
  local lbl="$1" sid="$2"
  echo ""
  echo "########################################################################"
  echo "# ${lbl}  sql_id=${sid}"
  echo "########################################################################"
  {
    echo "set serveroutput on;"
    awk '/^prompt PLAN from v\$sql_plan/,/^\/$/' "${SQL_SH}" | sed "s/&&sqlid/${sid}/g"
  } > "${DIR}/plan_show_${lbl}.sql"
  ytop -t "${HOST}" -u yashan -k ~/.ssh/id_rsa --login-cmd "${YASQL}" \
    -f "${DIR}/plan_show_${lbl}.sql" 2>&1 | tee "${DIR}/plan_result_${lbl}.txt" \
    | grep -E 'Plan Hash|SUBQUERY|OUTER|FILTER|SEMI|^\| *[0-9]' | head -24
}

echo "=== Run queries (optional, 60s timeout) ==="
scp -o ConnectTimeout=10 -q "${DIR}/plan_test_queries.sql" "yashan@${HOST}:/tmp/pt_queries.sql" 2>/dev/null || true
timeout 60 ssh -o ConnectTimeout=10 "yashan@${HOST}" \
  "source ~/.bash_profile 2>/dev/null; ${YASQL} @/tmp/pt_queries.sql" 2>&1 | tail -3 || echo "(skip if timeout)"

show_plan Q1_FILTER_SUBQ "${SQLID_Q1}"
show_plan Q2_LEFT_JOIN     "${SQLID_Q2}"
show_plan Q3_RIGHT_JOIN    "${SQLID_Q3}"
show_plan Q4_EXISTS_SUBQ   "${SQLID_Q4}"
show_plan Q5_FULL_FILTER   "${SQLID_Q5}"

echo ""
echo "Done. Full plans: ${DIR}/plan_result_Q*.txt"
