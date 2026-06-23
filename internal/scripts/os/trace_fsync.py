#!/usr/bin/env python
# -*- coding: utf-8 -*-
# File Name: trace_fsync.py
# Purpose: Trace fsync and fdatasync syscall latency via bpftrace
# Created: 20260616  by  huangtingzhong
"""
trace_fsync — fsync / fdatasync syscall latency (eBPF / bpftrace)

Complements trace_io.sh (pread/pwrite) and trace_blk.py (block layer).
Primary use: log file sync (CKPT/DBWR/RD_ARCH), redo/datafile flush latency.

Requires: Linux, bpftrace, sudo (passwordless for ytop), Python 2.7+ or 3.x.

Usage:
  trace_fsync.py -n CKPT -m 1000           # default 10s, yasdb auto-detect
  trace_fsync.py -p <pid> -m 500 -d 30
  trace_fsync.py -n CKPT -P 1              # append FD -> path
  trace_fsync.py -d 0                        # until Ctrl+C
"""

from __future__ import print_function, division

import argparse
import os
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime

PY3 = sys.version_info[0] >= 3

COMM_DEFAULT = "yasdb"
FSYNC_LINE_RE = re.compile(r"^FSYNC\t")

BPFTRACE_TEMPLATE = r"""
BEGIN {
  if (__SHOW_BANNER__) {
    printf("BPFTRACE_BEGIN\n");
  }
}

// op: 0 fsync, 1 fdatasync
tracepoint:syscalls:sys_enter_fsync
  / pid == __PID__ && (__TID__ == 0 || tid == __TID__) __TIDLIST_PRED__ / {
  @ts[tid, 0] = nsecs;
  @fd[tid, 0] = args->fd;
}

tracepoint:syscalls:sys_exit_fsync / @ts[tid, 0] / {
  $us = (nsecs - @ts[tid, 0]) / 1000;
  if ($us >= __MIN_US__) {
    printf("FSYNC\t%s.%06d\t%d\t%d\t%s\tfsync\t%d\t%d\t%d\n",
      strftime("%H:%M:%S", nsecs), (nsecs % 1000000000) / 1000,
      pid, tid, comm, @fd[tid, 0], args->ret, $us);
  }
  delete(@ts[tid, 0]);
  delete(@fd[tid, 0]);
}

tracepoint:syscalls:sys_enter_fdatasync
  / pid == __PID__ && (__TID__ == 0 || tid == __TID__) __TIDLIST_PRED__ / {
  @ts[tid, 1] = nsecs;
  @fd[tid, 1] = args->fd;
}

tracepoint:syscalls:sys_exit_fdatasync / @ts[tid, 1] / {
  $us = (nsecs - @ts[tid, 1]) / 1000;
  if ($us >= __MIN_US__) {
    printf("FSYNC\t%s.%06d\t%d\t%d\t%s\tfdatasync\t%d\t%d\t%d\n",
      strftime("%H:%M:%S", nsecs), (nsecs % 1000000000) / 1000,
      pid, tid, comm, @fd[tid, 1], args->ret, $us);
  }
  delete(@ts[tid, 1]);
  delete(@fd[tid, 1]);
}

END {
  clear(@ts);
  clear(@fd);
}
"""


def which(cmd):
    path = os.environ.get("PATH", "")
    for d in path.split(os.pathsep):
        p = os.path.join(d, cmd)
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def read_os_release():
    data = {}
    for path in ("/etc/os-release", "/usr/lib/os-release"):
        try:
            with open(path, "rb") as f:
                raw = f.read()
            text = raw.decode("utf-8", "replace") if PY3 else raw
            break
        except (IOError, OSError):
            continue
    else:
        return data
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        data[k.strip()] = v.strip().strip('"').strip("'")
    return data


