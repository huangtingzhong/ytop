-- File Name: ash_event_by_class_stat.sql
-- Purpose: Oracle ASH Event By Class stats
-- Created: 20260516  by  huangtingzhong

ACCEPT begin_hours prompt 'Enter Search Hours Ago (i.e. 2(default)) : '  default '2'
ACCEPT interval_hours prompt 'Enter How Interval Hours  (i.e. 2(default)) : ' default '2'
variable begin_hours number;
variable interval_hours number;
variable time number;
begin
   :begin_hours:=&begin_hours;
   :interval_hours:=&interval_hours;
   end;
   /
/* Formatted on 2013/2/27 14:17:45 (QP5 v5.215.12089.38647) */
  SELECT WAIT_CLASS, SUM (cnt) TOTAL
    FROM (SELECT 
                       DECODE (
                          SESSION_STATE,
                          'ON CPU', DECODE (SESSION_TYPE,
                                            'BACKGROUND', 'BCPU',
                                            'CPU'),
                          WAIT_CLASS)
                    WAIT_CLASS,
                 1 cnt
            FROM GV$ACTIVE_SESSION_HISTORY
           WHERE     SAMPLE_TIME >= SYSDATE - :begin_hours / 24
                 AND SAMPLE_TIME <= SYSDATE - (:begin_hours - :interval_hours) / 24
          UNION ALL
          SELECT 
                       DECODE (
                          SESSION_STATE,
                          'ON CPU', DECODE (SESSION_TYPE,
                                            'BACKGROUND', 'BCPU',
                                            'CPU'),
                          WAIT_CLASS)
                    WAIT_CLASS,
                 10 cnt
            FROM DBA_HIST_ACTIVE_SESS_HISTORY
           WHERE     SAMPLE_TIME >= SYSDATE - :begin_hours / 24
                 AND SAMPLE_TIME <= SYSDATE - (:begin_hours - :interval_hours) / 24)
GROUP BY WAIT_CLASS
ORDER BY TOTAL DESC;