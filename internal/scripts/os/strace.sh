#!/usr/bin/env bash
# File Name: strace.sh
# Purpose: Wrap strace for database syscall troubleshooting
# Created: 20260517  by  huangtingzhong

# dash, or bash invoked as `sh` with posix mode (no process substitution). Re-exec with bash.
_need_bash=
if [ -z "${BASH_VERSION-}" ]; then
  _need_bash=y
elif shopt -qo posix 2>/dev/null; then
  _need_bash=y
fi
if [ -n "$_need_bash" ]; then
  _bash_for_strace_sh="$(command -v bash 2>/dev/null)" || _bash_for_strace_sh=/bin/bash
  if [ ! -x "$_bash_for_strace_sh" ]; then
    printf '%s\n' "Error: strace.sh requires Bash (not plain sh/dash, and not bash --posix)." >&2
    printf '%s\n' "Use: bash strace.sh ...   or   chmod +x ./strace.sh && ./strace.sh ..." >&2
    exit 1
  fi
  exec "$_bash_for_strace_sh" "$0" ${1+"$@"}
fi
unset _need_bash _bash_for_strace_sh

set -euo pipefail

PROGNAME="$(basename "$0")"
DEFAULT_COMM="yasdb"

# Lowercase (Bash 3.x has no ${var,,})
lc() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

#-------------------------------------------------------------------------------
# Trace categories: strace -e trace= lists (comma-separated, no spaces).
# Syscall names may differ by kernel/arch; shrink the set if unknown syscall.
#-------------------------------------------------------------------------------

# Network: connect and send/recv (common TCP/UDP path)
TRACE_NETWORK="trace=connect,accept,accept4,socket,bind,listen,shutdown,setsockopt,getsockopt,getpeername,getsockname,sendto,recvfrom,sendmsg,recvmsg,send,recv"

# File metadata and open/close
TRACE_FS_META="trace=open,openat,creat,close,stat,fstat,lstat,statfs,fstatfs,access,faccessat,unlink,unlinkat,rename,renameat,chmod,fchmod,fchmodat,chown,fchown,lchown,truncate,ftruncate"

# Byte read/write and seek (datafiles, redo logs)
TRACE_IO_RW="trace=read,write,readv,writev,pread64,pwrite64,preadv,pwritev,preadv2,pwritev2,lseek,llseek"

# Flush and mmap persistence
TRACE_SYNC="trace=fsync,fdatasync,sync_file_range,msync,sync"

# Wait and sync primitives (block, schedule, locks)
TRACE_WAIT="trace=epoll_wait,epoll_pwait,poll,ppoll,select,pselect6,futex,nanosleep,clock_nanosleep,sched_yield"

# Memory mappings (huge pages / mmap IO)
TRACE_MEM="trace=mmap,munmap,mremap,madvise,brk,mprotect,mlock,munlock,mlockall,munlockall"

# DBA quick mix: common "where is it slow" syscalls
TRACE_QUICK="trace=connect,accept,accept4,sendto,recvfrom,sendmsg,recvmsg,send,recv,read,write,pread64,pwrite64,open,openat,close,fsync,fdatasync,epoll_wait,epoll_pwait,poll,futex,nanosleep,mmap,munmap"

# Connect phase only (handshake / timeout)
TRACE_CONNECT="trace=connect,socket,setsockopt,getsockopt"

# Disk rw and flush only (IO and fsync)
TRACE_DISK="trace=read,write,pread64,pwrite64,open,openat,close,fsync,fdatasync,sync_file_range,msync,lseek"