def detect_os_family():
    rel = read_os_release()
    text = " ".join(rel.values()).lower()
    id_ = rel.get("ID", "").lower()
    id_like = rel.get("ID_LIKE", "").lower()
    domestic_rpm = (
        "kylin", "neokylin", "openeuler", "euleros", "anolis", "alinux",
        "tencentos", "ctyunos", "fusionos", "nfs", "nfschina", "uos",
        "uniontech", "deepin", "linx", "isoft", "redflag",
    )
    for tag in domestic_rpm:
        if tag in id_ or tag in text:
            if id_ in ("uos", "uniontech", "deepin") or "debian" in id_like:
                return "debian"
            return "domestic_rpm"
    if id_ in ("rhel", "centos", "rocky", "almalinux", "ol", "oraclelinux"):
        return "rhel"
    if "rhel" in id_like or "fedora" in id_like or "centos" in id_like:
        return "rhel"
    if id_ in ("ubuntu", "debian") or "debian" in id_like:
        return "debian"
    if "suse" in id_ or "sles" in id_ or "opensuse" in id_:
        return "suse"
    return "unknown"


def bpftrace_install_hint():
    family = detect_os_family()
    hints = {
        "rhel": "  sudo dnf install -y bpftrace  # or yum",
        "domestic_rpm": "  sudo yum install -y bpftrace  # openEuler/Kylin/Anolis 等",
        "debian": "  sudo apt-get install -y bpftrace",
        "suse": "  sudo zypper install -y bpftrace",
        "unknown": "  Install bpftrace from OS repo or https://github.com/bpftrace/bpftrace",
    }
    return hints.get(family, hints["unknown"])


def run_cmd(cmd, timeout=None):
    try:
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out, err = proc.communicate(timeout=timeout)
        if PY3:
            out = out.decode("utf-8", "replace")
            err = err.decode("utf-8", "replace")
        return proc.returncode, out, err
    except subprocess.TimeoutExpired:
        proc.kill()
        out, err = proc.communicate()
        if PY3:
            out = out.decode("utf-8", "replace") if out else ""
            err = err.decode("utf-8", "replace") if err else ""
        return -9, out, err
    except (IOError, OSError) as e:
        return 1, "", str(e)


def check_bpftrace():
    bt = which("bpftrace")
    if not bt:
        print("ERROR: bpftrace not installed.", file=sys.stderr)
        print(bpftrace_install_hint(), file=sys.stderr)
        return False
    rc, out, err = run_cmd([bt, "--version"], timeout=10)
    if rc != 0:
        print("ERROR: bpftrace failed: {0}".format(err or out), file=sys.stderr)
        return False
    return True


def check_fsync_tracepoints():
    bt = which("bpftrace")
    rc, out, err = run_cmd(
        ["sudo", "-n", bt, "-l", "tracepoint:syscalls:sys_enter_fsync"],
        timeout=15)
    combined = (out or "") + (err or "")
    if rc != 0 or "sys_enter_fsync" not in combined:
        print("ERROR: tracepoint syscalls:sys_enter_fsync not available.",
              file=sys.stderr)
        return False
    return True


def check_sudo():
    if os.geteuid() == 0:
        return True
    if which("sudo") is None:
        print("ERROR: run as root or install sudo.", file=sys.stderr)
        return False
    rc, _, _ = run_cmd(["sudo", "-n", "true"], timeout=5)
    if rc != 0:
        print("ERROR: passwordless sudo required for bpftrace.", file=sys.stderr)
        return False
    return True


def resolve_pid(pid, comm, comm_explicit):
    if pid:
        rc, _, _ = run_cmd(["ps", "-p", str(pid)], timeout=5)
        if rc != 0:
            print("ERROR: PID {0} does not exist.".format(pid), file=sys.stderr)
            return None
        return pid
    rc, out, _ = run_cmd(["pgrep", "-o", "-x", comm], timeout=5)
    if rc == 0 and out.strip().isdigit():
        return int(out.strip())
    if not comm_explicit:
        rc, out, _ = run_cmd(["pgrep", "-o", "-f", comm], timeout=5)
        if rc == 0 and out.strip().isdigit():
            return int(out.strip())
    print("ERROR: process not found (comm={0}).".format(comm), file=sys.stderr)
    return None


