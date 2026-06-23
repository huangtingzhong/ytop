#!/usr/bin/env python
# -*- coding: utf-8 -*-
# File Name: iftop.py
# Purpose: Host-pair TCP throughput via ss like Linux iftop
# Created: 20260517  by  huangtingzhong
"""
iftop — TCP throughput by connection / peer (ss-based)

Like Linux iftop: show all established TCP flows (not only one process).
Uses ss -tan (all sockets); process name shown when ss -p can resolve it.

Usage: iftop [-n top] [-p proc] [interval] [count]
Requires: ss (iproute2), /proc — Linux only; Python 2.6+ or Python 3.
"""

from __future__ import print_function

import os
import re
import signal
import subprocess
import sys
import time
from datetime import datetime

PY3 = sys.version_info[0] >= 3

BAR_WIDTH = 16
W_TIME, W_PID = 8, 8
W_PROC = 16
W_PEER, W_PORT, W_RATE = 16, 6, 8

G_STOP = False
USERS_RE = re.compile(r'users:\(\("([^"]+)",pid=(\d+),fd=(\d+)\)\)')


class SockStat(object):
    def __init__(self, local_host, local_port, peer_host, peer_port,
                 pid=0, fd=-1, proc_name="", rx_bytes=0, tx_bytes=0):
        self.local_host = local_host
        self.local_port = local_port
        self.peer_host = peer_host
        self.peer_port = peer_port
        self.pid = pid
        self.fd = fd
        self.proc_name = proc_name
        self.rx_bytes = rx_bytes
        self.tx_bytes = tx_bytes

    @property
    def conn_key(self):
        return (self.local_host, self.local_port, self.peer_host, self.peer_port)


class AggRow(object):
    def __init__(self, pid=0, proc_name="", peer_host="", peer_port="",
                 rx_bytes=0, tx_bytes=0, rx_rate=0.0, tx_rate=0.0):
        self.pid = pid
        self.proc_name = proc_name
        self.peer_host = peer_host
        self.peer_port = peer_port
        self.rx_bytes = rx_bytes
        self.tx_bytes = tx_bytes
        self.rx_rate = rx_rate
        self.tx_rate = tx_rate


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


