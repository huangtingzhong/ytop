#!/usr/bin/env python
# -*- coding: utf-8 -*-
# File Name: sqlmap.py
# Purpose: One-click YashanDB SQLMAP creation tool (create / genexec / export / genbind / lit2bind / perf)
# Created: 20260802 by huangtingzhong
#
# Quick start:
#   python3 sqlmap.py create -s <src_sqlid> -t <tgt_sqlid> --run
#   python3 sqlmap.py create -s <src_sqlid> -f target.sql --run
#   python3 sqlmap.py create --src-file source.sql -f target.sql --run
#   python3 sqlmap.py genbind -s <src_sqlid> -o bind_values.txt
#   python3 sqlmap.py genexec -s <src_sqlid> -f rewritten.sql -b bind_values.txt --run
#   python3 sqlmap.py export -s <src_sqlid> -o output.sql
#   python3 sqlmap.py lit2bind -f literal.sql -o bind_sql.sql --bind-format ?
#   python3 sqlmap.py perf -s <src_sqlid> -f rewritten.sql -b bind_values.txt
#
# Full help:
#   python3 sqlmap.py -h

from __future__ import print_function, unicode_literals

import argparse
import os
import re
import subprocess
import sys
import tempfile

# Python 2.7 compatibility: subprocess.DEVNULL added in 3.3
try:
    from subprocess import DEVNULL
except ImportError:
    DEVNULL = open(os.devnull, 'w')

# --------------------------------------------------------------------------- #
#  Constants                                                                  #
# --------------------------------------------------------------------------- #

PROG = "sqlmap.py"
VERSION = "1.3.1"
DEFAULT_CONNECT = "/ as sysdba"
DEFAULT_YASQL = "yasql"
CHUNK_SIZE = 1500
SQLMAP_MAX_BYTES = 32000


# --------------------------------------------------------------------------- #
#  Utility: file I/O                                                          #
# --------------------------------------------------------------------------- #

def load_file(path):
    # type: (str) -> str
    with open(path, "r") as f:
        text = f.read().rstrip()
    if text.endswith(";"):
        text = text[:-1].rstrip()
    return text


def write_file(path, text):
    # type: (str, str) -> None
    with open(path, "w") as f:
        f.write(text)
    print("[OK] wrote {0}  ({1} bytes)".format(path, len(text.encode("utf-8"))))


def load_binds(path):
    # type: (str) -> list
    vals = []
    with open(path, "r") as f:
        for raw in f.read().splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.upper() in ("\\N", "NULL"):
                vals.append(None)
            else:
                vals.append(line)
    return vals


def format_binds_file(binds):
    # type: (list) -> str
    """Format bind values as one-per-line text for -b files (NULL for missing)."""
    lines = []
    for v in binds:
        if v is None:
            lines.append("NULL")
        else:
            lines.append(str(v))
    return "\n".join(lines) + ("\n" if lines else "")


# --------------------------------------------------------------------------- #
#  Utility: bind variable parsing                                             #
# --------------------------------------------------------------------------- #

def iter_question_binds(sql):
    # type: (str) -> list
    """Return 0-based offsets of ? outside single-quoted string literals."""
    pos = []
    i = 0
    in_q = False
    while i < len(sql):
        ch = sql[i]
        if ch == "'":
            if in_q and i + 1 < len(sql) and sql[i + 1] == "'":
                i += 2
                continue
            in_q = not in_q
            i += 1
            continue
        if not in_q and ch == "?":
            pos.append(i)
        i += 1
    return pos


def count_binds(sql):
    # type: (str) -> int
    return len(iter_question_binds(sql))


def bind_context(sql, offset, radius=28):
    # type: (str, int, int) -> str
    lo = max(0, offset - radius)
    hi = min(len(sql), offset + 1 + radius)
    return sql[lo:hi].replace("\n", " ").replace("\r", " ")


# --------------------------------------------------------------------------- #
#  yasql execution (local only)                                               #
# --------------------------------------------------------------------------- #