def resolve_thread_filter(pid, tname, tid):
    """Return (tid, tidlist_pred) for bpftrace placeholders."""
    tidlist_pred = ""
    if not tname:
        return tid, tidlist_pred
    rc, out, _ = run_cmd(["ps", "-T", "-p", str(pid), "-o", "tid=,comm="], timeout=10)
    if rc != 0:
        print("ERROR: ps -T failed for PID {0}.".format(pid), file=sys.stderr)
        return None
    tids = []
    for line in out.splitlines():
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        if parts[1] == tname:
            tids.append(parts[0])
    if not tids:
        print("ERROR: thread name not found: PID={0} comm={1}".format(pid, tname),
              file=sys.stderr)
        rc2, out2, _ = run_cmd(["ps", "-T", "-p", str(pid), "-o", "tid,comm"], timeout=10)
        if rc2 == 0:
            print("Threads (sample):", file=sys.stderr)
            for ln in out2.splitlines()[:50]:
                print("  " + ln, file=sys.stderr)
        return None
    if tid == 0 and len(tids) == 1:
        return int(tids[0]), ""
    if tid == 0 and len(tids) > 1:
        parts = ["tid=={0}".format(t) for t in tids]
        return 0, "&& (" + " || ".join(parts) + ")"
    return tid, tidlist_pred


def build_bpftrace_script(pid, tid, tidlist_pred, min_us, show_banner):
    script = BPFTRACE_TEMPLATE
    script = script.replace("__PID__", str(int(pid)))
    script = script.replace("__TID__", str(int(tid)))
    script = script.replace("__TIDLIST_PRED__", tidlist_pred)
    script = script.replace("__MIN_US__", str(int(min_us)))
    script = script.replace("__SHOW_BANNER__", "1" if show_banner else "0")
    return script


def human_lat(us):
    ms = us / 1000.0
    if ms >= 1000:
        return "{0:.2f}s".format(ms / 1000)
    if ms >= 100:
        return "{0:.0f}ms".format(ms)
    if ms >= 10:
        return "{0:.1f}ms".format(ms)
    if ms >= 1:
        return "{0:.2f}ms".format(ms)
    return "{0}us".format(int(us))


def lat_bucket(us):
    ms = us / 1000.0
    if ms < 1:
        return "<1ms"
    if ms < 5:
        return "1-5ms"
    if ms < 10:
        return "5-10ms"
    if ms < 50:
        return "10-50ms"
    return ">=50ms"


class FdPathMapper(object):
    """Background refresh of /proc/<pid>/fd -> path."""

    def __init__(self, pid, interval=2):
        self.pid = pid
        self.interval = interval
        self.lock = threading.Lock()
        self.fdmap = {}
        self._stop = False
        self._thread = threading.Thread(target=self._loop)
        self._thread.daemon = True

    def start(self):
        self._refresh()
        self._thread.start()

    def stop(self):
        self._stop = True

    def _loop(self):
        while not self._stop:
            time.sleep(self.interval)
            self._refresh()

    def _refresh(self):
        newmap = {}
        base = "/proc/{0}/fd".format(self.pid)
        if not os.path.isdir(base):
            return
        try:
            names = os.listdir(base)
        except OSError:
            return
        for name in names:
            if not name.isdigit():
                continue
            path = os.path.join(base, name)
            try:
                target = os.readlink(path)
            except OSError:
                target = "?"
            newmap[name] = target
        with self.lock:
            self.fdmap = newmap

    def lookup(self, fd):
        with self.lock:
            return self.fdmap.get(str(fd), "?")


