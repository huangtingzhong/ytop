#!/usr/bin/env python
# -*- coding: utf-8 -*-
# File Name: trace_blk.py
# Purpose: Trace block-layer I/O latency (issue to complete) via bpftrace
# Created: 20260616  by  huangtingzhong
"""
trace_blk — block-layer I/O tracer (eBPF / bpftrace)

Complements trace_io.sh (syscall layer): sectors, bytes, real disk latency.
Buffered writes often show as kworker / jbd2 / xfsaild.

Requires: Linux, bpftrace, sudo (passwordless for ytop), Python 2.7+ or 3.x.
Tested: RHEL/OL, openEuler, Anolis, Ubuntu; Kylin/UOS (rpm/apt variants).

Usage:
  trace_blk.py -m 1000                  # default 10s sample
  trace_blk.py -d 30 -m 1000
  trace_blk.py -D nvme0n1 -m 500 -d 20
  trace_blk.py -a -m 2000
  trace_blk.py -C yasdb,kworker -m 0 -d 0   # until Ctrl+C
"""

from __future__ import print_function, division

import argparse
import os
import re
import select
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime

PY3 = sys.version_info[0] >= 3

COMM_DEFAULT = "yasdb,kworker,jbd2,xfsaild"
BLK_LINE_RE = re.compile(r"^BLK\t")

