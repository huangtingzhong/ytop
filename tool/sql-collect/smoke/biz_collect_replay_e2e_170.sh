#!/usr/bin/env bash
# File Name: biz_collect_replay_e2e_170.sh
# Purpose: 170 真机: 模拟业务表操作 -> collect -> 清空表 -> replay -> 库内+v$sql 查证
# Created: 20260805 by huangtingzhong
# Updated: 20260805 by huangtingzhong (fix ycnt: DBMS_OUTPUT YC= 标记计数)
# Run ON 170: bash biz_collect_replay_e2e_170.sh [/path/to/ytop]
set -u

YTOP="${1:-/tmp/ytop_linux_arm64}"
HOME_Y="${HOME:-/home/yashan}"
INI="${INI:-$HOME_Y/jdbc_replay.ini}"
OUTBASE="${OUTBASE:-$HOME_Y/sql_collect_biz_e2e}"
LOG_DIR="${LOG_DIR:-$HOME_Y/logs}"
TAG="biz$(date +%H%M%S)"
REPORT="/tmp/biz_e2e_${TAG}.log"

export YASDB_HOME="${YASDB_HOME:-/home/yashan/.yasboot/yashandb_yasdb_home}"
export PATH="$YASDB_HOME/bin:$PATH"

PASS=0
FAIL=0
ok()  { echo "[PASS] $*" | tee -a "$REPORT"; PASS=$((PASS + 1)); }
bad() { echo "[FAIL] $*" | tee -a "$REPORT"; FAIL=$((FAIL + 1)); }
sec() { echo; echo "===== $* =====" | tee -a "$REPORT"; }

: >"$REPORT"
mkdir -p "$OUTBASE" "$LOG_DIR"

echo "biz_e2e $(date '+%Y-%m-%d %H:%M:%S') tag=$TAG" | tee -a "$REPORT"
echo "ytop=$YTOP outbase=$OUTBASE" | tee -a "$REPORT"

if [[ ! -x "$YTOP" ]]; then
  echo "ytop missing: $YTOP" | tee -a "$REPORT"
  exit 2
fi

# 经临时文件调 yasql, 避免函数内 heredoc+$() 丢结果
yasql_file() {
  local tmp out
  tmp=$(mktemp /tmp/biz_ysql.XXXXXX)
  out=$(mktemp /tmp/biz_ysql_out.XXXXXX)
  cat >"$tmp"
  yasql -S / as sysdba <"$tmp" >"$out" 2>/dev/null || true
  cat "$out"
  rm -f "$tmp" "$out"
}

