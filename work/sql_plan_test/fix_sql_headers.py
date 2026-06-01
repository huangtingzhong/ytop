#!/usr/bin/env python3
"""Normalize SQL headers and English comments under internal/scripts/sql."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path("/Users/yihan/tool/develop/yastop/internal/scripts/sql")

ENGINE_LABEL = {
    "yashandb": "YashanDB",
    "oracle": "Oracle",
    "postgresql": "PostgreSQL",
    "mysql": "MySQL",
    "dameng": "Dameng",
}

# basename -> purpose (no engine prefix); applied when <=50 chars with engine prefix
PURPOSE_BY_NAME: dict[str, str] = {
    "arch_delete_all.sql": "Delete all archivelog for the database",
    "arch_dest_status.sql": "Show archive destination status and gaps",
    "awr.sql": "Show AWR load profile metrics by snapshot",
    "awr_create.sql": "Create a manual AWR snapshot",
    "awr_event_avg_time_trend.sql": "AWR event avg wait time by day and hour",
    "awr_event_top5.sql": "Show top 5 wait events from AWR",
    "awr_snapshot.sql": "List AWR snapshots with DB time",
    "awr_sql_by_buffer_gets_by_day.sql": "AWR top SQL by buffer gets per day",
    "awr_sql_by_cpu_by_day.sql": "AWR top SQL by CPU time per day",
    "awr_sql_by_disk_reads_by_day.sql": "AWR top SQL by disk reads per day",
    "awr_sql_by_elapsed_by_day.sql": "AWR top SQL by elapsed time per day",
    "awr_top_sql_last_day.sql": "Top-N AWR SQL last day with plan and objects",
    "awr_top_sql_last_day_opt.sql": "Top-N AWR SQL last day, shared object scan",
    "awr_top_sql_last_snap.sql": "Top-N AWR SQL for latest snapshot only",
    "checkpoint.sql": "Show checkpoint progress information",
    "constraint_table.sql": "List table constraints and referenced keys",
    "datafile.sql": "Show datafile and tablespace usage details",
    "db.sql": "Show database open mode and log status",
    "db_size.sql": "Show tablespace size and free space",
    "db_version.sql": "Show database version and instance info",
    "dblink.sql": "List database links and connection status",
    "ddl_table.sql": "List DDL history for a table",
    "dump_block.sql": "Dump data block and print trace file path",
    "dump_sid.sql": "Dump session state to trace by SID",
    "find_sql.sql": "Find SQL in V$SQL by text fragment",
    "gv_vm.sql": "Show global VM and SGA memory summary",
    "kill_sess_by_where.sql": "Kill sessions matching filter predicates",
    "lock_tree.sql": "Show row and table lock wait tree",
    "lock_tx_tree.sql": "Show transaction lock wait tree",
    "logfile.sql": "Show online redo log member status",
    "logfile_add_redo.sql": "Add or resize redo log groups online",
    "logfile_swich.sql": "Switch redo log file",
    "mysid.sql": "Show current session SID and basic info",
    "object.sql": "Search objects by owner and name pattern",
    "parameter.sql": "Show instance parameters and defaults",
    "print_table.sql": "Print query rows in vertical G style",
    "redo_add.sql": "Recreate redo logs by count size and path",
    "segment.sql": "Show segment size by owner and name",
    "sess_time_model.sql": "Session time model stats for interval",
    "sid_undo.sql": "Show undo usage for a session",
    "sql.sql": "SQL tuning report with plan and objects",
    "sql10.sql": "SQL tuning report with plan and objects",
    "sql_bind_by_sqlid.sql": "Expand SQL text with bind values",
    "sql_by_sqlid.sql": "Show SQL details by sql_id",
    "standby.sql": "Show standby database apply status",
    "standby_switch_max_avai.sql": "Switch standby to max availability",
    "standby_switch_max_perf.sql": "Switch standby to max performance",
    "standby_switch_max_prot.sql": "Switch standby to max protection",
    "table.sql": "Show table storage and column summary",
    "table_column.sql": "Show table columns and data types",
    "table_index.sql": "Show indexes for a table",
    "table_part_size.sql": "Partition and LOB size by table",
    "table_size.sql": "Show table and index size with LOB",
    "user.sql": "Show database users and profiles",
    "user_all_priv.sql": "Show user roles and object privileges",
    "we.sql": "Session wait and SQL overview",
    "we_23.5.sql": "Session overview for YashanDB 23.5",
    "yfs_disk.sql": "Show YFS disk path and mount status",
    "yfs_diskgroup.sql": "Show YFS diskgroup space usage",
    "files.sql": "Show InnoDB tablespace file usage",
    "innodb_lock_waits.sql": "Show InnoDB lock wait chains",
    "lock_by_object.sql": "Show locks held on a database object",
    "lock_innodb.sql": "Show InnoDB lock holders and waiters",
    "mdl_block.sql": "Show metadata lock blocking sessions",
    "mgr_member.sql": "Show MySQL Group Replication members",
    "mgr_stat.sql": "Show MySQL Group Replication status",
    "mysql_insert_test_data.sql": "Insert sample rows for MySQL testing",
    "replica_slave.sql": "Show replication slave status",
    "standby_config.sql": "Show standby replication configuration",
    "table_no_primary.sql": "List tables without a primary key",
    "kill_session_create.sql": "Create function to kill PG sessions",
    "extention.sql": "List installed PostgreSQL extensions",
    "rep.sql": "Show PostgreSQL replication overview",
    "rep_slot.sql": "Show replication slot status",
    "stream_info.sql": "Show logical replication stream info",
    "stream_gap.sql": "Show logical replication lag",
    "stream_off.sql": "Disable logical replication stream",
    "stream_on.sql": "Enable logical replication stream",
}

CN_REPLACEMENTS: list[tuple[str, str]] = [
    ("显示活动会话的统计信息", "active session statistics"),
    ("显示sql优化信息", "SQL tuning and execution plan report"),
    ("显示 SQL 优化信息", "SQL tuning and execution plan report"),
    ("根据WAITCLASS值，按EVENT,SQL_ID,CURRENT_OBJ排序，显示TOP 2的信息",
     "TOP 2 rows by WAIT_CLASS, EVENT, SQL_ID, CURRENT_OBJ"),
    ("用于快速的切换日志", "quick log switch helper"),
    ("用于给用户授权，输入用户列表和权限列表", "grant privileges to user list"),
    ("隐藏PL/SQL执行成功提示", "hide PL/SQL success messages"),
    ("列格式化设置", "column format settings"),
    ("清理列格式化设置", "clear column format settings"),
    ("清理column format settings", "clear column format settings"),
    ("转换 MAX_VALUE", "substitute MAX_VALUE"),
    ("过滤条件，例如 'pid=123', 'user=john', 'active'",
     "filter e.g. pid=123, user=john, active"),
    ("1=调试模式(只打印信息)，0=执行 kill", "1=debug print only, 0=execute kill"),
    ("计数器：成功杀死的会话数", "killed session counter"),
    ("1. 检查参数", "1) validate parameters"),
    ("2. 生成过滤条件", "2) build filter expression"),
    ("3. Debug 显示过滤条件", "3) debug: show filter"),
    ("4. 查询目标会话", "4) query target sessions"),
    ("5. 显示最终统计信息", "5) print final stats"),
    ("普通 vacuum trigger", "plain VACUUM trigger"),
    ("根据 classid 判断类型，解析名称", "resolve object name by classid"),
    ("只看普通表", "regular tables only"),
    ("下面是没有做锁的类型的判断，需要特别注意，在KILL的时候，看看是否为后台现场。",
     "No lock-type filter below; verify background thread before KILL."),
    ("其实也是可以通过下面这个视图来查询SELECT * FROM sys.schema_table_lock_waits",
     "Also query sys.schema_table_lock_waits"),
    ("上述所有的操作都会依赖于performance_schema.metadata_lock此表，这个表需要依赖于开启特定的功能。5.7需要手动开启，8.0默认已经开启",
     "Requires performance_schema.metadata_lock (manual on 5.7, default on 8.0)"),
    ("在线开启", "enable online"),
    ("支持 10g,11g,12c", "supports 10g, 11g, 12c"),
    ("初始版本，主要用于ash_total.sql结果运行后，使用ash_object_by_waitclass.sql来定位更详细的信息",
     "drill-down after ash_total.sql"),
    ("修复输入ON CPU时结果集返回为空的情况，ON CPU为session_state的状态。",
     "fix empty result when filtering ON CPU session_state"),
    ("添加分区索引的状态，添加索引分区信息", "partition index status and partitions"),
    ("增加索引的压缩，分区，临时等属性(UCPTDVS)", "index compression partition temp flags"),
    ("添加从ASH中获取执行计划步骤的统计信息，支持11GR2以上数据库",
     "ASH plan step stats for 11gR2+"),
    ("添加AWR sql_stat的信息", "add AWR sql_stat section"),
    ("添加10GR2版本的支持", "add 10gR2 support"),
    ("修复部分对象不能统计大小", "fix object size for some objects"),
    ("添加sql monitor信息，默认此功能是关闭的，通过_SQL_MONITOR来开启",
     "SQL monitor section via _SQL_MONITOR flag"),
    ("支持在cdb环境中运行，但是目前只支持在pdb中只能存在唯一一条sql_id的情况",
     "CDB/PDB support with single sql_id per PDB"),
    ("修改awr里性能数据显示的单位", "AWR perf unit display format"),
    ("修改SQL性能指标显示单位的格式", "SQL perf metric unit format"),
    ("添加在AWR中不在内存中的执行计划的显示", "show plans from AWR not in memory"),
    ("修改为绑定变量模式", "bind variable mode"),
    ("添加列统计信息的最小值和最大值的显示，通过_TABLE_COL_VALUE参数控制是否显示，默认不显示",
     "column min/max stats via _TABLE_COL_VALUE flag"),
    ("最近 N 天", "last N days"),
    ("崖山", "YashanDB"),
    ("验证方法：", "Verification:"),
    ("方案 A", "option A"),
    ("修改此处三行即可传参（组数/大小/路径）", "edit three lines for count/size/path"),
    ("PLAN：", "PLAN:"),
    ("规避 YAS-04458", "avoid YAS-04458"),
    ("用于 EXEC/DISK_GETS/ROWS 等", "for EXEC/DISK_GETS/ROWS"),
    ("用于 CPU/ELAPSED/WAIT 等每执行一次的时间", "per-exec CPU/ELAPSED/WAIT"),
]

HEADER_META = re.compile(
    r"^--\s*(File Name|Purpose|Created|Date)\s*:",
    re.I,
)
CREATED_LINE = re.compile(
    r"^--\s*Created:\s*(\d{8})(?:\s+by\s+\S+)?",
    re.I,
)
DATE_LINE = re.compile(r"^--\s*Date\s*:\s*(\d{4})/(\d{2})/(\d{2})", re.I)
CHINESE = re.compile(r"[\u4e00-\u9fff]")
MOJIBAKE = re.compile(r"\ufffd|[\u0080-\u009f]")
STRIP_TOP_COMMENT = re.compile(
    r"^--\s*("
    r"={3,}|"
    r"http|"
    r"www\.|"
    r"QQ:|"
    r"weixin|"
    r"tel:|"
    r"v\d+\.\d|"
    r"\d{8}\s|"
    r"PostgreSQL Kill|"
    r"Equivalent to Oracle|"
    r"Usage:\s*SELECT|"
    r"认真就输|"
    r"fork from|"
    r"YashanDB|"
    r"Verification"
    r")",
    re.I,
)
SQL_START = re.compile(
    r"^(SET|ALTER|SELECT|WITH|DECLARE|CREATE|DROP|INSERT|UPDATE|DELETE|"
    r"PROMPT|COLUMN|BEGIN|@|REM\b|\)|EXEC\b|SHOW\b|USE\b|GRANT\b)",
    re.I,
)
TOKEN_MAP = {
    "awr": "AWR",
    "ash": "ASH",
    "sql": "SQL",
    "db": "DB",
    "sess": "session",
    "obj": "object",
    "priv": "privileges",
    "stat": "stats",
    "topsql": "top SQL",
    "topsess": "top sessions",
    "topplan": "top plan",
    "dstat": "DSTAT",
    "ogg": "OGG",
    "mdl": "MDL",
    "innodb": "InnoDB",
    "mgr": "MGR",
    "rep": "replication",
    "pg": "PG",
}


def engine_for(path: Path) -> str:
    rel = path.relative_to(ROOT)
    if rel.parts:
        return ENGINE_LABEL.get(rel.parts[0], rel.parts[0].title())
    return ""


def title_words(stem: str) -> str:
    parts = re.split(r"[_\-]+", stem)
    out: list[str] = []
    for p in parts:
        if not p:
            continue
        low = p.lower()
        if low in TOKEN_MAP:
            out.append(TOKEN_MAP[low])
        elif low.isdigit():
            out.append(p)
        else:
            out.append(p[:1].upper() + p[1:].lower() if len(p) > 1 else p.upper())
    return " ".join(out)


def fit_purpose(text: str, limit: int = 50) -> str:
    text = re.sub(r"\s+", " ", text.strip())
    if len(text) <= limit:
        return text
    cut = text[:limit].rsplit(" ", 1)[0]
    return cut if cut else text[:limit]


def purpose_for(path: Path) -> str:
    name = path.name
    eng = engine_for(path)
    if name in PURPOSE_BY_NAME:
        base = PURPOSE_BY_NAME[name]
    else:
        base = title_words(path.stem)
    if eng and not base.lower().startswith(eng.lower()):
        purpose = fit_purpose(f"{eng} {base}")
    else:
        purpose = fit_purpose(base)
    if name in PURPOSE_BY_NAME and eng:
        alt = fit_purpose(f"{eng} {PURPOSE_BY_NAME[name]}")
        if len(alt) <= 50:
            purpose = alt
    return purpose


def extract_created(lines: list[str]) -> str:
    for ln in lines[:30]:
        s = ln.strip()
        m = CREATED_LINE.match(s)
        if m:
            return f"{m.group(1)}  by  huangtingzhong"
        dm = DATE_LINE.match(s)
        if dm:
            return f"{dm.group(1)}{dm.group(2)}{dm.group(3)}  by  huangtingzhong"
        m2 = re.match(r"^--\s*Created:\s*(\d{4})/(\d{2})/(\d{2})", s, re.I)
        if m2:
            return f"{m2.group(1)}{m2.group(2)}{m2.group(3)}  by  huangtingzhong"
    return "20260516  by  huangtingzhong"


def is_legacy_top_comment(line: str) -> bool:
    s = line.strip()
    if not s.startswith("--"):
        return False
    if HEADER_META.match(s):
        return True
    if STRIP_TOP_COMMENT.search(s):
        return True
    if CHINESE.search(s) or MOJIBAKE.search(s):
        return True
    if re.match(r"^--\s*20\d{6}\b", s):
        return True
    if re.match(r"^--\s*201\d", s):
        return True
    return False


def strip_header(lines: list[str]) -> list[str]:
    i = 0
    while i < len(lines):
        s = lines[i].strip()
        if not s:
            i += 1
            continue
        if is_legacy_top_comment(s):
            i += 1
            continue
        if s.startswith("--") and i < 40:
            # drop short orphan English preamble before SQL
            if re.match(r"^--\s*(Example|Note|History)\b", s, re.I):
                i += 1
                continue
        break
    return lines[i:]


def translate_cn(text: str) -> str:
    for cn, en in CN_REPLACEMENTS:
        text = text.replace(cn, en)
    return text


def fix_file(path: Path) -> list[int]:
    raw = path.read_text(encoding="utf-8", errors="replace")
    lines = raw.splitlines()
    created = extract_created(lines)
    body = strip_header(lines)
    purpose = purpose_for(path)
    header = [
        f"-- File Name: {path.name}",
        f"-- Purpose: {purpose}",
        f"-- Created: {created}",
        "",
    ]
    new_text = "\n".join(header + body)
    if raw.endswith("\n"):
        new_text += "\n"
    new_text = translate_cn(new_text)
    path.write_text(new_text, encoding="utf-8")
    issues: list[int] = []
    if CHINESE.search(new_text) or MOJIBAKE.search(new_text):
        for i, ln in enumerate(new_text.splitlines(), 1):
            if CHINESE.search(ln) or MOJIBAKE.search(ln):
                issues.append(i)
    return issues


def verify_all() -> list[tuple[str, str]]:
    problems: list[tuple[str, str]] = []
    for p in sorted(ROOT.rglob("*.sql")):
        rel = str(p.relative_to(ROOT))
        text = p.read_text(encoding="utf-8", errors="replace")
        lines = text.splitlines()
        if len(lines) < 3:
            problems.append((rel, "too short"))
            continue
        fn = re.match(r"^-- File Name:\s*(.+)$", lines[0])
        pu = re.match(r"^-- Purpose:\s*(.+)$", lines[1])
        cr = re.match(r"^-- Created:\s*(\d{8})\s+by\s+(\S+)$", lines[2])
        if not fn or fn.group(1).strip() != p.name:
            problems.append((rel, f"bad File Name: {lines[0][:50]}"))
        if not pu:
            problems.append((rel, "missing Purpose"))
        elif len(pu.group(1)) > 50:
            problems.append((rel, f"Purpose len {len(pu.group(1))}"))
        if not cr or cr.group(2) != "huangtingzhong":
            problems.append((rel, f"bad Created: {lines[2][:50]}"))
        if CHINESE.search(text) or MOJIBAKE.search(text):
            problems.append((rel, "non-English text remains"))
    return problems


def main() -> None:
    remaining: dict[str, list[int]] = {}
    files = sorted(ROOT.rglob("*.sql"))
    for p in files:
        left = fix_file(p)
        if left:
            remaining[str(p.relative_to(ROOT))] = left[:10]
    print(f"processed {len(files)} files under {ROOT}")
    if remaining:
        print(f"remaining non-English lines in {len(remaining)} files:")
        for n, lines in list(remaining.items())[:40]:
            print(f"  {n}: {lines}")
        if len(remaining) > 40:
            print(f"  ... and {len(remaining) - 40} more")
    problems = verify_all()
    print(f"compliance issues: {len(problems)}")
    for rel, msg in problems[:25]:
        print(f"  {rel}: {msg}")
    if len(problems) > 25:
        print(f"  ... and {len(problems) - 25} more")


if __name__ == "__main__":
    main()
