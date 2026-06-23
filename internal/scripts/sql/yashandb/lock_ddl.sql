-- File Name: lock_ddl.sql
-- Purpose: YashanDB DDL/table lock holder and waiter (TS/ROW/TM/TX)
-- Created: 20260616  by  huangtingzhong

col LockRole   for a4
col SessID     for a19
col UserName   for a14
col SessStat   for a10
col CmdType    for a12
col SqlID      for a20
col PrevSQL    for a20
col WaitEvent  for a22
col LockMode   for a8
col ReqLock    for a8
col LockObj    for a36
col TxnID      for a16
col WaitTime   for a5

WITH base AS (
  SELECT a.lmode,
         a.request,
         a.id1,
         a.inst_id,
         a.sid,
         b.serial#,
         b.username,
         b.status,
         b.command,
         b.sql_id,
         b.prev_sql_id,
         b.wait_event,
         NVL(o.owner || '.' || o.object_name, TO_CHAR(lo.object_id)) AS object_name,
         TRUNC(EXTRACT(DAY FROM (SYSDATE - b.exec_start_time)) * 86400 +
               EXTRACT(HOUR FROM (SYSDATE - b.exec_start_time)) * 3600 +
               EXTRACT(MINUTE FROM (SYSDATE - b.exec_start_time)) * 60 +
               EXTRACT(SECOND FROM (SYSDATE - b.exec_start_time))) AS exec_sec
    FROM gv$lock a
    JOIN gv$session b
      ON a.sid = b.sid AND a.inst_id = b.inst_id
    LEFT JOIN gv$locked_object lo
      ON lo.session_id = b.sid AND lo.inst_id = b.inst_id
    LEFT JOIN dba_objects o
      ON o.object_id = lo.object_id
   WHERE b.type != 'BACKGROUND'
     AND (a.lmode IS NOT NULL OR a.request IS NOT NULL)
     AND (a.lmode IN ('ROW', 'TX', 'TS', 'TM') OR a.request IN ('ROW', 'TX', 'TS', 'TM'))
)
SELECT SUBSTR(CASE WHEN x.request IS NOT NULL THEN 'Wait' ELSE 'Hold' END, 1, 4) AS LockRole,
       SUBSTR(TO_CHAR(x.inst_id) || '.' || TO_CHAR(x.sid) || '.' ||
              TO_CHAR(x.serial#), 1, 19) AS SessID,
       SUBSTR(x.username, 1, 14) AS UserName,
       SUBSTR(x.status, 1, 10) AS SessStat,
       SUBSTR(TO_CHAR(x.command), 1, 12) AS CmdType,
       SUBSTR(x.sql_id, 1, 20) AS SqlID,
       SUBSTR(x.prev_sql_id, 1, 20) AS PrevSQL,
       SUBSTR(x.wait_event, 1, 22) AS WaitEvent,
       SUBSTR(x.lmode, 1, 8) AS LockMode,
       SUBSTR(x.request, 1, 8) AS ReqLock,
       SUBSTR(x.object_name, 1, 36) AS LockObj,
       SUBSTR(TO_CHAR(x.id1), 1, 16) AS TxnID,
       SUBSTR(
         CASE
           WHEN x.exec_sec < 1 THEN TO_CHAR(ROUND(x.exec_sec * 1000)) || 'MS'
           WHEN x.exec_sec < 10000 THEN TO_CHAR(ROUND(x.exec_sec)) || 'S'
           WHEN x.exec_sec < 36000 THEN TO_CHAR(ROUND(x.exec_sec / 60)) || 'M'
           ELSE TO_CHAR(ROUND(x.exec_sec / 3600)) || 'H'
         END, 1, 5) AS WaitTime
  FROM base x
 ORDER BY x.id1, LockRole DESC, x.sid;
