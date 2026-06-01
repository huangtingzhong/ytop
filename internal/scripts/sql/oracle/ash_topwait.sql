-- File Name: ash_topwait.sql
-- Purpose: Oracle ASH Topwait
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 300 pages 5000 verify off heading on
col event for a50
col wait_class for a20

ACCEPT btime prompt 'Enter Search before hours (i.e. 2012-01-01 23:00:00) : ' default 'sysdate-1'
ACCEPT hour prompt 'Enter Search jiange hours (i.e. 123| default 1)) : ' default 1

SELECT EVENT, sum(cnt) TOTAL, WAIT_CLASS
  FROM (SELECT DECODE(SESSION_STATE,
                      'ON CPU',
                      DECODE(SESSION_TYPE, 'BACKGROUND', 'BCPU', 'CPU'),
                      EVENT) EVENT,
               REPLACE(TRANSLATE(DECODE(SESSION_STATE,
                                        'ON CPU',
                                        DECODE(SESSION_TYPE,
                                               'BACKGROUND',
                                               'BCPU',
                                               'CPU'),
                                        WAIT_CLASS),
                                 ' $',
                                 '____'),
                       '/') WAIT_CLASS,
               1 cnt
          FROM GV$ACTIVE_SESSION_HISTORY
         where SAMPLE_TIME >= to_date('&&btime', 'YYYY-MM-DD HH24:MI:SS')
           AND SAMPLE_TIME <=
               (to_date('&&btime', 'YYYY-MM-DD HH24:MI:SS') + &&hour / 24)
        UNION ALL
        SELECT DECODE(SESSION_STATE,
                      'ON CPU',
                      DECODE(SESSION_TYPE, 'BACKGROUND', 'BCPU', 'CPU'),
                      EVENT) EVENT,
               REPLACE(TRANSLATE(DECODE(SESSION_STATE,
                                        'ON CPU',
                                        DECODE(SESSION_TYPE,
                                               'BACKGROUND',
                                               'BCPU',
                                               'CPU'),
                                        WAIT_CLASS),
                                 ' $',
                                 '____'),
                       '/') WAIT_CLASS,
               10 cnt
          FROM DBA_HIST_ACTIVE_SESS_HISTORY
         where SAMPLE_TIME >= to_date('&&btime', 'YYYY-MM-DD HH24:MI:SS')
           AND SAMPLE_TIME <=
               (to_date('&&btime', 'YYYY-MM-DD HH24:MI:SS') + &&hour / 24))
 GROUP BY EVENT, WAIT_CLASS
 ORDER BY TOTAL DESC;


undefine 1
undefine 2


undefine btime;
undefine hour;