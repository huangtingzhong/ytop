-- File Name: log_switch_by_mi.sql
-- Purpose: Oracle Log Switch By Mi
-- Created: 20260516  by  huangtingzhong

REM Log Switch Frequency Map
col Day for a12
col Date for a12
col total for 99999
col 00-05 for 999
col 05-10 for 999
col 10-15 for 999
col 15-20 for 999
col 20-25 for 999
col 25-30 for 999
col 30-35 for 999
col 35-40 for 999
col 40-45 for 999
col 45-50 for 999
col 50-55 for 999
col 55-60 for 999
col hour for 9999
set linesize 175
set pages 100
PROMPT
ACCEPT date prompt 'Enter Search Date (i.e. yyyy-mm-dd) : '
  SELECT TO_CHAR (first_time, 'yyyy-mm-dd') "Date",
         TO_CHAR (first_time, 'hh24') "HOUR",
         COUNT (1) "Total",
         SUM (DECODE (TRUNC (TO_CHAR (first_time, 'MI') / 5), '0', 1, 0))
            "00-05",
         SUM (DECODE (TRUNC (TO_CHAR (first_time, 'MI') / 5), '1', 1, 0))
            "05-10",
         SUM (DECODE (TRUNC (TO_CHAR (first_time, 'MI') / 5), '2', 1, 0))
            "10-15",
         SUM (DECODE (TRUNC (TO_CHAR (first_time, 'MI') / 5), '3', 1, 0))
            "15-20",
         SUM (DECODE (TRUNC (TO_CHAR (first_time, 'MI') / 5), '4', 1, 0))
            "20-25",
         SUM (DECODE (TRUNC (TO_CHAR (first_time, 'MI') / 5), '5', 1, 0))
            "25-30",
         SUM (DECODE (TRUNC (TO_CHAR (first_time, 'MI') / 5), '6', 1, 0))
            "30-35",
         SUM (DECODE (TRUNC (TO_CHAR (first_time, 'MI') / 5), '7', 1, 0))
            "35-40",
         SUM (DECODE (TRUNC (TO_CHAR (first_time, 'MI') / 5), '8', 1, 0))
            "40-45",
         SUM (DECODE (TRUNC (TO_CHAR (first_time, 'MI') / 5), '9', 1, 0))
            "45-50",
         SUM (DECODE (TRUNC (TO_CHAR (first_time, 'MI') / 5), '10', 1, 0))
            "50-55",
         SUM (DECODE (TRUNC (TO_CHAR (first_time, 'MI') / 5), '11', 1, 0))
            "55-60",
         ROUND (COUNT (1) / 12, 2) "Avg"
    FROM V$log_history
   WHERE TO_CHAR (first_time, 'yyyy-mm-dd') =
            NVL ('&date', TO_CHAR (first_time, 'yyyy-mm-dd'))
GROUP BY TO_CHAR (first_time, 'yyyy-mm-dd'), TO_CHAR (first_time, 'hh24')
ORDER BY 1
/