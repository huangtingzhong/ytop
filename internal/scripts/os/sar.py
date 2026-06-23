#!/usr/bin/env python
# -*- coding: utf-8 -*-
# File Name: sar.py
# Purpose: SAR trend report vs 7-day and 30-day baselines
# Created: 20260517  by  huangtingzhong
"""
SAR trend report: compare target day vs 7-day / 30-day baselines (same time slot).

Linux compatibility (sysstat/sar):
  RHEL/CentOS/Rocky/Alma, Oracle Linux/UEK, Fedora, openSUSE,
  openEuler, Anolis OS, Kylin, UnionTech UOS, TencentOS, EulerOS, etc.
  Typical sar dir: /var/log/sa (RHEL family) or /var/log/sysstat (Debian/Ubuntu).
  Requires: Python 2.7+ or Python 3.x; sar (sysstat).

Modes:
  hourly (default): slots 00-23, each hour vs historical same hour
  interval: requires -t HOUR and -i MINUTES (e.g. -t 08 -i 10 -> 08:00,08:10,...08:50)

Usage:
  sar.py [-D DATE] [-n IFACES] [-d DISKS] [-o FILE]
  sar.py -t 08 -i 10 -n ens160 -d dm-0
  sar.py -m disk -d nvme0n1 -f wkB -g
  sar.py -E "-s 140000 -e 145959" -M cpu,net
"""
from __future__ import print_function, division, unicode_literals

import argparse
import glob
import os
import re
import shlex
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timedelta

# ---------------------------------------------------------------------------
# Python 2 / 3 helpers
# ---------------------------------------------------------------------------

PY3 = sys.version_info[0] >= 3

if PY3:
    string_types = (str,)
else:
    string_types = (basestring,)  # noqa: F821


def to_text(val):
    if val is None:
        return u""
    if PY3:
        if isinstance(val, bytes):
            return val.decode("utf-8", "replace")
        return str(val)
    if isinstance(val, unicode):  # noqa: F821
        return val
    if isinstance(val, str):
        return val.decode("utf-8", "replace")
    return unicode(val)  # noqa: F821


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def check_output_quiet(cmd):
    """Run command, return stdout text; empty string on failure."""
    devnull = None
    try:
        if hasattr(subprocess, "DEVNULL"):
            err = subprocess.DEVNULL
        else:
            devnull = open(os.devnull, "w")
            err = devnull
        out = subprocess.check_output(cmd, stderr=err)
        return to_text(out)
    except (subprocess.CalledProcessError, OSError):
        return u""
    finally:
        if devnull is not None:
            devnull.close()


def which(prog):
    for p in os.environ.get("PATH", "").split(os.pathsep):
        full = os.path.join(p, prog)
        if os.path.isfile(full) and os.access(full, os.X_OK):
            return full
    return None


# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

SAR_DIR_DEFAULT = "/var/log/sa"
HISTORY_DAYS = 30
WINDOW_7 = 7
THRESH_MID = 20
THRESH_HIGH = 50
MODULES_DEFAULT = "cpu,mem,load,disk,net,swap"

# sar -d fields after DEV: tps rkB wkB areq-sz aqu-sz await svctm %util
DISK_METRICS = (
    ("tps", 1, ""),
    ("rkB", 2, ""),
    ("wkB", 3, ""),
    ("areq-sz", 4, ""),
    ("aqu-sz", 5, ""),
    ("await", 6, ""),
    ("svctm", 7, ""),
    ("util", 8, "%"),
)

CPU_METRICS = ("iowait", "user", "system", "idle")
NET_METRICS = ("rxpck", "txpck", "rxkB", "txkB", "rxcmp", "txcmp", "rxmcst", "ifutil")

# All -f selectable metrics grouped by module (wkB is one of disk/*)
METRICS_BY_MODULE = (
    ("cpu", CPU_METRICS),
    ("mem", ("memused_pct",)),
    ("load", ("ldavg1", "ldavg15")),
    ("disk", tuple(name for name, _off, _unit in DISK_METRICS)),
    ("net", NET_METRICS),
    ("swap", ("pswpin", "pswpout")),
)


