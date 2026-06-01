-- File Name: ash_event_by_class.sql
-- Purpose: Oracle ASH Event By Class
-- Created: 20260516  by  huangtingzhong

ACCEPT begin_hours prompt 'Enter Search Hours Ago (i.e. 2(default)) : '  default '2'
ACCEPT interval_hours prompt 'Enter How Interval Hours  (i.e. 2(default)) : ' default '2'
ACCEPT waitclass prompt 'Enter How Wait_Class (i.e. 2(default)) : ' default 'Concurrency'
variable begin_hours number;
variable interval_hours number;
variable waitclass varchar2(100);
begin
   :begin_hours:=&begin_hours;
   :interval_hours:=&interval_hours;
   :waitclass:='&waitclass';
   end;
/
set pages 170
col wait_class for a20
col event for a50
  SELECT WAIT_CLASS, event, SUM (cnt) TOTAL
    FROM (SELECT DECODE (
                    SESSION_STATE,
                    'ON CPU', DECODE (SESSION_TYPE,
                                      'BACKGROUND', 'BCPU',
                                      'CPU'),
                    EVENT)
                    EVENT,
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
                 AND SAMPLE_TIME <=
                        SYSDATE - (:begin_hours - :interval_hours) / 24
                 AND wait_class = :waitclass
          UNION ALL
          SELECT DECODE (
                    SESSION_STATE,
                    'ON CPU', DECODE (SESSION_TYPE,
                                      'BACKGROUND', 'BCPU',
                                      'CPU'),
                    EVENT)
                    EVENT,
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
                 AND wait_class = :waitclass
                 AND SAMPLE_TIME <=
                        SYSDATE - (:begin_hours - :interval_hours) / 24)
GROUP BY WAIT_CLASS, event
order by total desc
/