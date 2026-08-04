#!/usr/bin/env python3
# File Name: yasql_parallel.py
# Purpose: Parallel yasql runner with done and result logs
# Created: 20260802  by  huangtingzhong
"""
Read SQL statements from a file, execute them via yasql with configurable
parallelism, append finished SQL to a done file for tracking, and optionally
save each statement's yasql output to its own result file.

Delimiter modes:
  semicolon (default)  split on ';' outside quotes/comments
  slash                split on a line that is only '/'

ALTER SESSION SET CURRENT_SCHEMA:
  When seen, later statements are executed with that ALTER prepended
  (each yasql call is a new session).

--global-fail (default false):
  On first failure, stop submitting new work; still wait for in-flight
  workers to finish, then exit.

--pre-sql (default empty, repeatable):
  Custom SQL run before every statement. Multiple values supported via
  repeated --pre-sql and/or ';' inside one value.
  Prefix order: pre-sql(s) -> CURRENT_SCHEMA (if any) -> statement.

Examples:
  python3 yasql_parallel.py -f stmts.sql -c "/ as sysdba" -p 4
  python3 yasql_parallel.py -f stmts.sql -d slash -p 8 --save-result
  python3 yasql_parallel.py -f stmts.sql --global-fail -p 4
  python3 yasql_parallel.py -f stmts.sql --pre-sql "SELECT 1 FROM dual"
  python3 yasql_parallel.py -f stmts.sql --pre-sql "ALTER SESSION SET CURRENT_SCHEMA=HR" --pre-sql "SELECT 1 FROM dual"
"""

from __future__ import print_function

import argparse
import datetime as dt
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait

PY2 = sys.version_info[0] < 3

# ALTER SESSION SET CURRENT_SCHEMA = name | "name" | 'name'
_CURRENT_SCHEMA_RE = re.compile(
    r"^\s*ALTER\s+SESSION\s+SET\s+CURRENT_SCHEMA\s*=\s*"
    r"(?:\"([^\"]+)\"|'([^']+)'|([A-Za-z0-9_$#]+))\s*;?\s*$",
    re.IGNORECASE | re.DOTALL,
)


def eprint(*args):
    sys.stderr.write(" ".join(str(a) for a in args) + "\n")


def now_iso():
    return dt.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


def which(cmd):
    path = os.environ.get("PATH", "")
    for d in path.split(os.pathsep):
        p = os.path.join(d, cmd)
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def resolve_yasql(yasql_arg):
    if yasql_arg:
        if os.path.isfile(yasql_arg) and os.access(yasql_arg, os.X_OK):
            return yasql_arg
        raise SystemExit("yasql not found: {}".format(yasql_arg))
    home = os.environ.get("YASDB_HOME", "").strip()
    if home:
        p = os.path.join(home, "bin", "yasql")
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    p = which("yasql")
    if p:
        return p
    raise SystemExit("yasql not found; set YASDB_HOME or pass --yasql")


def build_env():
    env = os.environ.copy()
    home = env.get("YASDB_HOME", "").strip()
    if home:
        lib = os.path.join(home, "lib")
        bin_dir = os.path.join(home, "bin")
        env["YASDB_HOME"] = home
        old_ld = env.get("LD_LIBRARY_PATH", "")
        env["LD_LIBRARY_PATH"] = lib + ((":" + old_ld) if old_ld else "")
        env["PATH"] = bin_dir + ":" + env.get("PATH", "")
    return env


# ---------------------------------------------------------------------------
# SQL splitters
# ---------------------------------------------------------------------------

def split_by_slash(text):
    """Split on a line that contains only '/' (optional surrounding whitespace)."""
    stmts = []
    buf = []
    for line in text.splitlines(True):
        if line.strip() == "/":
            body = "".join(buf).strip()
            if body:
                stmts.append(body)
            buf = []
        else:
            buf.append(line)
    tail = "".join(buf).strip()
    if tail:
        stmts.append(tail)
    return stmts


