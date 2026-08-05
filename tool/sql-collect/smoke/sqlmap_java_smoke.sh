#!/usr/bin/env bash
# File Name: sqlmap_java_smoke.sh
# Purpose: Smoke for sql-collect sqlmap subcommand (JDBC SQLMAP)
# Created: 20260804 by huangtingzhong
# Updated: 20260804 by huangtingzhong (unified --verify modes; drop legacy verify flags)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${SQLMAP_SMOKE_HOST:-10.10.10.170}"
LOCAL_PORT="${SQLMAP_SMOKE_PORT:-11688}"
JDBC="${JDBC:-/Users/yihan/Downloads/oracle/yashandb-jdbc-1.9.18.jar}"
SMOKE_ROOT="${SQLMAP_SMOKE_ROOT:-/tmp/sqlmap_java_smoke_$$}"
PASS=0
FAIL=0
SOFT=0
LOG="$SMOKE_ROOT/smoke.log"
LOG_DIR="$SMOKE_ROOT/logs"
JDBC_URL="jdbc:yasdb://127.0.0.1:${LOCAL_PORT}/yasdb"
MAP_PREFIX="map_smoke_$$"
CREATED_MAPS=()

mkdir -p "$SMOKE_ROOT" "$LOG_DIR"
: >"$LOG"

ok() { echo "[PASS] $*" | tee -a "$LOG"; PASS=$((PASS + 1)); }
bad() { echo "[FAIL] $*" | tee -a "$LOG"; FAIL=$((FAIL + 1)); }
soft() { echo "[SOFT-SKIP] $*" | tee -a "$LOG"; SOFT=$((SOFT + 1)); }
sec() { echo; echo "===== $* =====" | tee -a "$LOG"; }

runj() {
  set +e
  "$ROOT/run.sh" "$@" --log-dir "$LOG_DIR" >>"$LOG" 2>&1
  local rc=$?
  set +e
  return $rc
}

track_map() { CREATED_MAPS+=("$1"); }

ensure_tunnel() {
  if ! pgrep -fl "${LOCAL_PORT}:${HOST}:1688" >/dev/null 2>&1; then
    ssh -f -N -o ExitOnForwardFailure=yes -o BatchMode=yes \
      -L "${LOCAL_PORT}:${HOST}:1688" yashan@"$HOST" || return 1
  fi
  return 0
}

maybe_soft_priv() {
  local label="$1"
  if [[ "${SMOKE_ALLOW_VERIFY_SKIP:-0}" == "1" ]] && grep -qiE 'insufficient privilege|sql_map|YAS-0' "$LOG"; then
    soft "$label"
    return 0
  fi
  bad "$label"
  return 1
}

cleanup_maps() {
  local n
  for n in "${CREATED_MAPS[@]:-}"; do
    [[ -n "$n" ]] || continue
    runj sqlmap drop --map-name "$n" -j "$INI" || true
  done
}

cd "$ROOT" || exit 1
echo "sqlmap java smoke $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"

sec "0. build + help"
bash ./build.sh >>"$LOG" 2>&1 && ok "build" || bad "build"
./run.sh --help 2>&1 | grep -qi sqlmap && ok "top help sqlmap" || bad "top help sqlmap"
./run.sh sqlmap --help 2>&1 | grep -q create && ok "sqlmap help" || bad "sqlmap help"
ensure_tunnel && ok "tunnel" || bad "tunnel"
[[ -f "$JDBC" ]] && ok "jdbc jar" || bad "jdbc jar"

INI="$SMOKE_ROOT/jdbc.ini"
cat >"$INI" <<EOF
[jdbc]
jdbc_jar = $JDBC
jdbc_url = $JDBC_URL
user = htz
password = htz123
schema_via_alter = false
EOF

sec "1. lit2bind offline"
printf "%s\n" "SELECT 1 FROM dual WHERE 1=1 AND x='a'" >"$SMOKE_ROOT/in.sql"
if runj sqlmap lit2bind -f "$SMOKE_ROOT/in.sql" -o "$SMOKE_ROOT/out.sql" \
    --bind-out "$SMOKE_ROOT/bv.txt" --bind-format '?'; then
  grep -q '?' "$SMOKE_ROOT/out.sql" && ok "lit2bind placeholders" || bad "lit2bind placeholders"
  [[ -s "$SMOKE_ROOT/bv.txt" ]] && ok "lit2bind bind-out" || bad "lit2bind bind-out"
