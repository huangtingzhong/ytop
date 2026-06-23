#!/usr/bin/env python
# -*- coding: utf-8 -*-
# File Name: trace_net.py
# Purpose: Per-thread TCP via eBPF plus ss peer/fd info
# Created: 20260612  by  huangtingzhong
"""
trace_net — per-thread TCP throughput (eBPF + ss)

Combines bpftrace (accurate TID per peer:port) with ss/iftop (FD, PEER, rates).
Output columns match iftop.py -t: one row per connection.

Requires: Linux, bpftrace, ss, sudo, Python 2.7+ or 3.x.

Usage: trace_net.py [-t] [-n top] [-p proc] [interval] [count]
"""

from __future__ import print_function, division

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
BAR_WIDTH = 16
W_TIME, W_PID, W_TID = 8, 8, 8
W_PROC, W_THREAD = 16, 16
W_FD, W_PEER, W_PORT, W_RATE = 4, 16, 6, 8

G_STOP = False
TS_LINE_RE = re.compile(r"^YTOP_NET_TS\s+(\S+)\s*$")
MAP_LINE_RE = re.compile(r"^@(tx|rx)\[(.+)\]:\s*(\d+)\s*$")


class SockStat(object):
    def __init__(self, pid, fd, peer_host, peer_port, rx_bytes=0, tx_bytes=0):
        self.pid = pid
        self.fd = fd
        self.peer_host = peer_host
        self.peer_port = peer_port
        self.rx_bytes = rx_bytes
        self.tx_bytes = tx_bytes


class AggRow(object):
    def __init__(self, pid, tid=0, fd=-1, proc_name="", thread_name="",
                 peer_host="", peer_port="", rx_bytes=0, tx_bytes=0,
                 rx_rate=0.0, tx_rate=0.0):
        self.pid = pid
        self.tid = tid
        self.fd = fd
        self.proc_name = proc_name
        self.thread_name = thread_name
        self.peer_host = peer_host
        self.peer_port = peer_port
        self.rx_bytes = rx_bytes
        self.tx_bytes = tx_bytes
        self.rx_rate = rx_rate
        self.tx_rate = tx_rate


class BpfConnSnapshot(object):
    __slots__ = ("ts", "by_peer")

    def __init__(self, ts=None, by_peer=None):
        self.ts = ts
        self.by_peer = by_peer or {}


class BpfNetReader(threading.Thread):
    def __init__(self, pid, interval_sec, bt_path):
        super(BpfNetReader, self).__init__()
        self.daemon = True
        self.pid = pid
        self.interval = interval_sec
        self.bt_path = bt_path
        self.lock = threading.Lock()
        self.snapshot = BpfConnSnapshot()
        self.proc = None
        self.error = None

    def get_snapshot(self):
        with self.lock:
            return self.snapshot

    def stop(self):
        if self.proc is not None and self.proc.poll() is None:
            try:
                subprocess.call(["sudo", "-n", "kill", str(self.proc.pid)])
            except (OSError, TypeError):
                pass

    def run(self):
        cmd = ["sudo", "-n", "bpftrace", "-q", "-B", "none", self.bt_path]
        try:
            self.proc = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except (IOError, OSError) as e:
            self.error = str(e)
            return

        cur_ts = None
        pending = {}

        while not G_STOP:
            line = self.proc.stdout.readline()
            if not line:
                break
            if PY3:
                line = line.decode("utf-8", "replace")
            line = line.rstrip("\n")
            if not line or line.startswith("Attaching"):
                continue

            ts_m = TS_LINE_RE.match(line)
            if ts_m:
                snap = build_conn_map(pending)
                snap.ts = ts_m.group(1)
                with self.lock:
                    self.snapshot = snap
                cur_ts = ts_m.group(1)
                pending = {}
                continue

            parse_conn_map_line(line, pending)

        err = self.proc.stderr.read()
        if PY3 and isinstance(err, bytes):
            err = err.decode("utf-8", "replace")
        if err.strip() and not self.error:
            self.error = err.strip()


def on_sig(_sig, _frame):
    global G_STOP
    G_STOP = True


