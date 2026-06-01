-- File Name: ash_event_by_class1.sql
-- Purpose: Oracle ASH Event By Class1
-- Created: 20260516  by  huangtingzhong

set heading off
set lines 2000 pages 50 verify off heading on
col wait_class for a20
col event for a50
SELECT WAIT_CLASS, event, SUM(cnt) TOTAL
  FROM (SELECT DECODE(SESSION_STATE,
                      'ON CPU',
                      DECODE(SESSION_TYPE, 'BACKGROUND', 'BCPU', 'CPU'),
                      EVENT) EVENT,
               DECODE(SESSION_STATE,
                      'ON CPU',
                      DECODE(SESSION_TYPE, 'BACKGROUND', 'BCPU', 'CPU'),
                      WAIT_CLASS) WAIT_CLASS,
               1 cnt
          FROM GV$ACTIVE_SESSION_HISTORY
         WHERE SAMPLE_TIME >= to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss')
           AND SAMPLE_TIME <=
               to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss')+nvl(&&interval_hours,2)/24
           AND upper(wait_class) = upper(nvl('&&waitclass','Concurrency'))
        UNION ALL
        SELECT DECODE(SESSION_STATE,
                      'ON CPU',
                      DECODE(SESSION_TYPE, 'BACKGROUND', 'BCPU', 'CPU'),
                      EVENT) EVENT,
               DECODE(SESSION_STATE,
                      'ON CPU',
                      DECODE(SESSION_TYPE, 'BACKGROUND', 'BCPU', 'CPU'),
                      WAIT_CLASS) WAIT_CLASS,
               10 cnt
          FROM DBA_HIST_ACTIVE_SESS_HISTORY
         WHERE SAMPLE_TIME >= to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss')
           AND upper(wait_class) = upper(nvl('&&waitclass','Concurrency'))
           AND SAMPLE_TIME <=
               to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss')+nvl(&&interval_hours,2)/24)
 GROUP BY WAIT_CLASS, event
 order by total desc
/