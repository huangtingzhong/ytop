-- File Name: lock_tree.sql
-- Purpose: YashanDB row/table lock wait tree (compact, no wrap)
-- Created: 20251208  by  huangtingzhong

col Lvl        for a1
col WaitSess   for a19
col WaitUser   for a14
col WaitStat   for a10
col BlockSess  for a19
col BlockUser  for a14
col BlockStat  for a10
col LockType   for a10
col WaitEvent  for a22
col WaitSQL    for a20
col BlockSQL   for a20
col TableName  for a28
col ResourceID for a14
col WaitTime   for a5
col HoldTime   for a5

WITH 
row_lockwait AS (
    SELECT 
        l.inst_id,
        l.sid AS request_sid, 
        l.request AS request_lock, 
        l.id1 AS resource_id,
        s.serial# AS request_serial#,
        s.username AS request_username,
        'ROW->ROW' AS lock_type,
        s.sql_id,substr(s.wait_event,1,18) event,sysdate-s.EXEC_START_TIME exec_time,s.EXEC_STATUS,
        NULL AS table_name
    FROM gv$lock l, gv$session s
    WHERE l.sid = s.sid
      AND l.inst_id = s.inst_id
      AND l.request = 'ROW'
),
row_blocking AS (
    SELECT 
        r.inst_id,
        r.request_sid,
        r.request_serial#,
        r.request_username,
        r.request_lock,
        r.lock_type,
        r.resource_id,
        r.table_name,
        s.inst_id AS blocking_inst,
        t.sid AS blocking_sid,
        s.serial# AS blocking_serial#,
        s.username AS blocking_username,
        r.sql_id b_sqlid,r.event b_event,r.exec_time b_exec_time,r.EXEC_STATUS b_exec_status,
        s.sql_id h_sqlid,substr(s.wait_event,1,18) h_event,sysdate-s.EXEC_START_TIME h_exec_time,s.EXEC_STATUS h_exec_status
    FROM row_lockwait r, gv$transaction t, gv$session s
    WHERE r.resource_id = t.xid
      AND t.inst_id = r.inst_id
      AND t.sid = s.sid
      AND t.inst_id = s.inst_id
),
ts_lockwait AS (
    SELECT 
        l.inst_id,
        l.sid AS request_sid, 
        l.request AS request_lock, 
        l.id1 AS resource_id,
        s.serial# AS request_serial#,
        s.username AS request_username,
        'TS->TX' AS lock_type,s.sql_id,substr(s.wait_event,1,18) event,sysdate-s.EXEC_START_TIME exec_time,s.EXEC_STATUS
    FROM gv$lock l, gv$session s
    WHERE l.sid = s.sid
      AND l.inst_id = s.inst_id
      AND l.request = 'TS'
),
ts_blocking AS (
    SELECT DISTINCT
        w.inst_id,
        w.request_sid,
        w.request_serial#,
        w.request_username,
        w.request_lock,
        w.lock_type,
        w.resource_id,
        o.owner || '.' || o.object_name AS table_name,
        gl.inst_id AS blocking_inst,
        gl.sid AS blocking_sid,
        s.serial# AS blocking_serial#,
        s.username AS blocking_username,
        w.sql_id b_sqlid,w.event b_event,w.exec_time b_exec_time,w.EXEC_STATUS b_exec_status,
        s.sql_id h_sqlid,substr(s.wait_event,1,18) h_event,sysdate-s.EXEC_START_TIME h_exec_time,s.EXEC_STATUS h_exec_status
    FROM ts_lockwait w, gv$lock gl, gv$session s, dba_objects o
    WHERE gl.id1 = w.resource_id
      AND (gl.request = 'TX' or gl.lmode = 'TX')
      AND gl.inst_id = w.inst_id
      AND gl.sid = s.sid
      AND gl.inst_id = s.inst_id
      AND w.resource_id = o.object_id(+)
),
-- 3. Table lock waits: TX waiting on TS lock (X waiting on S)
tx_lockwait AS (
    SELECT 
        l.inst_id,
        l.sid AS request_sid, 
        l.request AS request_lock, 
        l.id1 AS resource_id,
        s.serial# AS request_serial#,
        s.username AS request_username,
        'TX->TS' AS lock_type,s.sql_id,substr(s.wait_event,1,18) event,sysdate-s.EXEC_START_TIME exec_time,s.EXEC_STATUS
    FROM gv$lock l, gv$session s
    WHERE l.sid = s.sid
      AND l.inst_id = s.inst_id
      AND l.request = 'TX'
),
tx_blocking AS (
    SELECT 
        w.inst_id,
        w.request_sid,
        w.request_serial#,
        w.request_username,
        w.request_lock,
        w.lock_type,
        w.resource_id,
        o.owner || '.' || o.object_name AS table_name,
        gl.inst_id AS blocking_inst,
        gl.sid AS blocking_sid,
        s.serial# AS blocking_serial#,
        s.username AS blocking_username,
        w.sql_id b_sqlid,w.event b_event,w.exec_time b_exec_time,w.EXEC_STATUS b_exec_status,
        s.sql_id h_sqlid,substr(s.wait_event,1,18) h_event,sysdate-s.EXEC_START_TIME h_exec_time,s.EXEC_STATUS h_exec_status
    FROM tx_lockwait w, gv$lock gl, gv$session s, dba_objects o
    WHERE gl.id1 = w.resource_id
      AND gl.lmode = 'TS'
      AND gl.inst_id = w.inst_id
      AND gl.sid = s.sid
      AND gl.inst_id = s.inst_id
      AND w.resource_id = o.object_id(+)
),
all_lock_chain AS (
    SELECT * FROM row_blocking
    UNION ALL
    SELECT * FROM ts_blocking
    UNION ALL
    SELECT * FROM tx_blocking
),
fmt AS (
  SELECT a.*,
         TRUNC(EXTRACT(DAY FROM a.b_exec_time) * 86400 +
               EXTRACT(HOUR FROM a.b_exec_time) * 3600 +
               EXTRACT(MINUTE FROM a.b_exec_time) * 60 +
               EXTRACT(SECOND FROM a.b_exec_time)) AS b_sec,
         TRUNC(EXTRACT(DAY FROM a.h_exec_time) * 86400 +
               EXTRACT(HOUR FROM a.h_exec_time) * 3600 +
               EXTRACT(MINUTE FROM a.h_exec_time) * 60 +
               EXTRACT(SECOND FROM a.h_exec_time)) AS h_sec
    FROM all_lock_chain a
)
SELECT TO_CHAR(LEVEL) AS Lvl,
       SUBSTR(LPAD(' ', 2 * (LEVEL - 1)) ||
              TO_CHAR(a.inst_id) || '.' || TO_CHAR(a.request_sid) || '.' ||
              TO_CHAR(a.request_serial#), 1, 19) AS WaitSess,
       SUBSTR(a.request_username, 1, 14) AS WaitUser,
       SUBSTR(a.b_exec_status, 1, 10) AS WaitStat,
       SUBSTR(TO_CHAR(a.blocking_inst) || '.' || TO_CHAR(a.blocking_sid) || '.' ||
              TO_CHAR(a.blocking_serial#), 1, 19) AS BlockSess,
       SUBSTR(a.blocking_username, 1, 14) AS BlockUser,
       SUBSTR(a.h_exec_status, 1, 10) AS BlockStat,
       SUBSTR(a.lock_type, 1, 10) AS LockType,
       SUBSTR(a.b_event, 1, 22) AS WaitEvent,
       SUBSTR(a.b_sqlid, 1, 20) AS WaitSQL,
       SUBSTR(a.h_sqlid, 1, 20) AS BlockSQL,
       SUBSTR(a.table_name, 1, 28) AS TableName,
       SUBSTR(TO_CHAR(a.resource_id), 1, 14) AS ResourceID,
       SUBSTR(
         CASE
           WHEN a.b_sec < 1 THEN TO_CHAR(ROUND(a.b_sec * 1000)) || 'MS'
           WHEN a.b_sec < 10000 THEN TO_CHAR(ROUND(a.b_sec)) || 'S'
           WHEN a.b_sec < 36000 THEN TO_CHAR(ROUND(a.b_sec / 60)) || 'M'
           ELSE TO_CHAR(ROUND(a.b_sec / 3600)) || 'H'
         END, 1, 5) AS WaitTime,
       SUBSTR(
         CASE
           WHEN a.h_sec < 1 THEN TO_CHAR(ROUND(a.h_sec * 1000)) || 'MS'
           WHEN a.h_sec < 10000 THEN TO_CHAR(ROUND(a.h_sec)) || 'S'
           WHEN a.h_sec < 36000 THEN TO_CHAR(ROUND(a.h_sec / 60)) || 'M'
           ELSE TO_CHAR(ROUND(a.h_sec / 3600)) || 'H'
         END, 1, 5) AS HoldTime
FROM fmt a
START WITH NOT EXISTS (
    SELECT 1 FROM all_lock_chain a2
    WHERE a2.request_sid = a.blocking_sid
      AND a2.inst_id = a.inst_id
)
CONNECT BY PRIOR a.request_sid = a.blocking_sid
       AND PRIOR a.inst_id = a.inst_id
ORDER SIBLINGS BY a.lock_type, a.request_sid;

