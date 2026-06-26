#!/usr/bin/env python
# -*- coding: utf-8 -*-
# File Name: para_runlog_ini.py
# Purpose: Compare YashanDB yasdb.ini with run.log parameter snapshots and changes
# Created: 20260623 by huangtingzhong
"""
Compare YashanDB parameter file (yasdb.ini) with historical startup parameters
printed in run.log (between OUTPUT PARAMETER and PARAMETER PRINT END).

By default uses the last 2 parameter blocks from run.log.
Use -i none to scan all run.log blocks and report parameters whose values changed.

Requires: Python 2.7+ or 3.x
"""

from __future__ import print_function, division

import argparse
import io
import os
import re
import sys

PY3 = sys.version_info[0] >= 3

DEFAULT_HISTORY = 2

MARKER_START = re.compile(r"OUTPUT\s+PARAMETER", re.I)
MARKER_END = re.compile(r"PARAMETER\s+PRINT\s+END", re.I)
RUNLOG_PARAM = re.compile(
    r"^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+"
    r"\s+\d+\s+\[(?:INFO|WARN|ERROR|DEBUG)\]\s+"
    r"(?P<key>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*\"(?P<val>.*)\"\s*$"
)
RUNLOG_TS = re.compile(
    r"^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+)"
)
INI_KV = re.compile(
    r"^\s*(?P<key>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?P<val>.*?)\s*$"
)


def text_type(s):
    if s is None:
        return ""
    if PY3 and isinstance(s, bytes):
        return s.decode("utf-8", "replace")
    return s


def norm_key(key):
    return text_type(key).strip().upper()


def norm_value(value):
    v = text_type(value).strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
        v = v[1:-1]
    v = re.sub(r"\s+", " ", v)
    return v


def open_text(path):
    if PY3:
        return io.open(path, "r", encoding="utf-8", errors="replace")
    return io.open(path, "r", encoding="utf-8", errors="replace")


def is_ini_none(path):
    return text_type(path).strip().lower() == "none"


def resolve_ini_path(path):
    if path and is_ini_none(path):
        return "none"
    if path:
        return os.path.abspath(path)
    data = os.environ.get("YASDB_DATA", "").strip()
    if data:
        return os.path.join(data, "config", "yasdb.ini")
    return ""


def resolve_run_log_path(path, ini_params):
    if path:
        p = os.path.abspath(path)
        if os.path.isdir(p):
            return os.path.join(p, "run.log")
        return p

    run_dir = norm_value(ini_params.get("RUN_LOG_FILE_PATH", ""))
    if not run_dir:
        run_dir = os.environ.get("RUN_LOG_FILE_PATH", "").strip()
    if run_dir:
        if os.path.isdir(run_dir):
            return os.path.join(run_dir, "run.log")
        if run_dir.endswith(".log"):
            return run_dir
        return os.path.join(run_dir, "run.log")

    data = os.environ.get("YASDB_DATA", "").strip()
    if data:
        return os.path.join(data, "log", "run", "run.log")
    return ""


def parse_ini(path):
    params = {}
    with open_text(path) as fh:
        for raw in fh:
            line = text_type(raw).strip()
            if not line or line.startswith("#") or line.startswith(";"):
                continue
            m = INI_KV.match(line)
            if not m:
                continue
            params[norm_key(m.group("key"))] = norm_value(m.group("val"))
    return params


def parse_runlog_blocks(path, keep_last):
    blocks = []
    current = None

    with open_text(path) as fh:
        for raw in fh:
            line = text_type(raw).rstrip("\n\r")
            if MARKER_START.search(line):
                ts_m = RUNLOG_TS.match(line)
                current = {
                    "timestamp": ts_m.group(1) if ts_m else "",
                    "params": {},
                }
                continue
            if current is not None and MARKER_END.search(line):
                if current["params"]:
                    blocks.append(current)
                current = None
                continue
            if current is None:
                continue
            m = RUNLOG_PARAM.match(line)
            if m:
                current["params"][norm_key(m.group("key"))] = norm_value(
                    m.group("val")
                )

    if keep_last <= 0:
        return blocks
    return blocks[-keep_last:]


def select_keys(all_keys, requested):
    if not requested:
        return sorted(all_keys)
    wanted = set(norm_key(k) for k in requested)
    return sorted(k for k in all_keys if k in wanted)


def values_equal(a, b):
    return norm_value(a) == norm_value(b)