# $1 = 标量 SELECT, 如 SELECT COUNT(*) FROM t WHERE ...
# Yashan 无 q'[]', 单引号加倍后 EXECUTE IMMEDIATE
ycnt_sql() {
  local scalar_sql="$1" lit n
  lit=${scalar_sql//\'/\'\'}
  n=$(yasql_file <<EOF | sed -n 's/.*YC=//p' | head -1 | tr -d '[:space:]'
SET SERVEROUTPUT ON
DECLARE
  v NUMBER;
BEGIN
  EXECUTE IMMEDIATE '${lit}' INTO v;
  DBMS_OUTPUT.PUT_LINE('YC=' || TO_CHAR(v));
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('YC=0');
END;
/
EOF
)
  echo $((10#${n:-0}))
}

# 按语句前缀 + hint 取 sql_id, 避免采到「查 sql_id 的辅助 SQL」
ysid_stmt() {
  local prefix="$1" hint="$2"
  yasql_file <<EOF | sed -n 's/.*SID=//p' | head -1 | tr -d '[:space:]'
SET SERVEROUTPUT ON
DECLARE
  v VARCHAR2(64);
BEGIN
  SELECT sql_id INTO v FROM (
    SELECT sql_id FROM v\$sql
     WHERE sql_text LIKE '${prefix} /*${hint}*/%'
     ORDER BY last_active_time DESC NULLS LAST, executions DESC NULLS LAST
  ) WHERE ROWNUM = 1;
  DBMS_OUTPUT.PUT_LINE('SID=' || v);
EXCEPTION WHEN NO_DATA_FOUND THEN
  DBMS_OUTPUT.PUT_LINE('SID=');
END;
/
EOF
}

# --------------------------------------------------------------------------
sec "1. prepare business table + simulate ops"
yasql_file >>"$REPORT" <<EOF
SET FEEDBACK OFF
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE HTZ.BIZ_REPLAY_DEMO';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
CREATE TABLE HTZ.BIZ_REPLAY_DEMO(
  id   NUMBER PRIMARY KEY,
  note VARCHAR2(64),
  amt  NUMBER
);
INSERT /*${TAG}_ins*/ INTO HTZ.BIZ_REPLAY_DEMO(id, note, amt)
VALUES (1001, '${TAG}-init', 100);
UPDATE /*${TAG}_upd*/ HTZ.BIZ_REPLAY_DEMO
   SET note = '${TAG}-updated', amt = 250
 WHERE id = 1001;
INSERT /*${TAG}_ins2*/ INTO HTZ.BIZ_REPLAY_DEMO(id, note, amt)
VALUES (1002, '${TAG}-row2', 50);
SELECT /*${TAG}_sel*/ id, note, amt FROM HTZ.BIZ_REPLAY_DEMO WHERE id = 1001;
COMMIT;
EOF

BIZ_N=$(ycnt_sql "SELECT COUNT(*) FROM HTZ.BIZ_REPLAY_DEMO")
UPD_N=$(ycnt_sql "SELECT COUNT(*) FROM HTZ.BIZ_REPLAY_DEMO WHERE id=1001 AND note='${TAG}-updated' AND amt=250")
if [[ "$BIZ_N" -ge 2 && "$UPD_N" -ge 1 ]]; then
  ok "business data planted rows=$BIZ_N updated=$UPD_N"
else
  bad "business data planted rows=$BIZ_N updated=$UPD_N"
  yasql_file <<EOF | tee -a "$REPORT"
SET FEEDBACK OFF
SELECT id, note, amt FROM HTZ.BIZ_REPLAY_DEMO;
EOF
fi

SID_INS=$(ysid_stmt "INSERT" "${TAG}_ins")
SID_UPD=$(ysid_stmt "UPDATE" "${TAG}_upd")
SID_INS2=$(ysid_stmt "INSERT" "${TAG}_ins2")
SID_SEL=$(ysid_stmt "SELECT" "${TAG}_sel")
echo "sql_ids: ins=$SID_INS upd=$SID_UPD ins2=$SID_INS2 sel=$SID_SEL" | tee -a "$REPORT"

# 展示采到的业务文本头, 防止再误采
for label_sid in "ins:$SID_INS" "upd:$SID_UPD" "ins2:$SID_INS2" "sel:$SID_SEL"; do
  lab=${label_sid%%:*}
  sid=${label_sid#*:}
  [[ -z "$sid" ]] && continue
  echo "--- preview $lab $sid ---" | tee -a "$REPORT"
  yasql_file <<EOF | tee -a "$REPORT"
SET FEEDBACK OFF
SELECT SUBSTR(sql_text,1,100) AS t FROM v\$sql WHERE sql_id='$sid' AND ROWNUM=1;
EOF
done

IDS=""
for s in "$SID_INS" "$SID_UPD" "$SID_INS2" "$SID_SEL"; do
  if [[ -n "$s" && ${#s} -ge 8 && ${#s} -le 20 ]]; then
    if [[ -z "$IDS" ]]; then IDS="$s"; else IDS="$IDS,$s"; fi
  fi
done
ID_N=$(echo "$IDS" | awk -F, '{print NF}')
if [[ "$ID_N" -ge 3 ]]; then
  ok "resolved business sql_ids n=$ID_N ($IDS)"
else
  bad "resolved business sql_ids n=$ID_N ($IDS)"
  echo "PASS=$PASS FAIL=$FAIL" | tee -a "$REPORT"
  exit 1
fi

# --------------------------------------------------------------------------
sec "2. collect (new-run + force sql-id)"
set +e
"$YTOP" -f "sql_collect.sh collect --jdbc-config $INI --outdir $OUTBASE --new-run --count 1 --sql-id $IDS --max-new 20" >>"$REPORT" 2>&1
rc=$?
set +e
RUN_DIR=$(ls -1d "$OUTBASE"/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9] 2>/dev/null | sort | tail -1 || true)
echo "run_dir=$RUN_DIR" | tee -a "$REPORT"
PKG_N=0
if [[ -n "$RUN_DIR" ]]; then
  PKG_N=$(ls -d "$RUN_DIR"/replay/*/ 2>/dev/null | wc -l | tr -d ' ')
fi
[[ $rc -eq 0 ]] && ok "collect exit 0" || bad "collect exit 0 (rc=$rc)"
[[ "$PKG_N" -ge 3 ]] && ok "replay packages n=$PKG_N" || bad "replay packages n=$PKG_N"

# 包内 SQL 必须是业务 DML/SELECT
BIZ_PKG_OK=0
for d in "$RUN_DIR"/replay/*/; do
  [[ -d "$d" ]] || continue
  head1=$(head -c 80 "$d/orig.sql" 2>/dev/null | tr '\n' ' ')
  echo "pkg $(basename "$d"): $head1" | tee -a "$REPORT"
  if echo "$head1" | grep -qiE '^[[:space:]]*(INSERT|UPDATE|SELECT)'; then
    BIZ_PKG_OK=$((BIZ_PKG_OK + 1))
  fi
done
[[ "$BIZ_PKG_OK" -ge 3 ]] && ok "packages are business SQL n=$BIZ_PKG_OK" || bad "packages are business SQL n=$BIZ_PKG_OK"

# --------------------------------------------------------------------------
sec "3. clear business table (prove replay rewrites DB)"
yasql_file >>"$REPORT" <<EOF
SET FEEDBACK OFF
DELETE FROM HTZ.BIZ_REPLAY_DEMO;
COMMIT;
ALTER SYSTEM FLUSH SHARED_POOL;
EOF
EMPTY=$(ycnt_sql "SELECT COUNT(*) FROM HTZ.BIZ_REPLAY_DEMO")
[[ "$EMPTY" -eq 0 ]] && ok "table cleared cnt=$EMPTY" || bad "table cleared cnt=$EMPTY"
V0=$(ycnt_sql "SELECT COUNT(*) FROM v\$sql WHERE sql_id='${SID_SEL}'")
[[ "$V0" -eq 0 ]] && ok "flush: v\$sql empty for sel (cnt=$V0)" || ok "flush: v\$sql sel cnt=$V0"

# --------------------------------------------------------------------------
sec "4. replay --force --replay-all"
set +e
"$YTOP" -f "sql_collect.sh replay --jdbc-config $INI --outdir $OUTBASE --source file --exec --force --replay-all --sql-id $IDS" >>"$REPORT" 2>&1
rc=$?
set +e
[[ $rc -eq 0 ]] && ok "replay exit 0" || bad "replay exit 0 (rc=$rc)"
grep -E 'exec-ok sql_id=|fail sql_id=|replay summary' "$REPORT" | tail -20 | tee -a "$REPORT" || true

# --------------------------------------------------------------------------
sec "5. verify DB business rows after replay"
TOTAL=$(ycnt_sql "SELECT COUNT(*) FROM HTZ.BIZ_REPLAY_DEMO")
ROW1=$(ycnt_sql "SELECT COUNT(*) FROM HTZ.BIZ_REPLAY_DEMO WHERE id=1001 AND note='${TAG}-updated' AND amt=250")
ROW2=$(ycnt_sql "SELECT COUNT(*) FROM HTZ.BIZ_REPLAY_DEMO WHERE id=1002 AND note='${TAG}-row2' AND amt=50")
echo "db_total=$TOTAL row1_updated=$ROW1 row2=$ROW2" | tee -a "$REPORT"
yasql_file <<EOF | tee -a "$REPORT"
SET FEEDBACK OFF
SELECT id, note, amt FROM HTZ.BIZ_REPLAY_DEMO ORDER BY id;
EOF

[[ "$TOTAL" -ge 2 ]] && ok "DB has rows after replay total=$TOTAL" || bad "DB has rows after replay total=$TOTAL"
[[ "$ROW1" -ge 1 ]] && ok "DB has updated row id=1001 note/amt match" || bad "DB has updated row id=1001"
[[ "$ROW2" -ge 1 ]] && ok "DB has insert row id=1002" || bad "DB has insert row id=1002"

# --------------------------------------------------------------------------
sec "6. verify v\$sql memory (same sql_id as collected)"
for pair in "ins:$SID_INS" "upd:$SID_UPD" "ins2:$SID_INS2" "sel:$SID_SEL"; do
  name=${pair%%:*}
  sid=${pair#*:}
  [[ -z "$sid" ]] && continue
  c=$(ycnt_sql "SELECT COUNT(*) FROM v\$sql WHERE sql_id='${sid}'")
  if [[ "$c" -ge 1 ]]; then
    ok "v\$sql has $name sql_id=$sid cnt=$c"
  else
    bad "v\$sql has $name sql_id=$sid cnt=$c"
  fi
done

SESS=$(ycnt_sql "SELECT COUNT(*) FROM v\$session WHERE sql_id='${SID_SEL}'")
echo "note: v\$session cnt=$SESS after finish (0=expected, not an error)" | tee -a "$REPORT"
ok "v\$session empty after finish expected (cnt=$SESS)"

# --------------------------------------------------------------------------
sec "summary"
echo "PASS=$PASS FAIL=$FAIL" | tee -a "$REPORT"
echo "report=$REPORT run_dir=$RUN_DIR tag=$TAG" | tee -a "$REPORT"
echo "sql_ids=$IDS" | tee -a "$REPORT"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