def usage(prog):
    msg = (
        "iftop — TCP throughput by peer (all connections, like Linux iftop)\n"
        "Usage: {prog} [-n top] [-p proc] [interval] [count]\n"
        "  -n N     show top N rows (default 15)\n"
        "  -p list  optional filter by process name or PID only\n"
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


def match_proc_filter(pid, name, filter_pids, filter_names):
    if not filter_pids and not filter_names:
        return True
    if pid <= 0:
        return False
    if pid in filter_pids:
        return True
    if name in filter_names:
        return True
    return False


def read_comm(pid):
    try:
        with open("/proc/{0}/comm".format(pid), "rb") as f:
            raw = f.read().strip()
        if PY3:
            return raw.decode("utf-8", "replace")
        return raw
    except (IOError, OSError):
        return "pid-{0}".format(pid)


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


def parse_users_field(line):
    m = USERS_RE.search(line)
    if not m:
        return "", 0, -1
    return m.group(1), int(m.group(2)), int(m.group(3))


def parse_ss_output(text):
    socks = []
    pending = None

    for raw in text.splitlines():
        if raw.startswith("\t") or (raw.startswith(" ") and pending is not None):
            if pending is None:
                continue
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
            pending.rx_bytes = received
            pending.tx_bytes = acked
            socks.append(pending)
            pending = None
            continue

        line = raw.strip()
        if not line:
            continue
        fields = line.split()
        if len(fields) < 4:
            continue
        local_host, local_port = parse_peer_field(fields[2])
        peer_host, peer_port = parse_peer_field(fields[3])
        comm, pid, fd = parse_users_field(line)
        proc_name = comm if comm else (read_comm(pid) if pid > 0 else "-")
        pending = SockStat(
            local_host, local_port, peer_host, peer_port,
            pid=pid, fd=fd, proc_name=proc_name,
        )

    return socks


def run_ss():
    # -tanpi: byte counters on following line; -p adds pid when visible to user
    cmd = ["ss", "-H", "-tanpi", "state", "established"]
    try:
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out, _ = proc.communicate()
    except (IOError, OSError) as e:
        print("ERROR: failed to run ss: {0}".format(e), file=sys.stderr)
        return ""
    if proc.returncode != 0:
        return ""
    if PY3:
        return out.decode("utf-8", "replace")
    return out


def collect_via_ss():
    return parse_ss_output(run_ss())


def filter_socks(socks, filter_pids, filter_names):
    if not filter_pids and not filter_names:
        return socks
    out = []
    for s in socks:
        if match_proc_filter(s.pid, s.proc_name, filter_pids, filter_names):
            out.append(s)
    return out


def aggregate(cur, prev, filter_pids, filter_names):
    prev_map = {s.conn_key: s for s in prev}
    proc_agg = {}

    for s in cur:
        if not match_proc_filter(s.pid, s.proc_name, filter_pids, filter_names):
            continue
        pr = prev_map.get(s.conn_key)
        prx = pr.rx_bytes if pr else 0
        ptx = pr.tx_bytes if pr else 0
        drx = s.rx_bytes - prx if s.rx_bytes >= prx else s.rx_bytes
        dtx = s.tx_bytes - ptx if s.tx_bytes >= ptx else s.tx_bytes

        key = s.conn_key
        if key not in proc_agg:
            proc_agg[key] = AggRow(
                pid=s.pid,
                proc_name=s.proc_name,
                peer_host=s.peer_host,
                peer_port=s.peer_port,
            )

        row = proc_agg[key]
        row.rx_bytes += drx
        row.tx_bytes += dtx

    return list(proc_agg.values())


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


def print_table(rows, top, time_hms):
    max_tx = list_max(rows, "tx_rate", 0.001)
    max_rx = list_max(rows, "rx_rate", 0.001)
    rows.sort(key=lambda r: r.rx_rate + r.tx_rate, reverse=True)
    if top < len(rows):
        rows = rows[:top]
    if max_tx < 0.001:
        max_tx = 0.001
    if max_rx < 0.001:
        max_rx = 0.001

    sep_w = (
        W_TIME + W_PID + W_PROC + W_PEER + W_PORT + W_RATE + W_RATE
        + BAR_WIDTH + BAR_WIDTH + 8
    )

    print()
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
        pid_s = r.pid if r.pid > 0 else "-"
        pname = r.proc_name if r.pid > 0 else "-"
        print(
            "{t:<{wt}} {pid:<{wp}} "
            "{pn:<{wproc}} {peer:<{wpeer}} {port:<{wport}} "
            "{rx:>{wr}.2f} {tx:>{wr}.2f} {brx} {btx}".format(
                t=time_hms, wt=W_TIME,
                pid=pid_s, wp=W_PID,
                pn=trunc(pname, W_PROC), wproc=W_PROC,
                peer=trunc(r.peer_host, W_PEER), wpeer=W_PEER,
                port=trunc(r.peer_port, W_PORT), wport=W_PORT,
                rx=r.rx_rate, tx=r.tx_rate, wr=W_RATE,
                brx=brx, btx=btx,
            )
        )


def parse_args(argv):
    top = 15
    interval = 1.0
    count = -1
    filter_pids = []
    filter_names = []
    i = 1
    while i < len(argv) and argv[i].startswith("-"):
        if argv[i] == "-n" and i + 1 < len(argv):
            top = int(argv[i + 1])
            i += 1
        elif argv[i] == "-p" and i + 1 < len(argv):
            filter_pids, filter_names = parse_proc_filters(argv[i + 1])
            i += 1
        elif argv[i] in ("-h", "--help"):
            usage(argv[0])
            sys.exit(0)
        elif argv[i] == "-t":
            print("WARN: thread mode removed; use trace_net.py for per-thread stats",
                  file=sys.stderr)
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
    return top, interval, count, filter_pids, filter_names


def main():
    global G_STOP
    if not sys.platform.startswith("linux"):
        print("ERROR: iftop.py requires Linux", file=sys.stderr)
        return 1
    if not which("ss"):
        print("ERROR: ss not found — install iproute/iproute2", file=sys.stderr)
        return 1

    top, interval, count, filter_pids, filter_names = parse_args(sys.argv)
    signal.signal(signal.SIGINT, on_sig)
    signal.signal(signal.SIGTERM, on_sig)

    prev = filter_socks(collect_via_ss(), filter_pids, filter_names)
    if not prev:
        if filter_pids or filter_names:
            print("ERROR: no matching process TCP connections", file=sys.stderr)
        else:
            print("ERROR: no established TCP sockets (ss empty)", file=sys.stderr)
        return 1

    time.sleep(interval)
    iteration = 0

    while not G_STOP:
        cur = filter_socks(collect_via_ss(), filter_pids, filter_names)
        if not cur:
            print("WARN: sample failed", file=sys.stderr)
            break

        rows = aggregate(cur, prev, filter_pids, filter_names)
        calc_rates(rows, interval)
        time_hms = datetime.now().strftime("%H:%M:%S")
        print_table(rows, top, time_hms)

        prev = cur
        iteration += 1
        if count >= 0 and iteration >= count:
            break
        if G_STOP:
            break
        time.sleep(interval)

    return 0


if __name__ == "__main__":
    sys.exit(main())