def split_by_semicolon(text):
    """
    Split on ';' outside single/double quotes and outside -- / /* */ comments.
    Keeps statement text without the trailing ';'.
    """
    stmts = []
    buf = []
    i = 0
    n = len(text)
    in_squote = False
    in_dquote = False
    in_line_comment = False
    in_block_comment = False

    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""

        if in_line_comment:
            buf.append(ch)
            if ch == "\n":
                in_line_comment = False
            i += 1
            continue

        if in_block_comment:
            buf.append(ch)
            if ch == "*" and nxt == "/":
                buf.append(nxt)
                i += 2
                in_block_comment = False
                continue
            i += 1
            continue

        if in_squote:
            buf.append(ch)
            if ch == "'" and nxt == "'":
                buf.append(nxt)
                i += 2
                continue
            if ch == "'":
                in_squote = False
            i += 1
            continue

        if in_dquote:
            buf.append(ch)
            if ch == '"' and nxt == '"':
                buf.append(nxt)
                i += 2
                continue
            if ch == '"':
                in_dquote = False
            i += 1
            continue

        # not in quote/comment
        if ch == "-" and nxt == "-":
            buf.append(ch)
            buf.append(nxt)
            i += 2
            in_line_comment = True
            continue
        if ch == "/" and nxt == "*":
            buf.append(ch)
            buf.append(nxt)
            i += 2
            in_block_comment = True
            continue
        if ch == "'":
            buf.append(ch)
            in_squote = True
            i += 1
            continue
        if ch == '"':
            buf.append(ch)
            in_dquote = True
            i += 1
            continue
        if ch == ";":
            body = "".join(buf).strip()
            if body and not _is_comment_only(body):
                stmts.append(body)
            buf = []
            i += 1
            continue

        buf.append(ch)
        i += 1

    tail = "".join(buf).strip()
    if tail and not _is_comment_only(tail):
        stmts.append(tail)
    return stmts


_COMMENT_ONLY_RE = re.compile(
    r"^(?:\s|--[^\n]*|/\*.*?\*/)*$",
    re.DOTALL,
)


def _is_comment_only(text):
    if not text.strip():
        return True
    # strip line/block comments; if nothing remains, treat as empty
    s = text
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.DOTALL)
    lines = []
    for line in s.splitlines():
        if line.strip().startswith("--"):
            continue
        lines.append(line)
    return "".join(lines).strip() == ""


def load_statements(path, delimiter):
    with open(path, "r") as f:
        text = f.read()
    if delimiter == "slash":
        stmts = split_by_slash(text)
    else:
        stmts = split_by_semicolon(text)
    out = []
    for s in stmts:
        s = s.strip()
        if s and not _is_comment_only(s):
            out.append(s)
    return out


def parse_current_schema(stmt):
    """
    If stmt is ALTER SESSION SET CURRENT_SCHEMA=..., return normalized ALTER text.
    Otherwise return None.
    """
    m = _CURRENT_SCHEMA_RE.match(stmt.strip())
    if not m:
        return None
    dq, sq, bare = m.group(1), m.group(2), m.group(3)
    if dq is not None:
        return 'ALTER SESSION SET CURRENT_SCHEMA = "{}"'.format(dq.replace('"', '""'))
    if sq is not None:
        return "ALTER SESSION SET CURRENT_SCHEMA = '{}'".format(sq.replace("'", "''"))
    if bare:
        return "ALTER SESSION SET CURRENT_SCHEMA = {}".format(bare)
    return None


def normalize_pre_sqls(values):
    """
    Flatten --pre-sql values into a list of statements.
    Empty / whitespace-only ignored. Each value may contain multiple
    statements separated by ';' (quote/comment aware).
    """
    if not values:
        return []
    out = []
    for raw in values:
        if raw is None:
            continue
        text = str(raw).strip()
        if not text:
            continue
        if ";" in text:
            parts = split_by_semicolon(text)
        else:
            parts = [text]
        for p in parts:
            p = p.strip()
            if p and not _is_comment_only(p):
                # strip one trailing slash delimiter if user pasted slash-style
                if p.endswith("/") and p[:-1].strip():
                    # only treat trailing lone / line as delimiter remnant
                    lines = p.splitlines()
                    if lines and lines[-1].strip() == "/":
                        p = "\n".join(lines[:-1]).strip()
                if p:
                    out.append(p)
    return out


