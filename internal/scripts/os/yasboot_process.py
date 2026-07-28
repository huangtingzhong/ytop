#!/usr/bin/env python
# -*- coding: utf-8 -*-
# File Name: yasboot_process.py
# Purpose: Show yasboot cluster and process status for a cluster
# Created: 20260726  by  huangtingzhong
"""
Run yasboot cluster/process status commands.

Cluster name (-c/--cluster):
  - if provided, use it
  - if empty, discover from $YASDB_HOME by matching ~/.yasboot/*.env base_path
    (fallback: ~/.yasboot/<name>_yasdb_home symlink target)

Requires: Python 2.7+ or 3.x, yasboot under $YASDB_HOME/bin
"""
from __future__ import print_function, division

import argparse
import glob
import os
import re
import subprocess
import sys

PY2 = sys.version_info[0] < 3


def eprint(*args):
    print(*args, file=sys.stderr)


def expand_home(path):
    return os.path.expanduser(path)


def norm_path(path):
    if not path:
        return ""
    return os.path.realpath(os.path.expanduser(path)).rstrip("/")


def parse_env_file(path):
    """Parse ~/.yasboot/<cluster>.env style file. Return (cluster, base_path)."""
    cluster = None
    base_path = None
    try:
        with open(path, "r") as f:
            text = f.read()
    except (IOError, OSError) as err:
        eprint("WARN: cannot read %s: %s" % (path, err))
        return None, None
    m = re.search(r'^\s*cluster\s*=\s*"([^"]+)"', text, re.M)
    if m:
        cluster = m.group(1).strip()
    m = re.search(r'^\s*base_path\s*=\s*"([^"]+)"', text, re.M)
    if m:
        base_path = m.group(1).strip()
    return cluster, base_path


def discover_clusters_by_yasdb_home(yasdb_home):
    """Return list of cluster names whose base_path matches yasdb_home."""
    home = norm_path(yasdb_home)
    if not home:
        return []
    found = []
    yasboot_dir = expand_home("~/.yasboot")
    for env_path in sorted(glob.glob(os.path.join(yasboot_dir, "*.env"))):
        cluster, base_path = parse_env_file(env_path)
        if not cluster:
            continue
        if norm_path(base_path) == home and cluster not in found:
            found.append(cluster)
    if found:
        return found
    # Fallback: symlink ~/.yasboot/<cluster>_yasdb_home -> YASDB_HOME
    for link in sorted(glob.glob(os.path.join(yasboot_dir, "*_yasdb_home"))):
        if not os.path.exists(link):
            continue
        target = norm_path(link)
        if target != home:
            continue
        name = os.path.basename(link)
        if name.endswith("_yasdb_home"):
            name = name[: -len("_yasdb_home")]
        if name and name not in found:
            found.append(name)
    return found


def resolve_cluster(cli_cluster, yasdb_home):
    """Resolve cluster name from CLI or $YASDB_HOME discovery."""
    if cli_cluster:
        return cli_cluster.strip()
    if not yasdb_home:
        eprint("ERROR: cluster not set and YASDB_HOME is empty; export YASDB_HOME or pass -c")
        return None
    matches = discover_clusters_by_yasdb_home(yasdb_home)
    if not matches:
        eprint("ERROR: no cluster found for YASDB_HOME=%s under ~/.yasboot" % yasdb_home)
        return None
    if len(matches) > 1:
        eprint("ERROR: multiple clusters match YASDB_HOME=%s: %s" % (yasdb_home, ", ".join(matches)))
        eprint("Pass -c/--cluster to select one")
        return None
    return matches[0]


def resolve_yasboot(yasdb_home):
    """Prefer $YASDB_HOME/bin/yasboot, else PATH."""
    if yasdb_home:
        cand = os.path.join(norm_path(yasdb_home), "bin", "yasboot")
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    # PATH lookup
    path_env = os.environ.get("PATH", "")
    for d in path_env.split(os.pathsep):
        if not d:
            continue
        cand = os.path.join(d, "yasboot")
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return None


def run_cmd(argv):
    """Run command, stream output, return exit code."""
    print("")
    print("===== %s =====" % " ".join(argv))
    sys.stdout.flush()
    try:
        p = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except OSError as err:
        eprint("ERROR: failed to start %s: %s" % (argv[0], err))
        return 127
    out, _ = p.communicate()
    if out:
        if PY2 and isinstance(out, str):
            sys.stdout.write(out)
        else:
            if not isinstance(out, str):
                out = out.decode("utf-8", "replace")
            sys.stdout.write(out)
        if not out.endswith("\n"):
            print("")
        sys.stdout.flush()
    return p.returncode if p.returncode is not None else 1


def build_commands(yasboot, cluster):
    return [
        [yasboot, "cluster", "status", "-c", cluster, "-d"],
        [yasboot, "process", "yasdb", "status", "-c", cluster],
        [yasboot, "process", "yasagent", "status", "-c", cluster],
        [yasboot, "process", "yasom", "status", "-c", cluster],
        [yasboot, "process", "monit", "status", "-c", cluster],
    ]


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Show yasboot cluster and process status",
    )
    parser.add_argument(
        "-c",
        "--cluster",
        default="",
        help="yasdb cluster name; empty = discover via $YASDB_HOME",
    )
    args = parser.parse_args(argv)

    yasdb_home = os.environ.get("YASDB_HOME", "").strip()
    cluster = resolve_cluster(args.cluster, yasdb_home)
    if not cluster:
        return 2

    yasboot = resolve_yasboot(yasdb_home)
    if not yasboot:
        eprint("ERROR: yasboot not found; set YASDB_HOME or put yasboot in PATH")
        return 2

    print("YASDB_HOME=%s" % (yasdb_home or "(unset)"))
    print("cluster=%s" % cluster)
    print("yasboot=%s" % yasboot)

    worst = 0
    for cmd in build_commands(yasboot, cluster):
        rc = run_cmd(cmd)
        if rc != 0 and worst == 0:
            worst = rc
    return worst


if __name__ == "__main__":
    sys.exit(main())
