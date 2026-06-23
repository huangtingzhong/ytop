#!/usr/bin/env python
# -*- coding: utf-8 -*-
# File Name: para_om_to_ini.py
# Purpose: Generate yasdb.ini from YashanDB OM cod_domor.db (non-default params)
# Created: 20260616  by  huangtingzhong
"""
Generate yasdb.ini from YashanDB OM cod_domor.db (non-default params only).

Requires: Python 2.7+ or 3.x, sqlite3

Default output: /tmp/yashandb_yasdb_ini/<node_name>/yasdb.ini
Default OM db: $YASDB_HOME/om/**/cod_domor.db (auto-discovered)
Default catalog: $YASDB_HOME/om/conf/database_options.json
"""

from __future__ import print_function, division

import argparse
import errno
import io
import json
import os
import re
import sqlite3
import sys

PY3 = sys.version_info[0] >= 3

DEFAULT_OUTPUT_ROOT = "/tmp/yashandb_yasdb_ini"

DERIVED_KEYS = (
    "_CLUSTER_ID",
    "NODE_ID",
    "CONTROL_FILES",
    "DB_FILE_NAME_CONVERT",
    "REDO_FILE_NAME_CONVERT",
    "DB_BUCKET_NAME_CONVERT",
    "ARCHIVE_DEST_1",
)

PRIORITY_KEYS = [
    "_CLUSTER_ID",
    "NODE_ID",
    "CONTROL_FILES",
    "DB_FILE_NAME_CONVERT",
    "REDO_FILE_NAME_CONVERT",
    "DB_BUCKET_NAME_CONVERT",
    "ARCHIVE_DEST_1",
]

BOOL_KEYS = set([
    "USE_NATIVE_TYPE",
    "HA_ELECTION_ENABLED",
    "HA_ELECTION_LEADER_LEASE_ENABLED",
    "OM_ELECTION_ENABLE",
    "ISARCHIVELOG",
])


def text_type(s):
    if s is None:
        return ""
    if PY3 and isinstance(s, bytes):
        return s.decode("utf-8", "replace")
    return s


def norm_key(key):
    return text_type(key).strip().upper()


def norm_value(key, value):
    if value is None:
        return ""
    v = text_type(value).strip()
    k = norm_key(key)
    if k == "CHARACTER_SET" and v.lower() == "utf8":
        return "UTF8"
    if k in BOOL_KEYS and v.lower() in ("true", "false"):
        return v.upper()
    return v


def parse_size(s):
    s = text_type(s).strip().upper()
    m = re.match(r"^(-?\d+(?:\.\d+)?)([KMGT])?$", s)
    if not m:
        return s
    n = float(m.group(1))
    mul = {"K": 1 << 10, "M": 1 << 20, "G": 1 << 30, "T": 1 << 40}.get(
        m.group(2) or "", 1
    )
    return int(n * mul)