def join_sql_parts(parts):
    """Join SQL fragments with ';\\n', skipping empties."""
    cleaned = []
    for p in parts:
        if not p:
            continue
        s = p.rstrip()
        if s.endswith(";"):
            s = s[:-1].rstrip()
        if s:
            cleaned.append(s)
    return ";\n".join(cleaned)


def build_jobs(stmts, pre_sqls=None):
    """
    Build execution jobs with pre-sql + CURRENT_SCHEMA propagation.

    Each job: (idx, orig_sql, exec_sql, schema_sql_or_none)
    Prefix order on every statement:
      pre_sqls -> CURRENT_SCHEMA (if active / for schema stmt itself) -> stmt
    """
    pre_sqls = list(pre_sqls or [])
    jobs = []
    active_schema = None
    for i, stmt in enumerate(stmts, 1):
        schema_stmt = parse_current_schema(stmt)
        if schema_stmt is not None:
            active_schema = schema_stmt
            # ALTER itself: pre_sqls + this schema alter (no previous schema).
            exec_sql = join_sql_parts(pre_sqls + [schema_stmt])
            jobs.append((i, stmt, exec_sql, active_schema))
            continue
        parts = list(pre_sqls)
        if active_schema:
            parts.append(active_schema)
        parts.append(stmt)
        exec_sql = join_sql_parts(parts)
        jobs.append((i, stmt, exec_sql, active_schema))
    return jobs


# ---------------------------------------------------------------------------
# Done / result writers
# ---------------------------------------------------------------------------

class Tracker(object):
    def __init__(self, done_path, fail_path, result_dir, save_result):
        self.done_path = done_path
        self.fail_path = fail_path
        self.result_dir = result_dir
        self.save_result = save_result
        self._lock = threading.Lock()
        self.ok = 0
        self.fail = 0
        self.skip = 0

        done_dir = os.path.dirname(os.path.abspath(done_path))
        if done_dir and not os.path.isdir(done_dir):
            os.makedirs(done_dir)
        fail_dir = os.path.dirname(os.path.abspath(fail_path))
        if fail_dir and not os.path.isdir(fail_dir):
            os.makedirs(fail_dir)
        if save_result:
            if not os.path.isdir(result_dir):
                os.makedirs(result_dir)

        with open(done_path, "a") as f:
            f.write("\n-- ===== session start {} =====\n".format(now_iso()))
        with open(fail_path, "a") as f:
            f.write("\n-- ===== session start {} =====\n".format(now_iso()))

    def record(self, idx, total, orig_sql, exec_sql, ok, elapsed, output, returncode, skipped=False):
        if skipped:
            status = "SKIP"
        elif ok:
            status = "OK"
        else:
            status = "FAIL"
        banner = (
            "-- ===== #{:04d}/{:04d} {} status={} rc={} elapsed={:.3f}s =====\n"
            .format(idx, total, now_iso(), status, returncode, elapsed)
        )
        block = banner + orig_sql.rstrip() + "\n;\n\n"

        with self._lock:
            if skipped:
                self.skip += 1
                with open(self.fail_path, "a") as f:
                    f.write(block)
                    f.write("-- skipped due to --global-fail\n\n")
            elif ok:
                self.ok += 1
                with open(self.done_path, "a") as f:
                    f.write(block)
            else:
                self.fail += 1
                with open(self.fail_path, "a") as f:
                    f.write(block)
                    f.write("-- stderr/stdout --\n")
                    f.write((output or "").rstrip() + "\n\n")

            if self.save_result:
                name = "{:04d}.{}.out".format(
                    idx, "skip" if skipped else ("ok" if ok else "fail"),
                )
                path = os.path.join(self.result_dir, name)
                with open(path, "w") as f:
                    f.write(banner)
                    f.write("-- SQL (original) --\n")
                    f.write(orig_sql.rstrip() + "\n;\n\n")
                    if exec_sql and exec_sql.strip() != orig_sql.strip():
                        f.write("-- SQL (executed) --\n")
                        f.write(exec_sql.rstrip() + "\n;\n\n")
                    f.write("-- OUTPUT --\n")
                    f.write(output or "")
                    if output and not output.endswith("\n"):
                        f.write("\n")


