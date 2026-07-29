#!/usr/bin/env bash
# File Name: gstack.sh
# Purpose: Print native backtraces for yasdb via gstack
# Created: 20260728 by huangtingzhong

# dash, or bash invoked as sh with posix mode. Re-exec with bash.
_need_bash=
if [ -z "${BASH_VERSION-}" ]; then
  _need_bash=y
elif shopt -qo posix 2>/dev/null; then
  _need_bash=y
fi
if [ -n "$_need_bash" ]; then
  _bash_for_gstack_sh="$(command -v bash 2>/dev/null)" || _bash_for_gstack_sh=/bin/bash
  if [ ! -x "$_bash_for_gstack_sh" ]; then
    printf '%s\n' "Error: gstack.sh requires Bash (not plain sh/dash, and not bash --posix)." >&2
    printf '%s\n' "Use: bash gstack.sh ...   or   chmod +x ./gstack.sh && ./gstack.sh ..." >&2
    exit 1
  fi
  exec "$_bash_for_gstack_sh" "$0" ${1+"$@"}
fi
unset _need_bash _bash_for_gstack_sh

set -euo pipefail

PROGNAME="$(basename "$0")"
DEFAULT_COMM="yasdb"

usage() {
  cat <<EOF
================================================================================
  $PROGNAME - native backtrace via gstack
================================================================================

  Attach to a process (default: ${DEFAULT_COMM}) and print C/C++ call stacks
  using gstack (from the gdb package).
  Attaching briefly stops the target; keep runs short on production.
  Tracing other users' processes usually needs root: sudo $PROGNAME ...

  Requires: gstack (install: sudo yum install -y gdb)

Usage:
  $PROGNAME [options...]

  Quick start:
    sudo $PROGNAME                 # resolve ${DEFAULT_COMM}, dump all threads
    sudo $PROGNAME -p <PID>        # explicit PID

--------------------------------------------------------------------------------
  Options
--------------------------------------------------------------------------------
  Option        Meaning                      Notes
  ------------  ---------------------------  ----------------------------------
  -h            Show this help
  -p PID        Target process ID            if omitted, resolve via -n
  -n NAME       Resolve PID by process name  default ${DEFAULT_COMM}
  -o FILE       Write stacks to FILE         default: stdout
  -d            Dry-run: print command only

--------------------------------------------------------------------------------
  Examples
--------------------------------------------------------------------------------
  sudo $PROGNAME
  sudo $PROGNAME -p 6326
  sudo $PROGNAME -p 6326 -o /tmp/yasdb.gstack
  $PROGNAME -p 6326 -d

Production: attach freezes the process briefly; prefer lab or a short window.
EOF
}