def fmt_bytes(n):
    n = int(n)
    for unit, suffix in ((1 << 30, "G"), (1 << 20, "M"), (1 << 10, "K")):
        if n >= unit and n % unit == 0:
            return "{0}{1}".format(n // unit, suffix)
    return str(n)


def catalog_default_str(key, meta):
    default = meta.get("default")
    ptype = meta.get("type", "")
    if ptype == "bytes" and isinstance(default, (int, float)):
        return fmt_bytes(default)
    if ptype == "number":
        if isinstance(default, float) and default == int(default):
            return str(int(default))
        return str(default)
    if meta.get("area") == "TRUE/FALSE":
        return str(default).upper()
    return str(default)


def normalize_for_compare(key, value, catalog):
    k = norm_key(key)
    v = norm_value(k, value)
    if not v:
        return v
    meta = catalog.get(k)
    if meta and meta.get("type") == "bytes":
        if re.match(r"^\d", v):
            parsed = parse_size(v)
            if isinstance(parsed, int):
                return fmt_bytes(parsed)
    return v


def is_cost_default(value):
    v = text_type(value).strip()
    return v in ("-1", "-1.0", "-1.000000") or v.startswith("-1.0")


def is_default_param(key, value, catalog):
    """True if value matches database_options.json default."""
    k = norm_key(key)
    v = text_type(value).strip()
    if not v:
        return True
    if k.startswith("_COST_") or k.startswith("COST_"):
        return is_cost_default(v)
    meta = catalog.get(k)
    if not meta:
        return False
    actual = normalize_for_compare(k, v, catalog)
    expected = normalize_for_compare(k, catalog_default_str(k, meta), catalog)
    return actual == expected


def makedirs(path):
    if os.path.isdir(path):
        return
    try:
        os.makedirs(path)
    except OSError as exc:
        if exc.errno != errno.EEXIST or not os.path.isdir(path):
            raise


def read_text(path):
    with io.open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def write_text(path, content):
    if not PY3 and not isinstance(content, unicode):
        content = content.decode("utf-8")
    with io.open(path, "w", encoding="utf-8") as fh:
        fh.write(content)


def path_join(*parts):
    return os.path.normpath(os.path.join(*parts))


def find_files_by_name(root, filename):
    matches = []
    for dirpath, _dirnames, filenames in os.walk(root):
        if filename in filenames:
            matches.append(os.path.join(dirpath, filename))
    return sorted(matches)


def is_yashandb_data_cod_domor(path):
    parts = path.replace("\\", "/").split("/")
    return len(parts) >= 3 and parts[-2] == "data" and parts[-3] == "yashandb"


def resolve_yasdb_home():
    home = os.environ.get("YASDB_HOME", "").strip()
    if not home:
        raise SystemExit("YASDB_HOME is not set")
    if not os.path.isdir(home):
        raise SystemExit("YASDB_HOME is not a directory: {0}".format(home))
    return home


def find_cod_domor_db(yasdb_home=None):
    """Locate cod_domor.db under $YASDB_HOME/om (recursive)."""
    root = yasdb_home or resolve_yasdb_home()
    om_root = path_join(root, "om")
    if not os.path.isdir(om_root):
        raise SystemExit("om directory not found under YASDB_HOME: {0}".format(om_root))

    matches = find_files_by_name(om_root, "cod_domor.db")
    if not matches:
        raise SystemExit("cod_domor.db not found under {0}".format(om_root))

    if len(matches) == 1:
        return matches[0]

    preferred = [p for p in matches if is_yashandb_data_cod_domor(p)]
    if len(preferred) == 1:
        return preferred[0]

    lines = "\n".join("  {0}".format(p) for p in matches)
    raise SystemExit(
        "multiple cod_domor.db files found under YASDB_HOME/om; "
        "pass path explicitly:\n" + lines
    )


def resolve_cod_domor_db(explicit):
    if explicit:
        path = os.path.abspath(explicit)
        if not os.path.isfile(path):
            raise SystemExit("file not found: {0}".format(path))
        return path
    return find_cod_domor_db()


def resolve_defaults_json(explicit):
    candidates = []
    if explicit:
        candidates.append(os.path.abspath(explicit))
    env_home = os.environ.get("YASDB_HOME", "").strip()
    if env_home:
        candidates.append(path_join(env_home, "om", "conf", "database_options.json"))
    for p in candidates:
        if os.path.isfile(p):
            return p
    raise SystemExit(
        "database_options.json not found; use --defaults-json or set YASDB_HOME"
    )


def load_defaults(path):
    data = json.loads(read_text(path))
    return dict((norm_key(k), v) for k, v in data.items())


def fetch_rows(conn, sql, params=()):
    conn.row_factory = sqlite3.Row
    return conn.execute(sql, params).fetchall()


def row_get(row, name):
    try:
        val = row[name]
    except (IndexError, KeyError):
        return None
    if val is None:
        return None
    if PY3:
        return val
    if isinstance(val, buffer):
        return str(val)
    return val


def load_om(db_path):
    conn = sqlite3.connect(db_path)
    cluster = fetch_rows(
        conn,
        "SELECT uuid, cluster, version FROM yashandb WHERE deleted_at IS NULL LIMIT 1",
    )
    if not cluster:
        raise SystemExit("yashandb cluster record not found in {0}".format(db_path))
    cluster = cluster[0]

    nodes = fetch_rows(
        conn,
        """
        SELECT name, nodeid, hostid, data_path, role
        FROM node
        WHERE deleted_at IS NULL
        ORDER BY name
        """,
    )
    if not nodes:
        raise SystemExit("node table is empty")

    configs = fetch_rows(
        conn,
        """
        SELECT cluster, group_name, node_name, key, value
        FROM yasdb_config
        WHERE deleted_at IS NULL
        ORDER BY id
        """,
    )
    conn.close()
    return cluster, nodes, configs


def build_param_maps(configs):
    cluster_params = {}
    node_params = {}
    for row in configs:
        key = norm_key(row_get(row, "key"))
        val = norm_value(key, row_get(row, "value"))
        node_name = text_type(row_get(row, "node_name")).strip()
        if not node_name:
            cluster_params[key] = val
        else:
            node_params.setdefault(node_name, {})[key] = val
    return cluster_params, node_params


def merge_all_table_params(cluster_params, node_params, target_name, all_node_names):
    merged = dict(cluster_params)
    for name in sorted(all_node_names):
        if name == target_name:
            continue
        for k, v in node_params.get(name, {}).items():
            if k not in merged:
                merged[k] = v
    merged.update(node_params.get(target_name, {}))
    return merged


def control_files(_data_path):
    return "('?/dbfiles/ctrl1', '?/dbfiles/ctrl2', '?/dbfiles/ctrl3')"


def path_convert(peer_path, self_path):
    return "'{0}', '{1}'".format(peer_path, self_path)


def archive_dest(peer_repl, peer_nodeid):
    return "SERVICE={0} NODE_ID={1}".format(peer_repl, peer_nodeid)


def apply_derived_params(params, cluster_uuid, target, nodes, node_params):
    params["_CLUSTER_ID"] = text_type(cluster_uuid)
    params["NODE_ID"] = text_type(row_get(target, "nodeid"))
    params["CONTROL_FILES"] = control_files(row_get(target, "data_path"))

    target_name = row_get(target, "name")
    peers = [n for n in nodes if row_get(n, "name") != target_name]
    if len(peers) == 1:
        peer = peers[0]
        peer_name = row_get(peer, "name")
        peer_cfg = node_params.get(peer_name, {})
        peer_repl = peer_cfg.get("REPLICATION_ADDR")
        if peer_repl:
            params["ARCHIVE_DEST_1"] = archive_dest(
                peer_repl, row_get(peer, "nodeid")
            )
        conv = path_convert(
            row_get(peer, "data_path"), row_get(target, "data_path")
        )
        params["DB_FILE_NAME_CONVERT"] = conv
        params["REDO_FILE_NAME_CONVERT"] = conv
        params["DB_BUCKET_NAME_CONVERT"] = conv


def filter_non_default(params, catalog, include_all):
    if include_all:
        kept = dict((k, v) for k, v in params.items() if v != "")
        return kept, [], []

    kept = {}
    skipped_default = []
    skipped_empty = []

    for k in PRIORITY_KEYS:
        if k in params and params[k] != "":
            kept[k] = params[k]

    for k, v in sorted(params.items()):
        if k in DERIVED_KEYS:
            continue
        if not v:
            skipped_empty.append(k)
            continue
        if is_default_param(k, v, catalog):
            skipped_default.append(k)
            continue
        kept[k] = v

    return kept, skipped_default, skipped_empty


def order_keys(params):
    ordered = []
    for k in PRIORITY_KEYS:
        if k in params:
            ordered.append(k)
    for k in sorted(params):
        if k not in ordered:
            ordered.append(k)
    return ordered


def output_path(root, node_name):
    return path_join(root, node_name, "yasdb.ini")


def generate_ini(db_path, node_name, catalog, include_all=False):
    cluster, nodes, configs = load_om(db_path)
    cluster_params, node_params = build_param_maps(configs)
    all_node_names = [row_get(n, "name") for n in nodes]

    target = None
    for n in nodes:
        if row_get(n, "name") == node_name:
            target = n
            break
    if target is None:
        names = ", ".join(all_node_names)
        raise SystemExit(
            "node {0!r} not found; available: {1}".format(node_name, names)
        )

    params = merge_all_table_params(
        cluster_params, node_params, node_name, all_node_names
    )
    apply_derived_params(
        params, row_get(cluster, "uuid"), target, nodes, node_params
    )

    final, skipped_default, skipped_empty = filter_non_default(
        params, catalog, include_all
    )

    meta = {
        "table_rows": len(configs),
        "merged_keys": len([k for k, v in params.items() if v != ""]),
        "generated_keys": len(final),
        "skipped_default": skipped_default,
        "skipped_empty": skipped_empty,
    }

    lines = ["{0}={1}".format(k, final[k]) for k in order_keys(final)]
    return "\n".join(lines) + "\n", meta


def print_schema_summary(db_path):
    conn = sqlite3.connect(db_path)
    size = os.path.getsize(db_path)
    print("database: {0} ({1} bytes, SQLite)".format(db_path, size))
    for row in conn.execute(
        """
        SELECT COALESCE(NULLIF(node_name,''), '(cluster)') AS scope, COUNT(*) AS cnt
        FROM yasdb_config WHERE deleted_at IS NULL
        GROUP BY scope ORDER BY scope
        """
    ):
        print("  yasdb_config {0}: {1} rows".format(row[0], row[1]))
    conn.close()


def build_arg_parser():
    epilog = """
Environment:
  YASDB_HOME    YashanDB install root. Used to auto-locate:
                  - OM database:  $YASDB_HOME/om/**/cod_domor.db
                  - defaults:     $YASDB_HOME/om/conf/database_options.json

OM database discovery (when --db is omitted):
  1. Require YASDB_HOME to be set and readable.
  2. Search recursively under $YASDB_HOME/om for cod_domor.db.
  3. If exactly one file is found, use it.
  4. If multiple files are found, prefer .../yashandb/data/cod_domor.db.
  5. If ambiguity remains, exit with a list of candidates.

Output layout:
  <output-root>/<node>/yasdb.ini
  Default output-root: /tmp/yashandb_yasdb_ini

Parameter selection (default):
  - Always emit topology keys (_CLUSTER_ID, NODE_ID, CONTROL_FILES,
    ARCHIVE_DEST_1, *_NAME_CONVERT).
  - Emit yasdb_config values that differ from database_options.json defaults.
  - Skip optimizer _COST_* / COST_* entries equal to -1.0.
  - Skip empty values (e.g. TIME_ZONE).
  Use --all-params to include defaults as well.

Examples:
  # On DB host (YASDB_HOME already set), all nodes
  export YASDB_HOME=/data/yashan/yasdb_home/23.4.4.104
  %(prog)s

  # Via ytop on remote host
  ytop -t <host> -f para_om_to_ini.py
  ytop -t <host> -f "para_om_to_ini.py -n 1-1"

  # Explicit OM database path
  %(prog)s --db /home/yashan/.yasboot/yashandb_yasdb_home/om/yashandb/data/cod_domor.db

  # Single node, custom output directory
  %(prog)s -n 1-1 -o /tmp/my_cluster_ini

  # Inspect OM schema only
  %(prog)s --db /path/to/cod_domor.db --summary

  # Full parameter list (including defaults)
  %(prog)s --db /path/to/cod_domor.db --all-params
"""
    p = argparse.ArgumentParser(
        prog="para_om_to_ini.py",
        description=(
            "Generate YashanDB yasdb.ini from OM metadata (cod_domor.db).\n"
            "By default writes non-default parameters per node under /tmp."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=epilog,
    )
    p.add_argument(
        "-d",
        "--db",
        dest="db",
        default=None,
        metavar="PATH",
        help=(
            "path to OM SQLite database cod_domor.db; "
            "if omitted, search under $YASDB_HOME/om"
        ),
    )
    p.add_argument(
        "-n",
        "--node",
        action="append",
        dest="nodes",
        metavar="NAME",
        help="node name from OM node table (e.g. 1-1, 1-2); repeatable; default: all nodes",
    )
    p.add_argument(
        "-o",
        "--output-root",
        default=DEFAULT_OUTPUT_ROOT,
        metavar="DIR",
        help="output root directory (default: {0}); writes <node>/yasdb.ini".format(
            DEFAULT_OUTPUT_ROOT
        ),
    )
    p.add_argument(
        "--defaults-json",
        default=None,
        metavar="PATH",
        help=(
            "path to database_options.json for default-value comparison; "
            "default: $YASDB_HOME/om/conf/database_options.json"
        ),
    )
    p.add_argument(
        "--all-params",
        action="store_true",
        help="write all merged parameters including those equal to product defaults",
    )
    p.add_argument(
        "--summary",
        action="store_true",
        help="print yasdb_config row counts from cod_domor.db and exit (no ini files)",
    )
    return p


def main(argv=None):
    p = build_arg_parser()
    args = p.parse_args(argv)

    db_path = resolve_cod_domor_db(args.db)
    print("OM database: {0}".format(db_path), file=sys.stderr)

    if args.summary:
        print_schema_summary(db_path)
        return 0

    defaults_path = resolve_defaults_json(args.defaults_json)
    catalog = load_defaults(defaults_path)
    print(
        "defaults catalog: {0} ({1} entries)".format(
            defaults_path, len(catalog)
        ),
        file=sys.stderr,
    )

    _, nodes, _ = load_om(db_path)
    targets = args.nodes or [row_get(n, "name") for n in nodes]
    makedirs(args.output_root)

    for name in targets:
        content, meta = generate_ini(
            db_path, name, catalog, include_all=args.all_params
        )
        out = output_path(args.output_root, name)
        makedirs(os.path.dirname(out))
        write_text(out, content)
        mode = "all" if args.all_params else "non-default"
        print(
            "wrote {0} [{1}] merged {2} -> {3} params "
            "(skipped default {4}, empty {5})".format(
                out,
                mode,
                meta["merged_keys"],
                meta["generated_keys"],
                len(meta["skipped_default"]),
                len(meta["skipped_empty"]),
            ),
            file=sys.stderr,
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
