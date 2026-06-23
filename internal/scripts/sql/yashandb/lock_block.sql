-- File Name: lock_block.sql
-- Purpose: YashanDB lock waiters vs blockers (single-line <= ~300 chars)
-- Created: 20260615  by  huangtingzhong

col WaitSess   for a19
col WaitUser   for a14
col WaitStat   for a10
col BlockSess  for a19
col BlockUser  for a14
col BlockStat  for a10
col WaitEvent  for a22
col WaitSQL    for a20
col BlockSQL   for a20
col BlockEvent for a22
col Object     for a32
col TxnID      for a16
col LockType   for a8
col WaitTime   for a5

WITH row_wait AS (
  SELECT l.inst_id,
         l.sid AS wait_sid,
         l.id1 AS xid,
         l.request AS wait_lock,
         s.serial# AS wait_serial#,
         s.username AS wait_user,
         s.status AS wait_status,
         s.sql_id AS wait_sql_id,
         SUBSTR(s.wait_event, 1, 22) AS wait_event,
         TRUNC(EXTRACT(DAY FROM (SYSDATE - s.exec_start_time)) * 86400 +
               EXTRACT(HOUR FROM (SYSDATE - s.exec_start_time)) * 3600 +
               EXTRACT(MINUTE FROM (SYSDATE - s.exec_start_time)) * 60 +
               EXTRACT(SECOND FROM (SYSDATE - s.exec_start_time))) AS wait_sec
    FROM gv$lock l
    JOIN gv$session s ON l.sid = s.sid AND l.inst_id = s.inst_id
   WHERE l.request = 'ROW'
     AND s.type != 'BACKGROUND'
),
row_block AS (
  SELECT w.inst_id,
         w.wait_sid,
         w.wait_serial#,
         w.wait_user,
         w.wait_status,
         w.wait_sql_id,
         w.wait_event,
         w.wait_lock,
         w.wait_sec,
         w.xid,
         t.sid AS block_sid,
         bs.serial# AS block_serial#,
         bs.username AS block_user,
         bs.status AS block_status,
         bs.sql_id AS block_sql_id,
         SUBSTR(bs.wait_event, 1, 22) AS block_event,
         (SELECT SUBSTR(MAX(NVL(o.owner || '.' || o.object_name, '')), 1, 32)
            FROM gv$locked_object lo
            JOIN dba_objects o ON o.object_id = lo.object_id
           WHERE lo.session_id = t.sid
             AND lo.inst_id = t.inst_id) AS object_name
    FROM row_wait w
    JOIN gv$transaction t ON w.xid = t.xid AND w.inst_id = t.inst_id
    JOIN gv$session bs ON t.sid = bs.sid AND t.inst_id = bs.inst_id
)
SELECT SUBSTR(TO_CHAR(b.inst_id) || '.' || TO_CHAR(b.wait_sid) || '.' ||
              TO_CHAR(b.wait_serial#), 1, 19) AS WaitSess,
       SUBSTR(b.wait_user, 1, 14) AS WaitUser,
       SUBSTR(b.wait_status, 1, 10) AS WaitStat,
       SUBSTR(TO_CHAR(b.inst_id) || '.' || TO_CHAR(b.block_sid) || '.' ||
              TO_CHAR(b.block_serial#), 1, 19) AS BlockSess,
       SUBSTR(b.block_user, 1, 14) AS BlockUser,
       SUBSTR(b.block_status, 1, 10) AS BlockStat,
       b.wait_event AS WaitEvent,
       SUBSTR(b.wait_sql_id, 1, 20) AS WaitSQL,
       SUBSTR(b.block_sql_id, 1, 20) AS BlockSQL,
       b.block_event AS BlockEvent,
       b.object_name AS Object,
       SUBSTR(TO_CHAR(b.xid), 1, 16) AS TxnID,
       SUBSTR(b.wait_lock, 1, 8) AS LockType,
       SUBSTR(
         CASE
           WHEN b.wait_sec < 1 THEN TO_CHAR(ROUND(b.wait_sec * 1000)) || 'MS'
           WHEN b.wait_sec < 10000 THEN TO_CHAR(ROUND(b.wait_sec)) || 'S'
           WHEN b.wait_sec < 36000 THEN TO_CHAR(ROUND(b.wait_sec / 60)) || 'M'
           ELSE TO_CHAR(ROUND(b.wait_sec / 3600)) || 'H'
         END, 1, 5) AS WaitTime
  FROM row_block b
 ORDER BY b.wait_sid;
