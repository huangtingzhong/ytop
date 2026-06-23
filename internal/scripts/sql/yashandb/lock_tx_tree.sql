-- File Name: lock_tx_tree.sql
-- Purpose: YashanDB transaction lock wait tree (single-line <= ~300 chars)
-- Created: 20251208  by  huangtingzhong

col Lvl        for a1
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

WITH lockwait AS (
  SELECT l.inst_id,
         l.sid AS request_sid,
         l.request AS request_lock,
         l.id1 AS xid,
         s.serial# AS request_serial#,
         s.username AS request_username,
         s.status AS request_status,
         s.sql_id AS request_sql_id,
         SUBSTR(s.wait_event, 1, 22) AS request_event,
         TRUNC(EXTRACT(DAY FROM (SYSDATE - s.exec_start_time)) * 86400 +
               EXTRACT(HOUR FROM (SYSDATE - s.exec_start_time)) * 3600 +
               EXTRACT(MINUTE FROM (SYSDATE - s.exec_start_time)) * 60 +
               EXTRACT(SECOND FROM (SYSDATE - s.exec_start_time))) AS wait_sec
    FROM gv$lock l
    JOIN gv$session s ON l.sid = s.sid AND l.inst_id = s.inst_id
   WHERE l.request = 'ROW'
),
blocking_info AS (
  SELECT l.inst_id,
         l.request_sid,
         l.request_serial#,
         l.request_lock,
         l.request_username,
         l.request_status,
         l.request_sql_id,
         l.request_event,
         l.wait_sec,
         l.xid,
         t.inst_id AS blocking_inst_id,
         t.sid AS blocking_sid,
         s.serial# AS blocking_serial#,
         s.username AS blocking_username,
         s.status AS blocking_status,
         s.sql_id AS blocking_sql_id,
         SUBSTR(s.wait_event, 1, 22) AS blocking_event,
         (SELECT SUBSTR(MAX(NVL(o.owner || '.' || o.object_name, '')), 1, 32)
            FROM gv$locked_object lo
            JOIN dba_objects o ON o.object_id = lo.object_id
           WHERE lo.session_id = t.sid
             AND lo.inst_id = t.inst_id) AS object_name
    FROM lockwait l
    JOIN gv$transaction t ON l.xid = t.xid AND t.inst_id = l.inst_id
    JOIN gv$session s ON t.sid = s.sid AND t.inst_id = s.inst_id
)
SELECT TO_CHAR(LEVEL) AS Lvl,
       SUBSTR(LPAD(' ', 2 * (LEVEL - 1)) ||
              TO_CHAR(b.inst_id) || '.' || TO_CHAR(b.request_sid) || '.' ||
              TO_CHAR(b.request_serial#), 1, 19) AS WaitSess,
       SUBSTR(b.request_username, 1, 14) AS WaitUser,
       SUBSTR(b.request_status, 1, 10) AS WaitStat,
       SUBSTR(TO_CHAR(b.blocking_inst_id) || '.' || TO_CHAR(b.blocking_sid) || '.' ||
              TO_CHAR(b.blocking_serial#), 1, 19) AS BlockSess,
       SUBSTR(b.blocking_username, 1, 14) AS BlockUser,
       SUBSTR(b.blocking_status, 1, 10) AS BlockStat,
       b.request_event AS WaitEvent,
       SUBSTR(b.request_sql_id, 1, 20) AS WaitSQL,
       SUBSTR(b.blocking_sql_id, 1, 20) AS BlockSQL,
       b.blocking_event AS BlockEvent,
       b.object_name AS Object,
       SUBSTR(TO_CHAR(b.xid), 1, 16) AS TxnID,
       SUBSTR(b.request_lock, 1, 8) AS LockType,
       SUBSTR(
         CASE
           WHEN b.wait_sec < 1 THEN TO_CHAR(ROUND(b.wait_sec * 1000)) || 'MS'
           WHEN b.wait_sec < 10000 THEN TO_CHAR(ROUND(b.wait_sec)) || 'S'
           WHEN b.wait_sec < 36000 THEN TO_CHAR(ROUND(b.wait_sec / 60)) || 'M'
           ELSE TO_CHAR(ROUND(b.wait_sec / 3600)) || 'H'
         END, 1, 5) AS WaitTime
  FROM blocking_info b
 START WITH NOT EXISTS (
   SELECT 1 FROM lockwait l2
    WHERE l2.request_sid = b.blocking_sid AND l2.inst_id = b.inst_id
 )
CONNECT BY PRIOR b.request_sid = b.blocking_sid
       AND PRIOR b.inst_id = b.inst_id
 ORDER SIBLINGS BY b.request_sid;
