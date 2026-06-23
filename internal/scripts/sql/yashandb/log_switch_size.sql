-- File Name: log_switch_size.sql
-- Purpose: YashanDB Redo Size Map by day / hour (M/G/T auto, max 6 chars)
-- Created: 20260615  by  huangtingzhong
-- Note: size = blocks * block_size from V$ARCHIVED_LOG (ARCHIVELOG only)

-- Redo Size Frequency Map (M/G/T)
col Date for a12
col Day for a4
col Total for a6
col h0 for a6
col h1 for a6
col h2 for a6
col h3 for a6
col h4 for a6
col h5 for a6
col h6 for a6
col h7 for a6
col h8 for a6
col h9 for a6
col h10 for a6
col h11 for a6
col h12 for a6
col h13 for a6
col h14 for a6
col h15 for a6
col h16 for a6
col h17 for a6
col h18 for a6
col h19 for a6
col h20 for a6
col h21 for a6
col h22 for a6
col h23 for a6
col Avg for a6

WITH archived AS (
  SELECT TO_CHAR(first_time, 'yyyy-mm-dd') AS dt,
         TO_CHAR(first_time, 'Dy') AS dy,
         TO_CHAR(first_time, 'hh24') AS hr,
         blocks * block_size AS sz
    FROM v$archived_log
   WHERE first_time IS NOT NULL
),
day_tot AS (
  SELECT dt,
         dy,
         SUM(sz) AS total_b
    FROM archived
   GROUP BY dt, dy
),
hr AS (
  SELECT dt,
         dy,
         hr,
         SUM(sz) AS b
    FROM archived
   GROUP BY dt, dy, hr
),
fmt AS (
  SELECT dt,
         dy,
         hr,
         SUBSTR(
           CASE
             WHEN b = 0 THEN '0'
             WHEN b >= POWER(1024, 4) THEN
               RTRIM(RTRIM(TO_CHAR(ROUND(b / POWER(1024, 4),
                 CASE WHEN b >= 100 * POWER(1024, 4) THEN 0
                      WHEN b >= 10 * POWER(1024, 4) THEN 1 ELSE 2 END), 'FM9990.9'), '0'), '.') || 'T'
             WHEN b >= POWER(1024, 3) THEN
               RTRIM(RTRIM(TO_CHAR(ROUND(b / POWER(1024, 3),
                 CASE WHEN b >= 100 * POWER(1024, 3) THEN 0
                      WHEN b >= 10 * POWER(1024, 3) THEN 1 ELSE 2 END), 'FM9990.9'), '0'), '.') || 'G'
             ELSE
               RTRIM(RTRIM(TO_CHAR(ROUND(b / POWER(1024, 2),
                 CASE WHEN b >= 100 * POWER(1024, 2) THEN 0
                      WHEN b >= 10 * POWER(1024, 2) THEN 1 ELSE 2 END), 'FM9990.9'), '0'), '.') || 'M'
           END, 1, 6) AS val
    FROM hr
),
piv AS (
  SELECT dt,
         dy,
         h0, h1, h2, h3, h4, h5, h6, h7,
         h8, h9, h10, h11, h12, h13, h14, h15,
         h16, h17, h18, h19, h20, h21, h22, h23
    FROM fmt
   PIVOT (MAX(val) FOR hr IN (
         '00' AS h0,  '01' AS h1,  '02' AS h2,  '03' AS h3,
         '04' AS h4,  '05' AS h5,  '06' AS h6,  '07' AS h7,
         '08' AS h8,  '09' AS h9,  '10' AS h10, '11' AS h11,
         '12' AS h12, '13' AS h13, '14' AS h14, '15' AS h15,
         '16' AS h16, '17' AS h17, '18' AS h18, '19' AS h19,
         '20' AS h20, '21' AS h21, '22' AS h22, '23' AS h23))
)
SELECT p.dt AS "Date",
       p.dy AS "Day",
       SUBSTR(
         CASE
           WHEN t.total_b = 0 THEN '0'
           WHEN t.total_b >= POWER(1024, 4) THEN
             RTRIM(RTRIM(TO_CHAR(ROUND(t.total_b / POWER(1024, 4),
               CASE WHEN t.total_b >= 100 * POWER(1024, 4) THEN 0
                    WHEN t.total_b >= 10 * POWER(1024, 4) THEN 1 ELSE 2 END), 'FM9990.9'), '0'), '.') || 'T'
           WHEN t.total_b >= POWER(1024, 3) THEN
             RTRIM(RTRIM(TO_CHAR(ROUND(t.total_b / POWER(1024, 3),
               CASE WHEN t.total_b >= 100 * POWER(1024, 3) THEN 0
                    WHEN t.total_b >= 10 * POWER(1024, 3) THEN 1 ELSE 2 END), 'FM9990.9'), '0'), '.') || 'G'
           ELSE
             RTRIM(RTRIM(TO_CHAR(ROUND(t.total_b / POWER(1024, 2),
               CASE WHEN t.total_b >= 100 * POWER(1024, 2) THEN 0
                    WHEN t.total_b >= 10 * POWER(1024, 2) THEN 1 ELSE 2 END), 'FM9990.9'), '0'), '.') || 'M'
         END, 1, 6) AS "Total",
       NVL(p.h0, '0') AS "h0",
       NVL(p.h1, '0') AS "h1",
       NVL(p.h2, '0') AS "h2",
       NVL(p.h3, '0') AS "h3",
       NVL(p.h4, '0') AS "h4",
       NVL(p.h5, '0') AS "h5",
       NVL(p.h6, '0') AS "h6",
       NVL(p.h7, '0') AS "h7",
       NVL(p.h8, '0') AS "h8",
       NVL(p.h9, '0') AS "h9",
       NVL(p.h10, '0') AS "h10",
       NVL(p.h11, '0') AS "h11",
       NVL(p.h12, '0') AS "h12",
       NVL(p.h13, '0') AS "h13",
       NVL(p.h14, '0') AS "h14",
       NVL(p.h15, '0') AS "h15",
       NVL(p.h16, '0') AS "h16",
       NVL(p.h17, '0') AS "h17",
       NVL(p.h18, '0') AS "h18",
       NVL(p.h19, '0') AS "h19",
       NVL(p.h20, '0') AS "h20",
       NVL(p.h21, '0') AS "h21",
       NVL(p.h22, '0') AS "h22",
       NVL(p.h23, '0') AS "h23",
       SUBSTR(
         CASE
           WHEN t.total_b = 0 THEN '0'
           WHEN t.total_b >= POWER(1024, 4) THEN
             RTRIM(RTRIM(TO_CHAR(ROUND(t.total_b / POWER(1024, 4) / 24,
               CASE WHEN t.total_b >= 2400 * POWER(1024, 4) THEN 0
                    WHEN t.total_b >= 240 * POWER(1024, 4) THEN 1 ELSE 2 END), 'FM9990.9'), '0'), '.') || 'T'
           WHEN t.total_b >= POWER(1024, 3) THEN
             RTRIM(RTRIM(TO_CHAR(ROUND(t.total_b / POWER(1024, 3) / 24,
               CASE WHEN t.total_b >= 2400 * POWER(1024, 3) THEN 0
                    WHEN t.total_b >= 240 * POWER(1024, 3) THEN 1 ELSE 2 END), 'FM9990.9'), '0'), '.') || 'G'
           ELSE
             RTRIM(RTRIM(TO_CHAR(ROUND(t.total_b / POWER(1024, 2) / 24,
               CASE WHEN t.total_b >= 2400 * POWER(1024, 2) THEN 0
                    WHEN t.total_b >= 240 * POWER(1024, 2) THEN 1 ELSE 2 END), 'FM9990.9'), '0'), '.') || 'M'
         END, 1, 6) AS "Avg"
  FROM piv p
  JOIN day_tot t ON p.dt = t.dt AND p.dy = t.dy
 ORDER BY 1;
