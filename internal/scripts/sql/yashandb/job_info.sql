-- File Name: job_info.sql
-- Purpose: List all scheduler jobs with session when running
-- Created: 20260730 by huangtingzhong
--
-- Usage: ytop -f job_info.sql
-- Notes:
--   One query: core DBA_SCHEDULER_JOBS columns + session for RUNNING.
--   Display width budget <= 200 (sql-script-guide §3.2).

SET FEEDBACK OFF
SET VERIFY OFF

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | Scheduler jobs (DBA_SCHEDULER_JOBS + session)                          |
PROMPT +------------------------------------------------------------------------+


col OWNER      for a8
col JOB_NAME   for a16
col STATE      for a9
col ENABLED    for a5
col JOB_TYPE   for a8
col I          for a1
col RUN        for a3
col FAIL       for a2
col NEXT_RUN   for a16
col RPT        for a16
col LAST_DUR   for a10
col SID_TID    for a18
col EXEC_TIME  for a7
col LAST_START for a16
col COMMENTS   for a18

SELECT
    SUBSTR(j.owner, 1, 8) AS owner,
    SUBSTR(j.job_name, 1, 16) AS job_name,
    SUBSTR(j.state, 1, 9) AS state,
    CASE WHEN j.enabled THEN 'TRUE' ELSE 'FALSE' END AS enabled,
    SUBSTR(NVL(j.job_type, '-'), 1, 8) AS job_type,
    SUBSTR(TO_CHAR(NVL(j.running_instance, 0)), 1, 1) AS i,
    SUBSTR(TO_CHAR(NVL(j.run_count, 0)), 1, 3) AS run,
    SUBSTR(TO_CHAR(NVL(j.failure_count, 0)), 1, 2) AS fail,
    TO_CHAR(j.next_run_date, 'MM-DD HH24:MI:SS') AS next_run,
    SUBSTR(NVL(j.repeat_interval, '-'), 1, 16) AS rpt,
    SUBSTR(NVL(TO_CHAR(j.last_run_duration), '-'), 1, 10) AS last_dur,
    CASE
        WHEN j.state <> 'RUNNING' THEN NULL
        ELSE SUBSTR(
            NVL(TO_CHAR(a.inst_id), TO_CHAR(j.running_instance))
              ||'.'||NVL(TO_CHAR(a.sid), '-')
              ||'.'||NVL(TO_CHAR(a.serial#), '-')
              ||'.'||NVL(TO_CHAR(NVL(b.thread_id, schd.thread_id)), '-'),
            1, 18
        )
    END AS sid_tid,
    CASE
        WHEN j.state <> 'RUNNING' OR j.last_start_date IS NULL THEN NULL
        WHEN j.exec_ms < 1000 THEN ROUND(j.exec_ms, 0) || 'MS'
        WHEN j.exec_ms < 60000 THEN ROUND(j.exec_ms / 1000, 2) || 'S'
        WHEN j.exec_ms < 3600000 THEN ROUND(j.exec_ms / 60000, 2) || 'M'
        WHEN j.exec_ms < 86400000 THEN ROUND(j.exec_ms / 3600000, 2) || 'H'
        ELSE ROUND(j.exec_ms / 86400000, 2) || 'D'
    END AS exec_time,
    TO_CHAR(j.last_start_date, 'MM-DD HH24:MI:SS') AS last_start,
    SUBSTR(NVL(j.comments, '-'), 1, 18) AS comments
  FROM (
    SELECT
        owner,
        job_name,
        state,
        enabled,
        job_type,
        running_instance,
        run_count,
        failure_count,
        next_run_date,
        repeat_interval,
        last_run_duration,
        last_start_date,
        comments,
        GREATEST(0,
            EXTRACT(DAY FROM exec_delta) * 86400000 +
            EXTRACT(HOUR FROM exec_delta) * 3600000 +
            EXTRACT(MINUTE FROM exec_delta) * 60000 +
            EXTRACT(SECOND FROM exec_delta) * 1000
        ) AS exec_ms,
        CASE
            WHEN state = 'RUNNING' THEN
                ROW_NUMBER() OVER (
                    PARTITION BY CASE WHEN state = 'RUNNING' THEN NVL(running_instance, 1) END
                    ORDER BY last_start_date, job_name
                )
        END AS rn
      FROM (
        SELECT
            owner,
            job_name,
            state,
            enabled,
            job_type,
            running_instance,
            run_count,
            failure_count,
            next_run_date,
            repeat_interval,
            last_run_duration,
            last_start_date,
            comments,
            CASE
                WHEN state = 'RUNNING' AND last_start_date IS NOT NULL THEN
                    CAST(
                        CAST(SYSTIMESTAMP AS TIMESTAMP(6))
                          - CAST(last_start_date AS TIMESTAMP(6))
                        AS INTERVAL DAY(9) TO SECOND(6)
                    )
            END AS exec_delta
          FROM dba_scheduler_jobs
      )
  ) j
  LEFT JOIN gv$session a
    ON j.state = 'RUNNING'
   AND a.inst_id = NVL(j.running_instance, a.inst_id)
   AND (
          (a.action IS NOT NULL AND a.action = j.job_name)
       OR (a.module IS NOT NULL AND a.module = j.job_name)
   )
  LEFT JOIN gv$process b
    ON a.inst_id = b.inst_id
   AND a.paddr = b.thread_addr
  LEFT JOIN (
    SELECT
        inst_id,
        thread_id,
        ROW_NUMBER() OVER (
            PARTITION BY inst_id
            ORDER BY start_time, thread_id
        ) AS rn
      FROM gv$process
     WHERE name = 'DBMS_SCHEDULER'
  ) schd
    ON j.state = 'RUNNING'
   AND j.rn IS NOT NULL
   AND schd.inst_id = NVL(j.running_instance, schd.inst_id)
   AND schd.rn = j.rn
 ORDER BY CASE j.state WHEN 'RUNNING' THEN 0 ELSE 1 END,
          j.exec_ms DESC NULLS LAST,
          j.owner, j.job_name
/