def status_for(key, ini_val, snapshots, has_ini, has_snaps):
    parts = []
    if not has_ini and has_snaps:
        parts.append("missing-in-ini")
    elif has_ini and not has_snaps:
        parts.append("missing-in-runlog")

    snap_vals = [snap["params"].get(key) for snap in snapshots]
    present_vals = [v for v in snap_vals if v is not None]

    if has_ini and present_vals and not all(
        values_equal(ini_val, v) for v in present_vals
    ):
        parts.append("ini!=runlog")

    if len(present_vals) >= 2:
        if not all(values_equal(present_vals[0], v) for v in present_vals[1:]):
            parts.append("runlog-changed")

    if not parts:
        return "OK"
    return ",".join(parts)


def fmt_val(val):
    if val is None:
        return "-"
    return norm_value(val)


def print_table(ini_params, snapshots, keys, diff_only):
    labels = []
    for i, snap in enumerate(snapshots):
        ts = snap.get("timestamp") or ("snap%d" % (i + 1))
        labels.append("RUNLOG[%d] %s" % (len(snapshots) - i, ts))

    headers = ["PARAMETER", "INI_FILE"] + labels + ["STATUS"]
    rows = []
    for key in keys:
        ini_val = ini_params.get(key)
        snap_vals = [snap["params"].get(key) for snap in snapshots]
        st = status_for(
            key,
            ini_val,
            snapshots,
            ini_val is not None,
            any(v is not None for v in snap_vals),
        )
        if diff_only and st == "OK":
            continue
        row = [key, fmt_val(ini_val)] + [fmt_val(v) for v in snap_vals] + [st]
        rows.append(row)

    if not rows:
        print("No rows to display (all matched or no overlapping parameters).")
        return

    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))

    fmt = "  ".join("{:<" + str(w) + "}" for w in widths)
    print(fmt.format(*headers))
    print(fmt.format(*["-" * w for w in widths]))
    for row in rows:
        print(fmt.format(*row))


def collect_runlog_timeline(blocks, filter_keys):
    timeline = {}
    for block in blocks:
        ts = block.get("timestamp") or ""
        for key, val in block["params"].items():
            if filter_keys is not None and key not in filter_keys:
                continue
            timeline.setdefault(key, []).append((ts, val))
    return timeline


def find_runlog_value_changes(timeline):
    rows = []
    for key in sorted(timeline):
        entries = timeline[key]
        prev_val = None
        prev_val_since = ""
        for ts, val in entries:
            if prev_val is None:
                prev_val = val
                prev_val_since = ts
                continue
            if not values_equal(prev_val, val):
                rows.append(
                    {
                        "key": key,
                        "first_at": prev_val_since,
                        "from": prev_val,
                        "time": ts,
                        "to": val,
                    }
                )
                prev_val = val
                prev_val_since = ts
    return rows


def print_runlog_changes(rows):
    if not rows:
        print("No parameter value changes found in run.log.")
        return

    headers = ["PARAMETER", "FIRST_AT", "FROM", "CHANGED_AT", "TO"]
    table = []
    for row in rows:
        table.append(
            [
                row["key"],
                row["first_at"],
                fmt_val(row["from"]),
                row["time"],
                fmt_val(row["to"]),
            ]
        )

    widths = [len(h) for h in headers]
    for row in table:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))

    fmt = "  ".join("{:<" + str(w) + "}" for w in widths)
    print(fmt.format(*headers))
    print(fmt.format(*["-" * w for w in widths]))
    for row in table:
        print(fmt.format(*row))


