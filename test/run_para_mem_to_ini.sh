#!/usr/bin/env bash
# Integration test: para_mem_to_ini.sql PROMPT hint + Enter default (dryrun=1)
# Run on a host where yasql is available (local sysdba or ytop -t SSH).
#
# Usage:
#   ./test/run_para_mem_to_ini.sh
#   YTOP=./build/ytop SQL=/path/to/para_mem_to_ini.sql ./test/run_para_mem_to_ini.sh
#   ./test/run_para_mem_to_ini.sh --ssh -t 10.10.10.130 -u yashan -s ~/.bashrc
#   # password login only if needed: add -p PASS or export YTOP_TEST_PASS

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
YTOP="${YTOP:-$ROOT/build/ytop}"
SQL="${SQL:-$ROOT/internal/scripts/sql/yashandb/para_mem_to_ini.sql}"
YTOP_ARGS=()

if [[ "${1:-}" == "--ssh" ]]; then
  shift
  YTOP_ARGS=("$@")
fi

if [[ ! -x "$YTOP" ]]; then
  echo "ytop not found: $YTOP (run: go build -o build/ytop ./cmd/ytop/)" >&2
  exit 1
fi
if [[ ! -f "$SQL" ]]; then
  echo "SQL not found: $SQL" >&2
  exit 1
fi

run_ytop() {
  # Enter only: dryrun should default to empty -> script NVL(..., 1) => dryrun mode
  printf '\n' | "$YTOP" "${YTOP_ARGS[@]}" -f "$SQL" 2>&1
}

echo "=== Test 1: PROMPT hint shown, Enter (dryrun=1, print only) ==="
out="$(run_ytop || true)"

echo "$out"
echo "---"

fail=0
if ! echo "$out" | grep -q 'dryrun (Enter=1 print only, 0=execute):'; then
  echo "FAIL: PROMPT hint not displayed before variable input" >&2
  fail=1
fi
if echo "$out" | grep -Eiq 'unknown.*PROMPT|YASQL-[0-9]+.*PROMPT|SP2-'; then
  echo "FAIL: PROMPT line reached DB CLI (should be stripped by ytop)" >&2
  fail=1
fi
if echo "$out" | grep -qi 'Error connecting to database'; then
  echo "SKIP: no database connection (set -t/-u/-p/-s or run on YashanDB host)" >&2
  exit 2
fi
if ! echo "$out" | grep -q 'ALTER SYSTEM SET'; then
  echo "FAIL: expected dryrun ALTER SYSTEM output" >&2
  fail=1
fi
if echo "$out" | grep -q '\[ERROR\]'; then
  echo "WARN: script reported errors (check output above)" >&2
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "PASS: PROMPT hint OK, dryrun output present"

echo ""
echo "=== Test 2: explicit dryrun=0 (execute) — optional, uncomment to run ==="
echo "# printf '0\n' | $YTOP ${YTOP_ARGS[*]} -f $SQL"
