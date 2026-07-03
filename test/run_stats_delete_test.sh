#!/usr/bin/env bash
# Quick test for stats_delete.sql on YashanDB
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
YTOP="${YTOP:-$ROOT/build/ytop}"
SQL="stats_delete.sql"
HOST="${YTOP_TEST_HOST:-10.10.10.130}"
USER="${YTOP_TEST_USER:-yashan}"
SOURCE="${YTOP_TEST_SOURCE:-~/.bashrc}"

usage() {
  cat <<'EOF'
Usage: ./test/run_stats_delete_test.sh [options]

Safe default: dry-run only (invalid table __YTOP_STATS_DELETE_TEST__),
              verifies script syntax and PL/SQL execution without deleting real stats.

Options:
  --live   Run destructive test on real table (requires env vars below)
  -h       Show help

Live test env (only with --live):
  YTOP_STATS_OWNER      schema name
  YTOP_STATS_TABLE      table name
  YTOP_STATS_PARTITION  optional partition name
  YTOP_STATS_COLUMN     optional column name

Examples:
  ./test/run_stats_delete_test.sh
  YTOP_TEST_PASS=oracle ./test/run_stats_delete_test.sh
  ./test/run_stats_delete_test.sh --live   # needs YTOP_STATS_OWNER/TABLE set
EOF
}

LIVE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --live) LIVE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if [[ ! -x "$YTOP" ]]; then
  echo "Building ytop..." >&2
  (cd "$ROOT" && go build -o build/ytop ./cmd/ytop/)
fi

YTOP_ARGS=(-t "$HOST" -u "$USER" -s "$SOURCE")
if [[ -n "${YTOP_TEST_PASS:-}" ]]; then
  YTOP_ARGS+=(-p "$YTOP_TEST_PASS")
fi
if [[ -n "${YTOP_TEST_KEY:-}" ]]; then
  YTOP_ARGS+=(-k "$YTOP_TEST_KEY")
fi

fail_msg() { echo "FAIL: $1" >&2; }

run_with_inputs() {
  local name="$1"
  local inputs="$2"
  local expect_patterns=()
  shift 2
  while [[ $# -gt 0 ]]; do
    expect_patterns+=("$1")
    shift
  done
  echo ""
  echo "=== $name ==="
  local out
  out="$(printf '%s' "$inputs" | "$YTOP" "${YTOP_ARGS[@]}" -f "$SQL" 2>&1)" || true
  echo "$out"
  if echo "$out" | grep -Eiq 'Error connecting to database|SSH connection failed|authentication fail'; then
    fail_msg "cannot connect (SSH/DB). Set YTOP_TEST_PASS or YTOP_TEST_KEY"
    return 2
  fi
  if echo "$out" | grep -Eiq 'PLS-|YASQL-[0-9]|SP2-'; then
    if echo "$out" | grep -Eiq 'WARN no matching table|owner not found'; then
      :
    else
      fail_msg "SQL/PLSQL error in output"
      return 1
    fi
  fi
  local pat
  for pat in "${expect_patterns[@]}"; do
    if ! echo "$out" | grep -Eq "$pat"; then
      fail_msg "expected pattern not found: $pat"
      return 1
    fi
  done
  echo "PASS"
  return 0
}

echo "YashanDB stats_delete.sql test on $HOST"
rc=0

if [[ "$LIVE" -eq 0 ]]; then
  run_with_inputs \
    "Dry-run (default, print only)" \
    $'\nTPCC\n__YTOP_STATS_DELETE_TEST__\n\n\n' \
    'INFO dryrun=1' \
    'print only' \
    'DONE planned=0' \
    'WARN no matching table' || rc=$?
else
  owner="${YTOP_STATS_OWNER:?set YTOP_STATS_OWNER for --live}"
  table="${YTOP_STATS_TABLE:?set YTOP_STATS_TABLE for --live}"
  part="${YTOP_STATS_PARTITION:-}"
  col="${YTOP_STATS_COLUMN:-}"
  run_with_inputs \
    "Live delete stats" \
    $'0\n'"${owner}"$'\n'"${table}"$'\n'"${part}"$'\n'"${col}"$'\n' \
    'INFO dryrun=0' \
    'execute' \
    'DONE deleted=' || rc=$?
fi

if [[ "$rc" -eq 2 ]]; then
  exit 2
fi
if [[ "$rc" -ne 0 ]]; then
  exit 1
fi
echo ""
echo "stats_delete.sql test passed."