# ---------------------------------------------------------------------------
# Execute one statement
# ---------------------------------------------------------------------------

def run_one(yasql, connect, env, sql, timeout, work_dir, idx):
    """
    Run one SQL via yasql using a temp script file.
    Returns (ok, elapsed, output, returncode).
    """
    body = sql.rstrip()
    if not body.endswith(";") and not body.endswith("/"):
        body = body + "\n;"

    fd, path = tempfile.mkstemp(prefix="yasql_p_{:04d}_".format(idx), suffix=".sql", dir=work_dir)
    os.close(fd)
    try:
        with open(path, "w") as f:
            # Minimal settings; avoid unsupported SET options (YASQL-00008)
            f.write("SET FEEDBACK ON\n")
            f.write(body)
            f.write("\n")

        argv = [yasql, "-S", connect, "@" + path]
        t0 = time.time()
        try:
            # New session so timeout can kill the whole process group
            # (yasql/shell wrappers often spawn children that keep pipes open).
            popen_kwargs = dict(
                args=argv,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                env=env,
                universal_newlines=True,
            )
            try:
                proc = subprocess.Popen(start_new_session=True, **popen_kwargs)
            except TypeError:
                # Python 3.6 may need preexec_fn
                popen_kwargs["preexec_fn"] = os.setsid
                proc = subprocess.Popen(**popen_kwargs)

            try:
                out, _ = proc.communicate(timeout=timeout if timeout and timeout > 0 else None)
            except subprocess.TimeoutExpired:
                _kill_process_tree(proc)
                try:
                    out, _ = proc.communicate(timeout=5)
                except Exception:
                    out = ""
                elapsed = time.time() - t0
                msg = (out or "") + "\n[timeout after {}s]\n".format(timeout)
                return False, elapsed, msg, -9
            elapsed = time.time() - t0
            rc = proc.returncode
            out = out or ""
            sql_err = _looks_like_sql_error(out)
            ok = (rc == 0) and (not sql_err)
            return ok, elapsed, out, rc
        except OSError as exc:
            elapsed = time.time() - t0
            return False, elapsed, "failed to start yasql: {}\n".format(exc), -1
    finally:
        try:
            os.remove(path)
        except OSError:
            pass


def _kill_process_tree(proc):
    """Kill process group first, then the process itself as fallback."""
    if proc.poll() is not None:
        return
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except (OSError, ProcessLookupError):
        try:
            proc.kill()
        except OSError:
            pass


_ERR_MARKERS = (
    "YAS-",
    "YASQL-",
    "ORA-",
    "SP2-",
    "ERROR at line",
    "type convert error",
)


