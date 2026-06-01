#!/usr/bin/env python3
# File Name: iotop.py
# Purpose: Show per-process disk read write rates
# Created: 20260517  by  huangtingzhong
import os
import time
import pwd
import argparse
from datetime import datetime

def read_io(pid):
    try:
        with open(f"/proc/{pid}/io") as f:
            data = {}
            for line in f:
                key, val = line.strip().split(": ")
                data[key] = int(val)
            return data["read_bytes"], data["write_bytes"]
    except:
        return 0, 0

def get_username(uid):
    try:
        return pwd.getpwuid(uid).pw_name
    except:
        return str(uid)

def get_uid(pid):
    try:
        stat = os.stat(f"/proc/{pid}")
        return stat.st_uid
    except:
        return 0

def get_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline") as f:
            return f.read().replace('\x00', ' ').strip()
    except:
        return ""

def list_pids():
    return [pid for pid in os.listdir("/proc") if pid.isdigit()]

def parse_args():
    parser = argparse.ArgumentParser(
        description="Simple iotop-like tool (no kernel module required)",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument('-s', '--sort', choices=['read', 'write'], default='read',
                        help='Sort by read or write KB/s')
    parser.add_argument('-u', '--user', help='Filter by username')
    parser.add_argument('-t', '--top', type=int, default=10, help='Show top N lines')
    parser.add_argument('-n', '--interval', type=int, default=2, help='Interval between checks in seconds')
    parser.add_argument('-c', '--count', type=int, help='Number of samples to collect before exit')
    return parser.parse_args()

def main():
    args = parse_args()
    prev_io = {}
    counter = 0

    while True:
        time.sleep(args.interval)
        os.system("clear")

        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"{'TIME':<19} {'PID':>6} {'USER':>8} {'READ KB/s':>10} {'WRITE KB/s':>11} COMMAND")

        results = []
        for pid in list_pids():
            read1, write1 = read_io(pid)
            if pid not in prev_io:
                prev_io[pid] = (read1, write1)
                continue
            read0, write0 = prev_io[pid]
            prev_io[pid] = (read1, write1)

            delta_read = (read1 - read0) / 1024 / args.interval
            delta_write = (write1 - write0) / 1024 / args.interval

            uid = get_uid(pid)
            user = get_username(uid)

            if args.user and user != args.user:
                continue

            if delta_read > 0.1 or delta_write > 0.1:
                cmd = get_cmdline(pid)
                results.append((pid, user, delta_read, delta_write, cmd))

        if args.sort == 'read':
            results.sort(key=lambda x: x[2], reverse=True)
        else:
            results.sort(key=lambda x: x[3], reverse=True)

        for row in results[:args.top]:
            pid, user, read_kb, write_kb, cmd = row
            print(f"{now:<19} {pid:>6} {user:>8} {read_kb:10.2f} {write_kb:11.2f} {cmd[:60]}")

        counter += 1
        if args.count and counter >= args.count:
            break

if __name__ == "__main__":
    main()