def format_metrics_help():
    lines = [
        "Filter metrics (default: all enabled by -m). Forms:",
        "  NAME         match metric in any module, e.g. wkB, iowait, txkB",
        "  MODULE/NAME  e.g. disk/wkB, cpu/iowait, net/txkB",
        "  MODULE       all metrics in module, e.g. cpu, disk, net",
        "All metrics by module:",
    ]
    for cat, names in METRICS_BY_MODULE:
        lines.append("  {0}: {1}".format(cat, ", ".join(names)))
    lines.append("e.g. -f wkB,txkB  |  -f disk/wkB,cpu/iowait  |  -f disk")
    return "\n            ".join(lines)


METRICS_HELP = format_metrics_help()

HELP_EPILOG = """
Modes:
  hourly   Default: compare each hour 00-23 vs prior 7 days (daily) + 30d avg
  interval Requires -t and -i: compare HH:00, HH:10, ... within pinned hour

Examples:
  # Default hourly report: all modules, auto top disk/net
  sar.py

  # Hourly CPU+net on ens160, save to file
  sar.py -m cpu,net -n ens160 -o /tmp/sar_report.txt

  # Current slot only (quick snapshot for troubleshooting)
  sar.py --now -m cpu,net -n ens160

  # Interval mode: 08:00-08:50 every 10 minutes vs same clock baseline
  sar.py -t 8 -i 10 -m cpu,net -n ens160

  # Specific compare date with shorter history windows
  sar.py -D 20260610 -H 14 -W 3 -m cpu --now

  # Cross-module metrics: wkB is disk-only; txkB is net-only
  sar.py -m cpu,disk,net -f wkB,txkB,iowait --now

  # Disk module only: wkB + util (wkB is one of eight disk metrics)
  sar.py -m disk -d nvme0n1 -f disk/wkB,util

  # Group by metric: each metric block lists all hours (easier trend scan)
  sar.py -m disk -d nvme0n1 -f wkB,tps -g

  # Pass time range to sar (hourly mode, CPU only; HHMMSS compact)
  sar.py -E "-s 140000 -e 145959" -m cpu -f iowait

  # Non-default sar archive dir (Debian/Ubuntu sysstat path)
  sar.py -S /var/log/sysstat -m cpu --now

Option convention:
  lowercase  common:  -d -t -i -m -f -n -o -g --now
  uppercase  advanced: -D -H -W -E -S
  aliases: -M same as -m; -I same as -n; -w7 same as -W; -g same as --by-metric
"""

TIME_LINE_RE = re.compile(r"^[0-9]{1,2}:[0-9]{2}:[0-9]{2}")
DATE_ISO_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
DATE_SLASH_RE = re.compile(r"^[0-9]{2}/[0-9]{2}/[0-9]{4}$")
DATE_DOT_RE = re.compile(r"^[0-9]{2}\.[0-9]{2}\.[0-9]{4}$")
DATE_COMPACT_RE = re.compile(r"^\d{8}$")
TIME_COMPACT_RE = re.compile(r"^\d{6}$")


def normalize_date_str(d):
    if not d:
        return d
    d = d.strip()
    if DATE_COMPACT_RE.match(d):
        return "{0}-{1}-{2}".format(d[0:4], d[4:6], d[6:8])
    return d


def normalize_sar_time_token(tok):
    if TIME_COMPACT_RE.match(tok):
        return "{0}:{1}:{2}".format(tok[0:2], tok[2:4], tok[4:6])
    return tok


def normalize_sar_extra_args(args_list):
    out = []
    prev = None
    for tok in args_list:
        if prev in ("-s", "-e"):
            tok = normalize_sar_time_token(tok)
        out.append(tok)
        prev = tok
    return out


# ---------------------------------------------------------------------------
# Date helpers
# ---------------------------------------------------------------------------

def parse_date(s):
    return datetime.strptime(s, "%Y-%m-%d").date()


def fmt_date(d):
    return d.strftime("%Y-%m-%d")


def date_minus(d_str, days):
    d = parse_date(d_str) - timedelta(days=int(days))
    return fmt_date(d)


def date_le(a, b):
    return a <= b


def emit_date_from_parts(y, m, d):
    return "{0:04d}-{1:02d}-{2:02d}".format(int(y), int(m), int(d))


