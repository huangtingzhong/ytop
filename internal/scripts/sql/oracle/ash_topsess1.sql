-- File Name: ash_topsess1.sql
-- Purpose: Oracle ASH Topsess1
-- Created: 20260516  by  huangtingzhong

--------------------------------------------------------------------------------
--
-- File name:   ash_topsess.sql
-- Author:      zhangqiao
-- Copyright:   zhangqiaoc@olm.com.cn
--
--------------------------------------------------------------------------------

set linesize 250
set pagesize 999
col sid for a10
col username for a8
col program for a15
col TOTAL  for 999999
col OTHER  for 9999 
col NET    for 99999
col APP    for 99999
col ADMIN  for 9999 
col CLUST  for 99999
col CONCUR for 99999
col CONFIG for 9999 
col COMMIT for 99999
col S_IO   for 99999
col UIO    for 99999
col CPU    for 99999
col BCPU   for 99999

select * from (
SELECT *
  FROM (SELECT ASH.SESSION_ID || ',' || ASH.SESSION_SERIAL# SID,
               sum(cnt) TOTAL,
               SUM(DECODE(ASH.WAIT_CLASS, 'Other', cnt, 0)) OTHER,
               SUM(DECODE(ASH.WAIT_CLASS, 'Network', cnt, 0)) NET,
               SUM(DECODE(ASH.WAIT_CLASS, 'Application', cnt, 0)) APP,
               SUM(DECODE(ASH.WAIT_CLASS, 'Administration', cnt, 0)) ADMIN,
               SUM(DECODE(ASH.WAIT_CLASS, 'Cluster', cnt, 0)) CLUST,
               SUM(DECODE(ASH.WAIT_CLASS, 'Concurrency', cnt, 0)) CONCUR,
               SUM(DECODE(ASH.WAIT_CLASS, 'Configuration', cnt, 0)) CONFIG,
               SUM(DECODE(ASH.WAIT_CLASS, 'Commit', cnt, 0)) COMMIT,
               SUM(DECODE(ASH.WAIT_CLASS, 'System I/O', cnt, 0)) S_IO,
               SUM(DECODE(ASH.WAIT_CLASS, 'User I/O', cnt, 0)) UIO,
               SUM(DECODE(ASH.WAIT_CLASS, 'ON CPU', cnt, 0)) CPU,
               SUM(DECODE(ASH.WAIT_CLASS, 'BCPU', cnt, 0)) BCPU,
               substr(NVL(U.USERNAME, ASH.SESSION_ID || '#' || ASH.SESSION_SERIAL#),1,8) USERNAME,
               substr(ASH.PROGRAM,1,15) PROGRAM
          FROM (SELECT SQL_ID,
                       USER_ID,
                       SESSION_ID,
                       SAMPLE_ID,
                       SESSION_SERIAL#,
                       PROGRAM,
                       DECODE(SESSION_STATE,
                              'ON CPU',
                              DECODE(SESSION_TYPE,
                                     'BACKGROUND',
                                     'BCPU',
                                     'ON CPU'),
                              WAIT_CLASS) WAIT_CLASS,1 cnt
                  FROM GV$ACTIVE_SESSION_HISTORY
                --from  ash_dump
                 WHERE SAMPLE_TIME >=
                       sysdate-&&1/24
                   AND SAMPLE_TIME <=
                       sysdate-(&&1-&&2)/24
                UNION ALL
                SELECT SQL_ID,
                       USER_ID,
                       SESSION_ID,
                       SAMPLE_ID,
                       SESSION_SERIAL#,
                       PROGRAM,
                       DECODE(SESSION_STATE,
                              'ON CPU',
                              DECODE(SESSION_TYPE,
                                     'BACKGROUND',
                                     'BCPU',
                                     'ON CPU'),
                              WAIT_CLASS) WAIT_CLASS,10 cnt
                  FROM DBA_HIST_ACTIVE_SESS_HISTORY
                 WHERE SAMPLE_TIME >=
                       sysdate-&&1/24
                   AND SAMPLE_TIME <=
                       sysdate-(&&1-&&2)/24) ASH,
               DBA_USERS U
         WHERE U.USER_ID(+) = ASH.USER_ID
         GROUP BY ASH.SESSION_ID,
                  ASH.SESSION_SERIAL#,
                  ASH.PROGRAM,
                  U.USERNAME)
 ORDER BY TOTAL DESC)
where rownum<=100;

undefine 1
undefine 2