list_pids_by_name() {
  local name="$1"
  local pids=()

  if command -v pidof >/dev/null 2>&1; then
    # shellcheck disable=SC2207
    pids=( $(pidof "$name" 2>/dev/null || true) )
  fi

  if [[ ${#pids[@]} -eq 0 ]] && command -v pgrep >/dev/null 2>&1; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && pids+=("$line")
    done < <(pgrep -x "$name" 2>/dev/null || true)
  fi

  if [[ ${#pids[@]} -eq 0 ]] && command -v pgrep >/dev/null 2>&1; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && pids+=("$line")
    done < <(pgrep -f "$name" 2>/dev/null | head -20 || true)
  fi

  if [[ ${#pids[@]} -gt 0 ]]; then
    printf '%s\n' "${pids[@]}" | sort -u -n
  fi
}

format_pid_cmdline() {
  local p="$1"
  local line max=160
  if [[ -r "/proc/$p/cmdline" ]]; then
    line="$(tr '\0' ' ' < "/proc/$p/cmdline")"
  else
    line="(cmdline unreadable)"
  fi
  if [[ ${#line} -gt $max ]]; then
    line="${line:0:$max}..."
  fi
  printf '%s\n' "$line"
}

prompt_pick_pid() {
  local comm="$1"
  shift
  local pids=("$@")
  local i pid line choice

  echo "Multiple \"${comm}\" processes found. Select one:" >&2
  i=1
  for pid in "${pids[@]}"; do
    line="$(format_pid_cmdline "$pid")"
    printf '  [%u] pid=%s  %s\n' "$i" "$pid" "$line" >&2
    i=$((i + 1))
  done

  while true; do
    printf 'Enter choice [1-%u] or a PID listed above: ' "${#pids[@]}" >&2
    if ! read -r choice; then
      echo "Error: EOF on stdin; aborted." >&2
      exit 1
    fi
    if [[ -z "$choice" ]]; then
      echo "Empty input; try again." >&2
      continue
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      for pid in "${pids[@]}"; do
        if [[ "$choice" == "$pid" ]]; then
          printf '%s\n' "$pid"
          return 0
        fi
      done
      if [[ "$choice" -ge 1 && "$choice" -le ${#pids[@]} ]]; then
        printf '%s\n' "${pids[$((choice - 1))]}"
        return 0
      fi
    fi
    echo "Invalid choice. Enter a menu index (1-${#pids[@]}) or one of the PIDs." >&2
  done
}

main() {
  local pid=""
  local comm_name="$DEFAULT_COMM"
  local outfile=""
  local dry_run=0
  local help=0

  local OPTIND=1 opt
  while getopts "hp:n:o:d" opt; do
    case "$opt" in
      h) help=1 ;;
      p) pid="$OPTARG" ;;
      n) comm_name="$OPTARG" ;;
      o) outfile="$OPTARG" ;;
      d) dry_run=1 ;;
      *) usage; exit 2 ;;
    esac
  done
  shift $((OPTIND - 1)) || true

  if [[ "$help" -eq 1 ]]; then
    usage
    exit 0
  fi

  if [[ "$(uname -s 2>/dev/null)" != "Linux" ]]; then
    echo "Error: $PROGNAME requires Linux." >&2
    exit 1
  fi

  if ! command -v gstack >/dev/null 2>&1; then
    echo "Error: gstack not found. Install: sudo yum install -y gdb" >&2
    exit 1
  fi

  if [[ -z "$pid" ]]; then
    local pid_list=()
    while IFS= read -r line; do
      [[ -n "$line" ]] && pid_list+=("$line")
    done < <(list_pids_by_name "$comm_name")

    if [[ ${#pid_list[@]} -eq 0 ]]; then
      echo "Error: no PID found for process name '${comm_name}'. Use -p or change -n." >&2
      exit 1
    elif [[ ${#pid_list[@]} -eq 1 ]]; then
      pid="${pid_list[0]}"
    else
      if [[ "$dry_run" -eq 1 ]] || [[ ! -t 0 ]]; then
        echo "Error: multiple \"${comm_name}\" processes match; disambiguate with -p <PID>." >&2
        echo "Matches:" >&2
        local idx=1
        for p in "${pid_list[@]}"; do
          printf '  [%u] pid=%s  %s\n' "$idx" "$p" "$(format_pid_cmdline "$p")" >&2
          idx=$((idx + 1))
        done
        if [[ "$dry_run" -eq 1 ]]; then
          echo "Note: dry-run (-d) does not prompt; pass -p explicitly when several instances exist." >&2
        else
          echo "Note: stdin is not a TTY; re-run from an interactive shell or use -p." >&2
        fi
        exit 1
      fi
      pid="$(prompt_pick_pid "$comm_name" "${pid_list[@]}")"
    fi
  fi

  if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
    echo "Error: invalid PID: $pid" >&2
    exit 1
  fi

  if [[ ! -d "/proc/$pid" ]]; then
    echo "Error: PID $pid does not exist." >&2
    exit 1
  fi

  local -a cmd=("gstack" "$pid")

  echo ">>> target pid=$pid cmdline=$(format_pid_cmdline "$pid")" >&2
  echo ">>> backend=gstack (all threads)" >&2
  echo ">>> WARN: attach briefly stops the process" >&2

  if [[ "$dry_run" -eq 1 ]]; then
    printf 'DRY-RUN:'
    printf ' %q' "${cmd[@]}"
    printf '\n'
    exit 0
  fi

  local rc=0
  if [[ -n "$outfile" ]]; then
    {
      echo "# $PROGNAME pid=$pid backend=gstack ts=$(date '+%F %T')"
      echo "# cmdline=$(format_pid_cmdline "$pid")"
      echo "#"
      "${cmd[@]}"
    } >"$outfile" || rc=$?
    echo ">>> wrote $outfile" >&2
  else
    "${cmd[@]}" || rc=$?
  fi

  if [[ "$rc" -ne 0 ]]; then
    echo "Error: gstack failed (exit $rc). Need root? Or install debuginfo for symbols." >&2
    exit "$rc"
  fi
}

main "$@"