def build_arg_parser():
    epilog = """
Default paths:
  INI file : $YASDB_DATA/config/yasdb.ini
  run.log  : RUN_LOG_FILE_PATH from ini (+ /run.log if directory),
             else $YASDB_DATA/log/run/run.log

Examples:
  # On DB host with YASDB_DATA set
  %(prog)s

  # Explicit files
  %(prog)s -i /data/yashan/yasdb_data/db-1-1/config/yasdb.ini \\
           -l /data/yashan/log/db-1-1/run/run.log

  # Compare selected parameters only
  %(prog)s -k MAX_SESSIONS -k DATA_BUFFER_SIZE

  # Scan all run.log blocks for value changes (no ini compare)
  %(prog)s -i none -l /data/yashan/log/db-1-1/run/run.log

  # Via ytop on remote host
  ytop -t 10.10.10.130 -f para_runlog_ini.py
  ytop -t 10.10.10.130 -f "para_runlog_ini.py -i none -l /data/yashan/log/db-1-1/run/run.log"
"""
    p = argparse.ArgumentParser(
        prog="para_runlog_ini.py",
        description=(
            "Compare YashanDB yasdb.ini with run.log parameter snapshots, "
            "or use -i none to list value changes across all run.log blocks."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=epilog,
    )
    p.add_argument(
        "-i",
        "--ini",
        default=None,
        metavar="PATH",
        help=(
            "parameter file path, or 'none' to scan run.log value changes only "
            "(default: $YASDB_DATA/config/yasdb.ini)"
        ),
    )
    p.add_argument(
        "-l",
        "--log",
        default=None,
        metavar="PATH",
        help="run.log path or directory containing run.log",
    )
    p.add_argument(
        "-k",
        "--key",
        action="append",
        dest="keys",
        default=None,
        metavar="NAME",
        help="parameter name to compare; repeatable; default: all known keys",
    )
    p.add_argument(
        "-n",
        "--history",
        type=int,
        default=DEFAULT_HISTORY,
        metavar="N",
        help="number of recent run.log parameter blocks (default: %d)"
        % DEFAULT_HISTORY,
    )
    p.add_argument(
        "-d",
        "--diff-only",
        action="store_true",
        help="show only parameters with differences or missing on one side",
    )
    p.add_argument(
        "--list-ini",
        action="store_true",
        help="list all parameters from ini file and exit",
    )
    p.add_argument(
        "--list-runlog",
        action="store_true",
        help="list parameters from recent run.log blocks and exit",
    )
    return p


def main(argv=None):
    p = build_arg_parser()
    args = p.parse_args(argv)

    ini_none = args.ini is not None and is_ini_none(args.ini)
    ini_path = resolve_ini_path(args.ini)

    if not ini_none:
        if not ini_path:
            print(
                "error: ini path not set; use -i or export YASDB_DATA",
                file=sys.stderr,
            )
            return 2
        if not os.path.isfile(ini_path):
            print(
                "error: ini file not found: {0}".format(ini_path),
                file=sys.stderr,
            )
            return 2
        ini_params = parse_ini(ini_path)
        print(
            "ini file : {0} ({1} params)".format(ini_path, len(ini_params)),
            file=sys.stderr,
        )
    else:
        ini_params = {}
        print("ini file : none (run.log change scan mode)", file=sys.stderr)

    log_path = resolve_run_log_path(args.log, ini_params)
    if not log_path:
        print(
            "error: run.log path not set; use -l or set RUN_LOG_FILE_PATH in ini",
            file=sys.stderr,
        )
        return 2
    if not os.path.isfile(log_path):
        print("error: run.log not found: {0}".format(log_path), file=sys.stderr)
        return 2

    if ini_none:
        snapshots = parse_runlog_blocks(log_path, 0)
        print(
            "run.log  : {0} (all {1} block(s))".format(log_path, len(snapshots)),
            file=sys.stderr,
        )
    else:
        snapshots = parse_runlog_blocks(log_path, args.history)
        print(
            "run.log  : {0} (using last {1} block(s), found {2})".format(
                log_path, args.history, len(snapshots)
            ),
            file=sys.stderr,
        )

    if not snapshots:
        print("error: no parameter blocks found in run.log", file=sys.stderr)
        return 1

    if ini_none:
        filter_keys = None
        if args.keys:
            filter_keys = set(norm_key(k) for k in args.keys)
        timeline = collect_runlog_timeline(snapshots, filter_keys)
        if not timeline:
            print("error: no matching parameters for requested keys", file=sys.stderr)
            return 1
        print("", file=sys.stderr)
        print_runlog_changes(find_runlog_value_changes(timeline))
        return 0

    if args.list_ini:
        for key in sorted(ini_params):
            print("{0}={1}".format(key, ini_params[key]))
        return 0

    if args.list_runlog:
        for idx, snap in enumerate(snapshots):
            ts = snap.get("timestamp") or ("snap%d" % (idx + 1))
            print("# block {0}: {1}".format(idx + 1, ts))
            for key in sorted(snap["params"]):
                print("{0}={1}".format(key, snap["params"][key]))
            if idx + 1 < len(snapshots):
                print("")
        return 0

    all_keys = set(ini_params)
    for snap in snapshots:
        all_keys.update(snap["params"])
    keys = select_keys(all_keys, args.keys)
    if not keys:
        print("error: no matching parameters for requested keys", file=sys.stderr)
        return 1

    print("", file=sys.stderr)
    print_table(ini_params, snapshots, keys, args.diff_only)
    return 0


if __name__ == "__main__":
    sys.exit(main())
