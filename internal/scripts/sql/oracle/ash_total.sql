-- File Name: ash_total.sql
-- Purpose: Oracle ASH Total
-- Created: 20260516  by  huangtingzhong

set linesize 250
set pagesize 999

col time for a18
col TOTAL  for 99999   heading 'TOTAL'
col OTHER  for 99999   heading 'Other'
col NET    for 99999   heading 'Network'
col APP    for 99999   heading 'Application'
col ADMIN  for 99999   heading 'Administration'
col CLUST  for 99999   heading 'Cluster'
col CONCUR for 99999   heading 'Concurrency'
col CONFIG for 99999   heading 'Configuration'
col COMMIT for 99999   heading 'Commit'
col SIO    for 99999   heading 'System I/O'
col UIO    for 99999   heading 'User I/O'
col CPU    for 99999   heading 'ON CPU'
col BCPU   for 99999   heading 'BCPU'

ACCEPT begin_hours prompt 'Enter Search Hours Ago (i.e. 2(default)) : '  default '2'
ACCEPT interval_hours prompt 'Enter How Interval Hours  (i.e. 2(default)) : ' default '2'
ACCEPT display_time prompt 'Enter How Display Interval Minute  (i.e. 10(default)) : ' default '10'
variable begin_hours number;
variable interval_hours number;
variable time number;
begin
   :begin_hours:=&begin_hours;
   :interval_hours:=&interval_hours;
   :time:=&display_time;
   end;
/


 SELECT TO_CHAR(DATE_HH, 'yyyymmdd hh24') || ' ' || :time * (DATE_MI) || '-' ||
       :time * (DATE_MI + 1) TIME,
       round(SUM(cnt)/900) TOTAL,
       round(SUM(DECODE(ASH.WAIT_CLASS, 'Other', cnt, 0))/900) OTHER,
       round(SUM(DECODE(ASH.WAIT_CLASS, 'Network', cnt, 0))/900) NET,
       round(SUM(DECODE(ASH.WAIT_CLASS, 'Application', cnt, 0))/900) APP,
       round(SUM(DECODE(ASH.WAIT_CLASS, 'Administration', cnt, 0))/900) ADMIN,
       round(SUM(DECODE(ASH.WAIT_CLASS, 'Cluster', cnt, 0))/900) CLUST,
       round(SUM(DECODE(ASH.WAIT_CLASS, 'Concurrency', cnt, 0))/900) CONCUR,
       round(SUM(DECODE(ASH.WAIT_CLASS, 'Configuration', cnt, 0))/900) CONFIG,
       round(SUM(DECODE(ASH.WAIT_CLASS, 'Commit', cnt, 0))/900) COMMIT,
       round(SUM(DECODE(ASH.WAIT_CLASS, 'System I/O', cnt, 0))/900) SIO,
       round(SUM(DECODE(ASH.WAIT_CLASS, 'User I/O', cnt, 0))/900) UIO,
       round(SUM(DECODE(ASH.WAIT_CLASS, 'ON CPU', cnt, 0))/900) CPU,
       round(SUM(DECODE(ASH.WAIT_CLASS, 'BCPU', cnt, 0))/900) BCPU
  FROM (SELECT TRUNC(SAMPLE_TIME, 'HH') DATE_HH,
               TRUNC(TO_CHAR(SAMPLE_TIME, 'MI') / :time) DATE_MI,
               DECODE(SESSION_STATE,
                      'ON CPU',
                      DECODE(SESSION_TYPE, 'BACKGROUND', 'BCPU', 'ON CPU'),
                      WAIT_CLASS) WAIT_CLASS,1 cnt
          FROM GV$ACTIVE_SESSION_HISTORY
         WHERE SAMPLE_TIME >= SYSDATE - :begin_hours / 24
           AND SAMPLE_TIME <= SYSDATE - (:begin_hours - :interval_hours) / 24
        UNION ALL
        SELECT TRUNC(SAMPLE_TIME, 'HH') DATE_HH,
               TRUNC(TO_CHAR(SAMPLE_TIME, 'MI') / :time) DATE_MI,
               DECODE(SESSION_STATE,
                      'ON CPU',
                      DECODE(SESSION_TYPE, 'BACKGROUND', 'BCPU', 'ON CPU'),
                      WAIT_CLASS) WAIT_CLASS,10 cnt
          FROM DBA_HIST_ACTIVE_SESS_HISTORY
         WHERE SAMPLE_TIME >= SYSDATE - :begin_hours / 24
           AND SAMPLE_TIME <= SYSDATE - (:begin_hours - :interval_hours) / 24) ASH
 GROUP BY TO_CHAR(DATE_HH, 'yyyymmdd hh24') || ' ' || :time * (DATE_MI) || '-' ||
          :time * (DATE_MI + 1)
 ORDER BY 1;
undefine 1
undefine 2
