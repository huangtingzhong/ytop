#!/usr/bin/env bash
# Version-aware script resolution test on YashanDB SSH env
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
YTOP="${YTOP:-$ROOT/build/ytop}"

# Test environment (passwordless SSH)
export YTOP_TEST_HOST="${YTOP_TEST_HOST:-10.10.10.130}"
export YTOP_TEST_USER="${YTOP_TEST_USER:-yashan}"

# Profile: default | 2888
#   default — ~/.bashrc, DB 23.4.x (may be down)
#   2888    — YashanDB 23.5 on port 2888
PROFILE="${YTOP_TEST_PROFILE:-default}"
case "$PROFILE" in
  2888)
    export YTOP_TEST_SOURCE="${YTOP_TEST_SOURCE:-/data/yashan/yasdb_home_2888/23.5.2.101/conf/yashandb_2888.bashrc}"
    export YTOP_EXPECT_WE_BYTES="${YTOP_EXPECT_WE_BYTES:-2334}"
    export YTOP_EXPECT_VERSION_PREFIX="${YTOP_EXPECT_VERSION_PREFIX:-23.5}"
    ;;
  *)
    export YTOP_TEST_SOURCE="${YTOP_TEST_SOURCE:-~/.bashrc}"
    export YTOP_EXPECT_WE_BYTES="${YTOP_EXPECT_WE_BYTES:-2576}"
    export YTOP_EXPECT_VERSION_PREFIX="${YTOP_EXPECT_VERSION_PREFIX:-23.4}"
    ;;
esac

HOST="$YTOP_TEST_HOST"
USER="$YTOP_TEST_USER"
SOURCE="$YTOP_TEST_SOURCE"
EXPECT_WE_BYTES="$YTOP_EXPECT_WE_BYTES"
EXPECT_VER_PREFIX="$YTOP_EXPECT_VERSION_PREFIX"

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

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

echo "Script version test env: ${USER}@${HOST} profile=${PROFILE} source=${SOURCE}"

echo ""
echo "=== remote yasql -v ==="
remote_ver="$(ssh -o BatchMode=yes "${USER}@${HOST}" "source ${SOURCE} 2>/dev/null; yasql -v 2>&1 | head -1")"
echo "$remote_ver"
echo "$remote_ver" | grep -q "$EXPECT_VER_PREFIX" || fail "yasql -v does not contain $EXPECT_VER_PREFIX"

echo ""
echo "=== -S we (VERSIONS column) ==="
"$YTOP" "${YTOP_ARGS[@]}" -S '^we' | grep -E 'we\.sql|we_23\.5\.sql' || fail "-S we listing"

echo ""
echo "=== auto version: -D -f we.sql (expect ${EXPECT_WE_BYTES} bytes) ==="
out="$("$YTOP" "${YTOP_ARGS[@]}" -D -f we.sql 2>&1)" || true
echo "$out" | grep -q "bytes=${EXPECT_WE_BYTES}" || fail "auto we.sql bytes (expected ${EXPECT_WE_BYTES})"
pass "auto version selects correct we.sql variant"

echo ""
echo "=== -V 23.5.1 -D -f we.sql -> we_23.5.sql (2334 bytes) ==="
out="$("$YTOP" "${YTOP_ARGS[@]}" -V 23.5.1 -D -f we.sql 2>&1)" || true
echo "$out" | grep -q 'bytes=2334' || fail "-V 23.5.1 bytes (expected we_23.5.sql ~2334)"
pass "-V 23.5.1 selects we_23.5.sql"

echo ""
echo "=== execute we.sql on 23.4 (smoke, skip if DB down) ==="
out="$("$YTOP" "${YTOP_ARGS[@]}" -f we.sql 2>&1 | head -8)" || true
echo "$out"
if echo "$out" | grep -qiE 'Connection refused|unable to CONNECT'; then
  echo "SKIP: database not running on ${HOST} (script resolution already verified)"
elif echo "$out" | grep -qi 'Error connecting'; then
  fail "SSH connect failed"
elif ! echo "$out" | grep -qiE 'SID_TID|YASQL-'; then
  fail "we.sql execution smoke"
else
  pass "we.sql executes on ${HOST}"
fi

echo ""
echo "All script version tests passed on ${USER}@${HOST}"