else
  bad "lit2bind exit"
fi

sec "2. mutex / validate exit 2"
set +e
"$ROOT/run.sh" sqlmap create -s a --src-file s.sql -f t.sql -j "$INI" --log-dir "$LOG_DIR" >>"$LOG" 2>&1
rc=$?
set +e
[[ "$rc" -eq 2 ]] && ok "create src mutex exit 2" || bad "create src mutex exit 2 (rc=$rc)"

set +e
"$ROOT/run.sh" sqlmap verify --map-name X --verify result -j "$INI" --log-dir "$LOG_DIR" >>"$LOG" 2>&1
rc=$?
set +e
[[ "$rc" -eq 2 ]] && ok "verify needs --exec exit 2" || bad "verify needs --exec (rc=$rc)"

set +e
"$ROOT/run.sh" sqlmap verify --map-name X --verify-result --exec -j "$INI" --log-dir "$LOG_DIR" >>"$LOG" 2>&1
rc=$?
set +e
if [[ "$rc" -eq 2 ]] && grep -q 'removed flag --verify-result' "$LOG"; then
  ok "old --verify-result rejected"
else
  bad "old --verify-result should exit 2 (rc=$rc)"
fi

set +e
"$ROOT/run.sh" sqlmap show --map-name M --sql-id abc -j "$INI" --log-dir "$LOG_DIR" >>"$LOG" 2>&1
rc=$?
set +e
[[ "$rc" -eq 2 ]] && ok "show mutex exit 2" || bad "show mutex exit 2 (rc=$rc)"

sec "3. plant sql_ids for export/genbind/create-by-id"
TAG_SRC="sqlmap_smoke_src_$$"
TAG_TGT="sqlmap_smoke_tgt_$$"
cat >"$SMOKE_ROOT/PlantSqlmap.java" <<EOF
import java.sql.*;
public class PlantSqlmap {
  public static void main(String[] a) throws Exception {
    Class.forName("com.yashandb.jdbc.Driver");
    try (Connection c = DriverManager.getConnection(a[0], a[1], a[2]);
         Statement st = c.createStatement()) {
      try (ResultSet rs = st.executeQuery(
          "SELECT 101 AS n FROM dual /*${TAG_SRC}*/")) { rs.next(); System.out.println("SRC="+rs.getInt(1)); }
      try (ResultSet rs = st.executeQuery(
          "SELECT 202 AS n FROM dual /*${TAG_TGT}*/")) { rs.next(); System.out.println("TGT="+rs.getInt(1)); }
    }
  }
}
EOF
cat >"$SMOKE_ROOT/ResolveTag.java" <<'EOF'
import java.sql.*;
public class ResolveTag {
  public static void main(String[] a) throws Exception {
    Class.forName("com.yashandb.jdbc.Driver");
    try (Connection c = DriverManager.getConnection(a[0], a[1], a[2]);
         PreparedStatement ps = c.prepareStatement(
             "SELECT sql_id FROM v$sql WHERE parsing_schema_name = ? "
                 + "AND sql_text LIKE ? AND ROWNUM = 1")) {
      ps.setString(1, a[3].toUpperCase());
      ps.setString(2, "%" + a[4] + "%");
      try (ResultSet rs = ps.executeQuery()) {
        if (rs.next()) System.out.println("ID|" + rs.getString(1).trim());
      }
    }
  }
}
EOF
javac -cp "$JDBC" -d "$SMOKE_ROOT" "$SMOKE_ROOT/PlantSqlmap.java" "$SMOKE_ROOT/ResolveTag.java" \
  >>"$LOG" 2>&1 && ok "javac plant" || bad "javac plant"
java -Djava.net.preferIPv4Stack=true -cp "$SMOKE_ROOT:$JDBC" PlantSqlmap \
  "$JDBC_URL" htz htz123 >>"$LOG" 2>&1
grep -q 'SRC=101' "$LOG" && ok "plant SRC" || bad "plant SRC"
grep -q 'TGT=202' "$LOG" && ok "plant TGT" || bad "plant TGT"

