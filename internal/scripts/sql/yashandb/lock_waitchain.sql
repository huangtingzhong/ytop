-- File Name: lock_waitchain.sql
-- Purpose: YashanDB lock wait chain (single-line <= ~300 chars)
-- Note: Object = contended table on blocker session (one row per wait link).

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
chain_link AS (
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
         t.inst_id AS block_inst,
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
SELECT TO_CHAR(LEVEL) AS Lvl,
       SUBSTR(LPAD(' ', 2 * (LEVEL - 1)) ||
              TO_CHAR(c.inst_id) || '.' || TO_CHAR(c.wait_sid) || '.' ||
              TO_CHAR(c.wait_serial#), 1, 19) AS WaitSess,
       SUBSTR(c.wait_user, 1, 14) AS WaitUser,
       SUBSTR(c.wait_status, 1, 10) AS WaitStat,
       SUBSTR(TO_CHAR(c.block_inst) || '.' || TO_CHAR(c.block_sid) || '.' ||
              TO_CHAR(c.block_serial#), 1, 19) AS BlockSess,
       SUBSTR(c.block_user, 1, 14) AS BlockUser,
       SUBSTR(c.block_status, 1, 10) AS BlockStat,
       c.wait_event AS WaitEvent,
       SUBSTR(c.wait_sql_id, 1, 20) AS WaitSQL,
       SUBSTR(c.block_sql_id, 1, 20) AS BlockSQL,
       c.block_event AS BlockEvent,
       c.object_name AS Object,
       SUBSTR(TO_CHAR(c.xid), 1, 16) AS TxnID,
       SUBSTR(c.wait_lock, 1, 8) AS LockType,
       SUBSTR(
         CASE
           WHEN c.wait_sec < 1 THEN TO_CHAR(ROUND(c.wait_sec * 1000)) || 'MS'
           WHEN c.wait_sec < 10000 THEN TO_CHAR(ROUND(c.wait_sec)) || 'S'
           WHEN c.wait_sec < 36000 THEN TO_CHAR(ROUND(c.wait_sec / 60)) || 'M'
           ELSE TO_CHAR(ROUND(c.wait_sec / 3600)) || 'H'
         END, 1, 5) AS WaitTime
  FROM chain_link c
 START WITH NOT EXISTS (
   SELECT 1 FROM chain_link c2
    WHERE c2.wait_sid = c.block_sid AND c2.inst_id = c.inst_id
 )
CONNECT BY PRIOR c.wait_sid = c.block_sid
       AND PRIOR c.inst_id = c.inst_id
 ORDER SIBLINGS BY c.wait_sid;
