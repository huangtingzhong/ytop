-- File Name: ash_topsess.sql
-- Purpose: Oracle ASH top sessions
-- Created: 20260516  by  huangtingzhong

/* Formatted on 2025/9/26 15:46:06 (QP5 v5.300) */
SET FEEDBACK OFF
SET VERIFY OFF
SET LINESIZE 300
SET PAGESIZE 100
SET HEADING ON
SET TRIMSPOOL ON

-- column format settings
COL TIME        FORMAT A17    HEADING 'TIME'
COL SID         FORMAT A12    HEADING 'SESSION_ID'
COL RANK        FORMAT 9      HEADING 'R'
COL "DB%"       FORMAT 9999   HEADING 'DB%'
COL "CPU%"      FORMAT 9999   HEADING 'CPU%'
COL IOPS        FORMAT A5     HEADING 'IOPS'
COL THROUGHPUT  FORMAT A5     HEADING 'MBPS'
COL PGA         FORMAT A5     HEADING 'PGA'
COL TEMP        FORMAT A5     HEADING 'TEMP'
COL LOGICAL     FORMAT A6     HEADING 'LOGICAL'
COL DB_PCT      FORMAT 999.99 HEADING 'TDB%'
COL TOTAL       FORMAT 99999  HEADING 'TOTAL'
COL OTHER       FORMAT 99999  HEADING 'OTHER'
COL NET         FORMAT 9999   HEADING 'NET'
COL APP         FORMAT 999    HEADING 'APP'
COL ADMIN       FORMAT 999    HEADING 'ADMIN'
COL CLUST       FORMAT 99999  HEADING 'CLUST'
COL CONCUR      FORMAT 999999 HEADING 'CONCUR'
COL CONFIG      FORMAT 999999 HEADING 'CONFIG'
COL COMMIT      FORMAT 999999 HEADING 'COMMIT'
COL SIO         FORMAT 9999   HEADING 'SIO'
COL UIO         FORMAT 9999   HEADING 'UIO'
COL CPU         FORMAT 9999   HEADING 'CPU'
COL BCPU        FORMAT 9999   HEADING 'BCPU'
COL SQL_ID      FORMAT A13    HEADING 'SQL_ID'
COL USERNAME    FORMAT A8     HEADING 'USERNAME'
COL PROGRAM     FORMAT A15    HEADING 'PROGRAM'

ACCEPT begin_hours PROMPT 'Enter Search Hours Ago (i.e. 0.083(default)) : '  DEFAULT '0.083'
ACCEPT interval_hours PROMPT 'Enter How Interval Hours  (i.e. 0.083(default)) : ' DEFAULT '0.083'
ACCEPT display_time PROMPT 'Enter How Display Interval Minute  (i.e. 1(default)) : ' DEFAULT '1'
ACCEPT top_n PROMPT 'Enter TOP N Sessions per Time Interval (i.e. 5(default)) : ' DEFAULT '5'
VARIABLE begin_hours NUMBER;
VARIABLE interval_hours NUMBER;
VARIABLE TIME NUMBER;
VARIABLE top_n NUMBER;

BEGIN
    :begin_hours := &begin_hours;
    :interval_hours := &interval_hours;
    :time := &display_time;
    :top_n := &top_n;
END;
/
SET FEEDBACK OFF;