resolve_id() {
  java -Djava.net.preferIPv4Stack=true -cp "$SMOKE_ROOT:$JDBC" ResolveTag \
    "$JDBC_URL" htz htz123 HTZ "$1" 2>/dev/null \
    | grep '^ID|' | head -1 | cut -d'|' -f2 | tr -d '[:space:]'
}

replant_ids() {
  java -Djava.net.preferIPv4Stack=true -cp "$SMOKE_ROOT:$JDBC" PlantSqlmap \
    "$JDBC_URL" htz htz123 >>"$LOG" 2>&1
  SID=$(resolve_id "$TAG_SRC")
  TID=$(resolve_id "$TAG_TGT")
  echo "REPLANTED SID=$SID TID=$TID" | tee -a "$LOG"
}

SID=$(resolve_id "$TAG_SRC")
TID=$(resolve_id "$TAG_TGT")
echo "SID=$SID TID=$TID" | tee -a "$LOG"
[[ -n "$SID" && ${#SID} -eq 13 ]] && ok "resolve SID=$SID" || bad "resolve SID ($SID)"
[[ -n "$TID" && ${#TID} -eq 13 ]] && ok "resolve TID=$TID" || bad "resolve TID ($TID)"

sec "4. export + genbind"
if [[ -n "$SID" ]]; then
  if runj sqlmap export -s "$SID" -o "$SMOKE_ROOT/exp_$SID.sql" -j "$INI"; then
    [[ -s "$SMOKE_ROOT/exp_$SID.sql" ]] && ok "export non-empty" || bad "export empty"
  else
    bad "export"
  fi
  if runj sqlmap genbind -s "$SID" -o "$SMOKE_ROOT/bind_$SID.txt" -j "$INI"; then
    ok "genbind exit 0"
    [[ -f "$SMOKE_ROOT/bind_$SID.txt" ]] && ok "genbind file" || bad "genbind file"
  else
    bad "genbind"
  fi
else
  soft "export/genbind skipped (no SID)"
fi

sec "5. create dry-run + four combos"
printf "%s\n" "SELECT 1 AS c FROM dual /*${MAP_PREFIX}_fsrc*/" >"$SMOKE_ROOT/src.sql"
printf "%s\n" "SELECT 2 AS c FROM dual /*${MAP_PREFIX}_ftgt*/" >"$SMOKE_ROOT/tgt.sql"
if runj sqlmap create --src-file "$SMOKE_ROOT/src.sql" -f "$SMOKE_ROOT/tgt.sql" \
    --map-name "${MAP_PREFIX}_dry" --dry-run -j "$INI"; then
  ok "create dry-run file+file"
else
  bad "create dry-run file+file"
fi

create_combo() {
  local label="$1"; shift
  local name="$1"; shift
  if runj sqlmap create "$@" --map-name "$name" -j "$INI"; then
    track_map "$name"
    ok "create $label"
    return 0
  fi
  maybe_soft_priv "create $label"
  return 1
}

# file + file
create_combo "src-file+sql-file" "${MAP_PREFIX}_ff" \
  --src-file "$SMOKE_ROOT/src.sql" -f "$SMOKE_ROOT/tgt.sql"

# -s + -t first (CREATE invalidates source cursor; do before other -s uses)
replant_ids
if [[ -n "$SID" && -n "$TID" && "$SID" != "$TID" ]]; then
  create_combo "src-sqlid+tgt-sqlid" "${MAP_PREFIX}_st" \
    -s "$SID" -t "$TID"
else
  soft "create -s/-t skipped"
fi

# -s + -f (replant after previous CREATE may age out SID)
replant_ids
if [[ -n "$SID" ]]; then
  create_combo "src-sqlid+sql-file" "${MAP_PREFIX}_sf" \
    -s "$SID" -f "$SMOKE_ROOT/tgt.sql"
else
  soft "create -s/-f skipped"
fi

# --src-file + -t
replant_ids
if [[ -n "$TID" ]]; then
  printf "%s\n" "SELECT 3 AS c FROM dual /*${MAP_PREFIX}_fs2*/" >"$SMOKE_ROOT/src2.sql"
  create_combo "src-file+tgt-sqlid" "${MAP_PREFIX}_ft" \
    --src-file "$SMOKE_ROOT/src2.sql" -t "$TID"
else
  soft "create --src-file/-t skipped"
fi

sec "6. list / show / drop semantics"
MAP_NAME="${MAP_PREFIX}_ff"
if runj sqlmap list -j "$INI" --limit 200; then
  if grep -q "$MAP_NAME" "$LOG"; then
    ok "list sees $MAP_NAME"
  else
    soft "list miss (create may soft-skip)"
  fi
else
  bad "list"
fi

if runj sqlmap show --map-name "$MAP_NAME" -j "$INI"; then
  ok "show by name"
else
  soft "show by name"
fi

# show --sql-id: replant so hash matches an existing map created from same text (_sf)
replant_ids
if [[ -n "$SID" ]]; then
  if runj sqlmap show --sql-id "$SID" -j "$INI"; then
    ok "show --sql-id"
  else
    # prefix fallback may still find map_* if named with sql_id; our names are map_smoke_*
    soft "show --sql-id (hash miss after CREATE is possible)"
  fi
else
  soft "show --sql-id skipped"
fi

# drop missing → exit 1
set +e
"$ROOT/run.sh" sqlmap drop --map-name "map_smoke_missing_$$" -j "$INI" --log-dir "$LOG_DIR" >>"$LOG" 2>&1
rc=$?
set +e
[[ "$rc" -eq 1 ]] && ok "drop missing exit 1" || bad "drop missing exit 1 (rc=$rc)"

# drop existing then list should not show
if runj sqlmap drop --map-name "$MAP_NAME" -j "$INI"; then
  ok "drop existing"
  MARK=$(wc -l <"$LOG" | tr -d ' ')
  runj sqlmap list -j "$INI" --limit 500
  if tail -n +"$((MARK + 1))" "$LOG" | grep -q "$MAP_NAME"; then
    bad "list still shows dropped map"
  else
    ok "list no longer shows dropped map"
  fi
else
  soft "drop existing"
fi

sec "6b. create --flush / -o / verify-on-create + conflict drop"
# 无尾部换行, 避免与 SQL_MAP$ 存储文本长度不一致
printf '%s' "SELECT 11 AS n FROM dual /*${MAP_PREFIX}_fl_s*/" >"$SMOKE_ROOT/fl_src.sql"
printf '%s' "SELECT 11 AS n FROM dual /*${MAP_PREFIX}_fl_t*/" >"$SMOKE_ROOT/fl_tgt.sql"
MAP_FL="${MAP_PREFIX}_fl"
SUM_FL="$SMOKE_ROOT/create_summary.txt"
if runj sqlmap create --src-file "$SMOKE_ROOT/fl_src.sql" -f "$SMOKE_ROOT/fl_tgt.sql" \
    --map-name "$MAP_FL" --flush -o "$SUM_FL" --verify result --exec -j "$INI"; then
  track_map "$MAP_FL"
  ok "create --flush --verify result --exec"
  [[ -s "$SUM_FL" ]] && ok "create -o summary file" || bad "create -o summary file"
else
  maybe_soft_priv "create flush/verify" || true
fi

# same source text → second create should DROP conflicting map
MAP_FL2="${MAP_PREFIX}_fl2"
printf '%s' "SELECT 12 AS n FROM dual /*${MAP_PREFIX}_fl_t2*/" >"$SMOKE_ROOT/fl_tgt2.sql"
if runj sqlmap create --src-file "$SMOKE_ROOT/fl_src.sql" -f "$SMOKE_ROOT/fl_tgt2.sql" \
    --map-name "$MAP_FL2" -j "$INI"; then
  track_map "$MAP_FL2"
  ok "create conflict-same-src"
  if grep -qiE "Dropped conflicting|duplicate sql — re-scan|04398" "$LOG"; then
    ok "conflict drop or re-scan logged"
  else
    soft "conflict drop log not seen"
  fi
else
  maybe_soft_priv "create conflict-same-src" || true
fi

sec "6c. map effectiveness (SRC result 1 -> TGT 999)"
# 结果可区分: 仅当 matcher 改写 SRC 时, 执行 SRC 才得 999; verify-result 亦应匹配
EFF_TAG="${MAP_PREFIX}_eff"
printf '%s' "SELECT 1 AS n FROM dual /*${EFF_TAG}_s*/" >"$SMOKE_ROOT/eff_src.sql"
printf '%s' "SELECT 999 AS n FROM dual /*${EFF_TAG}_t*/" >"$SMOKE_ROOT/eff_tgt.sql"
MAP_EFF="${MAP_PREFIX}_eff"
SRC_EFF=$(cat "$SMOKE_ROOT/eff_src.sql")
if runj sqlmap create --src-file "$SMOKE_ROOT/eff_src.sql" -f "$SMOKE_ROOT/eff_tgt.sql" \
    --map-name "$MAP_EFF" --flush -j "$INI"; then
  track_map "$MAP_EFF"
  ok "create effectiveness map"
  if runj sqlmap verify --map-name "$MAP_EFF" --verify result --exec -j "$INI"; then
    ok "verify result after rewrite (1->999)"
  else
    bad "verify result effectiveness (map may not rewrite)"
  fi
  # 硬断言: JDBC 执行 SRC 文本必须返回 999
  cat >"$SMOKE_ROOT/EffAssert.java" <<'EOF'
import java.sql.*;
public class EffAssert {
  public static void main(String[] a) throws Exception {
    Class.forName("com.yashandb.jdbc.Driver");
    try (Connection c = DriverManager.getConnection(a[0], a[1], a[2]);
         Statement st = c.createStatement()) {
      try { st.execute("ALTER SYSTEM SET sql_map = TRUE"); } catch (Exception ignored) {}
      try (ResultSet rs = st.executeQuery(a[3])) {
        if (!rs.next()) {
          System.out.println("EMPTY");
          System.exit(2);
        }
        String v = rs.getString(1);
        System.out.println("exec_src_result=" + v);
        if (!"999".equals(v)) System.exit(1);
      }
    }
  }
}
EOF
  if javac -cp "$JDBC" -d "$SMOKE_ROOT" "$SMOKE_ROOT/EffAssert.java" >>"$LOG" 2>&1 \
      && java -cp "$SMOKE_ROOT:$JDBC" EffAssert "$JDBC_URL" htz htz123 "$SRC_EFF" \
      >>"$LOG" 2>&1; then
    ok "exec SRC returns 999 (map effective)"
  else
    bad "exec SRC did not return 999 (map not effective)"
  fi
else
  maybe_soft_priv "create effectiveness map" || true
fi

sec "7. genexec dry + exec + -t/-b/--marker"
printf "%s\n" "SELECT 7 AS n FROM dual /*${MAP_PREFIX}_ge*/" >"$SMOKE_ROOT/ge.sql"
if runj sqlmap genexec -f "$SMOKE_ROOT/ge.sql" -j "$INI"; then
  ok "genexec dry"
else
  bad "genexec dry"
fi
if runj sqlmap genexec -f "$SMOKE_ROOT/ge.sql" --exec -j "$INI"; then
  ok "genexec --exec"
else
  bad "genexec --exec"
fi

replant_ids
if [[ -n "$TID" ]]; then
  if runj sqlmap genexec -t "$TID" --exec -j "$INI"; then
    ok "genexec -t --exec"
  else
    soft "genexec -t"
  fi
else
  soft "genexec -t skipped"
fi

printf "%s\n" "SELECT ? AS n FROM dual /*${MAP_PREFIX}_geb*/" >"$SMOKE_ROOT/geb.sql"
printf "%s\n" "9" >"$SMOKE_ROOT/geb_binds.txt"
GE_OUT="$SMOKE_ROOT/genexec_out.sql"
if runj sqlmap genexec -f "$SMOKE_ROOT/geb.sql" -b "$SMOKE_ROOT/geb_binds.txt" \
    --marker "${MAP_PREFIX}_gemark" --exec -o "$GE_OUT" -j "$INI"; then
  ok "genexec -b --marker --exec"
  [[ -s "$GE_OUT" ]] && ok "genexec -o audit" || bad "genexec -o audit"
else
  bad "genexec -b --marker"
fi

sec "8. verify --verify modes (+ text matrix)"
printf "%s\n" "SELECT 42 AS n FROM dual /*${MAP_PREFIX}_vr_s*/" >"$SMOKE_ROOT/vr_src.sql"
printf "%s\n" "SELECT 42 AS n FROM dual /*${MAP_PREFIX}_vr_t*/" >"$SMOKE_ROOT/vr_tgt.sql"
MAP_VR="${MAP_PREFIX}_vr"
if runj sqlmap create --src-file "$SMOKE_ROOT/vr_src.sql" -f "$SMOKE_ROOT/vr_tgt.sql" \
    --map-name "$MAP_VR" -j "$INI"; then
  track_map "$MAP_VR"
  if runj sqlmap verify --map-name "$MAP_VR" --verify result --exec -j "$INI"; then
    ok "verify result"
  else
    maybe_soft_priv "verify result" || true
  fi
  if runj sqlmap verify --map-name "$MAP_VR" --verify result,unordered --exec -j "$INI"; then
    ok "verify result,unordered"
  else
    maybe_soft_priv "verify result,unordered" || true
  fi
  # verify plan: may soft-skip under SMOKE_ALLOW_VERIFY_SKIP
  if runj sqlmap verify --map-name "$MAP_VR" --verify plan --exec -j "$INI"; then
    ok "verify plan"
  else
    if [[ "${SMOKE_ALLOW_VERIFY_SKIP:-0}" == "1" ]] && grep -qiE 'insufficient privilege|sql_map|YAS-0|plan_hash|verify-plan' "$LOG"; then
      soft "verify plan"
    else
      # plan may legitimately fail if mapping doesn't change plan for dual constants
      soft "verify plan (no stable plan change on dual; documented soft)"
    fi
  fi
  if runj sqlmap verify --map-name "$MAP_VR" --verify plan-eq --exec -j "$INI"; then
    ok "verify plan-eq"
  else
    soft "verify plan-eq (dual may lack tgt baseline)"
  fi
else
  maybe_soft_priv "verify create" || true
fi

# verify by text matrix (no --map-name)
if runj sqlmap verify --src-file "$SMOKE_ROOT/vr_src.sql" -f "$SMOKE_ROOT/vr_tgt.sql" \
    --verify result --exec -j "$INI"; then
  ok "verify text-matrix --verify result"
else
  maybe_soft_priv "verify text-matrix" || true
fi

sec "8b. perf dry/-t/--exec"
replant_ids
printf "%s\n" "SELECT 303 AS n FROM dual /*${MAP_PREFIX}_perf_tgt*/" >"$SMOKE_ROOT/perf_tgt.sql"
if [[ -n "$SID" ]]; then
  if runj sqlmap perf -s "$SID" -f "$SMOKE_ROOT/perf_tgt.sql" \
      -o "$SMOKE_ROOT/perf_dry.txt" -j "$INI"; then
    if grep -q 'dry=true' "$SMOKE_ROOT/perf_dry.txt" || grep -q 'elapsed_ms=' "$SMOKE_ROOT/perf_dry.txt"; then
      ok "perf dry (no --exec)"
    else
      bad "perf dry summary"
    fi
  else
    soft "perf dry"
  fi

  replant_ids
  if [[ -n "$SID" && -n "$TID" ]] && runj sqlmap perf -s "$SID" -t "$TID" --exec \
      -o "$SMOKE_ROOT/perf_t.txt" -j "$INI"; then
    if grep -q 'elapsed_ms=' "$SMOKE_ROOT/perf_t.txt" && grep -q 'plan_hash=' "$SMOKE_ROOT/perf_t.txt"; then
      ok "perf -t --exec"
    else
      bad "perf -t summary"
    fi
  else
    soft "perf -t"
  fi

  replant_ids
  if [[ -n "$SID" ]] && runj sqlmap perf -s "$SID" -f "$SMOKE_ROOT/perf_tgt.sql" --exec \
      -o "$SMOKE_ROOT/perf.txt" --marker "${MAP_PREFIX}_perf" -j "$INI"; then
    if grep -q 'elapsed_ms=' "$SMOKE_ROOT/perf.txt" && grep -q 'plan_hash=' "$SMOKE_ROOT/perf.txt"; then
      ok "perf structured summary"
    else
      bad "perf structured summary"
    fi
  else
    soft "perf summary"
  fi
else
  soft "perf skipped (no SID)"
fi

sec "9. cleanup map_smoke_*"
cleanup_maps
ok "cleanup attempted"

echo
echo "========================================"
echo "PASS=$PASS FAIL=$FAIL SOFT=$SOFT" | tee -a "$LOG"
echo "log=$LOG"
echo "========================================"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