def check_yasql(yasql_path):
    # type: (str) -> None
    """Check that yasql is available; exit if not."""
    try:
        subprocess.Popen(
            [yasql_path, "--version"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE
        ).communicate(timeout=10)
    except OSError:
        print("[ERROR] yasql not found: '{0}'".format(yasql_path))
        print("        Install YashanDB client or set --yasql-path to the full path.")
        sys.exit(1)


def yasql_exec(sql_file, connect_str, yasql_path, schema):
    # type: (str, str, str, str) -> str
    """Execute yasql @file locally and return stdout."""
    local_file = sql_file
    if schema:
        td = tempfile.NamedTemporaryFile(mode="w", suffix=".sql", delete=False)
        td.write("ALTER SESSION SET CURRENT_SCHEMA = " + schema.upper() + ";\n")
        with open(sql_file, "r") as orig:
            td.write(orig.read())
        td.close()
        local_file = td.name

    cmd_parts = [yasql_path, "-S", connect_str, "@" + local_file]

    if os.environ.get("SQLMAP_DEBUG"):
        print("[DEBUG] cmd: {0}".format(" ".join(cmd_parts)), file=sys.stderr)

    try:
        result = subprocess.Popen(
            cmd_parts, stdin=DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        stdout, stderr = result.communicate(timeout=120)
        out = stdout.decode("utf-8", errors="replace") if stdout else ""
        err = stderr.decode("utf-8", errors="replace") if stderr else ""
        if result.returncode != 0:
            print("[ERROR] yasql exited {0}".format(result.returncode), file=sys.stderr)
            if err:
                print(err, file=sys.stderr)
        return out + ("\n" + err if err.strip() else "")
    except OSError as e:
        print("[ERROR] cannot run yasql: {0}".format(e), file=sys.stderr)
        return ""


def yasql_query(sql_text, connect_str, yasql_path, schema):
    # type: (str, str, str, str) -> str
    """Execute a PL/SQL block via yasql, return output."""
    td = tempfile.NamedTemporaryFile(mode="w", suffix=".sql", delete=False, dir="/tmp")
    if schema:
        td.write("ALTER SESSION SET CURRENT_SCHEMA = " + schema.upper() + ";\n")
    td.write("SET SERVEROUTPUT ON\n")
    td.write(sql_text)
    td.write("\nEXIT;\n")
    td.close()
    out = yasql_exec(td.name, connect_str, yasql_path, None)
    try:
        os.unlink(td.name)
    except OSError:
        pass
    return out


# --------------------------------------------------------------------------- #
#  DB fetch helpers                                                           #
# --------------------------------------------------------------------------- #

def fetch_sql_by_sqlid(sqlid, connect_str, yasql_path, schema):
    # type: (str, str, str, str) -> str
    """Fetch sql_fulltext from v$sql by sql_id, return the text or empty."""
    plsql = (
        "DECLARE v_sql CLOB; v_cnt NUMBER;\n"
        "BEGIN\n"
        "  SELECT COUNT(*) INTO v_cnt FROM v$sql WHERE sql_id = '" + sqlid + "';\n"
        "  IF v_cnt = 0 THEN\n"
        "    DBMS_OUTPUT.PUT_LINE('SQLMAP_ERROR: sql_id " + sqlid + " not in v$sql');\n"
        "    RETURN;\n"
        "  END IF;\n"
        "  SELECT sql_fulltext INTO v_sql FROM v$sql WHERE sql_id = '" + sqlid + "' AND ROWNUM=1;\n"
        "  DBMS_OUTPUT.PUT_LINE('SQLMAP_SQLTEXT_START');\n"
        "  DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(v_sql, 32000, 1));\n"
        "  DBMS_OUTPUT.PUT_LINE('SQLMAP_SQLTEXT_END');\n"
        "END;\n"
        "/"
    )
    out = yasql_query(plsql, connect_str, yasql_path, schema)
    if "SQLMAP_ERROR:" in out:
        for ln in out.splitlines():
            if "SQLMAP_ERROR:" in ln:
                print(ln.strip())
                return ""
    lines = out.splitlines()
    sql_lines = []
    in_text = False
    for ln in lines:
        s = ln.strip()
        if s == "SQLMAP_SQLTEXT_START":
            in_text = True
            continue
        if s == "SQLMAP_SQLTEXT_END":
            break
        if in_text:
            sql_lines.append(ln)
    return "\n".join(sql_lines).strip()


def fetch_binds_by_sqlid(sqlid, connect_str, yasql_path, schema):
    # type: (str, str, str, str) -> list
    """Fetch bind values from v$sql_bind_capture by sql_id."""
    plsql = (
        "DECLARE\n"
        "  v_child NUMBER;\n"
        "BEGIN\n"
        "  BEGIN\n"
        "    SELECT child_number INTO v_child FROM (\n"
        "      SELECT child_number FROM v$sql_bind_capture\n"
        "       WHERE sql_id = '" + sqlid + "'\n"
        "       ORDER BY last_captured DESC NULLS LAST, child_number DESC\n"
        "    ) WHERE ROWNUM = 1;\n"
        "  EXCEPTION WHEN NO_DATA_FOUND THEN\n"
        "    DBMS_OUTPUT.PUT_LINE('SQLMAP_BIND_ERROR: no bind capture for sql_id " + sqlid + "');\n"
        "    RETURN;\n"
        "  END;\n"
        "  DBMS_OUTPUT.PUT_LINE('SQLMAP_BIND_START');\n"
        "  FOR r IN (\n"
        "    SELECT position, value_string, was_captured\n"
        "      FROM v$sql_bind_capture\n"
        "     WHERE sql_id = '" + sqlid + "' AND child_number = v_child\n"
        "     ORDER BY position\n"
        "  ) LOOP\n"
        "    IF NVL(UPPER(r.was_captured),'NO') != 'YES' OR r.value_string IS NULL THEN\n"
        "      DBMS_OUTPUT.PUT_LINE('NULL');\n"
        "    ELSE\n"
        "      DBMS_OUTPUT.PUT_LINE(r.value_string);\n"
        "    END IF;\n"
        "  END LOOP;\n"
        "  DBMS_OUTPUT.PUT_LINE('SQLMAP_BIND_END');\n"
        "END;\n"
        "/"
    )
    out = yasql_query(plsql, connect_str, yasql_path, schema)
    if "SQLMAP_BIND_ERROR:" in out:
        for ln in out.splitlines():
            if "SQLMAP_BIND_ERROR:" in ln:
                print(ln.strip())
        return []
    binds = []
    in_binds = False
    for ln in out.splitlines():
        s = ln.strip()
        if s == "SQLMAP_BIND_START":
            in_binds = True
            continue
        if s == "SQLMAP_BIND_END":
            break
        if in_binds:
            if s.upper() == "NULL":
                binds.append(None)
            else:
                binds.append(s)
    return binds


# --------------------------------------------------------------------------- #
#  PL/SQL string helpers                                                      #
# --------------------------------------------------------------------------- #

def plsql_str(s):
    # type: (str) -> str
    return "'" + s.replace("'", "''") + "'"


def plsql_varchar_expr(s):
    # type: (str) -> str
    """Build a single-line PL/SQL varchar expression (newlines via CHR(10))."""
    pieces = []
    buf = []
    for ch in s:
        if ch == "\n":
            if buf:
                pieces.append("'" + "".join(buf).replace("'", "''") + "'")
                buf = []
            pieces.append("CHR(10)")
        elif ch == "\r":
            continue
        else:
            buf.append(ch)
    if buf:
        pieces.append("'" + "".join(buf).replace("'", "''") + "'")
    return " || ".join(pieces) if pieces else "''"


def append_clob_chunks(lines, var, text, chunk):
    # type: (list, str, str, int) -> None
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    lines.append("  DBMS_LOB.CREATETEMPORARY(" + var + ", TRUE);")
    for off in range(0, len(text), chunk):
        part = text[off:off + chunk]
        expr = plsql_varchar_expr(part)
        lines.append("  DBMS_LOB.WRITEAPPEND({0}, {1}, {2});".format(var, len(part), expr))


# --------------------------------------------------------------------------- #
#  Mode 1: create (source/target from sqlid and/or file -> CREATE SQLMAP)     #
# --------------------------------------------------------------------------- #

def gen_create_sqlmap(src_sql, tgt_sql, map_name, map_user, run, dry_run, do_flush,
                      src_sqlid="", src_from_file=False):
    # type: (str, str, str, str, bool, bool, bool, str, bool) -> str
    """Generate CREATE SQLMAP yasql script.

    src_sql / tgt_sql: already resolved SQL texts (from v$sql or files).
    When src_from_file is True, both sides are embedded; no v$sql lookup for source.
    do_flush: if True, FLUSH SHARED_POOL after create (may age out sql_id cursors).
    """
    src_bytes = len(src_sql.encode("utf-8"))
    tgt_bytes = len(tgt_sql.encode("utf-8"))
    if src_bytes > SQLMAP_MAX_BYTES:
        print("[ERROR] source SQL is {0} bytes; SQLMAP limit is {1}".format(
            src_bytes, SQLMAP_MAX_BYTES))
        sys.exit(1)
    if tgt_bytes > SQLMAP_MAX_BYTES:
        print("[ERROR] target SQL is {0} bytes; SQLMAP limit is {1}".format(
            tgt_bytes, SQLMAP_MAX_BYTES))
        sys.exit(1)
    if len(src_sql) > 32767 or len(tgt_sql) > 32767:
        print("[ERROR] SQL text exceeds VARCHAR2(32767) char limit for DDL builder")
        sys.exit(1)

    lines = []
    lines.append("-- Auto-generated by " + PROG + " create")
    if src_from_file:
        lines.append("-- source=file target_bytes=" + str(tgt_bytes)
                     + " source_bytes=" + str(src_bytes))
    else:
        lines.append("-- source_sqlid=" + src_sqlid
                     + " target_bytes=" + str(tgt_bytes)
                     + " source_bytes=" + str(src_bytes))
    lines.append("SET SERVEROUTPUT ON")
    lines.append("SET DEFINE OFF")
    lines.append("DECLARE")
    lines.append("  v_src_clob CLOB;")
    lines.append("  v_tgt_clob CLOB;")
    lines.append("  v_src_sql  VARCHAR2(32767);")
    lines.append("  v_tgt_sql  VARCHAR2(32767);")
    lines.append("  v_ddl      CLOB;")
    lines.append("  v_q        VARCHAR2(1) := CHR(39);")
    lines.append("  v_seg      VARCHAR2(4000);")
    lines.append("  v_map_name VARCHAR2(128);")
    lines.append("  v_map_user VARCHAR2(64) := " + plsql_str(map_user.upper()) + ";")
    lines.append("  v_src_len  NUMBER;")
    lines.append("BEGIN")
    # Embed source + target texts (already resolved in Python)
    append_clob_chunks(lines, "v_src_clob", src_sql, CHUNK_SIZE)
    append_clob_chunks(lines, "v_tgt_clob", tgt_sql, CHUNK_SIZE)
    lines.append("  v_src_len := DBMS_LOB.GETLENGTH(v_src_clob);")
    lines.append("  v_src_sql := DBMS_LOB.SUBSTR(v_src_clob, v_src_len, 1);")
    lines.append("  v_tgt_sql := DBMS_LOB.SUBSTR(v_tgt_clob, DBMS_LOB.GETLENGTH(v_tgt_clob), 1);")
    lines.append("  DBMS_OUTPUT.PUT_LINE('source chars=' || LENGTH(v_src_sql));")
    lines.append("  DBMS_OUTPUT.PUT_LINE('target chars=' || LENGTH(v_tgt_sql));")
    lines.append("  BEGIN EXECUTE IMMEDIATE 'ALTER SYSTEM SET sql_map = TRUE'; "
                 "EXCEPTION WHEN OTHERS THEN NULL; END;")
    if map_name:
        lines.append("  v_map_name := " + plsql_str(map_name.upper()) + ";")
    elif src_sqlid:
        lines.append("  v_map_name := 'map_' || " + plsql_str(src_sqlid)
                     + " || '_' || TO_CHAR(SYSTIMESTAMP,'YYYYMMDDHH24MISS');")
    else:
        lines.append("  v_map_name := 'map_file_' || TO_CHAR(SYSTIMESTAMP,'YYYYMMDDHH24MISS');")
    # Drop same name + any SQLMAP already covering this exact source text
    # (avoids YAS-04398 duplicate sql when another map name owns the source)
    lines.append("  BEGIN EXECUTE IMMEDIATE 'DROP SQLMAP ' || v_map_name; "
                 "EXCEPTION WHEN OTHERS THEN NULL; END;")
    lines.append("  FOR r IN (")
    lines.append("    SELECT name FROM SYS.SQL_MAP$")
    lines.append("     WHERE DBMS_LOB.GETLENGTH(sql_text) = v_src_len")
    lines.append("       AND DBMS_LOB.SUBSTR(sql_text, v_src_len, 1) = v_src_sql")
    lines.append("  ) LOOP")
    lines.append("    BEGIN")
    lines.append("      EXECUTE IMMEDIATE 'DROP SQLMAP ' || r.name;")
    lines.append("      DBMS_OUTPUT.PUT_LINE('Dropped conflicting SQLMAP: ' || r.name);")
    lines.append("    EXCEPTION WHEN OTHERS THEN")
    lines.append("      DBMS_OUTPUT.PUT_LINE('Drop conflict failed: ' || r.name || ' ' || SQLERRM);")
    lines.append("    END;")
    lines.append("  END LOOP;")
    # Escape quotes for CREATE SQLMAP string literals
    lines.append("  v_src_sql := REPLACE(v_src_sql, '''', '''''');")
    lines.append("  v_tgt_sql := REPLACE(v_tgt_sql, '''', '''''');")
    lines.append("  DBMS_LOB.CREATETEMPORARY(v_ddl, TRUE);")
    lines.append("  v_seg := 'CREATE SQLMAP ' || v_map_name || ' (' || v_map_user || ', ' || v_q;")
    lines.append("  DBMS_LOB.WRITEAPPEND(v_ddl, LENGTH(v_seg), v_seg);")
    lines.append("  DBMS_LOB.WRITEAPPEND(v_ddl, LENGTH(v_src_sql), v_src_sql);")
    lines.append("  v_seg := v_q || ', ' || v_q;")
    lines.append("  DBMS_LOB.WRITEAPPEND(v_ddl, LENGTH(v_seg), v_seg);")
    lines.append("  DBMS_LOB.WRITEAPPEND(v_ddl, LENGTH(v_tgt_sql), v_tgt_sql);")
    lines.append("  v_seg := v_q || ')';")
    lines.append("  DBMS_LOB.WRITEAPPEND(v_ddl, LENGTH(v_seg), v_seg);")
    lines.append("  DBMS_OUTPUT.PUT_LINE('[dry-run] ' || DBMS_LOB.SUBSTR(v_ddl, 4000, 1));")
    if dry_run:
        lines.append("  DBMS_OUTPUT.PUT_LINE('-- dry-run: not executing');")
    else:
        lines.append("  EXECUTE IMMEDIATE v_ddl;")
        lines.append("  DBMS_OUTPUT.PUT_LINE('SQLMAP created: ' || v_map_name);")
        lines.append("  DBMS_OUTPUT.PUT_LINE('Rollback: DROP SQLMAP ' || v_map_name || ';');")
        if do_flush:
            lines.append("  BEGIN EXECUTE IMMEDIATE 'ALTER SYSTEM FLUSH SHARED_POOL'; "
                         "EXCEPTION WHEN OTHERS THEN NULL; END;")
            lines.append("  DBMS_OUTPUT.PUT_LINE('FLUSH SHARED_POOL done.');")
        else:
            lines.append("  DBMS_OUTPUT.PUT_LINE("
                         "'Note: shared pool NOT flushed (unrelated sql_id kept); "
                         "mapped SOURCE cursor may still be invalidated by CREATE SQLMAP. "
                         "Use --flush to clear all cursors.');")
        if run:
            lines.append("  DBMS_OUTPUT.PUT_LINE("
                         "'-- --run: execute source SQL for perf check (placeholder)');")
    lines.append("END;")
    lines.append("/")
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------------- #
#  Mode 2: --genexec (source sqlid + SQL file -> exec script)                 #
# --------------------------------------------------------------------------- #

def inject_sql_marker(sql, marker):
    # type: (str, str) -> str
    """Ensure marker appears in executed SQL text so v$sql lookup can find it."""
    if not marker:
        return sql
    if marker in sql:
        return sql
    # Prefer leading comment form: /* MARK */ SELECT ...
    m = marker.strip()
    if not (m.startswith("/*") and m.endswith("*/")):
        m = "/* " + m + " */"
    return m + " " + sql.lstrip()


def gen_exec_script(sql, binds, label, marker, chunk):
    # type: (str, list, str, str, int) -> str
    n = count_binds(sql)
    if n == 0 and binds:
        print("[WARN] SQL has no ? but bind values provided; binds ignored")
        binds = []
    if n > 0 and n != len(binds):
        print("[ERROR] bind count mismatch: SQL has {0} ? but values has {1}".format(n, len(binds)))
        sys.exit(1)

    # Inject marker into SQL body so cursor text contains it (avoids NOT_FOUND)
    sql = inject_sql_marker(sql, marker)
    marker_lit = marker.replace("'", "''") if marker else ""
    sql_len = len(sql)

    using = ", ".join("b{0:03d}".format(i) for i in range(1, max(n, 1) + 1)) if n > 0 else ""
    lines = []
    lines.append("-- Auto-generated by " + PROG + " --genexec")
    lines.append("-- label=" + label + " marker=" + marker + " binds=" + str(n))
    lines.append("SET SERVEROUTPUT ON")
    lines.append("DECLARE")
    lines.append("  v_sql CLOB; v_cnt NUMBER; v_sqlid VARCHAR2(64); c SYS_REFCURSOR;")
    for i, v in enumerate(binds, 1):
        name = "b{0:03d}".format(i)
        if v is None:
            lines.append("  {0} VARCHAR2(4000) := NULL;".format(name))
        else:
            maxlen = max(32, min(4000, len(v) + 8))
            lines.append("  {0} VARCHAR2({1}) := {2};".format(name, maxlen, plsql_str(v)))
    lines.append("BEGIN")
    lines.append("  DBMS_LOB.CREATETEMPORARY(v_sql, TRUE);")
    append_clob_chunks(lines, "v_sql", sql, chunk)
    if using:
        lines.append("  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM (' || v_sql || ')' INTO v_cnt USING " + using + ";")
    else:
        lines.append("  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM (' || v_sql || ')' INTO v_cnt;")
    lines.append("  DBMS_OUTPUT.PUT_LINE('" + label + "_CNT=' || v_cnt);")
    if using:
        lines.append("  OPEN c FOR v_sql USING " + using + ";")
    else:
        lines.append("  OPEN c FOR v_sql;")
    lines.append("  CLOSE c;")
    lines.append("  BEGIN")
    lines.append("    SELECT sql_id INTO v_sqlid FROM (")
    lines.append("      SELECT sql_id FROM v$sql")
    if marker:
        # Anchor on marker + length; exclude generator/self-lookup noise
        lines.append("       WHERE DBMS_LOB.INSTR(sql_fulltext, '" + marker_lit + "') > 0")
        lines.append("         AND DBMS_LOB.GETLENGTH(sql_fulltext) = " + str(sql_len))
        lines.append("         AND DBMS_LOB.INSTR(sql_fulltext, 'WRITEAPPEND') = 0")
        lines.append("         AND DBMS_LOB.INSTR(sql_fulltext, 'v$sql') = 0")
        lines.append("         AND DBMS_LOB.INSTR(sql_fulltext, 'V$SQL') = 0")
        lines.append("         AND DBMS_LOB.INSTR(sql_fulltext, 'SQLMAP_') = 0")
    else:
        head = sql[:80].replace("'", "''")
        lines.append("       WHERE DBMS_LOB.SUBSTR(sql_fulltext, 80, 1) = '" + head + "'")
        lines.append("         AND DBMS_LOB.GETLENGTH(sql_fulltext) = " + str(sql_len))
        lines.append("         AND DBMS_LOB.INSTR(sql_fulltext, 'WRITEAPPEND') = 0")
    lines.append("       ORDER BY last_active_time DESC NULLS LAST")
    lines.append("    ) WHERE ROWNUM = 1;")
    lines.append("    DBMS_OUTPUT.PUT_LINE('" + label + "_SQL_ID=' || v_sqlid);")
    lines.append("  EXCEPTION WHEN NO_DATA_FOUND THEN")
    lines.append("    DBMS_OUTPUT.PUT_LINE('" + label + "_SQL_ID=NOT_FOUND');")
    lines.append("  END;")
    lines.append("END;")
    lines.append("/")
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------------- #
#  Mode: lit2bind (literal SQL -> bind variable SQL + values file)            #
# --------------------------------------------------------------------------- #

def convert_literals_to_binds(sql, bind_format):
    # type: (str, str) -> tuple
    """
    Convert SQL literals to bind variables.
    Returns (converted_sql, bind_values_list).
    """
    values = []
    result = []
    i = 0
    in_str = False
    in_comment = False
    bind_idx = [0]

    def next_placeholder():
        bind_idx[0] += 1
        n = bind_idx[0]
        if bind_format == ":1":
            return ":{0}".format(n)
        elif bind_format == ":name":
            return ":b{0}".format(n)
        else:
            return "?"

    while i < len(sql):
        ch = sql[i]

        # Handle line comments (-- until end of line)
        if not in_str and ch == "-" and i + 1 < len(sql) and sql[i + 1] == "-":
            in_comment = True

        if in_comment:
            result.append(ch)
            if ch == "\n":
                in_comment = False
            i += 1
            continue

        # Handle string literals (skip their content)
        if ch == "'":
            j = i - 1
            while j >= 0 and sql[j] in " \t\n\r":
                j -= 1
            if j >= 0:
                preceding = sql[max(0, j - 5):j + 1].upper()
                is_value = False
                if j >= 0 and sql[j] in "=><!":
                    is_value = True
                elif "LIKE" in preceding:
                    is_value = True

                if is_value:
                    end = i + 1
                    while end < len(sql):
                        if sql[end] == "'":
                            if end + 1 < len(sql) and sql[end + 1] == "'":
                                end += 2
                                continue
                            break
                        end += 1
                    value = sql[i + 1:end].replace("''", "'")
                    ph = next_placeholder()
                    result.append(ph)
                    values.append(value)
                    i = end + 1
                    continue
            result.append(ch)
            i += 1
            if i < len(sql) and sql[i] == "'":
                result.append(sql[i])
                i += 1
            continue

        # Handle numeric literals (after comparison operators)
        if ch.isdigit() and not in_str:
            j = len(result) - 1
            while j >= 0 and result[j] in " \t":
                j -= 1
            if j >= 0:
                preceding = "".join(result[max(0, j - 4):j + 1])
                if re.search(r'(=|>=|<=|<>|!=|>|<|\(|,)$', preceding):
                    end = i
                    while end < len(sql) and (sql[end].isdigit() or sql[end] == "."):
                        end += 1
                    value = sql[i:end]
                    ph = next_placeholder()
                    result.append(ph)
                    values.append(value)
                    i = end
                    continue

        result.append(ch)
        i += 1

    return "".join(result), values


# --------------------------------------------------------------------------- #
#  Mode: --perf (performance comparison)                                      #
# --------------------------------------------------------------------------- #

def gen_perf_script(src_sqlid, tgt_sql, binds, label, marker, chunk):
    # type: (str, str, list, str, str, int) -> str
    """Generate a perf comparison yasql script.
    Source SQL: read existing v$sql stats by sql_id (no re-execution).
    Target SQL: execute with binds (if any).
    """
    lines = []
    lines.append("-- Auto-generated by " + PROG + " --perf")
    lines.append("SET SERVEROUTPUT ON")
    lines.append("DECLARE")
    lines.append("  v_sql CLOB; v_cnt NUMBER;")
    lines.append("  v_elapsed NUMBER; v_bufgets NUMBER; v_execs NUMBER;")
    n = count_binds(tgt_sql) if tgt_sql else 0
    for i, v in enumerate(binds, 1):
        name = "b{0:03d}".format(i)
        if v is None:
            lines.append("  {0} VARCHAR2(4000) := NULL;".format(name))
        else:
            maxlen = max(32, min(4000, len(v) + 8))
            lines.append("  {0} VARCHAR2({1}) := {2};".format(name, maxlen, plsql_str(v)))
    using = ", ".join("b{0:03d}".format(i) for i in range(1, max(n, 1) + 1)) if n > 0 else ""
    lines.append("BEGIN")

    # Source SQL perf: read existing v$sql stats (NO re-execution)
    lines.append("  -- Source SQL: read existing stats from v$sql")
    lines.append("  BEGIN")
    lines.append("    SELECT elapsed_time, buffer_gets, executions")
    lines.append("      INTO v_elapsed, v_bufgets, v_execs")
    lines.append("      FROM v$sql")
    lines.append("     WHERE sql_id = '" + src_sqlid + "' AND ROWNUM=1;")
    lines.append("    DBMS_OUTPUT.PUT_LINE('SRC_ELAPSED=' || v_elapsed")
    lines.append("      || ' SRC_BUFGETS=' || v_bufgets")
    lines.append("      || ' SRC_EXECS=' || v_execs")
    lines.append("      || ' SRC_AVG_US=' || ROUND(v_elapsed/GREATEST(v_execs,1),1));")
    lines.append("  EXCEPTION WHEN NO_DATA_FOUND THEN")
    lines.append("    DBMS_OUTPUT.PUT_LINE('SRC_STATS=NOT_FOUND (sql_id " + src_sqlid + " not in v$sql)');")
    lines.append("  END;")

    # Target SQL perf
    if tgt_sql:
        lines.append("")
        lines.append("  -- Target SQL: execute + read stats")
        append_clob_chunks(lines, "v_sql", tgt_sql, chunk)
        if using:
            lines.append("  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM (' || v_sql || ')' INTO v_cnt USING " + using + ";")
        else:
            lines.append("  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM (' || v_sql || ')' INTO v_cnt;")
        lines.append("  DBMS_OUTPUT.PUT_LINE('TGT_CNT=' || v_cnt);")
        lines.append("  BEGIN")
        lines.append("    SELECT elapsed_time, buffer_gets")
        lines.append("      INTO v_elapsed, v_bufgets FROM v$sql")
        lines.append("     WHERE sql_fulltext LIKE SUBSTR(DBMS_LOB.SUBSTR(v_sql, 60, 1), 1, 60) || '%' AND ROWNUM=1;")
        lines.append("    DBMS_OUTPUT.PUT_LINE('TGT_ELAPSED=' || v_elapsed || ' TGT_BUFGETS=' || v_bufgets);")
        lines.append("  EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('TGT_STATS=NOT_FOUND'); END;")

    lines.append("END;")
    lines.append("/")
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------------- #
#  CLI (subcommand mode: create / genexec / export / genbind / lit2bind / perf)
# --------------------------------------------------------------------------- #

def _add_common_args(sp):
    """Add shared connection args to a subparser."""
    sp.add_argument("--connect", default=DEFAULT_CONNECT, help='yasql connect string (default: "/ as sysdba")')
    sp.add_argument("--schema", default="", help="ALTER SESSION SET CURRENT_SCHEMA=<schema>")
    sp.add_argument("--yasql-path", default=DEFAULT_YASQL, help="yasql path (default: yasql)")
    sp.add_argument("-v", "--verbose", action="store_true", help="verbose output")


def build_parser():
    ap = argparse.ArgumentParser(
        prog=PROG,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description=(
            "YashanDB SQLMAP one-click tool v{0}\n\n"
            "Subcommands:\n"
            "  create    Create SQLMAP (sqlid and/or SQL files)\n"
            "  genexec   Generate yasql exec script from sqlid + SQL file\n"
            "  export    Export SQL text from v$sql by sqlid to file\n"
            "  genbind   Export bind values from v$sql_bind_capture to a -b file\n"
            "  lit2bind  Convert literal SQL to bind-variable SQL (offline)\n"
            "  perf      Performance comparison (source vs target)\n\n"
            "Examples:\n"
            "  {1} create -s abc123 -t xyz789 --run\n"
            "  {1} create --src-file source.sql -f target.sql --run\n"
            "  {1} genbind -s abc123 -o binds.txt\n"
            "  {1} genexec -s abc123 -f rewritten.sql -b binds.txt --run\n"
            "  {1} export -s abc123 -o output.sql\n"
            "  {1} lit2bind -f literal.sql -o bind_sql.sql\n"
            "  {1} perf -s abc123 -f rewritten.sql -b binds.txt\n"
            "\n"
            "Each subcommand has its own -h, e.g.: {1} create -h"
        ).format(VERSION, PROG),
    )
    sub = ap.add_subparsers(dest="mode", metavar="<subcommand>")

    # --- create ---
    p_create = sub.add_parser("create", help="Create SQLMAP (sqlid and/or SQL files)",
        description="Create a SQLMAP that maps source SQL to target SQL.\n\n"
                    "Source SQL: -s <sql_id> (from v$sql) OR --src-file <file.sql>\n"
                    "Target SQL: -t <sql_id> (from v$sql) OR -f <file.sql>\n"
                    "When both sides are files (--src-file + -f), source sql_id is not needed.\n\n"
                    "The tool builds CREATE SQLMAP DDL and optionally executes it.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Examples:\n"
               "  {0} create -s abc123 -t xyz789 --run              # both from v$sql\n"
               "  {0} create -s abc123 -f target.sql --run           # src sqlid + tgt file\n"
               "  {0} create --src-file source.sql -f target.sql     # both from files\n"
               "  {0} create --src-file source.sql -f target.sql --dry-run".format(PROG))
    p_create.add_argument("-s", "--src-sqlid", default="", help="source sql_id in v$sql (use -s OR --src-file)")
    p_create.add_argument("--src-file", default="", help="source SQL file (use --src-file OR -s)")
    p_create.add_argument("-t", "--tgt-sqlid", default="", help="target sql_id in v$sql (use -t OR -f)")
    p_create.add_argument("-f", "--sql-file", default="", help="target SQL file (use -f OR -t)")
    p_create.add_argument("--map-name", default="", help="SQLMAP name (default: auto)")
    p_create.add_argument("--map-user", default="ALL", help="SQLMAP USER_NAME (default: ALL)")
    p_create.add_argument("--run", action="store_true", help="execute source SQL after create for perf check")
    p_create.add_argument("--dry-run", action="store_true", help="preview DDL without executing")
    p_create.add_argument("--flush", action="store_true",
                          help="FLUSH SHARED_POOL after create (default: off, keeps sql_id cursors)")
    p_create.add_argument("--no-flush", action="store_true",
                          help=argparse.SUPPRESS)  # deprecated alias; default is already no-flush
    p_create.add_argument("-o", "--out", default="", help="output DDL file path")
    p_create.add_argument("--chunk", type=int, default=CHUNK_SIZE, help="CLOB chunk size (default: 1500)")
    _add_common_args(p_create)

    # --- genexec ---
    p_genexec = sub.add_parser("genexec", help="Generate yasql exec script",
        description="Generate a yasql script to execute the rewritten SQL with bind values.\n\n"
                    "If the target SQL has ? placeholders and no -b file is provided,\n"
                    "bind values are auto-fetched from v$sql_bind_capture by source sql_id.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Example:\n  {0} genexec -s abc123 -f rewritten.sql -b values.txt --run".format(PROG))
    p_genexec.add_argument("-s", "--src-sqlid", required=True, help="source sql_id in v$sql")
    p_genexec.add_argument("-f", "--sql-file", required=True, help="target SQL file with ? placeholders")
    p_genexec.add_argument("-b", "--bind-file", default="", help="bind values file (auto-fetched if omitted)")
    p_genexec.add_argument("-o", "--out", default="", help="output exec script path")
    p_genexec.add_argument("--run", action="store_true", help="execute the generated script immediately")
    p_genexec.add_argument("--marker", default="", help="unique comment marker for v$sql lookup")
    p_genexec.add_argument("--label", default="TGT", help="DBMS_OUTPUT label prefix (default: TGT)")
    p_genexec.add_argument("--chunk", type=int, default=CHUNK_SIZE, help="CLOB chunk size (default: 1500)")
    _add_common_args(p_genexec)

    # --- export ---
    p_export = sub.add_parser("export", help="Export SQL text from v$sql to file",
        description="Fetch sql_fulltext from v$sql by sql_id and write to a file\n"
                    "for manual review or modification.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Example:\n  {0} export -s abc123 -o output.sql".format(PROG))
    p_export.add_argument("-s", "--src-sqlid", required=True, help="sql_id to export")
    p_export.add_argument("-o", "--out", default="", help="output file (default: sql_<sqlid>.sql)")
    _add_common_args(p_export)

    # --- genbind: export bind values from v$sql_bind_capture ---
    p_genbind = sub.add_parser("genbind", help="Export bind values from v$sql_bind_capture",
        description="Fetch bind values for a sql_id from v$sql_bind_capture and write\n"
                    "a one-value-per-line file for use with genexec/perf -b.\n\n"
                    "Format matches load_binds(): one bind per line; NULL for missing.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Examples:\n"
               "  {0} genbind -s abc123 -o binds.txt\n"
               "  {0} genexec -s abc123 -f target.sql -b binds.txt --run".format(PROG))
    p_genbind.add_argument("-s", "--src-sqlid", required=True, help="source sql_id in v$sql_bind_capture")
    p_genbind.add_argument("-o", "--out", default="", help="output bind values file (default: bind_<sqlid>.txt)")
    _add_common_args(p_genbind)

    # --- lit2bind: offline literal -> bind placeholder (former genbind) ---
    p_lit2bind = sub.add_parser("lit2bind", help="Convert literal SQL to bind-variable SQL",
        description="Convert WHERE-clause literals (string/number/date) in a SQL file\n"
                    "to bind variable placeholders (? or :1 or :name).\n"
                    "Outputs the converted SQL + a bind values file.\n\n"
                    "No database connection needed.\n"
                    "Note: for fetching live binds from the DB, use 'genbind' instead.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Example:\n  {0} lit2bind -f literal.sql -o bind.sql --bind-format ?".format(PROG))
    p_lit2bind.add_argument("-f", "--sql-file", required=True, help="input SQL file with literals")
    p_lit2bind.add_argument("-o", "--out", default="", help="output bind SQL file (default: bind_<input>)")
    p_lit2bind.add_argument("--bind-format", default="?", choices=["?", ":1", ":name"],
                            help="bind placeholder format (default: ?)")
    p_lit2bind.add_argument("--bind-out", default="bind_values.txt", help="bind values output file")

    # --- perf ---
    p_perf = sub.add_parser("perf", help="Performance comparison (source vs target)",
        description="Compare performance of source SQL (read v$sql stats by sql_id)\n"
                    "vs target SQL (execute with binds).\n\n"
                    "Source stats are read from v$sql (no re-execution needed).\n"
                    "Target SQL is executed; binds auto-fetched if no -b provided.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Examples:\n"
               "  {0} perf -s abc123                              # just source stats\n"
               "  {0} perf -s abc123 -f rewritten.sql              # source + execute target\n"
               "  {0} perf -s abc123 -f rewritten.sql -b vals.txt  # target with binds".format(PROG))
    p_perf.add_argument("-s", "--src-sqlid", required=True, help="source sql_id in v$sql")
    p_perf.add_argument("-f", "--sql-file", default="", help="target SQL file (optional)")
    p_perf.add_argument("-b", "--bind-file", default="", help="bind values file (auto-fetched if omitted)")
    p_perf.add_argument("-o", "--out", default="", help="output perf script path")
    p_perf.add_argument("--label", default="SQL", help="DBMS_OUTPUT label prefix (default: SQL)")
    p_perf.add_argument("--chunk", type=int, default=CHUNK_SIZE, help="CLOB chunk size (default: 1500)")
    _add_common_args(p_perf)

    ap.add_argument("--version", action="version", version="{0} v{1}".format(PROG, VERSION))
    return ap


def main(argv):
    # Support -help alias
    if "-help" in argv:
        argv = [x if x != "-help" else "--help" for x in argv]

    ap = build_parser()
    args = ap.parse_args(argv)

    if not args.mode:
        ap.print_help()
        return 1

    # --- lit2bind: offline, no DB needed ---
    if args.mode == "lit2bind":
        print("[INFO] lit2bind: converting literals to bind variables ({0})".format(args.bind_format))
        sql = load_file(args.sql_file)
        converted, values = convert_literals_to_binds(sql, args.bind_format)
        out_sql = args.out or "bind_" + os.path.basename(args.sql_file)
        write_file(out_sql, converted + ";")
        write_file(args.bind_out, format_binds_file(values))
        print("[OK] converted {0} literal(s) to {1} bind(s)".format(len(values), args.bind_format))
        print("     SQL: {0}".format(out_sql))
        print("     Binds: {0} ({1} values)".format(args.bind_out, len(values)))
        return 0

    # --- validate create args before checking yasql ---
    if args.mode == "create":
        src_ok = bool(args.src_sqlid) or bool(args.src_file)
        tgt_ok = bool(args.tgt_sqlid) or bool(args.sql_file)
        if not src_ok:
            print("[ERROR] create requires source: use -s <sql_id> or --src-file <file.sql>")
            return 1
        if args.src_sqlid and args.src_file:
            print("[ERROR] create: -s and --src-file are mutually exclusive; pick one")
            return 1
        if not tgt_ok:
            print("[ERROR] create requires target: use -t <sql_id> or -f <file.sql>")
            return 1
        if args.tgt_sqlid and args.sql_file:
            print("[ERROR] create: -t and -f are mutually exclusive; pick one")
            return 1

    # --- create: both from files -> generate DDL without needing v$sql fetch ---
    # (still needs yasql to EXECUTE unless --dry-run)
    if args.mode == "create":
        src_from_file = bool(args.src_file)
        tgt_from_file = bool(args.sql_file)
        need_fetch = (not src_from_file) or (not tgt_from_file)

        conn = args.connect
        yasql = args.yasql_path
        schema = args.schema

        if need_fetch or not args.dry_run:
            check_yasql(yasql)

        if src_from_file:
            src_sql = load_file(args.src_file)
            print("[INFO] create: source={0} (file, {1} chars)".format(
                args.src_file, len(src_sql)))
        else:
            print("[INFO] create: source={0} (v$sql)".format(args.src_sqlid))
            src_sql = fetch_sql_by_sqlid(args.src_sqlid, conn, yasql, schema)
            if not src_sql:
                print("[ERROR] could not fetch source SQL from v$sql")
                return 1

        if tgt_from_file:
            tgt_sql = load_file(args.sql_file)
            print("[INFO] create: target={0} (file, {1} chars)".format(
                args.sql_file, len(tgt_sql)))
        else:
            print("[INFO] create: target={0} (v$sql)".format(args.tgt_sqlid))
            tgt_sql = fetch_sql_by_sqlid(args.tgt_sqlid, conn, yasql, schema)
            if not tgt_sql:
                print("[ERROR] could not fetch target SQL from v$sql")
                return 1

        if args.verbose:
            print("[INFO] source SQL head: {0}...".format(src_sql[:100]))
            print("[INFO] target SQL head: {0}...".format(tgt_sql[:100]))

        # Default: do NOT flush (keeps sql_id usable for follow-up genbind/export/perf).
        # --flush opts in; --no-flush is a deprecated no-op (kept for old scripts).
        do_flush = bool(getattr(args, "flush", False))
        script = gen_create_sqlmap(
            src_sql, tgt_sql, args.map_name, args.map_user,
            args.run, args.dry_run, do_flush,
            src_sqlid=args.src_sqlid or "",
            src_from_file=src_from_file,
        )
        if args.out:
            out_file = args.out
        elif args.src_sqlid:
            out_file = "create_sqlmap_" + args.src_sqlid + ".sql"
        else:
            out_file = "create_sqlmap_from_files.sql"
        write_file(out_file, script)
        print("[OK] CREATE SQLMAP script: {0}".format(out_file))
        if args.dry_run:
            print("[INFO] dry-run mode; not executing.")
            return 0
        print("[INFO] executing yasql...")
        out = yasql_exec(out_file, conn, yasql, schema)
        print(out)
        return 0

    # --- modes below need DB access (local yasql) ---
    conn = args.connect
    yasql = args.yasql_path
    schema = args.schema
    check_yasql(yasql)

    # --- genbind: export bind values for -b ---
    if args.mode == "genbind":
        print("[INFO] genbind: fetching binds from v$sql_bind_capture sql_id={0}".format(
            args.src_sqlid))
        binds = fetch_binds_by_sqlid(args.src_sqlid, conn, yasql, schema)
        if not binds:
            print("[ERROR] no bind values found for sql_id={0}".format(args.src_sqlid))
            print("        Ensure the SQL was executed with binds and capture is available.")
            return 1
        out_file = args.out or ("bind_" + args.src_sqlid + ".txt")
        write_file(out_file, format_binds_file(binds))
        print("[OK] wrote {0} bind value(s) to {1}".format(len(binds), out_file))
        print("     Use with: {0} genexec -s {1} -f target.sql -b {2} --run".format(
            PROG, args.src_sqlid, out_file))
        if args.verbose:
            for i, v in enumerate(binds, 1):
                print("     [{0}] {1}".format(i, "NULL" if v is None else v))
        return 0

    # --- export ---
    if args.mode == "export":
        print("[INFO] export: fetching SQL for sql_id={0}".format(args.src_sqlid))
        sql_text = fetch_sql_by_sqlid(args.src_sqlid, conn, yasql, schema)
        if not sql_text:
            print("[ERROR] could not fetch SQL (sql_id not in v$sql or connection failed)")
            return 1
        out_file = args.out or "sql_" + args.src_sqlid + ".sql"
        write_file(out_file, sql_text + ";")
        print("[OK] exported {0} chars to {1}".format(len(sql_text), out_file))
        return 0

    # --- genexec ---
    if args.mode == "genexec":
        print("[INFO] genexec: source={0} file={1}".format(args.src_sqlid, args.sql_file))
        sql = load_file(args.sql_file)
        n_binds = count_binds(sql)
        if args.bind_file:
            binds = load_binds(args.bind_file)
            print("[INFO] binds: loaded {0} from {1}".format(len(binds), args.bind_file))
        elif n_binds > 0:
            print("[INFO] target SQL has {0} ? placeholders; auto-fetching binds from v$sql_bind_capture (sql_id={1})".format(n_binds, args.src_sqlid))
            binds = fetch_binds_by_sqlid(args.src_sqlid, conn, yasql, schema)
            if binds:
                print("[OK] auto-fetched {0} bind value(s) from source sql_id".format(len(binds)))
            else:
                print("[WARN] no bind values found in v$sql_bind_capture; use 'genbind -s {0}' or provide -b".format(args.src_sqlid))
        else:
            binds = []
        marker = args.marker or ("/* " + args.label + "_" + str(os.getpid()) + " */")
        script = gen_exec_script(sql, binds, args.label, marker, args.chunk)
        out_file = args.out or "exec_" + args.src_sqlid + ".sql"
        write_file(out_file, script)
        print("[OK] exec script: {0}  binds={1}  marker={2}".format(out_file, len(binds), marker))
        if args.run:
            print("[INFO] executing yasql...")
            out = yasql_exec(out_file, conn, yasql, schema)
            print(out)
        else:
            print("[INFO] use --run to execute directly, or:")
            print("       yasql -S \"{0}\" @{1}".format(conn, out_file))
        return 0

    # --- perf ---
    if args.mode == "perf":
        print("[INFO] perf: source={0} (read v$sql stats, no execution)".format(args.src_sqlid))
        tgt_sql = load_file(args.sql_file) if args.sql_file else ""
        if tgt_sql:
            print("[INFO] target={0} (execute with binds if any)".format(args.sql_file))
        n_binds = count_binds(tgt_sql) if tgt_sql else 0
        if args.bind_file:
            binds = load_binds(args.bind_file)
            print("[INFO] binds: loaded {0} from {1}".format(len(binds), args.bind_file))
        elif n_binds > 0:
            print("[INFO] target has {0} ? binds; auto-fetching from v$sql_bind_capture (sql_id={1})".format(n_binds, args.src_sqlid))
            binds = fetch_binds_by_sqlid(args.src_sqlid, conn, yasql, schema)
            if binds:
                print("[OK] auto-fetched {0} bind value(s)".format(len(binds)))
            else:
                print("[WARN] no bind values in v$sql_bind_capture; provide -b manually")
        else:
            binds = []
        script = gen_perf_script(args.src_sqlid, tgt_sql, binds, args.label, "", args.chunk)
        out_file = args.out or "perf_" + args.src_sqlid + ".sql"
        write_file(out_file, script)
        print("[OK] perf script: {0}".format(out_file))
        print("[INFO] executing yasql...")
        out = yasql_exec(out_file, conn, yasql, schema)
        print(out)
        for ln in out.splitlines():
            if any(k in ln for k in ["SRC_", "TGT_", "CNT", "ELAPSED", "BUFGETS"]):
                print("  {0}".format(ln.strip()))
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