usage() {
  cat <<EOF
================================================================================
  $PROGNAME - database process syscall tracing (strace wrapper)
================================================================================

  Trace syscalls from the OS layer to spot slow network, disk IO, fsync, locks, etc.
  Tracing other users' processes usually needs root: sudo $PROGNAME ...
  Stop tracing: Ctrl+C (-C prints a syscall summary after exit)

Usage:
  $PROGNAME [options...] [-- extra strace arguments]

  Quick start (pick one):
    sudo $PROGNAME                    # resolve ${DEFAULT_COMM}, default -c quick
    sudo $PROGNAME -p <PID>           # explicit PID
    sudo $PROGNAME -p <PID> -c disk   # category; see "Trace categories" below

  Requires Bash; if invoked via sh, re-execs as bash.
  Category details and symptom hints: $PROGNAME -l

--------------------------------------------------------------------------------
  Options
--------------------------------------------------------------------------------
  Option        Meaning                      Notes
  ------------  ---------------------------  ----------------------------------
  -h            Show this help               no arguments
  -l            List trace categories        includes symptom -> category hints
  -p PID        Target process ID            if omitted, resolve via -n; multi-instance: pick or use -p
  -n NAME       Resolve PID by process name  default ${DEFAULT_COMM} (/proc/comm or pgrep)
  -c CATEGORY   Trace category (syscall set) default quick; see below
  -o FILE       Output file prefix           same as strace -o; with -F: FILE.<pid>
  -f            Trace child processes        same as strace -f (after fork)
  -F            One output file per PID      same as strace -ff; use with -o
  -C            Count/summary mode           same as strace -c; summary on exit
  -y            Show path next to fd         same as strace -y; e.g. pread64(3</data/...>,...)
  -s SIZE       Max string print length      same as strace -s; omit for strace default
  -d            Dry-run: print command only  must be BEFORE --; after --, -d goes to strace

  Note: this script's -d is dry-run; strace's own debug -d belongs after --.

--------------------------------------------------------------------------------
  Trace categories (-c)
--------------------------------------------------------------------------------
  Category    What is traced                           Typical use
  ----------  ---------------------------------------  ---------------------------
  quick       net + rw + open/close + fsync + wait     first pass: where time goes
  network     connect/send/recv sockets                slow connect, replication net
  connect     connect/socket only                      handshake / connect timeout
  disk        rw + open + fsync (no network)           datafiles, redo, flush
  io          pread/pwrite/read/write/lseek            large IO, latency per call (-T)
  sync        fsync/fdatasync/msync                    checkpoint / log flush stalls
  fs          open/stat/rename metadata                many small files, paths, perms
  wait        epoll/futex/nanosleep                    low CPU, sessions not moving
  mem         mmap/brk/mprotect                        mappings, address space
  io_net      disk rw + network (no wait syscalls)     IO and net together, less wait noise
  full_io     io + metadata + sync (heavier disk set)  deep disk-side investigation
  custom      none; pass -e trace=... after --         only a few syscalls

--------------------------------------------------------------------------------
  Defaults (when not overridden)
--------------------------------------------------------------------------------
  - strace flags: -ttt -T (timestamps + per-syscall time); with -C: -c
  - target comm is yasdb and no -f/-F: auto -f (follow forked children)
  - -c in disk/io/full_io/sync/quick/io_net: auto -y (fd paths in lines)
  - disable auto behavior: see "Environment variables" below

--------------------------------------------------------------------------------
  Environment variables
--------------------------------------------------------------------------------
  STRACE_SH_NO_AUTO_FORK=1   do not auto-add -f for yasdb
  STRACE_SH_NO_AUTO_Y=1      do not auto-add -y for disk-related categories

--------------------------------------------------------------------------------
  Extra strace arguments
--------------------------------------------------------------------------------
  Append at end of command, or after -- (custom category needs -e after --):

    $PROGNAME -p <PID> -c custom -- -e trace=read,write
    $PROGNAME -p <PID> -c network -d          # -d before --: this script dry-run
    $PROGNAME -p <PID> -c custom -- -d        # -d after --: strace debug option

--------------------------------------------------------------------------------
  Common examples
--------------------------------------------------------------------------------
  # 1) Default: resolve ${DEFAULT_COMM}, quick category (usual entry point)
  sudo $PROGNAME

  # 2) Multiple instances: confirm PID with ps; non-TTY requires -p
  sudo $PROGNAME -p 6326

  # 3) Slow client connect / listen timeout -> network or connect only
  sudo $PROGNAME -p 6326 -c network
  sudo $PROGNAME -p 6326 -c connect

  # 4) Slow SQL and busy disk -> rw and flush (-T is per-syscall time)
  sudo $PROGNAME -p 6326 -c disk
  sudo $PROGNAME -p 6326 -c sync

  # 5) Many sessions, low throughput, low CPU -> locks / epoll / sleep
  sudo $PROGNAME -p 6326 -c wait

  # 6) Count mode: Ctrl+C then see which syscalls dominate
  sudo $PROGNAME -p 6326 -C -c quick

  # 7) Long capture: file output + one file per child (yasdb -f case)
  sudo $PROGNAME -p 6326 -c quick -o /tmp/yasdb.strace -F

  # 8) Process name other than ${DEFAULT_COMM}
  sudo $PROGNAME -n yashandb -p 12345 -c quick

  # 9) Preview the strace command before running (use -d before --)
  $PROGNAME -p 6326 -c network -d

  # 10) Custom syscall list: read/write only
  sudo $PROGNAME -p 6326 -c custom -- -e trace=read,write,pread64,pwrite64

  # 11) Disable auto -f for yasdb (no fork children, less overhead)
  STRACE_SH_NO_AUTO_FORK=1 sudo $PROGNAME -p 6326 -c quick

  # 12) Replication: network + standby disk writes together
  sudo $PROGNAME -p 6326 -c io_net

Production: keep runs short and narrow; strace is expensive on busy processes.
EOF
}

