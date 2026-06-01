-- File Name: we.sql
-- Purpose: YashanDB Session wait and SQL overview
-- Created: 20251201  by  huangtingzhong

col SID_TID           for a20
col PROGRAM           for a30
col EVENT             for a30
col USERNAME          for a15
col SQL_ID            for a18
col EXEC_TIME         for a8
col CLIENT            for a20

SELECT 
    sid_tid,
    event,
    username,
    sql_id,
    CASE 
        WHEN exec_ms < 1000 THEN 
            ROUND(exec_ms, 0) || 'MS'
        WHEN exec_ms < 60000 THEN 
            ROUND(exec_ms / 1000, 2) || 'S'
        WHEN exec_ms < 3600000 THEN 
            ROUND(exec_ms / 60000, 2) || 'M'
        WHEN exec_ms < 86400000 THEN 
            ROUND(exec_ms / 3600000, 2) || 'H'
        ELSE 
            ROUND(exec_ms / 86400000, 2) || 'D'
    END AS exec_time,
    program,
    client 
FROM (
    SELECT 
        x.sid_tid,
        x.event,
        x.username,
        x.program,
        x.sql_id,
        GREATEST(0,
            EXTRACT(DAY FROM x.exec_delta) * 86400000 +
            EXTRACT(HOUR FROM x.exec_delta) * 3600000 +
            EXTRACT(MINUTE FROM x.exec_delta) * 60000 +
            EXTRACT(SECOND FROM x.exec_delta) * 1000
        ) AS exec_ms,
        x.client
    FROM (
        SELECT 
            a.inst_id||'.'||a.sid||'.'||a.serial#||'.'||b.thread_id AS sid_tid,
            substr(a.wait_event,1,30) AS event,
            a.username AS username,
            substr(a.cli_program,1,30) AS program,
            substr(c.command_name,1,3)||'.'||nvl(a.sql_id,a.sql_id) AS sql_id,
            CAST(
                CAST(SYSTIMESTAMP AS TIMESTAMP(6)) - CAST(a.exec_start_time AS TIMESTAMP(6))
                AS INTERVAL DAY(9) TO SECOND(6)
            ) AS exec_delta,
            a.ip_address||'.'||a.ip_port AS client
        FROM gv$session a, gv$process b, v$SQLCOMMAND c  
        WHERE a.inst_id = b.inst_id 
          AND a.paddr = b.thread_addr  
          AND a.command = c.command_type(+)
          AND a.TYPE NOT IN ('BACKGROUND')
          AND a.status NOT IN ('INACTIVE') 
          AND NOT (a.INST_ID = TO_NUMBER(SYS_CONTEXT('USERENV', 'INSTANCE'))
           AND a.SID = TO_NUMBER(SYS_CONTEXT('USERENV', 'SID')))
    ) x
    ORDER BY exec_ms DESC
)
/

SELECT 
      a.inst_id,a.sql_id,a.wait_event,count(*) hcount 
FROM gv$session a 
WHERE a.status NOT IN ('INACTIVE')  AND a.TYPE NOT IN ('BACKGROUND') 
      AND NOT (a.INST_ID = TO_NUMBER(SYS_CONTEXT('USERENV', 'INSTANCE'))
       AND a.SID = TO_NUMBER(SYS_CONTEXT('USERENV', 'SID')))
GROUP BY  inst_id,sql_id,wait_event HAVING count(*) >1
ORDER BY hcount
/
