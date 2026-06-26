#!/usr/bin/env python
# -*- coding: utf-8 -*-
# File Name: pidstat.py
# Purpose: Process and thread CPU memory IO stats via /proc
# Created: 20260517  by  huangtingzhong
"""
pidstat - Process and thread resource monitoring (from pidstat.go)

Linux only (/proc). Default process: yasdb, interval 5s, continuous, options -t -urd.
Requires: Python 2.7+ or Python 3.x.
"""

from __future__ import print_function, division

import argparse
import copy
import os
import re
import sys
import time

PY3 = sys.version_info[0] >= 3

DEFAULT_PROCESS = "yasdb"
DEFAULT_INTERVAL = 5
DEFAULT_OPTS = "-t -urd"
HZ = 100


def open_text(path, mode="r"):
    if PY3:
        return open(path, mode, encoding="utf-8", errors="replace")
    import codecs
    return codecs.open(path, mode, encoding="utf-8", errors="replace")


def decode_utf8(raw):
    if not raw:
        return ""
    if PY3:
        if isinstance(raw, bytes):
            return raw.decode("utf-8", "replace")
        return str(raw)
    if isinstance(raw, str):
        return raw.decode("utf-8", "replace")
    return raw


def iteritems(mapping):
    if PY3:
        return mapping.items()
    return mapping.iteritems()


class ProcessStats(object):
    def __init__(self, **kwargs):
        self.uid = kwargs.get("uid", "")
        self.tgid = kwargs.get("tgid", "")
        self.tid = kwargs.get("tid", "")
        self.pid = kwargs.get("pid", "")
        self.usr = kwargs.get("usr", 0.0)
        self.sys = kwargs.get("sys", 0.0)
        self.guest = kwargs.get("guest", 0.0)
        self.wait = kwargs.get("wait", 0.0)
        self.cpu = kwargs.get("cpu", 0.0)
        self.cpu_core = kwargs.get("cpu_core", 0)
        self.minflt = kwargs.get("minflt", 0.0)
        self.majflt = kwargs.get("majflt", 0.0)
        self.vsz = kwargs.get("vsz", 0)
        self.rss = kwargs.get("rss", 0)
        self.mem = kwargs.get("mem", 0.0)
        self.kbrd = kwargs.get("kbrd", 0.0)
        self.kbwr = kwargs.get("kbwr", 0.0)
        self.kbccwr = kwargs.get("kbccwr", 0.0)
        self.syscr = kwargs.get("syscr", 0.0)
        self.syscw = kwargs.get("syscw", 0.0)
        self.riops = kwargs.get("riops", 0.0)
        self.wiops = kwargs.get("wiops", 0.0)
        self.threads = kwargs.get("threads", 0)
        self.fdnr = kwargs.get("fdnr", 0)
        self.cswch = kwargs.get("cswch", 0.0)
        self.nvcswch = kwargs.get("nvcswch", 0.0)
        self.time_plus = kwargs.get("time_plus", 0.0)
        self.cmd = kwargs.get("cmd", "")


class CPUStat(object):
    def __init__(self):
        self.user = 0
        self.nice = 0
        self.system = 0
        self.idle = 0
        self.iowait = 0
        self.irq = 0
        self.softirq = 0
        self.steal = 0
        self.guest = 0
        self.total = 0


class ProcessCPUStat(object):
    def __init__(self, **kwargs):
        self.utime = kwargs.get("utime", 0)
        self.stime = kwargs.get("stime", 0)
        self.cutime = kwargs.get("cutime", 0)
        self.cstime = kwargs.get("cstime", 0)
        self.starttime = kwargs.get("starttime", 0)
        self.delayacct_blkio_ticks = kwargs.get("delayacct_blkio_ticks", 0)


class ProcessStatData(object):
    def __init__(self, stats, cpu_stat, timestamp=0.0):
        self.stats = stats
        self.cpu_stat = cpu_stat
        self.timestamp = timestamp


class SortConfig(object):
    def __init__(self, column, desc=True):
        self.column = column
        self.desc = desc


def read_status(path):
    status = {}
    try:
        with open_text(path) as f:
            for line in f:
                if ":" not in line:
                    continue
                key, val = line.split(":", 1)
                status[key.strip()] = val.strip()
    except (OSError, IOError):
        pass
    return status


