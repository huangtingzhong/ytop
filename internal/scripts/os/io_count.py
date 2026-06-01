#!/usr/bin/env python3
# File Name: io_count.py
# Purpose: Strace IO syscalls and latency histogram
# Created: 20260517  by  huangtingzhong
import argparse
import subprocess
import time
import re
import datetime
import platform
import sys

# Latency buckets (milliseconds)
buckets = [
    (0, 0.1), (0.1, 0.5), (0.5, 1), (1, 2), (2, 3),
    (3, 4), (4, 5), (5, 8), (8, 15), (15, 30), (30, float("inf"))
]
bucket_labels = [
    "0-0.1ms", "0.1-0.5ms", "0.5-1ms", "1-2ms", "2-3ms",
    "3-4ms", "4-5ms", "5-8ms", "8-15ms", "15-30ms", ">30ms"
]
io_types = ['read', 'write', 'pread64', 'pwrite64', 'open', 'openat',
            'close', 'fsync', 'fdatasync', 'lseek', 'fallocate',
            'sync_file_range', 'mmap', 'munmap', 'msync']

def log(msg):
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"{timestamp} | {msg}")

def parse_args():
    parser = argparse.ArgumentParser(description='Trace and analyze IO syscalls.')
    parser.add_argument('-p', '--pid', type=int, required=True, help='Target process ID')
    parser.add_argument('-t', '--time', type=int, required=True, help='strace duration in seconds')
    parser.add_argument('-f', '--file', default='/tmp/strace_io.log', help='strace output file')
    return parser.parse_args()

def run_strace(pid, duration, log_path):
    cmd = [
        'strace', '-tt', '-T',
        '-e', 'trace=' + ','.join(io_types),
        '-p', str(pid),
        '-o', log_path
    ]
    proc = subprocess.Popen(cmd)
    log(f"Start strace on PID {pid}, duration: {duration}s, output: {log_path}")
    time.sleep(duration)
    proc.terminate()
    proc.wait()
    log("Strace process terminated. Starting log analysis...")

def bucket_index(duration_ms):
    for i, (start, end) in enumerate(buckets):
        if start <= duration_ms < end:
            return i
    return len(buckets) - 1

def parse_log(log_file):
    stats = {io: [0]*len(buckets) for io in io_types}
    total_time = {io: 0.0 for io in io_types}
    total_count = {io: 0 for io in io_types}

    syscall_pattern = re.compile(r"(\d+\:\d+\:\d+\.\d+)\s+([a-z0-9_]+)\(.*?\)\s+=.*?<([\d\.]+)>")

    with open(log_file, 'r') as f:
        for line in f:
            match = syscall_pattern.search(line)
            if not match:
                continue
            syscall = match.group(2)
            duration_sec = float(match.group(3))
            duration_ms = duration_sec * 1000
            if syscall not in stats:
                continue
            idx = bucket_index(duration_ms)
            stats[syscall][idx] += 1
            total_time[syscall] += duration_ms
            total_count[syscall] += 1

    return stats, total_time, total_count

def show_report(stats, total_time, total_count):
    for syscall in sorted(stats.keys()):
        count = total_count[syscall]
        if count == 0:
            continue
        log(f"IO Type: {syscall}")
        print(f"{'Range':<12}{'Count':<8}{'Total(ms)':<12}{'Avg(ms)':<10}{'Percent':<10}")
        for i in range(len(buckets)):
            c = stats[syscall][i]
            if c == 0:
                continue
            total_ms = total_time[syscall]
            bucket_time = (total_ms * c / count)
            avg_time = bucket_time / c
            percent = (c / count) * 100
            print(f"{bucket_labels[i]:<12}{c:<8}{bucket_time:<12.2f}{avg_time:<10.2f}{percent:<.2f}%")
        print("-" * 60)

def main():
    if platform.system().lower() != 'linux':
        log("Error: Only Linux is supported.")
        sys.exit(1)

    args = parse_args()
    log("Script started.")
    run_strace(args.pid, args.time, args.file)
    stats, total_time, total_count = parse_log(args.file)
    log("Log analysis completed. Report:")
    show_report(stats, total_time, total_count)
    log("Script finished.")

if __name__ == '__main__':
    main()