def _looks_like_sql_error(text):
    if not text:
        return False
    upper = text.upper()
    for m in _ERR_MARKERS:
        if m.upper() in upper:
            return True
    return False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def parse_args(argv):
    p = argparse.ArgumentParser(
        description="Parallel yasql runner with done-file tracking and optional per-SQL results",
    )
    p.add_argument("-f", "--file", required=True, help="Input SQL file")
    p.add_argument(
        "-c", "--connect", default="/ as sysdba",
        help='yasql connect string (default: "/ as sysdba")',
    )
    p.add_argument("-p", "--parallel", type=int, default=1, help="Parallel workers (default: 1)")
    p.add_argument("--yasql", default="", help="Path to yasql binary")
    p.add_argument(
        "-d", "--delimiter", choices=("semicolon", "slash"), default="semicolon",
        help="Statement delimiter: semicolon (default) or slash",
    )
    p.add_argument(
        "--done-file", default="",
        help="Append successfully finished SQL here (default: <input>.done.sql)",
    )
    p.add_argument(
        "--fail-file", default="",
        help="Append failed SQL here (default: <input>.fail.sql)",
    )
    p.add_argument(
        "--save-result", action="store_true", default=False,
        help="Save each SQL yasql output to its own file (default: off)",
    )
    p.add_argument(
        "--result-dir", default="",
        help="Directory for per-SQL result files (default: <input>.results/)",
    )
    p.add_argument(
        "--timeout", type=float, default=0,
        help="Per-statement timeout seconds; 0 means no timeout",
    )
    p.add_argument(
        "--global-fail", action="store_true", default=False,
        help="On first failure, stop submitting new work (default: false). "
             "In-flight workers still finish before process exit.",
    )
    p.add_argument(
        "--stop-on-error", action="store_true", default=False,
        help=argparse.SUPPRESS,  # alias of --global-fail
    )
    p.add_argument(
        "--pre-sql", action="append", default=[], metavar="SQL",
        help="Custom SQL executed before every statement (default: empty). "
             "Repeatable; one value may also contain multiple stmts separated by ';'.",
    )
    p.add_argument(
        "--dry-run", action="store_true", default=False,
        help="Parse and print statement plan only; do not execute",
    )
    args = p.parse_args(argv)
    if args.stop_on_error:
        args.global_fail = True
    args.pre_sqls = normalize_pre_sqls(args.pre_sql)
    return args


def _submit_next(pool, pending, futures, task_fn):
    """Submit next job from pending iterator into futures map."""
    try:
        item = next(pending)
    except StopIteration:
        return False
    fut = pool.submit(task_fn, item)
    futures[fut] = item
    return True


