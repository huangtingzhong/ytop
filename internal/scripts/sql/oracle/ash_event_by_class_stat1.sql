-- File Name: ash_event_by_class_stat1.sql
-- Purpose: Oracle ASH Event By Class Stat1
-- Created: 20260516  by  huangtingzhong

set echo off
set heading on pages 100 lines 300 verify off 


SELECT WAIT_CLASS, SUM(cnt) TOTAL
  FROM (SELECT DECODE(SESSION_STATE,
                      'ON CPU',
                      DECODE(SESSION_TYPE, 'BACKGROUND', 'BCPU', 'CPU'),
                      WAIT_CLASS) WAIT_CLASS,
               1 cnt
          FROM GV$ACTIVE_SESSION_HISTORY
         WHERE SAMPLE_TIME >=
               to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss')
           AND SAMPLE_TIME <=
               to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss') +
               nvl(&&interval_hours, 2) / 24
        UNION ALL
        SELECT DECODE(SESSION_STATE,
                      'ON CPU',
                      DECODE(SESSION_TYPE, 'BACKGROUND', 'BCPU', 'CPU'),
                      WAIT_CLASS) WAIT_CLASS,
               10 cnt
          FROM DBA_HIST_ACTIVE_SESS_HISTORY
         WHERE SAMPLE_TIME >=
               to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss')
           AND SAMPLE_TIME <=
               to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss') +
               nvl(&&interval_hours, 2) / 24)
 GROUP BY WAIT_CLASS
 order by total;

