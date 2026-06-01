#!/usr/bin/env python3
"""Verify Pid/Ord from pasted plan output against v$sql_plan tree walk."""
import re
import sys
from collections import defaultdict

# Pasted plan lines: |  id| pid| ord|...
LINE_RE = re.compile(r"^\|\s*(\d+)\|\s*(\d+|\s+)\|\s*(\d+)\|")

def parse_pasted(text: str) -> dict[int, tuple[int | None, int]]:
    out = {}
    for line in text.splitlines():
        m = LINE_RE.match(line)
        if not m:
            continue
        nid = int(m.group(1))
        pid = None if not m.group(2).strip() else int(m.group(2))
        ord_ = int(m.group(3))
        out[nid] = (pid, ord_)
    return out


def resolve_display_pid(
    nid: int,
    pid: int | None,
    op: str,
    rows: list[tuple[int, int | None, str, str]],
) -> int | None:
    """Match PL/SQL resolve_display_pid for INDEX + TABLE ACCESS BY INDEX ROWID."""
    if pid is None or not op.startswith("INDEX"):
        return pid
    tab_id = None
    for rid, rpid, rop, ropt in rows:
        if rpid != pid or rid >= nid:
            continue
        if "BY INDEX ROWID" in rop or "INDEX ROWID" in (ropt or ""):
            tab_id = max(tab_id or 0, rid)
    return tab_id if tab_id is not None else pid


def compute_ord(
    rows: list[tuple[int, int | None]],
    parent_map: dict[int, int | None] | None = None,
    pos_map: dict[int, int] | None = None,
) -> dict[int, int]:
    """Oracle: post-order on display tree; siblings by position/id ASC (left-top first)."""
    if parent_map is None:
        parent_map = {nid: pid for nid, pid in rows}
    children: dict[int, list[int]] = defaultdict(list)
    ids = set(parent_map)
    for nid, pid in parent_map.items():
        if pid is not None:
            children[pid].append(nid)

    def sib_key(nid: int) -> tuple[int, int]:
        return (pos_map.get(nid, 0) if pos_map else 0, nid)

    for pid in children:
        children[pid].sort(key=sib_key)

    ord_map: dict[int, int] = {}
    counter = 0

    def walk(parent: int):
        nonlocal counter
        for cid in children.get(parent, []):
            walk(cid)
            counter += 1
            ord_map[cid] = counter

    walk(0)
    if 0 in ids:
        counter += 1
        ord_map[0] = counter
    return ord_map


def main():
    # rows from stdin: id,parent_id[,operation,options] per line (parent empty = root)
    rows_raw = []
    rows_full = []
    for line in sys.stdin:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(",")
        nid = int(parts[0])
        pid = int(parts[1]) if len(parts) > 1 and parts[1] else None
        op = parts[2] if len(parts) > 2 else ""
        opt = parts[3] if len(parts) > 3 else ""
        rows_raw.append((nid, pid))
        rows_full.append((nid, pid, op, opt))

    use_display = "--display-pid" in sys.argv
    pid_db = {nid: pid for nid, pid in rows_raw}
    if use_display and rows_full:
        pid_db = {
            nid: resolve_display_pid(nid, pid, op, rows_full)
            for nid, pid, op, opt in rows_full
        }
    ord_exp = compute_ord(rows_raw, pid_db if use_display else None)

    cli_args = [a for a in sys.argv[1:] if a != "--display-pid"]
    pasted_path = cli_args[0] if cli_args else None
    if pasted_path:
        pasted = parse_pasted(open(pasted_path, encoding="utf-8").read())
    else:
        pasted = {}

    pid_mismatch = []
    ord_mismatch = []
    missing_in_paste = []
    for nid, pid in rows_raw:
        if nid not in pasted:
            missing_in_paste.append(nid)
            continue
        ppid, pord = pasted[nid]
        if ppid != pid:
            pid_mismatch.append((nid, pid, ppid))
        if ord_exp.get(nid) != pord:
            ord_mismatch.append((nid, ord_exp.get(nid), pord))

    extra_in_paste = set(pasted) - {nid for nid, _ in rows_raw}

    print(f"db_nodes={len(rows_raw)} pasted_nodes={len(pasted)}")
    print(f"ord_range_expected=1..{max(ord_exp.values()) if ord_exp else 0}")
    print(f"pid_mismatch={len(pid_mismatch)} ord_mismatch={len(ord_mismatch)}")
    print(f"missing_in_paste={len(missing_in_paste)} extra_in_paste={len(extra_in_paste)}")

    if pid_mismatch:
        print("\nPID mismatches (first 10):")
        for x in pid_mismatch[:10]:
            print(f"  id={x[0]} db_pid={x[1]} paste_pid={x[2]}")
    if ord_mismatch:
        print("\nORD mismatches (first 10):")
        for x in ord_mismatch[:10]:
            print(f"  id={x[0]} expected_ord={x[1]} paste_ord={x[2]}")

    # Tree sanity: every non-root pid must exist
    bad_pid_ref = [nid for nid, pid in rows_raw if pid is not None and pid not in pid_db]
    print(f"invalid_pid_ref={len(bad_pid_ref)}")

    ok = (
        not pid_mismatch
        and not ord_mismatch
        and not missing_in_paste
        and not extra_in_paste
        and not bad_pid_ref
    )
    print("RESULT:", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
