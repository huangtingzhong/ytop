-- File Name: ash_total_zq.sql
-- Purpose: Oracle ASH Total Zq
-- Created: 20260516  by  huangtingzhong

--------------------------------------------------------------------------------
--
-- File name:   ash_total.sql
-- Author:      zhangqiao
-- Copyright:   zhangqiaoc@olm.com.cn
--
--------------------------------------------------------------------------------

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


 SELECT TO_CHAR(DATE_HH, 'yyyymmdd hh24') || ' ' || 15 * (DATE_MI) || '-' ||
       15 * (DATE_MI + 1) TIME,
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
               TRUNC(TO_CHAR(SAMPLE_TIME, 'MI') / 15) DATE_MI,
               DECODE(SESSION_STATE,
                      'ON CPU',
                      DECODE(SESSION_TYPE, 'BACKGROUND', 'BCPU', 'ON CPU'),
                      WAIT_CLASS) WAIT_CLASS,1 cnt
          FROM GV$ACTIVE_SESSION_HISTORY
         WHERE SAMPLE_TIME >= SYSDATE - &&1 / 24
           AND SAMPLE_TIME <= SYSDATE - (&&1 - &&2) / 24
        UNION ALL
        SELECT TRUNC(SAMPLE_TIME, 'HH') DATE_HH,
               TRUNC(TO_CHAR(SAMPLE_TIME, 'MI') / 15) DATE_MI,
               DECODE(SESSION_STATE,
                      'ON CPU',
                      DECODE(SESSION_TYPE, 'BACKGROUND', 'BCPU', 'ON CPU'),
                      WAIT_CLASS) WAIT_CLASS,10 cnt
          FROM DBA_HIST_ACTIVE_SESS_HISTORY
         WHERE SAMPLE_TIME >= SYSDATE - &&1 / 24
           AND SAMPLE_TIME <= SYSDATE - (&&1 - &&2) / 24) ASH
 GROUP BY TO_CHAR(DATE_HH, 'yyyymmdd hh24') || ' ' || 15 * (DATE_MI) || '-' ||
          15 * (DATE_MI + 1)
 ORDER BY 1;
 
undefine 1
undefine 2