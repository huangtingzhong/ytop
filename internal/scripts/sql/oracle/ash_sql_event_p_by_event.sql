-- File Name: ash_sql_event_p_by_event.sql
-- Purpose: Oracle ASH SQL Event P By Event
-- Created: 20260516  by  huangtingzhong

set echo off;
set lines 250 pages 10000 heding on verify off
ACCEPT begin_hours prompt 'Enter Search Hours Ago (i.e. 2(default)) : '  default '2'
ACCEPT interval_hours prompt 'Enter How Interval Hours  (i.e. 2(default)) : ' default '2'
ACCEPT event prompt 'Enter How Event Name (i.e. 2(default)) : ' default 'latch:shared pool'
variable begin_hours number;
variable interval_hours number;
variable time number;
begin
   :begin_hours:=&begin_hours;
   :interval_hours:=&interval_hours;
   end;
/


col wait_class for a20
col event for a50

  SELECT sql_id, event,  p1,p2,p3,COUNT(*) COUNT
  FROM (SELECT sql_id, event, p1,p2,p3
          FROM gv$active_session_history
         WHERE SAMPLE_TIME >= SYSDATE - :begin_hours / 24
           AND SAMPLE_TIME <= SYSDATE - (:begin_hours - :interval_hours) / 24
           AND event LIKE '%&event%'
        UNION ALL
        SELECT sql_id, event,  p1,p2,p3
          FROM DBA_HIST_ACTIVE_SESS_HISTORY
         WHERE event LIKE '%&event%'
           AND SAMPLE_TIME >= SYSDATE - :begin_hours / 24
           AND SAMPLE_TIME <= SYSDATE - (:begin_hours - :interval_hours) / 24
 GROUP BY sql_id, event,  p1,p2,p3
 ORDER BY 6
/
undefine btime;
undefine hour;
