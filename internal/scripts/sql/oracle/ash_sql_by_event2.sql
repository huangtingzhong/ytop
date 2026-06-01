-- File Name: ash_sql_by_event2.sql
-- Purpose: Oracle ASH SQL By Event2
-- Created: 20260516  by  huangtingzhong

ACCEPT begin_hours prompt 'Enter Search Hours Ago (i.e. 2(default)) : '  default '2'
ACCEPT interval_hours prompt 'Enter How Interval Hours  (i.e. 2(default)) : ' default '2'
ACCEPT event prompt 'Enter How Event Name (i.e. 2(default)) : ' default 'latch:shared pool'
variable begin_hours number;
variable interval_hours number;
variable event varchar2(100);
begin
   :begin_hours:=&begin_hours;
   :interval_hours:=&interval_hours;
   :event:='&event';
   end;
/
set pages 170
col wait_class for a20
col event for a50
  /* Formatted on 2013/2/27 14:56:30 (QP5 v5.215.12089.38647) */
  SELECT sql_id,
         event,
         current_obj#,
         COUNT (*) COUNT
    FROM (SELECT sql_id, event, current_obj#
            FROM gv$active_session_history
           WHERE     SAMPLE_TIME >= SYSDATE - :begin_hours / 24
                 AND SAMPLE_TIME <=
                        SYSDATE - (:begin_hours - :interval_hours) / 24
                 AND event LIKE '%&event%'
          UNION ALL
          SELECT sql_id, event, current_obj#
            FROM DBA_HIST_ACTIVE_SESS_HISTORY
           WHERE     SAMPLE_TIME >= SYSDATE - :begin_hours / 24
                 AND event LIKE '%&event%'
                 AND SAMPLE_TIME <=
                        SYSDATE - (:begin_hours - :interval_hours) / 24)
GROUP BY sql_id, event, current_obj#
ORDER BY 4 DESC
/