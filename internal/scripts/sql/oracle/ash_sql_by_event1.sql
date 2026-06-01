-- File Name: ash_sql_by_event1.sql
-- Purpose: Oracle ASH SQL By Event1
-- Created: 20260516  by  huangtingzhong

set echo off
set heading on pages 100 lines 300 verify off 

SELECT sql_id, event, current_obj#, COUNT(*) COUNT
  FROM (SELECT sql_id, event, SAMPLE_ID, current_obj#
          FROM gv$active_session_history
         WHERE SAMPLE_TIME >=
               to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss')
           AND SAMPLE_TIME <=
               (to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss') +
               nvl(&&interval_hours, 2) / 24)
           AND event LIKE '%&&event%'
        UNION ALL
        SELECT sql_id, event, SAMPLE_ID, current_obj#
          FROM DBA_HIST_ACTIVE_SESS_HISTORY
         WHERE SAMPLE_TIME >=
               to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss')
           AND SAMPLE_TIME <=
               (to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss') +
               nvl(&&interval_hours, 2) / 24)
           AND event LIKE '%&&event%')
 GROUP BY sql_id, event, current_obj#
 ORDER BY 4 
 /