def which(cmd):
    path = os.environ.get("PATH", "")
    for d in path.split(os.pathsep):
        p = os.path.join(d, cmd)
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def detect_os_family():
    """Return a short distro family tag for install hints."""
    try:
        with open("/etc/os-release", "rb") as f:
            raw = f.read()
        if PY3:
            text = raw.decode("utf-8", "replace")
        else:
            text = raw
    except (IOError, OSError):
        return "unknown"
    text_l = text.lower()
    if "oracle" in text_l or "ol8" in text_l or "ol9" in text_l or "el8" in text_l or "el9" in text_l:
        return "rhel"
    if "centos" in text_l or "rocky" in text_l or "almalinux" in text_l or "red hat" in text_l:
        return "rhel"
    if "openeuler" in text_l or "euleros" in text_l:
        return "openeuler"
    if "ubuntu" in text_l or "debian" in text_l:
        return "debian"
    if "suse" in text_l or "sles" in text_l:
        return "suse"
    return "unknown"


def bpftrace_install_hint():
    family = detect_os_family()
    hints = {
        "rhel": (
            "  Oracle Linux / RHEL / Rocky / AlmaLinux:\n"
            "    sudo dnf install -y bpftrace\n"
            "    # or: sudo yum install -y bpftrace\n"
            "  Enable BTF/debuginfo if probes fail:\n"
            "    sudo dnf debuginfo-install -y kernel-debuginfo-$(uname -r)"
        ),
        "openeuler": (
            "  openEuler:\n"
            "    sudo yum install -y bpftrace\n"
            "    # or: sudo dnf install -y bpftrace"
        ),
        "debian": (
            "  Ubuntu / Debian:\n"
            "    sudo apt-get update\n"
            "    sudo apt-get install -y bpftrace"
        ),
        "suse": (
            "  SUSE / openSUSE:\n"
            "    sudo zypper install -y bpftrace"
        ),
        "unknown": (
            "  Generic:\n"
            "    Install package 'bpftrace' from your OS repo, or build from:\n"
            "    https://github.com/bpftrace/bpftrace"
        ),
    }
    return hints.get(family, hints["unknown"])


