-- File Name: log_switch.sql
-- Purpose: YashanDB Log Switch Frequency Map (by day / hour)
-- Created: 20260615  by  huangtingzhong
-- Note: YashanDB has no V$LOG_HISTORY; use V$ARCHIVED_LOG.first_time (ARCHIVELOG only)

-- Log Switch Frequency Map
col Date for a12
col Day for a4
col Total for a5
col h0 for a4
col h1 for a4
col h2 for a4
col h3 for a4
col h4 for a4
col h5 for a4
col h6 for a4
col h7 for a4
col h8 for a4
col h9 for a4
col h10 for a4
col h11 for a4
col h12 for a4
col h13 for a4
col h14 for a4
col h15 for a4
col h16 for a4
col h17 for a4
col h18 for a4
col h19 for a4
col h20 for a4
col h21 for a4
col h22 for a4
col h23 for a4
col Avg for a5

WITH archived AS (
  SELECT TO_CHAR(first_time, 'yyyy-mm-dd') AS dt,
         TO_CHAR(first_time, 'Dy') AS dy,
         TO_CHAR(first_time, 'hh24') AS hr
    FROM v$archived_log
   WHERE first_time IS NOT NULL
),
day_tot AS (
  SELECT dt,
         dy,
         COUNT(1) AS total_n
    FROM archived
   GROUP BY dt, dy
),
hr AS (
  SELECT dt,
         dy,
         hr,
         COUNT(1) AS n
    FROM archived
   GROUP BY dt, dy, hr
),
piv AS (
  SELECT dt,
         dy,
         h0, h1, h2, h3, h4, h5, h6, h7,
         h8, h9, h10, h11, h12, h13, h14, h15,
         h16, h17, h18, h19, h20, h21, h22, h23
    FROM hr
   PIVOT (SUM(n) FOR hr IN (
         '00' AS h0,  '01' AS h1,  '02' AS h2,  '03' AS h3,
         '04' AS h4,  '05' AS h5,  '06' AS h6,  '07' AS h7,
         '08' AS h8,  '09' AS h9,  '10' AS h10, '11' AS h11,
         '12' AS h12, '13' AS h13, '14' AS h14, '15' AS h15,
         '16' AS h16, '17' AS h17, '18' AS h18, '19' AS h19,
         '20' AS h20, '21' AS h21, '22' AS h22, '23' AS h23))
)
SELECT p.dt AS "Date",
       p.dy AS "Day",
       TO_CHAR(t.total_n) AS "Total",
       TO_CHAR(NVL(p.h0, 0)) AS "h0",
       TO_CHAR(NVL(p.h1, 0)) AS "h1",
       TO_CHAR(NVL(p.h2, 0)) AS "h2",
       TO_CHAR(NVL(p.h3, 0)) AS "h3",
       TO_CHAR(NVL(p.h4, 0)) AS "h4",
       TO_CHAR(NVL(p.h5, 0)) AS "h5",
       TO_CHAR(NVL(p.h6, 0)) AS "h6",
       TO_CHAR(NVL(p.h7, 0)) AS "h7",
       TO_CHAR(NVL(p.h8, 0)) AS "h8",
       TO_CHAR(NVL(p.h9, 0)) AS "h9",
       TO_CHAR(NVL(p.h10, 0)) AS "h10",
       TO_CHAR(NVL(p.h11, 0)) AS "h11",
       TO_CHAR(NVL(p.h12, 0)) AS "h12",
       TO_CHAR(NVL(p.h13, 0)) AS "h13",
       TO_CHAR(NVL(p.h14, 0)) AS "h14",
       TO_CHAR(NVL(p.h15, 0)) AS "h15",
       TO_CHAR(NVL(p.h16, 0)) AS "h16",
       TO_CHAR(NVL(p.h17, 0)) AS "h17",
       TO_CHAR(NVL(p.h18, 0)) AS "h18",
       TO_CHAR(NVL(p.h19, 0)) AS "h19",
       TO_CHAR(NVL(p.h20, 0)) AS "h20",
       TO_CHAR(NVL(p.h21, 0)) AS "h21",
       TO_CHAR(NVL(p.h22, 0)) AS "h22",
       TO_CHAR(NVL(p.h23, 0)) AS "h23",
       RTRIM(RTRIM(TO_CHAR(ROUND(t.total_n / 24, 2), 'FM990.00'), '0'), '.') AS "Avg"
  FROM piv p
  JOIN day_tot t ON p.dt = t.dt AND p.dy = t.dy
 ORDER BY 1;