class FsyncFormatter(object):
    def __init__(self, args, fd_mapper):
        self.args = args
        self.fd_mapper = fd_mapper
        self.printed = 0
        self.total = 0
        self.by_op = {}
        self.lat_buckets = {}
        self.slow_us = 0
        self.slow_row = None
        self._header = False

    def print_header(self):
        if self._header:
            return
        self._header = True
        print("=== fsync / fdatasync (syscall latency) ===")
        print("SNAP {0}".format(datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
        tinfo = ""
        if self.args.tname:
            tinfo = "  thread={0}".format(self.args.tname)
        dur = self.args.duration if self.args.duration > 0 else "until Ctrl+C"
        comm_ps = self.args.comm
        try:
            with open("/proc/{0}/comm".format(self.args.pid), "r") as f:
                comm_ps = f.read().strip()
        except (IOError, OSError):
            pass
        print("Target: PID={0}  comm={1}{2}  min>={3}us  duration={4}s".format(
            self.args.pid, comm_ps, tinfo, self.args.min_us, dur))
        print("(block layer: trace_blk.py · pread/pwrite: trace_io.sh)")
        print("")
        hdr = "{0}  {1} {2} {3}  {4} {5} {6}  {7}".format(
            "TIME".ljust(18), "COMM".ljust(16), "PID".rjust(6), "TID".rjust(6),
            "OP".ljust(10), "FD".rjust(4), "RET".rjust(6), "LATENCY".rjust(8))
        if self.args.show_path:
            hdr += "  PATH"
        print(hdr)
        print("-" * (90 if self.args.show_path else 74))

    def handle_line(self, line):
        line = line.rstrip("\n")
        if not FSYNC_LINE_RE.match(line):
            return
        parts = line.split("\t")
        if len(parts) < 9:
            return
        self.total += 1
        t = parts[1]
        pid = int(parts[2])
        tid = int(parts[3])
        comm = parts[4]
        op = parts[5]
        fd = int(parts[6])
        ret = int(parts[7])
        us = int(parts[8])

        self.by_op[op] = self.by_op.get(op, 0) + 1
        b = lat_bucket(us)
        self.lat_buckets[b] = self.lat_buckets.get(b, 0) + 1
        if us >= self.slow_us:
            self.slow_us = us
            self.slow_row = (t, comm, pid, tid, op, fd, ret, us)

        if self.args.max_lines == 0 or self.printed < self.args.max_lines:
            lat_s = human_lat(us)
            path_s = ""
            if self.args.show_path and self.fd_mapper:
                path_s = "  " + self.fd_mapper.lookup(fd)
            err_s = ""
            if ret < 0:
                err_s = " err"
            print("{0}  {1} {2} {3}  {4} {5} {6}  {7}{8}{9}".format(
                t.ljust(18), comm.ljust(16), str(pid).rjust(6), str(tid).rjust(6),
                op.ljust(10), str(fd).rjust(4), str(ret).rjust(6),
                lat_s.rjust(8), err_s, path_s))
            self.printed += 1

    def print_summary(self):
        if self.total == 0:
            print("\n(no fsync/fdatasync events; try -n CKPT, lower -m, or longer -d)")
            return
        if self.args.max_lines > 0 and self.total > self.printed:
            print("\n... {0} more events omitted (raise -L)".format(
                self.total - self.printed))
        print("\n--- Summary ({0} events) ---".format(self.total))
        print(" Latency  :", end="")
        for k in ("<1ms", "1-5ms", "5-10ms", "10-50ms", ">=50ms"):
            if k in self.lat_buckets:
                print("  {0}={1}".format(k, self.lat_buckets[k]), end="")
        print("")
        for op in sorted(self.by_op.keys()):
            print(" {0:10s}: {1}".format(op, self.by_op[op]))
        if self.slow_row:
            t, comm, pid, tid, op, fd, ret, us = self.slow_row
            print(" Slowest  : {0}  {1}  tid={2}  {3}  fd={4}  ret={5}".format(
                human_lat(us), comm, tid, op, fd, ret))
        print("\nTip: high fsync here + low trace_blk -> metadata/small sync writes; "
              "both high -> disk/redo path slow")


def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description="fsync/fdatasync syscall latency via bpftrace (log file sync)",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("-p", "--pid", type=int, default=0, help="Target PID")
    p.add_argument("-c", "--comm", default=COMM_DEFAULT,
                   help="Process comm when -p omitted (pgrep oldest)")
    p.add_argument("-t", "--tid", type=int, default=0,
                   help="Thread TID (0=all threads of PID)")
    p.add_argument("-n", "--tname", default="",
                   help="Thread comm filter, e.g. CKPT DBWR RD_ARCH")
    p.add_argument("-m", "--min-us", type=int, default=0,
                   help="Min latency microseconds")
    p.add_argument("-d", "--duration", type=int, default=10,
                   help="Duration seconds (0=until Ctrl+C)")
    p.add_argument("-L", "--max-lines", type=int, default=500,
                   help="Max detail lines (0=unlimited)")
    p.add_argument("-P", "--show-path", action="store_true",
                   help="Append FD target via /proc/<pid>/fd")
    p.add_argument("-B", "--buffer", choices=("none", "full"), default="none",
                   help="bpftrace output buffer mode")
    p.add_argument("-v", "--verbose", action="store_true",
                   help="Show bpftrace script path / attach lines")
    args = p.parse_args(argv)
    if argv is None:
        argv = sys.argv[1:]
    args.comm_explicit = any(
        a == "-c" or (a.startswith("-c") and len(a) > 2) or a == "--comm"
        for a in argv)
    return args


def stop_process(proc):
    if proc.poll() is not None:
        return
    try:
        proc.terminate()
    except OSError:
        pass
    t0 = time.time()
    while proc.poll() is None and time.time() - t0 < 3:
        time.sleep(0.1)
    if proc.poll() is None:
        try:
            proc.kill()
        except OSError:
            pass


def run_trace(args, bt_path):
    script = build_bpftrace_script(
        args.pid, args.tid, args.tidlist_pred,
        args.min_us, args.verbose)
    with open(bt_path, "w") as f:
        f.write(script)

    bpftrace = which("bpftrace")
    inner = [bpftrace, "-B", args.buffer]
    if not args.verbose:
        inner.append("-q")
    inner.append(bt_path)
    if args.duration > 0:
        to_cmd = which("timeout")
        if to_cmd is None:
            print("ERROR: 'timeout' not found (install coreutils).", file=sys.stderr)
            return 1
        cmd = ["sudo", "-n", to_cmd, str(args.duration)] + inner
    else:
        cmd = ["sudo", "-n"] + inner

    if args.verbose:
        print("[INFO] bpftrace script: {0}".format(bt_path), file=sys.stderr)
        print("[INFO] cmd: {0}".format(" ".join(cmd)), file=sys.stderr)

    fd_mapper = None
    if args.show_path:
        fd_mapper = FdPathMapper(args.pid)
        fd_mapper.start()

    formatter = FsyncFormatter(args, fd_mapper)
    formatter.print_header()

    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=1)

    def on_sig(_sig, _frame):
        stop_process(proc)

    signal.signal(signal.SIGINT, on_sig)
    signal.signal(signal.SIGTERM, on_sig)

    err_lines = []

    for raw in proc.stdout:
        if PY3:
            line = raw.decode("utf-8", "replace")
        else:
            line = raw
        if line.startswith("Attaching") or line.startswith("BPFTRACE_BEGIN"):
            if args.verbose:
                print(line.rstrip(), file=sys.stderr)
            continue
        if "ERROR:" in line:
            err_lines.append(line.rstrip())
            continue
        formatter.handle_line(line)

    proc.wait()
    if fd_mapper:
        fd_mapper.stop()
    formatter.print_summary()

    if err_lines and formatter.total == 0:
        print("\nbpftrace errors:", file=sys.stderr)
        for el in err_lines:
            print("  " + el, file=sys.stderr)
        return 1
    return 0


def main(argv=None):
    if not sys.platform.startswith("linux"):
        print("ERROR: trace_fsync.py requires Linux.", file=sys.stderr)
        return 1
    if not check_bpftrace():
        return 1
    if not check_sudo():
        return 1
    if not check_fsync_tracepoints():
        return 1

    args = parse_args(argv)
    pid = resolve_pid(args.pid, args.comm, args.comm_explicit)
    if pid is None:
        return 1
    args.pid = pid

    resolved = resolve_thread_filter(pid, args.tname, args.tid)
    if resolved is None:
        return 1
    args.tid, args.tidlist_pred = resolved

    fd, bt_path = tempfile.mkstemp(prefix="trace_fsync_", suffix=".bt")
    os.close(fd)
    try:
        return run_trace(args, bt_path)
    finally:
        try:
            os.unlink(bt_path)
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