list_categories() {
  cat <<EOF
================================================================================
  Trace categories ($PROGNAME -l)
================================================================================

  Category    What is traced                           Typical use
  ----------  ---------------------------------------  -------------------------
  quick       net + datafile rw + open/close + fsync   first pass: find bottleneck
  network     connect/send/recv                        slow link, peer unreachable
  connect     connect/socket only                      connect/handshake phase
  disk        rw + open + fsync (no network syscalls)  datafiles, archive logs
  io          pread/pwrite/read/write/lseek            large IO; per-call -T time
  sync        fsync/fdatasync/msync                    flush, checkpoint stalls
  fs          open/stat/rename                         many small files, bad paths
  wait        epoll/futex/nanosleep                    low CPU, sessions stuck
  mem         mmap/brk/mprotect                        mapping growth, shared mem
  io_net      disk rw + network (no wait)              replication/backup IO+net
  full_io     io + metadata + sync (widest disk set)     deep disk-side (heavier)
  custom      append: -- -e trace=...                  your own syscall list

--------------------------------------------------------------------------------
  Symptom -> suggested category (heuristic, not absolute)
--------------------------------------------------------------------------------
  Slow connect / timeout / listen hang     connect  or  network
  Slow SQL and busy disk (iostat)          disk     or  sync   or  quick
  Many sessions, low throughput, low CPU   wait     (add io if needed)
  Replication / backup network issues      network  or  io_net
  Not sure where to start                  quick    (default)

Examples: $PROGNAME -h
EOF
}

# Print matching PIDs, one per line, sorted numerically (unique).
list_pids_by_name() {
  local name="$1"
  local pids=()

  if command -v pidof >/dev/null 2>&1; then
    # shellcheck disable=SC2207
    pids=( $(pidof "$name" 2>/dev/null || true) )
  fi

  if [[ ${#pids[@]} -eq 0 ]] && command -v pgrep >/dev/null 2>&1; then
    # Exact comm match
    while IFS= read -r line; do
      [[ -n "$line" ]] && pids+=("$line")
    done < <(pgrep -x "$name" 2>/dev/null || true)
  fi

  if [[ ${#pids[@]} -eq 0 ]] && command -v pgrep >/dev/null 2>&1; then
    # Loose: cmdline contains name (may false-match; fallback only)
    while IFS= read -r line; do
      [[ -n "$line" ]] && pids+=("$line")
    done < <(pgrep -f "$name" 2>/dev/null | head -20 || true)
  fi

  # Deduplicate PIDs
  if [[ ${#pids[@]} -gt 0 ]]; then
    printf '%s\n' "${pids[@]}" | sort -u -n
  fi
}

# Print a one-line cmdline for display (paths like yasdb_home/... and -D ... vary).
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

# Interactive menu when multiple processes match. Prints chosen PID on stdout.
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

pick_trace_expr() {
  local cat
  cat="$(lc "$1")"
  case "$cat" in
    quick)     printf '%s %s\n' "-e" "$TRACE_QUICK" ;;
    network)   printf '%s %s\n' "-e" "$TRACE_NETWORK" ;;
    fs)        printf '%s %s\n' "-e" "$TRACE_FS_META" ;;
    io)        printf '%s %s\n' "-e" "$TRACE_IO_RW" ;;
    sync)      printf '%s %s\n' "-e" "$TRACE_SYNC" ;;
    wait)      printf '%s %s\n' "-e" "$TRACE_WAIT" ;;
    mem)       printf '%s %s\n' "-e" "$TRACE_MEM" ;;
    disk)      printf '%s %s\n' "-e" "$TRACE_DISK" ;;
    connect)   printf '%s %s\n' "-e" "$TRACE_CONNECT" ;;
    io_net)    printf '%s %s\n' "-e" "trace=connect,accept,accept4,sendto,recvfrom,sendmsg,recvmsg,send,recv,read,write,pread64,pwrite64,open,openat,close" ;;
    custom)    printf '\n' ;;
    *)
      echo "Unknown category: $1" >&2
      echo "Run with -l for the category list." >&2
      exit 2
      ;;
  esac
}

# full_io: merge three trace= groups
build_full_io() {
  printf '%s %s\n' "-e" "trace=read,write,readv,writev,pread64,pwrite64,preadv,pwritev,preadv2,pwritev2,lseek,llseek,open,openat,creat,close,stat,fstat,lstat,statfs,fstatfs,access,faccessat,unlink,unlinkat,rename,renameat,chmod,fchmod,fchmodat,chown,fchown,lchown,truncate,ftruncate,fsync,fdatasync,sync_file_range,msync,sync"
}