def run_pool(jobs, parallel, task_fn, global_fail, stop_flag):
    """
    Run jobs with up to `parallel` workers.
    Always waits for in-flight futures before returning.
    When global_fail and stop_flag is set, do not submit new jobs.
    Remaining unsubmitted jobs are returned for skip recording.
    """
    pending = iter(jobs)
    leftover = []
    with ThreadPoolExecutor(max_workers=parallel) as pool:
        futures = {}
        for _ in range(parallel):
            if not _submit_next(pool, pending, futures, task_fn):
                break

        while futures:
            done, _ = wait(list(futures.keys()), return_when=FIRST_COMPLETED)
            for fut in done:
                item = futures.pop(fut)
                try:
                    fut.result()
                except Exception as exc:
                    eprint("worker exception:", exc)
                    if global_fail:
                        stop_flag.set()

            if stop_flag.is_set() and global_fail:
                # Drain remaining unsubmitted jobs; do not submit more.
                for item in pending:
                    leftover.append(item)
                # Keep waiting for in-flight futures in next loop iteration.
                continue

            # Fill free slots
            while len(futures) < parallel:
                if not _submit_next(pool, pending, futures, task_fn):
                    break

    return leftover


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    in_path = os.path.abspath(args.file)
    if not os.path.isfile(in_path):
        raise SystemExit("input file not found: {}".format(in_path))

    if args.parallel < 1:
        raise SystemExit("--parallel must be >= 1")

    stmts = load_statements(in_path, args.delimiter)
    jobs = build_jobs(stmts, pre_sqls=args.pre_sqls)
    total = len(jobs)
    print("Input : {}".format(in_path))
    print("Delim : {}".format(args.delimiter))
    print("Stmts : {}".format(total))
    print("Par   : {}".format(args.parallel))
    print("GFail : {}".format(args.global_fail))
    if args.pre_sqls:
        print("PreSQL: {} statement(s)".format(len(args.pre_sqls)))
        for i, s in enumerate(args.pre_sqls, 1):
            pv = s.replace("\n", " ")
            if len(pv) > 100:
                pv = pv[:97] + "..."
            print("       [{}] {}".format(i, pv))
    else:
        print("PreSQL: (none)")

    if total == 0:
        print("No statements found; exit")
        return 0

    if args.dry_run:
        for idx, orig, exec_sql, schema in jobs:
            preview = orig.replace("\n", " ")
            if len(preview) > 80:
                preview = preview[:77] + "..."
            sch = schema if schema else "-"
            print("{:04d}: schema=[{}] {}".format(idx, sch, preview))
            if exec_sql.strip() != orig.strip():
                ep = exec_sql.replace("\n", " | ")
                if len(ep) > 120:
                    ep = ep[:117] + "..."
                print("      exec: {}".format(ep))
        return 0

    base = in_path
    done_path = os.path.abspath(args.done_file) if args.done_file else base + ".done.sql"
    fail_path = os.path.abspath(args.fail_file) if args.fail_file else base + ".fail.sql"
    result_dir = os.path.abspath(args.result_dir) if args.result_dir else base + ".results"

    print("Done  : {}".format(done_path))
    print("Fail  : {}".format(fail_path))
    if args.save_result:
        print("Result: {} (enabled)".format(result_dir))
    else:
        print("Result: off (pass --save-result to enable)")

    yasql = resolve_yasql(args.yasql)
    env = build_env()
    print("yasql : {}".format(yasql))
    print("conn  : {}".format(args.connect))
    print("")

    tracker = Tracker(done_path, fail_path, result_dir, args.save_result)
    work_dir = tempfile.mkdtemp(prefix="yasql_parallel_")
    stop_flag = threading.Event()
    t_all0 = time.time()

    def task(item):
        idx, orig_sql, exec_sql, schema = item
        ok, elapsed, output, rc = run_one(
            yasql, args.connect, env, exec_sql, args.timeout, work_dir, idx,
        )
        tracker.record(idx, total, orig_sql, exec_sql, ok, elapsed, output, rc, skipped=False)
        status = "OK" if ok else "FAIL"
        notes = []
        if args.pre_sqls:
            notes.append("+PRE_SQL")
        if schema and parse_current_schema(orig_sql) is None:
            notes.append("+CURRENT_SCHEMA")
        note = (" (" + ",".join(notes) + ")") if notes else ""
        print("[{}/{}] {} rc={} {:.3f}s{}".format(
            idx, total, status, rc, elapsed, note,
        ))
        if (not ok) and args.global_fail:
            stop_flag.set()
        return idx, ok, elapsed, rc

    leftover = []
    try:
        if args.parallel == 1:
            for item in jobs:
                if args.global_fail and stop_flag.is_set():
                    leftover.append(item)
                    continue
                task(item)
        else:
            leftover = run_pool(jobs, args.parallel, task, args.global_fail, stop_flag)

        # Record statements never submitted/executed after global-fail
        for item in leftover:
            idx, orig_sql, exec_sql, _schema = item
            tracker.record(
                idx, total, orig_sql, exec_sql,
                ok=False, elapsed=0.0,
                output="[skipped: --global-fail]\n",
                returncode=-2, skipped=True,
            )
            print("[{}/{}] SKIP rc=-2 0.000s".format(idx, total))
    finally:
        # Always reach here only after workers finished (run_pool waits in-flight)
        shutil.rmtree(work_dir, ignore_errors=True)

    elapsed_all = time.time() - t_all0
    print("")
    print("Finished in {:.3f}s: ok={} fail={} skip={} total={}".format(
        elapsed_all, tracker.ok, tracker.fail, tracker.skip, total,
    ))
    print("Done file : {}".format(done_path))
    print("Fail file : {}".format(fail_path))
    if args.save_result:
        print("Result dir: {}".format(result_dir))

    # Exit after all workers done; non-zero if any real failure
    return 1 if tracker.fail else 0


if __name__ == "__main__":
    sys.exit(main())