BPFTRACE_TEMPLATE = r"""
BEGIN {
  if (__SHOW_BANNER__) {
    printf("BPFTRACE_BEGIN\n");
  }
}

tracepoint:block:block_rq_issue {
  $maj = args->dev >> 20;
  $min = args->dev & ((1 << 20) - 1);
  if ($maj == 0) {
    $maj = args->dev >> 8;
    $min = args->dev & 0xff;
  }
  if (__DEV_FILTER__ == 0 || ($maj == __DEV_MAJ__ && $min == __DEV_MIN__)) {
    @ts[args->dev, args->sector, args->nr_sector] = nsecs;
    @pid[args->dev, args->sector, args->nr_sector] = pid;
    @comm[args->dev, args->sector, args->nr_sector] = comm;
    @bytes[args->dev, args->sector, args->nr_sector] = args->bytes;
  }
}

tracepoint:block:block_rq_complete / @ts[args->dev, args->sector, args->nr_sector] / {
  $us = (nsecs - @ts[args->dev, args->sector, args->nr_sector]) / 1000;

  $maj = args->dev >> 20;
  $min = args->dev & ((1 << 20) - 1);
  if ($maj == 0) {
    $maj = args->dev >> 8;
    $min = args->dev & 0xff;
  }

  if ($us >= __MIN_US__) {
    $rw = *(uint8*)args->rwbs;
    if ($rw == 87) { $op = 87; } else { $op = 82; }

    printf("BLK\t%s.%06d\t%d\t%d\t%d\t%s\t%d\t%d\t%d\t%d\t%c\n",
      strftime("%H:%M:%S", nsecs), (nsecs % 1000000000) / 1000,
      $maj, $min,
      @pid[args->dev, args->sector, args->nr_sector],
      @comm[args->dev, args->sector, args->nr_sector],
      @bytes[args->dev, args->sector, args->nr_sector],
      args->nr_sector, $us, args->error, $op);
  }

  delete(@ts[args->dev, args->sector, args->nr_sector]);
  delete(@pid[args->dev, args->sector, args->nr_sector]);
  delete(@comm[args->dev, args->sector, args->nr_sector]);
  delete(@bytes[args->dev, args->sector, args->nr_sector]);
}

END {
  clear(@ts); clear(@pid); clear(@comm); clear(@bytes);
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
    """Distro family for bpftrace / util-linux install hints (incl. domestic Linux)."""
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
    if id_ in ("openeuler", "anolis") or "openEuler" in text or "Anolis" in text:
        return "domestic_rpm"
    if id_ in ("ubuntu", "debian") or "debian" in id_like:
        return "debian"
    if "suse" in id_ or "sles" in id_ or "opensuse" in id_:
        return "suse"
    return "unknown"


def bpftrace_install_hint():
    family = detect_os_family()
    hints = {
        "rhel": (
            "  RHEL / Oracle Linux / Rocky / AlmaLinux / CentOS Stream:\n"
            "    sudo dnf install -y bpftrace util-linux\n"
            "    # or: sudo yum install -y bpftrace util-linux\n"
            "  If probes fail, install kernel debuginfo/BTF for $(uname -r)."
        ),
        "domestic_rpm": (
            "  openEuler / Anolis / Kylin / TencentOS / 统信(UOS rpm) 等 rpm 系:\n"
            "    sudo yum install -y bpftrace util-linux\n"
            "    # or: sudo dnf install -y bpftrace util-linux\n"
            "  若无 bpftrace 包，请启用发行版 EPOL/Everything 源或联系 OS 厂商。\n"
            "  内核需启用 CONFIG_BPF / tracepoint:block:block_rq_*。"
        ),
        "debian": (
            "  Ubuntu / Debian / 统信 UOS(deb) / Deepin:\n"
            "    sudo apt-get update\n"
            "    sudo apt-get install -y bpftrace util-linux"
        ),
        "suse": (
            "  SUSE / openSUSE:\n"
            "    sudo zypper install -y bpftrace util-linux"
        ),
        "unknown": (
            "  Generic Linux:\n"
            "    Install package bpftrace + util-linux (lsblk) from your OS repo,\n"
            "    or build bpftrace: https://github.com/bpftrace/bpftrace"
        ),
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
        print("ERROR: bpftrace not installed or not in PATH.", file=sys.stderr)
        print("", file=sys.stderr)
        print(bpftrace_install_hint(), file=sys.stderr)
        return False
    rc, out, err = run_cmd([bt, "--version"], timeout=10)
    if rc != 0:
        print("ERROR: bpftrace failed: {0}".format(err or out), file=sys.stderr)
        print(bpftrace_install_hint(), file=sys.stderr)
        return False
    return True


def check_block_tracepoints():
    bt = which("bpftrace")
    rc, out, err = run_cmd(
        ["sudo", "-n", bt, "-l", "tracepoint:block:block_rq_issue"],
        timeout=15)
    combined = (out or "") + (err or "")
    if rc != 0 or "block_rq_issue" not in combined:
        print("ERROR: kernel tracepoint block:block_rq_issue not available.",
              file=sys.stderr)
        print("  Need Linux 4.x+ with block tracepoints enabled.", file=sys.stderr)
        print("  On minimal/cloud images, install debug kernel or enable BPF.",
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


def parse_lsblk_output(text):
    """Return { '259:0': 'nvme0n1', ... } from lsblk -dn -o NAME,MAJ:MIN."""
    devmap = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        name, majmin = parts[0], parts[1]
        if ":" in majmin:
            devmap[majmin] = name
    return devmap


def load_devmap_from_proc_diskstats():
    devmap = {}
    try:
        with open("/proc/diskstats", "rb") as f:
            text = f.read().decode("utf-8", "replace") if PY3 else f.read()
    except (IOError, OSError):
        return devmap
    for line in text.splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        try:
            maj = int(parts[0])
            min_ = int(parts[1])
        except ValueError:
            continue
        name = parts[2]
        devmap["{0}:{1}".format(maj, min_)] = name
    return devmap


def load_devmap_from_sysfs():
    devmap = {}
    base = "/sys/dev/block"
    if not os.path.isdir(base):
        return devmap
    try:
        entries = os.listdir(base)
    except OSError:
        return devmap
    for majmin in entries:
        dev_path = os.path.join(base, majmin, "dev")
        name = None
        # Resolve dm-N / nvme0n1 via /sys/block
        parts = majmin.split(":")
        if len(parts) == 2:
            for blk in os.listdir("/sys/block"):
                try:
                    with open(os.path.join("/sys/block", blk, "dev"), "rb") as f:
                        val = f.read().decode("utf-8", "replace").strip()
                    if val.replace(":", ":") == majmin or val == majmin:
                        name = blk
                        break
                except (IOError, OSError):
                    continue
        if name:
            devmap[majmin] = name
    return devmap


def load_devmap():
    """Build MAJ:MIN -> disk name; lsblk preferred, fallbacks for domestic/minimal OS."""
    devmap = {}
    lsblk = which("lsblk")
    if lsblk:
        rc, out, _ = run_cmd([lsblk, "-dn", "-o", "NAME,MAJ:MIN"], timeout=10)
        if rc == 0 and out.strip():
            devmap.update(parse_lsblk_output(out))
    if not devmap:
        devmap.update(load_devmap_from_proc_diskstats())
    if not devmap:
        devmap.update(load_devmap_from_sysfs())
    return devmap


def resolve_device(dev_name, devmap):
    """Return (dev_filter, dev_maj, dev_min) for bpftrace placeholders."""
    if not dev_name:
        return 0, 0, 0
    for majmin, name in devmap.items():
        if name == dev_name:
            maj_s, min_s = majmin.split(":", 1)
            return 1, int(maj_s), int(min_s)
    # Direct MAJ:MIN input
    if re.match(r"^\d+:\d+$", dev_name):
        maj_s, min_s = dev_name.split(":", 1)
        return 1, int(maj_s), int(min_s)
    print("ERROR: device not found: {0}".format(dev_name), file=sys.stderr)
    print("  Known disks:", file=sys.stderr)
    for majmin in sorted(devmap.keys(), key=lambda x: devmap[x]):
        print("    {0}  ({1})".format(devmap[majmin], majmin), file=sys.stderr)
    return None


def build_bpftrace_script(min_us, dev_filter, dev_maj, dev_min, show_banner):
    script = BPFTRACE_TEMPLATE
    script = script.replace("__MIN_US__", str(int(min_us)))
    script = script.replace("__DEV_FILTER__", str(int(dev_filter)))
    script = script.replace("__DEV_MAJ__", str(int(dev_maj)))
    script = script.replace("__DEV_MIN__", str(int(dev_min)))
    script = script.replace("__SHOW_BANNER__", "1" if show_banner else "0")
    return script


def human_bytes(n):
    n = float(n)
    if n >= 1073741824:
        v, u = n / 1073741824, "G"
    elif n >= 1048576:
        v, u = n / 1048576, "M"
    elif n >= 1024:
        v, u = n / 1024, "K"
    else:
        return "{0}B".format(int(n))
    if v >= 100:
        return "{0:.0f}{1}".format(v, u)
    if v >= 10:
        return "{0:.1f}{1}".format(v, u)
    return "{0:.2f}{1}".format(v, u)


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


def comm_match(comm, comm_filter, all_comm):
    if all_comm:
        return True
    for prefix in comm_filter.split(","):
        prefix = prefix.strip()
        if prefix and comm.startswith(prefix):
            return True
    return False


def dev_name(maj, min_, devmap):
    key = "{0}:{1}".format(maj, min_)
    return devmap.get(key, key)


class BlkFormatter(object):
    def __init__(self, args, devmap):
        self.args = args
        self.devmap = devmap
        self.printed = 0
        self.total = 0
        self.filtered = 0
        self.read_ops = 0
        self.write_ops = 0
        self.read_bytes = 0
        self.write_bytes = 0
        self.lat_buckets = {}
        self.slow_us = 0
        self.slow_comm = ""
        self.slow_op = ""
        self.slow_disk = ""
        self._header_printed = False

    def print_header(self):
        if self._header_printed:
            return
        self._header_printed = True
        print("=== Block I/O (issue -> complete) ===")
        print("SNAP {0}".format(datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
        comm_label = "*" if self.args.all_comm else self.args.comm
        dev_label = self.args.device or "*"
        print("Filter: comm~{0}  dev={1}  min>={2}us  duration={3}s  (syscall: trace_io.sh)".format(
            comm_label, dev_label, self.args.min_us,
            self.args.duration if self.args.duration > 0 else "until Ctrl+C"))
        print("")
        print("{0}  {1} {2}  {3} {4} {5} {6}  {7}".format(
            "TIME".ljust(18), "COMM".ljust(18), "PID".rjust(6),
            "DISK".ljust(10), "OP".ljust(4), "SIZE".rjust(7),
            "SECT".rjust(6), "LATENCY".rjust(8)))
        print("-" * 74)

    def handle_line(self, line):
        line = line.rstrip("\n")
        if not BLK_LINE_RE.match(line):
            return
        parts = line.split("\t")
        if len(parts) < 11:
            return
        self.total += 1
        t = parts[1]
        maj = int(parts[2])
        min_ = int(parts[3])
        pid = int(parts[4])
        comm = parts[5]
        nbytes = int(parts[6])
        sect = int(parts[7])
        us = int(parts[8])
        err = int(parts[9])
        opch = parts[10]
        disk = dev_name(maj, min_, self.devmap)

        if self.args.device and disk != self.args.device:
            return
        if not comm_match(comm, self.args.comm, self.args.all_comm):
            return

        self.filtered += 1
        op = "WR" if opch == "W" else "RD"
        if op == "RD":
            self.read_ops += 1
            self.read_bytes += nbytes
        else:
            self.write_ops += 1
            self.write_bytes += nbytes

        b = lat_bucket(us)
        self.lat_buckets[b] = self.lat_buckets.get(b, 0) + 1
        if us >= self.slow_us:
            self.slow_us = us
            self.slow_comm = comm
            self.slow_op = op
            self.slow_disk = disk

        if self.args.max_lines == 0 or self.printed < self.args.max_lines:
            lat_s = human_lat(us)
            size_s = human_bytes(nbytes)
            err_s = " ERR={0}".format(err) if err else ""
            print("{0}  {1} {2}  {3} {4} {5} {6}  {7}{8}".format(
                t.ljust(18), comm.ljust(18), str(pid).rjust(6),
                disk.ljust(10), op.ljust(4), size_s.rjust(7),
                str(sect).rjust(6), lat_s.rjust(8), err_s))
            self.printed += 1

    def print_summary(self):
        if self.filtered == 0:
            print("\n(no matching block I/O; try -a, lower -m, or widen -C)")
            return
        if self.args.max_lines > 0 and self.filtered > self.printed:
            print("\n... {0} more events omitted (raise -L or tighten -m/-C)".format(
                self.filtered - self.printed))
        print("\n--- Summary ({0} events".format(self.filtered), end="")
        if self.total > self.filtered:
            print(", {0} before comm/dev filter".format(self.total), end="")
        print(") ---")
        print(" Latency  :", end="")
        for k in ("<1ms", "1-5ms", "5-10ms", "10-50ms", ">=50ms"):
            if k in self.lat_buckets:
                print("  {0}={1}".format(k, self.lat_buckets[k]), end="")
        print("")
        print(" Read     : {0} ({1} ops)".format(
            human_bytes(self.read_bytes), self.read_ops))
        print(" Write    : {0} ({1} ops)".format(
            human_bytes(self.write_bytes), self.write_ops))
        if self.slow_us > 0:
            print(" Slowest  : {0}  {1}  {2}  {3}".format(
                human_lat(self.slow_us), self.slow_comm,
                self.slow_op, self.slow_disk))
        print("\nTip: syscall fast but disk slow -> buffered writeback (kworker); "
              "pair with trace_io.sh")


def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description="Block-layer I/O latency via bpftrace (complements trace_io.sh)",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("-C", "--comm", default=COMM_DEFAULT,
                   help="Comm prefix filter, comma-separated")
    p.add_argument("-a", "--all-comm", action="store_true",
                   help="All processes (no comm filter)")
    p.add_argument("-D", "--device", default="",
                   help="Disk name (nvme0n1) or MAJ:MIN")
    p.add_argument("-m", "--min-us", type=int, default=0,
                   help="Min latency microseconds")
    p.add_argument("-d", "--duration", type=int, default=10,
                   help="Duration seconds (0=until Ctrl+C, default: 10)")
    p.add_argument("-L", "--max-lines", type=int, default=500,
                   help="Max detail lines (0=unlimited)")
    p.add_argument("-B", "--buffer", choices=("none", "full"), default="none",
                   help="bpftrace output buffer mode")
    p.add_argument("-v", "--verbose", action="store_true",
                   help="Show bpftrace INFO / script path")
    return p.parse_args(argv)


def stop_process(proc):
    """Stop bpftrace subprocess (may run under sudo)."""
    if proc.poll() is not None:
        return
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    except (OSError, AttributeError):
        try:
            proc.terminate()
        except OSError:
            pass
    t0 = time.time()
    while proc.poll() is None and time.time() - t0 < 3:
        time.sleep(0.1)
    if proc.poll() is None:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except (OSError, AttributeError):
            try:
                proc.kill()
            except OSError:
                pass


def run_trace(args, devmap, bt_path):
    resolved = resolve_device(args.device, devmap)
    if resolved is None:
        return 1
    dev_filter, dev_maj, dev_min = resolved

    script = build_bpftrace_script(
        args.min_us, dev_filter, dev_maj, dev_min, args.verbose)
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

    formatter = BlkFormatter(args, devmap)
    formatter.print_header()

    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=1)

    def on_sig(_sig, _frame):
        stop_process(proc)

    signal.signal(signal.SIGINT, on_sig)
    signal.signal(signal.SIGTERM, on_sig)

    err_lines = []
    stdout_fd = proc.stdout.fileno()

    while proc.poll() is None:
        rlist, _, _ = select.select([stdout_fd], [], [], 0.5)
        if not rlist:
            continue
        line = proc.stdout.readline()
        if not line:
            continue
        if PY3:
            line = line.decode("utf-8", "replace")
        if line.startswith("Attaching") or line.startswith("BPFTRACE_BEGIN"):
            if args.verbose:
                print(line.rstrip(), file=sys.stderr)
            continue
        if "ERROR:" in line:
            err_lines.append(line.rstrip())
            continue
        formatter.handle_line(line)

    for line in proc.stdout:
        if PY3:
            line = line.decode("utf-8", "replace")
        if "ERROR:" in line:
            err_lines.append(line.rstrip())
            continue
        formatter.handle_line(line)

    proc.wait()
    formatter.print_summary()

    if err_lines and formatter.filtered == 0:
        print("\nbpftrace errors:", file=sys.stderr)
        for el in err_lines:
            print("  " + el, file=sys.stderr)
        return 1
    return 0


def main(argv=None):
    if not sys.platform.startswith("linux"):
        print("ERROR: trace_blk.py requires Linux.", file=sys.stderr)
        return 1
    if not check_bpftrace():
        return 1
    if not check_sudo():
        return 1
    if not check_block_tracepoints():
        return 1

    args = parse_args(argv)
    devmap = load_devmap()
    if not devmap and args.verbose:
        print("WARN: empty device map; DISK column shows MAJ:MIN", file=sys.stderr)

    fd, bt_path = tempfile.mkstemp(prefix="trace_blk_", suffix=".bt")
    os.close(fd)
    try:
        return run_trace(args, devmap, bt_path)
    finally:
        try:
            os.unlink(bt_path)
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
