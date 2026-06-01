-- File Name: ash_pga.sql
-- Purpose: Oracle ASH Pga
-- Created: 20260516  by  huangtingzhong

set linesize 300
set pagesize 999 echo off verify off

col time for a18
col sql_id for a20

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



/* Formatted on 2022/12/10 16:17:50 (QP5 v5.300) */
/* Formatted on 2022/12/12 9:29:47 (QP5 v5.300) */
WITH ash
     AS (SELECT DISTINCT
                sample_time,
                sql_id,
                SUM (pga_allocated)
                    OVER (PARTITION BY sample_time ORDER BY sample_time)
                    s_pga,
                SUM (TEMP_SPACE_ALLOCATED)
                    OVER (PARTITION BY sample_time ORDER BY sample_time)
                    s_temp,
                SUM (pga_allocated)
                OVER (PARTITION BY sample_time, SQL_ID ORDER BY sample_time)
                    l_pga,
                SUM (TEMP_SPACE_ALLOCATED)
                OVER (PARTITION BY sample_time, SQL_ID ORDER BY sample_time)
                    l_temp
           FROM (SELECT SAMPLE_TIME,
                        NVL (SQL_ID, 'aaa' || ROWNUM) sql_id,
                        PGA_ALLOCATED,
                        TEMP_SPACE_ALLOCATED
                   FROM GV$ACTIVE_SESSION_HISTORY
                  WHERE     SAMPLE_TIME >= SYSDATE - :begin_hours / 24
                        AND SAMPLE_TIME <=
                                  SYSDATE
                                - (:begin_hours - :interval_hours) / 24
                 UNION ALL
                 SELECT SAMPLE_TIME,
                        NVL (SQL_ID, 'bbb' || ROWNUM) sql_id,
                        PGA_ALLOCATED,
                        TEMP_SPACE_ALLOCATED
                   FROM DBA_HIST_ACTIVE_SESS_HISTORY
                  WHERE     SAMPLE_TIME >= SYSDATE - :begin_hours / 24
                        AND SAMPLE_TIME <=
                                  SYSDATE
                                - (:begin_hours - :interval_hours) / 24)),
     time_date
     AS (    SELECT   TRUNC (SYSDATE - (:begin_hours - :interval_hours + 1) / 24,
                             'MI')
                    - (LEVEL / (24 * 60) * :time)
                        AS date_min,
                      TRUNC (SYSDATE - (:begin_hours - :interval_hours + 1) / 24,
                             'MI')
                    - ( (LEVEL - 1) / (24 * 60) * :time)
                        AS date_max
               FROM DUAL
         CONNECT BY LEVEL < (:interval_hours * 60 / :time) + 1
           ORDER BY date_min)
  SELECT date_min time,
         sql_id,
         avg_pga_mb || ':' || min_pga_mb || ':' || max_pga_mb avg_min_max_pga,
         avg_temp_mb || ':' || min_temp_mb || ':' || max_temp_mb
             avg_min_max_temp,
         avg_sql_pga_mb || ':' || min_sql_pga_mb || ':' || max_sql_pga_mb
             avg_min_max_sql_pga,
         avg_sql_temp_mb || ':' || min_sql_temp_mb || ':' || max_sql_temp_mb
             avg_min_max_sql_temp,
         pct_max_pga,
         pct_max_temp,
         max_pga_row,
         max_temp_row
    FROM (SELECT date_min,
                 sql_id,
                 avg_pga_mb,
                 min_pga_mb,
                 max_pga_mb,
                 avg_temp_mb,
                 min_temp_mb,
                 max_temp_mb,
                 avg_sql_pga_mb,
                 min_sql_pga_mb,
                 max_sql_pga_mb,
                 avg_sql_temp_mb,
                 min_sql_temp_mb,
                 max_sql_temp_mb,
                 ROUND (
                       100
                     * Ratio_to_report (max_sql_pga_mb)
                           OVER (PARTITION BY date_min ),
                     2)
                     pct_max_pga,
                 ROUND (
                       100
                     * Ratio_to_report (max_sql_pga_mb)
                           OVER (PARTITION BY date_min),
                     2)
                     pct_max_temp,
                 ROW_NUMBER ()
                     OVER (PARTITION BY date_min ORDER BY max_sql_pga_mb DESC)
                     max_pga_row,
                 ROW_NUMBER ()
                     OVER (PARTITION BY date_min ORDER BY max_sql_temp_mb DESC)
                     max_temp_row
            FROM (  SELECT TO_CHAR (c.date_min, 'YYYY-MM-DD HH24:MI:SS') date_min,
                           sql_id,
                           TRUNC (NVL (AVG (s_pga), 0) / 1024 / 1024, 2)
                               avg_pga_mb,
                           TRUNC (NVL (MIN (s_pga), 0) / 1024 / 1024, 2)
                               min_pga_mb,
                           TRUNC (NVL (MAX (s_pga), 0) / 1024 / 1024, 2)
                               max_pga_mb,
                           TRUNC (NVL (AVG (s_temp), 0) / 1024 / 1024, 2)
                               avg_temp_mb,
                           TRUNC (NVL (MIN (s_temp), 0) / 1024 / 1024, 2)
                               min_temp_mb,
                           TRUNC (NVL (MAX (s_temp), 0) / 1024 / 1024, 2)
                               max_temp_mb,
                           TRUNC (NVL (AVG (l_pga), 0) / 1024 / 1024, 2)
                               avg_sql_pga_mb,
                           TRUNC (NVL (MIN (l_pga), 0) / 1024 / 1024, 2)
                               min_sql_pga_mb,
                           TRUNC (NVL (MAX (l_pga), 0) / 1024 / 1024, 2)
                               max_sql_pga_mb,
                           TRUNC (NVL (AVG (l_temp), 0) / 1024 / 1024, 2)
                               avg_sql_temp_mb,
                           TRUNC (NVL (MIN (l_temp), 0) / 1024 / 1024, 2)
                               min_sql_temp_mb,
                           TRUNC (NVL (MAX (l_temp), 0) / 1024 / 1024, 2)
                               max_sql_temp_mb
                      FROM ash h, time_date c
                     WHERE     h.sample_time(+) >= c.date_min
                           AND h.sample_time(+) < c.date_max
                  GROUP BY c.date_min, sql_id))
   WHERE max_pga_row < 4 AND max_temp_row < 4
ORDER BY date_min
/