def check_bpftrace():
    """Verify bpftrace is installed and runnable; exit with install hint if not."""
    bt_path = which("bpftrace")
    if not bt_path:
        print("ERROR: bpftrace is not installed or not in PATH.", file=sys.stderr)
        print("", file=sys.stderr)
        print("Install bpftrace, then re-run trace_net.py:", file=sys.stderr)
        print(bpftrace_install_hint(), file=sys.stderr)
        return False

    try:
        proc = subprocess.Popen(
            [bt_path, "--version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        out, err = proc.communicate()
        if proc.returncode != 0:
            raise subprocess.CalledProcessError(proc.returncode, bt_path)
    except (IOError, OSError, subprocess.CalledProcessError) as e:
        print("ERROR: bpftrace found at {0} but failed to run: {1}".format(
            bt_path, e), file=sys.stderr)
        print("", file=sys.stderr)
        print("Reinstall bpftrace:", file=sys.stderr)
        print(bpftrace_install_hint(), file=sys.stderr)
        return False
    return True


def check_ss():
    if which("ss"):
        return True
    print("ERROR: ss not found — install iproute2 / iproute package.",
          file=sys.stderr)
    return False


def usage(prog):
    msg = (
        "trace_net — per-thread TCP (eBPF TID + ss peer/fd)\n"
        "Usage: {prog} [-t] [-n top] [-p proc] [interval] [count]\n"
        "  -t       thread mode (default ON): one row per connection\n"
        "  -T       process mode: aggregate by peer only\n"
        "  -n N     show top N (default 15)\n"
        "  -p list  filter by process name or PID\n"
        "  interval sampling seconds (default 1)\n"
        "  count    sample count (default infinite)\n"
    ).format(prog=prog)
    print(msg, file=sys.stderr)


def parse_proc_filters(spec):
    pids = []
    names = []
    for token in spec.split(","):
        token = token.strip()
        if not token:
            continue
        if token.isdigit():
            pids.append(int(token))
        else:
            names.append(token)
    return pids, names


def read_comm(pid, tid=None):
    if tid is None:
        tid = pid
    paths = [
        "/proc/{0}/task/{1}/comm".format(pid, tid),
        "/proc/{0}/comm".format(pid),
    ]
    for path in paths:
        try:
            with open(path, "rb") as f:
                raw = f.read().strip()
            if PY3:
                return raw.decode("utf-8", "replace")
            return raw
        except (IOError, OSError):
            continue
    if tid == pid:
        return "pid-{0}".format(pid)
    return "thread-{0}".format(tid)


def resolve_target_pid(filter_pids, filter_names):
    if len(filter_pids) > 1:
        print("ERROR: eBPF mode supports one PID; got: {0}".format(
            ",".join(str(p) for p in filter_pids)), file=sys.stderr)
        return None
    if filter_pids:
        pid = filter_pids[0]
        if not os.path.isdir("/proc/{0}".format(pid)):
            print("ERROR: PID {0} does not exist".format(pid), file=sys.stderr)
            return None
        return pid

    if filter_names:
        for name in filter_names:
            try:
                out = subprocess.check_output(
                    ["pgrep", "-o", "-x", name], stderr=subprocess.STDOUT)
                if PY3:
                    out = out.decode("utf-8", "replace")
                return int(out.strip())
            except (subprocess.CalledProcessError, ValueError):
                continue
        print("ERROR: process not found: {0}".format(
            ",".join(filter_names)), file=sys.stderr)
        return None

    for cmd in (["pgrep", "-o", "-x", COMM_DEFAULT],
                ["pgrep", "-o", "-f", COMM_DEFAULT]):
        try:
            out = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
            if PY3:
                out = out.decode("utf-8", "replace")
            return int(out.strip())
        except (subprocess.CalledProcessError, ValueError):
            continue
    print("ERROR: process not found ({0})".format(COMM_DEFAULT), file=sys.stderr)
    return None


def parse_peer_field(token):
    if token.startswith("[") and "]" in token:
        br = token.index("]")
        host = token[1:br]
        if len(token) > br + 2 and token[br + 1] == ":":
            port = token[br + 2:]
        else:
            port = "-"
        return host, port
    if ":" in token:
        host, port = token.rsplit(":", 1)
        return host, port
    return token, "-"


def parse_ss_output(text):
    socks = []
    pid = 0
    fd = 0
    peer_host = ""
    peer_port = ""
    has_conn = False

    for raw in text.splitlines():
        if raw.startswith("\t") or (raw.startswith(" ") and has_conn):
            acked = 0
            received = 0
            m = re.search(r"bytes_acked:(\d+)", raw)
            if m:
                acked = int(m.group(1))
            else:
                m = re.search(r"bytes_sent:(\d+)", raw)
                if m:
                    acked = int(m.group(1))
            m = re.search(r"bytes_received:(\d+)", raw)
            if m:
                received = int(m.group(1))
            if has_conn and pid > 0:
                socks.append(SockStat(
                    pid, fd, peer_host, peer_port, received, acked))
            has_conn = False
            continue

        line = raw.strip()
        if not line:
            continue
        pid = 0
        fd = 0
        fields = line.split()
        if len(fields) >= 4:
            peer_host, peer_port = parse_peer_field(fields[3])
        m_pid = re.search(r"pid=(\d+)", line)
        m_fd = re.search(r"fd=(\d+)", line)
        if m_pid and m_fd:
            pid = int(m_pid.group(1))
            fd = int(m_fd.group(1))
            has_conn = True
        else:
            has_conn = False

    return socks


def run_ss():
    cmd = ["ss", "-H", "-tanpi", "state", "established"]
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out, _ = proc.communicate()
    except (IOError, OSError) as e:
        print("ERROR: failed to run ss: {0}".format(e), file=sys.stderr)
        return ""
    if proc.returncode != 0:
        return ""
    if PY3:
        return out.decode("utf-8", "replace")
    return out


def collect_ss_for_pid(pid):
    return [s for s in parse_ss_output(run_ss()) if s.pid == pid]


def peer_key(host, port):
    return host, str(port)


def parse_map_key_fields(body):
    parts = [p.strip() for p in body.split(",")]
    if len(parts) < 4:
        return None
    try:
        tid = int(parts[0])
    except ValueError:
        return None
    dport = parts[-1]
    daddr = parts[-2]
    comm = ", ".join(parts[1:-2]).strip()
    return tid, comm, daddr, dport


def parse_conn_map_line(line, pending):
    m = MAP_LINE_RE.match(line.strip())
    if not m:
        return False
    kind, body, nbytes_s = m.groups()
    parsed = parse_map_key_fields(body)
    if parsed is None:
        return False
    tid, comm, daddr, dport = parsed
    key = peer_key(daddr, dport)
    slot = pending.setdefault(key, {"tid": tid, "comm": comm, "rx": 0, "tx": 0})
    slot["tid"] = tid
    slot["comm"] = comm
    nbytes = int(nbytes_s)
    if kind == "rx":
        slot["rx"] += nbytes
    else:
        slot["tx"] += nbytes
    return True


def build_conn_map(pending):
    by_peer = {}
    for key, slot in pending.items():
        score = slot["rx"] + slot["tx"]
        prev = by_peer.get(key)
        if prev is None or score > prev.get("_score", 0):
            by_peer[key] = {
                "tid": slot["tid"],
                "comm": slot["comm"],
                "rx": slot["rx"],
                "tx": slot["tx"],
                "_score": score,
            }
    for val in by_peer.values():
        val.pop("_score", None)
    return BpfConnSnapshot(by_peer=by_peer)


def aggregate_ss(cur, prev, pid, proc_name, thread_mode):
    prev_map = {(s.pid, s.fd): s for s in prev}
    proc_agg = {}

    for s in cur:
        if s.pid != pid:
            continue
        pr = prev_map.get((s.pid, s.fd))
        prx = pr.rx_bytes if pr else 0
        ptx = pr.tx_bytes if pr else 0
        drx = s.rx_bytes - prx if s.rx_bytes >= prx else s.rx_bytes
        dtx = s.tx_bytes - ptx if s.tx_bytes >= ptx else s.tx_bytes

        if thread_mode:
            key = (s.pid, s.fd, s.peer_host, s.peer_port)
        else:
            key = (s.pid, s.peer_host, s.peer_port)

        if key not in proc_agg:
            row = AggRow(
                pid=s.pid,
                fd=s.fd if thread_mode else -1,
                proc_name=proc_name,
                peer_host=s.peer_host,
                peer_port=s.peer_port,
            )
            proc_agg[key] = row

        row = proc_agg[key]
        row.rx_bytes += drx
        row.tx_bytes += dtx

    return list(proc_agg.values())


def apply_bpf_threads(rows, bpf_snap):
    by_peer = bpf_snap.by_peer if bpf_snap else {}
    for row in rows:
        info = by_peer.get(peer_key(row.peer_host, row.peer_port))
        if info:
            row.tid = info["tid"]
            row.thread_name = info["comm"] or read_comm(row.pid, info["tid"])
        else:
            row.tid = 0
            row.thread_name = "?"


def calc_rates(rows, interval):
    for r in rows:
        r.rx_rate = r.rx_bytes / interval / 1024.0
        r.tx_rate = r.tx_bytes / interval / 1024.0


def bar(v, vmax):
    if vmax < 0.001:
        vmax = 0.001
    n = int(v / vmax * BAR_WIDTH)
    if n > BAR_WIDTH:
        n = BAR_WIDTH
    return "#" * n + "." * (BAR_WIDTH - n)


def trunc(s, width):
    if len(s) <= width:
        return s
    return s[:width]


def list_max(rows, attr, default):
    if not rows:
        return default
    return max(getattr(r, attr) for r in rows)


def print_table(rows, top, thread_mode, time_hms):
    max_tx = list_max(rows, "tx_rate", 0.001)
    max_rx = list_max(rows, "rx_rate", 0.001)
    rows.sort(key=lambda r: r.tx_rate, reverse=True)
    if top < len(rows):
        rows = rows[:top]
    if max_tx < 0.001:
        max_tx = 0.001
    if max_rx < 0.001:
        max_rx = 0.001

    if thread_mode:
        sep_w = (
            W_TIME + W_PID + W_TID + W_PROC + W_THREAD + W_FD + W_PEER
            + W_PORT + W_RATE + W_RATE + BAR_WIDTH + BAR_WIDTH + 12
        )
    else:
        sep_w = (
            W_TIME + W_PID + W_PROC + W_PEER + W_PORT + W_RATE + W_RATE
            + BAR_WIDTH + BAR_WIDTH + 8
        )

    print()
    if thread_mode:
        print(
            "{time:<{wt}} {pid:<{wp}} {tid:<{wtid}} "
            "{pn:<{wproc}} {th:<{wth}} {fd:>{wfd}} "
            "{peer:<{wpeer}} {port:<{wport}} "
            "{rxlbl:>{wr}} {txlbl:>{wr}} "
            "{brxlbl:<{bw}} {btxlbl:<{bw}}".format(
                time="TIME", wt=W_TIME,
                pid="PID", wp=W_PID,
                tid="TID", wtid=W_TID,
                pn="PROC_NAME", wproc=W_PROC,
                th="THREAD", wth=W_THREAD,
                fd="FD", wfd=W_FD,
                peer="PEER_ADDR", wpeer=W_PEER,
                port="PORT", wport=W_PORT,
                rxlbl="RX_KB/s", txlbl="TX_KB/s", wr=W_RATE,
                brxlbl="RX_bar", btxlbl="TX_bar", bw=BAR_WIDTH,
            )
        )
    else:
        print(
            "{time:<{wt}} {pid:<{wp}} "
            "{pn:<{wproc}} {peer:<{wpeer}} {port:<{wport}} "
            "{rxlbl:>{wr}} {txlbl:>{wr}} "
            "{brxlbl:<{bw}} {btxlbl:<{bw}}".format(
                time="TIME", wt=W_TIME,
                pid="PID", wp=W_PID,
                pn="PROC_NAME", wproc=W_PROC,
                peer="PEER_ADDR", wpeer=W_PEER,
                port="PORT", wport=W_PORT,
                rxlbl="RX_KB/s", txlbl="TX_KB/s", wr=W_RATE,
                brxlbl="RX_bar", btxlbl="TX_bar", bw=BAR_WIDTH,
            )
        )
    print("-" * sep_w)

    for r in rows:
        brx = bar(r.rx_rate, max_rx)
        btx = bar(r.tx_rate, max_tx)
        if thread_mode:
            print(
                "{t:<{wt}} {pid:<{wp}} {tid:<{wtid}} "
                "{pn:<{wproc}} {th:<{wth}} {fd:>{wfd}} "
                "{peer:<{wpeer}} {port:<{wport}} "
                "{rx:>{wr}.2f} {tx:>{wr}.2f} {brx} {btx}".format(
                    t=time_hms, wt=W_TIME,
                    pid=r.pid, wp=W_PID,
                    tid=r.tid, wtid=W_TID,
                    pn=trunc(r.proc_name, W_PROC), wproc=W_PROC,
                    th=trunc(r.thread_name, W_THREAD), wth=W_THREAD,
                    fd=r.fd, wfd=W_FD,
                    peer=trunc(r.peer_host, W_PEER), wpeer=W_PEER,
                    port=trunc(r.peer_port, W_PORT), wport=W_PORT,
                    rx=r.rx_rate, tx=r.tx_rate, wr=W_RATE,
                    brx=brx, btx=btx,
                )
            )
        else:
            print(
                "{t:<{wt}} {pid:<{wp}} "
                "{pn:<{wproc}} {peer:<{wpeer}} {port:<{wport}} "
                "{rx:>{wr}.2f} {tx:>{wr}.2f} {brx} {btx}".format(
                    t=time_hms, wt=W_TIME,
                    pid=r.pid, wp=W_PID,
                    pn=trunc(r.proc_name, W_PROC), wproc=W_PROC,
                    peer=trunc(r.peer_host, W_PEER), wpeer=W_PEER,
                    port=trunc(r.peer_port, W_PORT), wport=W_PORT,
                    rx=r.rx_rate, tx=r.tx_rate, wr=W_RATE,
                    brx=brx, btx=btx,
                )
            )


def build_bpftrace_script(pid, interval_sec):
    iv = max(1, int(interval_sec))
    return """
kprobe:tcp_sendmsg /pid == {pid}/
{{
  $sk = (struct sock *)arg0;
  $da = ntop(2, $sk->__sk_common.skc_daddr);
  $dp = (($sk->__sk_common.skc_dport & 0xff) << 8)
       | (($sk->__sk_common.skc_dport >> 8) & 0xff);
  @tx[tid, comm, $da, $dp] = sum(arg2);
}}

kprobe:tcp_cleanup_rbuf /pid == {pid}/
{{
  $sk = (struct sock *)arg0;
  $da = ntop(2, $sk->__sk_common.skc_daddr);
  $dp = (($sk->__sk_common.skc_dport & 0xff) << 8)
       | (($sk->__sk_common.skc_dport >> 8) & 0xff);
  @rx[tid, comm, $da, $dp] = sum(arg1);
}}

interval:s:{iv}
{{
  printf("YTOP_NET_TS %s\\n", strftime("%H:%M:%S", nsecs));
  print(@tx);
  print(@rx);
  clear(@tx);
  clear(@rx);
}}
""".format(pid=pid, iv=iv)


def wait_bpf_ready(reader, timeout_sec):
    deadline = time.time() + timeout_sec
    while time.time() < deadline and not G_STOP:
        snap = reader.get_snapshot()
        if snap.by_peer:
            return True
        time.sleep(0.2)
    return False


def run_monitor_loop(pid, interval, count, thread_mode, top, proc_name):
    global G_STOP

    prev_ss = collect_ss_for_pid(pid)
    if not prev_ss:
        print("ERROR: no established TCP sockets for PID {0}".format(pid),
              file=sys.stderr)
        return 1

    fd, bt_path = tempfile.mkstemp(prefix="trace_net_", suffix=".bt")
    os.close(fd)
    with open(bt_path, "wb") as f:
        content = build_bpftrace_script(pid, interval)
        if PY3:
            f.write(content.encode("utf-8"))
        else:
            f.write(content)

    reader = BpfNetReader(pid, interval, bt_path)
    reader.start()
    time.sleep(0.3)
    if reader.error:
        print("ERROR: bpftrace: {0}".format(reader.error), file=sys.stderr)
        os.unlink(bt_path)
        return 1

    if not wait_bpf_ready(reader, interval + 5):
        print("WARN: bpftrace produced no peer map yet; TID may show ?",
              file=sys.stderr)

    time.sleep(interval)
    iteration = 0
    exit_code = 0

    try:
        while not G_STOP:
            cur_ss = collect_ss_for_pid(pid)
            if not cur_ss:
                print("WARN: ss sample empty", file=sys.stderr)
                break

            rows = aggregate_ss(cur_ss, prev_ss, pid, proc_name, thread_mode)
            if thread_mode:
                apply_bpf_threads(rows, reader.get_snapshot())

            calc_rates(rows, interval)
            time_hms = datetime.now().strftime("%H:%M:%S")
            print_table(rows, top, thread_mode, time_hms)

            prev_ss = cur_ss
            iteration += 1
            if count >= 0 and iteration >= count:
                break

            time.sleep(interval)
    finally:
        reader.stop()
        try:
            reader.join(timeout=5)
        except Exception:
            pass
        os.unlink(bt_path)
        if reader.error and iteration == 0:
            print("ERROR: bpftrace: {0}".format(reader.error), file=sys.stderr)
            exit_code = 1

    return exit_code


def parse_args(argv):
    thread_mode = True
    top = 15
    interval = 1.0
    count = -1
    filter_pids = []
    filter_names = []
    i = 1
    while i < len(argv) and argv[i].startswith("-"):
        if argv[i] == "-t":
            thread_mode = True
        elif argv[i] == "-T":
            thread_mode = False
        elif argv[i] == "-n" and i + 1 < len(argv):
            top = int(argv[i + 1])
            i += 1
        elif argv[i] == "-p" and i + 1 < len(argv):
            filter_pids, filter_names = parse_proc_filters(argv[i + 1])
            i += 1
        elif argv[i] in ("-h", "--help"):
            usage(argv[0])
            sys.exit(0)
        else:
            print("Unknown option: {0}".format(argv[i]), file=sys.stderr)
            usage(argv[0])
            sys.exit(1)
        i += 1
    if i < len(argv):
        interval = float(argv[i])
        i += 1
    if i < len(argv):
        count = int(argv[i])
    if interval <= 0:
        interval = 1.0
    return thread_mode, top, interval, count, filter_pids, filter_names


def main():
    global G_STOP
    if not sys.platform.startswith("linux"):
        print("ERROR: trace_net.py requires Linux", file=sys.stderr)
        return 1
    if not check_bpftrace():
        return 1
    if not check_ss():
        return 1
    if os.geteuid() != 0:
        if which("sudo") is None:
            print("ERROR: run as root or install sudo", file=sys.stderr)
            return 1
        try:
            subprocess.check_call(["sudo", "-n", "true"])
        except subprocess.CalledProcessError:
            print("ERROR: passwordless sudo required for bpftrace", file=sys.stderr)
            return 1

    thread_mode, top, interval, count, filter_pids, filter_names = parse_args(
        sys.argv)
    signal.signal(signal.SIGINT, on_sig)
    signal.signal(signal.SIGTERM, on_sig)

    pid = resolve_target_pid(filter_pids, filter_names)
    if pid is None:
        return 1
    proc_name = read_comm(pid)

    return run_monitor_loop(
        pid, interval, count, thread_mode, top, proc_name)


if __name__ == "__main__":
    sys.exit(main())