def parse_header_date_token(tok):
    tok = tok.strip()
    if DATE_ISO_RE.match(tok):
        parts = tok.split("-")
        return emit_date_from_parts(parts[0], parts[1], parts[2])
    if DATE_SLASH_RE.match(tok) or DATE_DOT_RE.match(tok):
        sep = "/" if "/" in tok else "."
        parts = tok.split(sep)
        a1, a2, a3 = int(parts[0]), int(parts[1]), int(parts[2])
        if a1 > 12 and a2 <= 12:
            return emit_date_from_parts(a3, a2, a1)
        return emit_date_from_parts(a3, a1, a2)
    return None


def get_file_date(sar_path, sar_extra_args):
    for flag in ("-u", "-n", "DEV"):
        cmd = ["sar", "-f", sar_path]
        cmd.extend(sar_extra_args)
        if flag == "-n":
            cmd.extend(["-n", "DEV"])
        else:
            cmd.append(flag)
        hdr = check_output_quiet(cmd).splitlines()
        if not hdr:
            continue
        line = hdr[0]
        for tok in line.split():
            d = parse_header_date_token(tok)
            if d:
                return d
    return None


# ---------------------------------------------------------------------------
# SAR archive discovery
# ---------------------------------------------------------------------------

def has_sar_files(d):
    if not os.path.isdir(d):
        return False
    for pattern in (os.path.join(d, "sa[0-9][0-9]"), os.path.join(d, "sa[0-9]")):
        if glob.glob(pattern):
            return True
    return False


def discover_sar_dir(explicit_dir, explicit_flag):
    if explicit_flag:
        return explicit_dir
    for candidate in ("/var/log/sa", "/var/log/sysstat"):
        if has_sar_files(candidate):
            return candidate
    return explicit_dir


def collect_sar_files(sar_dir):
    patterns = [os.path.join(sar_dir, "sa[0-9][0-9]"), os.path.join(sar_dir, "sa[0-9]")]
    seen = set()
    for pattern in patterns:
        for f in sorted(glob.glob(pattern)):
            if os.path.isfile(f):
                seen.add(f)
    return sorted(seen)


def field(parts, n):
    """Return awk-style 1-based field n, or None."""
    idx = n - 1
    if idx < 0 or idx >= len(parts):
        return None
    return parts[idx]


# ---------------------------------------------------------------------------
# SAR parsing
# ---------------------------------------------------------------------------

def normalize_pin_hour(pin_hour):
    if not pin_hour:
        return pin_hour
    part = pin_hour.split(":")[0]
    return "{0:02d}".format(int(part))


def build_slots(mode, pin_hour, interval_min):
    if mode == "hourly":
        return ["{0:02d}".format(h) for h in range(24)]
    slots = []
    m = 0
    while m < 60:
        slots.append("{0}:{1:02d}".format(pin_hour, m))
        m += interval_min
    return slots


def row_offset(parts):
    if len(parts) > 1 and parts[1] in ("AM", "PM"):
        return 3
    return 2


