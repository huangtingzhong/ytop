#!/usr/bin/env bash
# Verify Pid/Ord on a 100+ operator execution plan (default: b3r9gpydp6vtf)
set -euo pipefail
SQLID="${1:-b3r9gpydp6vtf}"
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
  2>&1 | tee "$DIR/run_complex_result.txt"

LOG="/Users/yihan/tool/develop/yasinstaller/.cursor/debug-934178.log"
# #region agent log
python3 - "$DIR/run_complex_result.txt" "$LOG" <<'PY'
import json, re, sys, time
out, log = sys.argv[1:3]
pat = re.compile(r"^\|\s*(\d+)\|\s*(\d+|\s+)\|\s*(\d+)\|")
rows = []
for line in open(out, encoding="utf-8", errors="replace"):
    m = pat.match(line)
    if m:
        rows.append({"id": int(m.group(1)), "pid": m.group(2).strip() or None, "ord": int(m.group(3))})
sample = {r["id"]: {"pid": r["pid"], "ord": r["ord"]} for r in rows if r["id"] in (19, 20, 21, 0, 147)}
payload = {"sessionId": "934178", "runId": "oracle-lr-ord", "hypothesisId": "H3",
           "location": "run_complex_verify.sh", "message": "ord_left_right_sample",
           "data": {"sample": sample,
                    "merge_branch_19_20_21": {k: sample[k] for k in sample if int(k) in (19,20,21)}},
           "timestamp": int(time.time() * 1000)}
with open(log, "a") as f:
    f.write(json.dumps(payload) + "\n")
PY
# #endregion

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yashan@10.10.10.130 \
  'source ~/.bash_profile 2>/dev/null; echo "
SELECT id, parent_id, operation, options FROM v\$sql_plan
 WHERE sql_id='"'"'b3r9gpydp6vtf'"'"' AND plan_hash_value=244671926
   AND id IS NOT NULL AND operation IS NOT NULL ORDER BY id;
" | yasql -S sys/oracle@10.10.10.130:1688' 2>&1 | python3 -c "
import re,sys
for line in sys.stdin:
    m=re.match(r'^\s*(\d+)\s*(\d*)\s+(\S+)\s*(.*)$', line.rstrip())
    if m:
        print(','.join([m.group(1), m.group(2) or '', m.group(3), (m.group(4) or '').strip()]))
" | python3 -c "
import re,sys
rows=[]
for line in sys.stdin:
    p=line.strip().split(',')
    if len(p)>=3 and p[0].isdigit():
        rows.append((int(p[0]), int(p[1]) if p[1] else None, p[2], p[3] if len(p)>3 else ''))
for a,b,c,d in rows:
    print(f'{a},{b or \"\"},{c},{d}')
" | python3 "$DIR/verify_pid_ord.py" "$DIR/run_complex_result.txt" --display-pid || true
