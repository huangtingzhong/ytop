#!/usr/bin/env bash
# Test ytop PROMPT + ACCEPT variable substitution on YashanDB
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
YTOP="${YTOP:-$ROOT/build/ytop}"
SQL="$ROOT/test/test_yashandb_prompt_accept.sql"
HOST="${YTOP_TEST_HOST:-10.10.10.130}"
USER="${YTOP_TEST_USER:-yashan}"
SOURCE="${YTOP_TEST_SOURCE:-~/.bashrc}"

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

run_case() {
  local name="$1"
  local input="$2"
  local want_top_n="$3"
  local want_name="$4"
  echo ""
  echo "=== $name ==="
  local out
  out="$(printf '%s' "$input" | "$YTOP" "${YTOP_ARGS[@]}" -f "$SQL" 2>&1)" || true
  echo "$out"
  local fail=0
  if ! echo "$out" | grep -q 'Enter top_n count:'; then
    echo "FAIL: ACCEPT prompt hint not shown" >&2
    fail=1
  fi
  if ! echo "$out" | grep -q 'Enter filter name (empty=ALL):'; then
    echo "FAIL: PROMPT hint not shown" >&2
    fail=1
  fi
  if ! echo "$out" | grep -q "Enter value for &top_n (default 10):"; then
    echo "FAIL: ACCEPT default not shown in input prompt" >&2
    fail=1
  fi
  if echo "$out" | grep -qi 'Error connecting to database'; then
    echo "SKIP: cannot connect to YashanDB at $HOST" >&2
    return 2
  fi
  if ! echo "$out" | grep -Eiq "${want_top_n}.*${want_name}|${want_name}.*${want_top_n}|${want_top_n}\s+\|\s+${want_name}"; then
    if ! echo "$out" | grep -q "$want_top_n"; then
      echo "FAIL: expected top_n=$want_top_n in result" >&2
      fail=1
    fi
    if ! echo "$out" | grep -q "$want_name"; then
      echo "FAIL: expected filter_name=$want_name in result" >&2
      fail=1
    fi
  fi
  if echo "$out" | grep -Eiq 'unknown.*PROMPT|YASQL.*PROMPT|SP2-'; then
    echo "FAIL: PROMPT/ACCEPT reached yasql (not stripped)" >&2
    fail=1
  fi
  if [[ "$fail" -ne 0 ]]; then
    return 1
  fi
  echo "PASS"
  return 0
}

echo "YashanDB PROMPT/ACCEPT test"
echo "Host: $HOST  SQL: $SQL"

rc=0
run_case "ACCEPT default on Enter + empty name" $'\n\n' "10" "" || rc=$?
run_case "Explicit top_n=5 + name=APP" $'5\nAPP\n' "5" "APP" || rc=$?

if [[ "$rc" -eq 2 ]]; then
  exit 2
fi
if [[ "$rc" -ne 0 ]]; then
  exit 1
fi
echo ""
echo "All PROMPT/ACCEPT tests passed."
