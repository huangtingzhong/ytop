-- File Name: rollback_stat.sql
-- Purpose: Rollback queue + session UNDO snapshot (each output line <= ~300 chars)
-- Created: 20260616  by  huangtingzhong

col Snap         for a19
col RbInfo       for a140
col UndoInfo     for a140
col Kind         for a3
col SessID       for a21
col UserName     for a16
col SessStat     for a7
col WaitEvent    for a40
col SqlID        for a26
col Program      for a42
col Client       for a28
col Ublk         for a9
col InPri        for a4
col RbStat       for a6
col SortRb       for a12
col Gap          for a4
col Xid          for a18
col TxAge        for a5
col ExecT        for a5
col Resid        for a5
col TxStat       for a6
col Isol         for a8
col Cmd          for a6
col Locks        for a16

WITH rb AS (
  SELECT COUNT(*) AS rb_cnt,
         NVL(SUM(CASE WHEN sort_pos > rb_pos THEN 1 ELSE 0 END), 0) AS queued,
         NVL(SUM(CASE WHEN sort_pos <= rb_pos THEN 1 ELSE 0 END), 0) AS reached,
         NVL(MIN(rb_pos), 0) AS min_rb,
         NVL(MAX(sort_pos), 0) AS max_sort,
         NVL(SUM(CASE WHEN in_priority = 'TRUE' THEN 1 ELSE 0 END), 0) AS pri_cnt,
         NVL(SUM(row_lock_count), 0) AS row_lk,
         NVL(SUM(table_lock_count), 0) AS tbl_lk,
         NVL(SUM(key_lock_count), 0) AS key_lk
    FROM gv$rollback
),
tx AS (
  SELECT COUNT(*) AS open_tx,
         NVL(SUM(used_ublk), 0) AS sum_ublk,
         NVL(MAX(used_ublk), 0) AS max_ublk,
         NVL(SUM(CASE WHEN residual = 'TRUE' THEN 1 ELSE 0 END), 0) AS residual
    FROM gv$transaction
   WHERE status = 'OPEN'
)
SELECT SUBSTR(TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'), 1, 19) AS snap,
       SUBSTR('RB cnt=' || TO_CHAR(rb.rb_cnt) ||
              ' q=' || TO_CHAR(rb.queued) ||
              ' r=' || TO_CHAR(rb.reached) ||
              ' pos=' || TO_CHAR(rb.min_rb) || '-' || TO_CHAR(rb.max_sort) ||
              ' gap=' || TO_CHAR(rb.max_sort - rb.min_rb) ||
              ' pri=' || TO_CHAR(rb.pri_cnt) ||
              ' lk=' || TO_CHAR(rb.row_lk) || '/' ||
              TO_CHAR(rb.tbl_lk) || '/' || TO_CHAR(rb.key_lk), 1, 140) AS rb_info,
       SUBSTR('TX open=' || TO_CHAR(tx.open_tx) ||
              ' res=' || TO_CHAR(tx.residual) ||
              ' ublk=' || TO_CHAR(tx.sum_ublk) || '/' || TO_CHAR(tx.max_ublk), 1, 140) AS undo_info
  FROM rb, tx;

WITH base AS (
  SELECT 'RB' AS kind,
         r.inst_id,
         r.sid,
         s.serial#,
         s.username,
         s.status,
         s.wait_event,
         s.sql_id,
         s.cli_program,
         s.ip_address,
         s.ip_port,
         s.command,
         r.xid,
         NVL(t.used_ublk, 0) AS used_ublk,
         t.status AS tx_status,
         t.residual,
         t.isolation_level,
         r.in_priority,
         CASE WHEN r.sort_pos > r.rb_pos THEN 'QUEUED'
              ELSE 'REACH' END AS rb_stat,
         r.sort_pos,
         r.rb_pos,
         r.sort_pos - r.rb_pos AS queue_gap,
         r.table_lock_count,
         r.row_lock_count,
         r.key_lock_count,
         TRUNC((SYSDATE - t.start_date) * 86400) AS tx_sec,
         TRUNC(EXTRACT(DAY FROM (SYSDATE - s.exec_start_time)) * 86400 +
               EXTRACT(HOUR FROM (SYSDATE - s.exec_start_time)) * 3600 +
               EXTRACT(MINUTE FROM (SYSDATE - s.exec_start_time)) * 60 +
               EXTRACT(SECOND FROM (SYSDATE - s.exec_start_time))) AS exec_sec
    FROM gv$rollback r
    LEFT JOIN gv$session s
      ON r.inst_id = s.inst_id AND r.sid = s.sid
    LEFT JOIN gv$transaction t
      ON r.inst_id = t.inst_id AND r.xid = t.xid
  UNION ALL
  SELECT 'TX' AS kind,
         t.inst_id,
         t.sid,
         s.serial#,
         s.username,
         s.status,
         s.wait_event,
         s.sql_id,
         s.cli_program,
         s.ip_address,
         s.ip_port,
         s.command,
         t.xid,
         t.used_ublk,
         t.status AS tx_status,
         t.residual,
         t.isolation_level,
         NULL AS in_priority,
         NULL AS rb_stat,
         NULL AS sort_pos,
         NULL AS rb_pos,
         NULL AS queue_gap,
         0 AS table_lock_count,
         0 AS row_lock_count,
         0 AS key_lock_count,
         TRUNC((SYSDATE - t.start_date) * 86400) AS tx_sec,
         TRUNC(EXTRACT(DAY FROM (SYSDATE - s.exec_start_time)) * 86400 +
               EXTRACT(HOUR FROM (SYSDATE - s.exec_start_time)) * 3600 +
               EXTRACT(MINUTE FROM (SYSDATE - s.exec_start_time)) * 60 +
               EXTRACT(SECOND FROM (SYSDATE - s.exec_start_time))) AS exec_sec
    FROM gv$transaction t
    JOIN gv$session s
      ON t.inst_id = s.inst_id AND t.sid = s.sid AND t.xid = s.xid
   WHERE t.status = 'OPEN'
     AND NVL(t.used_ublk, 0) > 0
     AND NOT EXISTS (
           SELECT 1 FROM gv$rollback r
            WHERE r.inst_id = t.inst_id AND r.xid = t.xid
         )
     AND s.type != 'BACKGROUND'
)
SELECT SUBSTR(x.kind, 1, 3) AS kind,
       SUBSTR(TO_CHAR(x.inst_id) || '.' || TO_CHAR(x.sid) || '.' ||
              TO_CHAR(x.serial#), 1, 21) AS sess_id,
       SUBSTR(NVL(x.username, '-'), 1, 16) AS user_name,
       SUBSTR(NVL(x.status, '-'), 1, 7) AS sess_stat,
       SUBSTR(NVL(x.wait_event, '-'), 1, 40) AS wait_event,
       SUBSTR(NVL(x.sql_id, '-'), 1, 26) AS sql_id,
       SUBSTR(NVL(x.cli_program, '-'), 1, 42) AS program,
       SUBSTR(NVL(x.ip_address, '-') || ':' || NVL(TO_CHAR(x.ip_port), '-'), 1, 28) AS client,
       SUBSTR(TO_CHAR(x.used_ublk), 1, 9) AS ublk,
       SUBSTR(NVL(x.in_priority, '-'), 1, 4) AS in_pri,
       SUBSTR(NVL(x.rb_stat, '-'), 1, 6) AS rb_stat,
       SUBSTR(NVL(TO_CHAR(x.sort_pos), '-') || '/' ||
              NVL(TO_CHAR(x.rb_pos), '-'), 1, 12) AS sort_rb,
       SUBSTR(NVL(TO_CHAR(x.queue_gap), '-'), 1, 4) AS gap,
       SUBSTR(TO_CHAR(x.xid), 1, 18) AS xid,
       SUBSTR(
         CASE
           WHEN NVL(x.tx_sec, 0) < 1 THEN TO_CHAR(ROUND(NVL(x.tx_sec, 0) * 1000)) || 'MS'
           WHEN NVL(x.tx_sec, 0) < 10000 THEN TO_CHAR(NVL(x.tx_sec, 0)) || 'S'
           WHEN NVL(x.tx_sec, 0) < 36000 THEN TO_CHAR(ROUND(NVL(x.tx_sec, 0) / 60)) || 'M'
           ELSE TO_CHAR(ROUND(NVL(x.tx_sec, 0) / 3600)) || 'H'
         END, 1, 5) AS tx_age,
       SUBSTR(
         CASE
           WHEN NVL(x.exec_sec, 0) < 1 THEN TO_CHAR(ROUND(NVL(x.exec_sec, 0) * 1000)) || 'MS'
           WHEN NVL(x.exec_sec, 0) < 10000 THEN TO_CHAR(NVL(x.exec_sec, 0)) || 'S'
           WHEN NVL(x.exec_sec, 0) < 36000 THEN TO_CHAR(ROUND(NVL(x.exec_sec, 0) / 60)) || 'M'
           ELSE TO_CHAR(ROUND(NVL(x.exec_sec, 0) / 3600)) || 'H'
         END, 1, 5) AS exec_t,
       SUBSTR(NVL(x.residual, '-'), 1, 5) AS resid,
       SUBSTR(NVL(x.tx_status, '-'), 1, 6) AS tx_stat,
       SUBSTR(NVL(x.isolation_level, '-'), 1, 8) AS isol,
       SUBSTR(NVL(TO_CHAR(x.command), '-'), 1, 6) AS cmd,
       SUBSTR(TO_CHAR(x.table_lock_count) || '/' ||
              TO_CHAR(x.row_lock_count) || '/' ||
              TO_CHAR(x.key_lock_count), 1, 16) AS locks
  FROM base x
 ORDER BY x.kind, x.sort_pos NULLS LAST, x.used_ublk DESC;
