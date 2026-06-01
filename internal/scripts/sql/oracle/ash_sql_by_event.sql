-- File Name: ash_sql_by_event.sql
-- Purpose: Oracle ASH SQL By Event
-- Created: 20260516  by  huangtingzhong

set echo off;
set lines 250 pages 10000 heding on verify off
ACCEPT btime prompt 'Enter Search before hours (i.e. 2012-01-01 23:00:00) : ' default 'sysdate-1'
ACCEPT hour prompt 'Enter Search jiange hours (i.e. 123| default 1)) : ' default 1
ACCEPT event prompt 'Enter How Event Name (i.e. 2(default)) : ' default 'latch:shared pool'

col wait_class for a20
col event for a50

  SELECT sql_id, event, COUNT(*) COUNT
  FROM (SELECT sql_id, event, current_obj#
          FROM gv$active_session_history
         WHERE SAMPLE_TIME >= to_date('&&btime', 'YYYY-MM-DD HH24:MI:SS')
           AND SAMPLE_TIME <=
               (to_date('&&btime', 'YYYY-MM-DD HH24:MI:SS') + &&hour / 24)
           AND event LIKE '%&event%'
        UNION ALL
        SELECT sql_id, event, current_obj#
          FROM DBA_HIST_ACTIVE_SESS_HISTORY
         WHERE event LIKE '%&event%'
           AND SAMPLE_TIME >= to_date('&&btime', 'YYYY-MM-DD HH24:MI:SS')
           AND SAMPLE_TIME <=
               (to_date('&&btime', 'YYYY-MM-DD HH24:MI:SS') + &&hour / 24))
 GROUP BY sql_id, event, current_obj#
 ORDER BY 4 DESC
/
undefine btime;
undefine hour;