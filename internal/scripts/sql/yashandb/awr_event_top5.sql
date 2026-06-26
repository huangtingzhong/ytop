-- File Name: awr_event_top5.sql
-- Purpose: YashanDB Show top 5 wait events from AWR
-- Created: 20260516  by  huangtingzhong

-- Mapping: DBA_HIST_SNAPSHOT -> WRM$_SNAPSHOT; system events via WRH$_SYSTEM_EVENT
-- yasql has no SET LINES; wide pivot via DBMS_OUTPUT (see awr_top_sql_last_day.sql).

SET SERVEROUTPUT ON

DECLARE
  v_line VARCHAR2(4000);

  PROCEDURE put_line(s VARCHAR2) IS
    v_max NUMBER := 4000;
    v_off NUMBER := 1;
    v_len NUMBER;
  BEGIN
    IF s IS NULL THEN DBMS_OUTPUT.PUT_LINE(''); RETURN; END IF;
    v_len := LENGTH(s);
    WHILE v_off <= v_len LOOP
      DBMS_OUTPUT.PUT_LINE(SUBSTR(s, v_off, v_max));
      v_off := v_off + v_max;
    END LOOP;
  END;

BEGIN
  put_line(RPAD('SNAP_TIME', 12) || ' ' ||
           RPAD('EVENT1', 25) || ' ' ||
           LPAD('AAS1', 6) || ' ' ||
           LPAD('RATIO1', 7) || ' ' ||
           LPAD('AVG_T1', 6) || ' ' ||
           RPAD('EVENT2', 25) || ' ' ||
           LPAD('AAS2', 6) || ' ' ||
           LPAD('RATIO2', 7) || ' ' ||
           LPAD('AVG_T2', 6) || ' ' ||
           RPAD('EVENT3', 20) || ' ' ||
           LPAD('AAS3', 6) || ' ' ||
           LPAD('RATIO3', 7) || ' ' ||
           LPAD('AVG_T3', 6) || ' ' ||
           RPAD('EVENT4', 20) || ' ' ||
           LPAD('AAS4', 6) || ' ' ||
           LPAD('RATIO4', 7) || ' ' ||
           LPAD('AVG_T4', 6));
  put_line(RPAD('-', 12, '-') || ' ' ||
           RPAD('-', 25, '-') || ' ' ||
           RPAD('-', 6, '-') || ' ' ||
           RPAD('-', 7, '-') || ' ' ||
           RPAD('-', 6, '-') || ' ' ||
           RPAD('-', 25, '-') || ' ' ||
           RPAD('-', 6, '-') || ' ' ||
           RPAD('-', 7, '-') || ' ' ||
           RPAD('-', 6, '-') || ' ' ||
           RPAD('-', 20, '-') || ' ' ||
           RPAD('-', 6, '-') || ' ' ||
           RPAD('-', 7, '-') || ' ' ||
           RPAD('-', 6, '-') || ' ' ||
           RPAD('-', 20, '-') || ' ' ||
           RPAD('-', 6, '-') || ' ' ||
           RPAD('-', 7, '-') || ' ' ||
           RPAD('-', 6, '-'));

  FOR r IN (
    WITH
    delta_base AS (
      SELECT
        SA.END_INTERVAL_TIME AS SNAP_TIME,
        SB.END_INTERVAL_TIME AS NEXT_SNAP_TIME,
        V.EVENT,
        (BB.TIME_WAITED_MICRO - AA.TIME_WAITED_MICRO) / 1000000.0 AS TIME_WAITED,
        (BB.TOTAL_WAITS - AA.TOTAL_WAITS) AS TOTAL_WAITS,
        EXTRACT(DAY FROM (SB.END_INTERVAL_TIME - SA.END_INTERVAL_TIME)) * 86400
          + EXTRACT(HOUR FROM (SB.END_INTERVAL_TIME - SA.END_INTERVAL_TIME)) * 3600
          + EXTRACT(MINUTE FROM (SB.END_INTERVAL_TIME - SA.END_INTERVAL_TIME)) * 60
          + EXTRACT(SECOND FROM (SB.END_INTERVAL_TIME - SA.END_INTERVAL_TIME)) AS interval_sec
      FROM SYS.WRH$_SYSTEM_EVENT AA
      JOIN SYS.WRM$_SNAPSHOT SA ON AA.SNAP_ID = SA.SNAP_ID AND AA.INSTANCE_NUMBER = SA.INSTANCE_NUMBER
      JOIN SYS.WRH$_SYSTEM_EVENT BB ON AA.EVENT_ID = BB.EVENT_ID AND AA.INSTANCE_NUMBER = BB.INSTANCE_NUMBER AND BB.SNAP_ID = AA.SNAP_ID + 1
      JOIN SYS.WRM$_SNAPSHOT SB ON BB.SNAP_ID = SB.SNAP_ID AND BB.INSTANCE_NUMBER = SB.INSTANCE_NUMBER
      JOIN V$SYSTEM_EVENT V ON AA.EVENT_ID = V.EVENT_ID
      WHERE AA.INSTANCE_NUMBER = (SELECT INSTANCE_NUMBER FROM V$INSTANCE)
        AND V.WAIT_CLASS <> 'Idle'
    ),
    with_total AS (
      SELECT SNAP_TIME, NEXT_SNAP_TIME, EVENT, TIME_WAITED, TOTAL_WAITS, interval_sec,
             SUM(TIME_WAITED) OVER (PARTITION BY SNAP_TIME) AS total_time_waited,
             ROW_NUMBER() OVER (PARTITION BY SNAP_TIME ORDER BY TIME_WAITED DESC) AS RN
      FROM delta_base
      WHERE interval_sec > 0
    ),
    top5 AS (
      SELECT
        TO_CHAR(SNAP_TIME, 'mmdd hh24:mi') AS snap_time,
        EVENT,
        TIME_WAITED,
        ROUND(TIME_WAITED / NULLIF(interval_sec, 0), 2) AS AAS,
        ROUND(TIME_WAITED * 100 / NULLIF(total_time_waited, 0), 2) AS RATIO,
        CASE
          WHEN TOTAL_WAITS = 0 OR TOTAL_WAITS IS NULL THEN NULL
          WHEN (TIME_WAITED * 1000 / TOTAL_WAITS) < 1000 THEN TO_CHAR(ROUND(TIME_WAITED * 1000 / TOTAL_WAITS, 0))
          WHEN (TIME_WAITED * 1000 / TOTAL_WAITS) BETWEEN 1000 AND 1000000 THEN ROUND(TIME_WAITED * 1000 / TOTAL_WAITS / 1000, 1) || 'S'
          ELSE ROUND(TIME_WAITED * 1000 / TOTAL_WAITS / 1000 / 60, 0) || 'M'
        END AS avg_time,
        RN
      FROM with_total
      WHERE RN <= 5
    ),
    pivot_top5 AS (
      SELECT snap_time, RN,
        EVENT AS event1, AAS AS aas1, RATIO AS ratio1, avg_time AS avg_time1,
        LEAD(EVENT, 1) OVER (PARTITION BY snap_time ORDER BY RN) AS event2,
        LEAD(AAS, 1) OVER (PARTITION BY snap_time ORDER BY RN) AS aas2,
        LEAD(RATIO, 1) OVER (PARTITION BY snap_time ORDER BY RN) AS ratio2,
        LEAD(avg_time, 1) OVER (PARTITION BY snap_time ORDER BY RN) AS avg_time2,
        LEAD(EVENT, 2) OVER (PARTITION BY snap_time ORDER BY RN) AS event3,
        LEAD(AAS, 2) OVER (PARTITION BY snap_time ORDER BY RN) AS aas3,
        LEAD(RATIO, 2) OVER (PARTITION BY snap_time ORDER BY RN) AS ratio3,
        LEAD(avg_time, 2) OVER (PARTITION BY snap_time ORDER BY RN) AS avg_time3,
        LEAD(EVENT, 3) OVER (PARTITION BY snap_time ORDER BY RN) AS event4,
        LEAD(AAS, 3) OVER (PARTITION BY snap_time ORDER BY RN) AS aas4,
        LEAD(RATIO, 3) OVER (PARTITION BY snap_time ORDER BY RN) AS ratio4,
        LEAD(avg_time, 3) OVER (PARTITION BY snap_time ORDER BY RN) AS avg_time4
      FROM top5
    )
    SELECT snap_time, event1, aas1, ratio1, avg_time1,
           event2, aas2, ratio2, avg_time2,
           event3, aas3, ratio3, avg_time3,
           event4, aas4, ratio4, avg_time4
    FROM pivot_top5
    WHERE RN = 1
    ORDER BY snap_time
  ) LOOP
    v_line :=
      RPAD(NVL(r.snap_time, ' '), 12) || ' ' ||
      RPAD(SUBSTR(NVL(r.event1, ' '), 1, 25), 25) || ' ' ||
      LPAD(NVL(TO_CHAR(r.aas1), ' '), 6) || ' ' ||
      LPAD(NVL(TO_CHAR(r.ratio1), ' '), 7) || ' ' ||
      LPAD(SUBSTR(NVL(r.avg_time1, ' '), 1, 6), 6) || ' ' ||
      RPAD(SUBSTR(NVL(r.event2, ' '), 1, 25), 25) || ' ' ||
      LPAD(NVL(TO_CHAR(r.aas2), ' '), 6) || ' ' ||
      LPAD(NVL(TO_CHAR(r.ratio2), ' '), 7) || ' ' ||
      LPAD(SUBSTR(NVL(r.avg_time2, ' '), 1, 6), 6) || ' ' ||
      RPAD(SUBSTR(NVL(r.event3, ' '), 1, 20), 20) || ' ' ||
      LPAD(NVL(TO_CHAR(r.aas3), ' '), 6) || ' ' ||
      LPAD(NVL(TO_CHAR(r.ratio3), ' '), 7) || ' ' ||
      LPAD(SUBSTR(NVL(r.avg_time3, ' '), 1, 6), 6) || ' ' ||
      RPAD(SUBSTR(NVL(r.event4, ' '), 1, 20), 20) || ' ' ||
      LPAD(NVL(TO_CHAR(r.aas4), ' '), 6) || ' ' ||
      LPAD(NVL(TO_CHAR(r.ratio4), ' '), 7) || ' ' ||
      LPAD(SUBSTR(NVL(r.avg_time4, ' '), 1, 6), 6);
    put_line(v_line);
  END LOOP;
END;
/