WITH agg
     AS (  SELECT    TO_CHAR (SAMPLE_TIME, 'yyyymmdd hh24')
                  || ' '
                  || :time * FLOOR (EXTRACT (MINUTE FROM SAMPLE_TIME) / :time)
                  || '-'
                  ||   :time
                     * (FLOOR (EXTRACT (MINUTE FROM SAMPLE_TIME) / :time) + 1)
                      TIME,
                  ASH.SESSION_ID,
                  ASH.SESSION_SERIAL#,
                  NVL (U.USERNAME,
                       ASH.SESSION_ID || '#' || ASH.SESSION_SERIAL#)
                      USERNAME,
                  ASH.PROGRAM,
                  SUM (cnt)                                             TOTAL,
                  SUM (DECODE (ASH.WAIT_CLASS, 'Other', cnt, 0))        OTHER,
                  SUM (DECODE (ASH.WAIT_CLASS, 'Network', cnt, 0))      NET,
                  SUM (DECODE (ASH.WAIT_CLASS, 'Application', cnt, 0))  APP,
                  SUM (DECODE (ASH.WAIT_CLASS, 'Administration', cnt, 0)) ADMIN,
                  SUM (DECODE (ASH.WAIT_CLASS, 'Cluster', cnt, 0))      CLUST,
                  SUM (DECODE (ASH.WAIT_CLASS, 'Concurrency', cnt, 0))
                      CONCUR,
                  SUM (DECODE (ASH.WAIT_CLASS, 'Configuration', cnt, 0))
                      CONFIG,
                  SUM (DECODE (ASH.WAIT_CLASS, 'Commit', cnt, 0))
                      COMMIT,
                  SUM (DECODE (ASH.WAIT_CLASS, 'System I/O', cnt, 0))   SIO,
                  SUM (DECODE (ASH.WAIT_CLASS, 'User I/O', cnt, 0))     UIO,
                  SUM (DECODE (ASH.WAIT_CLASS, 'ON CPU', cnt, 0))       CPU,
                  SUM (DECODE (ASH.WAIT_CLASS, 'BCPU', cnt, 0))         BCPU,
                  SUM (ASH.TM_DELTA_DB_TIME)
                      SUM_DB_TIME,
                  SUM (ASH.TM_DELTA_TIME)
                      SUM_ELAPSED,
                  SUM (ASH.TM_DELTA_CPU_TIME)
                      SUM_CPU_TIME,
                  SUM (
                      ASH.DELTA_READ_IO_REQUESTS + ASH.DELTA_WRITE_IO_REQUESTS)
                      SUM_IO_REQS,
                  SUM (ASH.DELTA_READ_IO_BYTES + ASH.DELTA_WRITE_IO_BYTES)
                      SUM_IO_BYTES,
                  MAX (ASH.PGA_ALLOCATED)
                      MAX_PGA,
                  MAX (ASH.TEMP_SPACE_ALLOCATED)
                      MAX_TEMP,
                  SUM (ASH.DELTA_READ_MEM_BYTES)
                      SUM_LOGICAL
             FROM (SELECT SQL_ID,
                          USER_ID,
                          SESSION_ID,
                          SAMPLE_ID,
                          SESSION_SERIAL#,
                          PROGRAM,
                          SAMPLE_TIME,
                          TM_DELTA_DB_TIME,
                          TM_DELTA_TIME,
                          TM_DELTA_CPU_TIME,
                          DELTA_READ_IO_REQUESTS,
                          DELTA_WRITE_IO_REQUESTS,
                          DELTA_READ_IO_BYTES,
                          DELTA_WRITE_IO_BYTES,
                          PGA_ALLOCATED,
                          delta_time,
                          TEMP_SPACE_ALLOCATED,
                          DELTA_READ_MEM_BYTES,
                          DECODE (
                              SESSION_STATE,
                              'ON CPU', DECODE (SESSION_TYPE,
                                                'BACKGROUND', 'BCPU',
                                                'ON CPU'),
                              WAIT_CLASS)
                              WAIT_CLASS,
                          1 cnt
                     FROM GV$ACTIVE_SESSION_HISTORY
                    WHERE     IS_AWR_SAMPLE = 'N'
                          AND SAMPLE_TIME >= SYSDATE - :begin_hours / 24
                          AND SAMPLE_TIME <=
                                    SYSDATE
                                  - (:begin_hours - :interval_hours) / 24) ASH
                  LEFT JOIN DBA_USERS U ON ASH.USER_ID = U.USER_ID
         GROUP BY    TO_CHAR (SAMPLE_TIME, 'yyyymmdd hh24')
                  || ' '
                  ||   :time
                     * FLOOR (EXTRACT (MINUTE FROM SAMPLE_TIME) / :time)
                  || '-'
                  ||   :time
                     * (FLOOR (EXTRACT (MINUTE FROM SAMPLE_TIME) / :time) + 1),
                  ASH.SESSION_ID,
                  ASH.SESSION_SERIAL#,
                  NVL (U.USERNAME,
                       ASH.SESSION_ID || '#' || ASH.SESSION_SERIAL#),
                  ASH.PROGRAM)
  SELECT ranked.TIME,
         ranked.SESSION_ID || ',' || ranked.SESSION_SERIAL# SID,
         ranked.rn                                        AS RANK,
         TRUNC ( (100 * ranked.SUM_DB_TIME) / NULLIF (ranked.SUM_ELAPSED, 0))
             "DB%",
         TRUNC ( (100 * ranked.SUM_CPU_TIME) / NULLIF (ranked.SUM_ELAPSED, 0))
             "CPU%",
         ROUND ( (100 * ranked.SUM_DB_TIME) / NULLIF (ranked.TOTAL_DB_TIME, 0), 2)
             DB_PCT,
         CASE
             WHEN ranked.SUM_ELAPSED > 0
             THEN
                 CASE
                     WHEN (ranked.SUM_IO_REQS * 1000000) / ranked.SUM_ELAPSED >=
                              10000
                     THEN
                            TO_CHAR (
                                TRUNC (
                                      (ranked.SUM_IO_REQS * 1000000)
                                    / ranked.SUM_ELAPSED
                                    / 10000))
                         || 'W'
                     WHEN (ranked.SUM_IO_REQS * 1000000) / ranked.SUM_ELAPSED >=
                              1000
                     THEN
                            TO_CHAR (
                                TRUNC (
                                      (ranked.SUM_IO_REQS * 1000000)
                                    / ranked.SUM_ELAPSED
                                    / 1000))
                         || 'K'
                     ELSE
                         TO_CHAR (
                             TRUNC (
                                   (ranked.SUM_IO_REQS * 1000000)
                                 / ranked.SUM_ELAPSED))
                 END
             ELSE
                 '0'
         END
             IOPS,
         CASE
             WHEN ranked.SUM_ELAPSED > 0
             THEN
                 CASE
                     WHEN (ranked.SUM_IO_BYTES * 1000000) / ranked.SUM_ELAPSED >=
                              1024 * 1024 * 1024
                     THEN
                            TO_CHAR (
                                TRUNC (
                                      (  (ranked.SUM_IO_BYTES * 1000000)
                                       / ranked.SUM_ELAPSED)
                                    / (1024 * 1024 * 1024)))
                         || 'GB'
                     WHEN (ranked.SUM_IO_BYTES * 1000000) / ranked.SUM_ELAPSED >=
                              1024 * 1024
                     THEN
                            TO_CHAR (
                                TRUNC (
                                      (  (ranked.SUM_IO_BYTES * 1000000)
                                       / ranked.SUM_ELAPSED)
                                    / (1024 * 1024)))
                         || 'MB'
                     WHEN (ranked.SUM_IO_BYTES * 1000000) / ranked.SUM_ELAPSED >=
                              1024
                     THEN
                            TO_CHAR (
                                TRUNC (
                                      (  (ranked.SUM_IO_BYTES * 1000000)
                                       / ranked.SUM_ELAPSED)
                                    / 1024))
                         || 'KB'
                     ELSE
                            TO_CHAR (
                                TRUNC (
                                      (ranked.SUM_IO_BYTES * 1000000)
                                    / ranked.SUM_ELAPSED))
                         || 'B'
                 END
             ELSE
                 '0'
         END
             THROUGHPUT,
         CASE
             WHEN ranked.MAX_PGA >= 1024 * 1024 * 1024
             THEN
                    TO_CHAR (TRUNC (ranked.MAX_PGA / (1024 * 1024 * 1024)))
                 || 'GB'
             WHEN ranked.MAX_PGA >= 1024 * 1024
             THEN
                 TO_CHAR (TRUNC (ranked.MAX_PGA / (1024 * 1024))) || 'MB'
             WHEN ranked.MAX_PGA >= 1024
             THEN
                 TO_CHAR (TRUNC (ranked.MAX_PGA / 1024)) || 'KB'
             ELSE
                 TO_CHAR (TRUNC (ranked.MAX_PGA)) || 'B'
         END
             PGA,
         CASE
             WHEN ranked.MAX_TEMP >= 1024 * 1024 * 1024
             THEN
                    TO_CHAR (TRUNC (ranked.MAX_TEMP / (1024 * 1024 * 1024)))
                 || 'GB'
             WHEN ranked.MAX_TEMP >= 1024 * 1024
             THEN
                 TO_CHAR (TRUNC (ranked.MAX_TEMP / (1024 * 1024))) || 'MB'
             WHEN ranked.MAX_TEMP >= 1024
             THEN
                 TO_CHAR (TRUNC (ranked.MAX_TEMP / 1024)) || 'KB'
             ELSE
                 TO_CHAR (TRUNC (ranked.MAX_TEMP)) || 'B'
         END
             TEMP,
         CASE
             WHEN ranked.SUM_LOGICAL >= 1024 * 1024 * 1024
             THEN
                    TO_CHAR (TRUNC (ranked.SUM_LOGICAL / (1024 * 1024 * 1024)))
                 || 'GB'
             WHEN ranked.SUM_LOGICAL >= 1024 * 1024
             THEN
                 TO_CHAR (TRUNC (ranked.SUM_LOGICAL / (1024 * 1024))) || 'MB'
             WHEN ranked.SUM_LOGICAL >= 1024
             THEN
                 TO_CHAR (TRUNC (ranked.SUM_LOGICAL / 1024)) || 'KB'
             ELSE
                 TO_CHAR (TRUNC (ranked.SUM_LOGICAL)) || 'B'
         END
             LOGICAL,
         ranked.TOTAL,
         ranked.OTHER,
         ranked.NET,
         ranked.APP,
         ranked.ADMIN,
         ranked.CLUST,
         ranked.CONCUR,
         ranked.CONFIG,
         ranked.COMMIT,
         ranked.SIO,
         ranked.UIO,
         ranked.CPU,
         ranked.BCPU,
         SUBSTR (ranked.USERNAME, 1, 8)                   USERNAME,
         SUBSTR (ranked.PROGRAM, 1, 15)                   PROGRAM
    FROM (SELECT agg.*,
                 ROW_NUMBER ()
                     OVER (PARTITION BY agg.TIME ORDER BY NVL(agg.SUM_DB_TIME, 0) DESC)
                     AS rn,
                 SUM(agg.SUM_DB_TIME) OVER (PARTITION BY agg.TIME) AS TOTAL_DB_TIME
            FROM agg) ranked
   WHERE ranked.rn <= :top_n
ORDER BY ranked.TIME, ranked.rn ASC;

-- clear column format settings
CLEAR COLUMNS
