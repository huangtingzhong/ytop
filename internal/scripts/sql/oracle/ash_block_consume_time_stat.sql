-- File Name: ash_block_consume_time_stat.sql
-- Purpose: Oracle ASH Block Consume Time stats
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set serveroutput on
set feedback off
set lines 200
set pages 40
col time for a17	
col event for a25
col username for a15
col program for a20
col module for a20	
col o_w for a30 heading 'OBJECT|OWNER.NAME'
col t_r for 99 heading 'TIME|RANK'
col pct_of_time for 999.99 heading '%PCT|OF TIME'

variable begin_hours number;
variable interval_hours number;
begin
   :begin_hours:=&begin_hours;
   :interval_hours:=&interval_hours;
   end;
   /
  SELECT time,
         substr(event,1,24) event,
         username,
         substr(program,1,19) program,
         substr(module,1,19) module,
         sql_id,
         sql_child_number,
         o_w,
         ROUND (SUM (time_waited) / 1000, 2) "TIME_WAITED(S)",
         RANK () OVER (PARTITION BY time ORDER BY SUM (time_waited)) t_r,
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
