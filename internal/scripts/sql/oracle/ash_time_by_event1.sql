-- File Name: ash_time_by_event1.sql
-- Purpose: Oracle ASH Time By Event1
-- Created: 20260516  by  huangtingzhong

set echo off
set heading on pages 100 lines 300 verify off 

SELECT SAMPLE_ID, time, COUNT(*) COUNT
             FROM (SELECT SAMPLE_ID,
                          to_char(SAMPLE_time, 'yyyy-mm-dd hh24:mi:ss') time
                     FROM gv$active_session_history
                    WHERE SAMPLE_TIME >=
                          to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss')
                      AND SAMPLE_TIME <=
                          (to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss') +
                          nvl(&&interval_hours, 2) / 24)
                      AND event LIKE '%&&event%'
                   UNION ALL
                   SELECT SAMPLE_ID,
                          to_char(SAMPLE_time, 'yyyy-mm-dd hh24:mi:ss') time
                     FROM DBA_HIST_ACTIVE_SESS_HISTORY
                    WHERE SAMPLE_TIME >=
                          to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss')
                      AND SAMPLE_TIME <=
                          (to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss') +
                          nvl(&&interval_hours, 2) / 24)
                      AND event LIKE '%&&event%')
            GROUP BY SAMPLE_ID, time
            ORDER BY 3
/