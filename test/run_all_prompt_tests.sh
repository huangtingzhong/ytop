#!/usr/bin/env bash
# Run all YashanDB PROMPT/ACCEPT manual test scripts via ytop.
# Usage:
#   ./test/run_all_prompt_tests.sh              # interactive (you type each answer)
#   ./test/run_all_prompt_tests.sh --auto       # pipe preset inputs, smoke-check output
# Auth: default SSH key (~/.ssh/id_rsa). Set YTOP_TEST_PASS only for password login.
# Optional: YTOP_TEST_KEY=/path/to/key
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
YTOP="${YTOP:-$ROOT/build/ytop}"
HOST="${YTOP_TEST_HOST:-10.10.10.130}"
USER="${YTOP_TEST_USER:-yashan}"
SOURCE="${YTOP_TEST_SOURCE:-~/.bashrc}"
MODE="${1:-interactive}"

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

declare -a CASES=(
  "01_basic_mixed|test/test_yashandb_prompt_accept.sql|Enter filter name; ACCEPT top_n default 10|\n\n"
  "02_one_line_per_var|test/yashandb_prompt_02_one_line_per_var.sql|FIFO two PROMPT lines|100\n200\n"
  "03_banner_user|test/yashandb_prompt_03_banner_user.sql|Banner with &username|SYS\n"
  "04_three_vars|test/yashandb_prompt_04_three_vars.sql|Banner 2 vars + inst_id PROMPT|1\n2\n1\n"
  "05_third_no_prompt|test/yashandb_prompt_05_third_no_prompt.sql|inst_id uses Enter value for only|10\n20\n3\n"
  "06_orphan_accept|test/yashandb_prompt_06_orphan_accept.sql|Orphan skipped; a default 1|\n99\n"
  "07_dryrun_nvl|test/yashandb_prompt_07_dryrun_nvl.sql|Empty dryrun -> NVL default 1|\n"
  "08_no_prompt|test/yashandb_prompt_08_no_prompt.sql|No PROMPT banner at all|100\n"
  "09_comment_skip|test/yashandb_prompt_09_comment_skip.sql|Only &secret prompted|hello\n"
  "10_accept_defaults|test/yashandb_prompt_10_accept_defaults.sql|Two ACCEPT defaults on Enter|\n\n"
  "11_optional_filter|test/yashandb_prompt_11_optional_filter.sql|Empty login -> ALL|\n"
)

run_one() {
  local id="$1" sql_rel="$2" desc="$3" input="$4"
  local sql="$ROOT/$sql_rel"
  local out rc=0

  if [[ ! -f "$sql" ]]; then
    echo "SKIP $id: missing $sql_rel" >&2
    return 2
  fi

  echo ""
  echo "================================================================"
  echo "[$id] $desc"
  echo "SQL : $sql_rel"
  echo "================================================================"

  if [[ "$MODE" == "--auto" ]]; then
    out="$(printf '%b' "$input" | "$YTOP" "${YTOP_ARGS[@]}" -f "$sql" 2>&1)" || rc=$?
    echo "$out"
    if echo "$out" | grep -qi 'Error connecting to database'; then
      return 2
    fi
    if echo "$out" | grep -Eiq 'unknown.*PROMPT|YASQL.*PROMPT|SP2-'; then
      echo "FAIL [$id]: PROMPT/ACCEPT reached database CLI" >&2
      return 1
    fi
    return "$rc"
  fi

  echo "Expected: $desc"
  echo "  $YTOP ${YTOP_ARGS[*]} -f $sql_rel"
  read -r -p "Press Enter to run (Ctrl+C to stop)... "
  "$YTOP" "${YTOP_ARGS[@]}" -f "$sql"
}

echo "YashanDB PROMPT/ACCEPT test suite"
echo "Host: $HOST  Mode: $MODE"
echo ""
echo "Scripts:"
for entry in "${CASES[@]}"; do
  IFS='|' read -r id sql_rel desc _ <<< "$entry"
  printf "  %-22s %s\n" "$id" "$sql_rel"
done

if [[ "$MODE" != "--auto" && "$MODE" != "interactive" ]]; then
  echo "Usage: $0 [--auto|interactive]" >&2
  exit 1
fi

conn_fail=0
fail=0
for entry in "${CASES[@]}"; do
  IFS='|' read -r id sql_rel desc input <<< "$entry"
  if ! run_one "$id" "$sql_rel" "$desc" "$input"; then
    rc=$?
    if [[ "$rc" -eq 2 ]]; then
      conn_fail=1
      break
    fi
    fail=1
  fi
done

echo ""
if [[ "$conn_fail" -eq 1 ]]; then
  echo "Cannot connect to $HOST — check YTOP_TEST_* env and retry." >&2
  exit 2
fi
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "Done. Review output above for each case."