def time_slot(parts, mode, pin_hour, interval_min):
    if not parts:
        return None
    time_tok = parts[0]
    tparts = time_tok.split(":")
    h = int(tparts[0])
    mi = int(tparts[1]) if len(tparts) > 1 else 0
    if len(parts) > 1 and parts[1] in ("AM", "PM"):
        ap = parts[1]
        if ap == "AM" and h == 12:
            h = 0
        elif ap == "PM" and h != 12:
            h += 12
    if mode == "interval":
        if "{0:02d}".format(h) != pin_hour:
            return None
        mi = (mi // interval_min) * interval_min
        if mi >= 60:
            return None
        return "{0:02d}:{1:02d}".format(h, mi)
    return "{0:02d}".format(h)


def parse_float(tok, default=None):
    try:
        return float(tok.replace("%", ""))
    except (ValueError, AttributeError):
        return default


def run_sar(sar_path, sar_auto_opts, sar_extra_args, extra_flags):
    cmd = ["sar", "-f", sar_path]
    cmd.extend(sar_auto_opts)
    cmd.extend(sar_extra_args)
    cmd.extend(extra_flags)
    return check_output_quiet(cmd).splitlines()


def iter_sar_rows(lines, mode, pin_hour, interval_min):
    for line in lines:
        line = line.strip()
        if not line or not TIME_LINE_RE.match(line):
            continue
        parts = line.split()
        slot = time_slot(parts, mode, pin_hour, interval_min)
        if not slot:
            continue
        yield parts, slot, row_offset(parts)


def extract_cpu(sar_path, d, mode, pin_hour, interval_min, sar_auto_opts, sar_extra_args):
    rows = []
    for parts, slot, off in iter_sar_rows(
        run_sar(sar_path, sar_auto_opts, sar_extra_args, ["-u"]),
        mode, pin_hour, interval_min,
    ):
        if field(parts, off) != "all":
            continue
        metrics = (
            ("user", off + 1),
            ("system", off + 3),
            ("iowait", off + 4),
            ("idle", off + 6),
        )
        for name, idx in metrics:
            val = parse_float(field(parts, idx))
            if val is None or val > 100:
                continue
            rows.append((d, slot, "cpu", "", name, val))
    return rows


def extract_mem(sar_path, d, mode, pin_hour, interval_min, sar_auto_opts, sar_extra_args):
    rows = []
    for parts, slot, off in iter_sar_rows(
        run_sar(sar_path, sar_auto_opts, sar_extra_args, ["-r"]),
        mode, pin_hour, interval_min,
    ):
        tok = field(parts, off)
        if tok is None or not re.match(r"^[0-9]+$", tok):
            continue
        rows.append((d, slot, "mem", "", "kbmemfree", float(tok)))
        tok = field(parts, off + 1)
        if tok is not None:
            rows.append((d, slot, "mem", "", "kbavail", float(tok)))
        val = parse_float(field(parts, off + 3))
        if val is not None:
            rows.append((d, slot, "mem", "", "memused_pct", val))
    return rows


def extract_load(sar_path, d, mode, pin_hour, interval_min, sar_auto_opts, sar_extra_args):
    rows = []
    for parts, slot, off in iter_sar_rows(
        run_sar(sar_path, sar_auto_opts, sar_extra_args, ["-q"]),
        mode, pin_hour, interval_min,
    ):
        tok = field(parts, off + 1)
        if tok is None or not re.match(r"^[0-9]", tok):
            continue
        val = parse_float(field(parts, off + 2), 0.0)
        if val is not None:
            rows.append((d, slot, "load", "", "ldavg1", val))
        val = parse_float(field(parts, off + 4), 0.0)
        if val is not None:
            rows.append((d, slot, "load", "", "ldavg15", val))
    return rows


def extract_disk(sar_path, d, mode, pin_hour, interval_min, sar_auto_opts, sar_extra_args):
    rows = []
    for parts, slot, off in iter_sar_rows(
        run_sar(sar_path, sar_auto_opts, sar_extra_args, ["-dp"]),
        mode, pin_hour, interval_min,
    ):
        dev = field(parts, off)
        if dev is None or dev == "DEV" or dev.startswith("scd"):
            continue
        for met, delta, _unit in DISK_METRICS:
            val = parse_float(field(parts, off + delta), 0.0)
            if val is not None:
                rows.append((d, slot, "disk", dev, met, val))
    return rows


def extract_net(sar_path, d, mode, pin_hour, interval_min, sar_auto_opts, sar_extra_args):
    rows = []
    for parts, slot, off in iter_sar_rows(
        run_sar(sar_path, sar_auto_opts, sar_extra_args, ["-n", "DEV"]),
        mode, pin_hour, interval_min,
    ):
        iface = field(parts, off)
        if iface in (None, "IFACE", "", "lo"):
            continue
        net_metrics = (
            ("rxpck", 1), ("txpck", 2), ("rxkB", 3), ("txkB", 4),
            ("rxcmp", 5), ("txcmp", 6), ("rxmcst", 7),
        )
        for name, delta in net_metrics:
            val = parse_float(field(parts, off + delta), 0.0)
            if val is not None:
                rows.append((d, slot, "net", iface, name, val))
        val = parse_float(field(parts, off + 8), 0.0)
        if val is not None:
            rows.append((d, slot, "net", iface, "ifutil", val))
    return rows


def extract_swap(sar_path, d, mode, pin_hour, interval_min, sar_auto_opts, sar_extra_args):
    rows = []
    for parts, slot, off in iter_sar_rows(
        run_sar(sar_path, sar_auto_opts, sar_extra_args, ["-W"]),
        mode, pin_hour, interval_min,
    ):
        val = parse_float(field(parts, off), 0.0)
        if val is not None:
            rows.append((d, slot, "swap", "", "pswpin", val))
        val = parse_float(field(parts, off + 1), 0.0)
        if val is not None:
            rows.append((d, slot, "swap", "", "pswpout", val))
    return rows


EXTRACTORS = {
    "cpu": extract_cpu,
    "mem": extract_mem,
    "load": extract_load,
    "disk": extract_disk,
    "net": extract_net,
    "swap": extract_swap,
}


def module_enabled(modules, name):
    return name in [x.strip() for x in modules.split(",") if x.strip()]


def aggregate_csv(raw_rows):
    """Average samples per date+slot+category+entity+metric; drop bad CPU."""
    sums = defaultdict(float)
    counts = defaultdict(int)
    for d, slot, cat, ent, met, val in raw_rows:
        if cat == "cpu" and (val < 0 or val > 100):
            continue
        key = (d, slot, cat, ent, met)
        sums[key] += val
        counts[key] += 1
    out = []
    for key, total in sums.items():
        cnt = counts[key]
        d, slot, cat, ent, met = key
        out.append((d, slot, cat, ent, met, total / cnt))
    return out


def auto_top_entities(csv_rows, compare_date, cat, metric, exclude=None, top_n=3):
    scores = defaultdict(float)
    for d, slot, c, ent, met, val in csv_rows:
        if d != compare_date or c != cat or met != metric:
            continue
        if exclude and ent == exclude:
            continue
        scores[ent] += val
    ranked = sorted(scores.items(), key=lambda x: (-x[1], x[0]))
    return [k for k, _ in ranked[:top_n]]


# ---------------------------------------------------------------------------
# Report rendering
# ---------------------------------------------------------------------------

def pct_change(today, baseline):
    if today is None or baseline is None:
        return "N/A"
    if baseline == 0:
        return "0" if today == 0 else "N/A"
    return "{0:.0f}".format((today - baseline) / baseline * 100.0)


def trend_label(pct_str, thresh_mid, thresh_high):
    if pct_str == "N/A":
        return "-"
    try:
        n = int(float(pct_str))
    except ValueError:
        return "-"
    if n >= thresh_high:
        return "CRIT"
    if n >= thresh_mid:
        return "HIGH"
    if n <= -thresh_mid:
        return "LOW"
    return "OK"


def bar_chart(value, max_val):
    if max_val is None or max_val <= 0:
        max_val = value if value and value > 0 else 1.0
    n = int(value / max_val * 10) if max_val else 0
    if n > 10:
        n = 10
    return ("#" * n) + ("." * (10 - n))


def index_csv(csv_rows):
    data = {}
    for d, slot, cat, ent, met, val in csv_rows:
        data[(d, slot, cat, ent, met)] = val
    return data


def fmt_cell(v, unit):
    """Fixed-width value cell (width 8)."""
    if v is None:
        return "{0:>8s}".format("-")
    if unit == "%":
        return "{0:>7.2f}%".format(v)
    return "{0:>8.2f}".format(v)


def fmt_vs30(p):
    if p == "N/A":
        return "{0:>6s}".format("N/A")
    return "{0:>5s}%".format(p)


def build_metric_specs(modules, disks, ifaces):
    specs = []

    def add(cat, ent, met, unit):
        label = "{0}/{1}".format(ent, met) if ent else "{0}/{1}".format(cat, met)
        specs.append((cat, ent, met, unit, label))

    if module_enabled(modules, "cpu"):
        for m in CPU_METRICS:
            add("cpu", "", m, "%")
    if module_enabled(modules, "mem"):
        add("mem", "", "memused_pct", "%")
    if module_enabled(modules, "load"):
        add("load", "", "ldavg1", "")
        add("load", "", "ldavg15", "")
    if module_enabled(modules, "swap"):
        add("swap", "", "pswpin", "")
        add("swap", "", "pswpout", "")
    for dev in disks:
        if dev:
            for met, _delta, unit in DISK_METRICS:
                add("disk", dev, met, unit)
    for iface in ifaces:
        if iface and iface != "lo":
            for m in NET_METRICS:
                add("net", iface, m, "%" if m == "ifutil" else "")
    return specs


def row_metrics(data, compare_date, start_30, days_7, slot, cat, ent, met, unit,
                thresh_mid, thresh_high):
    today = data.get((compare_date, slot, cat, ent, met))
    day_vals = []
    sum7 = 0.0
    c7 = 0
    for d7 in days_7:
        hv = data.get((d7, slot, cat, ent, met))
        day_vals.append(hv)
        if hv is not None:
            sum7 += hv
            c7 += 1
    b7 = (sum7 / c7) if c7 > 0 else None

    sum30 = 0.0
    c30 = 0
    for key, val in data.items():
        d, s, c, e, m = key
        if s != slot or c != cat or e != ent or m != met:
            continue
        if d < compare_date and d >= start_30:
            sum30 += val
            c30 += 1
    b30 = (sum30 / c30) if c30 > 0 else None

    p30 = pct_change(today, b30)
    tr = trend_label(pct_change(today, b7), thresh_mid, thresh_high)
    return today, day_vals, b30, p30, tr


def build_table_header(group_by, day_labels):
    if group_by == "metric":
        parts = ["{0:<18s}".format("Metric"), "{0:>5s}".format("Slot")]
    else:
        parts = ["{0:>5s}".format("Slot"), "{0:<18s}".format("Metric")]
    parts.append("{0:>8s}".format("Compare"))
    for lab in day_labels:
        parts.append("{0:>8s}".format(lab))
    parts.extend([
        "{0:>8s}".format("30d-avg"),
        "{0:>6s}".format("vs30d"),
        "{0:>5s}".format("Trend"),
        "{0:<10s}".format("Bar"),
    ])
    return " ".join(parts)


def render_unified_table(csv_rows, cfg, metric_specs, group_by="slot"):
    if not metric_specs:
        return ""
    if group_by not in ("slot", "metric"):
        group_by = "slot"

    data = index_csv(csv_rows)
    slots = cfg["slots"]
    compare_date = cfg["compare_date"]
    start_30 = cfg["start_30"]
    days_7 = cfg["days_7"]
    day_labels = cfg["day_labels"]
    now_slot = cfg["now_slot"]
    current_only = cfg["current_only"]
    thresh_mid = cfg["thresh_mid"]
    thresh_high = cfg["thresh_high"]

    active_slots = [s for s in slots if not current_only or s == now_slot]
    if not active_slots:
        return ""

    max_by_key = {}
    for cat, ent, met, unit, _label in metric_specs:
        mx = 0.0
        for slot in active_slots:
            v = data.get((compare_date, slot, cat, ent, met))
            if v is not None and v > mx:
                mx = v
        max_by_key[(cat, ent, met)] = mx

    lines = []
    if group_by == "slot":
        lines.append(build_table_header(group_by, day_labels))

    if group_by == "slot":
        for slot in active_slots:
            for cat, ent, met, unit, label in metric_specs:
                today, day_vals, b30, p30, tr = row_metrics(
                    data, compare_date, start_30, days_7, slot, cat, ent, met, unit,
                    thresh_mid, thresh_high,
                )
                bar_v = today if today is not None else 0.0
                row = [
                    "{0:>5s}".format(slot),
                    "{0:<18s}".format(label[:18]),
                    fmt_cell(today, unit),
                ]
                for hv in day_vals:
                    row.append(fmt_cell(hv, unit))
                row.append(fmt_cell(b30, unit))
                row.append(fmt_vs30(p30))
                row.append("{0:>5s}".format(tr))
                row.append(bar_chart(bar_v, max_by_key[(cat, ent, met)]))
                lines.append(" ".join(row))
    else:
        header = build_table_header(group_by, day_labels)
        for mi, (cat, ent, met, unit, label) in enumerate(metric_specs):
            if mi > 0:
                lines.append("")
            lines.append(header)
            first_in_group = True
            for slot in active_slots:
                today, day_vals, b30, p30, tr = row_metrics(
                    data, compare_date, start_30, days_7, slot, cat, ent, met, unit,
                    thresh_mid, thresh_high,
                )
                bar_v = today if today is not None else 0.0
                metric_col = "{0:<18s}".format(label[:18]) if first_in_group else "{0:<18s}".format("")
                row = [
                    metric_col,
                    "{0:>5s}".format(slot),
                    fmt_cell(today, unit),
                ]
                for hv in day_vals:
                    row.append(fmt_cell(hv, unit))
                row.append(fmt_cell(b30, unit))
                row.append(fmt_vs30(p30))
                row.append("{0:>5s}".format(tr))
                row.append(bar_chart(bar_v, max_by_key[(cat, ent, met)]))
                lines.append(" ".join(row))
                first_in_group = False

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_metrics_filter(metrics_filter):
    if not metrics_filter:
        return None
    return [x.strip().lower() for x in metrics_filter.split(",") if x.strip()]


def metric_matches_filter(cat, met, tokens):
    cat_l = cat.lower()
    met_l = met.lower()
    for tok in tokens:
        if "/" in tok:
            parts = tok.split("/", 1)
            if len(parts) == 2 and parts[0] == cat_l and parts[1] == met_l:
                return True
        elif tok == cat_l:
            return True
        elif tok == met_l:
            return True
    return False


def filter_metric_specs(specs, metrics_filter):
    tokens = parse_metrics_filter(metrics_filter)
    if not tokens:
        return specs
    filtered = [s for s in specs if metric_matches_filter(s[0], s[2], tokens)]
    return filtered


def build_parser():
    p = argparse.ArgumentParser(
        prog="sar.py",
        description="SAR trend report (English output)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=HELP_EPILOG,
    )
    p.add_argument(
        "-D", dest="compare_date", default="",
        help="Compare date YYYYMMDD or YYYY-MM-DD (default: latest archive). e.g. -D 20260610",
    )
    p.add_argument(
        "-H", dest="history_days", type=int, default=HISTORY_DAYS,
        help="Long history window for 30d baseline (default: 30). e.g. -H 14",
    )
    p.add_argument(
        "-W", "-w7", dest="window_7", type=int, default=WINDOW_7,
        help="Prior N calendar days as daily columns (default: 7). e.g. -W 3",
    )
    p.add_argument(
        "-t", dest="pin_hour", default="",
        help="Pin hour for interval mode (requires -i). e.g. -t 8 or -t 08 or -t 08:00",
    )
    p.add_argument(
        "-i", dest="interval_min", type=int, default=0,
        help="Sample interval within pinned hour (requires -t). e.g. -i 10 -> 08:00,08:10,...,08:50",
    )
    p.add_argument(
        "-n", "-I", dest="ifaces", default="",
        help="Network interfaces, comma-separated (default: auto top3 txkB, skip lo). "
             "e.g. -n ens160 or -n eth0,eth1",
    )
    p.add_argument(
        "-d", dest="disks", default="",
        help="Disk devices, comma-separated (default: auto top3 wkB). "
             "e.g. -d dm-0 or -d sda,nvme0n1",
    )
    p.add_argument(
        "-m", "-M",
        dest="modules",
        default=MODULES_DEFAULT,
        metavar="MODULES",
        help="Report modules, comma-separated (default: all): cpu,mem,load,disk,net,swap. "
             "e.g. -m cpu,net or -m mem,load",
    )
    p.add_argument(
        "-f", dest="metrics", default="", metavar="METRICS",
        help=METRICS_HELP,
    )
    p.add_argument(
        "-E", dest="sar_extra_opts", default="",
        help='Extra sar args after -f FILE; -s/-e accept HHMMSS compact time. '
             'e.g. -E "-s 140000 -e 145959" or -E "-u -s 080000 -e 085959"',
    )
    p.add_argument(
        "-S", dest="sar_dir", default=SAR_DIR_DEFAULT,
        help="Sar archive directory (default: auto /var/log/sa or /var/log/sysstat). "
             "e.g. -S /var/log/sa or -S /var/log/sysstat",
    )
    p.add_argument(
        "-o", dest="out_file", default="",
        help="Save report to file (stdout still printed). e.g. -o /tmp/sar_report.txt",
    )
    p.add_argument(
        "--now", dest="current_only", action="store_true",
        help="Current slot only: summary + detail sections for NOW hour/slot",
    )
    p.add_argument(
        "-g", "--by-metric", dest="group_by_metric", action="store_true",
        help="Group rows by metric (Slot as sub-rows) for easier same-metric trend scan. "
             "Default groups by time slot.",
    )
    return p


def parse_sar_extra_opts(opt_str):
    if not opt_str:
        return []
    return normalize_sar_extra_args(shlex.split(opt_str))


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]
    parser = build_parser()
    args = parser.parse_args(argv)

    if which("sar") is None:
        eprint("ERROR: sar not found - install sysstat (yum/dnf/apt) and enable sa1/sa2 collection")
        return 1

    sar_dir_explicit = "-S" in argv
    sar_dir = discover_sar_dir(args.sar_dir, sar_dir_explicit)
    if not has_sar_files(sar_dir):
        eprint("ERROR: no sar archives in {0} - install sysstat, enable sa1/sa2, or use -S DIR".format(sar_dir))
        return 1

    pin_hour = normalize_pin_hour(args.pin_hour) if args.pin_hour else ""
    interval_min = args.interval_min or 0

    if pin_hour and interval_min:
        mode = "interval"
    elif pin_hour or interval_min:
        eprint("ERROR: interval mode requires both -t HOUR and -i MINUTES (e.g. -t 08 -i 10)")
        return 1
    else:
        mode = "hourly"

    if mode == "interval" and (interval_min < 1 or interval_min >= 60):
        eprint("ERROR: interval must be between 1 and 59 minutes")
        return 1

    modules = args.modules
    compare_date = normalize_date_str(args.compare_date) if args.compare_date else ""
    sar_extra_args = parse_sar_extra_opts(args.sar_extra_opts)
    sar_auto_opts = []
    if mode == "interval" and "-s" not in args.sar_extra_opts:
        sar_auto_opts = ["-s", "{0}:00:00".format(pin_hour), "-e", "{0}:59:59".format(pin_hour)]

    slots = build_slots(mode, pin_hour, interval_min)

    files = collect_sar_files(sar_dir)
    file_by_date = {}
    for f in files:
        d = get_file_date(f, sar_extra_args)
        if d:
            file_by_date[d] = f

    if not file_by_date:
        eprint("ERROR: no dated sar archives under {0}".format(sar_dir))
        return 1

    compare_date = compare_date or sorted(file_by_date.keys())[-1]
    if compare_date not in file_by_date:
        eprint("ERROR: no sar data for compare date {0}".format(compare_date))
        return 1

    history_days = args.history_days
    window_7 = args.window_7
    start_30 = date_minus(compare_date, history_days)

    days_7 = []
    day_labels = []
    for di in range(1, window_7 + 1):
        d = date_minus(compare_date, di)
        days_7.append(d)
        day_labels.append(parse_date(d).strftime("%m-%d"))

    now = datetime.now()
    now_slot = now.strftime("%H")
    if mode == "interval":
        now_min = (now.minute // interval_min) * interval_min
        now_slot = "{0}:{1:02d}".format(pin_hour, now_min)

    raw_rows = []
    for d, f in file_by_date.items():
        if not date_le(start_30, d) or not date_le(d, compare_date):
            continue
        for mod, fn in EXTRACTORS.items():
            if module_enabled(modules, mod):
                raw_rows.extend(fn(f, d, mode, pin_hour, interval_min, sar_auto_opts, sar_extra_args))

    csv_rows = aggregate_csv(raw_rows)
    if not csv_rows:
        eprint("ERROR: no slot data extracted")
        return 1

    disks = [x.strip() for x in args.disks.split(",") if x.strip()] if args.disks else []
    ifaces = [x.strip() for x in args.ifaces.split(",") if x.strip()] if args.ifaces else []

    if not disks and module_enabled(modules, "disk"):
        disks = auto_top_entities(csv_rows, compare_date, "disk", "wkB")
    if not ifaces and module_enabled(modules, "net"):
        ifaces = auto_top_entities(csv_rows, compare_date, "net", "txkB", exclude="lo")

    cfg = {
        "slots": slots,
        "compare_date": compare_date,
        "start_30": start_30,
        "days_7": days_7,
        "day_labels": day_labels,
        "now_slot": now_slot,
        "current_only": args.current_only,
        "thresh_mid": THRESH_MID,
        "thresh_high": THRESH_HIGH,
    }

    metric_specs = build_metric_specs(modules, disks, ifaces)
    metric_specs = filter_metric_specs(metric_specs, args.metrics)
    if not metric_specs:
        eprint("ERROR: no metrics match -f {0}".format(args.metrics or ""))
        return 1
    report = render_unified_table(
        csv_rows, cfg, metric_specs,
        group_by="metric" if args.group_by_metric else "slot",
    )
    if not report:
        eprint("ERROR: no report rows generated")
        return 1

    print(report)
    if args.out_file:
        with open(args.out_file, "w") as fh:
            fh.write(report)
            if not report.endswith("\n"):
                fh.write("\n")
        eprint("")
        eprint("Report saved: {0}".format(args.out_file))

    return 0


if __name__ == "__main__":
    sys.exit(main())