def read_system_cpu():
    stat = CPUStat()
    try:
        with open_text("/proc/stat") as f:
            for line in f:
                if not line.startswith("cpu "):
                    continue
                fields = line.split()
                if len(fields) < 8:
                    break
                stat.user = int(fields[1])
                stat.nice = int(fields[2])
                stat.system = int(fields[3])
                stat.idle = int(fields[4])
                stat.iowait = int(fields[5])
                stat.irq = int(fields[6])
                stat.softirq = int(fields[7])
                if len(fields) > 8:
                    stat.steal = int(fields[8])
                if len(fields) > 9:
                    stat.guest = int(fields[9])
                stat.total = (
                    stat.user + stat.nice + stat.system + stat.idle
                    + stat.iowait + stat.irq + stat.softirq + stat.steal
                )
                break
    except (OSError, IOError):
        pass
    return stat


def get_total_memory():
    try:
        with open_text("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    return int(line.split()[1])
    except (OSError, IOError, ValueError, IndexError):
        pass
    return 0


def get_num_cpu():
    try:
        with open_text("/proc/cpuinfo") as f:
            return max(1, sum(1 for line in f if line.startswith("processor")))
    except (OSError, IOError):
        return 1


def parse_stat_fields(path):
    try:
        with open_text(path) as f:
            data = f.read()
    except (OSError, IOError):
        return []
    idx = data.rfind(")")
    if idx == -1:
        return []
    return data[idx + 1:].split()


def read_cpu_stat_data(path, stat):
    rest = parse_stat_fields(path)
    cpu = ProcessCPUStat()
    if len(rest) < 13:
        return cpu
    cpu.utime = int(rest[11])
    cpu.stime = int(rest[12])
    if len(rest) > 14:
        cpu.cutime = int(rest[13])
        cpu.cstime = int(rest[14])
    if len(rest) > 19:
        cpu.starttime = int(rest[19])
    if len(rest) > 38:
        cpu.delayacct_blkio_ticks = int(rest[38])
    if len(rest) > 36:
        try:
            stat.cpu_core = int(rest[36])
        except ValueError:
            stat.cpu_core = 0
    if cpu.utime or cpu.stime:
        stat.time_plus = (cpu.utime + cpu.stime) / float(HZ)
    return cpu


def read_mem_stat(status, stat):
    if "VmSize" in status:
        parts = status["VmSize"].split()
        if parts:
            stat.vsz = int(parts[0])
    if "VmRSS" in status:
        parts = status["VmRSS"].split()
        if parts:
            stat.rss = int(parts[0])
    total = get_total_memory()
    if total > 0 and stat.rss > 0:
        stat.mem = stat.rss / float(total) * 100.0


def read_page_faults(stat_path, stat):
    rest = parse_stat_fields(stat_path)
    if len(rest) > 9:
        stat.minflt = float(rest[7])
        stat.majflt = float(rest[9])


def read_io_stat(path, stat):
    try:
        with open_text(path) as f:
            for line in f:
                if ":" not in line:
                    continue
                key, val = line.split(":", 1)
                key = key.strip()
                val = val.strip()
                if key == "read_bytes":
                    stat.kbrd = int(val) / 1024.0
                elif key == "write_bytes":
                    stat.kbwr = int(val) / 1024.0
                elif key == "cancelled_write_bytes":
                    stat.kbccwr = int(val) / 1024.0
                elif key == "syscr":
                    stat.syscr = float(val)
                elif key == "syscw":
                    stat.syscw = float(val)
    except (OSError, IOError):
        pass


def read_switch_stat(stat_path, stat):
    status_path = stat_path.replace("/stat", "/status")
    status = read_status(status_path)
    if "voluntary_ctxt_switches" in status:
        stat.cswch = float(status["voluntary_ctxt_switches"])
    if "nonvoluntary_ctxt_switches" in status:
        stat.nvcswch = float(status["nonvoluntary_ctxt_switches"])


def _process_rss_kb(status):
    if "VmRSS" not in status:
        return 0
    parts = status["VmRSS"].split()
    if not parts:
        return 0
    try:
        return int(parts[0])
    except ValueError:
        return 0


def _process_cmdline(pid):
    try:
        with open("/proc/{}/cmdline".format(pid), "rb") as f:
            raw = f.read()
    except (OSError, IOError):
        return ""
    return decode_utf8(raw.replace(b"\x00", b" ")).strip()


def _match_process_name(name, status, cmdline_parts):
    if status.get("Name", "").strip() == name:
        return True
    decoded = [decode_utf8(p).strip() for p in cmdline_parts]
    for i, part in enumerate(decoded):
        if not part or part.startswith("-"):
            continue
        if i > 0 and decoded[i - 1] in ("--name", "-n"):
            continue
        if os.path.basename(part) == name:
            return True
    return False


def find_process_candidates(name):
    """Return [(pid, rss_kb, cmd), ...] sorted by RSS descending."""
    results = []
    seen = set()
    try:
        entries = os.listdir("/proc")
    except (OSError, IOError):
        return results
    for entry in entries:
        if not entry.isdigit():
            continue
        pid = int(entry)
        status = read_status(os.path.join("/proc", entry, "status"))
        cmdline_path = os.path.join("/proc", entry, "cmdline")
        try:
            with open(cmdline_path, "rb") as f:
                raw = f.read()
        except (OSError, IOError):
            raw = b""
        parts = raw.split(b"\x00")
        if not _match_process_name(name, status, parts):
            continue
        if pid in seen:
            continue
        seen.add(pid)
        cmd = _process_cmdline(pid)
        if not cmd:
            cmd = status.get("Name", "")
        results.append((pid, _process_rss_kb(status), cmd))
    results.sort(key=lambda item: (-item[1], item[0]))
    return results


def find_process_by_name(name):
    return [pid for pid, _rss, _cmd in find_process_candidates(name)]


def print_process_candidates(name, candidates):
    print("Multiple processes match name {!r}:".format(name), file=sys.stderr)
    print("{:<8} {:>12}  {}".format("PID", "RSS", "COMMAND"), file=sys.stderr)
    for pid, rss, cmd in candidates:
        rss_s = format_memory_size(rss) if rss else "0K"
        print("{:<8} {:>12}  {}".format(pid, rss_s, cmd[:80]), file=sys.stderr)


def resolve_target_pids(process_name, process_id, all_matches, list_only):
    if process_id is not None:
        if not os.path.isdir("/proc/{}".format(process_id)):
            print("Error: process {} not found".format(process_id), file=sys.stderr)
            sys.exit(1)
        return [process_id]

    name = process_name or DEFAULT_PROCESS
    candidates = find_process_candidates(name)
    if not candidates:
        print("Error: process {!r} not found, use --pid or --name".format(name),
              file=sys.stderr)
        sys.exit(1)

    if list_only:
        print_process_candidates(name, candidates)
        sys.exit(0)

    if len(candidates) == 1:
        return [candidates[0][0]]

    print_process_candidates(name, candidates)
    if all_matches:
        print("Monitoring all {} matches (--all-matches).".format(len(candidates)),
              file=sys.stderr)
        return [pid for pid, _rss, _cmd in candidates]

    chosen_pid, chosen_rss, chosen_cmd = candidates[0]
    print("Using PID {} (largest RSS). "
          "Specify --pid, --all-matches, or --list-matches.".format(chosen_pid),
          file=sys.stderr)
    return [chosen_pid]


def should_include_thread(pid, tid, thread_ids, thread_name_regexes):
    if not thread_ids and not thread_name_regexes:
        return True
    if thread_ids:
        return tid in thread_ids
    status = read_status("/proc/{}/task/{}/status".format(pid, tid))
    tname = status.get("Name", "")
    return any(r.search(tname) for r in thread_name_regexes)


def _read_cmd(pid, tid, status, proc_status=None):
    if pid == tid:
        try:
            with open("/proc/{}/cmdline".format(pid), "rb") as f:
                cmd = decode_utf8(f.read().replace(b"\x00", b" ")).strip()
            if cmd:
                return cmd
        except (OSError, IOError):
            pass
    return status.get("Name", proc_status.get("Name", "") if proc_status else "")


def collect_process_stat_data(pid, tid, status, cfg):
    stat = ProcessStats(pid=str(pid), tid=str(tid), tgid=str(pid))
    if "Uid" in status:
        stat.uid = status["Uid"].split()[0]
    stat.cmd = _read_cmd(pid, tid, status)
    stat_path = "/proc/{}/stat".format(tid)
    cpu_stat = read_cpu_stat_data(stat_path, stat)
    if cfg["show_mem"]:
        read_mem_stat(status, stat)
        read_page_faults(stat_path, stat)
    if cfg["show_io"]:
        read_io_stat("/proc/{}/io".format(tid), stat)
    if "Threads" in status:
        stat.threads = int(status["Threads"])
    fd_dir = "/proc/{}/fd".format(stat.pid)
    try:
        stat.fdnr = len(os.listdir(fd_dir))
    except OSError:
        stat.fdnr = 0
    if cfg["show_switch"]:
        read_switch_stat(stat_path, stat)
    return ProcessStatData(stats=stat, cpu_stat=cpu_stat, timestamp=time.time())


def collect_thread_stats_data(pid, tid, proc_status, cfg):
    stat = ProcessStats(pid=str(pid), tid=str(tid), tgid=str(pid))
    status = read_status("/proc/{}/task/{}/status".format(pid, tid))
    if "Uid" in status:
        stat.uid = status["Uid"].split()[0]
    elif "Uid" in proc_status:
        stat.uid = proc_status["Uid"].split()[0]
    stat.cmd = _read_cmd(pid, tid, status, proc_status)
    stat_path = "/proc/{}/task/{}/stat".format(pid, tid)
    cpu_stat = read_cpu_stat_data(stat_path, stat)
    if cfg["show_mem"]:
        read_mem_stat(proc_status, stat)
        read_page_faults(stat_path, stat)
    if cfg["show_io"]:
        read_io_stat("/proc/{}/task/{}/io".format(pid, tid), stat)
    if "Threads" in proc_status:
        stat.threads = int(proc_status["Threads"])
    elif "Threads" in status:
        stat.threads = int(status["Threads"])
    try:
        stat.fdnr = len(os.listdir("/proc/{}/fd".format(stat.pid)))
    except OSError:
        stat.fdnr = 0
    if cfg["show_switch"]:
        read_switch_stat(stat_path, stat)
    return ProcessStatData(stats=stat, cpu_stat=cpu_stat, timestamp=time.time())


def collect_stats_data(pid, cfg):
    data = {}
    proc_dir = "/proc/{}".format(pid)
    if not os.path.isdir(proc_dir):
        return data
    status = read_status(os.path.join(proc_dir, "status"))
    if cfg["thread_mode"]:
        data["P{}".format(pid)] = collect_process_stat_data(pid, pid, status, cfg)
        task_dir = os.path.join(proc_dir, "task")
        try:
            for entry in os.listdir(task_dir):
                if not entry.isdigit():
                    continue
                tid = int(entry)
                if tid == pid:
                    continue
                if should_include_thread(pid, tid, cfg["thread_ids"],
                                         cfg["thread_name_regexes"]):
                    data["T{}".format(tid)] = collect_thread_stats_data(
                        pid, tid, status, cfg)
        except OSError:
            pass
    else:
        data["P{}".format(pid)] = collect_process_stat_data(pid, pid, status, cfg)
    return data


def calculate_cpu_usage(prev, curr, prev_sys, curr_sys):
    if not prev or not curr:
        return
    sys_diff = float(curr_sys.total - prev_sys.total)
    if sys_diff <= 0:
        return
    if (curr.cpu_stat.utime < prev.cpu_stat.utime or
            curr.cpu_stat.stime < prev.cpu_stat.stime):
        return
    ut_diff = float(curr.cpu_stat.utime - prev.cpu_stat.utime)
    st_diff = float(curr.cpu_stat.stime - prev.cpu_stat.stime)
    proc_diff = ut_diff + st_diff
    num_cpu = float(get_num_cpu())
    single = sys_diff / num_cpu
    if single <= 0:
        return
    curr.stats.cpu = proc_diff / single * 100.0
    curr.stats.usr = ut_diff / single * 100.0
    curr.stats.sys = st_diff / single * 100.0
    curr.stats.guest = 0.0
    if curr.cpu_stat.delayacct_blkio_ticks >= prev.cpu_stat.delayacct_blkio_ticks:
        wait_diff = float(curr.cpu_stat.delayacct_blkio_ticks -
                          prev.cpu_stat.delayacct_blkio_ticks)
        curr.stats.wait = wait_diff / single * 100.0
    else:
        curr.stats.wait = 0.0


def _delta_rate(curr_val, prev_val, interval):
    if interval <= 0 or curr_val < prev_val:
        return 0.0
    return (curr_val - prev_val) / interval


def calculate_io_usage(prev, curr, interval):
    curr.kbrd = _delta_rate(curr.kbrd, prev.kbrd, interval)
    curr.kbwr = _delta_rate(curr.kbwr, prev.kbwr, interval)
    curr.kbccwr = _delta_rate(curr.kbccwr, prev.kbccwr, interval)
    curr.riops = _delta_rate(curr.syscr, prev.syscr, interval)
    curr.wiops = _delta_rate(curr.syscw, prev.syscw, interval)


def calculate_switch_usage(prev, curr, interval):
    curr.cswch = _delta_rate(curr.cswch, prev.cswch, interval)
    curr.nvcswch = _delta_rate(curr.nvcswch, prev.nvcswch, interval)


def calculate_page_faults(prev, curr, interval):
    curr.minflt = _delta_rate(curr.minflt, prev.minflt, interval)
    curr.majflt = _delta_rate(curr.majflt, prev.majflt, interval)


def snapshot_cumulative(stats):
    return ProcessStats(
        kbrd=stats.kbrd, kbwr=stats.kbwr, kbccwr=stats.kbccwr,
        syscr=stats.syscr, syscw=stats.syscw,
        cswch=stats.cswch, nvcswch=stats.nvcswch,
        minflt=stats.minflt, majflt=stats.majflt,
    )


def deep_copy_data(data, originals):
    out = {}
    for key, item in data.items():
        orig = originals.get(key, snapshot_cumulative(item.stats))
        out[key] = ProcessStatData(
            stats=ProcessStats(
                uid=item.stats.uid, tgid=item.stats.tgid, tid=item.stats.tid,
                pid=item.stats.pid, usr=item.stats.usr, sys=item.stats.sys,
                guest=item.stats.guest, wait=item.stats.wait, cpu=item.stats.cpu,
                cpu_core=item.stats.cpu_core,
                minflt=orig.minflt, majflt=orig.majflt,
                vsz=item.stats.vsz, rss=item.stats.rss, mem=item.stats.mem,
                kbrd=orig.kbrd, kbwr=orig.kbwr, kbccwr=orig.kbccwr,
                syscr=orig.syscr, syscw=orig.syscw,
                riops=item.stats.riops, wiops=item.stats.wiops,
                threads=item.stats.threads, fdnr=item.stats.fdnr,
                cswch=orig.cswch, nvcswch=orig.nvcswch,
                time_plus=item.stats.time_plus, cmd=item.stats.cmd,
            ),
            cpu_stat=ProcessCPUStat(
                utime=item.cpu_stat.utime, stime=item.cpu_stat.stime,
                cutime=item.cpu_stat.cutime, cstime=item.cpu_stat.cstime,
                starttime=item.cpu_stat.starttime,
                delayacct_blkio_ticks=item.cpu_stat.delayacct_blkio_ticks,
            ),
            timestamp=item.timestamp,
        )
    return out


def get_column_value(stat, column):
    col = column.lower()
    mapping = {
        "usr": stat.usr, "%usr": stat.usr,
        "sys": stat.sys, "%sys": stat.sys,
        "guest": stat.guest, "%guest": stat.guest,
        "wait": stat.wait, "%wait": stat.wait,
        "cpu": stat.cpu, "%cpu": stat.cpu,
        "minflt": stat.minflt, "majflt": stat.majflt,
        "vsz": float(stat.vsz), "rss": float(stat.rss),
        "mem": stat.mem, "%mem": stat.mem,
        "kbrd": stat.kbrd, "kb_rd": stat.kbrd,
        "kbwr": stat.kbwr, "kb_wr": stat.kbwr,
        "kbccwr": stat.kbccwr, "kb_ccwr": stat.kbccwr,
        "threads": float(stat.threads),
        "fdnr": float(stat.fdnr), "fd-nr": float(stat.fdnr),
        "cswch": stat.cswch, "nvcswch": stat.nvcswch,
        "tid": float(stat.tid or 0),
        "pid": float(stat.pid or 0),
        "tgid": float(stat.tgid or 0),
    }
    return mapping.get(col, 0.0)


def sort_data_list(items, sort_configs):
    def sort_key(item):
        keys = []
        for cfg in sort_configs:
            val = get_column_value(item.stats, cfg.column)
            keys.append(-val if cfg.desc else val)
        return tuple(keys)

    items.sort(key=sort_key)


def format_memory_size(kb):
    if kb < 1024:
        return "{}K".format(kb)
    if kb < 1024 * 1024:
        return "{:.2f}M".format(kb / 1024.0)
    return "{:.2f}G".format(kb / (1024.0 * 1024.0))


def format_kb_size(kb):
    if kb < 1024:
        return "{:.2f}K".format(kb)
    if kb < 1024 * 1024:
        return "{:.2f}M".format(kb / 1024.0)
    return "{:.2f}G".format(kb / (1024.0 * 1024.0))


def format_per_second(count):
    if count < 1000:
        return "{:.2f}".format(count)
    if count < 1000000:
        return "{:.2f}K".format(count / 1000.0)
    return "{:.2f}M".format(count / 1000000.0)


def format_time_plus(seconds):
    total_seconds = int(seconds)
    minutes = total_seconds // 60
    secs = total_seconds % 60
    milliseconds = int((seconds - total_seconds) * 100)
    return "{}:{:02d}.{:02d}".format(minutes, secs, milliseconds)


def print_header(thread_mode):
    if thread_mode:
        print("{:<10} {:<4} {:<8} {:<8} {:<6} {:<6} {:<6} {:<6} {:<6} {:<6} "
              "{:<8} {:<8} {:<8} {:<8} {:<8} {:<8} {:<8} {:<8} {:<8} {:<8} "
              "{:<15} {:<5} {:<8} {:<30}".format(
                  "TIME", "UID", "TGID", "TID", "%USR", "%SYS", "%GUEST", "%WAIT",
                  "%CPU", "CPU", "MINFLT", "MAJFLT", "VSZ", "RSS", "%MEM",
                  "KB_RD", "KB_WR", "KB_CCWR", "RIOPS", "WIOPS", "TIME+", "THR",
                  "FD-NR", "COMMAND"))
    else:
        print("{:<10} {:<4} {:<8} {:<6} {:<6} {:<6} {:<6} {:<6} {:<6} "
              "{:<8} {:<8} {:<8} {:<8} {:<8} {:<8} {:<8} {:<8} {:<8} {:<8} "
              "{:<15} {:<5} {:<8} {:<30}".format(
                  "TIME", "UID", "PID", "%USR", "%SYS", "%GUEST", "%WAIT", "%CPU",
                  "CPU", "MINFLT", "MAJFLT", "VSZ", "RSS", "%MEM", "KB_RD", "KB_WR",
                  "KB_CCWR", "RIOPS", "WIOPS", "TIME+", "THR", "FD-NR", "COMMAND"))


def print_stats(time_str, stat, thread_mode):
    vsz = format_memory_size(stat.vsz)
    rss = format_memory_size(stat.rss)
    if thread_mode:
        print("{:<10} {:<4} {:<8} {:<8} {:<6.2f} {:<6.2f} {:<6.2f} {:<6.2f} "
              "{:<6.2f} {:<6} {:<8} {:<8} {:<8} {:<8} {:<8.2f} {:<8} {:<8} "
              "{:<8} {:<8} {:<8} {:<15} {:<5} {:<8} {:<30}".format(
                  time_str, stat.uid, stat.tgid, stat.tid,
                  stat.usr, stat.sys, stat.guest, stat.wait, stat.cpu, stat.cpu_core,
                  format_per_second(stat.minflt), format_per_second(stat.majflt),
                  vsz, rss, stat.mem,
                  format_kb_size(stat.kbrd), format_kb_size(stat.kbwr),
                  format_kb_size(stat.kbccwr),
                  format_per_second(stat.riops), format_per_second(stat.wiops),
                  format_time_plus(stat.time_plus), stat.threads, stat.fdnr,
                  stat.cmd[:30]))
    else:
        print("{:<10} {:<4} {:<8} {:<6.2f} {:<6.2f} {:<6.2f} {:<6.2f} {:<6.2f} "
              "{:<6} {:<8} {:<8} {:<8} {:<8} {:<8.2f} {:<8} {:<8} {:<8} {:<8} "
              "{:<8} {:<15} {:<5} {:<8} {:<30}".format(
                  time_str, stat.uid, stat.pid,
                  stat.usr, stat.sys, stat.guest, stat.wait, stat.cpu, stat.cpu_core,
                  format_per_second(stat.minflt), format_per_second(stat.majflt),
                  vsz, rss, stat.mem,
                  format_kb_size(stat.kbrd), format_kb_size(stat.kbwr),
                  format_kb_size(stat.kbccwr),
                  format_per_second(stat.riops), format_per_second(stat.wiops),
                  format_time_plus(stat.time_plus), stat.threads, stat.fdnr,
                  stat.cmd[:30]))


def collect_stats_data_multi(pids, cfg):
    data = {}
    for pid in pids:
        data.update(collect_stats_data(pid, cfg))
    return data


def build_data_list(curr_data, cfg):
    main_procs = []
    thread_list = []
    for item in curr_data.values():
        if item.stats.tgid == item.stats.tid:
            main_procs.append(item)
        else:
            thread_list.append(item)
    if cfg["sort_configs"] and thread_list:
        sort_data_list(thread_list, cfg["sort_configs"])
    data_list = []
    data_list.extend(main_procs)
    data_list.extend(thread_list)
    return data_list


def run_sample_loop(pids, cfg, interval, count):
    prev_sys = read_system_cpu()
    prev_data = collect_stats_data_multi(pids, cfg)
    loop_count = 0
    interval_sec = float(interval)

    while True:
        time.sleep(interval)
        curr_sys = read_system_cpu()
        curr_data = collect_stats_data_multi(pids, cfg)
        now = time.strftime("%H:%M:%S")

        originals = {k: snapshot_cumulative(v.stats) for k, v in iteritems(curr_data)}

        for key, curr in iteritems(curr_data):
            prev = prev_data.get(key)
            if prev:
                calculate_cpu_usage(prev, curr, prev_sys, curr_sys)
                calculate_io_usage(prev.stats, curr.stats, interval_sec)
                calculate_switch_usage(prev.stats, curr.stats, interval_sec)
                calculate_page_faults(prev.stats, curr.stats, interval_sec)
            else:
                curr.stats.kbrd = curr.stats.kbwr = curr.stats.kbccwr = 0.0
                curr.stats.riops = curr.stats.wiops = 0.0
                curr.stats.cswch = curr.stats.nvcswch = 0.0
                curr.stats.minflt = curr.stats.majflt = 0.0

        data_list = build_data_list(curr_data, cfg)
        print_header(cfg["thread_mode"])
        limit = min(len(data_list), cfg["display_limit"])
        for item in data_list[:limit]:
            print_stats(now, item.stats, cfg["thread_mode"])

        loop_count += 1
        if count > 0 and loop_count >= count:
            if hasattr(sys.stdout, "flush"):
                sys.stdout.flush()
            break

        print()
        if hasattr(sys.stdout, "flush"):
            sys.stdout.flush()

        prev_data = deep_copy_data(curr_data, originals)
        prev_sys = copy.copy(curr_sys)


PROG_NAME = "pidstat.py"


def build_arg_parser():
    parser = argparse.ArgumentParser(
        prog=PROG_NAME,
        description=(
            "Process/thread resource monitoring via /proc (pidstat-like).\n"
            "Default: --name yasdb, 5s interval, continuous sampling; "
            "interval only (no count) also runs continuously."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples (timing like iostat: interval [count]):
  pidstat.py                          # yasdb, every 5s, run until stopped
  pidstat.py 3 3                      # every 3s, 3 samples
  pidstat.py 10                       # every 10s, run until stopped
  pidstat.py --name yasdb 1 5
  pidstat.py --pid 2441 3
  pidstat.py --list-matches
  pidstat.py --all-matches 3 2
  pidstat.py --sort "cpu desc" --limit 20 1 3

Select process with --pid / --name (default yasdb); interval/count are trailing positional args, not PID.
Compatibility: -i / -c still accepted with the same meaning as positional args.
""",
    )
    proc = parser.add_argument_group("Process selection")
    proc.add_argument(
        "-p", "--pid", type=int, default=None, metavar="PID",
        help="Monitor this PID (overrides --name; no name search)",
    )
    proc.add_argument(
        "-n", "--name", default=DEFAULT_PROCESS, metavar="NAME",
        help="Match process by /proc Name or executable basename (default: %(default)s)",
    )
    proc.add_argument(
        "--all-matches", action="store_true",
        help="When name matches multiple processes, monitor all (default: largest RSS only)",
    )
    proc.add_argument(
        "--list-matches", action="store_true",
        help="List matching processes (PID/RSS/COMMAND) and exit without sampling",
    )

    timing = parser.add_argument_group("Sampling interval (positional, like iostat interval [count])")
    timing.add_argument(
        "interval", nargs="?", type=int, default=None, metavar="interval",
        help="Sample interval in seconds (default 5; interval only runs forever)",
    )
    timing.add_argument(
        "count", nargs="?", type=int, default=None, metavar="count",
        help="Number of samples (omit to run forever)",
    )
    # Keep -i/-c for compatibility; hidden from main help listing
    parser.add_argument("-i", "--interval", type=int, default=None, dest="interval_flag",
                        help=argparse.SUPPRESS)
    parser.add_argument("-c", "--count", type=int, default=None, dest="count_flag",
                        help=argparse.SUPPRESS)

    stats = parser.add_argument_group("Metrics (default equivalent to -t -u -r -d)")
    stats.add_argument(
        "-t", "--thread", dest="thread_mode", action="store_true",
        help="Per-thread stats (show TGID/TID; on by default)",
    )
    stats.add_argument(
        "-u", "--cpu", dest="show_cpu", action="store_true",
        help="CPU: %%USR/%%SYS/%%CPU/%%WAIT etc. (on by default)",
    )
    stats.add_argument(
        "-r", "--mem", dest="show_mem", action="store_true",
        help="Memory and faults: VSZ/RSS/%%MEM/MINFLT/MAJFLT (on by default)",
    )
    stats.add_argument(
        "-d", "--io", dest="show_io", action="store_true",
        help="Disk I/O: KB_RD/KB_WR/RIOPS/WIOPS (on by default)",
    )
    stats.add_argument(
        "-w", "--switch", dest="show_switch", action="store_true",
        help="Context switches (voluntary/nonvoluntary; off by default)",
    )
    stats.add_argument(
        "-v", "--proc", dest="show_proc", action="store_true",
        help="Reserved; currently unused",
    )
    stats.add_argument(
        "-s", "--stack", dest="show_stack", action="store_true",
        help="Reserved; currently unused",
    )

    filt = parser.add_argument_group("Filter and display")
    filt.add_argument(
        "--tid", metavar="IDS",
        help="Show only these thread IDs, comma-separated (e.g. 2443,2451)",
    )
    filt.add_argument(
        "--tname", metavar="REGEX",
        help="Show threads whose name matches regex, comma-separated (e.g. DBWR,TIMER)",
    )
    filt.add_argument(
        "--sort", metavar="SPEC",
        help='Sort threads, e.g. "cpu desc,mem asc" (default: cpu desc)',
    )
    filt.add_argument(
        "--limit", "--lines", type=int, default=50, dest="display_limit", metavar="N",
        help="Max rows per sample (default: %(default)s)",
    )
    parser.set_defaults(
        thread_mode=True, show_cpu=True, show_mem=True, show_io=True,
        show_switch=False, show_proc=False, show_stack=False,
    )
    return parser


def parse_args(argv):
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    if args.pid is not None and args.all_matches:
        parser.error("--pid cannot be used with --all-matches")
    if args.pid is not None and args.list_matches:
        parser.error("--pid cannot be used with --list-matches")
    if args.all_matches and args.list_matches:
        parser.error("--all-matches and --list-matches are mutually exclusive")

    interval = DEFAULT_INTERVAL
    if args.interval is not None:
        interval = args.interval
    elif args.interval_flag is not None:
        interval = args.interval_flag
    if interval <= 0:
        parser.error("interval must be positive")

    count_val = -1
    if args.count is not None:
        if args.count <= 0:
            parser.error("count must be positive when specified")
        count_val = args.count
    elif args.count_flag is not None:
        if args.count_flag <= 0:
            parser.error("count must be positive when specified")
        count_val = args.count_flag

    if args.display_limit <= 0:
        parser.error("--limit must be positive")

    cfg = {
        "thread_mode": args.thread_mode,
        "show_cpu": args.show_cpu,
        "show_mem": args.show_mem,
        "show_io": args.show_io,
        "show_proc": args.show_proc,
        "show_switch": args.show_switch,
        "show_stack": args.show_stack,
        "thread_ids": [],
        "thread_name_regexes": [],
        "sort_configs": [SortConfig("cpu", True)],
        "display_limit": args.display_limit,
    }

    if args.tid:
        cfg["thread_ids"] = [int(x.strip()) for x in args.tid.split(",")]
    if args.tname:
        for name in args.tname.split(","):
            cfg["thread_name_regexes"].append(re.compile(name.strip()))
    if args.tid and args.tname:
        parser.error("--tid and --tname cannot be used together")
    if args.sort:
        cfg["sort_configs"] = parse_sort_config(args.sort)

    pids = resolve_target_pids(
        args.name, args.pid, args.all_matches, args.list_matches)
    return cfg, pids, interval, count_val


def parse_sort_config(sort_str):
    configs = []
    for part in sort_str.split(","):
        part = part.strip()
        if not part:
            continue
        fields = part.split()
        column = fields[0].lower()
        desc = True
        if len(fields) > 1:
            desc = fields[1].lower() != "asc"
        configs.append(SortConfig(column, desc))
    return configs


def main():
    if sys.platform != "linux" and not any(
            a in ("-h", "--help") for a in sys.argv[1:]):
        print("Error: pidstat.py requires Linux (/proc)", file=sys.stderr)
        sys.exit(1)

    cfg, pids, interval, count = parse_args(sys.argv[1:])
    if sys.platform != "linux":
        return
    run_sample_loop(pids, cfg, interval, count)


if __name__ == "__main__":
    main()
