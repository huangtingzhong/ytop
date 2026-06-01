-- File Name: ash_lock_stats.sql
-- Purpose: Oracle ASH Lock Stats
-- Created: 20260516  by  huangtingzhong

set echo off

set echo off
set verify off
set serveroutput on
set feedback off
set lines 200
set pages 40

  SELECT time,
         event,
         username,
         program,
         module,
         sql_id,
         sql_child_number,
         o_w,
         ROUND (SUM (time_waited) / 1000, 2) "TIME_WAITED(S)",
         RANK () OVER (PARTITION BY time ORDER BY SUM (time_waited)) time_rank,
         ROUND (
              SUM (time_waited)
            * 100
            / SUM (SUM (time_waited)) OVER (PARTITION BY time),
            2)
            AS "pct_of_time"
    FROM (SELECT    TO_CHAR (TRUNC (a.sample_time, 'HH'), 'yyyymmdd hh24')
                 || ' '
                 || 10 * (TRUNC (TO_CHAR (a.sample_time, 'MI') / 10))
                 || '-'
                 || 10 * (TRUNC (TO_CHAR (a.sample_time, 'MI') / 10) + 1)
                    TIME,
                 a.event,
                 b.username,
                 a.PROGRAM,
                 a.MODULE,
                 a.sql_id,
                 a.sql_child_number,
                 c.owner || '.' || c.object_name o_w,
                 a.TIME_WAITED
            FROM v$active_session_history a, dba_users b, dba_objects c
           WHERE     a.user_id = b.user_id
                 AND c.object_id = a.CURRENT_OBJ#
                 AND a.event LIKE 'enq:%'
                 AND a.SAMPLE_TIME >= SYSDATE - :begin_hours / 24
                 AND a.SAMPLE_TIME <=
                        SYSDATE - (:begin_hours - :interval_hours) / 24
          UNION ALL
          SELECT    TO_CHAR (TRUNC (a.sample_time, 'HH'), 'yyyymmdd hh24')
                 || ' '
                 || 10 * (TRUNC (TO_CHAR (a.sample_time, 'MI') / 10))
                 || '-'
                 || 10 * (TRUNC (TO_CHAR (a.sample_time, 'MI') / 10) + 1)
                    TIME,
                 a.event,
                 b.username,
                 a.PROGRAM,
                 a.MODULE,
                 a.sql_id,
                 a.sql_child_number,
                 c.owner || '.' || c.object_name,
                 a.TIME_WAITED
            FROM DBA_HIST_ACTIVE_SESS_HISTORY a, dba_users b, dba_objects c
           WHERE     a.user_id = b.user_id
                 AND c.object_id = a.CURRENT_OBJ#
                 AND a.event LIKE 'enq:%'
                 AND a.SAMPLE_TIME >= SYSDATE - :begin_hours / 24
                 AND a.SAMPLE_TIME <=
                        SYSDATE - (:begin_hours - :interval_hours) / 24)
GROUP BY time,
         event,
         username,
         program,
         module,
         sql_id,
         sql_child_number,
         o_w
/         
clear    breaks  