main() {
  local pid=""
  local comm_name="$DEFAULT_COMM"
  local category="quick"
  local outfile=""
  local follow_fork=0
  local follow_ff=0
  local count_mode=0
  local strace_y=0
  local strace_s=""
  local dry_run=0
  local help=0
  local list=0

  local OPTIND=1 opt
  while getopts "hlp:n:c:o:fFCys:d" opt; do
    case "$opt" in
      h) help=1 ;;
      l) list=1 ;;
      p) pid="$OPTARG" ;;
      n) comm_name="$OPTARG" ;;
      c) category="$OPTARG" ;;
      o) outfile="$OPTARG" ;;
      f) follow_fork=1 ;;
      F) follow_ff=1 ;;
      C) count_mode=1 ;;
      y) strace_y=1 ;;
      s) strace_s="$OPTARG" ;;
      d) dry_run=1 ;;
      *) usage; exit 2 ;;
    esac
  done
  shift $((OPTIND - 1))
  if [[ "${1-}" == "--" ]]; then
    shift
  fi

  if [[ "$help" -eq 1 ]]; then
    usage
    exit 0
  fi
  if [[ "$list" -eq 1 ]]; then
    list_categories
    exit 0
  fi

  if ! command -v strace >/dev/null 2>&1; then
    echo "Error: strace not found. Install it (e.g. yum install -y strace or apt install -y strace)." >&2
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
      # Several instances (e.g. different yasdb_home / -D data paths): pick one.
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

  if [[ ! -r "/proc/$pid/cmdline" ]]; then
    echo "Error: cannot read /proc/$pid (process missing or no permission). Tracing other users' processes usually requires root." >&2
    exit 1
  fi

  local cat_lc
  cat_lc="$(lc "$category")"

  # On 10.10.10.125-style hosts: yasdb is multi-threaded; it may also fork short-lived helpers.
  # strace -p already traces threads in the same group, but -f is still recommended for forked children.
  if [[ -z "${STRACE_SH_NO_AUTO_FORK-}" ]] && [[ "$follow_fork" -eq 0 ]] && [[ "$follow_ff" -eq 0 ]]; then
    local proc_comm=""
    if [[ -r "/proc/$pid/comm" ]]; then
      proc_comm="$(tr '\0' '\n' < "/proc/$pid/comm" | head -n1)"
    fi
    proc_comm="$(lc "$proc_comm")"
    if [[ "$proc_comm" == "yasdb" ]]; then
      follow_fork=1
      echo ">>> auto-enabled -f for yasdb (follow forks). Disable: STRACE_SH_NO_AUTO_FORK=1 $PROGNAME ..." >&2
    fi
  fi

  # strace -y: show path next to fd (e.g. pread64(36</dev/yfs/sys1>, buf, ...)).
  if [[ -z "${STRACE_SH_NO_AUTO_Y-}" ]] && [[ "$strace_y" -eq 0 ]]; then
    case "$cat_lc" in
      disk|io|full_io|sync|quick|io_net)
        strace_y=1
        echo ">>> auto-enabled -y (fd paths in syscall lines). Disable: STRACE_SH_NO_AUTO_Y=1 $PROGNAME ..." >&2
        ;;
    esac
  fi

  local trace_args=()
  if [[ "$cat_lc" == "full_io" ]]; then
    read -r -a trace_args < <(build_full_io)
  elif [[ "$cat_lc" == "custom" ]]; then
    trace_args=()
  else
    read -r -a trace_args < <(pick_trace_expr "$category")
  fi

  local cmd=(strace)

  if [[ "$count_mode" -eq 1 ]]; then
    cmd+=(-c)
  else
    cmd+=(-ttt -T)
  fi

  if [[ "$follow_fork" -eq 1 ]]; then
    cmd+=(-f)
  fi
  if [[ "$follow_ff" -eq 1 ]]; then
    cmd+=(-ff)
  fi

  if [[ -n "$outfile" ]]; then
    cmd+=(-o "$outfile")
  fi

  if [[ "$strace_y" -eq 1 ]]; then
    cmd+=(-y)
  fi
  if [[ -n "$strace_s" ]]; then
    cmd+=(-s "$strace_s")
  fi

  if [[ ${#trace_args[@]} -gt 0 ]]; then
    cmd+=("${trace_args[@]}")
  fi

  cmd+=(-p "$pid")
  cmd+=("$@")

  echo ">>> target pid=$pid category=$category resolve_name=${comm_name}" >&2
  if [[ -r "/proc/$pid/cmdline" ]]; then
    echo ">>> cmdline: $(tr '\0' ' ' < "/proc/$pid/cmdline")" >&2
  fi
  echo ">>> exec: ${cmd[*]}" >&2

  if [[ "$dry_run" -eq 1 ]]; then
    printf '%q ' "${cmd[@]}"
    echo
    exit 0
  fi

  exec "${cmd[@]}"
}

main "$@"
